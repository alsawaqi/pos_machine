import '../tenancy/business_identity.dart';
import '../tenancy/device_heartbeat.dart';
import '../services/server_receipt_history.dart';
import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../services/display_strings.dart';
import '../services/kitchen_ticket.dart';
import '../services/local_order_storage_service.dart';
import '../services/mosambee_payment_service.dart';
import '../core/authorization.dart';
import '../core/permissions.dart';
import '../core/training_flag.dart' show TrainingOrderStore;
import '../services/order_sync_payload.dart'
    show orderAuthorizationTargets, uuidV4;
import '../services/pricing_adapter.dart' as machine_pricing;
import '../services/presentation_service.dart';
import '../services/sunmi_receipt_service.dart';
import '../services/table_action_deadline.dart';

/// The cashier's resolution of an unconfirmed card charge (the "Card charge not
/// confirmed" prompt): cancel/abort the charge, force-record it as pending
/// reconciliation, or retry by re-launching the payment terminal.
enum PendingReconChoice { cancel, record, retry }

/// Outcome of a (possibly retried) card charge attempt.
enum _CardChargeOutcome { success, recordPending, aborted }

abstract class DiningTableSyncHooks {
  void onTableOccupied(DiningTableSession s);
  void onTableDraftPersisted(DiningTableSession s);
  void onTableLeft(String tableId);
  void onTableTransferred(String fromId, DiningTableSession moved);
  void onTablesJoined(DiningTableSession head, DiningTableSession seat);
  void onTablesCleared(Set<String> groupIds, DiningTableSession? head);
  FutureOr<void> onTablePaid(DiningTableSession paid, OrderSnapshot snapshot);
}

class CustomerActionTag {
  const CustomerActionTag(this.generation, this.sequence);
  final int generation;
  final int sequence;
}

/// Monetary values used by one payment-page render, in integer baisas.
/// Background price readers must never replace this cashier-facing quote.
class PaymentPageAmounts {
  const PaymentPageAmounts({
    required this.total,
    required this.due,
    required this.tendered,
    required this.change,
    required this.cardRemainder,
  });
  final int total;
  final int due;
  final int tendered;
  final int change;
  final int cardRemainder;
  bool get isMixed => tendered > 0 && tendered < due;
}

