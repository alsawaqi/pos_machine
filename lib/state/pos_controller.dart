import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../services/display_strings.dart';
import '../services/kitchen_ticket.dart';
import '../services/local_order_storage_service.dart';
import '../services/mosambee_payment_service.dart';
import '../services/order_sync_payload.dart' show uuidV4;
import '../services/presentation_service.dart';
import '../services/sunmi_receipt_service.dart';

class PosController extends ChangeNotifier {
  static const Duration _rearDisplaySyncDebounceDuration = Duration(
    milliseconds: 250,
  );
  static const Duration _diningTablePersistDebounceDuration = Duration(
    milliseconds: 120,
  );

  final PresentationService _presentation = PresentationService.instance;
  final MosambeePaymentService _paymentBridge = MosambeePaymentService();
  final OrderStorageService _orderStorage;

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

  /// This branch's ingredient balances by ingredient id (from the config), for
  /// ingredient-based sold-out enforcement (see [isOutOfStock]).
  Map<int, double> ingredientBalances = const <int, double>{};

  /// v2 #14 — staff positions the merchant allows to cancel an order at the POS
  /// (company policy from /device/config). Defaults to managers-only until a
  /// config sync populates it; see [positionCanCancelOrders].
  List<String> cancelOrderPositions = const <String>['manager'];

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
  AppliedComp? appliedComp;

  /// Whether a staff member with [position] may cancel an order under the
  /// current company policy. Case-insensitive; an unknown / null position is
  /// denied. With no policy cached, the default managers-only list applies.
  bool positionCanCancelOrders(String? position) {
    final p = (position ?? '').trim().toLowerCase();
    if (p.isEmpty) return false;

    return cancelOrderPositions.any((allowed) => allowed.trim().toLowerCase() == p);
  }

  /// The unmodified catalog (base prices). [allProducts] is this list re-priced
  /// for the selected provider when the order type is delivery.
  List<Product> _baseProducts = const <Product>[];

  final List<CartItem> _cart = [];
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
  OrderType selectedOrderType = OrderType.quickOrder;
  DiscountConfiguration discount = const DiscountConfiguration();

  // Session branch id, for auto-applying product/category-scope discounts to
  // cart lines (set by applyCatalog). Null = no branch context → no auto-apply.
  int? _discountBranchId;
  /// Merchant discount rules from the cached catalog (from the API). The picker
  /// offers the currently-applicable order-scope ones.
  List<MerchantDiscount> availableDiscounts = const [];
  /// Merchant loyalty rules from the cached catalog (stamp card / points).
  List<LoyaltyRule> loyaltyRules = const [];
  /// Cached customer slice (offline lookup / order attach).
  List<CustomerRef> cachedCustomers = const [];

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
  int splitCount = 1;
  final List<SplitPaymentRecord> _splitPayments = [];
  /// Soft POS evidence for the most recent single (non-split) card payment.
  /// Captured at completion and read synchronously by the order-push bridge
  /// before the next-order reset clears it. Split tenders carry their own
  /// evidence on each [SplitPaymentRecord] instead.
  CardCharge? _lastCardCharge;
  double? _activePaymentBaseOverride;
  String? activeDiningTableId;

  String paymentStatus = 'Waiting';
  String selectedPaymentMethod = 'Cash';
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
  void Function(OrderSnapshot snapshot)? onOrderCompleted;