class PosController extends ChangeNotifier
    implements machine_pricing.MachinePricingState {
  final _businessIdentity = BusinessBoundary.current?.toJson();
  static const Duration _rearDisplaySyncDebounceDuration = Duration(
    milliseconds: 250,
  );
  static const Duration _diningTablePersistDebounceDuration = Duration(
    milliseconds: 120,
  );

  final PresentationService _presentation = PresentationService.instance;
  final MosambeePaymentService _paymentBridge;
  final OrderStorageService? _orderStorageOverride;
  OrderStorageService get _orderStorage =>
      _orderStorageOverride ?? LocalOrderStorageService.instance;
  DraftRecoveryGuard? _observedRecoveryGuard;
  void _refreshStorageAfterActivation() {
    _observedRecoveryGuard?.recoveryBlocked.removeListener(_notifySafely);
    _observedRecoveryGuard = _recoveryGuard;
    _observedRecoveryGuard?.recoveryBlocked.addListener(_notifySafely);
    unawaited(
      _observedRecoveryGuard?.refreshRecoveryGuard().catchError(
            (Object _) {},
          ) ??
          Future.value(),
    );
  }

  final pricing.PriceResult Function(pricing.PricingInput) _priceOrder;

  /// Gap sweep G1 — injectable wall clock for the daily availability windows
  /// (tests pin it; production keeps the default).
  DateTime Function() clock = DateTime.now;

  DiningTableSyncHooks? diningTableSyncHooks;

  /// T6 owner-approved eligibility seam; no change to card charge arithmetic.
  bool Function()? isLiveSharedTable;
  Future<bool> Function(OrderSnapshot)? onDiningTableFinalRound;

  /// Live table tenders must be authorised before cash, native launch or print.
  Future<String?> Function()? verifyDiningTableTender;
  Future<Map<String, dynamic>> Function(double? cashTendered)?
  prepareDiningTableTender;
  int? Function()? liveDiningTotal;
  Map<String, dynamic>? _reservedDiningBill;
  final Map<String, String> _diningHookOccupancies = {};
  String? _activeDiningTableSeatingKey;

  String get activeDiningTableBillUuid => _activeServerOrderUuid ?? '';

  int _orderGeneration = 0;
  int _customerActionSequence = 0;
  final Set<CustomerActionTag> _pendingCustomerLookups = {};
  CustomerActionTag? _restoreCustomerLookup;
  CustomerActionTag? _detailsCustomerLookup;
  int? _detailsCustomerId;
  int _tableTransitionDepth = 0;
  int get orderGeneration => _orderGeneration;
  CustomerActionTag get customerActionTag =>
      CustomerActionTag(_orderGeneration, _customerActionSequence);
  bool get tableTransitionInProgress => _tableTransitionDepth > 0;
  bool get customerLookupPending => _pendingCustomerLookups.any(
    (tag) =>
        tag.generation == _orderGeneration &&
        tag.sequence == _customerActionSequence,
  );
  bool get customerTenderStarted =>
      isProcessingPayment ||
      showCharityRoundUpPrompt ||
      showPaymentLaunchOverlay;
  Future<({CustomerSearchResult? customer, bool deleted})> Function(int id)?
  refreshRestoredCustomer;

  String get customerLookupMessage => _l10n.localeName.startsWith('ar')
      ? 'جارٍ البحث عن العميل — انتظر قليلاً ثم ادفع مرة أخرى'
      : 'Customer lookup in progress — wait a moment, then pay again';
  String get tableTransitionMessage => _l10n.localeName.startsWith('ar')
      ? 'ما زال حفظ الطاولة جارياً — انتظر قليلاً ثم حاول مرة أخرى'
      : 'The table is still being saved — wait a moment, then try again';
  String get splitIdentityMessage => _l10n.localeName.startsWith('ar')
      ? 'تم دفع جزء من هذه الفاتورة — لا يمكن تغيير العميل أو الخصم الآن'
      : 'Part of this bill is already paid — the customer and discount can no longer change';
  String get giftRedemptionMessage => _l10n.localeName.startsWith('ar')
      ? 'أزل استبدال نقاط الولاء قبل إهداء الطلب'
      : 'Remove the loyalty redemption before gifting the order';

  void _identityNotice(String message) {
    lastPaymentMessage = message;
    displayNote = message;
    onDraftRedemptionCleared?.call(message);
    _notifySafely();
  }

  void _advanceOrderGeneration() {
    _orderGeneration++;
    _displayedPaymentAmounts = null;
    _pendingCustomerLookups.clear();
  }

  CustomerActionTag? beginCustomerAction({
    bool lookup = false,
    int? detailsCustomerId,
  }) {
    if (customerTenderStarted) return null;
    if (!_cartMutationAllowed()) return null;
    final tag = CustomerActionTag(_orderGeneration, ++_customerActionSequence);
    _pendingCustomerLookups.clear();
    if (lookup) _pendingCustomerLookups.add(tag);
    if (detailsCustomerId != null) {
      _detailsCustomerLookup = tag;
      _detailsCustomerId = detailsCustomerId;
    }
    _notifySafely();
    return tag;
  }

  bool customerActionCurrent(CustomerActionTag tag) =>
      !_isDisposed &&
      tag.generation == _orderGeneration &&
      tag.sequence == _customerActionSequence &&
      !customerTenderStarted;

  void markCustomerLookup(CustomerActionTag tag) {
    if (customerActionCurrent(tag)) {
      _pendingCustomerLookups.add(tag);
      _notifySafely();
    }
  }

  void endCustomerLookup(CustomerActionTag tag) {
    _pendingCustomerLookups.remove(tag);
    if (identical(_restoreCustomerLookup, tag)) _restoreCustomerLookup = null;
    if (!_isDisposed &&
        tag.generation == _orderGeneration &&
        !customerTenderStarted &&
        !tableTransitionInProgress &&
        !recoveryBlocked) {
      maybeAutoApplyOrderDiscount();
    }
    _notifySafely();
  }

  bool get restoredCustomerLookupPending =>
      _restoreCustomerLookup != null &&
      customerActionCurrent(_restoreCustomerLookup!) &&
      _pendingCustomerLookups.contains(_restoreCustomerLookup);

  bool allowCustomerControl({bool refuseLookup = false}) {
    if (customerTenderStarted || !_cartMutationAllowed()) return false;
    if (refuseLookup && customerLookupPending) {
      _identityNotice(customerLookupMessage);
      return false;
    }
    return true;
  }

  bool isSameCustomerNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final customer = selectedCustomer;
    return customer != null &&
        digits.isNotEmpty &&
        (digits == customer.phone.replaceAll(RegExp(r'\D'), '') ||
            digits == customerReferenceNumber);
  }

  bool get attachedCustomerCheckPending =>
      restoredCustomerLookupPending ||
      (_detailsCustomerLookup != null &&
          _detailsCustomerId == selectedCustomer?.id &&
          customerActionCurrent(_detailsCustomerLookup!) &&
          _pendingCustomerLookups.contains(_detailsCustomerLookup));

  bool keepsAttachedCustomerCheck(String value) =>
      selectedCustomer != null &&
      attachedCustomerCheckPending &&
      (value.trim().isEmpty || isSameCustomerNumber(value));

  bool confirmSameCustomerNumber() {
    if (!allowCustomerControl()) return false;
    // Keyboard Done cannot discard an authoritative check of this customer.
    // A different-id Details/search reply can still be superseded.
    if (!attachedCustomerCheckPending) cancelCustomerLookups();
    _notifySafely();
    return true;
  }

  void detachMissingCustomer() {
    selectedCustomer = null;
    selectedEarnRuleIds = null;
    customerReferenceNumber = '';
    vehiclePlateNumber = '';
    if (_hasLoyaltyRedemption) discount = const DiscountConfiguration();
    _clearLoyaltyRedemption();
    _resetCharityRoundUp();
    _identityNotice(
      _l10n.localeName.startsWith('ar')
          ? 'هذا العميل لم يعد موجوداً — تمت إزالة العميل وأي استبدال لنقاط الولاء'
          : 'This customer no longer exists — the customer and any loyalty redemption were removed',
    );
    _broadcast();
  }

  void cancelCustomerLookups() {
    _customerActionSequence++;
    _pendingCustomerLookups.clear();
  }

  bool _identityMutationAllowed({bool money = false}) {
    if (customerTenderStarted) return false;
    if (!_cartMutationAllowed()) return false;
    if (hasRecordedSplitPayments) {
      _identityNotice(splitIdentityMessage);
      return false;
    }
    if (money && customerLookupPending) {
      _identityNotice(customerLookupMessage);
      return false;
    }
    return true;
  }

  bool allowLoyaltyDialog() => _identityMutationAllowed(money: true);

  PaymentPageAmounts? _displayedPaymentAmounts;

  PaymentPageAmounts _paymentPageAmounts(double tendered) {
    final due = pricing.omrToBaisas(activePaymentBaseTotal);
    final cash = pricing.omrToBaisas(tendered);
    return PaymentPageAmounts(
      total: pricing.omrToBaisas(total),
      due: due,
      tendered: cash,
      change: cash > due ? cash - due : 0,
      cardRemainder: due > cash ? due - cash : 0,
    );
  }

  /// Called only by the payment page as it builds the displayed values.
  /// Does not notify listeners. Snapshot/config/rear-display reads cannot
  /// replace this quote; only the next actual payment-page render does so.
  PaymentPageAmounts recordPaymentPageAmounts(double tendered) =>
      _displayedPaymentAmounts = _paymentPageAmounts(tendered);

  String? customerTenderRefusal({bool gift = false}) {
    // LAUNCH-P4 H4/C5 — the menu rules (a required add-on choice, a product
    // not sold on this channel) refuse a tender BEFORE it starts; never once
    // money has been taken.
    if (!customerTenderStarted && !hasRecordedSplitPayments) {
      final menu = menuTenderRefusal();
      if (menu != null) {
        _identityNotice(menu);
        return menu;
      }
    }
    final message = gift && _hasLoyaltyRedemption
        ? giftRedemptionMessage
        : customerLookupPending
        ? customerLookupMessage
        : tableTransitionInProgress
        ? tableTransitionMessage
        : null;
    if (message != null) {
      _identityNotice(message);
      return message;
    }
    // Leave an inconsistent redemption untouched for the existing tender
    // ownership guard. Repricing must not erase its evidence or move that
    // refusal ahead of the normal delivery-details dialog.
    if (_hasLoyaltyRedemption && !_loyaltyRedemptionConsistent) return null;
    // Reprice only before a tender starts; a changed total requires another tap.
    if (!customerTenderStarted &&
        !recoveryBlocked &&
        !hasRecordedSplitPayments) {
      // A local counter quote cannot price a canonical live-table bill.
      // That path keeps its existing server snapshot/claim verification below.
      final displayed = isLiveSharedTable?.call() == true
          ? null
          : _displayedPaymentAmounts;
      final before = displayed?.total;
      _invalidatePriceCache();
      maybeAutoApplyOrderDiscount();
      final fresh = _paymentPageAmounts((displayed?.tendered ?? 0) / 1000);
      if (before != null &&
          (fresh.total != before ||
              fresh.due != displayed!.due ||
              fresh.change != displayed.change ||
              fresh.cardRemainder != displayed.cardRemainder)) {
        final changed = _l10n.localeName.startsWith('ar')
            ? 'تم تحديث الإجمالي بعد تطبيق الخصم — راجع المبلغ ثم ادفع مرة أخرى'
            : 'The discount updated the total — check the amount, then pay again';
        _identityNotice(changed);
        return changed;
      }
    }
    return null;
  }

  Future<T> _duringTableTransition<T>(Future<T> Function() action) async {
    _tableTransitionDepth++;
    _notifySafely();
    try {
      return await action();
    } finally {
      _tableTransitionDepth--;
      _notifySafely();
    }
  }

  void _refreshDraftCustomer() {
    final id = selectedCustomer?.id;
    final refresh = refreshRestoredCustomer;
    if (id == null || refresh == null || isLiveSharedTable?.call() == true) {
      return;
    }
    final tag = CustomerActionTag(_orderGeneration, ++_customerActionSequence);
    _pendingCustomerLookups.add(tag);
    _restoreCustomerLookup = tag;
    unawaited(() async {
      try {
        final result = await refresh(id).timeout(const Duration(seconds: 3));
        if (!customerActionCurrent(tag) || selectedCustomer?.id != id) return;
        if (result.deleted) {
          detachMissingCustomer();
        } else if (result.customer?.id == id) {
          selectedCustomer = result.customer;
          customerReferenceNumber = result.customer!.phone
              .replaceAll(RegExp(r'\D'), '')
              .trim();
          _broadcast();
        }
      } catch (_) {
        // Offline, timeout or an unreadable response keeps the saved identity.
      } finally {
        endCustomerLookup(tag);
      }
    }());
  }

  DraftRecoveryGuard? get _recoveryGuard => _orderStorage is DraftRecoveryGuard
      ? _orderStorage as DraftRecoveryGuard
      : null;
  bool get recoveryBlocked => _recoveryGuard?.recoveryBlocked.value ?? false;
  bool _cartMutationAllowed({bool insideTableTransition = false}) {
    if (tableTransitionInProgress && !insideTableTransition) {
      _identityNotice(tableTransitionMessage);
      return false;
    }
    if (!recoveryBlocked) return true;
    lastPaymentMessage = _l10n.localeName.startsWith('ar')
        ? 'أكمل استعادة مسودة الفاتورة المحفوظة في قسم داخل المطعم أولاً.'
        : 'Finish the saved bill draft recovery in Dine-In first.';
    displayNote = lastPaymentMessage;
    _notifySafely();
    return false;
  }

  Future<bool> _draftAllowed({
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  }) async {
    try {
      await _tablePhase('draft_guard', () async {
        await _recoveryGuard?.assertDraftNotRetired(
          uuid: uuid,
          tableId: tableId,
          reference: reference,
          occupiedAt: occupiedAt,
          seatingKey: seatingKey,
        );
      });
      return true;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      lastPaymentMessage =
          'This local bill was archived. Use its canonical Dine-In bill.';
      displayNote = lastPaymentMessage;
      _notifySafely();
      return false;
    }
  }

  void forgetRecoveredOccupancy(
    String tableId,
    String reference,
    String? occupiedAt,
  ) {
    if (occupiedAt != null &&
        _diningHookOccupancies[tableId] ==
            '$reference|${DateTime.parse(occupiedAt)}') {
      _diningHookOccupancies.remove(tableId);
    }
  }

  Future<void> assertIdleForCombine() async {
    if (_diningTablePersistTimer != null ||
        cart.isNotEmpty ||
        isProcessingPayment ||
        hasRecordedSplitPayments) {
      throw StateError('Finish the active cart and pending table work first.');
    }
    await _diningTablePersistQueue;
    if (_diningTablePersistTimer != null ||
        cart.isNotEmpty ||
        isProcessingPayment ||
        hasRecordedSplitPayments) {
      throw StateError('Table work changed while checking.');
    }
  }

  Future<bool> _combineMutationAllowed({
    bool insideTableTransition = false,
  }) async {
    if (!_cartMutationAllowed(insideTableTransition: insideTableTransition)) {
      return false;
    }
    try {
      await _tablePhase('combine_check', _orderStorage.assertNoPendingCombine);
      return await _draftAllowed(
        uuid: _activeServerOrderUuid,
        tableId: activeDiningTableId,
        reference: currentOrderReference,
        occupiedAt: diningSessionFor(
          activeDiningTableId ?? '',
        )?.occupiedAt?.toIso8601String(),
        seatingKey: _activeDiningTableSeatingKey,
      );
    } on TimeoutException {
      rethrow;
    } catch (_) {
      lastPaymentMessage = _l10n.localeName.startsWith('ar')
          ? 'أكمل دمج الفواتير المعلق في قسم داخل المطعم أولاً.'
          : 'Finish the pending bill combine in Dine-In first.';
      displayNote = lastPaymentMessage;
      _notifySafely();
      return false;
    }
  }

  Future<void> assertNoPendingCombine() =>
      _orderStorage.assertNoPendingCombine();

  /// Owner-approved T6 correction: this device's initial proposal/ACK may
  /// bind the current bill without reopening or reloading the cashier's cart.
  bool bindDiningTableBillIdentity({
    required bool live,
    required String tableId,
    required String orderReference,
    required String seatingKey,
    required String expectedOrderUuid,
    required String orderUuid,
  }) {
    if (!live ||
        selectedOrderType != OrderType.dineIn ||
        activeDiningTableId != tableId ||
        currentOrderReference != orderReference ||
        orderUuid.isEmpty) {
      return false;
    }
    final currentSeating =
        _activeDiningTableSeatingKey ?? diningSessionFor(tableId)?.seatingKey;
    if (currentSeating != null && currentSeating != seatingKey) return false;
    final active = _activeServerOrderUuid ?? '';
    if (active == orderUuid) {
      _activeDiningTableSeatingKey = seatingKey;
      return true;
    }
    if (active != expectedOrderUuid) return false;
    _activeServerOrderUuid = orderUuid;
    _activeDiningTableSeatingKey = seatingKey;
    return true;
  }

  List<String> categories = const [
    'Coffee',
    'Drinks',
    'Food',
    'Dessert',
    'Bakery',
    'Special',
  ];

  List<Product> allProducts = const [
    Product(
      id: '1',
      name: 'Espresso',
      category: 'Coffee',
      price: 1.500,
      imageAsset: 'assets/images/espresso_blue.png',
      lowStock: true,
    ),
    Product(
      id: '2',
      name: 'Cappuccino',
      category: 'Coffee',
      price: 2.000,
      imageAsset: 'assets/images/cappuccino.png',
      lowStock: true,
    ),
    Product(
      id: '3',
      name: 'Latte',
      category: 'Coffee',
      price: 2.200,
      imageAsset: 'assets/images/latte.png',
      lowStock: true,
    ),
    Product(
      id: '4',
      name: 'Americano',
      category: 'Coffee',
      price: 1.800,
      imageAsset: 'assets/images/americano.png',
      lowStock: true,
    ),
    Product(
      id: '7',
      name: 'Mocha',
      category: 'Coffee',
      price: 2.300,
      imageAsset: 'assets/images/cappuccino.png',
      lowStock: true,
    ),
    Product(
      id: '8',
      name: 'Flat White',
      category: 'Coffee',
      price: 2.100,
      imageAsset: 'assets/images/latte.png',
      lowStock: true,
    ),
    Product(id: '5', name: 'Orange Juice', category: 'Drinks', price: 1.700),
    Product(id: '6', name: 'Brownie', category: 'Dessert', price: 1.600),
  ];

  List<DiningFloor> diningFloors = const [
    DiningFloor(id: 'main_hall', label: 'Main Hall'),
    DiningFloor(id: 'first_floor', label: 'First Floor'),
    DiningFloor(id: 'second_floor', label: 'Second Floor'),
  ];

  List<DiningTableDefinition> diningTableDefinitions = const [
    DiningTableDefinition(
      id: 'main_t1',
      floorId: 'main_hall',
      name: 'T1',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 1,
    ),
    DiningTableDefinition(
      id: 'main_t2',
      floorId: 'main_hall',
      name: 'T2',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 2,
    ),
    DiningTableDefinition(
      id: 'main_t3',
      floorId: 'main_hall',
      name: 'T3',
      sizeLabel: 'Large',
      seats: 8,
      sortOrder: 3,
    ),
    DiningTableDefinition(
      id: 'main_t4',
      floorId: 'main_hall',
      name: 'T4',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 4,
    ),
    DiningTableDefinition(
      id: 'main_c1',
      floorId: 'main_hall',
      name: 'C1',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 5,
    ),
    DiningTableDefinition(
      id: 'main_c2',
      floorId: 'main_hall',
      name: 'C2',
      sizeLabel: 'Standard',
      seats: 2,
      sortOrder: 6,
    ),
    DiningTableDefinition(
      id: 'main_t5',
      floorId: 'main_hall',
      name: 'T5',
      sizeLabel: 'Large',
      seats: 6,
      sortOrder: 7,
    ),
    DiningTableDefinition(
      id: 'first_f1',
      floorId: 'first_floor',
      name: 'F1',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 8,
    ),
    DiningTableDefinition(
      id: 'first_f2',
      floorId: 'first_floor',
      name: 'F2',
      sizeLabel: 'Booth',
      seats: 6,
      sortOrder: 9,
    ),
    DiningTableDefinition(
      id: 'first_f3',
      floorId: 'first_floor',
      name: 'F3',
      sizeLabel: 'Large',
      seats: 8,
      sortOrder: 10,
    ),
    DiningTableDefinition(
      id: 'first_f4',
      floorId: 'first_floor',
      name: 'F4',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 11,
    ),
    DiningTableDefinition(
      id: 'second_s1',
      floorId: 'second_floor',
      name: 'S1',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 12,
    ),
    DiningTableDefinition(
      id: 'second_s2',
      floorId: 'second_floor',
      name: 'S2',
      sizeLabel: 'Standard',
      seats: 4,
      sortOrder: 13,
    ),
    DiningTableDefinition(
      id: 'second_s3',
      floorId: 'second_floor',
      name: 'S3',
      sizeLabel: 'Large',
      seats: 8,
      sortOrder: 14,
    ),
    DiningTableDefinition(
      id: 'second_s4',
      floorId: 'second_floor',
      name: 'S4',
      sizeLabel: 'Booth',
      seats: 6,
      sortOrder: 15,
    ),
  ];

  /// Company add-on groups (each with its options) from the API config, set in
  /// [applyCatalog]. Products reference them by id (see [addonGroupsForProduct]).
  List<AddonGroup> addonGroups = const <AddonGroup>[];

  /// Company delivery providers (Talabat, Otlob, …) for the delivery picker.
  List<DeliveryProvider> deliveryProviders = const <DeliveryProvider>[];

  /// Company expense categories from the config (value = key, label = name) for
  /// the expense-log picker. Empty = use the screen's hardcoded const fallback.
  List<({String key, String name})> expenseCategories =
      const <({String key, String name})>[];

  /// The provider chosen for the current delivery order (null = none picked).
  int? selectedDeliveryProviderId;

  /// LAUNCH-P4 C2 — the branch name printed on receipts (from the config).
  String receiptBranchName = '';
  String receiptBranchNameAr = '';

  /// v2 #14 — staff positions the merchant allows to cancel an order at the POS
  /// (company policy from /device/config). Defaults to managers-only until a
  /// config sync populates it; see [positionCanCancelOrders].
  List<String> cancelOrderPositions = const <String>['manager'];

  /// P-F6 — staff positions allowed to open the branch Reports screen
  /// (`settings.reports_positions`). Managers-only until synced.
  List<String> reportsPositions = const <String>['manager'];

  /// P-G1 — staff positions allowed to open the Kitchen production screen
  /// (`settings.kitchen_positions`). Managers-only until synced.
  List<String> kitchenPositions = const <String>['manager'];

  /// P-F8 — the merchant's order-numbering config (disabled = device-local
  /// numbers only).
  OrderNumberingConfig orderNumbering = OrderNumberingConfig.disabled;

  /// P-F8 — the merchant's formatted sequential number for THIS order,
  /// allocated server-side at payment time ('' until then / offline).
  String receiptNumber = '';

  /// P-F8 — wired by the screen: asks pos_api for the next merchant order
  /// number. Null result = numbering disabled server-side; throws offline.
  Future<({int number, String formatted})?> Function()? allocateReceiptNumber;

  /// The branch's merchant-authored receipt template (from /device/config).
  /// Null = print the built-in default receipt. Passed to [SunmiReceiptService].
  ReceiptTemplate? receiptTemplate;

  /// Phase C4 — Arabic category display names keyed by the ENGLISH identity
  /// name (selectedCategory / product.category stay English). Display-only.
  Map<String, String> categoryNamesAr = const <String, String>{};

  /// The category label to SHOW for [arabic] UI.
  String categoryDisplayName(String name, bool arabic) =>
      arabic ? (categoryNamesAr[name] ?? name) : name;

  /// Phase B — company void reason codes (the cancel dialog requires one when
  /// any exist) + comp reasons (manager write-offs) + the category-level
  /// add-on group bindings unioned in [addonGroupsForProduct].
  List<VoidReasonRef> voidReasons = const <VoidReasonRef>[];
  List<CompReasonRef> compReasons = const <CompReasonRef>[];
  Map<int, List<int>> categoryAddonGroupIds = const <int, List<int>>{};

  /// Phase B — the manager comp applied to the current order (one at a time;
  /// the amount is DERIVED live — see [compAmount]). Null = no comp.
  @override
  AppliedComp? appliedComp;

  // ---------------------------------------------------------------------------
  // LAUNCH-P5 C3 — the approvals given while building THIS order. They are
  // signed into order.create's `authorizations` when the sale completes
  // (the order uuid and the final amounts are known only then) and the
  // approvers' keys are wiped. Never persisted: a held or restored cart
  // carries no approvals (the server then records them as missing).
  // ---------------------------------------------------------------------------
  final Map<String, ActionAuthorization> _orderAuthorizations = {};
  final Map<CartItem, ActionAuthorization> _giftAuthorizations =
      Map.identity();

  /// Slots: `discount`, `comp`, `loyalty`, `gift_tender`. Replaces any
  /// earlier approval of the slot; null clears it.
  void recordOrderAuthorization(String slot, ActionAuthorization? value) {
    final previous = _orderAuthorizations.remove(slot);
    if (previous != null && !identical(previous, value)) {
      previous.grant?.forget();
    }
    if (value != null) _orderAuthorizations[slot] = value;
  }

  ActionAuthorization? orderAuthorization(String slot) =>
      _orderAuthorizations[slot];

  /// The gift approval of one cart line.
  void recordGiftAuthorization(CartItem item, ActionAuthorization value) {
    _giftAuthorizations.remove(item)?.grant?.forget();
    _giftAuthorizations[item] = value;
  }

  void _forgetOrderAuthorizations() {
    for (final a in [
      ..._orderAuthorizations.values,
      ..._giftAuthorizations.values,
    ]) {
      a.grant?.forget();
    }
    _orderAuthorizations.clear();
    _giftAuthorizations.clear();
  }

  /// The tick list of the person ringing this sale, for the discount check
  /// at completion (wired by the screen).
  StaffPermissions Function()? staffPermissions;

  /// Who is ringing this sale: `(id, name)` (wired by the screen).
  ({int? id, String name}) Function()? currentActor;

  /// LAUNCH-P5 C3 — sign this sale's approvals over its uuid and its final
  /// order.create rows. A manual discount above the person's maximum with no
  /// approval still gets a `position` block, so the server records it.
  List<Map<String, dynamic>> signOrderAuthorizations(OrderSnapshot snapshot) {
    final uuid = snapshot.serverOrderUuid;
    final targets = orderAuthorizationTargets(snapshot);
    final blocks = <Map<String, dynamic>>[];
    final discountApproval = _orderAuthorizations['discount'];
    if (targets.orderDiscountBaisas > 0 && !isLoyaltyOwnedDiscount(discount)) {
      if (discountApproval != null) {
        blocks.add(
          discountApproval.block(
            subjectUuid: uuid,
            amountBaisas: targets.orderDiscountBaisas,
            ref: 'discount:0',
          ),
        );
      } else if (discount.discountId == null && staffPermissions != null) {
        final percent = discountPercentOf(
          discountAmount: targets.orderDiscountBaisas / 1000,
          subtotal: snapshot.rawSubtotal,
        );
        if (!staffPermissions!().can(
          'discount.manual',
          amountPercent: percent,
        )) {
          final actor = currentActor?.call();
          blocks.add(
            ActionAuthorization.position(
              action: 'discount.manual',
              actorStaffId: actor?.id,
              actorName: actor?.name ?? '',
            ).block(ref: 'discount:0'),
          );
        }
      }
    }
    final comp = _orderAuthorizations['comp'];
    for (final row in targets.comps) {
      if (!row.gift) {
        if (comp != null) {
          blocks.add(
            comp.block(
              subjectUuid: uuid,
              amountBaisas: row.amountBaisas,
              ref: row.ref,
            ),
          );
        }
        continue;
      }
      final line = row.lineIndex;
      final item = line != null && line >= 0 && line < _cart.length
          ? _cart[line]
          : null;
      final gift = item == null ? null : _giftAuthorizations[item];
      if (gift != null) {
        blocks.add(
          gift.block(
            subjectUuid: uuid,
            amountBaisas: row.amountBaisas,
            ref: row.ref,
          ),
        );
      }
    }
    final loyalty = _orderAuthorizations['loyalty'];
    if (loyalty != null && loyaltyRedeemRuleId != null) {
      blocks.add(loyalty.block(subjectUuid: uuid, ref: 'loyalty:0'));
    }
    final giftTender = _orderAuthorizations['gift_tender'];
    if (giftTender != null &&
        snapshot.paymentMethod.trim().toLowerCase() == 'gift') {
      // The whole-bill gift tender is payments[0] of order.pay; its block
      // rides in order.create, so its amount stays empty (Part A §6).
      blocks.add(giftTender.block(subjectUuid: uuid, ref: 'tender:0'));
    }
    _forgetOrderAuthorizations();
    return blocks;
  }

  /// Whether a staff member with [position] may cancel an order under the
  /// current company policy. Case-insensitive; an unknown / null position is
  /// denied. With no policy cached, the default managers-only list applies.
  bool positionCanCancelOrders(String? position) {
    final p = (position ?? '').trim().toLowerCase();
    if (p.isEmpty) return false;

    return cancelOrderPositions.any(
      (allowed) => allowed.trim().toLowerCase() == p,
    );
  }

  /// P-F6 — whether [position] may open the branch Reports screen.
  bool positionCanViewReports(String? position) {
    final p = (position ?? '').trim().toLowerCase();
    if (p.isEmpty) return false;
    return reportsPositions.any((allowed) => allowed.trim().toLowerCase() == p);
  }

  /// P-G1 — whether [position] may open the Kitchen production screen.
  bool positionCanUseKitchen(String? position) {
    final p = (position ?? '').trim().toLowerCase();
    if (p.isEmpty) return false;
    return kitchenPositions.any((allowed) => allowed.trim().toLowerCase() == p);
  }

  /// The unmodified catalog (base prices). [allProducts] is this list re-priced
  /// for the selected provider when the order type is delivery.
  List<Product> _baseProducts = const <Product>[];

  final List<CartItem> _cart = [];
  @override
  List<CartItem> get cart => List.unmodifiable(_cart);

  List<OrderHistoryRecord> orderHistory = const [];
  List<HeldOrderRecord> heldOrders = const [];
  List<DiningTableSession> diningTableSessions = const [];

  int currentOrderNumber = 1450;
  String currentOrderReference = '';
  int _nextOrderNumberSeed = 1451;

  String selectedCategory = 'Coffee';
  String productSearchQuery = '';
  String diningTableSearchQuery = '';
  String selectedDiningFloorId = 'main_hall';
  ProductViewMode productViewMode = ProductViewMode.grid;
  OrderType _selectedOrderType = OrderType.quickOrder;
  @override
  OrderType get selectedOrderType => _selectedOrderType;
  set selectedOrderType(OrderType value) {
    if (_selectedOrderType == value) return;
    _selectedOrderType = value;
    _invalidatePriceCache();
  }

  @override
  DiscountConfiguration discount = const DiscountConfiguration();

  // Session branch id, for auto-applying product/category-scope discounts to
  // cart lines (set by applyCatalog). Null = no branch context → no auto-apply.
  int? _discountBranchId;
  @override
  int? get pricingBranchId => _discountBranchId;

  /// Merchant discount rules from the cached catalog (from the API). The picker
  /// offers the currently-applicable order-scope ones.
  @override
  List<MerchantDiscount> availableDiscounts = const [];

  /// P-F9 — merchant offers (promotions) from the cached catalog. Auto types
  /// self-apply via the offer engine; bundles are cashier-picked.
  @override
  List<Offer> availableOffers = const [];

  /// Merchant loyalty rules from the cached catalog (stamp card / points).
  List<LoyaltyRule> loyaltyRules = const [];

  /// Cached customer slice (offline lookup / order attach).
  List<CustomerRef> cachedCustomers = const [];

  /// P-G6 — staff announcements from the cached catalog (newest first).
  List<StaffMessage> staffMessages = const [];

  /// Phase 3 — the advertising loop (ordered slides) for the customer screen,
  /// from the cached catalog. Pushed to the secondary display on its own
  /// channel so its continuous playback is independent of order updates.
  List<SliderSlide> adSlides = const [];
  // Reads recorded on THIS device but possibly not yet reflected in the
  // server receipts (the POST is best-effort; the next config sync heals
  // read_staff_ids). Keyed staffId → message ids, so one cashier opening
  // the sheet never silences another's badge.
  final Map<int, Set<int>> _localMessageReads = {};
  // The subset still awaiting a server ACK. Locally-read ids clear the
  // badge immediately, but stay HERE until a receipt POST succeeds — so a
  // failed/offline POST is retried on the next sheet open or reconnect
  // instead of being silently lost behind the local override.
  final Map<int, Set<int>> _pendingMessageReceipts = {};

  /// The announcements [staffId] should see: company/branch broadcasts plus
  /// the ones addressed to that staff member (catalog order = newest first).
  List<StaffMessage> visibleMessagesFor(int staffId) =>
      staffMessages.where((m) => m.visibleTo(staffId)).toList();

  /// Unread = visible, not in the server receipts, and not locally read.
  int unreadMessageCountFor(int staffId) {
    final local = _localMessageReads[staffId] ?? const <int>{};
    return staffMessages
        .where(
          (m) =>
              m.visibleTo(staffId) &&
              !m.isReadBy(staffId) &&
              !local.contains(m.id),
        )
        .length;
  }

  bool isMessageReadBy(StaffMessage m, int staffId) =>
      m.isReadBy(staffId) ||
      (_localMessageReads[staffId]?.contains(m.id) ?? false);

  /// Record local reads (the badge clears immediately; the receipt POST is
  /// fired separately and ACKed via [markMessageReceiptsAcked]).
  void markMessagesReadLocal(int staffId, Iterable<int> messageIds) {
    if (messageIds.isEmpty) return;
    final ids = messageIds.toSet();
    (_localMessageReads[staffId] ??= <int>{}).addAll(ids);
    (_pendingMessageReceipts[staffId] ??= <int>{}).addAll(ids);
    _broadcast();
  }

  /// Receipt ids still awaiting a successful POST for [staffId] — the
  /// batch to (re-)send whenever the sheet opens or connectivity returns.
  List<int> pendingMessageReceiptIds(int staffId) =>
      List<int>.unmodifiable(_pendingMessageReceipts[staffId] ?? const <int>{});

  /// The server accepted these receipts — stop retrying them.
  void markMessageReceiptsAcked(int staffId, Iterable<int> messageIds) {
    _pendingMessageReceipts[staffId]?.removeAll(messageIds.toSet());
  }

  /// The first active loyalty rule (kept for callers that want a single rule).
  LoyaltyRule? get activeEarnRule {
    for (final r in loyaltyRules) {
      if (r.isActive) return r;
    }
    return null;
  }

  /// v2 #3 — the ids of EVERY active earn rule. A merchant can run several earn
  /// programs at once (e.g. a stamp card AND points); the device names them all
  /// on the pay event (loyalty_rule_ids) so an identified customer accrues under
  /// each, not just the first.
  List<int> get activeEarnRuleIds =>
      loyaltyRules.where((r) => r.isActive).map((r) => r.id).toList();

  /// P-F3 — the earn program(s) the cashier/customer picked for THIS order
  /// (the picker shows on customer attach when several programs run at
  /// once). Null = no explicit choice → earn under every active rule, the
  /// longstanding default. Reset when the customer changes, detaches, or
  /// the order completes.
  List<int>? selectedEarnRuleIds;

  /// The earn-rule ids the pay event carries: the explicit choice clipped to
  /// the still-active rules, else all active rules.
  List<int> get effectiveEarnRuleIds {
    final chosen = selectedEarnRuleIds;
    if (chosen == null) return activeEarnRuleIds;
    final active = activeEarnRuleIds;
    return chosen.where(active.contains).toList();
  }

  bool setSelectedEarnRules(List<int> ruleIds) {
    if (!_identityMutationAllowed()) return false;
    selectedEarnRuleIds = List<int>.from(ruleIds);
    _broadcast();
    return true;
  }

  int splitCount = 1;
  final List<SplitPaymentRecord> _splitPayments = [];

  /// Custom per-guest base amounts (3dp OMR), length == [splitCount], set by
  /// the split dialog's customize mode. Null ⇒ equal shares. Transient: never
  /// persisted into drafts — a held order resumed mid-plan falls back to
  /// equal shares (the remainder rule still closes the legs to the total).
  List<double>? _splitPlanAmounts;

  /// [orderUpdateNonce] at the moment the plan was applied. Any cart addition
  /// afterwards bumps the nonce and inerts the plan — a swapped cart whose
  /// new total COINCIDES with the planned one must not resurrect old amounts.
  int _splitPlanNonce = 0;

  /// Soft POS evidence for the most recent single (non-split) card payment.
  /// Captured at completion and read synchronously by the order-push bridge
  /// before the next-order reset clears it. Split tenders carry their own
  /// evidence on each [SplitPaymentRecord] instead.
  CardCharge? _lastCardCharge;
  double? _activePaymentBaseOverride;
  String? activeDiningTableId;

  String paymentStatus = 'Waiting';
  String selectedPaymentMethod = 'Cash';
  // P-G7 — the Proceed-popup facts for the in-flight delivery order: the
  // PROVIDER's order number (required) + the driver's number (optional).
  // Set by completeDeliveryOrder just before the order finalizes; cleared
  // with the rest of the per-order state.
  String deliveryReference = '';
  String deliveryDriverPhone = '';
  // The provider FROZEN at the Proceed confirmation, captured BEFORE the
  // receipt-number await: a config refresh during that await can null
  // selectedDeliveryProviderId (provider deleted on the portal), and the
  // snapshot must still carry the provider the cashier actually punched —
  // otherwise the push would silently fall back to a tendered cash sale.
  int? _punchedDeliveryProviderId;
  String _punchedDeliveryProviderName = '';
  String lastCustomerEvent = '';
  String lastPaymentMessage = '';
  String displayNote = '';
  String paymentOverlayTitle = '';
  String customerReferenceNumber = '';
  String vehiclePlateNumber = '';

  /// A customer chosen from live search (with loyalty balances). When set, the
  /// order attaches by this customer's id (not the phone field) and loyalty
  /// earn/redeem use this customer.
  CustomerSearchResult? selectedCustomer;
  bool rearDisplayOpened = false;
  bool isProcessingPayment = false;
  bool isLoadingStorage = false;
  bool showCharityRoundUpPrompt = false;
  bool showPendingReconciliationPrompt = false;

  /// True once the unresolved-card-charge prompt has waited 2+ minutes with
  /// no answer. The UI escalates (danger banner) instead of a timer
  /// cancelling the money question — see [_promptForPendingReconciliation].
  bool pendingReconEscalated = false;
  bool showPaymentLaunchOverlay = false;
  bool charityRoundUpAccepted = false;
  double charityRoundUpAmount = 0;
  double charityRoundUpTotal = 0;
  String recentProductId = '';
  int orderUpdateNonce = 0;

  /// Invoked once with the completed order's snapshot the moment it is finalized
  /// (after the local save + receipt). The screen wires this to the order-push
  /// outbox so the order reaches pos_api. Fire-and-forget — it must never block
  /// or fail order completion.
  FutureOr<void> Function(OrderSnapshot snapshot)? onOrderCompleted;

  /// Whether the outbox already holds a durable row for this sale key. A
  /// live-table pay row is saved before its local journal step, so a failure
  /// after that point must not be reported as "not saved".
  Future<bool> Function(String key)? paidSaleDurable;
  String? Function()? canonicalDiningBillUuid;
  Future<OrderSnapshot> Function(OrderSnapshot)? refreshServerReceipt;

  /// Phase 3C — invoked for each advertising-slide play reported by the
  /// customer screen, carrying a ready-to-push `slider.display` sync event
  /// (client_event_id minted here). The screen wires this to a best-effort
  /// online telemetry push (→ pos_marketing_impressions). Fire-and-forget.
  void Function(Map<String, dynamic> event)? onSliderDisplay;

  /// Invoked when a finalized order consumed finite shelf stock — a map of
  /// {productId → quantity sold} for unit + cooked products only. The screen
  /// wires this to the Drift cache so the local shelf count survives an app
  /// restart (until the next /device/config sync brings the server's
  /// authoritative balance). Fire-and-forget; the in-memory catalog is already
  /// decremented before this fires. The count is informational — it never
  /// gates a sale (LAUNCH-P2 "sell, but warn").
  void Function(Map<int, double> soldByProductId)? onShelfStockConsumed;

  /// Phase G4 — invoked when a PRINT fails on real hardware (paper out,
  /// cover open, printer fault). jobKind ∈ {'receipt','kitchen','shift'}.
  /// Fire-and-forget: printing is fail-safe and never blocks a sale; this
  /// only lets the screen alert staff. Never fired on dev hardware (no
  /// printer plugin at all).
  void Function(String jobKind)? onPrintFailed;

  void _reportPrintFailure(String jobKind) {
    if (!SunmiReceiptService.printerPluginAvailable) return; // dev hardware
    onPrintFailed?.call(jobKind);
  }

  /// Phase C2 — invoked when an order is placed on hold (after the local save).
  /// The screen wires this to the hold-mirror outbox (order.hold) so the held
  /// order survives a device wipe and shows on the branch's other terminals.
  /// Fire-and-forget — holding never blocks on, or fails because of, the
  /// network.
  void Function(OrderSessionDraft draft)? onOrderHeld;

  /// Called after a successful cart edit invalidates and clears a manager comp.
  /// The screen surfaces the required operator notice; tests can observe the
  /// event without coupling controller state to a BuildContext.
  void Function()? onCompClearedAfterCartEdit;

  /// A saved legacy reward cannot be honored without its original debit.
  void Function(String message)? onDraftRedemptionCleared;

  /// Phase C2 — the server order uuid for the CURRENT cart, minted at hold
  /// time (and restored on resume) so hold → re-hold → completion → void all
  /// share one uuid. Null = this cart was never held.
  String? _activeServerOrderUuid;

  /// Invoked when a completed order is FULLY canceled — the screen wires this to
  /// the outbox so an `order.void` reaches pos_api (which unwinds the sale's
  /// inventory / loyalty / round-up / commission). Fire-and-forget; never blocks
  /// the local cancel. Carries the server order_uuid the order was pushed under.
  void Function(
    String orderUuid, {
    int? orderNumber,
    String? reason,
    int? voidReasonId,
    // LAUNCH-P5 C3 — the order.void_unpaid / order.void_paid gate result.
    ActionAuthorization? authorization,
  })?
  onOrderVoided;

  /// Phase C4 — resolves controller-authored user-facing messages in the
  /// device language without a BuildContext. Stored messages (lastPaymentMessage,
  /// displayNote) keep the language they were authored in until the next action.
  L10n Function()? localize;
  L10n get _l10n => localize?.call() ?? lookupL10n(const Locale('en'));

  /// Whether to print a Sunmi receipt on completion (driven by Settings; the
  /// screen keeps it in sync with the settings controller).
  bool printReceipts = true;

  /// Phase C1 — whether to print an items-only kitchen ticket on completion
  /// and on hold (blueprint §6.10). Driven by Settings like [printReceipts].
  bool printKitchenTickets = true;

  bool _presentationEnabled =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _isDisposed = false;
  Completer<bool?>? _charityRoundUpCompleter;
  Timer? _rearDisplaySyncTimer;
  bool _rearDisplaySyncInFlight = false;
  bool _rearDisplaySyncPending = false;
  bool _restoreRearDisplayAfterPayment = false;
  Timer? _diningTablePersistTimer;
  Future<void> _diningTablePersistQueue = Future<void>.value();
  int _activeCharityRoundUpPromptId = 0;
  bool _charityPromptCanceled = false;
  int _referenceSequence = 0;
  Completer<PendingReconChoice>? _pendingReconCompleter;
  Timer? _pendingReconEscalationTimer;
  double _pendingReconAmount = 0;

  bool _hasRealCatalog = false;
  final bool releaseBuild;

  PosController({
    this.releaseBuild = kReleaseMode,
    OrderStorageService? orderStorage,
    MosambeePaymentService? paymentBridge,
    pricing.PriceResult Function(pricing.PricingInput)? priceOrderOverride,
  }) : _paymentBridge = paymentBridge ?? MosambeePaymentService(),
       _orderStorageOverride = orderStorage ?? debugOrderStorageOverride,
       _priceOrder = priceOrderOverride ?? pricing.priceOrder {
    if (releaseBuild) {
      allProducts = [];
      categories = [];
      diningFloors = [];
      diningTableDefinitions = [];
    }
    _paymentBridge.setLaunchStateListener(_handlePaymentLaunchState);
    _observedRecoveryGuard = _recoveryGuard;
    _observedRecoveryGuard?.recoveryBlocked.addListener(_notifySafely);
    BusinessBoundary.activationCompleted.addListener(
      _refreshStorageAfterActivation,
    );
  }

  Future<void> init() async {
    _advanceOrderGeneration();
    await _loadStoredOrders();

    if (_presentationEnabled) {
      try {
        _presentation.listenFromCustomer((data) {
          if (data is! Map) return;

          final event = Map<String, dynamic>.from(data);
          if (event['type'] == 'charity_round_up_response') {
            final accepted = event['accepted'] == true;
            final promptId = (event['promptId'] as num?)?.toInt();
            debugPrint(
              'PosController received charity round-up response: accepted=$accepted promptId=$promptId activePromptId=$_activeCharityRoundUpPromptId',
            );
            _handleCharityRoundUpResponse(accepted, promptId: promptId);
            return;
          }

          if (event['type'] == 'customer_event') {
            lastCustomerEvent = event['message']?.toString() ?? '';
            _notifySafely();
            return;
          }

          // Phase 3C — an advertising slide finished on the customer screen.
          // Mint a sync event (stable client_event_id for idempotency) and hand
          // it to the screen's best-effort telemetry push.
          if (event['type'] == 'slider.display') {
            final nowIso = DateTime.now().toUtc().toIso8601String();
            onSliderDisplay?.call(<String, dynamic>{
              'client_event_id': uuidV4(),
              'event_type': 'slider.display',
              'client_timestamp': nowIso,
              'payload': <String, dynamic>{
                'slider_id': (event['slider_id'] as num?)?.toInt(),
                'slider_item_id': (event['slider_item_id'] as num?)?.toInt(),
                'content_asset_id': (event['content_asset_id'] as num?)
                    ?.toInt(),
                'advertiser_id': (event['advertiser_id'] as num?)?.toInt(),
                'duration_ms': (event['duration_ms'] as num?)?.toInt(),
                'played_at': nowIso,
              },
            });
            return;
          }
        });
        await syncRearDisplay();
      } on MissingPluginException {
        _presentationEnabled = false;
      } catch (_) {
        _presentationEnabled = false;
      }
    }

    _notifySafely();
  }

  /// Replace the in-memory catalog with branch-scoped data fetched from pos_api
  /// (mapped from the Drift cache). The existing UI reads these lists directly,
  /// so this bridge is all that is needed — no widget changes.
  void applyCatalog({
    required List<String> categories,
    Map<String, String> categoryNamesAr = const <String, String>{},
    required List<Product> products,
    required List<DiningFloor> floors,
    required List<DiningTableDefinition> tables,
    List<CompanyTax> taxes = const <CompanyTax>[],
    List<AddonGroup> addonGroups = const <AddonGroup>[],
    List<DeliveryProvider> deliveryProviders = const <DeliveryProvider>[],
    List<({String key, String name})> expenseCategories =
        const <({String key, String name})>[],
    List<MerchantDiscount> discounts = const <MerchantDiscount>[],
    List<Offer> offers = const <Offer>[],
    List<LoyaltyRule> loyaltyRules = const <LoyaltyRule>[],
    List<CustomerRef> customers = const <CustomerRef>[],
    List<String> cancelOrderPositions = const <String>['manager'],
    List<String> reportsPositions = const <String>['manager'],
    List<String> kitchenPositions = const <String>['manager'],
    OrderNumberingConfig orderNumbering = OrderNumberingConfig.disabled,
    ReceiptTemplate? receiptTemplate,
    List<VoidReasonRef> voidReasons = const <VoidReasonRef>[],
    List<CompReasonRef> compReasons = const <CompReasonRef>[],
    Map<int, List<int>> categoryAddonGroupIds = const <int, List<int>>{},
    List<StaffMessage> staffMessages = const <StaffMessage>[],
    List<SliderSlide> adSlides = const <SliderSlide>[],
    int? branchId,
    CompanyTaxSettings companyTax = CompanyTaxSettings.legacy,
    String branchName = '',
    String branchNameAr = '',
  }) {
    _hasRealCatalog = branchId != null;
    receiptBranchName = branchName;
    receiptBranchNameAr = branchNameAr;
    this.categories = categories;
    this.categoryNamesAr = categoryNamesAr;
    _baseProducts = products;
    diningFloors = floors;
    diningTableDefinitions = tables;
    this.addonGroups = addonGroups;
    this.deliveryProviders = deliveryProviders;
    this.expenseCategories = expenseCategories;
    availableDiscounts = discounts;
    availableOffers = offers;
    _discountBranchId = branchId;
    this.loyaltyRules = loyaltyRules;
    cachedCustomers = customers;
    this.cancelOrderPositions = cancelOrderPositions.isEmpty
        ? const <String>['manager']
        : cancelOrderPositions;
    this.reportsPositions = reportsPositions.isEmpty
        ? const <String>['manager']
        : reportsPositions;
    this.kitchenPositions = kitchenPositions.isEmpty
        ? const <String>['manager']
        : kitchenPositions;
    this.orderNumbering = orderNumbering;
    this.receiptTemplate = receiptTemplate;
    this.voidReasons = voidReasons;
    this.compReasons = compReasons;
    this.categoryAddonGroupIds = categoryAddonGroupIds;
    this.staffMessages = staffMessages;
    // Phase 3 — refresh the customer-screen ad loop and push it to the
    // secondary display (no-op off-device / when unchanged downstream).
    this.adSlides = adSlides;
    if (_presentationEnabled) {
      unawaited(_presentation.sendSlides(adSlides));
    }
    // Receipts that round-tripped (this till's POST landed, or another
    // till/restart recorded them) no longer need a retry.
    if (_pendingMessageReceipts.isNotEmpty) {
      final messagesById = {for (final m in staffMessages) m.id: m};
      for (final entry in _pendingMessageReceipts.entries) {
        entry.value.removeWhere(
          (id) => messagesById[id]?.isReadBy(entry.key) ?? false,
        );
      }
    }
    // Company taxes drive the cart tax lines + total. Stored in the shared
    // source so the persisted / printed order agrees with the live cart.
    // LAUNCH-P4 — with the merchant's VAT setup: an unregistered merchant
    // charges no tax at all; "prices include VAT" switches to inclusive.
    activeTaxSettings = companyTax;
    activeCompanyTaxes = companyTax.forbidsTax ? const <CompanyTax>[] : taxes;

    // Drop a selected provider that no longer exists in the refreshed catalog.
    if (selectedDeliveryProviderId != null &&
        !deliveryProviders.any((p) => p.id == selectedDeliveryProviderId)) {
      selectedDeliveryProviderId = null;
    }
    // Publish allProducts (re-priced for the active delivery provider, if any).
    _applyDeliveryPricing();

    // Keep the current selections valid against the new catalog.
    if (categories.isNotEmpty && !categories.contains(selectedCategory)) {
      selectedCategory = categories.first;
    }
    if (floors.isNotEmpty &&
        !floors.any((f) => f.id == selectedDiningFloorId)) {
      selectedDiningFloorId = floors.first.id;
    }
    _invalidatePriceCache();
    _notifySafely();
  }

  /// The provider chosen for the current delivery order, if any.
  DeliveryProvider? get selectedDeliveryProvider {
    final id = selectedDeliveryProviderId;
    if (id == null) return null;
    for (final p in deliveryProviders) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Pick a delivery provider — re-prices the menu + cart to that provider.
  void selectDeliveryProvider(int providerId) {
    if (!_cartMutationAllowed()) return;
    selectedDeliveryProviderId = providerId;
    _applyDeliveryPricing();
    _broadcast();
  }

  /// Recompute [allProducts] (and re-price open cart lines) for the current
  /// order context: delivery + a chosen provider ⇒ each product's resolved
  /// delivery price; otherwise the base price.
  void _applyDeliveryPricing() {
    _invalidatePriceCache();
    final base = _baseProducts.isEmpty ? allProducts : _baseProducts;
    final pid = selectedDeliveryProviderId;
    final isDelivery = selectedOrderType == OrderType.delivery && pid != null;

    allProducts = isDelivery
        ? base.map((p) => p.copyWith(price: p.deliveryPriceFor(pid))).toList()
        : List<Product>.from(base);

    // Re-price open cart lines from the base catalog by id, so a provider/
    // order-type change is reflected in items already in the cart.
    for (var i = 0; i < _cart.length; i++) {
      final item = _cart[i];
      final src = base.firstWhere(
        (p) => p.id == item.product.id,
        orElse: () => item.product,
      );
      final newPrice = isDelivery ? src.deliveryPriceFor(pid) : src.price;
      if (newPrice != item.product.price) {
        // LAUNCH-P4 C5 — keep EVERYTHING but the price: the gift flag, the
        // bundle instance and the combo components used to be dropped here.
        _cart[i] = item.withProduct(src.copyWith(price: newPrice));
      }
    }
  }

  /// The add-on groups assigned to [product], resolved against the company set.
  /// Looks the product up in the live catalog by id first, so a cart line
  /// restored from storage (whose Product copy may predate the catalog) still
  /// resolves its add-ons. Empty when the product has none or no catalog loaded.
  List<AddonGroup> addonGroupsForProduct(Product product) {
    if (addonGroups.isEmpty) return const <AddonGroup>[];
    final live = allProducts.firstWhere(
      (p) => p.id == product.id,
      orElse: () => product,
    );
    // LAUNCH-P4 — a combo carries no add-ons of its own (its items keep
    // theirs): not even the groups bound to its category, which would
    // otherwise make a combo in "coffee" ask for a coffee size at payment.
    if (live.isCombo || product.isCombo) return const <AddonGroup>[];
    final ownIds = live.addonGroupIds.isNotEmpty
        ? live.addonGroupIds
        : product.addonGroupIds;
    // Phase B — union the product's own groups with any bound to its
    // category ("attach a group to a category; the more specific binding
    // wins" — a duplicate id simply dedupes here).
    final categoryId = live.categoryId ?? product.categoryId;
    final categoryIds = categoryId != null
        ? (categoryAddonGroupIds[categoryId] ?? const <int>[])
        : const <int>[];
    final ids = <int>[
      ...ownIds,
      for (final id in categoryIds)
        if (!ownIds.contains(id)) id,
    ];
    if (ids.isEmpty) return const <AddonGroup>[];
    final byId = {for (final g in addonGroups) g.id: g};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  /// P-G3 — whether the add-on [option] can't be sold right now. Only an
  /// EXPLICIT absence counts: an option backed by a real product
  /// (linked_product_id) is unavailable when that product is missing from
  /// this branch's catalog (deleted, made internal, or switched off for
  /// this branch — the server leaves it out of the config).
  ///
  /// LAUNCH-P2 "sell, but warn": stock never gates an option — neither the
  /// linked product's cached shelf count nor the option's PD3b stock-usage
  /// lines. The server consumes them at sale time and lets the balance go
  /// negative; the manager sees the shortfall in the portal.
  bool isAddonOptionUnavailable(AddonOption option) {
    final linkedId = option.linkedProductId;
    if (linkedId == null) return false;
    final key = linkedId.toString();
    return !allProducts.any((p) => p.id == key);
  }

  /// Gap sweep G1 — whether [product] is outside its daily availability
  /// window right now (greyed-out / blocked).
  bool isOutsideHours(Product product) => !product.isAvailableAt(clock());

  /// A product can't be added to the cart when it is outside its daily
  /// window — the explicit availability the device evaluates itself (a
  /// product switched off for this branch never reaches the catalog). The
  /// tile gating + add-to-cart guards use this.
  ///
  /// LAUNCH-P2 "sell, but warn": cached stock never makes a product
  /// unorderable — not a low, zero, negative, missing or stale branch
  /// balance, for unit, cooked and recipe products alike.
  bool isUnorderable(Product product) =>
      isOutsideHours(product) ||
      !isSoldOnCurrentChannel(product) ||
      isSoldOut(product);

  /// LAUNCH-P4 C6 — this branch switched [product] off by hand ("sold out").
  /// Never driven by stock (owner decision 4).
  bool isSoldOut(Product product) => _liveProduct(product).soldOut;

  /// LAUNCH-P4 C6 — reflect a sold-out switch at once (the cached catalog
  /// re-emits the same flag shortly after).
  void markSoldOutLocally(String productId, bool soldOut) {
    _baseProducts = [
      for (final p in _baseProducts)
        p.id == productId ? p.copyWith(soldOut: soldOut) : p,
    ];
    _applyDeliveryPricing();
    _notifySafely();
  }

  /// LAUNCH-P4 C5 — whether [product] is offered on the current order's
  /// channel: in-store order types need `sold_in_store`; delivery needs
  /// `sold_on_delivery` and, once a provider is picked, its `listed` flag.
  bool isSoldOnCurrentChannel(Product product) {
    final live = _liveProduct(product);
    if (selectedOrderType == OrderType.delivery) {
      if (!live.soldOnDelivery) return false;
      final providerId = selectedDeliveryProviderId;
      return providerId == null || live.isListedOn(providerId);
    }
    return live.soldInStore;
  }

  /// The catalog's current copy of [product] (cart lines restored from
  /// storage carry a reduced copy), falling back to [product] itself.
  Product _liveProduct(Product product) =>
      productForId(product.id) ?? product;

  // An id index over the base catalog, rebuilt whenever the list is replaced
  // (the grid asks per tile and per frame).
  List<Product>? _indexedBase;
  Map<String, Product> _productIndex = const <String, Product>{};

  /// Total quantity of [productId] already in the current cart, pooled across
  /// line items (a product split into a plain line + a customized line counts
  /// once).
  double cartQuantityForProduct(String productId) {
    var total = 0.0;
    for (final item in _cart) {
      if (item.product.id == productId) total += item.qty;
    }
    return total;
  }

  static double _clampStock(double v) => v < 0 ? 0 : v;

  /// #3 — a finalized sale decrements the cached shelf count LOCALLY so the
  /// device's copy tracks the server's between config syncs (the product
  /// waste screen lists it). It never gates a sale (LAUNCH-P2 "sell, but
  /// warn"). Unit + cooked products only — they hold a produced/allocated
  /// shelf count; ingredient + untracked products are not shelf-counted
  /// here. The catalog ([_baseProducts] → [allProducts]) is decremented in
  /// memory, and [onShelfStockConsumed] fires so the screen persists it to
  /// Drift (surviving a restart until the next /device/config sync brings
  /// the server's authoritative balance). Reads the cart, so it must run
  /// BEFORE the next-order reset clears it. Add-on linked-product /
  /// cooked-component consumption is left to the server + the next sync
  /// (the device only decrements the top-level sold product here).
  void _consumeShelfStockFromCart() {
    final sold = <String, double>{};
    for (final item in _cart) {
      final mode = item.product.stockMode;
      if (mode == 'unit' || mode == 'cooked') {
        sold[item.product.id] = (sold[item.product.id] ?? 0) + item.qty;
      }
    }
    applyShelfStockConsumption(sold);
  }

  /// Decrement finite shelf stock for [soldByProductId] ({productId → quantity})
  /// in the in-memory catalog (clamped at 0) and persist via
  /// [onShelfStockConsumed]. Split out from [_consumeShelfStockFromCart] so the
  /// sale-decrement path is testable without driving a full payment.
  @visibleForTesting
  void applyShelfStockConsumption(Map<String, double> soldByProductId) {
    if (soldByProductId.isEmpty) return;

    _baseProducts = [
      for (final p in _baseProducts)
        (soldByProductId.containsKey(p.id) && p.branchStockQty != null)
            ? p.copyWith(
                setBranchStockQty: _clampStock(
                  p.branchStockQty! - soldByProductId[p.id]!,
                ),
              )
            : p,
    ];
    // Re-publish allProducts from the decremented base (also re-prices the
    // cart, which is about to be cleared — harmless).
    _applyDeliveryPricing();

    final byId = <int, double>{};
    soldByProductId.forEach((id, qty) {
      final intId = int.tryParse(id);
      if (intId != null) byId[intId] = qty;
    });
    if (byId.isNotEmpty) onShelfStockConsumed?.call(byId);
  }

  /// True when any cached product has a daily window configured — lets the
  /// screen skip minute-tick rebuilds entirely for merchants that never use
  /// time-windowed menus.
  bool get hasTimeWindowedProducts =>
      allProducts.any((p) => p.hasAvailabilityWindow);

  /// Called by the screen on each minute boundary so windowed tiles flip
  /// available/unavailable without a manual refresh.
  void onMinuteTick() {
    if (hasTimeWindowedProducts) notifyListeners();
  }

  List<Product> get visibleProducts {
    final query = productSearchQuery.trim().toLowerCase();
    return allProducts.where((product) {
      final matchesCategory = product.category == selectedCategory;
      if (!matchesCategory) return false;
      // LAUNCH-P4 C5 — only what this order's channel sells.
      if (!isSoldOnCurrentChannel(product)) return false;
      if (query.isEmpty) return true;
      // Phase C4 — an Arabic cashier can search by the Arabic product name.
      return product.name.toLowerCase().contains(query) ||
          product.nameAr.contains(query) ||
          product.category.toLowerCase().contains(query);
    }).toList();
  }

  bool get isEditingDiningTable =>
      selectedOrderType == OrderType.dineIn && activeDiningTableId != null;

  DiningFloor? get selectedDiningFloor =>
      _findDiningFloorById(selectedDiningFloorId);

  DiningTableDefinition? get activeDiningTableDefinition =>
      _findDiningTableDefinitionById(activeDiningTableId);

  DiningTableSession? get activeDiningTableSession =>
      activeDiningTableId == null
      ? null
      : diningSessionFor(activeDiningTableId!);

  List<DiningTableDefinition> get visibleDiningTables {
    final query = diningTableSearchQuery.trim().toLowerCase();

    return diningTableDefinitions
        .where((table) => table.floorId == selectedDiningFloorId)
        .where((table) {
          if (query.isEmpty) return true;
          final session = diningSessionFor(table.id);
          return table.name.toLowerCase().contains(query) ||
              table.sizeLabel.toLowerCase().contains(query) ||
              '${session?.orderNumber ?? ''}'.contains(query) ||
              (session?.orderReference.toLowerCase().contains(query) ?? false);
        })
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }

  pricing.PriceResult? _tenderPrice;
  OrderSnapshot? _tenderSnapshot;

  void _freezeTenderPrice() {
    if (_tenderPrice != null) return; // Paid split legs own this same price.
    _tenderPrice = _price;
    _tenderSnapshot = snapshot();
  }

  void _releaseTenderPrice() {
    if (hasRecordedSplitPayments) return;
    _tenderPrice = null;
    _tenderSnapshot = null;
    _invalidatePriceCache();
  }

  pricing.PriceResult? _priceCache;
  int _priceCacheNonce = -1;
  DateTime? _priceCacheAt;

  pricing.PriceResult get _price {
    if (_tenderPrice != null) return _tenderPrice!;
    final now = clock();
    final stale =
        _priceCache == null ||
        _priceCacheNonce != orderUpdateNonce ||
        _priceCacheAt == null ||
        now.difference(_priceCacheAt!).inSeconds >= 60;
    if (stale) {
      _priceCache = _priceOrder(machine_pricing.buildPricingInput(this, now));
      _priceCacheNonce = orderUpdateNonce;
      _priceCacheAt = now;
    }
    return _priceCache!;
  }

  void _invalidatePriceCache() {
    _priceCache = null;
    _priceCacheNonce = -1;
    _priceCacheAt = null;
  }

  double get rawSubtotal => pricing.baisasToOmr(_price.rawSubtotalBaisas);

  double get discountAmount => pricing.baisasToOmr(_price.discountTotalBaisas);

  /// The best applicable product/category-scope discount for [item] right now —
  /// auto-applied, since targeted promotions need no picker. Zero if none.
  ({double amount, int? id, String? amountType, String label}) lineDiscountFor(
    CartItem item,
  ) {
    var lineIndex = -1;
    for (var i = 0; i < _cart.length; i++) {
      if (identical(_cart[i], item)) {
        lineIndex = i;
        break;
      }
    }
    if (lineIndex >= 0) {
      for (final result in _price.lineDiscounts) {
        if (result.lineIndex == lineIndex) {
          return (
            amount: pricing.baisasToOmr(result.amountBaisas),
            id: result.ruleId,
            amountType: result.amountType,
            label: result.label,
          );
        }
      }
    }
    return (amount: 0.0, id: null, amountType: null, label: '');
  }

  /// Total of auto-applied product/category line discounts across the cart (OMR).
  double get lineDiscountTotal =>
      pricing.baisasToOmr(_price.lineDiscountTotalBaisas);

  /// P-F9 — the offer engine's verdict for the current cart: auto offers
  /// (bogo / multi-buy / cheapest-free / spend-get) plus any intact
  /// cashier-picked bundle instances. Pure recompute on every read.
  List<machine_pricing.AppliedOffer> get appliedOffers =>
      machine_pricing.appliedOffersFromResult(_price);

  /// Total taken off by offers (OMR).
  double get offerDiscountTotal =>
      pricing.baisasToOmr(_price.offerDiscountTotalBaisas);

  int _bundleSeq = 0;

  /// P-F9 — add a cashier-picked BUNDLE: the chosen products enter the cart
  /// tagged with one bundle instance key; the engine prices the intact set
  /// at the bundle price (removing a piece breaks the bundle — items then
  /// charge normally).
  void addBundle(Offer offer, List<Product> picks) {
    if (!_cartMutationAllowed()) return;
    // P-G7 — no promotions on delivery-provider orders: the bundle price
    // comes from the offer engine, which is delivery-gated, so the items
    // would silently charge full price. Refuse instead.
    if (selectedOrderType == OrderType.delivery) return;
    if (picks.isEmpty) return;
    // LAUNCH-P2 "sell, but warn" — a bundle is never refused on cached
    // stock, even when it takes a shelf count below zero.

    _dropCompForCartMutation();
    _ensureOrderReference();
    final key = '${offer.id}:${++_bundleSeq}';
    for (final product in picks) {
      _cart.insert(0, CartItem(product: product, bundleKey: key));
    }
    _markOrderUpdated(picks.first.id);
    _broadcast();
  }

  /// P-F4 — a cashier "clear" suppresses re-auto-application for the rest of
  /// this order (otherwise the rule would snap right back).
  bool _autoOrderDiscountSuppressed = false;

  /// P-F4 — self-apply the best qualifying ORDER-scope auto_apply rule when
  /// the discount slot is free. Called when items land in the cart and when
  /// the payment page opens (time windows re-checked then). Rules that
  /// require manager approval never auto-apply — nobody approved them.
  void maybeAutoApplyOrderDiscount() {
    if (customerTenderStarted ||
        customerLookupPending ||
        hasRecordedSplitPayments) {
      return;
    }
    if (isLiveSharedTable?.call() == true) return;
    if (!_cartMutationAllowed()) return;
    if (_autoOrderDiscountSuppressed) return;
    if (_hasLoyaltyRedemption) {
      if (_loyaltyRedemptionConsistent) return;
      discount = const DiscountConfiguration();
      _clearLoyaltyRedemption();
      _resetCharityRoundUp();
      _identityNotice(
        _l10n.localeName.startsWith('ar')
            ? 'تمت إزالة خصم الولاء المحفوظ لعدم توفر بيانات الاستبدال. يرجى استبدال المكافأة من جديد.'
            : 'Saved loyalty discount removed because its redemption details are missing. Please redeem the reward again.',
      );
      _broadcast();
    }
    if (discount.isActive || _cart.isEmpty) return;
    final now = clock();
    final input = machine_pricing.buildPricingInput(this, now);
    final best = pricing.selectAutoOrderDiscount(
      lines: input.lines,
      rules: input.discountRules,
      now: input.now,
      branchId: input.branchId,
      isDeliveryProvider: input.isDeliveryProvider,
    );
    if (best == null) return;
    discount = machine_pricing.discountConfigurationFromSelection(
      pricing.ruleAsOrderSelection(best),
    );
    _broadcast();
  }

  /// A cart item's snapshot map + its auto-applied line discount, so the order
  /// push can emit a per-line discounts[] entry with line_index.
  Map<String, dynamic> _snapshotItem(
    CartItem item, {
    pricing.PriceResult? priced,
  }) {
    final map = item.toMap();
    var lineIndex = -1;
    for (var i = 0; i < _cart.length; i++) {
      if (identical(_cart[i], item)) {
        lineIndex = i;
        break;
      }
    }
    pricing.LineDiscountResult? lineDiscount;
    if (lineIndex >= 0) {
      for (final result in (priced ?? _price).lineDiscounts) {
        if (result.lineIndex == lineIndex) {
          lineDiscount = result;
          break;
        }
      }
    }
    if (lineDiscount != null && lineDiscount.amountBaisas > 0) {
      map['lineDiscount'] = pricing.baisasToOmr(lineDiscount.amountBaisas);
      map['lineDiscountLabel'] = lineDiscount.label;
      if (lineDiscount.ruleId != null) {
        map['lineDiscountId'] = lineDiscount.ruleId;
      }
      if (lineDiscount.amountType != null) {
        map['lineDiscountAmountType'] = lineDiscount.amountType;
      }
    }
    // P-F5 — the gifted line's write-off value, frozen at snapshot time so
    // the push can emit an is_gift comp row per line.
    final giftBaisas = lineIndex < 0
        ? 0
        : ((priced ?? _price).giftAmountsBaisas[lineIndex] ?? 0);
    if (giftBaisas > 0) {
      map['giftAmount'] = pricing.baisasToOmr(giftBaisas);
    }
    return map;
  }

  double get subtotal => pricing.baisasToOmr(_price.subtotalBaisas);

  /// Phase B — the comp write-off (OMR), derived LIVE from the cart so edits
  /// can never leave a stale figure: a line comp = that line's discounted
  /// total; a whole-order comp = the whole discounted subtotal. A comped line
  /// that was removed clears the comp (returns 0).
  /// P-F5 — a gifted line's write-off value: its discounted total.
  double giftAmountFor(CartItem item) {
    for (var i = 0; i < _cart.length; i++) {
      if (identical(_cart[i], item)) {
        return pricing.baisasToOmr(_price.giftAmountsBaisas[i] ?? 0);
      }
    }
    return 0;
  }

  /// P-F5 — total written off by per-item gifts (OMR).
  double get giftedLinesTotal => pricing.baisasToOmr(_price.giftedTotalBaisas);

  bool get hasGiftedLines => _cart.any((item) => item.gifted);

  /// The total write-off: the manager comp + the gifted lines. A FULL-ORDER
  /// comp covers only what isn't already gifted (no double write-off); a
  /// line comp on a gifted line counts once (the gift wins).
  double get compAmount => pricing.baisasToOmr(_price.compTotalBaisas);

  /// P-F5 — the manager-comp slice of [compAmount] (what the reasoned comp
  /// row carries on the wire; the gifted lines ride their own is_gift rows).
  double get managerCompAmount => pricing.baisasToOmr(_price.managerCompBaisas);

  /// P-F5 — toggle a line gift (the screen owns the manager gate). Refused
  /// while a FULL-ORDER comp is applied — the order is already written off.
  bool toggleGiftItem(CartItem item) {
    if (!_cartMutationAllowed()) return false;
    // P-G7 — no gift write-offs on delivery-provider orders (the provider
    // pays the punched total; nothing is collected at the till anyway).
    if (selectedOrderType == OrderType.delivery && !item.gifted) {
      return false;
    }
    if (appliedComp != null && appliedComp!.lineIndex == null && !item.gifted) {
      return false;
    }
    item.gifted = !item.gifted;
    if (!item.gifted) _giftAuthorizations.remove(item)?.grant?.forget();
    _resetCharityRoundUp();
    _markOrderUpdated(item.product.id);
    _broadcast();
    return true;
  }

  /// The taxed base after the comp — comped food is given away, not sold, so
  /// no tax is charged on it (a fully comped order totals 0.000).
  double get _taxedBase => pricing.baisasToOmr(_price.taxedBaseBaisas);

  /// Per-tax breakdown (one line per active company tax) for the cart + receipt.
  List<TaxLineAmount> get taxLines {
    assert(pricing.omrToBaisas(_taxedBase) == _price.taxedBaseBaisas);
    return [
      for (final result in _price.taxLines)
        machine_pricing.taxLineFromResult(result),
    ];
  }

  double get tax => pricing.baisasToOmr(_price.taxTotalBaisas);

  double get total => pricing.baisasToOmr(_price.grandTotalBaisas);

  /// Phase B — apply a manager comp (one per order; replaces any prior one).
  /// The CALLER is responsible for manager authorization + cap validation
  /// against the picked reason's maxAmount.
  void applyComp(AppliedComp comp) {
    if (!_cartMutationAllowed()) return;
    // P-G7 — delivery-provider orders are exempt from EVERYTHING: a comp
    // would shrink the punched total the provider settles against.
    if (selectedOrderType == OrderType.delivery) return;
    final lineIndex = comp.lineIndex;
    int? normalizedQty;
    if (lineIndex != null && lineIndex >= 0 && lineIndex < _cart.length) {
      final lineQty = _cart[lineIndex].qty;
      final requestedQty = comp.qty;
      if (requestedQty != null && lineQty > 1 && requestedQty < lineQty) {
        normalizedQty = requestedQty.clamp(1, lineQty - 1).toInt();
      }
    }
    recordOrderAuthorization('comp', null);
    appliedComp = AppliedComp(
      reasonId: comp.reasonId,
      reasonName: comp.reasonName,
      lineIndex: lineIndex,
      qty: normalizedQty,
      note: comp.note,
    );
    _resetCharityRoundUp();
    _broadcast();
  }

  void removeComp() {
    if (!_cartMutationAllowed()) return;
    if (appliedComp == null) return;
    appliedComp = null;
    recordOrderAuthorization('comp', null);
    _resetCharityRoundUp();
    _broadcast();
  }

  void _dropCompForCartMutation() {
    if (appliedComp == null) return;
    appliedComp = null;
    recordOrderAuthorization('comp', null);
    _resetCharityRoundUp();
    onCompClearedAfterCartEdit?.call();
  }

  List<SplitPaymentRecord> get splitPayments =>
      List.unmodifiable(_splitPayments);

  /// Soft POS evidence for the last single (non-split) card payment, or null.
  /// The order-push bridge reads this synchronously at completion.
  CardCharge? get lastCardCharge => _lastCardCharge;

  int get paidSplitCount =>
      splitCount > 1 ? _splitPayments.length.clamp(0, splitCount).toInt() : 0;

  /// The active custom split plan (per-guest base amounts), or null when the
  /// split is equal-shares. Read-only — apply a new plan via [setSplitPlan].
  List<double>? get splitPlanAmounts {
    final plan = _splitPlanAmounts;
    return plan == null ? null : List.unmodifiable(plan);
  }

  int get activeSplitIndex {
    if (splitCount <= 1) return 1;
    if (paidSplitCount >= splitCount) return splitCount;
    return paidSplitCount + 1;
  }

  bool get hasRecordedSplitPayments =>
      splitCount > 1 && _splitPayments.isNotEmpty;

  bool get isSplitPaymentComplete =>
      splitCount > 1 && paidSplitCount >= splitCount;

  double get _splitBasePaidTotal => _roundMoney(
    _splitPayments.fold<double>(0, (sum, payment) => sum + payment.baseAmount),
  );

  double get _splitPaidTotal => _roundMoney(
    _splitPayments.fold<double>(0, (sum, payment) => sum + payment.paidAmount),
  );

  String? get reservedDiningBillUuid => _reservedDiningBill?['uuid'] as String?;

  double get activePaymentBaseTotal {
    if (isLiveSharedTable?.call() == true) {
      final server =
          (isProcessingPayment
              ? (_reservedDiningBill?['grand_total_baisas'] as int?)
              : null) ??
          liveDiningTotal?.call();
      if (server != null) return server / 1000;
    }
    final override = _activePaymentBaseOverride;
    if (override != null) return override;

    if (splitCount <= 1) return total;
    if (isSplitPaymentComplete) {
      return _splitPayments.isEmpty
          ? pricing.baisasToOmr(
              pricing.equalShareBaisas(_price.grandTotalBaisas, splitCount),
            )
          : _splitPayments.last.baseAmount;
    }

    final remainingShares = splitCount - paidSplitCount;
    if (remainingShares <= 1) {
      return pricing.baisasToOmr(
        pricing.remainderShareBaisas(
          _price.grandTotalBaisas,
          pricing.omrToBaisas(_splitBasePaidTotal),
        ),
      );
    }

    // Custom plan: the next guest pays their planned share — but only while
    // the cart is untouched since planning (nonce) AND the plan still matches
    // the live total. A cart edited after planning silently falls back to
    // equal shares rather than charging stale figures; the nonce also blocks
    // a swapped cart whose new total merely coincides with the planned one.
    final plan = _splitPlanAmounts;
    if (plan != null &&
        plan.length == splitCount &&
        _splitPlanNonce == orderUpdateNonce) {
      final planBaisas = [
        for (final amount in plan) pricing.omrToBaisas(amount),
      ];
      if (pricing.splitPlanMatchesTotal(planBaisas, _price.grandTotalBaisas)) {
        return pricing.baisasToOmr(planBaisas[paidSplitCount]);
      }
    }

    return pricing.baisasToOmr(
      pricing.equalShareBaisas(_price.grandTotalBaisas, splitCount),
    );
  }

  double get payableTotal {
    if (isSplitPaymentComplete) return _splitPaidTotal;
    return charityRoundUpAccepted
        ? charityRoundUpTotal
        : activePaymentBaseTotal;
  }

  double get offeredCharityRoundUpTotal =>
      _roundMoney(activePaymentBaseTotal.ceilToDouble());

  double get offeredCharityRoundUpAmount =>
      _roundMoney(offeredCharityRoundUpTotal - activePaymentBaseTotal);

  bool get canOfferCharityRoundUp =>
      !(selectedOrderType == OrderType.dineIn &&
          activeDiningTableId != null &&
          (isLiveSharedTable?.call() ?? false)) &&
      // P-G7 — no round-up on delivery orders (no till money at all).
      selectedOrderType != OrderType.delivery &&
      // CARD legs only. The round-up must ride the card charge (the bank
      // collects sale + round-up in one lump and the platform forwards the
      // round-up to charity). A round-up accepted on a CASH leg — previously
      // allowed inside a split — puts the money in the till instead: the sync
      // payload only transmits donations when a card tender exists, so a
      // cash-only split silently kept untracked charity cash, and even in a
      // mixed split the cash-leg round-up never reached the bank lump. Plain
      // cash sales never offered round-up; this makes splits consistent.
      selectedPaymentMethod == 'Credit Card' &&
      offeredCharityRoundUpAmount >= 0.001;

  DiningTableSession? diningSessionFor(String tableId) {
    for (final session in diningTableSessions) {
      if (session.tableId == tableId) return session;
    }
    return null;
  }

  OrderSnapshot snapshot({String? note}) {
    final activeTable = activeDiningTableDefinition;
    final floor = activeTable == null
        ? null
        : _findDiningFloorById(activeTable.floorId);
    final priced = _price;
    final frozen = _tenderSnapshot;

    // P-F9 — freeze the applied offers (flattened allocations).
    final frozenOffers = <Map<String, dynamic>>[
      for (final o in priced.appliedOffers) ...[
        for (final e in o.lineAmountsBaisas.entries)
          {
            'offer_id': o.offerId,
            'name': o.name,
            'amount': pricing.baisasToOmr(e.value),
            'line_index': e.key,
          },
        if (o.orderAmountBaisas > 0)
          {
            'offer_id': o.offerId,
            'name': o.name,
            'amount': pricing.baisasToOmr(o.orderAmountBaisas),
          },
      ],
    ];

    return OrderSnapshot(
      businessIdentity: _businessIdentity,
      orderNumber: currentOrderNumber,
      receiptNumber: receiptNumber, // P-F8 — '' until allocated
      offers: frozenOffers, // P-F9
      orderType: selectedOrderType.storageValue,
      items:
          frozen?.items ??
          [for (final item in _cart) _snapshotItem(item, priced: priced)],
      rawSubtotal: pricing.baisasToOmr(priced.rawSubtotalBaisas),
      discountAmount: pricing.baisasToOmr(priced.discountTotalBaisas),
      discountLabel: frozen == null ? discount.label : frozen.discountLabel,
      discountId: frozen == null ? discount.discountId : frozen.discountId,
      discountAmountType: frozen == null
          ? discount.amountType
          : frozen.discountAmountType,
      discountReason: frozen == null ? discount.reason : frozen.discountReason,
      loyaltyRedeemRuleId: loyaltyRedeemRuleId,
      loyaltyRedeemPoints: loyaltyRedeemPoints,
      loyaltyRedeemStamps: loyaltyRedeemStamps,
      compAmount: pricing.baisasToOmr(priced.compTotalBaisas),
      compReasonId: frozen == null
          ? appliedComp?.reasonId
          : frozen.compReasonId,
      compReasonName: frozen == null
          ? appliedComp?.reasonName ?? ''
          : frozen.compReasonName,
      compLineIndex: frozen == null
          ? appliedComp?.lineIndex
          : frozen.compLineIndex,
      compQty: frozen == null ? appliedComp?.qty : frozen.compQty,
      subtotal: pricing.baisasToOmr(priced.subtotalBaisas),
      tax: pricing.baisasToOmr(priced.taxTotalBaisas),
      // LAUNCH-P4 — freeze the inclusive flag and the priced tax lines (with
      // their Arabic names) for the receipt and the push.
      pricesIncludeTax: priced.pricesIncludeTax,
      taxLines: [
        for (final line in priced.taxLines)
          {
            'name': line.name,
            if ((line.nameAr ?? '').trim().isNotEmpty) 'nameAr': line.nameAr,
            'ratePercent': line.ratePercent,
            'amount': pricing.baisasToOmr(line.amountBaisas),
          },
      ],
      total: pricing.baisasToOmr(priced.grandTotalBaisas),
      activePaymentBaseTotal: activePaymentBaseTotal,
      splitCount: splitCount,
      payableTotal: payableTotal,
      paymentStatus: paymentStatus,
      paymentMethod: isSplitPaymentComplete
          ? 'Split Payment'
          : selectedPaymentMethod,
      customerReferenceNumber: customerReferenceNumber,
      diningFloorId: activeTable?.floorId ?? '',
      diningFloorLabel: floor?.label ?? '',
      diningTableId: activeTable?.id ?? '',
      diningTableName: activeTable?.name ?? '',
      note: note ?? displayNote,
      showCharityRoundUpPrompt: showCharityRoundUpPrompt,
      showPaymentLaunchOverlay: showPaymentLaunchOverlay,
      paymentOverlayTitle: paymentOverlayTitle,
      charityRoundUpAccepted: charityRoundUpAccepted,
      charityRoundUpAmount: charityRoundUpAmount,
      charityRoundUpTotal: charityRoundUpTotal,
      splitPayments: List<SplitPaymentRecord>.from(_splitPayments),
      charityRoundUpPromptId: showCharityRoundUpPrompt
          ? _activeCharityRoundUpPromptId
          : 0,
      recentProductId: recentProductId,
      orderUpdateNonce: orderUpdateNonce,
      // P-G7 — the delivery-provider lifecycle (deliveryReference is only
      // ever non-empty after completeDeliveryOrder's Proceed popup). The
      // punched values win: they survive a mid-completion config refresh
      // that drops the live selection.
      deliveryProviderId:
          _punchedDeliveryProviderId ??
          (selectedOrderType == OrderType.delivery
              ? selectedDeliveryProviderId
              : null),
      deliveryProviderName: _punchedDeliveryProviderName.isNotEmpty
          ? _punchedDeliveryProviderName
          : (selectedOrderType == OrderType.delivery
                ? (selectedDeliveryProvider?.name ?? '')
                : ''),
      deliveryReference: deliveryReference,
      deliveryDriverPhone: deliveryDriverPhone,
    );
  }

  void _restoreDraftDiscount(OrderSessionDraft draft) {
    vehiclePlateNumber = draft.vehiclePlateNumber;
    selectedCustomer = draft.customer != null && draft.customer!.id > 0
        ? draft.customer
        : null;
    selectedEarnRuleIds = selectedCustomer == null
        ? null
        : draft.earnRuleIds == null
        ? null
        : List<int>.from(draft.earnRuleIds!);
    customerReferenceNumber = draft.customerReferenceNumber;
    _refreshDraftCustomer();
    discount = draft.discount;
    loyaltyRedeemRuleId = draft.hasLoyaltyDebit
        ? draft.loyaltyRedeemRuleId
        : null;
    loyaltyRedeemPoints = draft.hasLoyaltyDebit ? draft.loyaltyRedeemPoints : 0;
    loyaltyRedeemStamps = draft.hasLoyaltyDebit ? draft.loyaltyRedeemStamps : 0;
    loyaltyRedeemCustomerId = draft.hasLoyaltyDebit
        ? draft.loyaltyRedeemCustomerId
        : null;
    if (draft.hasUnbackedLoyaltyDiscount ||
        (draft.hasLoyaltyDebit && !_loyaltyRedemptionConsistent)) {
      discount = const DiscountConfiguration();
      _clearLoyaltyRedemption();
      final message = _l10n.localeName.startsWith('ar')
          ? 'تمت إزالة خصم الولاء المحفوظ لعدم توفر بيانات الاستبدال. يرجى استبدال المكافأة من جديد.'
          : 'Saved loyalty discount removed because its redemption details are missing. Please redeem the reward again.';
      lastPaymentMessage = message;
      displayNote = message;
      onDraftRedemptionCleared?.call(message);
    }
  }

  OrderSessionDraft createDraft({String serverOrderUuid = ''}) {
    final activeTable = activeDiningTableDefinition;
    final floor = activeTable == null
        ? null
        : _findDiningFloorById(activeTable.floorId);

    return OrderSessionDraft(
      orderReference: _ensureOrderReference(),
      orderType: selectedOrderType,
      selectedCategory: selectedCategory,
      customerReferenceNumber: customerReferenceNumber,
      customer: selectedCustomer == null
          ? null
          : CustomerSearchResult.fromJson(selectedCustomer!.toJson()),
      earnRuleIds: selectedEarnRuleIds == null
          ? null
          : List<int>.from(selectedEarnRuleIds!),
      loyaltyRedeemCustomerId: loyaltyRedeemCustomerId,
      vehiclePlateNumber: vehiclePlateNumber,
      diningFloorId: activeTable?.floorId ?? '',
      diningFloorLabel: floor?.label ?? '',
      diningTableId: activeTable?.id ?? '',
      diningTableName: activeTable?.name ?? '',
      items: _cart.map((item) => CartItem.fromMap(item.toMap())).toList(),
      discount: discount,
      loyaltyRedeemRuleId: loyaltyRedeemRuleId,
      loyaltyRedeemPoints: loyaltyRedeemPoints,
      loyaltyRedeemStamps: loyaltyRedeemStamps,
      splitCount: splitCount,
      note: displayNote,
      serverOrderUuid: serverOrderUuid,
    );
  }

  Future<void> syncRearDisplay() async {
    if (!_presentationEnabled) return;
    if (_rearDisplaySyncInFlight) {
      _rearDisplaySyncPending = true;
      return;
    }

    _rearDisplaySyncInFlight = true;
    try {
      do {
        _rearDisplaySyncPending = false;
        try {
          await _presentation.sendOrder(snapshot());
        } on MissingPluginException {
          _presentationEnabled = false;
          _rearDisplaySyncPending = false;
        } catch (_) {
          _presentationEnabled = false;
          _rearDisplaySyncPending = false;
        }

        if (_rearDisplaySyncPending &&
            !_isDisposed &&
            _presentationEnabled &&
            rearDisplayOpened) {
          await Future<void>.delayed(_rearDisplaySyncDebounceDuration);
        }
      } while (_rearDisplaySyncPending &&
          !_isDisposed &&
          _presentationEnabled &&
          rearDisplayOpened);
    } finally {
      _rearDisplaySyncInFlight = false;
    }
  }

  void selectCategory(String category) {
    selectedCategory = category;
    _notifySafely();
  }

  Future<void> selectOrderType(OrderType orderType) async {
    if (tableTransitionInProgress) {
      _identityNotice(tableTransitionMessage);
      return;
    }
    return _duringTableTransition(() => _selectOrderType(orderType));
  }

  Future<void> _selectOrderType(OrderType orderType) async {
    if (!_cartMutationAllowed(insideTableTransition: true)) return;
    // LAUNCH-P5 C7 — training sells over the counter only (no tables, no
    // delivery providers).
    if (training &&
        orderType != OrderType.quickOrder &&
        orderType != OrderType.toGo) {
      _trainingRefusal();
      return;
    }
    if (selectedOrderType == orderType) {
      if (orderType == OrderType.dineIn && activeDiningTableId == null) {
        displayNote = _l10n.ctrlMsgChooseTableDineIn;
        _broadcast();
      }
      return;
    }

    if (selectedOrderType == OrderType.dineIn && activeDiningTableId != null) {
      await _duringTableTransition(_returnToDiningFloorPlan);
    }

    selectedOrderType = orderType;
    if (orderType == OrderType.dineIn) {
      displayNote = _l10n.ctrlMsgChooseTableDineIn;
      paymentStatus = 'Waiting';
      selectedPaymentMethod = 'Cash';
      productSearchQuery = '';
    } else {
      activeDiningTableId = null;
      diningTableSearchQuery = '';
    }
    // Leaving delivery clears the chosen provider; entering it waits for the
    // cashier to pick one. Either way, re-price the menu + cart accordingly.
    if (orderType != OrderType.delivery) {
      selectedDeliveryProviderId = null;
    } else {
      // P-G7 — a delivery order is exempt from EVERYTHING: drop any active
      // discount / loyalty redemption picked up before the switch (the
      // gates above stop new ones from applying).
      discount = const DiscountConfiguration();
      loyaltyRedeemRuleId = null;
      loyaltyRedeemPoints = 0;
      loyaltyRedeemStamps = 0;
      loyaltyRedeemCustomerId = null;
    }
    _applyDeliveryPricing();
    _broadcast();
  }

  void setProductSearchQuery(String value) {
    productSearchQuery = value;
    _notifySafely();
  }

  void setDiningTableSearchQuery(String value) {
    diningTableSearchQuery = value.trim();
    _notifySafely();
  }

  void clearDiningTableSearch() {
    diningTableSearchQuery = '';
    _notifySafely();
  }

  void selectDiningFloor(String floorId) {
    selectedDiningFloorId = floorId;
    _notifySafely();
  }

  void clearProductSearch() {
    productSearchQuery = '';
    _notifySafely();
  }

  void setProductViewMode(ProductViewMode mode) {
    productViewMode = mode;
    _notifySafely();
  }

  void selectPaymentMethod(String paymentMethod) {
    if (!_cartMutationAllowed()) return;
    selectedPaymentMethod = paymentMethod;
    _broadcast();
  }

  void _customerChangingTo(int? id) {
    if (selectedCustomer?.id == id) return;
    if (selectedCustomer != null) vehiclePlateNumber = '';
    selectedEarnRuleIds = null;
    if (!_hasLoyaltyRedemption) return;
    discount = const DiscountConfiguration();
    _clearLoyaltyRedemption();
    _resetCharityRoundUp();
    final message = _l10n.localeName.startsWith('ar')
        ? 'تمت إزالة استبدال نقاط الولاء لتغيّر العميل. أعد الاستبدال إذا لزم.'
        : 'Loyalty redemption removed because the customer changed. Redeem again if needed.';
    lastPaymentMessage = message;
    displayNote = message;
    onDraftRedemptionCleared?.call(message);
  }

  bool setCustomerReferenceNumber(String value) {
    if (!_identityMutationAllowed()) return false;
    final reference = value.replaceAll(RegExp(r'\D'), '').trim();
    final attachedReference = selectedCustomer?.phone
        .replaceAll(RegExp(r'\D'), '')
        .trim();
    if (selectedCustomer == null || reference != attachedReference) {
      _customerChangingTo(null);
      selectedCustomer = null;
      selectedEarnRuleIds = null;
    }
    customerReferenceNumber = reference;
    _broadcast();
    return true;
  }

  /// An explicit search with no match is a raw reference, even when its digits
  /// equal a differently formatted stored phone.
  bool setUnmatchedCustomerReference(String value) {
    if (!_identityMutationAllowed()) return false;
    _customerChangingTo(null);
    selectedCustomer = null;
    selectedEarnRuleIds = null;
    customerReferenceNumber = value.replaceAll(RegExp(r'\D'), '').trim();
    _broadcast();
    return true;
  }

  bool clearAttachedCustomer() {
    if (!_identityMutationAllowed()) return false;
    cancelCustomerLookups();
    _customerChangingTo(null);
    selectedCustomer = null;
    selectedEarnRuleIds = null;
    customerReferenceNumber = '';
    vehiclePlateNumber = '';
    _broadcast();
    return true;
  }

  /// A same-id refresh keeps the order's redemption and earn choice.
  bool attachCustomer(CustomerSearchResult customer) {
    if (hasRecordedSplitPayments &&
        !customerTenderStarted &&
        selectedCustomer?.id == customer.id &&
        !tableTransitionInProgress) {
      return true;
    }
    if (!_identityMutationAllowed()) return false;
    _customerChangingTo(customer.id);
    selectedCustomer = customer;
    customerReferenceNumber = customer.phone
        .replaceAll(RegExp(r'\D'), '')
        .trim();
    _broadcast();
    return true;
  }

  bool setVehiclePlateNumber(String value) {
    if (!_identityMutationAllowed(money: true)) return false;
    // Plates are alphanumeric; store the canonical uppercased form (the server
    // matches plates uppercased).
    vehiclePlateNumber = value.trim().toUpperCase();
    _broadcast();
    return true;
  }

  /// Offline customer search over the cached slice (name/phone contains the
  /// query), returning the CustomerSearchResult shape WITH cached loyalty, so
  /// attach + redeem work unchanged when the live search is unreachable.
  List<CustomerSearchResult> searchCachedCustomers(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return cachedCustomers
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.phone.toLowerCase().contains(q) ||
              // P-F2 — offline plate lookup (plates cache uppercased).
              c.plates.any((p) => p.toLowerCase().contains(q)),
        )
        .take(20)
        .map((c) => c.toSearchResult())
        .toList();
  }

  /// Pending loyalty redemption for this order (the points SPENT). Its monetary
  /// value rides as the order discount; this is sent as loyalty_redeem on pay so
  /// the server decrements the balance. Null = no redemption.
  @override
  int? loyaltyRedeemRuleId;
  @override
  int loyaltyRedeemPoints = 0;
  // Stamps spent on a visit_based (stamp-card) redemption (sent as
  // loyalty_redeem.stamps on pay). 0 = a points redemption (or none).
  @override
  int loyaltyRedeemStamps = 0;

  int? loyaltyRedeemCustomerId;

  bool get _hasLoyaltyRedemption =>
      loyaltyRedeemRuleId != null ||
      loyaltyRedeemPoints != 0 ||
      loyaltyRedeemStamps != 0;

  bool get _loyaltyRedemptionConsistent =>
      selectedCustomer != null &&
      selectedCustomer!.id > 0 &&
      loyaltyRedeemCustomerId == selectedCustomer!.id &&
      loyaltyRedeemRuleId != null &&
      loyaltyRedeemRuleId! > 0 &&
      ((loyaltyRedeemPoints > 0 &&
              loyaltyRedeemStamps == 0 &&
              discount.label == 'Loyalty redemption') ||
          (loyaltyRedeemStamps > 0 &&
              loyaltyRedeemPoints == 0 &&
              discount.label == 'Stamp reward')) &&
      discount.kind == DiscountKind.fixedAmount &&
      discount.discountId == null &&
      discount.value > 0;

  void _clearLoyaltyRedemption() {
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    loyaltyRedeemStamps = 0;
    loyaltyRedeemCustomerId = null;
  }

  String? _guardLoyaltyTender() {
    // Canonical live-table redemptions are owned by the server, not this slot.
    if (isLiveSharedTable?.call() == true ||
        !_hasLoyaltyRedemption ||
        _loyaltyRedemptionConsistent) {
      return null;
    }
    final message = _l10n.localeName.startsWith('ar')
        ? 'أعد إرفاق العميل أو أزل استبدال نقاط الولاء قبل الدفع'
        : 'Attach the customer again or remove the loyalty redemption before paying';
    lastPaymentMessage = message;
    displayNote = message;
    _notifySafely();
    return message;
  }

  static bool isLoyaltyOwnedDiscount(DiscountConfiguration configuration) =>
      configuration.kind == DiscountKind.fixedAmount &&
      configuration.discountId == null &&
      (configuration.label == 'Loyalty redemption' ||
          configuration.label == 'Stamp reward');

  bool applyDiscount(DiscountConfiguration configuration) {
    if (isLoyaltyOwnedDiscount(configuration)) return false;
    if (!_identityMutationAllowed(money: true)) return false;
    // P-G7 — delivery-provider orders take no discounts.
    if (selectedOrderType == OrderType.delivery) return false;
    discount = configuration;
    recordOrderAuthorization('discount', null);
    recordOrderAuthorization('loyalty', null);
    // A manual/merchant discount reuses the single discount slot — drop any
    // pending loyalty redemption so we don't send a stale redeem on pay.
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    loyaltyRedeemStamps = 0;
    loyaltyRedeemCustomerId = null;
    _resetCharityRoundUp();
    _broadcast();
    return true;
  }

  /// Redeem under a loyalty rule: apply [valueOmr] as the order discount and
  /// remember the [points] OR [stamps] to spend (sent as loyalty_redeem on
  /// pay). spend_based passes points; visit_based passes stamps.
  bool applyLoyaltyRedemption({
    required int ruleId,
    required double valueOmr,
    required String label,
    int? customerId,
    int points = 0,
    int stamps = 0,
  }) {
    if (!_identityMutationAllowed(money: true)) return false;
    if (selectedCustomer == null ||
        (customerId != null && customerId != selectedCustomer!.id)) {
      _identityNotice(
        _l10n.localeName.startsWith('ar')
            ? 'تغيّر العميل. افتح الاستبدال مرة أخرى.'
            : 'The customer changed. Open Redeem again.',
      );
      return false;
    }
    if (selectedOrderType == OrderType.delivery) return false;
    discount = DiscountConfiguration(
      kind: DiscountKind.fixedAmount,
      value: valueOmr,
      label: label,
    );
    recordOrderAuthorization('discount', null);
    recordOrderAuthorization('loyalty', null);
    loyaltyRedeemCustomerId = selectedCustomer!.id;
    loyaltyRedeemRuleId = ruleId;
    loyaltyRedeemPoints = points;
    loyaltyRedeemStamps = stamps;
    _resetCharityRoundUp();
    _broadcast();
    return true;
  }

  bool clearDiscount() {
    if (!_identityMutationAllowed(money: true)) return false;
    discount = const DiscountConfiguration();
    recordOrderAuthorization('discount', null);
    recordOrderAuthorization('loyalty', null);
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    loyaltyRedeemStamps = 0;
    loyaltyRedeemCustomerId = null;
    // P-F4 — an explicit clear means "no discount on THIS order": stop the
    // auto order-scope rule from re-applying itself.
    _autoOrderDiscountSuppressed = true;
    _resetCharityRoundUp();
    _broadcast();
    return true;
  }

  /// The catalogue product with this id, or null (used to value a free-product
  /// stamp reward at its current price).
  Product? productById(int id) {
    for (final p in _baseProducts) {
      if (int.tryParse(p.id) == id) return p;
    }
    return null;
  }

  void setSplitCount(int count) {
    if (!_cartMutationAllowed()) return;
    if (hasRecordedSplitPayments) return;
    splitCount = count < 1 ? 1 : count;
    _splitPayments.clear();
    _splitPlanAmounts = null;
    _resetCharityRoundUp();
    _broadcast();
  }

  /// Applies a CUSTOM split: each guest pays an arbitrary share instead of an
  /// equal one. Non-final shares must each be at least one baisa AND leave at
  /// least a baisa over; the LAST share is rewritten to the exact remainder so
  /// the legs always close to the total (3dp hand-entry drift never strands a
  /// baisa). Returns false when the plan is rejected — the caller must NOT
  /// present the split as active in that case.
  bool setSplitPlan(List<double> amounts) {
    if (!_cartMutationAllowed()) return false;
    if (hasRecordedSplitPayments) return false;
    final shares = pricing.validateSplitPlan([
      for (final amount in amounts) pricing.omrToBaisas(amount),
    ], _price.grandTotalBaisas);
    if (shares == null) return false;
    splitCount = shares.length;
    _splitPayments.clear();
    _splitPlanAmounts = [
      for (final amount in shares) pricing.baisasToOmr(amount),
    ];
    _splitPlanNonce = orderUpdateNonce;
    _resetCharityRoundUp();
    _broadcast();
    return true;
  }

  void clearSplit() {
    if (!_cartMutationAllowed()) return;
    if (hasRecordedSplitPayments) return;
    splitCount = 1;
    _splitPayments.clear();
    _splitPlanAmounts = null;
    _resetCharityRoundUp();
    _broadcast();
  }

  void addProduct(Product product) {
    BusinessBoundary.assertWritable();
    if (releaseBuild && !_hasRealCatalog) {
      throw StateError('Load this branch configuration before selling.');
    }
    if (!_cartMutationAllowed()) return;
    // LAUNCH-P4 C5 / C6 — never add what this order's channel does not sell,
    // or what this branch switched to sold out.
    if (!isSoldOnCurrentChannel(product) || isSoldOut(product)) return;
    // LAUNCH-P2 "sell, but warn" — the cached shelf count never caps the
    // cart; the sale may take the branch balance below zero.
    final index = _cart.indexWhere(
      (item) => item.product.id == product.id && !item.hasCustomization,
    );
    _dropCompForCartMutation();
    _ensureOrderReference();
    if (index == -1) {
      _cart.insert(0, CartItem(product: product));
    } else {
      final updatedItem = _cart.removeAt(index);
      updatedItem.qty++;
      _cart.insert(0, updatedItem);
    }
    _markOrderUpdated(product.id);
    maybeAutoApplyOrderDiscount(); // P-F4 — order-scope auto rules
    _broadcast();
  }

  /// LAUNCH-P4 H4 — add [product] with the add-ons the cashier picked in the
  /// options sheet (a tap on a product with a required group opens it). An
  /// identical existing line (same options and notes) takes the quantity.
  void addCustomizedProduct(
    Product product, {
    required List<CartItemModifier> modifiers,
    String notes = '',
  }) {
    BusinessBoundary.assertWritable();
    if (releaseBuild && !_hasRealCatalog) {
      throw StateError('Load this branch configuration before selling.');
    }
    if (!_cartMutationAllowed()) return;
    if (!isSoldOnCurrentChannel(product) || isSoldOut(product)) return;
    final line = CartItem(product: product, modifiers: modifiers, notes: notes);
    final index = _cart.indexWhere(
      (item) => item.mergeSignature == line.mergeSignature,
    );
    _dropCompForCartMutation();
    _ensureOrderReference();
    if (index == -1) {
      _cart.insert(0, line);
    } else {
      final existing = _cart.removeAt(index);
      existing.qty++;
      _cart.insert(0, existing);
    }
    _markOrderUpdated(product.id);
    maybeAutoApplyOrderDiscount();
    _broadcast();
  }

  /// The catalog's product with [id] (null when it is not in this branch's
  /// catalog).
  Product? productForId(String id) {
    if (!identical(_indexedBase, _baseProducts)) {
      _productIndex = {for (final p in _baseProducts) p.id: p};
      _indexedBase = _baseProducts;
    }
    final indexed = _productIndex[id];
    if (indexed != null) return indexed;
    // The built-in demo catalogue has no base list.
    if (_baseProducts.isEmpty) {
      for (final p in allProducts) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  /// LAUNCH-P4 C7 — a combo's slots from the live catalog.
  List<ComboSlot> comboSlotsFor(Product combo) =>
      _liveProduct(combo).comboSlots;

  /// LAUNCH-P4 C7 — why [components] are not a valid choice for [combo]
  /// (null = valid): every slot between its min and max picks, every pick an
  /// option of its slot, priced at that option's extra, and each pick's
  /// required add-ons chosen. English identity names (the screen localizes).
  String? comboChoiceError(Product combo, List<ComboComponent> components) {
    final slots = comboSlotsFor(combo);
    if (slots.isEmpty) return 'combo has no slots';
    for (final slot in slots) {
      final picks = components.where((c) => c.slotId == slot.id).toList();
      final count = picks.fold<int>(0, (sum, c) => sum + c.qty);
      if (count < slot.min || count > slot.max) return slot.name;
      for (final pick in picks) {
        final option = slot.options
            .where((o) => o.productId.toString() == pick.productId)
            .firstOrNull;
        if (option == null) return slot.name;
        if (pricing.omrToBaisas(option.extraPrice) !=
            pricing.omrToBaisas(pick.extraPrice)) {
          return slot.name;
        }
        final product = productForId(pick.productId);
        if (product != null &&
            missingRequiredGroup(product, pick.modifiers) != null) {
          return slot.name;
        }
      }
    }
    if (components.any((c) => !slots.any((s) => s.id == c.slotId))) {
      return 'unknown slot';
    }
    return null;
  }

  /// LAUNCH-P4 C7 — add a combo built in the combo sheet. Refused (no line)
  /// when the channel does not sell the combo (e.g. a delivery app that
  /// does not list it), it is sold out, or the choices are invalid. The
  /// same combo with the same choices merges into the existing line.
  bool addCombo(Product combo, List<ComboComponent> components) {
    BusinessBoundary.assertWritable();
    if (releaseBuild && !_hasRealCatalog) {
      throw StateError('Load this branch configuration before selling.');
    }
    if (!_cartMutationAllowed()) return false;
    final live = _liveProduct(combo);
    if (!live.isCombo ||
        !isSoldOnCurrentChannel(live) ||
        isSoldOut(live) ||
        comboChoiceError(live, components) != null) {
      return false;
    }
    // The channel price published in allProducts (delivery re-priced).
    final priced = allProducts.firstWhere(
      (p) => p.id == live.id,
      orElse: () => live,
    );
    final line = CartItem(product: priced, components: components);
    final index = _cart.indexWhere(
      (item) => item.mergeSignature == line.mergeSignature,
    );
    _dropCompForCartMutation();
    _ensureOrderReference();
    if (index == -1) {
      _cart.insert(0, line);
    } else {
      final existing = _cart.removeAt(index);
      existing.qty++;
      _cart.insert(0, existing);
    }
    _markOrderUpdated(live.id);
    maybeAutoApplyOrderDiscount();
    _broadcast();
    return true;
  }

  /// LAUNCH-P4 C7 — edit a combo line's choices (the quantity stays).
  bool updateComboComponents(CartItem item, List<ComboComponent> components) {
    if (!_cartMutationAllowed()) return false;
    final index = _cart.indexOf(item);
    if (index == -1) return false;
    if (comboChoiceError(item.product, components) != null) return false;
    _dropCompForCartMutation();
    item.components = List<ComboComponent>.from(components);
    _markOrderUpdated(item.product.id);
    _broadcast();
    return true;
  }

  /// LAUNCH-P4 H4 — whether tapping [product] must open the options sheet
  /// first (it has a required add-on group).
  bool needsOptionsBeforeAdd(Product product) =>
      addonGroupsForProduct(product).any((group) => group.isRequired);

  /// LAUNCH-P4 H4 — the first cart line that misses a required add-on choice
  /// (fewer picks than the group's minimum), or null.
  ({CartItem item, AddonGroup group})? firstMissingRequiredChoice() {
    for (final item in _cart) {
      final missing = missingRequiredGroup(item.product, item.modifiers);
      if (missing != null) return (item: item, group: missing);
      // LAUNCH-P4 C7 — each item inside a combo keeps its required groups.
      for (final component in item.components) {
        final product = productForId(component.productId);
        if (product == null) continue;
        final group = missingRequiredGroup(product, component.modifiers);
        if (group != null) return (item: item, group: group);
      }
    }
    return null;
  }

  /// LAUNCH-P4 H4 — the first required group of [product] that [modifiers]
  /// do not satisfy (counted by option id), or null.
  AddonGroup? missingRequiredGroup(
    Product product,
    List<CartItemModifier> modifiers,
  ) {
    final picked = {for (final m in modifiers) m.id};
    for (final group in addonGroupsForProduct(product)) {
      if (!group.isRequired) continue;
      final count = group.options
          .where((option) => picked.contains(option.id.toString()))
          .length;
      if (count < group.effectiveMin) return group;
    }
    return null;
  }

  /// LAUNCH-P4 — why the current cart cannot be paid under the menu rules
  /// (null = it can): a line not sold on this order's channel (C5 — e.g. the
  /// order moved to a delivery app that does not list it), or a line missing
  /// a required add-on choice (H4).
  String? menuTenderRefusal() {
    final arabic = _l10n.localeName.startsWith('ar');
    for (final item in _cart) {
      if (!isSoldOnCurrentChannel(item.product)) {
        return _l10n.ctrlMsgNotSoldOnChannel(item.product.displayName(arabic));
      }
      // LAUNCH-P4 C7 — a combo must carry a valid set of choices (a combo
      // line restored without its components cannot be paid).
      if (_liveProduct(item.product).isCombo &&
          comboChoiceError(item.product, item.components) != null) {
        return _l10n.ctrlMsgComboIncomplete(item.product.displayName(arabic));
      }
    }
    final missing = firstMissingRequiredChoice();
    if (missing != null) {
      return _l10n.ctrlMsgRequiredChoiceMissing(
        missing.item.product.displayName(arabic),
        arabic && (missing.group.nameAr ?? '').trim().isNotEmpty
            ? missing.group.nameAr!.trim()
            : missing.group.name,
      );
    }
    return null;
  }

  void incrementCartItem(CartItem item) {
    if (!_cartMutationAllowed()) return;
    final index = _cart.indexOf(item);
    if (index == -1) return;

    _dropCompForCartMutation();
    _cart[index].qty++;
    _markOrderUpdated(_cart[index].product.id);
    _broadcast();
  }

  void removeCartItem(CartItem item) {
    if (!_cartMutationAllowed()) return;
    final removed = _cart.remove(item);
    if (!removed) return;
    _dropCompForCartMutation();
    _broadcast();
  }

  void decreaseCartItem(CartItem item) {
    if (!_cartMutationAllowed()) return;
    final index = _cart.indexOf(item);
    if (index == -1) return;

    _dropCompForCartMutation();
    if (_cart[index].qty <= 1) {
      _cart.removeAt(index);
    } else {
      _cart[index].qty--;
    }
    _broadcast();
  }

  void updateCartItemCustomization(
    CartItem item, {
    required List<CartItemModifier> modifiers,
    required String notes,
  }) {
    if (!_cartMutationAllowed()) return;
    final index = _cart.indexOf(item);
    if (index == -1) return;

    _dropCompForCartMutation();
    _cart[index].modifiers = List<CartItemModifier>.from(modifiers);
    _cart[index].notes = notes.trim();
    _broadcast();
  }

  /// The group head id for a table — itself if it's a head/standalone, else
  /// the primary it's linked to.
  String _diningGroupHeadId(String tableId) {
    final s = diningSessionFor(tableId);
    if (s != null && s.isLinkedSecondary && s.primaryTableId != tableId) {
      return s.primaryTableId!;
    }
    return tableId;
  }

  /// Every table id in a table's joined party (the head + its linked seats).
  Set<String> _diningGroupIds(String tableId) {
    final head = _diningGroupHeadId(tableId);
    final headSession = diningSessionFor(head);
    return <String>{head, ...?headSession?.linkedTableIds};
  }

  /// Public lookup of a table definition by id — the floor plan resolves a
  /// linked seat's head label for the "Joined → …" badge.
  DiningTableDefinition? diningTableDefinitionById(String id) =>
      _findDiningTableDefinitionById(id);

  Future<void> openDiningTable(String tableId) async {
    if (tableTransitionInProgress) {
      _identityNotice(tableTransitionMessage);
      return;
    }
    return _duringTableTransition(() => _openDiningTable(tableId));
  }

  Future<void> _openDiningTable(String tableId) async {
    if (!await _combineMutationAllowed(insideTableTransition: true) ||
        isProcessingPayment) {
      return;
    }
    // Joined tables: tapping a linked seat opens the party's shared bill on
    // the group head, not the empty linked seat.
    final tapped = diningSessionFor(tableId);
    if (tapped != null &&
        tapped.isLinkedSecondary &&
        tapped.primaryTableId != tableId) {
      await _duringTableTransition(
        () => _openDiningTable(tapped.primaryTableId!),
      );
      return;
    }

    final definition = _findDiningTableDefinitionById(tableId);
    if (definition == null) return;

    if (activeDiningTableId != null && activeDiningTableId != tableId) {
      await _duringTableTransition(_returnToDiningFloorPlan);
    }

    final session = diningSessionFor(tableId);
    final canReuseCurrentCart =
        selectedOrderType == OrderType.dineIn &&
        activeDiningTableId == null &&
        _cart.isNotEmpty &&
        (session == null || session.status == DiningTableStatus.available);

    if (session != null &&
        !await _draftAllowed(
          uuid: session.serverOrderUuid ?? session.draft?.serverOrderUuid,
          tableId: tableId,
          reference: session.orderReference,
          occupiedAt: session.occupiedAt?.toIso8601String(),
          seatingKey: session.seatingKey,
        )) {
      return;
    }
    if (!_cartMutationAllowed(insideTableTransition: true)) return;

    if (!canReuseCurrentCart) _advanceOrderGeneration();
    selectedOrderType = OrderType.dineIn;
    activeDiningTableId = tableId;
    _activeDiningTableSeatingKey = session?.seatingKey;
    selectedDiningFloorId = definition.floorId;
    diningTableSearchQuery = '';
    productSearchQuery = '';
    paymentStatus = 'Waiting';
    selectedPaymentMethod = 'Cash';
    lastPaymentMessage = '';
    _splitPayments.clear();
    _splitPlanAmounts = null;
    _clearPaymentLaunchOverlay();
    _resetCharityRoundUp();

    if (session != null &&
        session.status == DiningTableStatus.occupied &&
        session.draft != null) {
      _dropCompForCartMutation();
      _cart
        ..clear()
        ..addAll(
          session.draft!.items.map((item) => CartItem.fromMap(item.toMap())),
        );
      currentOrderReference = session.orderReference.isNotEmpty
          ? session.orderReference
          : session.draft!.orderReference;
      selectedCategory = session.draft!.selectedCategory;
      _activeServerOrderUuid = session.draft!.serverOrderUuid.isEmpty
          ? null
          : session.draft!.serverOrderUuid;
      customerReferenceNumber = session.draft!.customerReferenceNumber;
      splitCount = session.draft!.splitCount;
      _splitPayments.clear();
      _splitPlanAmounts = null;
      displayNote = session.draft!.note.isNotEmpty
          ? session.draft!.note
          : _l10n.ctrlMsgEditingTableOnFloor(
              definition.name,
              _floorLabel(definition.floorId),
            );
      _restoreDraftDiscount(session.draft!);
    } else {
      if (!canReuseCurrentCart) {
        _dropCompForCartMutation();
        _cart.clear();
        selectedCategory = categories.first;
        customerReferenceNumber = '';
        vehiclePlateNumber = '';
        selectedCustomer = null;
        selectedEarnRuleIds = null;
        _clearLoyaltyRedemption();
        discount = const DiscountConfiguration();
        splitCount = 1;
        _splitPayments.clear();
        currentOrderReference = '';
        displayNote = _l10n.ctrlMsgAddItemsForTable(definition.name);
      } else if (displayNote.isEmpty) {
        displayNote = _l10n.ctrlMsgAssignItemsToTable(definition.name);
      }
    }

    _broadcast();
  }

  Future<void> returnToDiningFloorPlan() async {
    if (tableTransitionInProgress) {
      _identityNotice(tableTransitionMessage);
      return;
    }
    return _boundedTableAction(
      'returnToDiningFloorPlan',
      () => _duringTableTransition(() => _returnToDiningFloorPlan()),
    );
  }

  bool _reviewingSavedCopy = false;
  Future<void> returnForSavedCopyReview() async {
    if (tableTransitionInProgress ||
        isProcessingPayment ||
        hasRecordedSplitPayments) {
      return;
    }
    _reviewingSavedCopy = true;
    try {
      await _boundedTableAction(
        'clearActiveDiningTable',
        () => _duringTableTransition(_returnToDiningFloorPlan),
      );
    } finally {
      _reviewingSavedCopy = false;
    }
  }

  Future<void> _boundedTableAction(
    String name,
    Future<void> Function() operation,
  ) async {
    final inherited = TableActionDeadline.current;
    if (inherited != null) return operation();
    final deadline = TableActionDeadline(name);
    try {
      await deadline.run(operation);
    } on TimeoutException {
      _identityNotice(
        _l10n.localeName.startsWith('ar')
            ? 'استغرق التحقق من الطاولة وقتاً طويلاً. احتفظنا بالنسخة المحفوظة. أعد الاتصال ثم حاول مرة أخرى.'
            : 'The table check took too long. Your saved copy is kept. Reconnect and try again.',
      );
    }
  }

  Future<T> _tablePhase<T>(String phase, Future<T> Function() action) =>
      TableActionDeadline.current?.step(phase, action) ?? action();

  Future<void> _returnToDiningFloorPlan() => _boundedTableAction(
    'returnToDiningFloorPlan',
    _returnToDiningFloorPlanBody,
  );

  Future<void> _returnToDiningFloorPlanBody() async {
    if (!await _tablePhase(
      'combine_and_draft_guard',
      () => _combineMutationAllowed(insideTableTransition: true),
    )) {
      return;
    }
    if (selectedOrderType != OrderType.dineIn) return;

    final leavingTableId = activeDiningTableId;
    if (leavingTableId == null && _cart.isEmpty) return;
    _advanceOrderGeneration();
    await _tablePhase('persistence_flush', _flushActiveDiningTablePersistence);
    if (leavingTableId != null && !_reviewingSavedCopy) {
      diningTableSyncHooks?.onTableLeft(leavingTableId);
    }
    _resetForNextOrder(
      advanceOrderNumber: false,
      nextOrderType: OrderType.dineIn,
      clearActiveDiningTable: true,
      note: _l10n.ctrlMsgChooseTableDineIn,
    );
  }

  Future<void> _clearDiningGroup(Iterable<String> tableIds) async {
    final storage = _orderStorage;
    if (storage is AtomicDiningTableClear) {
      await (storage as AtomicDiningTableClear).clearDiningTables(tableIds);
    } else {
      for (final id in tableIds) {
        await storage.clearDiningTable(id);
      }
    }
  }

  Future<void> clearActiveDiningTable() =>
      _boundedTableAction('clearActiveDiningTable', _clearActiveDiningTable);

  Future<void> _clearActiveDiningTable() async {
    if (!await _tablePhase(
          'combine_and_draft_guard',
          _combineMutationAllowed,
        ) ||
        isProcessingPayment) {
      return;
    }
    final tableId = activeDiningTableId;
    if (tableId == null) return;

    _cancelPendingDiningTablePersistence();
    // Discarding the bill frees the whole joined party, not just the head.
    final groupIds = _diningGroupIds(tableId);
    final clearedHead = diningSessionFor(_diningGroupHeadId(tableId));
    await _tablePhase('persistence_clear', () => _clearDiningGroup(groupIds));
    for (final id in groupIds) {
      _diningHookOccupancies.remove(id);
    }
    diningTableSyncHooks?.onTablesCleared(groupIds, clearedHead);
    diningTableSessions = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere((session) => groupIds.contains(session.tableId));
    _resetForNextOrder(
      advanceOrderNumber: false,
      nextOrderType: OrderType.dineIn,
      clearActiveDiningTable: true,
      note: _l10n.ctrlMsgChooseTableDineIn,
    );
  }

  Future<void> clearDiningTableById(String tableId) => _boundedTableAction(
    'clearActiveDiningTable',
    () => _clearDiningTableById(tableId),
  );

  Future<void> _clearDiningTableById(String tableId) async {
    if (!await _tablePhase(
          'combine_and_draft_guard',
          _combineMutationAllowed,
        ) ||
        isProcessingPayment) {
      return;
    }
    // Resolve to the whole party (head + linked seats) so discarding any one
    // table frees the joined group together.
    final groupIds = _diningGroupIds(tableId);
    final clearedHead = diningSessionFor(_diningGroupHeadId(tableId));
    final clearsActive =
        activeDiningTableId != null && groupIds.contains(activeDiningTableId);
    if (clearsActive) {
      _cancelPendingDiningTablePersistence();
    }

    await _tablePhase('persistence_clear', () => _clearDiningGroup(groupIds));
    for (final id in groupIds) {
      _diningHookOccupancies.remove(id);
    }
    diningTableSyncHooks?.onTablesCleared(groupIds, clearedHead);
    diningTableSessions = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere((session) => groupIds.contains(session.tableId));

    if (clearsActive) {
      _resetForNextOrder(
        advanceOrderNumber: false,
        nextOrderType: OrderType.dineIn,
        clearActiveDiningTable: true,
        note: _l10n.ctrlMsgChooseTableDineIn,
      );
      return;
    }

    _notifySafely();
  }

  /// Gap sweep G2 — move an OCCUPIED table's session to a FREE table (the
  /// customer changed seats). Device-local, like the sessions themselves;
  /// the eventual order.create reads the table LIVE from the active
  /// definition, so the server needs no fixup. Returns the localized result
  /// message, or null when the preconditions fail (caller guards UI-side
  /// too). Floor-plan context only (no active table) — that sidesteps the
  /// debounced-persist race by construction.
  Future<String?> transferDiningTable(
    String fromTableId,
    String toTableId,
  ) async {
    if (tableTransitionInProgress) {
      _identityNotice(tableTransitionMessage);
      return lastPaymentMessage;
    }
    return _duringTableTransition(
      () => _transferDiningTable(fromTableId, toTableId),
    );
  }

  Future<String?> _transferDiningTable(
    String fromTableId,
    String toTableId,
  ) async {
    if (!await _combineMutationAllowed(insideTableTransition: true) ||
        isProcessingPayment) {
      return lastPaymentMessage;
    }
    if (activeDiningTableId != null || fromTableId == toTableId) return null;
    final source = diningSessionFor(fromTableId);
    final targetDef = _findDiningTableDefinitionById(toTableId);
    if (source == null ||
        source.status != DiningTableStatus.occupied ||
        source.draft == null ||
        targetDef == null ||
        diningSessionFor(toTableId) != null) {
      return null;
    }
    // A joined party can't be moved piecemeal — its seats stay linked.
    if (source.isLinkedSecondary || source.hasJoinedTables) return null;

    final sourceDef = _findDiningTableDefinitionById(fromTableId);
    final newDraft = source.draft!.copyWith(
      diningTableId: targetDef.id,
      diningTableName: targetDef.name,
      diningFloorId: targetDef.floorId,
      diningFloorLabel: _floorLabel(targetDef.floorId),
    );
    final moved = DiningTableSession(
      tableId: targetDef.id,
      floorId: targetDef.floorId,
      status: DiningTableStatus.occupied,
      updatedAt: DateTime.now(),
      orderNumber: source.orderNumber,
      orderReference: source.orderReference,
      occupiedAt: source.occupiedAt,
      draft: newDraft,
    );

    // Save target BEFORE deleting source (REPLACE is idempotent): a crash in
    // between duplicates a row, never loses the cart.
    _advanceOrderGeneration();
    await _orderStorage.saveDiningTableSession(moved);
    await _orderStorage.clearDiningTable(fromTableId);
    _diningHookOccupancies.remove(fromTableId);
    diningTableSyncHooks?.onTableTransferred(
      fromTableId,
      moved.copyWith(
        seatingKey: source.seatingKey,
        seatingUuid: source.seatingUuid,
        seatingState: source.seatingState,
        serverOrderUuid: source.serverOrderUuid,
        tempReference: source.tempReference,
        winnerSeatingUuid: source.winnerSeatingUuid,
        lastVerdict: source.lastVerdict,
        lastVerdictAt: source.lastVerdictAt,
      ),
    );
    diningTableSessions = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere(
        (s) => s.tableId == fromTableId || s.tableId == targetDef.id,
      )
      ..insert(0, moved);
    _notifySafely();

    return _l10n.ctrlMsgTableTransferred(
      sourceDef?.name ?? fromTableId,
      targetDef.name,
    );
  }

  /// "Join a free table" — pull a FREE neighbouring table into an OCCUPIED
  /// party so the whole group shares the party's ONE bill. This deliberately
  /// does NOT combine two separate orders: the [headTableId] party keeps its
  /// single order; [freeTableId] becomes a linked seat with no bill of its own,
  /// and both free together when the order is paid or discarded. The order the
  /// device sends still carries the head as its primary table_id plus the
  /// joined seats (see [joinedTableIdsFor]) so the merchant can see which
  /// tables the one order covered. If a linked seat id is passed for the head
  /// it resolves to that party's head, so you can keep adding tables to a party.
  Future<String?> joinDiningTables(
    String headTableId,
    String freeTableId,
  ) async {
    if (!await _combineMutationAllowed() || isProcessingPayment) {
      return lastPaymentMessage;
    }
    if (activeDiningTableId != null) return null;

    final head = _diningGroupHeadId(headTableId);
    if (head == freeTableId) return null;

    final headSession = diningSessionFor(head);
    final freeSession = diningSessionFor(freeTableId);
    final freeDef = _findDiningTableDefinitionById(freeTableId);
    // The party head must be occupied with a bill; the joined table must be
    // FREE (no session). Joining never merges two running orders.
    if (headSession == null ||
        headSession.status != DiningTableStatus.occupied ||
        headSession.draft == null ||
        freeDef == null ||
        freeSession != null) {
      return null;
    }
    final headDef = _findDiningTableDefinitionById(head);

    final now = DateTime.now();
    final linkedIds = <String>{
      ...headSession.linkedTableIds,
      freeTableId,
    }.toList();
    final updatedHead = headSession.copyWith(
      linkedTableIds: linkedIds,
      updatedAt: now,
    );
    final seat = DiningTableSession(
      tableId: freeTableId,
      floorId: freeDef.floorId,
      status: DiningTableStatus.occupied,
      updatedAt: now,
      orderReference: headSession.orderReference,
      occupiedAt: headSession.occupiedAt ?? now,
      draft: null,
      primaryTableId: head,
    );

    await _orderStorage.saveDiningTableSession(updatedHead);
    await _orderStorage.saveDiningTableSession(seat);
    diningTableSyncHooks?.onTablesJoined(updatedHead, seat);
    diningTableSessions = <DiningTableSession>[
      updatedHead,
      seat,
      ...diningTableSessions.where(
        (s) => s.tableId != head && s.tableId != freeTableId,
      ),
    ];
    _notifySafely();

    return _l10n.ctrlMsgTablesMerged(freeDef.name, headDef?.name ?? head);
  }

  /// The joined-seat ids (parsed to ints) for the party headed by [tableId] —
  /// the joined_table_ids the order payload carries so the server records which
  /// tables the one shared order covered. Empty for a standalone table. Read at
  /// order time BEFORE the paid-marking frees the seats (it clears the head's
  /// linkedTableIds the instant the order is marked paid).
  List<int> joinedTableIdsFor(String tableId) {
    final session = diningSessionFor(tableId);
    if (session == null || session.linkedTableIds.isEmpty) {
      return const <int>[];
    }
    return session.linkedTableIds.map(int.tryParse).whereType<int>().toList();
  }

  Future<void> openRearDisplay() async {
    if (!_presentationEnabled) return;

    try {
      rearDisplayOpened = await _presentation.openFirstRearDisplay();
      _notifySafely();
      if (rearDisplayOpened) {
        await Future.delayed(const Duration(milliseconds: 450));
        await syncRearDisplay();
        // Phase 3 — re-seed the freshly opened display with the current ad
        // loop so it isn't blank until the next catalog change.
        await _presentation.resendSlides();
      }
    } on MissingPluginException {
      _presentationEnabled = false;
      rearDisplayOpened = false;
    } catch (_) {
      rearDisplayOpened = false;
    }
  }

  Future<void> closeRearDisplay() async {
    if (!_presentationEnabled) return;

    try {
      await _presentation.closeRearDisplay();
    } on MissingPluginException {
      _presentationEnabled = false;
    } catch (_) {}

    rearDisplayOpened = false;
    _restoreRearDisplayAfterPayment = false;
    _notifySafely();
  }

  /// Returns false when the print failed (Phase G4) — the caller shows the
  /// right feedback instead of a false success.
  Future<bool> printOnly() async {
    if (_cart.isEmpty) return false;
    final ok = await SunmiReceiptService.printReceipt(
      snapshot(),
      template: receiptTemplate,
      tax: activeTaxSettings,
      branchName: receiptBranchName,
      branchNameAr: receiptBranchNameAr,
    );
    if (!ok) _reportPrintFailure('receipt');
    return ok;
  }

  Future<bool> printHistoricalReceipt(OrderHistoryRecord record) async {
    final ok = await SunmiReceiptService.printReceipt(
      record.snapshot,
      template: receiptTemplate,
      tax: activeTaxSettings,
      branchName: receiptBranchName,
      branchNameAr: receiptBranchNameAr,
      // LAUNCH-P4 C2 — a reprint shows the ORIGINAL order date and time.
      at: record.createdAt,
    );
    if (!ok) _reportPrintFailure('receipt');
    return ok;
  }

  /// Phase C1 — reprint the KITCHEN ticket for a past order. The caller is
  /// responsible for the manager gate (blueprint §6.10: kitchen ticket reprint
  /// requires Manager permission). Stamps the ORIGINAL order time + a REPRINT
  /// banner. Fail-safe (the service swallows printer errors); returns false
  /// on a print failure (Phase G4).
  Future<bool> printHistoricalKitchenTicket(OrderHistoryRecord record) async {
    final ok = await SunmiReceiptService.printKitchenTicket(
      _kitchenTicketFromSnapshot(
        record.snapshot,
        time: record.createdAt,
        isReprint: true,
      ),
    );
    if (!ok) _reportPrintFailure('kitchen');
    return ok;
  }

  /// 'Table 4 | Main Hall' — same composition the customer receipt uses.
  static String _composeTableLabel(String tableName, String floorLabel) {
    final table = tableName.trim();
    if (table.isEmpty) return '';
    final floor = floorLabel.trim();
    return floor.isEmpty ? 'Table $table' : 'Table $table | $floor';
  }

  KitchenTicketData _kitchenTicketFromSnapshot(
    OrderSnapshot s, {
    required DateTime time,
    bool isReprint = false,
  }) {
    return KitchenTicketData(
      orderLabel: 'Order ${s.displayOrderNumber}', // P-F8
      orderTypeLabel: OrderTypeLabel.fromStorage(s.orderType).label,
      tableLabel: _composeTableLabel(s.diningTableName, s.diningFloorLabel),
      // selectedDeliveryProvider is the LIVE order's pick — it is only valid
      // on the completion path (still set until the post-print reset). Past
      // orders never stored the provider, so reprints omit it.
      deliveryProvider:
          !isReprint && s.orderType == OrderType.delivery.storageValue
          ? (selectedDeliveryProvider?.name ?? '')
          : '',
      time: time,
      isReprint: isReprint,
      items: s.items,
    );
  }

  // ── Device↔device order transfer ────────────────────────────────────────────

  /// Send leg, step 1: binds the current cart to a stable server uuid and
  /// returns the draft the screen pushes as an `order.transfer` sync event.
  /// Null when there is nothing transferable. The uuid is KEPT on a failed
  /// push so a retry converges on the same pos_orders row.
  OrderSessionDraft? prepareTransferDraft() {
    if (!_cartMutationAllowed()) return null;
    if (_cart.isEmpty || isProcessingPayment) return null;
    return createDraft(serverOrderUuid: _activeServerOrderUuid ??= uuidV4());
  }

  /// Send leg, step 2 — the server ACCEPTED the transfer: the order now lives
  /// on the target device, so clear this cart for the next customer (the
  /// order number is NOT consumed — nothing was sold here). Returns false
  /// when a tender raced the push ACK: the cart is left untouched so the
  /// running payment keeps its lines and the screen surfaces the conflict.
  Future<bool> completeTransfer() async {
    if (!await _combineMutationAllowed()) return false;
    if (isProcessingPayment) return false;
    if (activeDiningTableId != null) {
      // The bill left this device with the order — free the whole party
      // (storage + sessions) and return to the floor plan; otherwise the
      // table stays occupied with a payable ghost copy of the transferred
      // order (its reopened draft has no server uuid → duplicate charge).
      await clearActiveDiningTable();
      return true;
    }
    _resetForNextOrder(advanceOrderNumber: false);
    return true;
  }

  /// Receive leg: loads a CLAIMED transfer into the cart — resumeHeldOrder's
  /// shape, but hydrated from the server snapshot instead of a local draft.
  /// Completion then pays against the SAME uuid, upserting the server's held
  /// row (never duplicating it). Returns false — cart untouched — when a
  /// tender is running or split legs are recorded (real money is mid-flight);
  /// the caller keeps the snapshot and retries once the console is idle.
  bool receiveTransferredOrder({
    required String orderUuid,
    required OrderType orderType,
    required List<CartItem> items,
  }) {
    if (!_cartMutationAllowed()) return false;
    if (isProcessingPayment || hasRecordedSplitPayments) return false;

    // Canonical reset FIRST so nothing from the previous cart (customer,
    // plate, loyalty redeem, comp, delivery facts, split, receipt number)
    // leaks into the received order; then load the snapshot on top. The
    // order number is not consumed — receiving is not a sale yet.
    _resetForNextOrder(
      advanceOrderNumber: false,
      nextOrderType: orderType,
      clearActiveDiningTable: true,
    );
    _cart.addAll(items);
    _activeServerOrderUuid = orderUuid.isEmpty ? null : orderUuid;
    _broadcast();
    return true;
  }

  Future<String?> holdCurrentOrder() async {
    if (_cart.isEmpty || isProcessingPayment) return null;
    // LAUNCH-P5 C7 — a training cart is never held (that would save it and
    // mirror it to the server).
    if (training) return _trainingRefusal();
    if (!await _combineMutationAllowed() || isProcessingPayment) {
      return lastPaymentMessage;
    }

    try {
      // Phase C2 — mint the server uuid at hold time (or keep the resumed
      // one) so the mirror, re-holds, the final order.create and a discard's
      // order.void all converge on one pos_orders row.
      _advanceOrderGeneration();
      final draft = createDraft(
        serverOrderUuid: _activeServerOrderUuid ??= uuidV4(),
      );
      await _orderStorage.saveHeldOrder(draft);
      await refreshHeldOrders();
      // Mirror server-side via the durable outbox (fire-and-forget).
      onOrderHeld?.call(draft);
      _activeServerOrderUuid = null; // consumed by the draft
      if (printKitchenTickets) {
        // Phase C1 — holding IS the "send to kitchen" moment today, so the
        // kitchen gets its ticket now (fail-safe; before the reset below so
        // the delivery-provider pick is still readable).
        final printed = await SunmiReceiptService.printKitchenTicket(
          KitchenTicketData(
            orderLabel: draft.orderReference.isEmpty
                ? 'Order #$currentOrderNumber'
                : draft.orderReference,
            orderTypeLabel: draft.orderType.label,
            tableLabel: _composeTableLabel(
              draft.diningTableName,
              draft.diningFloorLabel,
            ),
            deliveryProvider: draft.orderType == OrderType.delivery
                ? (selectedDeliveryProvider?.name ?? '')
                : '',
            time: DateTime.now(),
            isHold: true,
            items: draft.items.map((item) => item.toMap()).toList(),
          ),
        );
        if (!printed) _reportPrintFailure('kitchen');
      }
      final message = _l10n.ctrlMsgOrderHeld(draft.orderReference);
      _resetForNextOrder(advanceOrderNumber: false);
      lastPaymentMessage = message;
      displayNote = message;
      _broadcast();
      return message;
    } catch (error) {
      final message = _l10n.ctrlMsgHoldFailed;
      debugPrint('Failed to hold order: $error');
      lastPaymentMessage = message;
      displayNote = message;
      _notifySafely();
      return message;
    }
  }

  Future<String?> resumeHeldOrder(HeldOrderRecord record) async {
    if (isProcessingPayment) return null;
    if (!await _combineMutationAllowed() || isProcessingPayment) {
      return lastPaymentMessage;
    }
    if (!await _draftAllowed(
          uuid: record.draft.serverOrderUuid,
          tableId: record.draft.diningTableId,
          reference: record.orderReference,
        ) ||
        !_cartMutationAllowed()) {
      return lastPaymentMessage;
    }

    _advanceOrderGeneration();
    _dropCompForCartMutation();
    _cart
      ..clear()
      ..addAll(
        record.draft.items.map((item) => CartItem.fromMap(item.toMap())),
      );
    // Phase C2 — carry the held mirror's uuid into this cart so completion
    // (order.create) upserts the server's held row instead of duplicating it.
    _activeServerOrderUuid = record.draft.serverOrderUuid.isEmpty
        ? null
        : record.draft.serverOrderUuid;
    currentOrderReference = record.orderReference.isNotEmpty
        ? record.orderReference
        : record.draft.orderReference;
    selectedOrderType = record.draft.orderType;
    selectedCategory = record.draft.selectedCategory;
    customerReferenceNumber = record.draft.customerReferenceNumber;
    splitCount = record.draft.splitCount;
    _splitPayments.clear();
    _splitPlanAmounts = null;
    _reserveOrderNumber(currentOrderNumber);
    paymentStatus = 'Waiting';
    selectedPaymentMethod = 'Cash';
    displayNote = record.draft.note;
    lastPaymentMessage = '';
    _restoreDraftDiscount(record.draft);
    activeDiningTableId = record.draft.diningTableId.isEmpty
        ? null
        : record.draft.diningTableId;
    if (record.draft.diningFloorId.isNotEmpty) {
      selectedDiningFloorId = record.draft.diningFloorId;
    }
    _clearPaymentLaunchOverlay();
    _resetCharityRoundUp();
    await _orderStorage.deleteHeldOrder(record.id);
    await refreshHeldOrders();
    _broadcast();
    return _l10n.ctrlMsgOrderResumed(currentOrderReference);
  }

  /// Phase C2 — discard a held order (blueprint §6.7 "Cancel: voids the
  /// order"). Deletes the local draft and, when it was mirrored server-side,
  /// emits an order.void (an unpaid void has no inventory unwind) so the
  /// mirror leaves the branch's active list. The CALLER owns any
  /// confirmation / manager gate.
  Future<String> discardHeldOrder(
    HeldOrderRecord record, {
    ActionAuthorization? authorization,
  }) async {
    if (!await _combineMutationAllowed()) return lastPaymentMessage;
    if (!await _draftAllowed(
          uuid: record.draft.serverOrderUuid,
          tableId: record.draft.diningTableId,
          reference: record.orderReference,
        ) ||
        !_cartMutationAllowed()) {
      return lastPaymentMessage;
    }
    await _orderStorage.deleteHeldOrder(record.id);
    await refreshHeldOrders();
    final uuid = record.draft.serverOrderUuid;
    if (uuid.isNotEmpty) {
      onOrderVoided?.call(
        uuid,
        orderNumber: record.orderNumber,
        reason: 'Held order discarded',
        authorization: authorization,
      );
    }
    return _l10n.ctrlMsgHeldOrderDiscarded(record.orderReference);
  }

  Future<void> refreshOrderHistory() async {
    orderHistory = await _orderStorage.loadOrderHistory();
    _notifySafely();
  }

  /// Show the branch's server-authoritative order history (cross-device) instead
  /// of the device-local store. The screen calls this when online; offline it
  /// falls back to [refreshOrderHistory] (the local store). Records are marked
  /// fromServer, so their cancel action is disabled.
  void applyServerOrderHistory(List<OrderHistoryRecord> records) {
    orderHistory = records;
    _notifySafely();
  }

  Future<void> refreshHeldOrders() async {
    heldOrders = await _orderStorage.loadHeldOrders();
    _notifySafely();
  }

  Future<void> refreshDiningTables() async {
    diningTableSessions = await _orderStorage.loadDiningTableSessions();
    _notifySafely();
  }

  Future<String> cancelCompletedOrder(
    OrderHistoryRecord record, {
    required bool cancelFullOrder,
    required Set<int> itemIndexes,
    // Phase B — the picked void reason (required by the dialog when the
    // company has reason codes). Threaded onto the order.void event.
    VoidReasonRef? voidReason,
    // LAUNCH-P5 C1 — the order.void_paid gate (own tick or an approver).
    ActionAuthorization? authorization,
  }) async {
    final snapshot = record.snapshot;
    final authorizedBy = authorization?.authorizedByName ?? 'Manager';
    if (snapshot.isFullyCanceled || record.isServerTerminal) {
      return _l10n.ctrlMsgOrderAlreadyCanceled(record.orderNumber);
    }

    // P-F1 — a server-history record (cross-device) cancels FULL-ORDER only:
    // the wire supports a whole-order order.void, pos_api's handler is
    // branch-scoped (any device of the branch may void), and the record
    // lives in memory, not in this device's local store.
    if (record.fromServer) {
      if (!cancelFullOrder) return _l10n.ctrlMsgNoCancellableItems;
      final serverUuid = snapshot.serverOrderUuid;
      if (serverUuid.isEmpty) return _l10n.ctrlMsgNoCancellableItems;

      final now = DateTime.now();
      final updatedSnapshot = snapshot.copyWith(
        paymentStatus: 'Canceled',
        note: _l10n.ctrlMsgOrderCanceledByManagerNote,
        cancellations: [
          ...snapshot.cancellations,
          OrderCancellationRecord(
            id: 'cancel_${record.orderNumber}_${now.microsecondsSinceEpoch}',
            fullOrder: true,
            itemName: 'Full order',
            quantity: snapshot.items.fold<int>(
              0,
              (sum, item) => sum + ((item['qty'] as num?)?.toInt() ?? 0),
            ),
            amount: snapshot.payableTotal,
            canceledAt: now,
            authorizedBy: authorizedBy,
          ),
        ],
      );
      final updatedRecord = OrderHistoryRecord(
        id: record.id,
        orderNumber: record.orderNumber,
        orderType: record.orderType,
        createdAt: record.createdAt,
        snapshot: updatedSnapshot,
        fromServer: true,
      );
      orderHistory = [
        for (final r in orderHistory) r.id == record.id ? updatedRecord : r,
      ];
      _notifySafely();

      onOrderVoided?.call(
        serverUuid,
        orderNumber: record.orderNumber,
        reason: voidReason?.name ?? 'Canceled by manager at POS',
        voidReasonId: voidReason?.id,
        authorization: authorization,
      );
      return _l10n.ctrlMsgOrderFullyCanceled(record.orderNumber);
    }

    final now = DateTime.now();
    final existingCancellations = List<OrderCancellationRecord>.from(
      snapshot.cancellations,
    );
    final newCancellations = <OrderCancellationRecord>[];

    if (cancelFullOrder) {
      final remainingAmount = _roundMoney(
        (snapshot.payableTotal - snapshot.canceledAmount)
            .clamp(0.0, double.infinity)
            .toDouble(),
      );
      final quantity = snapshot.items.fold<int>(
        0,
        (sum, item) => sum + ((item['qty'] as num?)?.toInt() ?? 0),
      );

      newCancellations.add(
        OrderCancellationRecord(
          id: 'cancel_${record.orderNumber}_${now.microsecondsSinceEpoch}',
          fullOrder: true,
          itemName: 'Full order',
          quantity: quantity,
          amount: remainingAmount > 0 ? remainingAmount : snapshot.payableTotal,
          canceledAt: now,
          authorizedBy: authorizedBy,
        ),
      );
    } else {
      final alreadyCanceled = snapshot.canceledItemIndexes;
      final sortedIndexes = itemIndexes.toList()..sort();

      for (final itemIndex in sortedIndexes) {
        if (itemIndex < 0 || itemIndex >= snapshot.items.length) continue;
        if (alreadyCanceled.contains(itemIndex)) continue;

        final item = snapshot.items[itemIndex];
        final quantity = (item['qty'] as num?)?.toInt() ?? 1;
        final amount = _snapshotItemCancellationAmount(snapshot, item);

        newCancellations.add(
          OrderCancellationRecord(
            id: 'cancel_${record.orderNumber}_${itemIndex}_${now.microsecondsSinceEpoch}',
            fullOrder: false,
            itemIndex: itemIndex,
            itemName: item['name']?.toString() ?? 'Item ${itemIndex + 1}',
            quantity: quantity,
            amount: amount,
            canceledAt: now,
            authorizedBy: authorizedBy,
          ),
        );
      }
    }

    if (newCancellations.isEmpty) {
      return _l10n.ctrlMsgNoCancellableItems;
    }

    final updatedCancellations = [
      ...existingCancellations,
      ...newCancellations,
    ];
    final updatedSnapshot = snapshot.copyWith(
      paymentStatus: cancelFullOrder ? 'Canceled' : 'Partially Canceled',
      note: cancelFullOrder
          ? _l10n.ctrlMsgOrderCanceledByManagerNote
          : _l10n.ctrlMsgItemsCanceledByManagerNote(newCancellations.length),
      cancellations: updatedCancellations,
    );
    final updatedRecord = OrderHistoryRecord(
      id: record.id,
      orderNumber: record.orderNumber,
      orderType: record.orderType,
      createdAt: record.createdAt,
      snapshot: updatedSnapshot,
    );

    await _orderStorage.updateCompletedOrder(updatedRecord);
    await refreshOrderHistory();

    if (cancelFullOrder) {
      // Mirror the cancellation to pos_api: a full cancel of an order that was
      // pushed (has a server uuid + isn't a server-history record) emits an
      // order.void so the backend unwinds its inventory / loyalty / round-up /
      // commission. Local-only when there's no server uuid (e.g. demo orders).
      final serverUuid = snapshot.serverOrderUuid;
      if (serverUuid.isNotEmpty && !record.fromServer) {
        onOrderVoided?.call(
          serverUuid,
          orderNumber: record.orderNumber,
          reason: voidReason?.name ?? 'Canceled by manager at POS',
          voidReasonId: voidReason?.id,
          authorization: authorization,
        );
      }
      return _l10n.ctrlMsgOrderFullyCanceled(record.orderNumber);
    }
    return _l10n.ctrlMsgItemsCanceledFromOrder(
      newCancellations.length,
      record.orderNumber,
    );
  }

  /// P-G7 — complete a delivery-provider order with NO tender. The
  /// provider's order number is required; the order finalizes as PENDING
  /// VERIFICATION (prints + saves + pushes order.create + order.deliver,
  /// never order.pay) and only becomes a sale when the merchant reconciles
  /// the provider's statement on the portal Deliveries page.
  Future<String?> completeDeliveryOrder({
    required String reference,
    String customerPhone = '',
    String driverPhone = '',
  }) async {
    final customerRefusal = customerTenderRefusal();
    if (customerRefusal != null) return customerRefusal;
    final loyaltyRefusal = _guardLoyaltyTender();
    if (loyaltyRefusal != null) return loyaltyRefusal;
    if (_cart.isEmpty || isProcessingPayment) return null;
    if (selectedOrderType != OrderType.delivery ||
        selectedDeliveryProviderId == null) {
      return null;
    }
    final trimmedReference = reference.trim();
    if (trimmedReference.isEmpty) return null;
    _freezeTenderPrice();
    isProcessingPayment = true;
    try {
      if (!await _combineMutationAllowed()) return lastPaymentMessage;

      // Freeze the provider NOW — a config refresh during the allocation
      // await below can drop selectedDeliveryProviderId (provider deleted
      // on the portal mid-sale), and the punched order must keep the
      // provider the cashier actually chose.
      _punchedDeliveryProviderId = selectedDeliveryProviderId;
      _punchedDeliveryProviderName = selectedDeliveryProvider?.name ?? '';

      _resetCharityRoundUp();
      _clearPaymentLaunchOverlay();
      lastPaymentMessage = '';

      // P-F8 — a punched delivery order is a real order with a printed
      // ticket, so it takes a sequential number like any tendered sale
      // (same short fuse + offline fallback as payAndPrint).
      if (orderNumbering.enabled &&
          receiptNumber.isEmpty &&
          allocateReceiptNumber != null) {
        try {
          final allocated = await allocateReceiptNumber!().timeout(
            const Duration(seconds: 3),
          );
          if (allocated != null) receiptNumber = allocated.formatted;
        } catch (_) {
          // Offline / timeout / refused — the local number stands.
        }
      }

      deliveryReference = trimmedReference;
      deliveryDriverPhone = driverPhone.replaceAll(RegExp(r'\D'), '').trim();
      selectedPaymentMethod = 'Delivery';
      paymentStatus = 'Pending verification';
      lastPaymentMessage = _l10n.ctrlMsgDeliveryRecorded;
      displayNote = _l10n.ctrlMsgDeliveryCompleted;
      _broadcast();

      return await _finishCompletedOrder(
        isDineInPayment: false,
        successMessage: lastPaymentMessage,
      );
    } finally {
      isProcessingPayment = false;
      _releaseTenderPrice();
    }
  }

  Future<String?> payAndPrint({double? cashTenderedAmount}) =>
      DeviceHeartbeat.trackTender(
        () => _payAndPrintAdmitted(cashTenderedAmount: cashTenderedAmount),
      );
  Future<String?> _payAndPrintAdmitted({double? cashTenderedAmount}) async {
    final customerRefusal = customerTenderRefusal(
      gift: selectedPaymentMethod == 'Gift',
    );
    if (customerRefusal != null) return customerRefusal;
    final loyaltyRefusal = _guardLoyaltyTender();
    if (loyaltyRefusal != null) return loyaltyRefusal;
    if (_cart.isEmpty || isProcessingPayment) return null;
    // LAUNCH-P5 C7 — no card, SoftPOS, bank terminal or gift in training.
    if (training && selectedPaymentMethod != 'Cash') {
      lastPaymentMessage = _l10n.trainingCashOnly;
      displayNote = lastPaymentMessage;
      _notifySafely();
      return lastPaymentMessage;
    }

    final transactionMethod = selectedPaymentMethod;
    final transactionSplitCount = splitCount;
    final transactionSplitIndex = activeSplitIndex;
    _reservedDiningBill = null;
    var transactionBaseAmount = activePaymentBaseTotal;
    final isDineInPayment =
        selectedOrderType == OrderType.dineIn && activeDiningTableId != null;

    _resetCharityRoundUp();
    _clearPaymentLaunchOverlay();
    _freezeTenderPrice();
    isProcessingPayment = true;
    lastPaymentMessage = '';

    if (!await _combineMutationAllowed()) {
      isProcessingPayment = false;
      _releaseTenderPrice();
      return lastPaymentMessage;
    }

    if (isDineInPayment && isLiveSharedTable?.call() == true) {
      String? refusal;
      try {
        refusal = verifyDiningTableTender == null
            ? 'Could not verify the table bill. Reconnect and try again.'
            : await verifyDiningTableTender!();
        if (refusal == null && prepareDiningTableTender != null) {
          _reservedDiningBill = await prepareDiningTableTender!(
            cashTenderedAmount,
          );
          transactionBaseAmount = activePaymentBaseTotal;
          if (cashTenderedAmount != null &&
              selectedPaymentMethod == 'Cash' &&
              cashTenderedAmount + 0.0005 < transactionBaseAmount) {
            refusal =
                'The bill changed. Check payment result before taking cash.';
          }
        }
      } catch (_) {
        refusal = 'Could not verify the table bill. Reconnect and try again.';
      }
      if (refusal != null) {
        isProcessingPayment = false;
        _releaseTenderPrice();
        paymentStatus = 'Payment blocked';
        lastPaymentMessage = refusal;
        displayNote = refusal;
        _notifySafely();
        return refusal;
      }
    }

    // P-F8 — merchant order numbering: allocate the official sequential
    // number ONCE per order (the first tender of a split wins), short-fused
    // so an offline/slow till never stalls the sale — the fallback is the
    // device-local number (receiptNumber stays '').
    if (!(isDineInPayment && isLiveSharedTable?.call() == true) &&
        orderNumbering.enabled &&
        receiptNumber.isEmpty &&
        allocateReceiptNumber != null) {
      try {
        final allocated = await allocateReceiptNumber!().timeout(
          const Duration(seconds: 3),
        );
        if (allocated != null) receiptNumber = allocated.formatted;
      } catch (_) {
        // Offline / timeout / refused — the local number stands.
      }
    }

    try {
      if (canOfferCharityRoundUp) {
        final accepted = await _promptForCharityRoundUp();
        if (accepted == null) {
          // 'Credit Card' shortens to 'Card' in this message (original copy).
          final paymentLabel = transactionMethod == 'Credit Card'
              ? _l10n.displayMethodCardShort
              : localizedPaymentMethod(_l10n, transactionMethod);
          _clearPaymentLaunchOverlay();
          paymentStatus = 'Payment canceled';
          lastPaymentMessage = _charityPromptCanceled
              ? _l10n.ctrlMsgPaymentCanceledWithMethod(paymentLabel)
              : _l10n.ctrlMsgCustomerResponseTimeout;
          displayNote = lastPaymentMessage;
          _broadcast();
          return lastPaymentMessage;
        }
      }

      if (transactionMethod == 'Cash') {
        _clearPaymentLaunchOverlay();
        if (charityRoundUpAccepted &&
            cashTenderedAmount != null &&
            cashTenderedAmount + 0.0005 < payableTotal) {
          _clearPaymentLaunchOverlay();
          paymentStatus = 'Payment canceled';
          lastPaymentMessage = _l10n.ctrlMsgTenderedCashTooLow(
            SunmiReceiptService.money(payableTotal),
          );
          displayNote = lastPaymentMessage;
          _broadcast();
          return lastPaymentMessage;
        }

        paymentStatus = 'Processing payment';
        displayNote = transactionSplitCount > 1
            ? _l10n.ctrlMsgCashierCompletingSplitCash(
                transactionSplitIndex,
                transactionSplitCount,
              )
            : _l10n.ctrlMsgCashierCompletingCash;
        paymentOverlayTitle = '';
        _broadcast();

        paymentStatus = 'Paid';
        lastPaymentMessage = _l10n.ctrlMsgCashPaymentRecorded;
        displayNote = _l10n.ctrlMsgCashPaymentCompleted;
        _broadcast();

        return await _completeSuccessfulPayment(
          transactionMethod: transactionMethod,
          splitCountAtPayment: transactionSplitCount,
          splitIndexAtPayment: transactionSplitIndex,
          baseAmount: transactionBaseAmount,
          isDineInPayment: isDineInPayment,
          successMessage: lastPaymentMessage,
        );
      }

      // P-F5 — BANK POS: the customer paid on the bank's standalone card
      // terminal; the device only RECORDS it (no Mosambee launch, exact
      // amount, no change). Must run before the card path below. The wire
      // method is 'bank_pos' — deliberately NOT card money, so the bank
      // commission slice stays with the merchant.
      if (transactionMethod == 'Bank POS') {
        _clearPaymentLaunchOverlay();
        paymentStatus = 'Processing payment';
        displayNote = _l10n.ctrlMsgBankPosRecording;
        _broadcast();

        paymentStatus = 'Paid';
        lastPaymentMessage = _l10n.ctrlMsgBankPosRecorded;
        displayNote = _l10n.ctrlMsgBankPosCompleted;
        _broadcast();

        return await _completeSuccessfulPayment(
          transactionMethod: transactionMethod,
          splitCountAtPayment: transactionSplitCount,
          splitIndexAtPayment: transactionSplitIndex,
          baseAmount: transactionBaseAmount,
          isDineInPayment: isDineInPayment,
          successMessage: lastPaymentMessage,
        );
      }

      // Phase D4 (blueprint §6.8) — GIFT: the whole order gifted, zero
      // charged. Mirrors the cash path (no tender/change validation, no
      // round-up — canOfferCharityRoundUp already excludes it) and must run
      // BEFORE the card path below, which launches a real Mosambee charge.
      // The screen owns the manager gate; the wire tender is method 'gift'
      // at the full grand total (the server validates Σ(tendered)==grand).
      if (transactionMethod == 'Gift') {
        _clearPaymentLaunchOverlay();
        paymentStatus = 'Paid';
        lastPaymentMessage = _l10n.ctrlMsgGiftRecorded;
        displayNote = _l10n.ctrlMsgGiftCompleted;
        _broadcast();

        return await _completeSuccessfulPayment(
          transactionMethod: transactionMethod,
          splitCountAtPayment: transactionSplitCount,
          splitIndexAtPayment: transactionSplitIndex,
          baseAmount: transactionBaseAmount,
          isDineInPayment: isDineInPayment,
          successMessage: lastPaymentMessage,
        );
      }

      debugPrint(
        'PosController invoking Mosambee loginAndPay with amount=${payableTotal.toStringAsFixed(3)}',
      );

      final (cardOutcome, paymentResult) = await _runCardCharge(
        amount: payableTotal,
        processingNote: charityRoundUpAccepted
            ? _l10n.ctrlMsgTapToPayRoundUp
            : _l10n.ctrlMsgTapToPay,
      );

      // Uncertain charge force-recorded by the cashier (settles against the bank
      // file via the admin queue) so the sale isn't lost.
      if (cardOutcome == _CardChargeOutcome.recordPending) {
        _clearPaymentLaunchOverlay();
        paymentStatus = 'Paid (pending reconciliation)';
        lastPaymentMessage = _l10n.ctrlMsgCardPendingReconRecorded;
        displayNote = _l10n.ctrlMsgPaymentPendingBankThanks;
        _broadcast();

        // Re-warm a login session for the next card sale.
        prewarmCardPayment();

        return await _completeSuccessfulPayment(
          transactionMethod: transactionMethod,
          splitCountAtPayment: transactionSplitCount,
          splitIndexAtPayment: transactionSplitIndex,
          baseAmount: transactionBaseAmount,
          isDineInPayment: isDineInPayment,
          successMessage: lastPaymentMessage,
          cardCharge: _cardChargeFromResult(
            paymentResult,
            status: 'pending_reconciliation',
          ),
        );
      }

      if (cardOutcome == _CardChargeOutcome.aborted) {
        _clearPaymentLaunchOverlay();
        paymentStatus = paymentResult.isCanceled
            ? 'Payment canceled'
            : 'Payment failed';
        lastPaymentMessage = _cardFailureMessage(paymentResult);
        displayNote = lastPaymentMessage;
        _broadcast();
        return lastPaymentMessage;
      }

      _clearPaymentLaunchOverlay();
      paymentStatus = 'Paid';
      lastPaymentMessage = charityRoundUpAccepted
          ? _l10n.ctrlMsgCardApprovedRoundUpThanks(paymentResult.userMessage)
          : paymentResult.userMessage;
      displayNote = charityRoundUpAccepted
          ? _l10n.ctrlMsgPaymentApprovedRoundUpNote
          : _l10n.ctrlMsgPaymentApprovedNote;
      _broadcast();

      // Re-warm a login session for the next card sale.
      prewarmCardPayment();

      return await _completeSuccessfulPayment(
        transactionMethod: transactionMethod,
        splitCountAtPayment: transactionSplitCount,
        splitIndexAtPayment: transactionSplitIndex,
        baseAmount: transactionBaseAmount,
        isDineInPayment: isDineInPayment,
        successMessage: lastPaymentMessage,
        cardCharge: _cardChargeFromResult(paymentResult),
      );
    } finally {
      _clearPaymentLaunchOverlay();
      isProcessingPayment = false;
      _releaseTenderPrice();
      _broadcast();
      await _restoreRearDisplayAfterPaymentIfNeeded();
    }
  }

  Future<String?> payMixedCashAndCard({required double cashAmount}) =>
      DeviceHeartbeat.trackTender(
        () => _payMixedCashAndCardAdmitted(cashAmount: cashAmount),
      );
  Future<String?> _payMixedCashAndCardAdmitted({
    required double cashAmount,
  }) async {
    final customerRefusal = customerTenderRefusal();
    if (customerRefusal != null) return customerRefusal;
    final loyaltyRefusal = _guardLoyaltyTender();
    if (loyaltyRefusal != null) return loyaltyRefusal;
    if (_cart.isEmpty || isProcessingPayment) return null;

    if (splitCount > 1 || hasRecordedSplitPayments) {
      paymentStatus = 'Payment canceled';
      lastPaymentMessage = _l10n.ctrlMsgClearSplitBillFirst;
      displayNote = lastPaymentMessage;
      _broadcast();
      return lastPaymentMessage;
    }

    final isDineInPayment =
        selectedOrderType == OrderType.dineIn && activeDiningTableId != null;
    final billTotal = total;
    final cashShare = _roundMoney(cashAmount);
    final cardBaseAmount = _roundMoney(billTotal - cashShare);

    if (cashShare <= 0 || cardBaseAmount <= 0) {
      paymentStatus = 'Payment canceled';
      lastPaymentMessage = _l10n.ctrlMsgEnterCashBelowTotal(
        SunmiReceiptService.money(billTotal),
      );
      displayNote = lastPaymentMessage;
      _broadcast();
      return lastPaymentMessage;
    }

    _resetCharityRoundUp();
    _clearPaymentLaunchOverlay();
    _activePaymentBaseOverride = cardBaseAmount;
    selectedPaymentMethod = 'Credit Card';
    _freezeTenderPrice();
    isProcessingPayment = true;
    lastPaymentMessage = '';
    if (!await _combineMutationAllowed()) {
      isProcessingPayment = false;
      _releaseTenderPrice();
      _activePaymentBaseOverride = null;
      return lastPaymentMessage;
    }

    try {
      if (canOfferCharityRoundUp) {
        final accepted = await _promptForCharityRoundUp();
        if (accepted == null) {
          _clearPaymentLaunchOverlay();
          paymentStatus = 'Payment canceled';
          lastPaymentMessage = _charityPromptCanceled
              ? _l10n.ctrlMsgSplitPaymentCanceled
              : _l10n.ctrlMsgCustomerResponseTimeout;
          displayNote = lastPaymentMessage;
          _broadcast();
          return lastPaymentMessage;
        }
      }

      debugPrint(
        'PosController invoking Mosambee split card payment with amount=${payableTotal.toStringAsFixed(3)}',
      );

      final (cardOutcome, paymentResult) = await _runCardCharge(
        amount: payableTotal,
        processingNote: charityRoundUpAccepted
            ? _l10n.ctrlMsgTapForRemainingSplitRoundUp
            : _l10n.ctrlMsgTapForRemainingSplit,
      );

      // Cashier canceled the unconfirmed card leg (or it hard-failed) → abort the
      // whole split.
      if (cardOutcome == _CardChargeOutcome.aborted) {
        _clearPaymentLaunchOverlay();
        paymentStatus = paymentResult.isCanceled
            ? 'Payment canceled'
            : 'Payment failed';
        lastPaymentMessage = _cardFailureMessage(paymentResult);
        displayNote = lastPaymentMessage;
        _broadcast();
        return lastPaymentMessage;
      }

      final cardChargeStatus = cardOutcome == _CardChargeOutcome.recordPending
          ? 'pending_reconciliation'
          : 'success';

      final cardPaidAmount = payableTotal;
      final cardRoundUpAmount = charityRoundUpAccepted
          ? charityRoundUpAmount
          : 0.0;

      splitCount = 2;
      _splitPayments
        ..clear()
        ..add(
          SplitPaymentRecord(
            splitIndex: 1,
            splitCount: 2,
            paymentMethod: 'Cash',
            baseAmount: cashShare,
            charityRoundUpAccepted: false,
            charityRoundUpAmount: 0,
            paidAmount: cashShare,
            paidAt: DateTime.now(),
          ),
        )
        ..add(
          SplitPaymentRecord(
            splitIndex: 2,
            splitCount: 2,
            paymentMethod: 'Credit Card',
            baseAmount: cardBaseAmount,
            charityRoundUpAccepted: charityRoundUpAccepted,
            charityRoundUpAmount: cardRoundUpAmount,
            paidAmount: cardPaidAmount,
            paidAt: DateTime.now(),
            cardCharge: _cardChargeFromResult(
              paymentResult,
              status: cardChargeStatus,
            ),
          ),
        );

      final cardPending = cardChargeStatus == 'pending_reconciliation';
      _clearPaymentLaunchOverlay();
      paymentStatus = cardPending ? 'Paid (pending reconciliation)' : 'Paid';
      selectedPaymentMethod = 'Split Payment';
      lastPaymentMessage = cardPending
          ? _l10n.ctrlMsgSplitRecordedCardPending(
              SunmiReceiptService.money(cashShare),
              SunmiReceiptService.money(cardPaidAmount),
            )
          : _l10n.ctrlMsgSplitCompletedCashCard(
              SunmiReceiptService.money(cashShare),
              SunmiReceiptService.money(cardPaidAmount),
            );
      displayNote = cardPending
          ? _l10n.ctrlMsgCashReceivedCardPendingNote
          : charityRoundUpAccepted
          ? _l10n.ctrlMsgSplitCompletedRoundUpNote
          : _l10n.ctrlMsgSplitCompletedNote;
      _broadcast();

      // Re-warm a login session for the next card sale.
      prewarmCardPayment();

      return await _finishCompletedOrder(
        isDineInPayment: isDineInPayment,
        successMessage: lastPaymentMessage,
      );
    } finally {
      _activePaymentBaseOverride = null;
      _clearPaymentLaunchOverlay();
      isProcessingPayment = false;
      _releaseTenderPrice();
      _broadcast();
      await _restoreRearDisplayAfterPaymentIfNeeded();
    }
  }

  /// Build the Soft POS evidence object from a Mosambee result. [status] is the
  /// pos_api Payment status — 'success', or 'pending_reconciliation' when the
  /// cashier force-records an unconfirmed (e.g. NFC-timeout) charge.
  CardCharge _cardChargeFromResult(
    MosambeePaymentResult result, {
    String status = 'success',
  }) {
    return CardCharge(
      softposReference: result.softposReference,
      softposAuthCode: result.softposAuthCode,
      bankResponse: result.payload,
      transactionId: result.identifiers.transactionId,
      rrn: result.identifiers.rrn,
      authCode: result.identifiers.authCode,
      status: status,
    );
  }

  Future<String> _completeSuccessfulPayment({
    required String transactionMethod,
    required int splitCountAtPayment,
    required int splitIndexAtPayment,
    required double baseAmount,
    required bool isDineInPayment,
    required String successMessage,
    CardCharge? cardCharge,
  }) async {
    if (splitCountAtPayment > 1) {
      final paidAmount = payableTotal;
      final roundUpAmount = charityRoundUpAccepted ? charityRoundUpAmount : 0.0;

      _splitPayments.add(
        SplitPaymentRecord(
          splitIndex: splitIndexAtPayment,
          splitCount: splitCountAtPayment,
          paymentMethod: transactionMethod,
          baseAmount: baseAmount,
          charityRoundUpAccepted: charityRoundUpAccepted,
          charityRoundUpAmount: roundUpAmount,
          paidAmount: paidAmount,
          paidAt: DateTime.now(),
          cardCharge: cardCharge,
        ),
      );

      if (_splitPayments.length < splitCountAtPayment) {
        final nextSplitIndex = _splitPayments.length + 1;
        _resetCharityRoundUp();
        _clearPaymentLaunchOverlay();
        paymentStatus = 'Split payment pending';
        lastPaymentMessage = _l10n.ctrlMsgSplitProgressRecorded(
          splitIndexAtPayment,
          splitCountAtPayment,
          nextSplitIndex,
        );
        displayNote = _l10n.ctrlMsgGuestPaidCollectNext(
          splitIndexAtPayment,
          SunmiReceiptService.money(paidAmount),
          nextSplitIndex,
          splitCountAtPayment,
        );
        _broadcast();
        return lastPaymentMessage;
      }

      _clearPaymentLaunchOverlay();
      paymentStatus = 'Paid';
      selectedPaymentMethod = 'Split Payment';
      lastPaymentMessage = _l10n.ctrlMsgSplitCompletedSummary(
        splitCountAtPayment,
        SunmiReceiptService.money(_splitPaidTotal),
      );
      displayNote = _l10n.ctrlMsgSplitBillCompletedNote(splitCountAtPayment);
      _broadcast();

      return await _finishCompletedOrder(
        isDineInPayment: isDineInPayment,
        successMessage: lastPaymentMessage,
      );
    }

    // Single (non-split) payment: the card evidence (if any) rides on the
    // order via the bridge, which reads lastCardCharge synchronously.
    _lastCardCharge = cardCharge;

    return await _finishCompletedOrder(
      isDineInPayment: isDineInPayment,
      successMessage: successMessage,
    );
  }

  Future<String> _finishCompletedOrder({
    required bool isDineInPayment,
    required String successMessage,
  }) async {
    final paid = snapshot().copyWith(
      serverOrderUuid: _activeServerOrderUuid ?? uuidV4(),
    );
    Future<void> preserve() => BusinessBoundary.quarantine(
      'paid-sale-completion',
      paid.serverOrderUuid,
      {
        'identity': _businessIdentity,
        'snapshot': paid.toMap(),
        'card_charge': _lastCardCharge?.toMap(),
        // A live table is charged from the server's reserved bill, under its
        // canonical bill uuid, not from the local cart.
        if (_reservedDiningBill != null) 'reserved_bill': _reservedDiningBill,
        if (_paidSaleKey != null) 'bill_uuid': _paidSaleKey,
      },
    );
    if (!BusinessBoundary.owns(_businessIdentity)) {
      await preserve();
      _resetForNextOrder(
        advanceOrderNumber: !isDineInPayment,
        clearActiveDiningTable: true,
      );
      return successMessage;
    }
    // A captured tender must finish durably even if access was suspended
    // while the bank/cash confirmation was in progress.
    _paidSaleQueued = false;
    _paidSaleKey = null;
    try {
      return await BusinessBoundary.persistPaid(
        _businessIdentity,
        () => _finishCompletedOrderAdmitted(
          isDineInPayment: isDineInPayment,
          successMessage: successMessage,
        ),
      );
    } catch (error) {
      // The money is already taken. Whatever failed (local storage, the
      // outbox write, the live-table journal), the paid sale must stay
      // durable, the cashier must be told, and the till must be free for the
      // next customer.
      debugPrint('Paid sale completion failed: $error');
      var durable = _paidSaleQueued;
      final key = _paidSaleKey;
      if (!durable && key != null && paidSaleDurable != null) {
        try {
          durable = await paidSaleDurable!(key);
        } catch (_) {
          // Unknown stays "not saved": evidence is kept instead.
        }
      }
      if (!durable) await preserve();
      _resetForNextOrder(
        advanceOrderNumber: !isDineInPayment,
        clearActiveDiningTable: true,
      );
      lastPaymentMessage = durable
          ? successMessage
          : _l10n.ctrlMsgPaidSaleKeptForReview;
      displayNote = lastPaymentMessage;
      _broadcast();
      return lastPaymentMessage;
    }
  }

  /// Set once the paid sale is durable for sending (the outbox for a local
  /// sale, the table journal for a live shared table).
  bool _paidSaleQueued = false;

  /// The outbox key of the sale being completed, once it is final.
  String? _paidSaleKey;

  /// LAUNCH-P5 C7 — training mode (set by the screen). A training sale is
  /// printed as "TRAINING — NOT A RECEIPT", kept only in the separate
  /// [TrainingOrderStore], never saved to the history, never queued for the
  /// server, never sent to the kitchen and never moves stock.
  bool training = false;

  String _trainingRefusal() {
    lastPaymentMessage = _l10n.trainingNotAvailable;
    displayNote = lastPaymentMessage;
    _notifySafely();
    return lastPaymentMessage;
  }

  Future<String> _finishTrainingOrder({required String successMessage}) async {
    final completed = snapshot().copyWith(
      serverOrderUuid: uuidV4(),
      training: true,
      authorizations: const <Map<String, dynamic>>[],
    );
    _forgetOrderAuthorizations();
    if (printReceipts) {
      final ok = await SunmiReceiptService.printReceipt(
        completed,
        template: receiptTemplate,
        tax: activeTaxSettings,
        branchName: receiptBranchName,
        branchNameAr: receiptBranchNameAr,
      );
      if (!ok) _reportPrintFailure('receipt');
    }
    TrainingOrderStore.orders.add(completed);
    _activeServerOrderUuid = null;
    _paidSaleQueued = true;
    _resetForNextOrder(advanceOrderNumber: false, clearActiveDiningTable: true);
    return successMessage;
  }

  Future<String> _finishCompletedOrderAdmitted({
    required bool isDineInPayment,
    required String successMessage,
  }) async {
    if (training) return _finishTrainingOrder(successMessage: successMessage);
    _assignFinalOrderNumber();
    // Stamp the server order_uuid now, so the saved record + the order.create
    // push share it — a later full-cancel can then emit a matching order.void.
    // A cart resumed from hold keeps its mirror's uuid (Phase C2), so the
    // server upserts the held row open instead of duplicating it.
    final serverOwned = isDineInPayment && isLiveSharedTable?.call() == true;
    var completedSnapshot = snapshot().copyWith(
      serverOrderUuid: _activeServerOrderUuid ?? uuidV4(),
      serverReceipt: serverOwned,
      receiptNumber: serverOwned ? '' : receiptNumber,
      tempReference: serverOwned ? currentOrderReference : '',
    );
    if (!serverOwned) {
      completedSnapshot = completedSnapshot.copyWith(
        authorizations: signOrderAuthorizations(completedSnapshot),
      );
    }
    if (printReceipts && !serverOwned) {
      // Fail-safe: a printer error must never abort the local save or the
      // pos_api push below — it only surfaces a staff alert (Phase G4).
      final ok = await SunmiReceiptService.printReceipt(
        completedSnapshot,
        template: receiptTemplate,
        tax: activeTaxSettings,
        branchName: receiptBranchName,
        branchNameAr: receiptBranchNameAr,
      );
      if (!ok) _reportPrintFailure('receipt');
    }
    final tableRoundHandled =
        isDineInPayment &&
        await (onDiningTableFinalRound?.call(completedSnapshot) ??
            Future<bool>.value(false));
    if (serverOwned) {
      final canonical =
          canonicalDiningBillUuid?.call() ??
          diningSessionFor(activeDiningTableId ?? '')?.serverOrderUuid ??
          _activeServerOrderUuid;
      if (canonical != null && canonical.isNotEmpty) {
        completedSnapshot = completedSnapshot.copyWith(
          serverOrderUuid: canonical,
        );
      }
    }
    final bill = _reservedDiningBill;
    if (serverOwned && bill != null) {
      final sub = (bill['subtotal_baisas'] as int) / 1000;
      final discount = (bill['discount_total_baisas'] as int) / 1000;
      completedSnapshot = completedSnapshot.copyWith(
        rawSubtotal: sub,
        discountAmount: discount,
        subtotal: sub - discount,
        compAmount: (bill['comp_total_baisas'] as int? ?? 0) / 1000,
        tax: (bill['tax_total_baisas'] as int) / 1000,
        // LAUNCH-P4 — the server bill says whether its total contains VAT.
        pricesIncludeTax: bill['prices_include_tax'] == true,
        total: (bill['grand_total_baisas'] as int) / 1000,
        activePaymentBaseTotal: (bill['grand_total_baisas'] as int) / 1000,
        payableTotal: (bill['grand_total_baisas'] as int) / 1000,
      );
    }
    _activeServerOrderUuid = null;
    if (printKitchenTickets && !tableRoundHandled) {
      // Phase C1 — the kitchen copy: items + add-ons + notes, no prices. The
      // service itself swallows printer errors.
      final ok = await SunmiReceiptService.printKitchenTicket(
        _kitchenTicketFromSnapshot(completedSnapshot, time: DateTime.now()),
      );
      if (!ok) _reportPrintFailure('kitchen');
    }
    await _saveCompletedOrder(completedSnapshot);
    _paidSaleKey = completedSnapshot.serverOrderUuid;
    // Push the finalized order to pos_api (via the durable outbox). Fire-and-
    // forget: completion never waits on, or fails because of, the network.
    await onOrderCompleted?.call(completedSnapshot);
    if (!serverOwned) _paidSaleQueued = true;
    if (isDineInPayment && !serverOwned) {
      await _markActiveDiningTablePaid(completedSnapshot);
    }
    if (serverOwned) {
      _cancelPendingDiningTablePersistence();
      await _diningTablePersistQueue;
      // Keep the acknowledged draft/round proof until the server confirms the
      // closed bill. Automatic closed-copy retirement archives it unchanged.
      final paid = _buildActiveDiningTableSession(
        paidSnapshot: completedSnapshot,
      );
      if (paid != null) {
        await diningTableSyncHooks?.onTablePaid(paid, completedSnapshot);
      }
      _paidSaleQueued = true;
    }
    if (serverOwned && refreshServerReceipt != null) {
      try {
        completedSnapshot = await refreshServerReceipt!(completedSnapshot);
      } catch (_) {
        /* Durable provisional copy remains on lost ACK. */
      }
    }
    if (printReceipts && serverOwned) {
      final ok = await SunmiReceiptService.printReceipt(
        completedSnapshot,
        template: receiptTemplate,
        tax: activeTaxSettings,
        branchName: receiptBranchName,
        branchNameAr: receiptBranchNameAr,
      );
      if (!ok) _reportPrintFailure('receipt');
    }

    // #3 — decrement the cached shelf count (unit/cooked) locally before the
    // cart is cleared (informational; it never gates the next sale).
    _consumeShelfStockFromCart();

    _resetForNextOrder(
      advanceOrderNumber: !isDineInPayment,
      nextOrderType: isDineInPayment ? OrderType.dineIn : OrderType.quickOrder,
      forceOrderNumber: isDineInPayment ? _nextOrderNumberSeed : null,
      clearActiveDiningTable: true,
      note: isDineInPayment ? _l10n.ctrlMsgChooseTableDineIn : '',
    );
    return successMessage;
  }

  void clearForNextOrder() {
    if (!_cartMutationAllowed()) return;
    _resetForNextOrder(advanceOrderNumber: false);
  }

  Future<void> shutdown() async {
    await closeRearDisplay();
  }

  void confirmCharityRoundUp(bool accepted) {
    _handleCharityRoundUpResponse(accepted, source: 'staff');
  }

  void cancelCharityRoundUpPrompt() {
    if (_charityRoundUpCompleter == null ||
        _charityRoundUpCompleter!.isCompleted) {
      showCharityRoundUpPrompt = false;
      _clearPaymentLaunchOverlay();
      _broadcast();
      return;
    }

    _charityPromptCanceled = true;
    showCharityRoundUpPrompt = false;
    _clearPaymentLaunchOverlay();
    charityRoundUpAccepted = false;
    charityRoundUpAmount = 0;
    charityRoundUpTotal = 0;
    lastCustomerEvent = 'Staff canceled the charity round-up prompt.';
    _broadcast();
    _charityRoundUpCompleter!.complete(null);
  }

  @override
  void dispose() {
    BusinessBoundary.activationCompleted.removeListener(
      _refreshStorageAfterActivation,
    );
    _observedRecoveryGuard?.recoveryBlocked.removeListener(_notifySafely);
    cancelCustomerLookups();
    _isDisposed = true;
    _rearDisplaySyncTimer?.cancel();
    _rearDisplaySyncPending = false;
    _diningTablePersistTimer?.cancel();
    super.dispose();
  }

  void _broadcast() {
    if (recoveryBlocked) {
      _notifySafely();
      return;
    }
    _invalidatePriceCache();
    _syncActiveDiningTableInMemory();
    _scheduleActiveDiningTablePersistence();
    _notifySafely();
    _scheduleRearDisplaySync();
  }

  void _scheduleActiveDiningTablePersistence() {
    if (selectedOrderType != OrderType.dineIn || activeDiningTableId == null) {
      return;
    }

    _diningTablePersistTimer?.cancel();
    _diningTablePersistTimer = Timer(_diningTablePersistDebounceDuration, () {
      _diningTablePersistTimer = null;
      unawaited(_queueActiveDiningTablePersistence());
    });
  }

  Future<void> _flushActiveDiningTablePersistence() async {
    if (selectedOrderType != OrderType.dineIn || activeDiningTableId == null) {
      _cancelPendingDiningTablePersistence();
      return;
    }

    _diningTablePersistTimer?.cancel();
    _diningTablePersistTimer = null;
    await _queueActiveDiningTablePersistence();
  }

  Future<void> _queueActiveDiningTablePersistence() {
    final operation = _diningTablePersistQueue.then(
      (_) => _persistActiveDiningTableSession(),
    );
    _diningTablePersistQueue = operation.catchError((_) {});
    return operation;
  }

  void _cancelPendingDiningTablePersistence() {
    _diningTablePersistTimer?.cancel();
    _diningTablePersistTimer = null;
  }

  void _scheduleRearDisplaySync() {
    if (!_presentationEnabled) return;
    if (!rearDisplayOpened) return;

    _rearDisplaySyncPending = true;
    _rearDisplaySyncTimer?.cancel();
    _rearDisplaySyncTimer = Timer(_rearDisplaySyncDebounceDuration, () {
      _rearDisplaySyncTimer = null;
      unawaited(syncRearDisplay());
    });
  }

  void _handoffRearDisplayToPayment() {
    if (!rearDisplayOpened) return;

    _restoreRearDisplayAfterPayment = true;
    rearDisplayOpened = false;
    _rearDisplaySyncTimer?.cancel();
    _rearDisplaySyncTimer = null;
    _rearDisplaySyncPending = false;
  }

  Future<void> _restoreRearDisplayAfterPaymentIfNeeded() async {
    if (!_restoreRearDisplayAfterPayment) return;
    _restoreRearDisplayAfterPayment = false;

    if (_isDisposed || !_presentationEnabled) return;

    await openRearDisplay();
  }

  Future<bool?> _promptForCharityRoundUp() async {
    if (_charityRoundUpCompleter != null &&
        !_charityRoundUpCompleter!.isCompleted) {
      _charityRoundUpCompleter!.complete(null);
    }
    _charityPromptCanceled = false;
    _charityRoundUpCompleter = Completer<bool?>();
    _activeCharityRoundUpPromptId++;

    paymentStatus = 'Awaiting confirmation';
    showCharityRoundUpPrompt = true;
    _clearPaymentLaunchOverlay();
    charityRoundUpAccepted = false;
    charityRoundUpAmount = offeredCharityRoundUpAmount;
    charityRoundUpTotal = offeredCharityRoundUpTotal;
    displayNote = _l10n.ctrlMsgRoundUpPromptQuestion(
      SunmiReceiptService.money(charityRoundUpAmount),
    );
    _broadcast();
    debugPrint('PosController waiting for charity round-up response.');

    try {
      return await _charityRoundUpCompleter!.future.timeout(
        const Duration(minutes: 2),
      );
    } on TimeoutException {
      showCharityRoundUpPrompt = false;
      _clearPaymentLaunchOverlay();
      _broadcast();
      return null;
    } finally {
      _charityRoundUpCompleter = null;
    }
  }

  void _handleCharityRoundUpResponse(
    bool accepted, {
    String source = 'customer',
    int? promptId,
  }) {
    if (_charityRoundUpCompleter == null ||
        _charityRoundUpCompleter!.isCompleted) {
      debugPrint(
        'PosController ignored charity response because no active prompt was waiting.',
      );
      return;
    }

    if (source == 'customer' &&
        promptId != null &&
        promptId != _activeCharityRoundUpPromptId) {
      debugPrint(
        'PosController ignored stale charity response promptId=$promptId activePromptId=$_activeCharityRoundUpPromptId.',
      );
      return;
    }

    showCharityRoundUpPrompt = false;
    charityRoundUpAccepted = accepted;
    charityRoundUpAmount = accepted ? offeredCharityRoundUpAmount : 0;
    charityRoundUpTotal = accepted
        ? offeredCharityRoundUpTotal
        : activePaymentBaseTotal;
    final isCashMethod = selectedPaymentMethod == 'Cash';
    _showPaymentLaunchOverlay(
      title: isCashMethod
          ? _l10n.ctrlOverlayPreparingCashPayment
          : _l10n.ctrlOverlayPreparingSecurePayment,
      message: accepted
          ? (isCashMethod
                ? _l10n.ctrlMsgPreparingRoundedCash
                : _l10n.ctrlMsgPreparingRoundedCard)
          : (isCashMethod
                ? _l10n.ctrlMsgPreparingOriginalCash
                : _l10n.ctrlMsgPreparingOriginalCard),
    );
    lastCustomerEvent = switch (source) {
      'staff' =>
        accepted
            ? 'Staff confirmed the customer accepted the charity round-up.'
            : 'Staff confirmed the customer declined the charity round-up.',
      _ =>
        accepted
            ? 'Customer accepted the charity round-up.'
            : 'Customer declined the charity round-up.',
    };
    debugPrint(lastCustomerEvent);
    _broadcast();
    _charityRoundUpCompleter!.complete(accepted);
  }

  void _resetCharityRoundUp() {
    showCharityRoundUpPrompt = false;
    _clearPaymentLaunchOverlay();
    charityRoundUpAccepted = false;
    charityRoundUpAmount = 0;
    charityRoundUpTotal = 0;
    _charityPromptCanceled = false;
  }

  /// The card amount awaiting a force-record decision (for the dialog message).
  double get pendingReconciliationAmount => _pendingReconAmount;

  /// Pre-warm a Mosambee login session so the next card payment skips the (slow)
  /// login. Best-effort, Android-only, fire-and-forget. Call it when the POS
  /// screen opens, when the app resumes, and right after a card sale completes.
  void prewarmCardPayment() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(_paymentBridge.prepareSession());
  }

  /// Cashier-facing text for a failed card charge. Mosambee's own messages are
  /// English technical strings; the one failure staff can actually ACT on — no
  /// bank terminal assigned to this device — gets a localized, actionable
  /// message instead ("ask the administrator to assign a terminal").
  String _cardFailureMessage(MosambeePaymentResult result) =>
      result.isTerminalBusy
      ? _l10n.ctrlMsgCardTerminalBusy
      : result.isMissingTerminalId
      ? _l10n.ctrlMsgCardNoTerminalAssigned
      : result.userMessage;

  /// Launches a card charge via the payment terminal and, on an UNCERTAIN result
  /// (e.g. an NFC timeout), asks the cashier to cancel, force-record as pending
  /// reconciliation, or retry. Retry re-launches the terminal; the loop repeats
  /// until the cashier resolves it. Returns the outcome plus the last result.
  ///
  /// A charge that provably never reached the acquirer (no terminal assigned,
  /// SoftPOS missing) is NEVER offered as "record as pending reconciliation":
  /// there is no bank transaction for the settlement file to match, so
  /// recording it would invent revenue. See [MosambeePaymentResult.isUncertain].
  Future<(_CardChargeOutcome, MosambeePaymentResult)> _runCardCharge({
    required double amount,
    required String processingNote,
  }) async {
    while (true) {
      _clearPaymentLaunchOverlay();
      paymentStatus = 'Processing payment';
      displayNote = processingNote;
      _broadcast();

      final result = await _paymentBridge.payWithPreparedSession(amount);
      if (result.isSuccess) {
        return (_CardChargeOutcome.success, result);
      }

      if (result.isUncertain) {
        final choice = await _promptForPendingReconciliation(amount: amount);
        if (choice == PendingReconChoice.retry) {
          continue; // re-launch the payment terminal
        }
        if (choice == PendingReconChoice.record) {
          return (_CardChargeOutcome.recordPending, result);
        }
        return (_CardChargeOutcome.aborted, result); // cancel
      }

      // An explicit cancel or a hard failure — no retry/record offered.
      return (_CardChargeOutcome.aborted, result);
    }
  }

  /// Ask the cashier how to resolve an unconfirmed card charge (cancel, record as
  /// pending reconciliation, or retry). Awaited inline inside the pay flow, so
  /// the in-flight transaction context survives.
  Future<PendingReconChoice> _promptForPendingReconciliation({
    required double amount,
  }) async {
    if (_pendingReconCompleter != null &&
        !_pendingReconCompleter!.isCompleted) {
      _pendingReconCompleter!.complete(PendingReconChoice.cancel);
    }
    _pendingReconCompleter = Completer<PendingReconChoice>();
    _pendingReconAmount = amount;

    // Set the neutral "awaiting cashier" status and restore the customer UI FIRST —
    // the card payment left the customer panel mirroring the staff screen. Only once
    // the customer is back on its own neutral overlay do we show the staff-only
    // "Card charge not confirmed" dialog, so the customer never sees it mirrored.
    paymentStatus = 'Card charge not confirmed';
    _clearPaymentLaunchOverlay();
    displayNote = _l10n.ctrlMsgCardUnconfirmedReviewing;
    _broadcast();
    await _restoreRearDisplayAfterPaymentIfNeeded();

    showPendingReconciliationPrompt = true;
    pendingReconEscalated = false;
    _broadcast();

    // NO auto-cancel: a timer must never answer a money question. The card
    // may genuinely have been captured by the bank, and silently discarding
    // the prompt would leave that charge with no recorded sale and nothing
    // in the reconciliation queue — unrecoverable. (The handheld's twin
    // dialog has no timer for the same reason.) Instead, after 2 minutes
    // the prompt ESCALATES — flag + alert sound — so the UI pulls a
    // distracted cashier back; the dialog then waits for a human answer.
    // Worst case is a visibly blocked till anyone can resolve in seconds.
    _pendingReconEscalationTimer?.cancel();
    _pendingReconEscalationTimer = Timer(const Duration(minutes: 2), () {
      if (_pendingReconCompleter == null ||
          _pendingReconCompleter!.isCompleted) {
        return;
      }
      pendingReconEscalated = true;
      unawaited(SystemSound.play(SystemSoundType.alert)); // best-effort
      _broadcast();
    });

    try {
      return await _pendingReconCompleter!.future;
    } finally {
      _pendingReconEscalationTimer?.cancel();
      _pendingReconEscalationTimer = null;
      pendingReconEscalated = false;
      _pendingReconCompleter = null;
    }
  }

  /// Cashier's answer to the "Card charge not confirmed" prompt:
  /// [PendingReconChoice.record] force-records the card leg as
  /// pending_reconciliation, [PendingReconChoice.retry] re-launches the payment
  /// terminal to try again, and [PendingReconChoice.cancel] aborts the charge.
  void resolvePendingReconciliation(PendingReconChoice choice) {
    if (_pendingReconCompleter == null || _pendingReconCompleter!.isCompleted) {
      return;
    }
    showPendingReconciliationPrompt = false;
    _broadcast();
    _pendingReconCompleter!.complete(choice);
  }

  void _markOrderUpdated(String productId) {
    recentProductId = productId;
    orderUpdateNonce++;
  }

  void _showPaymentLaunchOverlay({
    required String title,
    required String message,
  }) {
    showPaymentLaunchOverlay = true;
    paymentOverlayTitle = title;
    paymentStatus = 'Preparing payment';
    displayNote = message;
  }

  void _clearPaymentLaunchOverlay() {
    showPaymentLaunchOverlay = false;
    paymentOverlayTitle = '';
  }

  void _handlePaymentLaunchState(Map<String, dynamic> event) {
    final stage = event['stage']?.toString() ?? '';
    final surface = event['surface']?.toString() ?? 'unknown';

    if (!isProcessingPayment) return;
    final isLogin = stage == 'login' || stage == 'login_started';
    final isPayment = stage == 'payment' || stage == 'payment_started';
    if (!isLogin && !isPayment) return;

    debugPrint(
      'PosController received Mosambee launch event: $stage on $surface.',
    );

    if (surface == 'rear') {
      _handoffRearDisplayToPayment();
    }

    paymentStatus = 'Processing payment';
    _showPaymentLaunchOverlay(
      title: isLogin
          ? _l10n.ctrlOverlayConnectingTerminal
          : _l10n.ctrlOverlayWaitingPaymentResult,
      message: isLogin
          ? _l10n.ctrlMsgTerminalOpening
          : charityRoundUpAccepted
          ? _l10n.ctrlMsgRoundedSentToTerminal
          : _l10n.ctrlMsgTotalSentToTerminal,
    );
    _broadcast();
  }

  Future<void> _loadStoredOrders() async {
    isLoadingStorage = true;
    _notifySafely();
    try {
      await _recoveryGuard?.refreshRecoveryGuard();
      currentOrderNumber = await _orderStorage.fetchNextOrderNumber();
      _nextOrderNumberSeed = currentOrderNumber + 1;
      currentOrderReference = '';
      orderHistory = await _orderStorage.loadOrderHistory();
      heldOrders = await _orderStorage.loadHeldOrders();
      diningTableSessions = await _orderStorage.loadDiningTableSessions();
    } catch (error) {
      debugPrint('Failed to load local order storage: $error');
      currentOrderNumber = 1450;
      currentOrderReference = '';
      _nextOrderNumberSeed = 1451;
      orderHistory = const [];
      heldOrders = const [];
      diningTableSessions = const [];
    } finally {
      isLoadingStorage = false;
      _notifySafely();
    }
  }

  Future<void> _saveCompletedOrder(OrderSnapshot completedSnapshot) async {
    try {
      if (completedSnapshot.serverReceipt) {
        await ServerReceiptHistory(_orderStorage).record(completedSnapshot);
      } else {
        await _orderStorage.saveCompletedOrder(completedSnapshot);
      }
      await refreshOrderHistory();
    } catch (error) {
      // Local history is a display copy; the outbox, not history, carries
      // the sale to the server. Its failure must never stop that (release
      // behaviour).
      debugPrint('Failed to save completed order: $error');
    }
  }

  DiningFloor? _findDiningFloorById(String? floorId) {
    if (floorId == null || floorId.isEmpty) return null;
    for (final floor in diningFloors) {
      if (floor.id == floorId) return floor;
    }
    return null;
  }

  DiningTableDefinition? _findDiningTableDefinitionById(String? tableId) {
    if (tableId == null || tableId.isEmpty) return null;
    for (final table in diningTableDefinitions) {
      if (table.id == tableId) return table;
    }
    return null;
  }

  String _floorLabel(String floorId) =>
      _findDiningFloorById(floorId)?.label ?? _l10n.ctrlFloorFallbackDining;

  /// Gap sweep G2 — public floor label for the table pickers.
  String floorLabelFor(String floorId) => _floorLabel(floorId);

  void _reserveOrderNumber(int orderNumber) {
    if (orderNumber >= _nextOrderNumberSeed) {
      _nextOrderNumberSeed = orderNumber + 1;
    }
  }

  void _assignFinalOrderNumber() {
    _reserveOrderNumber(currentOrderNumber);
  }

  String _ensureOrderReference() {
    if (currentOrderReference.isNotEmpty) return currentOrderReference;
    currentOrderReference = _generateOrderReference();
    return currentOrderReference;
  }

  String _generateOrderReference() {
    _referenceSequence++;
    final timestamp = DateTime.now().millisecondsSinceEpoch
        .remainder(100000000)
        .toString()
        .padLeft(8, '0');
    final sequence = _referenceSequence.toString().padLeft(2, '0');
    return 'REF-$timestamp$sequence';
  }

  void _syncActiveDiningTableInMemory() {
    if (selectedOrderType != OrderType.dineIn || activeDiningTableId == null) {
      return;
    }

    final session = _buildActiveDiningTableSession();
    if (session == null) {
      // The head's cart emptied. DON'T drop the head here — the debounced
      // persist below frees the WHOLE joined party (head + linked seats) while
      // the link is still resolvable; dropping the head now would orphan its
      // linked seats (occupied, pointing at a vanished head). The brief stale
      // render clears within the persist debounce window.
      return;
    }

    final updated = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere((entry) => entry.tableId == activeDiningTableId);
    updated.insert(0, session);
    diningTableSessions = updated;
  }

  Future<void> _persistActiveDiningTableSession() async {
    final notifyHooks = !_reviewingSavedCopy;
    // Persistence belongs to the transition itself, including its final flush.
    if (!await _combineMutationAllowed(insideTableTransition: true)) return;
    if (selectedOrderType != OrderType.dineIn || activeDiningTableId == null) {
      return;
    }

    final tableId = activeDiningTableId!;
    final session = _buildActiveDiningTableSession();
    final existing = diningSessionFor(tableId);

    try {
      if (session == null) {
        if (existing == null) return;
        // Empty cart — free the WHOLE joined party (head + its linked seats)
        // from memory + storage, so the linked seats don't orphan.
        final groupIds = _diningGroupIds(tableId);
        await _clearDiningGroup(groupIds);
        diningTableSessions = List<DiningTableSession>.from(diningTableSessions)
          ..removeWhere((s) => groupIds.contains(s.tableId));
        for (final id in groupIds) {
          _diningHookOccupancies.remove(id);
        }
        if (notifyHooks) {
          diningTableSyncHooks?.onTablesCleared(groupIds, existing);
        }
        _notifySafely();
      } else {
        await _orderStorage.saveDiningTableSession(session);
        final occupancy = '${session.orderReference}|${session.occupiedAt}';
        if (!notifyHooks) return;
        if (_diningHookOccupancies[tableId] == occupancy) {
          diningTableSyncHooks?.onTableDraftPersisted(session);
        } else {
          _diningHookOccupancies[tableId] = occupancy;
          diningTableSyncHooks?.onTableOccupied(session);
        }
      }
    } catch (error) {
      debugPrint('Failed to persist dining table $tableId: $error');
    }
  }

  DiningTableSession? _buildActiveDiningTableSession({
    OrderSnapshot? paidSnapshot,
  }) {
    final tableId = activeDiningTableId;
    final definition = activeDiningTableDefinition;

    if (tableId == null || definition == null) return null;

    final now = DateTime.now();
    final existing = diningSessionFor(tableId);

    if (paidSnapshot != null) {
      return DiningTableSession(
        tableId: tableId,
        floorId: definition.floorId,
        status: DiningTableStatus.paid,
        orderNumber: paidSnapshot.orderNumber,
        orderReference: currentOrderReference,
        updatedAt: now,
        occupiedAt: existing?.occupiedAt ?? now,
        paidAt: now,
        draft: null,
        paidSnapshot: paidSnapshot,
      );
    }

    if (_cart.isEmpty) return null;

    return DiningTableSession(
      tableId: tableId,
      floorId: definition.floorId,
      status: DiningTableStatus.occupied,
      orderNumber: null,
      orderReference: _ensureOrderReference(),
      updatedAt: now,
      occupiedAt: existing?.occupiedAt ?? now,
      paidAt: null,
      draft: createDraft(),
      paidSnapshot: null,
      // Preserve the joined-party link through the debounced re-persist —
      // the active table is the head; its linked seats must survive an edit.
      primaryTableId: existing?.primaryTableId,
      linkedTableIds: existing?.linkedTableIds ?? const [],
      // The in-memory draft must retain the same acknowledged generation as
      // storage. Otherwise Done leaves a copy that cleanup cannot identify
      // until the next app launch reloads these fields from SQLite.
      seatingKey: existing?.seatingKey,
      seatingUuid: existing?.seatingUuid,
      seatingState: existing?.seatingState,
      serverOrderUuid: existing?.serverOrderUuid,
      tempReference: existing?.tempReference,
      winnerSeatingUuid: existing?.winnerSeatingUuid,
      lastVerdict: existing?.lastVerdict,
      lastVerdictAt: existing?.lastVerdictAt,
    );
  }

  Future<void> _markActiveDiningTablePaid(
    OrderSnapshot completedSnapshot,
  ) async {
    _cancelPendingDiningTablePersistence();
    await _diningTablePersistQueue;

    final headId = activeDiningTableId;
    final linkedIds =
        (headId != null ? diningSessionFor(headId)?.linkedTableIds : null) ??
        const <String>[];

    final paidSession = _buildActiveDiningTableSession(
      paidSnapshot: completedSnapshot,
    );
    if (paidSession == null) return;

    // The paid head is no longer a party — its linked seats free immediately
    // (the bill they shared is settled); the head shows the paid receipt until
    // the cashier acknowledges it.
    final freeIds = linkedIds.toSet();
    diningTableSessions = <DiningTableSession>[
      paidSession,
      ...diningTableSessions.where(
        (session) =>
            session.tableId != paidSession.tableId &&
            !freeIds.contains(session.tableId),
      ),
    ];

    try {
      await _orderStorage.saveDiningTableSession(paidSession);
      for (final id in freeIds) {
        await _orderStorage.clearDiningTable(id);
      }
      await diningTableSyncHooks?.onTablePaid(paidSession, completedSnapshot);
    } catch (error) {
      debugPrint('Failed to mark dining table as paid: $error');
    }
  }

  void _resetForNextOrder({
    required bool advanceOrderNumber,
    OrderType nextOrderType = OrderType.quickOrder,
    int? forceOrderNumber,
    bool clearActiveDiningTable = false,
    String note = '',
  }) {
    _advanceOrderGeneration();
    _tenderPrice = null;
    _tenderSnapshot = null;
    _reservedDiningBill = null;
    _forgetOrderAuthorizations();
    _cart.clear();
    // Phase C2 — a leftover uuid (resumed-then-cleared cart) is dropped, not
    // voided: the server mirror stays held and remains resumable/discardable
    // from the held list of any branch terminal.
    _activeServerOrderUuid = null;
    paymentStatus = 'Waiting';
    _activeDiningTableSeatingKey = null;
    selectedPaymentMethod = 'Cash';
    lastPaymentMessage = '';
    displayNote = note;
    paymentOverlayTitle = '';
    customerReferenceNumber = '';
    vehiclePlateNumber = '';
    selectedCustomer = null;
    selectedEarnRuleIds = null; // P-F3 — per-order choice
    receiptNumber = ''; // P-F8 — per-order allocation
    currentOrderReference = '';
    isProcessingPayment = false;
    productSearchQuery = '';
    discount = const DiscountConfiguration();
    _autoOrderDiscountSuppressed = false; // P-F4 — per-order
    splitCount = 1;
    _splitPayments.clear();
    _splitPlanAmounts = null;
    _lastCardCharge = null;
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    loyaltyRedeemStamps = 0;
    loyaltyRedeemCustomerId = null;
    appliedComp = null;
    // P-G7 — per-order delivery facts. The provider pick is ALSO cleared:
    // the next delivery order must go through the picker deliberately (an
    // inherited provider is financially binding now — it decides who owes
    // the payout and at which commission %). _applyDeliveryPricing then
    // restores base prices (next order type is never delivery here).
    deliveryReference = '';
    deliveryDriverPhone = '';
    _punchedDeliveryProviderId = null;
    _punchedDeliveryProviderName = '';
    selectedDeliveryProviderId = null;
    // A reset that force-hides the unresolved-charge prompt is a deliberate
    // abandon — resolve the awaiting pay flow as cancel so it can never
    // hang forever now that the prompt itself has no timeout.
    if (_pendingReconCompleter != null &&
        !_pendingReconCompleter!.isCompleted) {
      _pendingReconCompleter!.complete(PendingReconChoice.cancel);
    }
    showPendingReconciliationPrompt = false;
    _activePaymentBaseOverride = null;
    selectedOrderType = nextOrderType;
    // P-G7 — with the provider cleared and a non-delivery order type, this
    // restores base menu prices for the next order.
    _applyDeliveryPricing();
    if (clearActiveDiningTable) {
      _cancelPendingDiningTablePersistence();
      activeDiningTableId = null;
      diningTableSearchQuery = '';
    }
    _clearPaymentLaunchOverlay();
    recentProductId = '';
    orderUpdateNonce = 0;
    _resetCharityRoundUp();
    if (forceOrderNumber != null) {
      currentOrderNumber = forceOrderNumber;
    } else if (advanceOrderNumber) {
      currentOrderNumber = _nextOrderNumberSeed;
      _nextOrderNumberSeed++;
    }
    _broadcast();
  }

  double _snapshotItemCancellationAmount(
    OrderSnapshot snapshot,
    Map<String, dynamic> item,
  ) {
    final lineTotal = (item['lineTotal'] as num?)?.toDouble() ?? 0;
    if (lineTotal <= 0) return 0;

    final rawTotal = snapshot.rawSubtotal <= 0
        ? snapshot.items.fold<double>(
            0,
            (sum, entry) =>
                sum + ((entry['lineTotal'] as num?)?.toDouble() ?? 0),
          )
        : snapshot.rawSubtotal;

    if (rawTotal <= 0) return _roundMoney(lineTotal);
    return _roundMoney(snapshot.payableTotal * (lineTotal / rawTotal));
  }

  double _roundMoney(double value) => double.parse(value.toStringAsFixed(3));

  void _notifySafely() {
    if (_isDisposed) return;
    notifyListeners();
  }
}