  /// Phase C2 — invoked when an order is placed on hold (after the local save).
  /// The screen wires this to the hold-mirror outbox (order.hold) so the held
  /// order survives a device wipe and shows on the branch's other terminals.
  /// Fire-and-forget — holding never blocks on, or fails because of, the
  /// network.
  void Function(OrderSessionDraft draft)? onOrderHeld;

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
  })? onOrderVoided;

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
  Completer<bool>? _pendingReconCompleter;
  double _pendingReconAmount = 0;

  PosController({OrderStorageService? orderStorage})
    : _orderStorage = orderStorage ?? LocalOrderStorageService.instance {
    _paymentBridge.setLaunchStateListener(_handlePaymentLaunchState);
  }

  Future<void> init() async {
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
    Map<int, double> ingredientBalances = const <int, double>{},
    List<MerchantDiscount> discounts = const <MerchantDiscount>[],
    List<LoyaltyRule> loyaltyRules = const <LoyaltyRule>[],
    List<CustomerRef> customers = const <CustomerRef>[],
    List<String> cancelOrderPositions = const <String>['manager'],
    ReceiptTemplate? receiptTemplate,
    List<VoidReasonRef> voidReasons = const <VoidReasonRef>[],
    List<CompReasonRef> compReasons = const <CompReasonRef>[],
    Map<int, List<int>> categoryAddonGroupIds = const <int, List<int>>{},
    int? branchId,
  }) {
    this.categories = categories;
    this.categoryNamesAr = categoryNamesAr;
    _baseProducts = products;
    diningFloors = floors;
    diningTableDefinitions = tables;
    this.addonGroups = addonGroups;
    this.deliveryProviders = deliveryProviders;
    this.expenseCategories = expenseCategories;
    this.ingredientBalances = ingredientBalances;
    availableDiscounts = discounts;
    _discountBranchId = branchId;
    this.loyaltyRules = loyaltyRules;
    cachedCustomers = customers;
    this.cancelOrderPositions =
        cancelOrderPositions.isEmpty ? const <String>['manager'] : cancelOrderPositions;
    this.receiptTemplate = receiptTemplate;
    this.voidReasons = voidReasons;
    this.compReasons = compReasons;
    this.categoryAddonGroupIds = categoryAddonGroupIds;
    // Company taxes drive the cart tax lines + total. Stored in the shared
    // source so the persisted / printed order agrees with the live cart.
    activeCompanyTaxes = taxes;

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
    if (floors.isNotEmpty && !floors.any((f) => f.id == selectedDiningFloorId)) {
      selectedDiningFloorId = floors.first.id;
    }
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
    selectedDeliveryProviderId = providerId;
    _applyDeliveryPricing();
    _broadcast();
  }

  /// Recompute [allProducts] (and re-price open cart lines) for the current
  /// order context: delivery + a chosen provider ⇒ each product's resolved
  /// delivery price; otherwise the base price.
  void _applyDeliveryPricing() {
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
        _cart[i] = CartItem(
          product: src.copyWith(price: newPrice),
          qty: item.qty,
          modifiers: List<CartItemModifier>.from(item.modifiers),
          notes: item.notes,
        );
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
    final ownIds =
        live.addonGroupIds.isNotEmpty ? live.addonGroupIds : product.addonGroupIds;
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

  /// Whether [product] is sold out at this branch (greyed-out / blocked on the
  /// POS). Unit products: branch count ≤ 0. Ingredient products: any recipe
  /// ingredient's branch balance is below what one unit needs. Untracked
  /// products are always available.
  bool isOutOfStock(Product product) {
    switch (product.stockMode) {
      case 'unit':
        final qty = product.branchStockQty;
        return qty != null && qty <= 0;
      case 'ingredient':
        for (final line in product.recipe) {
          if ((ingredientBalances[line.ingredientId] ?? 0) < line.quantity) {
            return true;
          }
        }
        return false;
      default:
        return false;
    }
  }

  List<Product> get visibleProducts {
    final query = productSearchQuery.trim().toLowerCase();
    return allProducts.where((product) {
      final matchesCategory = product.category == selectedCategory;
      if (!matchesCategory) return false;
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

  double get rawSubtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);

  double get discountAmount {
    final orderLevel = discount.isActive
        ? switch (discount.kind) {
            DiscountKind.fixedAmount => discount.value,
            DiscountKind.percentage => rawSubtotal * (discount.value / 100),
            DiscountKind.none => 0.0,
          }
        : 0.0;
    // Auto-applied product/category line discounts stack on top of any
    // order-level discount; the combined total is clamped so the order can
    // never go negative.
    final combined = orderLevel + lineDiscountTotal;
    return _roundMoney(combined.clamp(0.0, rawSubtotal).toDouble());
  }

  /// The best applicable product/category-scope discount for [item] right now —
  /// auto-applied, since targeted promotions need no picker. Zero if none.
  ({double amount, int? id, String? amountType, String label}) lineDiscountFor(
    CartItem item,
  ) {
    final branchId = _discountBranchId;
    if (branchId == null) {
      return (amount: 0.0, id: null, amountType: null, label: '');
    }
    final productId = int.tryParse(item.product.id);
    final categoryId = item.product.categoryId;
    final now = DateTime.now();

    MerchantDiscount? best;
    double bestAmount = 0;
    for (final d in availableDiscounts) {
      if (d.isOrderScope) continue;
      if (!d.appliesAt(now, branchId: branchId)) continue;
      if (!d.appliesToProduct(productId, categoryId)) continue;
      final amount = d.amountFor(item.lineTotal);
      if (amount > bestAmount) {
        bestAmount = amount;
        best = d;
      }
    }
    if (best == null || bestAmount <= 0) {
      return (amount: 0.0, id: null, amountType: null, label: '');
    }
    return (
      amount: bestAmount,
      id: best.id,
      amountType: best.amountType,
      label: best.name,
    );
  }

  /// Total of auto-applied product/category line discounts across the cart (OMR).
  double get lineDiscountTotal =>
      _cart.fold(0.0, (sum, item) => sum + lineDiscountFor(item).amount);

  /// A cart item's snapshot map + its auto-applied line discount, so the order
  /// push can emit a per-line discounts[] entry with line_index.
  Map<String, dynamic> _snapshotItem(CartItem item) {
    final map = item.toMap();
    final ld = lineDiscountFor(item);
    if (ld.amount > 0) {
      map['lineDiscount'] = ld.amount;
      map['lineDiscountLabel'] = ld.label;
      if (ld.id != null) map['lineDiscountId'] = ld.id;
      if (ld.amountType != null) map['lineDiscountAmountType'] = ld.amountType;
    }
    return map;
  }

  double get subtotal => _roundMoney(
    (rawSubtotal - discountAmount).clamp(0.0, double.infinity).toDouble(),
  );

  /// Phase B — the comp write-off (OMR), derived LIVE from the cart so edits
  /// can never leave a stale figure: a line comp = that line's discounted
  /// total; a whole-order comp = the whole discounted subtotal. A comped line
  /// that was removed clears the comp (returns 0).
  double get compAmount {
    final comp = appliedComp;
    if (comp == null) return 0;
    final lineIndex = comp.lineIndex;
    if (lineIndex == null) return subtotal;
    if (lineIndex < 0 || lineIndex >= _cart.length) return 0;
    final item = _cart[lineIndex];
    final net = item.lineTotal - lineDiscountFor(item).amount;
    return _roundMoney(net.clamp(0.0, subtotal).toDouble());
  }

  /// The taxed base after the comp — comped food is given away, not sold, so
  /// no tax is charged on it (a fully comped order totals 0.000).
  double get _taxedBase => _roundMoney(
    (subtotal - compAmount).clamp(0.0, double.infinity).toDouble(),
  );

  /// Per-tax breakdown (one line per active company tax) for the cart + receipt.
  List<TaxLineAmount> get taxLines => taxLinesFor(_taxedBase);

  double get tax => taxTotalFor(_taxedBase);

  double get total => _roundMoney(_taxedBase + tax);

  /// Phase B — apply a manager comp (one per order; replaces any prior one).
  /// The CALLER is responsible for manager authorization + cap validation
  /// against the picked reason's maxAmount.
  void applyComp(AppliedComp comp) {
    appliedComp = comp;
    _resetCharityRoundUp();
    _broadcast();
  }

  void removeComp() {
    if (appliedComp == null) return;
    appliedComp = null;
    _resetCharityRoundUp();
    _broadcast();
  }

  List<SplitPaymentRecord> get splitPayments =>
      List.unmodifiable(_splitPayments);

  /// Soft POS evidence for the last single (non-split) card payment, or null.
  /// The order-push bridge reads this synchronously at completion.
  CardCharge? get lastCardCharge => _lastCardCharge;

  int get paidSplitCount =>
      splitCount > 1 ? _splitPayments.length.clamp(0, splitCount).toInt() : 0;

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

  double get activePaymentBaseTotal {
    final override = _activePaymentBaseOverride;
    if (override != null) return override;

    if (splitCount <= 1) return total;
    if (isSplitPaymentComplete) {
      return _splitPayments.isEmpty
          ? _roundMoney(total / splitCount)
          : _splitPayments.last.baseAmount;
    }

    final remainingShares = splitCount - paidSplitCount;
    if (remainingShares <= 1) {
      return _roundMoney(
        (total - _splitBasePaidTotal).clamp(0.0, double.infinity).toDouble(),
      );
    }

    return _roundMoney(total / splitCount);
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
      (selectedPaymentMethod == 'Credit Card' ||
          (splitCount > 1 && selectedPaymentMethod == 'Cash')) &&
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

    return OrderSnapshot(
      orderNumber: currentOrderNumber,
      orderType: selectedOrderType.storageValue,
      items: _cart.map(_snapshotItem).toList(),
      rawSubtotal: rawSubtotal,
      discountAmount: discountAmount,
      discountLabel: discount.label,
      discountId: discount.discountId,
      discountAmountType: discount.amountType,
      loyaltyRedeemRuleId: loyaltyRedeemRuleId,
      loyaltyRedeemPoints: loyaltyRedeemPoints,
      loyaltyRedeemStamps: loyaltyRedeemStamps,
      compAmount: compAmount,
      compReasonId: appliedComp?.reasonId,
      compReasonName: appliedComp?.reasonName ?? '',
      compLineIndex: appliedComp?.lineIndex,
      subtotal: subtotal,
      tax: tax,
      total: total,
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
    );
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
      diningFloorId: activeTable?.floorId ?? '',
      diningFloorLabel: floor?.label ?? '',
      diningTableId: activeTable?.id ?? '',
      diningTableName: activeTable?.name ?? '',
      items: _cart.map((item) => CartItem.fromMap(item.toMap())).toList(),
      discount: discount,
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
    if (selectedOrderType == orderType) {
      if (orderType == OrderType.dineIn && activeDiningTableId == null) {
        displayNote = _l10n.ctrlMsgChooseTableDineIn;
        _broadcast();
      }
      return;
    }

    if (selectedOrderType == OrderType.dineIn && activeDiningTableId != null) {
      await returnToDiningFloorPlan();
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
    selectedPaymentMethod = paymentMethod;
    _broadcast();
  }

  void setCustomerReferenceNumber(String value) {
    customerReferenceNumber = value.replaceAll(RegExp(r'\D'), '').trim();
    // Typing a raw number detaches any searched customer (they diverge).
    selectedCustomer = null;
    _broadcast();
  }

  /// Attach a customer chosen from live search. Their phone backfills the
  /// reference display; the order will attach by id.
  void attachCustomer(CustomerSearchResult customer) {
    selectedCustomer = customer;
    customerReferenceNumber =
        customer.phone.replaceAll(RegExp(r'\D'), '').trim();
    _broadcast();
  }

  void setVehiclePlateNumber(String value) {
    // Plates are alphanumeric; store the canonical uppercased form (the server
    // matches plates uppercased).
    vehiclePlateNumber = value.trim().toUpperCase();
    _broadcast();
  }

  /// Offline customer search over the cached slice (name/phone contains the
  /// query), returning the CustomerSearchResult shape WITH cached loyalty, so
  /// attach + redeem work unchanged when the live search is unreachable.
  List<CustomerSearchResult> searchCachedCustomers(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return cachedCustomers
        .where((c) =>
            c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q))
        .take(20)
        .map((c) => c.toSearchResult())
        .toList();
  }

  /// Pending loyalty redemption for this order (the points SPENT). Its monetary
  /// value rides as the order discount; this is sent as loyalty_redeem on pay so
  /// the server decrements the balance. Null = no redemption.
  int? loyaltyRedeemRuleId;
  int loyaltyRedeemPoints = 0;
  // Stamps spent on a visit_based (stamp-card) redemption (sent as
  // loyalty_redeem.stamps on pay). 0 = a points redemption (or none).
  int loyaltyRedeemStamps = 0;

  void applyDiscount(DiscountConfiguration configuration) {
    discount = configuration;
    // A manual/merchant discount reuses the single discount slot — drop any
    // pending loyalty redemption so we don't send a stale redeem on pay.
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    loyaltyRedeemStamps = 0;
    _resetCharityRoundUp();
    _broadcast();
  }

  /// Redeem under a loyalty rule: apply [valueOmr] as the order discount and
  /// remember the [points] OR [stamps] to spend (sent as loyalty_redeem on
  /// pay). spend_based passes points; visit_based passes stamps.
  void applyLoyaltyRedemption({
    required int ruleId,
    required double valueOmr,
    required String label,
    int points = 0,
    int stamps = 0,
  }) {
    discount = DiscountConfiguration(
      kind: DiscountKind.fixedAmount,
      value: valueOmr,
      label: label,
    );
    loyaltyRedeemRuleId = ruleId;
    loyaltyRedeemPoints = points;
    loyaltyRedeemStamps = stamps;
    _resetCharityRoundUp();
    _broadcast();
  }

  void clearDiscount() {
    discount = const DiscountConfiguration();
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    loyaltyRedeemStamps = 0;
    _resetCharityRoundUp();
    _broadcast();
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
    if (hasRecordedSplitPayments) return;
    splitCount = count < 1 ? 1 : count;
    _splitPayments.clear();
    _resetCharityRoundUp();
    _broadcast();
  }

  void clearSplit() {
    if (hasRecordedSplitPayments) return;
    splitCount = 1;
    _splitPayments.clear();
    _resetCharityRoundUp();
    _broadcast();
  }

  void addProduct(Product product) {
    final index = _cart.indexWhere(
      (item) => item.product.id == product.id && !item.hasCustomization,
    );
    _ensureOrderReference();
    if (index == -1) {
      _cart.insert(0, CartItem(product: product));
    } else {
      final updatedItem = _cart.removeAt(index);
      updatedItem.qty++;
      _cart.insert(0, updatedItem);
    }
    _markOrderUpdated(product.id);
    _broadcast();
  }

  void incrementCartItem(CartItem item) {
    final index = _cart.indexOf(item);
    if (index == -1) return;

    _cart[index].qty++;
    _markOrderUpdated(_cart[index].product.id);
    _broadcast();
  }

  void removeCartItem(CartItem item) {
    final removed = _cart.remove(item);
    if (!removed) return;
    _broadcast();
  }

  void decreaseCartItem(CartItem item) {
    final index = _cart.indexOf(item);
    if (index == -1) return;

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
    final index = _cart.indexOf(item);
    if (index == -1) return;

    _cart[index].modifiers = List<CartItemModifier>.from(modifiers);
    _cart[index].notes = notes.trim();
    _broadcast();
  }

  Future<void> openDiningTable(String tableId) async {
    final definition = _findDiningTableDefinitionById(tableId);
    if (definition == null) return;

    if (activeDiningTableId != null && activeDiningTableId != tableId) {
      await returnToDiningFloorPlan();
    }

    final session = diningSessionFor(tableId);
    final canReuseCurrentCart =
        selectedOrderType == OrderType.dineIn &&
        activeDiningTableId == null &&
        _cart.isNotEmpty &&
        (session == null || session.status == DiningTableStatus.available);

    selectedOrderType = OrderType.dineIn;
    activeDiningTableId = tableId;
    selectedDiningFloorId = definition.floorId;
    diningTableSearchQuery = '';
    productSearchQuery = '';
    paymentStatus = 'Waiting';
    selectedPaymentMethod = 'Cash';
    lastPaymentMessage = '';
    _splitPayments.clear();
    _clearPaymentLaunchOverlay();
    _resetCharityRoundUp();

    if (session != null &&
        session.status == DiningTableStatus.occupied &&
        session.draft != null) {
      _cart
        ..clear()
        ..addAll(
          session.draft!.items.map((item) => CartItem.fromMap(item.toMap())),
        );
      currentOrderReference = session.orderReference.isNotEmpty
          ? session.orderReference
          : session.draft!.orderReference;
      selectedCategory = session.draft!.selectedCategory;
      customerReferenceNumber = session.draft!.customerReferenceNumber;
      discount = session.draft!.discount;
      splitCount = session.draft!.splitCount;
      _splitPayments.clear();
      displayNote = session.draft!.note.isNotEmpty
          ? session.draft!.note
          : _l10n.ctrlMsgEditingTableOnFloor(
              definition.name,
              _floorLabel(definition.floorId),
            );
    } else {
      if (!canReuseCurrentCart) {
        _cart.clear();
        selectedCategory = categories.first;
        customerReferenceNumber = '';
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
    if (selectedOrderType != OrderType.dineIn) return;

    await _flushActiveDiningTablePersistence();
    _resetForNextOrder(
      advanceOrderNumber: false,
      nextOrderType: OrderType.dineIn,
      clearActiveDiningTable: true,
      note: _l10n.ctrlMsgChooseTableDineIn,
    );
  }

  Future<void> clearActiveDiningTable() async {
    final tableId = activeDiningTableId;
    if (tableId == null) return;

    _cancelPendingDiningTablePersistence();
    await _orderStorage.clearDiningTable(tableId);
    diningTableSessions = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere((session) => session.tableId == tableId);
    _resetForNextOrder(
      advanceOrderNumber: false,
      nextOrderType: OrderType.dineIn,
      clearActiveDiningTable: true,
      note: _l10n.ctrlMsgChooseTableDineIn,
    );
  }

  Future<void> clearDiningTableById(String tableId) async {
    if (activeDiningTableId == tableId) {
      _cancelPendingDiningTablePersistence();
    }

    await _orderStorage.clearDiningTable(tableId);
    diningTableSessions = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere((session) => session.tableId == tableId);

    if (activeDiningTableId == tableId) {
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

  Future<void> openRearDisplay() async {
    if (!_presentationEnabled) return;

    try {
      rearDisplayOpened = await _presentation.openFirstRearDisplay();
      _notifySafely();
      if (rearDisplayOpened) {
        await Future.delayed(const Duration(milliseconds: 450));
        await syncRearDisplay();
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

  Future<void> printOnly() async {
    if (_cart.isEmpty) return;
    try {
      await SunmiReceiptService.printReceipt(snapshot(), template: receiptTemplate);
    } catch (error) {
      debugPrint('Receipt print failed: $error');
    }
  }

  Future<void> printHistoricalReceipt(OrderHistoryRecord record) async {
    try {
      await SunmiReceiptService.printReceipt(record.snapshot, template: receiptTemplate);
    } catch (error) {
      debugPrint('Receipt reprint failed: $error');
    }
  }

  /// Phase C1 — reprint the KITCHEN ticket for a past order. The caller is
  /// responsible for the manager gate (blueprint §6.10: kitchen ticket reprint
  /// requires Manager permission). Stamps the ORIGINAL order time + a REPRINT
  /// banner. Fail-safe (the service swallows printer errors).
  Future<void> printHistoricalKitchenTicket(OrderHistoryRecord record) async {
    await SunmiReceiptService.printKitchenTicket(
      _kitchenTicketFromSnapshot(
        record.snapshot,
        time: record.createdAt,
        isReprint: true,
      ),
    );
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
      orderLabel: 'Order #${s.orderNumber}',
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

  Future<String?> holdCurrentOrder() async {
    if (_cart.isEmpty || isProcessingPayment) return null;

    try {
      // Phase C2 — mint the server uuid at hold time (or keep the resumed
      // one) so the mirror, re-holds, the final order.create and a discard's
      // order.void all converge on one pos_orders row.
      final draft =
          createDraft(serverOrderUuid: _activeServerOrderUuid ??= uuidV4());
      await _orderStorage.saveHeldOrder(draft);
      await refreshHeldOrders();
      // Mirror server-side via the durable outbox (fire-and-forget).
      onOrderHeld?.call(draft);
      _activeServerOrderUuid = null; // consumed by the draft
      if (printKitchenTickets) {
        // Phase C1 — holding IS the "send to kitchen" moment today, so the
        // kitchen gets its ticket now (fail-safe; before the reset below so
        // the delivery-provider pick is still readable).
        await SunmiReceiptService.printKitchenTicket(
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
    discount = record.draft.discount;
    splitCount = record.draft.splitCount;
    _splitPayments.clear();
    _reserveOrderNumber(currentOrderNumber);
    paymentStatus = 'Waiting';
    selectedPaymentMethod = 'Cash';
    displayNote = record.draft.note;
    lastPaymentMessage = '';
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
  Future<String> discardHeldOrder(HeldOrderRecord record) async {
    await _orderStorage.deleteHeldOrder(record.id);
    await refreshHeldOrders();
    final uuid = record.draft.serverOrderUuid;
    if (uuid.isNotEmpty) {
      onOrderVoided?.call(
        uuid,
        orderNumber: record.orderNumber,
        reason: 'Held order discarded',
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
  }) async {
    final snapshot = record.snapshot;
    if (snapshot.isFullyCanceled) {
      return _l10n.ctrlMsgOrderAlreadyCanceled(record.orderNumber);
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
          authorizedBy: 'Manager',
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
            authorizedBy: 'Manager',
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
        );
      }
      return _l10n.ctrlMsgOrderFullyCanceled(record.orderNumber);
    }
    return _l10n.ctrlMsgItemsCanceledFromOrder(
      newCancellations.length,
      record.orderNumber,
    );
  }

  Future<String?> payAndPrint({double? cashTenderedAmount}) async {
    if (_cart.isEmpty || isProcessingPayment) return null;

    final transactionMethod = selectedPaymentMethod;
    final transactionSplitCount = splitCount;
    final transactionSplitIndex = activeSplitIndex;
    final transactionBaseAmount = activePaymentBaseTotal;
    final isDineInPayment =
        selectedOrderType == OrderType.dineIn && activeDiningTableId != null;

    _resetCharityRoundUp();
    _clearPaymentLaunchOverlay();
    isProcessingPayment = true;
    lastPaymentMessage = '';

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

      _clearPaymentLaunchOverlay();
      paymentStatus = 'Processing payment';
      displayNote = charityRoundUpAccepted
          ? _l10n.ctrlMsgTapToPayRoundUp
          : _l10n.ctrlMsgTapToPay;
      _broadcast();

      debugPrint(
        'PosController invoking Mosambee loginAndPay with amount=${payableTotal.toStringAsFixed(3)}',
      );

      final paymentResult = await _paymentBridge.loginAndPay(payableTotal);

      if (!paymentResult.isSuccess) {
        // Uncertain (NFC timeout / ambiguous, not an explicit cancel): offer the
        // cashier to force-record the charge as pending reconciliation so the
        // sale isn't lost — the admin queue settles it against the bank file.
        if (paymentResult.isUncertain &&
            await _promptForPendingReconciliation(amount: payableTotal)) {
          _clearPaymentLaunchOverlay();
          paymentStatus = 'Paid (pending reconciliation)';
          lastPaymentMessage = _l10n.ctrlMsgCardPendingReconRecorded;
          displayNote = _l10n.ctrlMsgPaymentPendingBankThanks;
          _broadcast();

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

        _clearPaymentLaunchOverlay();
        paymentStatus = paymentResult.isCanceled
            ? 'Payment canceled'
            : 'Payment failed';
        lastPaymentMessage = paymentResult.userMessage;
        displayNote = paymentResult.userMessage;
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
      _broadcast();
      await _restoreRearDisplayAfterPaymentIfNeeded();
    }
  }

  Future<String?> payMixedCashAndCard({required double cashAmount}) async {
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
    isProcessingPayment = true;
    lastPaymentMessage = '';

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

      _clearPaymentLaunchOverlay();
      paymentStatus = 'Processing payment';
      displayNote = charityRoundUpAccepted
          ? _l10n.ctrlMsgTapForRemainingSplitRoundUp
          : _l10n.ctrlMsgTapForRemainingSplit;
      _broadcast();

      debugPrint(
        'PosController invoking Mosambee split card payment with amount=${payableTotal.toStringAsFixed(3)}',
      );

      final paymentResult = await _paymentBridge.loginAndPay(payableTotal);

      var cardChargeStatus = 'success';
      if (!paymentResult.isSuccess) {
        // Uncertain charge → let the cashier force-record the card leg as
        // pending reconciliation; otherwise abort the whole split.
        if (!(paymentResult.isUncertain &&
            await _promptForPendingReconciliation(amount: payableTotal))) {
          _clearPaymentLaunchOverlay();
          paymentStatus = paymentResult.isCanceled
              ? 'Payment canceled'
              : 'Payment failed';
          lastPaymentMessage = paymentResult.userMessage;
          displayNote = paymentResult.userMessage;
          _broadcast();
          return lastPaymentMessage;
        }
        cardChargeStatus = 'pending_reconciliation';
      }

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

      return await _finishCompletedOrder(
        isDineInPayment: isDineInPayment,
        successMessage: lastPaymentMessage,
      );
    } finally {
      _activePaymentBaseOverride = null;
      _clearPaymentLaunchOverlay();
      isProcessingPayment = false;
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
    _assignFinalOrderNumber();
    // Stamp the server order_uuid now, so the saved record + the order.create
    // push share it — a later full-cancel can then emit a matching order.void.
    // A cart resumed from hold keeps its mirror's uuid (Phase C2), so the
    // server upserts the held row open instead of duplicating it.
    final completedSnapshot =
        snapshot().copyWith(serverOrderUuid: _activeServerOrderUuid ?? uuidV4());
    _activeServerOrderUuid = null;
    if (printReceipts) {
      // Fail-safe: a printer error must never abort the local save or the
      // pos_api push below.
      try {
        await SunmiReceiptService.printReceipt(completedSnapshot, template: receiptTemplate);
      } catch (error) {
        debugPrint('Receipt print failed: $error');
      }
    }
    if (printKitchenTickets) {
      // Phase C1 — the kitchen copy: items + add-ons + notes, no prices. The
      // service itself swallows printer errors.
      await SunmiReceiptService.printKitchenTicket(
        _kitchenTicketFromSnapshot(completedSnapshot, time: DateTime.now()),
      );
    }
    await _saveCompletedOrder(completedSnapshot);
    // Push the finalized order to pos_api (via the durable outbox). Fire-and-
    // forget: completion never waits on, or fails because of, the network.
    onOrderCompleted?.call(completedSnapshot);
    if (isDineInPayment) {
      await _markActiveDiningTablePaid(completedSnapshot);
    }

    await Future.delayed(const Duration(milliseconds: 700));
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
    _isDisposed = true;
    _rearDisplaySyncTimer?.cancel();
    _rearDisplaySyncPending = false;
    _diningTablePersistTimer?.cancel();
    super.dispose();
  }

  void _broadcast() {
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

  /// Ask the cashier whether to force-record an unconfirmed card charge as
  /// pending reconciliation. Resolves true to record, false to abort. Awaited
  /// inline inside the pay flow, so the in-flight transaction context survives.
  Future<bool> _promptForPendingReconciliation({required double amount}) async {
    if (_pendingReconCompleter != null && !_pendingReconCompleter!.isCompleted) {
      _pendingReconCompleter!.complete(false);
    }
    _pendingReconCompleter = Completer<bool>();
    _pendingReconAmount = amount;

    paymentStatus = 'Card charge not confirmed';
    showPendingReconciliationPrompt = true;
    _clearPaymentLaunchOverlay();
    displayNote = _l10n.ctrlMsgCardUnconfirmedReviewing;
    _broadcast();

    try {
      return await _pendingReconCompleter!.future.timeout(
        const Duration(minutes: 2),
      );
    } on TimeoutException {
      showPendingReconciliationPrompt = false;
      _broadcast();
      return false;
    } finally {
      _pendingReconCompleter = null;
    }
  }

  /// Cashier's answer to the pending-reconciliation prompt: [forceRecord] true
  /// records the card leg as pending_reconciliation, false aborts the payment.
  void confirmPendingReconciliation(bool forceRecord) {
    if (_pendingReconCompleter == null || _pendingReconCompleter!.isCompleted) {
      return;
    }
    showPendingReconciliationPrompt = false;
    _broadcast();
    _pendingReconCompleter!.complete(forceRecord);
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
    if (stage != 'login_started' && stage != 'payment_started') return;

    debugPrint(
      'PosController received Mosambee launch event: $stage on $surface.',
    );

    if (surface == 'rear') {
      _handoffRearDisplayToPayment();
    }

    paymentStatus = 'Processing payment';
    _showPaymentLaunchOverlay(
      title: stage == 'login_started'
          ? _l10n.ctrlOverlayConnectingTerminal
          : _l10n.ctrlOverlayWaitingPaymentResult,
      message: stage == 'login_started'
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
      await _orderStorage.saveCompletedOrder(completedSnapshot);
      await refreshOrderHistory();
    } catch (error) {
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
    final updated = List<DiningTableSession>.from(diningTableSessions)
      ..removeWhere((entry) => entry.tableId == activeDiningTableId);

    if (session != null) {
      updated.insert(0, session);
    }

    diningTableSessions = updated;
  }

  Future<void> _persistActiveDiningTableSession() async {
    if (selectedOrderType != OrderType.dineIn || activeDiningTableId == null) {
      return;
    }

    final tableId = activeDiningTableId!;
    final session = _buildActiveDiningTableSession();
    final existing = diningSessionFor(tableId);

    try {
      if (session == null) {
        if (existing == null) return;
        await _orderStorage.clearDiningTable(tableId);
      } else {
        await _orderStorage.saveDiningTableSession(session);
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
    );
  }

  Future<void> _markActiveDiningTablePaid(
    OrderSnapshot completedSnapshot,
  ) async {
    _cancelPendingDiningTablePersistence();
    await _diningTablePersistQueue;

    final paidSession = _buildActiveDiningTableSession(
      paidSnapshot: completedSnapshot,
    );
    if (paidSession == null) return;

    diningTableSessions = <DiningTableSession>[
      paidSession,
      ...diningTableSessions.where(
        (session) => session.tableId != paidSession.tableId,
      ),
    ];

    try {
      await _orderStorage.saveDiningTableSession(paidSession);
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
    _cart.clear();
    // Phase C2 — a leftover uuid (resumed-then-cleared cart) is dropped, not
    // voided: the server mirror stays held and remains resumable/discardable
    // from the held list of any branch terminal.
    _activeServerOrderUuid = null;
    paymentStatus = 'Waiting';
    selectedPaymentMethod = 'Cash';
    lastPaymentMessage = '';
    displayNote = note;
    paymentOverlayTitle = '';
    customerReferenceNumber = '';
    vehiclePlateNumber = '';
    selectedCustomer = null;
    currentOrderReference = '';
    isProcessingPayment = false;
    productSearchQuery = '';
    discount = const DiscountConfiguration();
    splitCount = 1;
    _splitPayments.clear();
    _lastCardCharge = null;
    loyaltyRedeemRuleId = null;
    loyaltyRedeemPoints = 0;
    appliedComp = null;
    showPendingReconciliationPrompt = false;
    _activePaymentBaseOverride = null;
    selectedOrderType = nextOrderType;
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
