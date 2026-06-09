import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/pos_models.dart';
import '../services/manager_authorization_service.dart';
import '../services/sunmi_receipt_service.dart';
import '../state/pos_controller.dart';
import '../widgets/animated_feedback_widgets.dart';
import '../providers/providers.dart';
import 'log_expense_screen.dart';
import 'restock_request_screen.dart';
import 'settings_screen.dart';
import 'shift_close_screen.dart';
import '../services/config_mapper.dart';

const _customizationGroups = <_ModifierGroupDefinition>[
  _ModifierGroupDefinition(
    step: 1,
    title: 'Size (Required)',
    requiredSelection: true,
    options: [
      _ModifierOptionDefinition(id: 'size_tall', label: 'Tall', price: 0),
      _ModifierOptionDefinition(id: 'size_grande', label: 'Grande', price: 0),
      _ModifierOptionDefinition(id: 'size_venti', label: 'Venti', price: 0.500),
    ],
  ),
  _ModifierGroupDefinition(
    step: 2,
    title: 'Milk Type',
    options: [
      _ModifierOptionDefinition(id: 'milk_whole', label: 'Whole', price: 0),
      _ModifierOptionDefinition(id: 'milk_2_percent', label: '2%', price: 0),
      _ModifierOptionDefinition(id: 'milk_oat', label: 'Oat', price: 0.500),
      _ModifierOptionDefinition(
        id: 'milk_almond',
        label: 'Almond',
        price: 0.500,
      ),
    ],
  ),
  _ModifierGroupDefinition(
    step: 3,
    title: 'Add-ons',
    multiSelect: true,
    options: [
      _ModifierOptionDefinition(
        id: 'addon_espresso_shot',
        label: 'Espresso Shot',
        price: 1.000,
      ),
      _ModifierOptionDefinition(
        id: 'addon_vanilla_syrup',
        label: 'Vanilla Syrup',
        price: 0.500,
      ),
      _ModifierOptionDefinition(
        id: 'addon_caramel_drizzle',
        label: 'Caramel Drizzle',
        price: 0.500,
      ),
    ],
  ),
];

const bool _staffVisualEffectsEnabled = bool.fromEnvironment(
  'POS_ENABLE_VISUAL_EFFECTS',
  defaultValue: false,
);

String _formatStorageDateTime(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = value.hour == 0
      ? 12
      : (value.hour > 12 ? value.hour - 12 : value.hour);
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '${months[value.month - 1]} ${value.day}, ${value.year} | ${hour.toString().padLeft(2, '0')}:$minute $meridiem';
}

class StaffPosScreen extends ConsumerStatefulWidget {
  const StaffPosScreen({super.key});

  @override
  ConsumerState<StaffPosScreen> createState() => _StaffPosScreenState();
}

class _StaffPosScreenState extends ConsumerState<StaffPosScreen> {
  late final PosController controller;
  late final TextEditingController _customerNumberController;
  late final TextEditingController _vehiclePlateController;
  late final ValueNotifier<DateTime> _clockNow;
  late final ScrollController _currentOrderScrollController;
  final ManagerAuthorizationService _managerAuthorization =
      ManagerAuthorizationService();
  Timer? _clockTimer;
  Timer? _popupTimer;
  bool _showPaymentPage = false;
  String _cashTenderInput = '';
  _StaffPopupMessage? _popupMessage;
  int _popupSeed = 0;
  ProviderSubscription<AsyncValue<CatalogSnapshot>>? _catalogSub;
  ProviderSubscription<AsyncValue<bool>>? _connectivitySub;

  static const double _designWidth = 1600;
  static const double _designHeight = 900;
  static const double _topBarHeight = 104;
  static const double _bottomBarHeight = 120;
  static const double _paymentHeaderHeight = 82;
  static const double _panelGap = 16;
  static const double _currentOrderPanelWidth = 660;
  static const double _middlePanelWidth = 284;
  static const double _productsPanelWidth = 624;

  static const _primaryOrderTypes = <OrderType>[
    OrderType.quickOrder,
    OrderType.toGo,
    OrderType.delivery,
    OrderType.dineIn,
  ];

  static const _secondaryNavItems = <_NavItemData>[
    _NavItemData('Home', Icons.home_outlined),
    _NavItemData('Report', Icons.description_outlined),
    _NavItemData('History', Icons.history_rounded),
  ];

  static const _categoryIcons = <String, IconData>{
    'Coffee': Icons.coffee_outlined,
    'Drinks': Icons.local_bar_outlined,
    'Food': Icons.restaurant_outlined,
    'Dessert': Icons.cake_outlined,
    'Bakery': Icons.bakery_dining_outlined,
    'Special': Icons.star_border_rounded,
  };

  @override
  void initState() {
    super.initState();
    controller = PosController();
    controller.onOrderCompleted = _handleOrderCompleted;
    // Keep the receipt-printing toggle in sync with Settings.
    controller.printReceipts = ref.read(settingsControllerProvider).printReceipts;
    ref.listenManual(settingsControllerProvider, (prev, next) {
      controller.printReceipts = next.printReceipts;
    });
    _customerNumberController = TextEditingController();
    _vehiclePlateController = TextEditingController();
    _clockNow = ValueNotifier<DateTime>(DateTime.now());
    _currentOrderScrollController = ScrollController();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _clockNow.value = DateTime.now();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.init();
      await controller.openRearDisplay();
      // Flush any orders queued in a previous session (e.g. completed offline).
      unawaited(ref.read(orderSyncRepositoryProvider).flush().catchError((_) => 0));
    });

    // Bridge: feed the branch catalog (from the Drift cache, refreshed from
    // pos_api) into the existing controller. fireImmediately covers the case
    // where the cache is already populated before this screen mounts.
    _catalogSub = ref.listenManual(
      catalogProvider,
      (previous, next) {
        final catalog = next.asData?.value;
        if (catalog != null) {
          controller.applyCatalog(
            categories: catalog.categories,
            products: catalog.products,
            floors: catalog.floors,
            tables: catalog.tables,
            taxes: catalog.taxes,
            addonGroups: catalog.addonGroups,
            deliveryProviders: catalog.deliveryProviders,
            ingredientBalances: catalog.ingredientBalances,
            discounts: catalog.discounts,
            loyaltyRules: catalog.loyaltyRules,
            customers: catalog.customers,
          );
        }
      },
      fireImmediately: true,
    );

    // Back online → refresh the cached config (best effort).
    _connectivitySub = ref.listenManual(
      connectivityProvider,
      (previous, next) {
        if (next.asData?.value == true) {
          unawaited(
            ref.read(configRepositoryProvider).syncConfig().catchError((_) {}),
          );
          // Back online → push any orders queued while offline.
          unawaited(
            ref.read(orderSyncRepositoryProvider).flush().catchError((_) => 0),
          );
        }
      },
    );
  }

  /// Push a finalized order to pos_api. Captures the device GPS (required at a
  /// geofenced branch — the server fails closed without it) + the staff id,
  /// then enqueues to the durable outbox, which persists the order before any
  /// network I/O and retries it on the next reconnect.
  Future<void> _handleOrderCompleted(OrderSnapshot snapshot) async {
    // Capture the customer + delivery inputs SYNCHRONOUSLY — the controller
    // resets them shortly after this callback fires, so reading them post-await
    // would race.
    final phone = controller.customerReferenceNumber.trim();
    final plate = controller.vehiclePlateNumber.trim();
    final deliveryProviderName = controller.selectedDeliveryProvider?.name;
    // A customer chosen from search attaches by id (their stored phone may carry
    // a +country prefix the numeric field strips, so re-resolving by phone could
    // mismatch).
    final searchedCustomer = controller.selectedCustomer;
    // Soft POS evidence for a single (non-split) card payment — read now, before
    // the controller's next-order reset clears it (split tenders carry their own
    // evidence on the snapshot's SplitPaymentRecords).
    final cardCharge = controller.lastCardCharge;

    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        lat = last?.latitude;
        lng = last?.longitude;
      } catch (_) {
        // No fix available — enqueue without GPS; a fenced branch will reject
        // it server-side and it stays queued until a fix is obtained.
      }
    }

    if (!mounted) return;
    final staffId = ref.read(sessionServiceProvider).staff?.id;
    final tableId = int.tryParse(snapshot.diningTableId);

    // Resolve the customer (find-or-create on phone, + register the plate).
    // Best-effort: offline, the order still saves — the plate rides on the
    // order itself, only the customer LINK is deferred.
    int? customerId;
    if (searchedCustomer != null) {
      customerId = searchedCustomer.id;
    } else if (phone.isNotEmpty) {
      try {
        customerId = await ref.read(apiServiceProvider).saveCustomer(
              name: phone, // no separate name field at the POS; phone is the key
              phone: phone,
              plateNumber: plate.isEmpty ? null : plate,
            );
      } catch (_) {
        // leave customerId null; the order is not blocked on this
      }
    }

    // Loyalty earn: only an identified customer accrues, under the active rule.
    final loyaltyRuleId =
        customerId != null ? controller.activeEarnRule?.id : null;

    try {
      await ref.read(orderSyncRepositoryProvider).enqueue(
            snapshot,
            lat: lat,
            lng: lng,
            staffId: staffId,
            tableId: tableId,
            customerId: customerId,
            plateNumber: plate.isEmpty ? null : plate,
            deliveryProviderName: deliveryProviderName,
            cardCharge: cardCharge,
            loyaltyRuleId: loyaltyRuleId,
          );
    } catch (_) {
      // The outbox persists the order before any network call, so it is queued
      // even if this throws; flush() retries on the next reconnect.
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _popupTimer?.cancel();
    _clockNow.dispose();
    _currentOrderScrollController.dispose();
    _customerNumberController.dispose();
    _vehiclePlateController.dispose();
    unawaited(controller.shutdown());
    controller.dispose();
    _catalogSub?.close();
    _connectivitySub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF12232B),
          body: Stack(
            children: [
              const Positioned.fill(
                child: RepaintBoundary(child: _BackgroundScene()),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final outerPadding = constraints.maxWidth < 1400
                        ? 10.0
                        : 16.0;
                    final availableWidth =
                        constraints.maxWidth - (outerPadding * 2);
                    final availableHeight =
                        constraints.maxHeight - (outerPadding * 2);
                    final contentHeight =
                        _designHeight -
                        _topBarHeight -
                        _bottomBarHeight -
                        (_panelGap * 2);

                    return Padding(
                      padding: EdgeInsets.all(outerPadding),
                      child: SizedBox(
                        width: availableWidth,
                        height: availableHeight,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: _designWidth,
                            height: _designHeight,
                            child: _showPaymentPage
                                ? _buildPaymentPageSurface()
                                : _showDineInFloorPlan
                                ? _buildDineInFloorPlanSurface(contentHeight)
                                : _buildCatalogSurface(contentHeight),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (controller.showCharityRoundUpPrompt)
                Positioned.fill(child: _buildStaffCharityFallbackOverlay()),
              if (controller.showPaymentLaunchOverlay &&
                  !controller.showCharityRoundUpPrompt)
                Positioned.fill(child: _buildStaffPaymentLaunchOverlay()),
              if (controller.isProcessingPayment &&
                  controller.selectedPaymentMethod == 'Cash' &&
                  !controller.showCharityRoundUpPrompt &&
                  !controller.showPaymentLaunchOverlay)
                Positioned.fill(child: _buildStaffCashProcessingOverlay()),
              if (controller.showPendingReconciliationPrompt)
                Positioned.fill(child: _buildPendingReconciliationOverlay()),
              _buildPopupMessageOverlay(),
            ],
          ),
        );
      },
    );
  }

  bool get _showDineInFloorPlan =>
      controller.selectedOrderType == OrderType.dineIn &&
      !controller.isEditingDiningTable;

  bool get _isEditingDiningTable => controller.isEditingDiningTable;

  String get _activeDiningTableLabel =>
      controller.activeDiningTableDefinition?.name ?? '';

  String _formatOccupancyDuration(DateTime? value) {
    if (value == null) return '0m';
    final difference = _clockNow.value.difference(value);
    if (difference.inHours >= 1) {
      final hours = difference.inHours;
      final minutes = difference.inMinutes.remainder(60);
      return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
    }
    final minutes = difference.inMinutes;
    return '${minutes < 1 ? 1 : minutes}m';
  }

  Widget _buildCatalogSurface(double contentHeight) {
    return Column(
      children: [
        SizedBox(height: _topBarHeight, child: _buildTopBar()),
        const SizedBox(height: _panelGap),
        SizedBox(
          height: contentHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _currentOrderPanelWidth,
                child: _buildCurrentOrderPanel(),
              ),
              const SizedBox(width: _panelGap),
              SizedBox(
                width: _middlePanelWidth,
                child: _buildCategoriesPanel(),
              ),
              const SizedBox(width: _panelGap),
              SizedBox(
                width: _productsPanelWidth,
                child: _buildProductsPanel(),
              ),
            ],
          ),
        ),
        const SizedBox(height: _panelGap),
        SizedBox(height: _bottomBarHeight, child: _buildBottomBar()),
      ],
    );
  }

  Widget _buildDineInFloorPlanSurface(double _) => _buildDineInFloorPlanPanel();

  Widget _buildDineInFloorPlanPanel() {
    final tables = controller.visibleDiningTables;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8FB),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEAF8F0),
            const Color(0xFFF7FAFC),
            const Color(0xFFE8F3FF).withValues(alpha: 0.92),
          ],
          stops: const [0, 0.48, 1],
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 74,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.66),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.72),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF86BFE0).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 390,
                  child: Row(
                    children: [
                      _CircleGlassButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () {
                          unawaited(
                            controller.selectOrderType(OrderType.quickOrder),
                          );
                        },
                      ),
                      const SizedBox(width: 18),
                      const Text(
                        'Floor Plan',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF17252C),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2F8).withValues(alpha: 0.84),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF9DB6C8,
                            ).withValues(alpha: 0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: controller.diningFloors
                            .map(
                              (floor) => _FloorSelectorChip(
                                label: floor.label,
                                selected:
                                    controller.selectedDiningFloorId ==
                                    floor.id,
                                onTap: () =>
                                    controller.selectDiningFloor(floor.id),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 530,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const _DiningLegendDot(
                        color: Color(0xFF20D362),
                        label: 'Free',
                      ),
                      const SizedBox(width: 12),
                      const _DiningLegendDot(
                        color: Color(0xFFFF7A1A),
                        label: 'Occupied',
                      ),
                      const SizedBox(width: 12),
                      const _DiningLegendDot(
                        color: Color(0xFF2B8E64),
                        label: 'Paid',
                      ),
                      const SizedBox(width: 18),
                      _DiningSearchPill(
                        hint: controller.diningTableSearchQuery.isEmpty
                            ? 'Search table or ticket...'
                            : controller.diningTableSearchQuery,
                        active: controller.diningTableSearchQuery.isNotEmpty,
                        onTap: () {
                          unawaited(_openDiningSearchKeyboard());
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 30, 30, 26),
              child: tables.isEmpty
                  ? _StorageEmptyState(
                      icon: Icons.table_restaurant_rounded,
                      title: 'No tables found',
                      message: controller.diningTableSearchQuery.isEmpty
                          ? 'This floor is ready for dine-in service.'
                          : 'No table or ticket matched your search.',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = constraints.maxWidth < 980
                            ? 2
                            : 3;
                        // 3 columns of ~405-wide cards (incl. 28px gaps) to
                        // match the floor-plan card spec on the 15-inch screen.
                        final maxGridWidth = crossAxisCount == 3
                            ? (constraints.maxWidth < 1271.0
                                  ? constraints.maxWidth
                                  : 1271.0)
                            : constraints.maxWidth;

                        return Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxGridWidth),
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              physics: const BouncingScrollPhysics(),
                              itemCount: tables.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 28,
                                    mainAxisSpacing: 26,
                                    childAspectRatio: 2.0,
                                  ),
                              itemBuilder: (context, index) {
                                final table = tables[index];
                                final session = controller.diningSessionFor(
                                  table.id,
                                );
                                final status =
                                    session?.status ??
                                    DiningTableStatus.available;

                                return _DiningTableCard(
                                  table: table,
                                  session: session,
                                  status: status,
                                  durationLabel: _formatOccupancyDuration(
                                    session?.occupiedAt,
                                  ),
                                  onTap: () async {
                                    if (status == DiningTableStatus.paid &&
                                        session != null) {
                                      await _openPaidDiningTableDialog(
                                        table,
                                        session,
                                      );
                                      return;
                                    }

                                    await controller.openDiningTable(table.id);
                                    if (!mounted) return;
                                    setState(() {
                                      _showPaymentPage = false;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentPage() async {
    if (controller.cart.isEmpty || controller.isProcessingPayment) {
      if (!mounted || controller.isProcessingPayment) return;
      _showPopupMessage(
        title: 'Order Required',
        message: 'Add at least one item before paying.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    setState(() {
      _showPaymentPage = true;
      _cashTenderInput = '';
    });
    _customerNumberController.text = controller.customerReferenceNumber;
    _vehiclePlateController.text = controller.vehiclePlateNumber;
  }

  Future<void> _submitCardPayment() async {
    if (controller.isProcessingPayment) return;
    controller.setCustomerReferenceNumber(_customerNumberController.text);
    controller.selectPaymentMethod('Credit Card');
    final message = await controller.payAndPrint();
    if (!mounted || message == null || message.isEmpty) return;

    if (controller.cart.isEmpty) {
      setState(() {
        _showPaymentPage = false;
        _cashTenderInput = '';
        _customerNumberController.clear();
      });
    }

    if (controller.cart.isNotEmpty && controller.splitCount > 1) {
      setState(() {
        _cashTenderInput = '';
      });
    }

    _showPopupMessage(
      title: _paymentMessageTitle(),
      message: message,
      tone: _paymentMessageTone(),
    );
  }

  Future<void> _submitCashPayment() async {
    if (controller.isProcessingPayment) return;
    final tendered = _tenderedCashAmount;
    if (tendered < controller.activePaymentBaseTotal) {
      _showPopupMessage(
        title: 'Tendered Amount Too Low',
        message:
            'Tendered cash must be at least ${SunmiReceiptService.money(controller.activePaymentBaseTotal)}.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    controller.setCustomerReferenceNumber(_customerNumberController.text);
    controller.selectPaymentMethod('Cash');
    final message = await controller.payAndPrint(cashTenderedAmount: tendered);
    if (!mounted || message == null || message.isEmpty) return;

    if (controller.cart.isEmpty) {
      setState(() {
        _showPaymentPage = false;
        _cashTenderInput = '';
        _customerNumberController.clear();
      });
    }

    if (controller.cart.isNotEmpty && controller.splitCount > 1) {
      setState(() {
        _cashTenderInput = '';
      });
    }

    _showPopupMessage(
      title: _paymentMessageTitle(),
      message: message,
      tone: _paymentMessageTone(),
    );
  }

  Future<void> _submitMixedPayment() async {
    if (controller.isProcessingPayment) return;
    if (controller.splitCount > 1 || controller.hasRecordedSplitPayments) {
      _showPopupMessage(
        title: 'Clear Split Bill First',
        message:
            'Cash and card split payment can be used after clearing guest split bill.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    final cashAmount = _tenderedCashAmount;
    if (cashAmount <= 0 ||
        cashAmount + 0.0005 >= controller.activePaymentBaseTotal) {
      _showPopupMessage(
        title: 'Enter Cash Portion',
        message:
            'Enter the cash amount first. It must be less than ${SunmiReceiptService.money(controller.activePaymentBaseTotal)} so the rest can go to card.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    controller.setCustomerReferenceNumber(_customerNumberController.text);
    final message = await controller.payMixedCashAndCard(
      cashAmount: cashAmount,
    );
    if (!mounted || message == null || message.isEmpty) return;

    if (controller.cart.isEmpty) {
      setState(() {
        _showPaymentPage = false;
        _cashTenderInput = '';
        _customerNumberController.clear();
      });
    }

    _showPopupMessage(
      title: _paymentMessageTitle(),
      message: message,
      tone: _paymentMessageTone(),
    );
  }

  void _closePaymentPage() {
    if (controller.isProcessingPayment ||
        controller.showCharityRoundUpPrompt ||
        controller.showPaymentLaunchOverlay) {
      return;
    }
    if (controller.hasRecordedSplitPayments && controller.cart.isNotEmpty) {
      _showPopupMessage(
        title: 'Split Payment In Progress',
        message: 'Finish all split payments before leaving checkout.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    setState(() {
      _showPaymentPage = false;
      _cashTenderInput = '';
      _customerNumberController.clear();
    });
    controller.setCustomerReferenceNumber('');
  }

  Future<void> _handleHoldOrder() async {
    final message = await controller.holdCurrentOrder();
    if (!mounted || message == null) return;

    setState(() {
      _showPaymentPage = false;
      _cashTenderInput = '';
      _customerNumberController.clear();
    });
    _showPopupMessage(
      title: 'Order Held',
      message: message,
      tone: FeedbackTone.success,
    );
  }

  Future<void> _openHeldOrdersDialog() async {
    await controller.refreshHeldOrders();
    if (!mounted) return;

    final resumed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Held Orders',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _StorageOverlayShell(
          title: 'Held Orders',
          subtitle:
              'Resume any paused ticket and continue from where you left off.',
          child: _HeldOrdersPanel(
            records: controller.heldOrders,
            onResume: (record) async {
              final message = await controller.resumeHeldOrder(record);
              if (!context.mounted) return;
              Navigator.of(context).pop(true);
              if (message != null && mounted) {
                _showPopupMessage(
                  title: 'Held Order Resumed',
                  message: message,
                  tone: FeedbackTone.success,
                );
              }
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );

    if (resumed == true && mounted) {
      setState(() {
        _showPaymentPage = false;
        _cashTenderInput = '';
        _customerNumberController.clear();
      });
    }
  }

  Future<void> _openOrderHistoryDialog() async {
    // Branch-wide history (cross-device) from the server when online; fall back
    // to the device-local store offline. This is what lets a freshly-paired or
    // second device at the branch see prior orders rung on other devices.
    try {
      final serverOrders = await ref.read(apiServiceProvider).fetchBranchOrders();
      controller.applyServerOrderHistory(serverOrders);
    } catch (_) {
      await controller.refreshOrderHistory();
    }
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Order History',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _StorageOverlayShell(
          title: 'Order History',
          subtitle:
              'Review completed orders, their payment details, and reprint receipts whenever needed.',
          child: _OrderHistoryPanel(
            records: controller.orderHistory,
            onRegisterManager: _registerManagerFingerprint,
            onPrint: (record) async {
              await controller.printHistoricalReceipt(record);
              if (!mounted) return;
              _showPopupMessage(
                title: 'Receipt Printed',
                message:
                    'Previous receipt for order #${record.orderNumber} was sent to the printer.',
                tone: FeedbackTone.success,
              );
            },
            onCancel: (record) => _handleOrderCancellationRequest(
              historyDialogContext: context,
              record: record,
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _registerManagerFingerprint() async {
    final registered = await _showFingerprintAuthorizationOverlay(
      title: 'Register Manager Fingerprint',
      message: 'Place the manager finger on the sensor to enable cancellation.',
      action: _managerAuthorization.registerManagerFingerprint,
    );
    if (!mounted) return;

    _showPopupMessage(
      title: registered ? 'Manager Registered' : 'Registration Not Completed',
      message: registered
          ? 'Manager fingerprint approval is ready for order cancellation.'
          : 'The manager fingerprint was not registered on this terminal.',
      tone: registered ? FeedbackTone.success : FeedbackTone.warning,
    );
  }

  Future<void> _handleOrderCancellationRequest({
    required BuildContext historyDialogContext,
    required OrderHistoryRecord record,
  }) async {
    var hasManager = await _managerAuthorization.isManagerRegistered();
    var authorized = false;
    if (!mounted) return;

    if (!hasManager) {
      hasManager = await _showFingerprintAuthorizationOverlay(
        title: 'Register Manager Fingerprint',
        message:
            'Register the manager fingerprint once before cancelling this completed order.',
        action: _managerAuthorization.registerManagerFingerprint,
      );
      if (!mounted) return;
      if (!hasManager) {
        if (historyDialogContext.mounted) {
          Navigator.of(historyDialogContext).pop();
        }
        _showPopupMessage(
          title: 'Manager Fingerprint Required',
          message:
              'The manager fingerprint was not registered on this terminal.',
          tone: FeedbackTone.warning,
        );
        return;
      }
      authorized = true;
    }

    if (!authorized && hasManager) {
      authorized = await _showFingerprintAuthorizationOverlay(
        title: 'Manager Approval Required',
        message: 'Place the manager fingerprint to unlock cancellation.',
        action: _managerAuthorization.authenticateCancellation,
      );
    }
    if (!mounted) return;

    if (!authorized) {
      if (historyDialogContext.mounted) {
        Navigator.of(historyDialogContext).pop();
      }
      _showPopupMessage(
        title: 'Cancellation Locked',
        message: 'Manager fingerprint was not approved.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    if (historyDialogContext.mounted) {
      Navigator.of(historyDialogContext).pop();
    }

    final message = await _openOrderCancellationDialog(record);
    if (!mounted || message == null || message.isEmpty) return;

    _showPopupMessage(
      title: message.contains('fully') ? 'Order Canceled' : 'Items Canceled',
      message: message,
      tone: FeedbackTone.success,
    );
  }

  Future<bool> _showFingerprintAuthorizationOverlay({
    required String title,
    required String message,
    required Future<bool> Function() action,
  }) async {
    return await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: false,
          barrierLabel: title,
          barrierColor: Colors.black.withValues(alpha: 0.38),
          pageBuilder: (context, animation, secondaryAnimation) {
            return _FingerprintAuthorizationDialog(
              title: title,
              message: message,
              action: action,
            );
          },
          transitionBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              ),
            );
          },
        ) ??
        false;
  }

  Future<String?> _openOrderCancellationDialog(
    OrderHistoryRecord record,
  ) async {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cancel Order',
      barrierColor: Colors.black.withValues(alpha: 0.36),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _OrderCancellationPage(
          record: record,
          onSubmit:
              ({required bool cancelFullOrder, required Set<int> itemIndexes}) {
                return controller.cancelCompletedOrder(
                  record,
                  cancelFullOrder: cancelFullOrder,
                  itemIndexes: itemIndexes,
                );
              },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openSearchKeyboard() async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: 'Search Products',
        initialValue: controller.productSearchQuery,
        hintText: 'Type product name or category',
      ),
    );

    if (value == null) return;
    controller.setProductSearchQuery(value);
  }

  /// Customer field tap: search the live book (with loyalty), or enter a number.
  Future<void> _openCustomerChooser() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_search_rounded),
              title: const Text('Search customer'),
              subtitle: const Text('Find by name / phone / plate, see loyalty'),
              onTap: () => Navigator.pop(ctx, 'search'),
            ),
            ListTile(
              leading: const Icon(Icons.dialpad_rounded),
              title: const Text('Enter number'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            if (controller.selectedCustomer != null ||
                controller.customerReferenceNumber.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Clear customer'),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'search':
        await _openCustomerSearch();
      case 'manual':
        await _openCustomerNumberKeyboard();
      case 'clear':
        setState(() => _customerNumberController.clear());
        controller.setCustomerReferenceNumber('');
    }
  }

  Future<void> _openCustomerSearch() async {
    final result = await showDialog<CustomerSearchResult>(
      context: context,
      builder: (_) => _CustomerSearchDialog(
        search: ref.read(apiServiceProvider).searchCustomers,
      ),
    );
    if (!mounted || result == null) return;
    controller.attachCustomer(result);
    setState(() => _customerNumberController.text =
        controller.customerReferenceNumber);
    final pts = controller.activeEarnRule != null
        ? result.pointsForRule(controller.activeEarnRule!.id)
        : 0;
    _showPopupMessage(
      title: 'Customer Attached',
      message: '${result.name}${pts > 0 ? '  ·  $pts points' : ''}',
      tone: FeedbackTone.success,
    );
  }

  Future<void> _openCustomerNumberKeyboard() async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: 'Customer Number',
        initialValue: _customerNumberController.text,
        hintText: 'Enter number for reference',
        numbersOnly: true,
      ),
    );

    if (value == null) return;

    setState(() {
      _customerNumberController.text = value;
    });
    controller.setCustomerReferenceNumber(value);
  }

  Future<void> _openVehiclePlateKeyboard() async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: 'Vehicle Plate',
        initialValue: _vehiclePlateController.text,
        hintText: 'Enter the car plate number',
      ),
    );

    if (value == null) return;

    final plate = value.trim().toUpperCase();
    setState(() {
      _vehiclePlateController.text = plate;
    });
    controller.setVehiclePlateNumber(plate);
  }

  Future<void> _handleOrderTypeTap(OrderType type) async {
    await controller.selectOrderType(type);
    if (!mounted) return;
    // Entering delivery: pick the provider first — its prices drive the menu.
    if (type == OrderType.delivery &&
        controller.selectedDeliveryProviderId == null) {
      await _openDeliveryProviderPicker();
    }
  }

  Future<void> _openDeliveryProviderPicker() async {
    final providers = controller.deliveryProviders;
    if (providers.isEmpty) {
      _showPlaceholderMessage(
        'No Delivery Providers',
        'No delivery providers are set up yet. Add them in the merchant portal.',
      );
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _DeliveryProviderPickerDialog(
        providers: providers,
        selectedId: controller.selectedDeliveryProviderId,
      ),
    );
    if (picked == null || !mounted) return;
    controller.selectDeliveryProvider(picked);
  }

  Future<void> _openDiningSearchKeyboard() async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: 'Search Tables',
        initialValue: controller.diningTableSearchQuery,
        hintText: 'Search by table name or ticket',
      ),
    );

    if (value == null) return;
    controller.setDiningTableSearchQuery(value);
  }

  Future<void> _openPaidDiningTableDialog(
    DiningTableDefinition table,
    DiningTableSession session,
  ) async {
    final snapshot = session.paidSnapshot;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 360,
            vertical: 150,
          ),
          child: _glassPanel(
            tint: const Color(0xEEF8FBFD),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${table.name} Paid',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16242B),
                        ),
                      ),
                    ),
                    _CircleGlassButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Ticket #${session.orderNumber ?? snapshot?.orderNumber ?? '-'} was paid successfully. Clear the table when it is ready for the next guest.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF23343C).withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _glassInsetCard(
                        child: _fallbackAmountBlock(
                          title: 'Paid Total',
                          amount: snapshot?.payableTotal ?? session.total,
                          tint: const Color(0xFFDDF5EA),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _glassInsetCard(
                        child: _fallbackAmountBlock(
                          title: 'Floor',
                          amount: 0,
                          tint: const Color(0xFFEAF2F8),
                          valueText: controller.diningFloors
                              .where((floor) => floor.id == table.floorId)
                              .map((floor) => floor.label)
                              .first,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _OutlineActionButton(
                        label: 'Close',
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FilledActionButton(
                        label: 'Clear Table',
                        onTap: () async {
                          Navigator.of(context).pop();
                          await controller.clearDiningTableById(table.id);
                          if (!mounted) return;
                          _showPopupMessage(
                            title: '${table.name} Cleared',
                            message:
                                '${table.name} is now available for the next guest.',
                            tone: FeedbackTone.success,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Discount entry point. Offers the currently-applicable merchant rules (from
  /// the cached catalog) first, plus a custom amount and a remove option. With
  /// no applicable rules it falls straight through to the manual editor.
  Future<void> _openDiscountDialog() async {
    final branchId = ref.read(sessionControllerProvider).branchId ?? 0;
    final now = DateTime.now();
    final applicable = controller.availableDiscounts
        .where((d) => d.isOrderScope && d.appliesAt(now, branchId: branchId))
        .toList();
    final redeem = _redeemable();

    if (applicable.isEmpty && redeem == null) {
      await _openManualDiscountDialog();
      return;
    }

    final action =
        await showModalBottomSheet<({String type, MerchantDiscount? rule})>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Apply a discount',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
            if (redeem != null)
              ListTile(
                leading: const Icon(Icons.card_giftcard_rounded),
                title: const Text('Redeem loyalty points'),
                subtitle: Text(
                  '${redeem.points} points available  ·  ${redeem.rule.name}',
                ),
                onTap: () => Navigator.pop(ctx, (type: 'redeem', rule: null)),
              ),
            for (final d in applicable)
              ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: Text(d.name),
                subtitle: Text(
                  _discountSubtitle(d) +
                      (d.requiresManagerApproval
                          ? '  ·  manager approval'
                          : ''),
                ),
                onTap: () => Navigator.pop(ctx, (type: 'rule', rule: d)),
              ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Custom amount'),
              onTap: () => Navigator.pop(ctx, (type: 'custom', rule: null)),
            ),
            if (controller.discount.isActive)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove discount'),
                onTap: () => Navigator.pop(ctx, (type: 'remove', rule: null)),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action.type) {
      case 'custom':
        await _openManualDiscountDialog();
      case 'remove':
        controller.clearDiscount();
        _showPopupMessage(
          title: 'Discount Cleared',
          message: 'The order discount has been removed.',
          tone: FeedbackTone.info,
        );
      case 'rule':
        await _applyMerchantDiscount(action.rule!);
      case 'redeem':
        await _openRedeemDialog();
    }
  }

  /// The redeemable spend-based rule for the attached customer (enough points
  /// for at least one redemption block), or null.
  ({LoyaltyRule rule, CustomerSearchResult customer, int points})? _redeemable() {
    final c = controller.selectedCustomer;
    if (c == null) return null;
    for (final r in controller.loyaltyRules) {
      if (!r.isActive || !r.isSpendBased) continue;
      if (r.redemptionPoints <= 0 || r.redemptionValue <= 0) continue;
      final pts = c.pointsForRule(r.id);
      final minNeeded =
          r.minRedemptionPoints > 0 ? r.minRedemptionPoints : r.redemptionPoints;
      if (pts >= minNeeded && pts >= r.redemptionPoints) {
        return (rule: r, customer: c, points: pts);
      }
    }
    return null;
  }

  Future<void> _openRedeemDialog() async {
    final redeem = _redeemable();
    if (redeem == null) return;
    final rule = redeem.rule;
    // Cap blocks by the balance AND the order subtotal (can't discount past it).
    final byBalance = redeem.points ~/ rule.redemptionPoints;
    final byTotal = rule.redemptionValue > 0
        ? (controller.rawSubtotal / rule.redemptionValue).floor()
        : 0;
    final maxBlocks = byBalance < byTotal ? byBalance : byTotal;
    if (maxBlocks < 1) {
      _showPopupMessage(
        title: 'Cannot Redeem',
        message: 'The order total is too low to redeem a block.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    final blocks = await showDialog<int>(
      context: context,
      builder: (_) => _RedeemBlocksDialog(
        maxBlocks: maxBlocks,
        pointsPerBlock: rule.redemptionPoints,
        valuePerBlock: rule.redemptionValue,
      ),
    );
    if (!mounted || blocks == null || blocks < 1) return;

    controller.applyLoyaltyRedemption(
      ruleId: rule.id,
      points: blocks * rule.redemptionPoints,
      valueOmr: blocks * rule.redemptionValue,
      label: 'Loyalty redemption',
    );
    _showPopupMessage(
      title: 'Points Redeemed',
      message:
          '${blocks * rule.redemptionPoints} points → ${SunmiReceiptService.money(blocks * rule.redemptionValue)} off.',
      tone: FeedbackTone.success,
    );
  }

  String _discountSubtitle(MerchantDiscount d) => d.amountType == 'percent'
      ? '${(d.percent ?? 0).toStringAsFixed(0)}% off'
      : '${SunmiReceiptService.money(d.fixedAmount ?? 0)} off';

  Future<void> _applyMerchantDiscount(MerchantDiscount d) async {
    if (d.requiresManagerApproval) {
      final ok = await _managerAuthorization.authenticateManagerApproval(
        subtitle: 'Approve discount',
        description: 'Place the manager fingerprint to approve "${d.name}".',
      );
      if (!mounted) return;
      if (!ok) {
        _showPopupMessage(
          title: 'Approval Required',
          message: 'Manager approval was not granted for "${d.name}".',
          tone: FeedbackTone.warning,
        );
        return;
      }
    }
    controller.applyDiscount(d.toConfiguration());
    _showPopupMessage(
      title: 'Discount Applied',
      message: '${d.name} is now active.',
      tone: FeedbackTone.success,
    );
  }

  Future<void> _openManualDiscountDialog() async {
    final value = await showDialog<DiscountConfiguration>(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          _DiscountDialog(initialDiscount: controller.discount),
    );

    if (value == null) return;
    if (value.isActive) {
      controller.applyDiscount(value);
      _showPopupMessage(
        title: 'Discount Applied',
        message:
            '${value.label.isEmpty ? 'Order discount' : value.label} is now active.',
        tone: FeedbackTone.success,
      );
    } else {
      controller.clearDiscount();
      _showPopupMessage(
        title: 'Discount Cleared',
        message: 'The order discount has been removed.',
        tone: FeedbackTone.info,
      );
    }
  }

  Future<void> _openSplitBillDialog() async {
    if (controller.hasRecordedSplitPayments) {
      _showPopupMessage(
        title: 'Split Payment In Progress',
        message: 'Finish all split payments before changing the guest count.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    final split = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SplitBillDialog(
        initialSplitCount: controller.splitCount,
        total: controller.total,
      ),
    );

    if (split == null) return;

    if (split <= 1) {
      controller.clearSplit();
      _showPopupMessage(
        title: 'Split Bill Cleared',
        message: 'The order is back to a single payment.',
        tone: FeedbackTone.info,
      );
    } else {
      controller.setSplitCount(split);
      _showPopupMessage(
        title: 'Split Bill Ready',
        message:
            'The order is split into $split shares of ${SunmiReceiptService.money(controller.activePaymentBaseTotal)} each.',
        tone: FeedbackTone.success,
      );
    }
  }

  void _showPlaceholderMessage(String title, String message) {
    _showPopupMessage(title: title, message: message, tone: FeedbackTone.info);
  }

  void _showPopupMessage({
    required String title,
    required String message,
    FeedbackTone tone = FeedbackTone.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    _popupTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _popupSeed++;
      _popupMessage = _StaffPopupMessage(
        id: _popupSeed,
        title: title,
        message: message,
        tone: tone,
      );
    });

    _popupTimer = Timer(duration, _dismissPopupMessage);
  }

  void _dismissPopupMessage() {
    _popupTimer?.cancel();
    _popupTimer = null;
    if (!mounted) return;
    setState(() {
      _popupMessage = null;
    });
  }

  FeedbackTone _paymentMessageTone() {
    return switch (controller.paymentStatus) {
      'Paid' => FeedbackTone.success,
      'Payment canceled' => FeedbackTone.warning,
      'Payment failed' => FeedbackTone.error,
      _ => FeedbackTone.info,
    };
  }

  String _paymentMessageTitle() {
    return switch (controller.paymentStatus) {
      'Paid' =>
        controller.selectedPaymentMethod == 'Cash'
            ? 'Cash Payment Complete'
            : 'Payment Approved',
      'Split payment pending' => 'Split Payment Recorded',
      'Payment canceled' => 'Payment Canceled',
      'Payment failed' => 'Payment Failed',
      _ => 'Payment Update',
    };
  }

  /// Resolve the modifier groups for a product: the add-on groups the merchant
  /// assigned to it (from the API config). Falls back to the bundled sample
  /// groups only when no company add-ons are loaded at all (demo / offline seed)
  /// so the dialog still demonstrates customization; a product with a live
  /// catalog but no assigned add-ons simply shows the notes field.
  List<_ModifierGroupDefinition> _resolveModifierGroups(Product product) {
    final apiGroups = controller.addonGroupsForProduct(product);
    if (apiGroups.isNotEmpty) {
      var step = 0;
      return apiGroups.map((group) {
        step++;
        return _ModifierGroupDefinition(
          step: step,
          title: group.name,
          multiSelect: group.multiSelect,
          options: group.options
              .map((option) => _ModifierOptionDefinition(
                    id: option.id.toString(),
                    label: option.label,
                    price: option.priceDelta,
                  ))
              .toList(),
        );
      }).toList();
    }
    if (controller.addonGroups.isEmpty) {
      return _customizationGroups;
    }
    return const <_ModifierGroupDefinition>[];
  }

  Future<void> _openCustomizeDialog(CartItem item) async {
    final result = await showDialog<_CartItemCustomizationResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomizeCartItemDialog(
        item: item,
        groups: _resolveModifierGroups(item.product),
      ),
    );

    if (!mounted || result == null) return;

    controller.updateCartItemCustomization(
      item,
      modifiers: result.modifiers,
      notes: result.notes,
    );
  }

  double get _tenderedCashAmount =>
      double.tryParse(_cashTenderInput.isEmpty ? '0' : _cashTenderInput) ?? 0;

  double get _cashChangeAmount {
    final change = _tenderedCashAmount - controller.activePaymentBaseTotal;
    if (change <= 0) return 0;
    return double.parse(change.toStringAsFixed(3));
  }

  double get _mixedCardBalance {
    final balance = controller.activePaymentBaseTotal - _tenderedCashAmount;
    if (balance <= 0) return 0;
    return double.parse(balance.toStringAsFixed(3));
  }

  bool get _showMixedCardBalance =>
      _tenderedCashAmount > 0 &&
      _tenderedCashAmount + 0.0005 < controller.activePaymentBaseTotal;

  List<int> _quickCashAmounts() {
    final base = controller.activePaymentBaseTotal.ceil();
    final values = <int>{if (base > 0) base, if (base > 0) base + 1, 5, 10};
    final sorted = values.toList()..sort();
    return sorted.take(4).toList();
  }

  void _setQuickCashAmount(int value) {
    setState(() {
      _cashTenderInput = value.toStringAsFixed(3);
    });
  }

  void _appendCashKey(String value) {
    setState(() {
      if (value == '.') {
        if (_cashTenderInput.contains('.')) return;
        _cashTenderInput = _cashTenderInput.isEmpty
            ? '0.'
            : '$_cashTenderInput.';
        return;
      }

      final parts = _cashTenderInput.split('.');
      final integerPart = parts.first;
      final fractionalPart = parts.length > 1 ? parts.last : '';

      if (_cashTenderInput.contains('.')) {
        if (fractionalPart.length >= 3) return;
      } else if (integerPart.length >= 6) {
        return;
      }

      if (_cashTenderInput == '0') {
        _cashTenderInput = value;
        return;
      }

      _cashTenderInput = '$_cashTenderInput$value';
    });
  }

  void _backspaceCashKey() {
    setState(() {
      if (_cashTenderInput.isEmpty) return;
      _cashTenderInput = _cashTenderInput.substring(
        0,
        _cashTenderInput.length - 1,
      );
      if (_cashTenderInput == '0.') {
        _cashTenderInput = '0';
      }
    });
  }

  Widget _buildPopupMessageOverlay() {
    return Positioned(
      top: 24,
      left: 0,
      right: 0,
      child: SafeArea(
        child: IgnorePointer(
          ignoring: _popupMessage == null,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.18),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _popupMessage == null
                  ? const SizedBox.shrink()
                  : AnimatedFeedbackPopupCard(
                      key: ValueKey('staff-popup-${_popupMessage!.id}'),
                      title: _popupMessage!.title,
                      message: _popupMessage!.message,
                      tone: _popupMessage!.tone,
                      onClose: _dismissPopupMessage,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffCharityFallbackOverlay() {
    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withValues(alpha: 0.34),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: _glassPanel(
              tint: const Color(0xE8F6FBFC),
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirm Charity Round-Up',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF16242B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose whether to add the optional charity donation before the payment terminal opens. The customer display will show the same totals.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF23343C).withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _glassInsetCard(
                          child: _fallbackAmountBlock(
                            title: 'Order Total',
                            amount: controller.activePaymentBaseTotal,
                            tint: const Color(0xFFE9F7FB),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _glassInsetCard(
                          child: _fallbackAmountBlock(
                            title: 'Round Up',
                            amount: controller.charityRoundUpAmount,
                            tint: const Color(0xFFFCEBC6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _glassInsetCard(
                          child: _fallbackAmountBlock(
                            title: 'New Total',
                            amount: controller.charityRoundUpTotal > 0
                                ? controller.charityRoundUpTotal
                                : controller.activePaymentBaseTotal,
                            tint: const Color(0xFFDDF5EA),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 84,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildCharityFallbackAction(
                            label: 'No, keep original total',
                            filled: false,
                            onTap: () =>
                                controller.confirmCharityRoundUp(false),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildCharityFallbackAction(
                            label: 'Yes, round up for charity',
                            filled: true,
                            onTap: () => controller.confirmCharityRoundUp(true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: _OutlinePillButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: controller.cancelCharityRoundUpPrompt,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Cashier-only confirm dialog shown when a card charge could not be
  /// confirmed (e.g. NFC timeout). The cashier either retries or force-records
  /// the card leg as pending reconciliation (settled later against the bank
  /// file). Wired to controller.confirmPendingReconciliation.
  Widget _buildPendingReconciliationOverlay() {
    return Material(
      color: Colors.black.withValues(alpha: 0.62),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCEBC6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB9770E),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Card charge not confirmed',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16242B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'The terminal did not confirm the '
                  '${SunmiReceiptService.money(controller.pendingReconciliationAmount)} '
                  'card charge (e.g. an NFC timeout).\n\n'
                  'If the customer was charged, record it as PENDING '
                  'RECONCILIATION — it will be matched against the bank '
                  'settlement file. Otherwise cancel and try the charge again.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF23343C).withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _pendingReconButton(
                        label: 'Cancel — retry charge',
                        filled: false,
                        onTap: () =>
                            controller.confirmPendingReconciliation(false),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _pendingReconButton(
                        label: 'Mark paid — pending reconciliation',
                        filled: true,
                        onTap: () =>
                            controller.confirmPendingReconciliation(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendingReconButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? const Color(0xFF1F8A70) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: filled ? Colors.transparent : const Color(0xFFB7C4CB),
              width: 1.4,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: filled ? Colors.white : const Color(0xFF23343C),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffPaymentLaunchOverlay() {
    return AbsorbPointer(
      absorbing: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ProfessionalProcessingCard(
                title: controller.paymentOverlayTitle.isEmpty
                    ? 'Preparing Payment'
                    : controller.paymentOverlayTitle,
                message: controller.displayNote.isEmpty
                    ? 'Please wait while the payment terminal opens.'
                    : controller.displayNote,
                badge: 'SECURE CARD PAYMENT',
                icon: Icons.credit_card_rounded,
                accent: const Color(0xFF0B6D8A),
                accentGlow: const Color(0xFF1599B8),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffCashProcessingOverlay() {
    return AbsorbPointer(
      absorbing: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ProfessionalProcessingCard(
                title: 'Recording Cash Payment',
                message: controller.displayNote.isEmpty
                    ? 'Please wait while the cash payment is completed.'
                    : controller.displayNote,
                badge: 'CASH CHECKOUT',
                icon: Icons.payments_rounded,
                accent: const Color(0xFF1AA148),
                accentGlow: const Color(0xFF40BE6C),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentPageSurface() {
    return Column(
      children: [
        SizedBox(height: _paymentHeaderHeight, child: _buildPaymentHeader()),
        const SizedBox(height: _panelGap),
        Expanded(child: _buildPaymentBody()),
      ],
    );
  }

  Widget _buildPaymentHeader() {
    return _glassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          _CircleGlassButton(
            icon: Icons.arrow_back_rounded,
            onTap: _closePaymentPage,
          ),
          const SizedBox(width: 14),
          const Text(
            'Payment',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF17252C),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD6F1E2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
              boxShadow: _softShadow,
            ),
            child: Text(
              controller.currentOrderReference.isEmpty
                  ? 'New Order'
                  : 'Ref ${controller.currentOrderReference}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF22523B),
              ),
            ),
          ),
          if (_isEditingDiningTable) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F0FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
                boxShadow: _softShadow,
              ),
              child: Text(
                'Table $_activeDiningTableLabel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF204E6A),
                ),
              ),
            ),
          ],
          const Spacer(),
          _buildTimeBlock(),
          const SizedBox(width: 12),
          _buildProfileBlock(),
        ],
      ),
    );
  }

  Widget _buildPaymentBody() {
    return _glassPanel(
      padding: const EdgeInsets.all(18),
      tint: const Color(0xA8F7FBFD),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF7FBFC),
          const Color(0xFFF3F9FF).withValues(alpha: 0.96),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 330, child: _buildPaymentOrderPanel()),
          const SizedBox(width: 18),
          Expanded(child: _buildPaymentConsole()),
        ],
      ),
    );
  }

  Widget _buildPaymentOrderPanel() {
    return _glassPanel(
      tint: Colors.white.withValues(alpha: 0.72),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF192831),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Scrollbar(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: controller.cart.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = controller.cart[index];
                  return _PaymentOrderItemCard(item: item);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (controller.selectedOrderType == OrderType.delivery) ...[
            _buildDeliveryProviderField(),
            const SizedBox(height: 16),
          ],
          _buildCustomerReferenceField(),
          const SizedBox(height: 16),
          _buildVehiclePlateField(),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
              boxShadow: _softShadow,
            ),
            child: Column(
              children: [
                _paymentTotalRow('Subtotal', controller.rawSubtotal),
                if (controller.discountAmount > 0) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow(
                    controller.discount.label.isEmpty
                        ? 'Discount'
                        : controller.discount.label,
                    -controller.discountAmount,
                  ),
                ],
                const SizedBox(height: 10),
                _paymentTotalRow('Net Subtotal', controller.subtotal),
                for (final t in controller.taxLines) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow('${t.name} (${t.rateLabel}%)', t.amount),
                ],
                if (controller.splitCount > 1) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow(
                    'Guest ${controller.activeSplitIndex} Share',
                    controller.activePaymentBaseTotal,
                  ),
                ],
                const SizedBox(height: 14),
                Container(height: 1, color: const Color(0xFFD9E5EA)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.splitCount > 1 ? 'Share Due' : 'Total Due',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF192831),
                        ),
                      ),
                    ),
                    Text(
                      SunmiReceiptService.money(
                        controller.activePaymentBaseTotal,
                      ),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1F8D54),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerReferenceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Number (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF192831),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('payment-customer-number'),
          onTap: _openCustomerChooser,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDCE8EC)),
              boxShadow: _softShadow,
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_outlined, color: Color(0xFF70818E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _customerNumberController.text.isEmpty
                        ? 'Add a customer number for reference'
                        : _customerNumberController.text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _customerNumberController.text.isEmpty
                          ? const Color(0xFF91A0AB)
                          : const Color(0xFF22323B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.dialpad_rounded, color: Color(0xFF4B5C67)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehiclePlateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehicle Plate (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF192831),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('payment-vehicle-plate'),
          onTap: _openVehiclePlateKeyboard,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDCE8EC)),
              boxShadow: _softShadow,
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car_outlined,
                    color: Color(0xFF70818E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _vehiclePlateController.text.isEmpty
                        ? 'Add a vehicle plate for drive-thru'
                        : _vehiclePlateController.text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _vehiclePlateController.text.isEmpty
                          ? const Color(0xFF91A0AB)
                          : const Color(0xFF22323B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_alt_outlined,
                    color: Color(0xFF4B5C67)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryProviderField() {
    final provider = controller.selectedDeliveryProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Provider',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF192831),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('payment-delivery-provider'),
          onTap: () => unawaited(_openDeliveryProviderPicker()),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDCE8EC)),
              boxShadow: _softShadow,
            ),
            child: Row(
              children: [
                const Icon(Icons.delivery_dining_outlined,
                    color: Color(0xFF70818E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider == null
                        ? 'Choose a delivery provider'
                        : provider.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: provider == null
                          ? const Color(0xFF91A0AB)
                          : const Color(0xFF22323B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more_rounded, color: Color(0xFF4B5C67)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentConsole() {
    final quickAmounts = _quickCashAmounts();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PaymentTopActionCard(
                icon: Icons.workspace_premium_rounded,
                title: 'Redeem Loyalty',
                onTap: () {
                  _showPlaceholderMessage(
                    'Loyalty Coming Next',
                    'We will connect reward redemption once the customer profile flow is ready.',
                  );
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _PaymentTopActionCard(
                icon: Icons.percent_rounded,
                title: 'Add Discount',
                accent: Color(0xFFFF8A2B),
                onTap: () {
                  unawaited(_openDiscountDialog());
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _PaymentTopActionCard(
                icon: Icons.call_split_rounded,
                title: 'Split Bill',
                onTap: () {
                  unawaited(_openSplitBillDialog());
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: _glassPanel(
                tint: Colors.white.withValues(alpha: 0.72),
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.84),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              boxShadow: _softShadow,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Tendered',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6B7A86),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      SunmiReceiptService.money(
                                        _tenderedCashAmount,
                                      ),
                                      key: const ValueKey('tendered-amount'),
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF1A2830),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 1,
                                  color: const Color(0xFFDCE7EB),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      _showMixedCardBalance
                                          ? 'Card Balance'
                                          : 'Change',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6B7A86),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      SunmiReceiptService.money(
                                        _showMixedCardBalance
                                            ? _mixedCardBalance
                                            : _cashChangeAmount,
                                      ),
                                      key: const ValueKey('change-amount'),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color: _showMixedCardBalance
                                            ? const Color(0xFF1B6F37)
                                            : const Color(0xFF1FA153),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: quickAmounts
                                .map(
                                  (amount) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: amount == quickAmounts.last
                                            ? 0
                                            : 10,
                                      ),
                                      child: _QuickCashButton(
                                        label: '$amount OMR',
                                        onTap: () =>
                                            _setQuickCashAmount(amount),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: Column(
                              children: [
                                if (controller.splitCount > 1)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE9F7FB),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFFD4E9F0),
                                      ),
                                    ),
                                    child: Text(
                                      'Collecting guest ${controller.activeSplitIndex} of ${controller.splitCount}: ${SunmiReceiptService.money(controller.activePaymentBaseTotal)}.',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF25414B),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Row(
                                    children: [
                                      _buildPaymentKeyCell('1'),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('2'),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('3'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Row(
                                    children: [
                                      _buildPaymentKeyCell('4'),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('5'),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('6'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Row(
                                    children: [
                                      _buildPaymentKeyCell('7'),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('8'),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('9'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Row(
                                    children: [
                                      _buildPaymentKeyCell(
                                        '.',
                                        buttonKey: const ValueKey(
                                          'payment-key-decimal',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildPaymentKeyCell('0'),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _PaymentKeyButton(
                                          buttonKey: const ValueKey(
                                            'payment-key-backspace',
                                          ),
                                          icon: Icons.backspace_outlined,
                                          onTap: _backspaceCashKey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    SizedBox(
                      width: 236,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: _PaymentMethodActionButton(
                              label: 'Cash',
                              icon: Icons.payments_outlined,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF1DB14A), Color(0xFF17A243)],
                              ),
                              onTap: _submitCashPayment,
                            ),
                          ),
                          const SizedBox(height: 14),
                          AspectRatio(
                            aspectRatio: 1,
                            child: _PaymentMethodActionButton(
                              label: 'Card',
                              icon: Icons.credit_card_rounded,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF2A8B42), Color(0xFF1F7236)],
                              ),
                              onTap: _submitCardPayment,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 86,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _PaymentBottomActionButton(
                                    label: 'Cancel',
                                    icon: Icons.close_rounded,
                                    onTap: _closePaymentPage,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _PaymentBottomActionButton(
                                    label: 'Split\nPayment',
                                    icon: Icons.call_split_rounded,
                                    filled: true,
                                    onTap: _submitMixedPayment,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _paymentTotalRow(String title, double amount) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF556571),
            ),
          ),
        ),
        Text(
          SunmiReceiptService.money(amount),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Color(0xFF33424A),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentKeyCell(String keyLabel, {Key? buttonKey}) {
    return Expanded(
      child: _PaymentKeyButton(
        buttonKey: buttonKey ?? ValueKey('payment-key-$keyLabel'),
        label: keyLabel,
        onTap: () => _appendCashKey(keyLabel),
      ),
    );
  }

  Widget _fallbackAmountBlock({
    required String title,
    required double amount,
    required Color tint,
    String? valueText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF32444D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            valueText ?? SunmiReceiptService.money(amount),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF18262D),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharityFallbackAction({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B7F9E), Color(0xFF0C5F78)],
                )
              : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: filled
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.88),
          ),
          boxShadow: _softShadow,
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: filled ? Colors.white : const Color(0xFF17252C),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return _glassPanel(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 13,
            child: _buildOrderTypeGroup(alignment: Alignment.centerLeft),
          ),
          const SizedBox(width: 12),
          _buildBrandBlock(),
          const SizedBox(width: 12),
          Expanded(
            flex: 10,
            child: _buildSecondaryNavGroup(alignment: Alignment.centerRight),
          ),
          const SizedBox(width: 8),
          _buildTimeBlock(),
          const SizedBox(width: 8),
          _CircleGlassButton(icon: Icons.settings_outlined, onTap: () {}),
          const SizedBox(width: 8),
          Flexible(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildProfileBlock(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeGroup({required Alignment alignment}) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Row(
          children: _primaryOrderTypes
              .asMap()
              .entries
              .map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    right: entry.key == _primaryOrderTypes.length - 1 ? 0 : 8,
                  ),
                  child: _HeaderNavChip(
                    title: entry.value.label,
                    icon: _orderTypeIcon(entry.value),
                    selected: controller.selectedOrderType == entry.value,
                    onTap: () {
                      unawaited(_handleOrderTypeTap(entry.value));
                    },
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildSecondaryNavGroup({required Alignment alignment}) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Row(
          children: _secondaryNavItems
              .asMap()
              .entries
              .map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    right: entry.key == _secondaryNavItems.length - 1 ? 0 : 8,
                  ),
                  child: _HeaderNavChip(
                    title: entry.value.title,
                    icon: entry.value.icon,
                    selected: false,
                    onTap: () {
                      switch (entry.value.title) {
                        case 'History':
                          unawaited(_openOrderHistoryDialog());
                          break;
                        case 'Report':
                          _showPlaceholderMessage(
                            'Reports Coming Next',
                            'We will connect detailed reporting once the local order archive is fully connected to the database flow.',
                          );
                          break;
                        default:
                          _showPlaceholderMessage(
                            'Home',
                            'You are already on the main POS screen.',
                          );
                      }
                    },
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  IconData _orderTypeIcon(OrderType type) {
    return switch (type) {
      OrderType.quickOrder => Icons.tune_rounded,
      OrderType.toGo => Icons.shopping_bag_outlined,
      OrderType.delivery => Icons.delivery_dining_outlined,
      OrderType.dineIn => Icons.storefront_outlined,
    };
  }

  Widget _buildBrandBlock() {
    return Container(
      width: 156,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _chipDecoration(selected: false),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'MITHQAL 2.0',
              maxLines: 1,
              style: TextStyle(
                color: Color(0xFF65789C),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Better ordering',
              maxLines: 1,
              style: TextStyle(
                color: Color(0xFF9EA7B0),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBlock() {
    return _ClockBlock(nowListenable: _clockNow);
  }

  Widget _buildProfileBlock() {
    final staff = ref.read(sessionControllerProvider).staff;
    final name = (staff?.name.isNotEmpty ?? false) ? staff!.name : 'Staff';
    final position = staff?.position ?? '';
    final positionLabel = position.isEmpty
        ? ''
        : '  ${position[0].toUpperCase()}${position.substring(1)}';
    return InkWell(
      onTap: _openStaffMenu,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 196),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _chipDecoration(selected: false),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFE6EBF0), Color(0xFFC7D2DA)],
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF5A6772),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF21262C),
                        ),
                      ),
                      TextSpan(
                        text: positionLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B6770),
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                ),
                const SizedBox(width: 8),
                const Icon(Icons.logout, size: 16, color: Color(0xFF5B6770)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Staff chip menu: close the cash-drawer shift, or log out.
  Future<void> _openStaffMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.point_of_sale_rounded),
              title: const Text('Close shift'),
              subtitle: const Text('Count the drawer and reconcile cash'),
              onTap: () => Navigator.pop(ctx, 'close_shift'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded),
              title: const Text('Log expense'),
              subtitle: const Text('Record a petty-cash expense'),
              onTap: () => Navigator.pop(ctx, 'log_expense'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_rounded),
              title: const Text('Request restock'),
              subtitle: const Text('Ask the branch to restock ingredients'),
              onTap: () => Navigator.pop(ctx, 'restock_request'),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              subtitle: const Text('Server address, printing'),
              onTap: () => Navigator.pop(ctx, 'settings'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              subtitle: const Text('Return to the staff PIN screen'),
              onTap: () => Navigator.pop(ctx, 'logout'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'logout') {
      await _confirmLogout();
    } else if (action == 'close_shift') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ShiftCloseScreen()),
      );
    } else if (action == 'log_expense') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LogExpenseScreen()),
      );
    } else if (action == 'restock_request') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RestockRequestScreen()),
      );
    } else if (action == 'settings') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will return to the staff PIN screen. The device stays set up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionControllerProvider.notifier).logoutStaff();
    }
  }

  Widget _buildCurrentOrderPanel() {
    return _glassPanel(
      tint: const Color(0xCCB9F1F4),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Current Order',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF16252A),
                      ),
                    ),
                    Text(
                      '(${controller.cart.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF24353B),
                      ),
                    ),
                    _OrderMetaChip(
                      label:
                          '${controller.currentOrderReference.isEmpty ? 'New' : 'Ref ${controller.currentOrderReference}'} | ${controller.selectedOrderType.label}',
                    ),
                    if (_isEditingDiningTable) ...[
                      _OrderMetaChip(label: 'Table $_activeDiningTableLabel'),
                      if (controller.activeDiningTableDefinition != null)
                        _OrderMetaChip(
                          label: controller.diningFloors
                              .where(
                                (floor) =>
                                    floor.id ==
                                    controller
                                        .activeDiningTableDefinition!
                                        .floorId,
                              )
                              .map((floor) => floor.label)
                              .first,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _OutlinePillButton(
                icon: _isEditingDiningTable
                    ? Icons.grid_view_rounded
                    : Icons.cleaning_services_outlined,
                label: _isEditingDiningTable ? 'Floor Plan' : 'Clear',
                onTap: _isEditingDiningTable
                    ? () {
                        unawaited(controller.returnToDiningFloorPlan());
                      }
                    : controller.clearForNextOrder,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: controller.cart.isEmpty
                ? const _EmptyOrderState()
                : Scrollbar(
                    controller: _currentOrderScrollController,
                    thumbVisibility: controller.cart.length > 3,
                    child: ListView.separated(
                      controller: _currentOrderScrollController,
                      primary: false,
                      itemCount: controller.cart.length,
                      physics: const BouncingScrollPhysics(),
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = controller.cart[index];
                        final pulseNonce =
                            controller.recentProductId == item.product.id
                            ? controller.orderUpdateNonce
                            : 0;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutBack,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0.08),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _OrderItemCard(
                            key: ValueKey(
                              '${item.product.id}_${item.qty}_${item.lineTotal}_${item.mergeSignature}',
                            ),
                            item: item,
                            onAdd: () => controller.incrementCartItem(item),
                            onRemove: () => controller.decreaseCartItem(item),
                            onDelete: () => controller.removeCartItem(item),
                            onCustomize: () {
                              unawaited(_openCustomizeDialog(item));
                            },
                            highlighted: pulseNonce > 0,
                            pulseNonce: pulseNonce,
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          _glassInsetCard(
            child: Column(
              children: [
                _summaryRow('Subtotal', controller.rawSubtotal),
                if (controller.discountAmount > 0) ...[
                  const SizedBox(height: 6),
                  _summaryRow(
                    controller.discount.label.isEmpty
                        ? 'Discount'
                        : controller.discount.label,
                    -controller.discountAmount,
                  ),
                ],
                const SizedBox(height: 6),
                _summaryRow('Net Subtotal', controller.subtotal),
                for (final t in controller.taxLines) ...[
                  const SizedBox(height: 6),
                  _summaryRow('${t.name} (${t.rateLabel}%)', t.amount),
                ],
                if (controller.splitCount > 1) ...[
                  const SizedBox(height: 6),
                  _summaryRow(
                    'Per Share (${controller.splitCount})',
                    controller.activePaymentBaseTotal,
                  ),
                ],
                const SizedBox(height: 6),
                _summaryRow('Total', controller.total, emphasize: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _isEditingDiningTable
                    ? _ActionSquareCard(
                        icon: Icons.grid_view_rounded,
                        title: 'Back To Floor',
                        tint: Color(0xFFDDF1FF),
                        foreground: Color(0xFF1C4257),
                        iconColor: Color(0xFF1B6B91),
                        onTap: () {
                          unawaited(controller.returnToDiningFloorPlan());
                        },
                      )
                    : _ActionSquareCard(
                        icon: Icons.pause_circle_outline_rounded,
                        title: 'Hold',
                        tint: Color(0xFFFFD7A4),
                        iconColor: Color(0xFFA56A15),
                        onTap: () {
                          unawaited(_handleHoldOrder());
                        },
                      ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _ActionSquareCard(
                  icon: _isEditingDiningTable
                      ? Icons.delete_sweep_rounded
                      : Icons.delete_outline_rounded,
                  title: _isEditingDiningTable ? 'Clear Table' : 'Void',
                  tint: Color(0xFFF6F0F0),
                  foreground: Color(0xFF1F2A31),
                  iconColor: Color(0xFF6B757C),
                  onTap: _isEditingDiningTable
                      ? () {
                          unawaited(controller.clearActiveDiningTable());
                        }
                      : controller.clearForNextOrder,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesPanel() {
    return _glassPanel(
      padding: const EdgeInsets.all(16),
      tint: const Color(0x1CFFFFFF),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.08),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Categories',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: controller.categories.length,
              physics: const BouncingScrollPhysics(),
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final category = controller.categories[index];
                final selected = category == controller.selectedCategory;
                return _CategoryCard(
                  title: category,
                  icon: _categoryIcons[category] ?? Icons.category_outlined,
                  selected: selected,
                  onTap: () => controller.selectCategory(category),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WideActionTile(
            icon: Icons.star_border_rounded,
            title: 'Favourites',
            onTap: () {
              _showPlaceholderMessage(
                'Favourites Coming Next',
                'We will wire favourite products to the local database in the next pass.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductsPanel() {
    final products = controller.visibleProducts;

    return _glassPanel(
      padding: const EdgeInsets.all(14),
      tint: const Color(0x18FFFFFF),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.06),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Products',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SearchPill(
                  width: double.infinity,
                  hint: controller.productSearchQuery.isEmpty
                      ? 'Search'
                      : controller.productSearchQuery,
                  active: controller.productSearchQuery.isNotEmpty,
                  onTap: () {
                    unawaited(_openSearchKeyboard());
                  },
                ),
              ),
              const SizedBox(width: 12),
              _TinyToggleChip(
                icon: Icons.format_list_bulleted_rounded,
                label: 'List',
                selected: controller.productViewMode == ProductViewMode.list,
                onTap: () =>
                    controller.setProductViewMode(ProductViewMode.list),
              ),
              const SizedBox(width: 8),
              _TinyToggleChip(
                icon: Icons.grid_view_rounded,
                label: 'Grid',
                selected: controller.productViewMode == ProductViewMode.grid,
                onTap: () =>
                    controller.setProductViewMode(ProductViewMode.grid),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: products.isEmpty
                ? _EmptyProductsState(
                    hasSearch: controller.productSearchQuery.isNotEmpty,
                    onClearSearch: controller.clearProductSearch,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth < 430
                          ? 1
                          : (constraints.maxWidth < 560 ? 2 : 3);
                      final compact = crossAxisCount >= 3;
                      final childAspectRatio = crossAxisCount == 1
                          ? 1.42
                          : (compact ? 0.96 : 1.26);

                      if (controller.productViewMode == ProductViewMode.list) {
                        return ListView.separated(
                          physics: const BouncingScrollPhysics(),
                          itemCount: products.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            final pulseNonce =
                                controller.recentProductId == product.id
                                ? controller.orderUpdateNonce
                                : 0;
                            return _ProductListTile(
                              product: product,
                              onAdd: () {
                                if (!controller.isOutOfStock(product)) {
                                  controller.addProduct(product);
                                }
                              },
                              outOfStock: controller.isOutOfStock(product),
                              highlighted: pulseNonce > 0,
                              pulseNonce: pulseNonce,
                            );
                          },
                        );
                      }

                      return GridView.builder(
                        itemCount: products.length,
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final pulseNonce =
                              controller.recentProductId == product.id
                              ? controller.orderUpdateNonce
                              : 0;
                          return _ProductTile(
                            product: product,
                            onAdd: () {
                              if (!controller.isOutOfStock(product)) {
                                controller.addProduct(product);
                              }
                            },
                            outOfStock: controller.isOutOfStock(product),
                            compact: compact,
                            highlighted: pulseNonce > 0,
                            pulseNonce: pulseNonce,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Row(
      children: [
        SizedBox(
          width: _currentOrderPanelWidth,
          child: _PayButton(
            total: controller.activePaymentBaseTotal,
            busy: controller.isProcessingPayment,
            onTap: () {
              unawaited(_openPaymentPage());
            },
          ),
        ),
        const SizedBox(width: _panelGap),
        Expanded(
          child: _glassPanel(
            height: 120,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _FooterActionCard(
                    icon: Icons.print_outlined,
                    title: 'Print',
                    onTap: () async {
                      await controller.printOnly();
                      if (!mounted) return;
                      _showPopupMessage(
                        title: 'Receipt Printed',
                        message:
                            'The current order receipt was sent to the printer.',
                        tone: FeedbackTone.success,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FooterActionCard(
                    icon: Icons.history_rounded,
                    title: 'Order History',
                    onTap: () {
                      unawaited(_openOrderHistoryDialog());
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FooterActionCard(
                    icon: Icons.pause_circle_outline_rounded,
                    title: 'Held Orders',
                    onTap: () {
                      unawaited(_openHeldOrdersDialog());
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FooterActionCard(
                    icon: Icons.loyalty_outlined,
                    title: 'Loyalty',
                    onTap: () {
                      _showPlaceholderMessage(
                        'Loyalty Coming Next',
                        'We will connect loyalty profiles after the order archive flow is finalized.',
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String title, double value, {bool emphasize = false}) {
    final style = TextStyle(
      fontSize: emphasize ? 15 : 13,
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
      color: emphasize ? const Color(0xFF16252A) : const Color(0xFF284149),
    );

    return Row(
      children: [
        Expanded(child: Text(title, style: style)),
        Text(SunmiReceiptService.money(value), style: style),
      ],
    );
  }
}

class _StaffPopupMessage {
  final int id;
  final String title;
  final String message;
  final FeedbackTone tone;

  const _StaffPopupMessage({
    required this.id,
    required this.title,
    required this.message,
    required this.tone,
  });
}

class _ClockBlock extends StatelessWidget {
  final ValueListenable<DateTime> nowListenable;

  const _ClockBlock({required this.nowListenable});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: ValueListenableBuilder<DateTime>(
          valueListenable: nowListenable,
          builder: (context, now, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatTime(now),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(now),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xE1FFFFFF),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute:$second $meridiem';
  }

  String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

class _NavItemData {
  final String title;
  final IconData icon;

  const _NavItemData(this.title, this.icon);
}

class _BackgroundScene extends StatelessWidget {
  const _BackgroundScene();

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/images/front_pos_background.jpg',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF182830), Color(0xFF2B3132), Color(0xFF6A5444)],
            ),
          ),
        );
      },
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_staffVisualEffectsEnabled)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: image,
          )
        else
          image,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.25, -0.55),
              radius: 1.1,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderNavChip extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _HeaderNavChip({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: _chipDecoration(selected: selected),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF242B31)),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                color: const Color(0xFF252C31),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: _chipDecoration(selected: false),
        child: Icon(icon, color: const Color(0xFF2A3136)),
      ),
    );
  }
}

class _OutlinePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlinePillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF516068)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E3E46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOrderState extends StatelessWidget {
  const _EmptyOrderState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 34,
                  color: Color(0xFF35505A),
                ),
                SizedBox(height: 8),
                Text(
                  'Tap any product to start the order',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A3F48),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'The cart, actions, and totals will appear here.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4A5E68),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderItemCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDelete;
  final VoidCallback onCustomize;
  final bool highlighted;
  final int pulseNonce;

  const _OrderItemCard({
    super.key,
    required this.item,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onCustomize,
    this.highlighted = false,
    this.pulseNonce = 0,
  });

  @override
  Widget build(BuildContext context) {
    final detailLines = item.detailLines;
    final subtitle =
        item.firstModifierLabel('Size (Required)') ?? item.product.category;

    return TweenAnimationBuilder<double>(
      key: ValueKey('cart-pulse-${item.mergeSignature}-$pulseNonce'),
      tween: Tween<double>(begin: highlighted ? 1 : 0, end: 0),
      duration: _staffVisualEffectsEnabled
          ? const Duration(milliseconds: 620)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, pulse, child) {
        final effectPulse = _staffVisualEffectsEnabled ? pulse : 0.0;
        return Transform.scale(
          scale: 1 + (effectPulse * 0.016),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.white.withValues(alpha: 0.74),
                const Color(0xFFF2FDFF),
                effectPulse * 0.72,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.72),
                  const Color(0xFF88E0F2),
                  effectPulse,
                )!,
                width: 1.2 + (effectPulse * 0.4),
              ),
              boxShadow: [
                ..._softShadow,
                if (effectPulse > 0.001)
                  BoxShadow(
                    color: const Color(
                      0x2E58CAE2,
                    ).withValues(alpha: 0.22 + (effectPulse * 0.16)),
                    blurRadius: 18 + (effectPulse * 14),
                    spreadRadius: effectPulse * 1.5,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProductArtwork(
            imageAsset: item.product.imageAsset,
            width: 84,
            height: 84,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.product.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF19262E),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFF5A6871),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4F6069),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Spacer(),
                    InkWell(
                      onTap: onCustomize,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F8F9),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Add On',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF28363E),
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 16,
                              color: Color(0xFF2F3E46),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (detailLines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...detailLines.map(
                    (detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5F727B),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _CounterButton(icon: Icons.remove_rounded, onTap: onRemove),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      alignment: Alignment.center,
                      child: Text(
                        '${item.qty}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1C2730),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CounterButton(icon: Icons.add_rounded, onTap: onAdd),
                    const Spacer(),
                    Text(
                      SunmiReceiptService.money(item.lineTotal),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C2C34),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOrderItemCard extends StatelessWidget {
  final CartItem item;

  const _PaymentOrderItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final detailLines = item.detailLines;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${item.qty}x ${item.product.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1C2A33),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                SunmiReceiptService.money(item.lineTotal),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1C2A33),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.product.category,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6A7984),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.qty} x ${SunmiReceiptService.money(item.unitPrice)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF83919A),
            ),
          ),
          if (detailLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...detailLines.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF60707A),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModifierGroupDefinition {
  final int step;
  final String title;
  final bool multiSelect;
  final bool requiredSelection;
  final List<_ModifierOptionDefinition> options;

  const _ModifierGroupDefinition({
    required this.step,
    required this.title,
    this.multiSelect = false,
    this.requiredSelection = false,
    required this.options,
  });
}

class _ModifierOptionDefinition {
  final String id;
  final String label;
  final double price;

  const _ModifierOptionDefinition({
    required this.id,
    required this.label,
    required this.price,
  });
}

class _CartItemCustomizationResult {
  final List<CartItemModifier> modifiers;
  final String notes;

  const _CartItemCustomizationResult({
    required this.modifiers,
    required this.notes,
  });
}

class _CustomizeCartItemDialog extends StatefulWidget {
  final CartItem item;
  final List<_ModifierGroupDefinition> groups;

  const _CustomizeCartItemDialog({required this.item, required this.groups});

  @override
  State<_CustomizeCartItemDialog> createState() =>
      _CustomizeCartItemDialogState();
}

class _CustomizeCartItemDialogState extends State<_CustomizeCartItemDialog> {
  late final TextEditingController _notesController;
  late final Map<String, Set<String>> _selectedByGroup;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.item.normalizedNotes);
    _selectedByGroup = <String, Set<String>>{
      for (final group in widget.groups)
        group.title: widget.item
            .modifiersForGroup(group.title)
            .map((modifier) => modifier.id)
            .toSet(),
    };

    for (final group in widget.groups) {
      if (group.requiredSelection && _selectedByGroup[group.title]!.isEmpty) {
        _selectedByGroup[group.title]!.add(group.options.first.id);
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  List<CartItemModifier> get _selectedModifiers {
    final modifiers = <CartItemModifier>[];

    for (final group in widget.groups) {
      final selectedIds = _selectedByGroup[group.title] ?? const <String>{};
      for (final option in group.options) {
        if (!selectedIds.contains(option.id)) continue;
        modifiers.add(
          CartItemModifier(
            id: option.id,
            group: group.title,
            label: option.label,
            price: option.price,
          ),
        );
      }
    }

    return modifiers;
  }

  bool get _canSubmit => widget.groups.every((group) {
    if (!group.requiredSelection) return true;
    return (_selectedByGroup[group.title] ?? const <String>{}).isNotEmpty;
  });

  double get _previewLineTotal {
    final modifierTotal = _selectedModifiers.fold<double>(
      0,
      (sum, modifier) => sum + modifier.price,
    );
    return (widget.item.product.price + modifierTotal) * widget.item.qty;
  }

  void _toggleOption(
    _ModifierGroupDefinition group,
    _ModifierOptionDefinition option,
  ) {
    setState(() {
      final selected = _selectedByGroup.putIfAbsent(
        group.title,
        () => <String>{},
      );

      if (group.multiSelect) {
        if (selected.contains(option.id)) {
          selected.remove(option.id);
        } else {
          selected.add(option.id);
        }
        return;
      }

      selected
        ..clear()
        ..add(option.id);
    });
  }

  void _submit() {
    if (!_canSubmit) return;

    Navigator.of(context).pop(
      _CartItemCustomizationResult(
        modifiers: _selectedModifiers,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 812, maxHeight: 690),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFEFE),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 36,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customize ${widget.item.product.name}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF17252C),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select add-ons and leave notes for this order line.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF73828E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F7F8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 25,
                        color: Color(0xFF52626B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final group in widget.groups) ...[
                        _CustomizeGroupSection(
                          group: group,
                          selectedIds:
                              _selectedByGroup[group.title] ?? const <String>{},
                          onToggle: (option) => _toggleOption(group, option),
                        ),
                        const SizedBox(height: 18),
                      ],
                      const Text(
                        'Notes',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF17252C),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('customize-notes'),
                        controller: _notesController,
                        maxLines: 3,
                        minLines: 3,
                        decoration: InputDecoration(
                          hintText:
                              'Add preparation notes for the kitchen or cashier',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF90A0AB),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF7FAFB),
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE8EC),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Color(0xFFDCE8EC),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: const BorderSide(
                              color: Color(0xFF1A8A52),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 70,
                      child: _OutlineActionButton(
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 70,
                      child: _FilledActionButton(
                        buttonKey: const ValueKey('customize-confirm'),
                        label:
                            'Apply ${SunmiReceiptService.money(_previewLineTotal)}',
                        onTap: _canSubmit ? _submit : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomizeGroupSection extends StatelessWidget {
  final _ModifierGroupDefinition group;
  final Set<String> selectedIds;
  final ValueChanged<_ModifierOptionDefinition> onToggle;

  const _CustomizeGroupSection({
    required this.group,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFDFF4E5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${group.step}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F7A47),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              group.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF17252C),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: group.options
              .map(
                (option) => SizedBox(
                  width: group.multiSelect ? 230 : 156,
                  child: _CustomizationOptionTile(
                    option: option,
                    multiSelect: group.multiSelect,
                    selected: selectedIds.contains(option.id),
                    onTap: () => onToggle(option),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _CustomizationOptionTile extends StatelessWidget {
  final _ModifierOptionDefinition option;
  final bool multiSelect;
  final bool selected;
  final VoidCallback onTap;

  const _CustomizationOptionTile({
    required this.option,
    required this.multiSelect,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('customize-option-${option.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: multiSelect ? 12 : 10,
          vertical: multiSelect ? 14 : 16,
        ),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1FBF4) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF2C9255) : const Color(0xFFDCE6EA),
            width: selected ? 1.8 : 1.1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: multiSelect
            ? Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: selected
                        ? const Color(0xFF1F7A47)
                        : const Color(0xFF6D7E89),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? const Color(0xFF175E36)
                            : const Color(0xFF2C3C45),
                      ),
                    ),
                  ),
                  if (option.price > 0)
                    Text(
                      '+${SunmiReceiptService.money(option.price)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? const Color(0xFF1F7A47)
                            : const Color(0xFF7D8C97),
                      ),
                    ),
                ],
              )
            : Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          option.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? const Color(0xFF175E36)
                                : const Color(0xFF364852),
                          ),
                        ),
                        if (option.price > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '+${SunmiReceiptService.money(option.price)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? const Color(0xFF1F7A47)
                                  : const Color(0xFF8B9AA5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF2C9255),
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(14),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CounterButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6F8),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _softShadow,
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF2E3D45)),
      ),
    );
  }
}

class _ActionSquareCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color tint;
  final Color foreground;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionSquareCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.tint = const Color(0xFFE8F3F5),
    this.foreground = const Color(0xFF102028),
    this.iconColor = const Color(0xFF203038),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 88,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.65),
            width: 1.2,
          ),
          boxShadow: _softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rippleController;
  Offset _tapPosition = const Offset(40, 35);

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!_staffVisualEffectsEnabled) return;

    setState(() {
      _tapPosition = details.localPosition;
    });
    _rippleController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedT = widget.selected ? 1.0 : 0.0;

        return AnimatedBuilder(
          animation: _rippleController,
          builder: (context, child) {
            final rippleT = Curves.easeOutCubic.transform(
              _rippleController.value,
            );
            final delayedRippleT = Curves.easeOut.transform(
              ((_rippleController.value - 0.14) / 0.86).clamp(0.0, 1.0),
            );
            final tertiaryRippleT = Curves.easeOut.transform(
              ((_rippleController.value - 0.28) / 0.72).clamp(0.0, 1.0),
            );

            final overlayTint = selectedT * 0.85 + rippleT * 0.45;

            return Transform.scale(
              scale: 1 + (selectedT * 0.024) + (rippleT * 0.01),
              child: InkWell(
                onTapDown: _handleTapDown,
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(22),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Builder(
                    builder: (context) {
                      final surface = Stack(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 70,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: widget.selected
                                    ? const [
                                        Color(0xA293EEFF),
                                        Color(0x967DDCF6),
                                        Color(0x8A54AFBB),
                                      ]
                                    : [
                                        Colors.white.withValues(alpha: 0.22),
                                        Colors.white.withValues(alpha: 0.14),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Color.lerp(
                                  Colors.white.withValues(alpha: 0.32),
                                  Colors.white.withValues(alpha: 0.72),
                                  overlayTint.clamp(0.0, 1.0),
                                )!,
                                width: 1.2 + (overlayTint * 0.45),
                              ),
                              boxShadow: [
                                const BoxShadow(
                                  color: Color(0x18FFFFFF),
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                                const BoxShadow(
                                  color: Color(0x16000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 10),
                                ),
                                if (overlayTint > 0.001)
                                  BoxShadow(
                                    color: const Color(0x455CCFEE).withValues(
                                      alpha: 0.08 + (overlayTint * 0.18),
                                    ),
                                    blurRadius: 18 + (overlayTint * 18),
                                    offset: const Offset(0, 8),
                                  ),
                              ],
                            ),
                            child: child,
                          ),
                          if (rippleT > 0.001) ...[
                            _LiquidGlassRipple(
                              center: _tapPosition,
                              progress: rippleT,
                              diameter: lerpDouble(
                                26,
                                constraints.maxWidth * 0.9,
                                rippleT,
                              )!,
                              fillOpacity: 0.18,
                              ringOpacity: 0.26,
                            ),
                            _LiquidGlassRipple(
                              center: _tapPosition,
                              progress: delayedRippleT,
                              diameter: lerpDouble(
                                16,
                                constraints.maxWidth * 1.26,
                                delayedRippleT,
                              )!,
                              fillOpacity: 0.08,
                              ringOpacity: 0.20,
                            ),
                            _LiquidGlassRipple(
                              center: _tapPosition,
                              progress: tertiaryRippleT,
                              diameter: lerpDouble(
                                14,
                                constraints.maxWidth * 1.48,
                                tertiaryRippleT,
                              )!,
                              fillOpacity: 0.0,
                              ringOpacity: 0.14,
                            ),
                          ],
                          if (overlayTint > 0.001) ...[
                            Positioned(
                              left: 10,
                              top: -8,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.32 + (selectedT * 0.16),
                                  child: Container(
                                    width: 92,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withValues(alpha: 0.78),
                                          Colors.white.withValues(alpha: 0.06),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: -8,
                              bottom: -18,
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: 0.16 + (overlayTint * 0.16),
                                  child: Container(
                                    width: 110,
                                    height: 54,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFBFF5FF),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );

                      if (!_staffVisualEffectsEnabled) return surface;

                      return BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 10 + (overlayTint * 7),
                          sigmaY: 10 + (overlayTint * 7),
                        ),
                        child: surface,
                      );
                    },
                  ),
                ),
              ),
            );
          },
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 26,
                color: widget.selected ? Colors.white : const Color(0xFF202B31),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: widget.selected
                        ? Colors.white
                        : const Color(0xFF202B31),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiquidGlassRipple extends StatelessWidget {
  final Offset center;
  final double progress;
  final double diameter;
  final double fillOpacity;
  final double ringOpacity;

  const _LiquidGlassRipple({
    required this.center,
    required this.progress,
    required this.diameter,
    required this.fillOpacity,
    required this.ringOpacity,
  });

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.001) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: center.dx - (diameter / 2),
      top: center.dy - (diameter / 2),
      child: IgnorePointer(
        child: Opacity(
          opacity: (1 - progress).clamp(0.0, 1.0),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: fillOpacity),
                  const Color(0xFFBDF4FF).withValues(alpha: fillOpacity * 0.9),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: ringOpacity),
                width: 1.2 + ((1 - progress) * 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TinyToggleChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _chipDecoration(selected: selected),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF202B31)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF202B31),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final double width;
  final String hint;
  final bool active;
  final VoidCallback onTap;

  const _SearchPill({
    required this.width,
    required this.hint,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: width,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: _chipDecoration(selected: false),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Color(0xFF283038)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active
                      ? const Color(0xFF22323B)
                      : const Color(0xFF5B6770),
                ),
              ),
            ),
            if (active) ...[
              const Spacer(),
              const Icon(Icons.edit_rounded, color: Color(0xFF3B4F58)),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderMetaChip extends StatelessWidget {
  final String label;

  const _OrderMetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF2A3E47),
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onClearSearch;

  const _EmptyProductsState({
    required this.hasSearch,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_off_rounded,
                size: 40,
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              Text(
                hasSearch
                    ? 'No products match your search.'
                    : 'No products available here yet.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasSearch
                    ? 'Try another product name or clear the current search.'
                    : 'Choose another category or add products to this category later.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Color(0xD9FFFFFF),
                ),
              ),
              if (hasSearch) ...[
                const SizedBox(height: 16),
                _OutlinePillButton(
                  icon: Icons.close_rounded,
                  label: 'Clear Search',
                  onTap: onClearSearch,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductListTile extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  final bool highlighted;
  final int pulseNonce;
  final bool outOfStock;

  const _ProductListTile({
    required this.product,
    required this.onAdd,
    this.highlighted = false,
    this.pulseNonce = 0,
    this.outOfStock = false,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('product-list-pulse-${product.id}-$pulseNonce'),
      tween: Tween<double>(begin: highlighted ? 1 : 0, end: 0),
      duration: _staffVisualEffectsEnabled
          ? const Duration(milliseconds: 560)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, pulse, child) {
        final effectPulse = _staffVisualEffectsEnabled ? pulse : 0.0;
        return Transform.scale(scale: 1 + (effectPulse * 0.018), child: child);
      },
      child: InkWell(
        onTap: outOfStock ? null : onAdd,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.90)),
            boxShadow: _softShadow,
          ),
          child: Row(
            children: [
              _ProductArtwork(
                imageAsset: product.imageAsset,
                width: 120,
                height: 86,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF17232B),
                            ),
                          ),
                        ),
                        if (outOfStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE1E1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'SOLD OUT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFB42318),
                              ),
                            ),
                          ),
                        if (product.lowStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD45D),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'LOW STOCK',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF2A2418),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.category,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF73838E),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          SunmiReceiptService.money(product.price),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF30424C),
                          ),
                        ),
                        const Spacer(),
                        _FilledMiniAction(label: 'Add', onTap: onAdd),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  final bool compact;
  final bool highlighted;
  final int pulseNonce;
  final bool outOfStock;

  const _ProductTile({
    required this.product,
    required this.onAdd,
    this.compact = false,
    this.highlighted = false,
    this.pulseNonce = 0,
    this.outOfStock = false,
  });

  @override
  Widget build(BuildContext context) {
    final artworkHeight = compact ? 72.0 : 96.0;
    final outerPadding = compact ? 8.0 : 10.0;
    final titleSize = compact ? 12.8 : 14.6;
    final priceSize = compact ? 11.6 : 13.2;
    final addButtonSize = compact ? 34.0 : 38.0;
    final addIconSize = compact ? 20.0 : 22.0;
    final badgeFontSize = compact ? 9.0 : 10.0;

    return TweenAnimationBuilder<double>(
      key: ValueKey('product-pulse-${product.id}-$pulseNonce'),
      tween: Tween<double>(begin: highlighted ? 1 : 0, end: 0),
      duration: _staffVisualEffectsEnabled
          ? const Duration(milliseconds: 560)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, pulse, child) {
        final effectPulse = _staffVisualEffectsEnabled ? pulse : 0.0;
        return Transform.scale(
          scale: 1 + (effectPulse * 0.026),
          child: InkWell(
            onTap: outOfStock ? null : onAdd,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: EdgeInsets.all(outerPadding),
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.84),
                  const Color(0xFFF5FEFF),
                  effectPulse * 0.82,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Color.lerp(
                    Colors.white.withValues(alpha: 0.90),
                    const Color(0xFF97E5F4),
                    effectPulse,
                  )!,
                  width: 1.2 + (effectPulse * 0.4),
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x22FFFFFF),
                    blurRadius: 2,
                    offset: Offset(0, -1),
                  ),
                  const BoxShadow(
                    color: Color(0x19000000),
                    blurRadius: 22,
                    offset: Offset(0, 12),
                  ),
                  if (effectPulse > 0.001)
                    BoxShadow(
                      color: const Color(
                        0x2258CAE2,
                      ).withValues(alpha: 0.08 + (effectPulse * 0.18)),
                      blurRadius: 24 + (effectPulse * 16),
                      offset: const Offset(0, 12),
                    ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _ProductArtwork(
                imageAsset: product.imageAsset,
                width: double.infinity,
                height: artworkHeight,
              ),
              if (outOfStock)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'SOLD OUT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              if (product.lowStock)
                Positioned(
                  top: compact ? 6 : 8,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 10,
                      vertical: compact ? 3 : 4,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFC84C),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: compact ? 11 : 14,
                          color: const Color(0xFF24211B),
                        ),
                        SizedBox(width: compact ? 3 : 4),
                        Text(
                          'LOW STOCK',
                          style: TextStyle(
                            fontSize: badgeFontSize,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF24211B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 7 : 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        product.name,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF17232B),
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: compact ? 3 : 2),
                      Text(
                        SunmiReceiptService.money(product.price),
                        style: TextStyle(
                          fontSize: priceSize,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF34454E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: addButtonSize,
                    height: addButtonSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FBFC),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: _softShadow,
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: addIconSize,
                      color: const Color(0xFF1E2C33),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductArtwork extends StatelessWidget {
  final String? imageAsset;
  final double width;
  final double height;

  const _ProductArtwork({
    required this.imageAsset,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF243640),
        child: imageAsset == null
            ? _placeholderArtwork()
            : Image.asset(
                imageAsset!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _placeholderArtwork();
                },
              ),
      ),
    );
  }

  Widget _placeholderArtwork() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF324C57), Color(0xFF111D24)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white70, size: 30),
      ),
    );
  }
}

class _PaymentTopActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  const _PaymentTopActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.accent = const Color(0xFFAF6CFF),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 110,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.84)),
          boxShadow: _softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: accent),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4E5E6A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCashButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickCashButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E6DB)),
          boxShadow: _softShadow,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2AA253),
          ),
        ),
      ),
    );
  }
}

class _PaymentKeyButton extends StatelessWidget {
  final Key? buttonKey;
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _PaymentKeyButton({
    this.buttonKey,
    this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: buttonKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
          boxShadow: _softShadow,
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: 24, color: const Color(0xFF8796A4))
              : Text(
                  label ?? '',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF33424E),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PaymentMethodActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _PaymentMethodActionButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: _softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: Colors.white),
            const SizedBox(height: 18),
            Text(
              label,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _OutlineActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
          boxShadow: _softShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: const Color(0xFF42515D)),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF33434D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentBottomActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _PaymentBottomActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF233145), Color(0xFF101927)],
                )
              : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: filled
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.92),
          ),
          boxShadow: _softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: filled ? Colors.white : const Color(0xFF6C7A88),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.05,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: filled ? Colors.white : const Color(0xFF3E4C58),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilledActionButton extends StatelessWidget {
  final Key? buttonKey;
  final String label;
  final VoidCallback? onTap;

  const _FilledActionButton({
    this.buttonKey,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return InkWell(
      key: buttonKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: disabled
              ? const LinearGradient(
                  colors: [Color(0xFFB5C7CF), Color(0xFF9DB3BC)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF208849), Color(0xFF166C39)],
                ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: _softShadow,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _WideActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _WideActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
          boxShadow: _softShadow,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF223038)),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF18252D),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _FooterActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
          boxShadow: _softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: const Color(0xFF223038)),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF14212A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final double total;
  final bool busy;
  final VoidCallback onTap;

  const _PayButton({
    required this.total,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: busy
                ? const [Color(0xFF5E8995), Color(0xFF48656F)]
                : const [Color(0xFF0B6D8A), Color(0xFF0F5167)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: _softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                busy
                    ? Icons.hourglass_top_rounded
                    : Icons.account_balance_wallet_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busy ? 'Processing Payment' : 'Process to Pay',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    busy
                        ? 'Completing order'
                        : 'PAY ${SunmiReceiptService.money(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilledMiniAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FilledMiniAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF208849), Color(0xFF166C39)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _FloorSelectorChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FloorSelectorChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: const BoxConstraints(minWidth: 92),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.96)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFCAE8D4) : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF8DA9B6).withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? const Color(0xFF1F7D47) : const Color(0xFF5A6C76),
          ),
        ),
      ),
    );
  }
}

class _DiningSearchPill extends StatelessWidget {
  final String hint;
  final bool active;
  final VoidCallback onTap;

  const _DiningSearchPill({
    required this.hint,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 214,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE7EF)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8DA9B6).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 19,
              color: Color(0xFF8B99A7),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active
                      ? const Color(0xFF22323B)
                      : const Color(0xFF8996A2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiningLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _DiningLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4E606A),
          ),
        ),
      ],
    );
  }
}

/// The dine-in card outline for a table's shape, at the grid-slot size. round
/// → capsule, oval → ellipse, square/counter/rectangle → rounded rectangles of
/// decreasing roundness. The `side` carries the status-colored border.
ShapeBorder _diningCardShape(String shape, BorderSide side) {
  switch (shape) {
    case 'oval':
      return OvalBorder(side: side);
    case 'round':
      return StadiumBorder(side: side);
    case 'square':
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: side,
      );
    case 'counter':
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: side,
      );
    default: // rectangle
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: side,
      );
  }
}

class _DiningTableCard extends StatelessWidget {
  final DiningTableDefinition table;
  final DiningTableSession? session;
  final DiningTableStatus status;
  final String durationLabel;
  final VoidCallback onTap;

  const _DiningTableCard({
    required this.table,
    required this.session,
    required this.status,
    required this.durationLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status) {
      DiningTableStatus.available => const Color(0xFF218947),
      DiningTableStatus.occupied => const Color(0xFFC9470F),
      DiningTableStatus.paid => const Color(0xFF277C4E),
    };
    final ticketColor = switch (status) {
      DiningTableStatus.available => const Color(0xFFDAF4E4),
      DiningTableStatus.occupied => const Color(0xFFFF7C22),
      DiningTableStatus.paid => const Color(0xFF3C8A57),
    };
    final background = switch (status) {
      DiningTableStatus.available => const [
        Color(0xFFFFFFFF),
        Color(0xFFFAFDFC),
      ],
      DiningTableStatus.occupied => const [
        Color(0xFFF7FFF6),
        Color(0xFFF7FCF4),
      ],
      DiningTableStatus.paid => const [Color(0xFFF2FBF3), Color(0xFFEAF7EC)],
    };
    final hasTicket = status != DiningTableStatus.available && session != null;

    // Same grid-slot size + position, but the card takes the table's SHAPE.
    // Children clip to it: the centered name + status sit inside every shape;
    // the corner ticket badge / dot show only on the rectangular shapes.
    final cardShape = _diningCardShape(
      table.shape,
      BorderSide(
        color: status == DiningTableStatus.available
            ? const Color(0xFFE8EEF0)
            : statusColor.withValues(alpha: 0.2),
        width: 2,
      ),
    );

    return InkWell(
      onTap: onTap,
      customBorder: cardShape,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: background,
          ),
          shape: cardShape,
          shadows: [
            BoxShadow(
              color: const Color(0xFF7896A8).withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.7),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
            if (status == DiningTableStatus.occupied)
              BoxShadow(
                color: const Color(0xFFFF8A2C).withValues(alpha: 0.1),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Stack(
          children: [
            if (hasTicket)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: ticketColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomRight: Radius.circular(13),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.receipt_long_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status == DiningTableStatus.paid
                            ? 'Ticket #${session!.orderNumber ?? '-'}'
                            : 'Ref ${session!.orderReference}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (status == DiningTableStatus.occupied)
              Positioned(
                top: 17,
                right: 17,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A1A),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF7A1A).withValues(alpha: 0.42),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            Center(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, hasTicket ? 24 : 18, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        table.name,
                        style: TextStyle(
                          height: 0.95,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (status == DiningTableStatus.available)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _TinyInfoBadge(
                            icon: Icons.people_alt_outlined,
                            label: 'Seats ${table.seats}',
                          ),
                          _StatusCapsule(
                            label: 'AVAILABLE',
                            color: const Color(0xFFD8F9E7),
                            foreground: const Color(0xFF218947),
                          ),
                        ],
                      )
                    else if (status == DiningTableStatus.occupied &&
                        session != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TinyInfoBadge(
                            label: SunmiReceiptService.money(session!.total),
                            strong: true,
                            foreground: const Color(0xFF9E3410),
                          ),
                          _TinyInfoBadge(
                            icon: Icons.schedule_rounded,
                            label: durationLabel,
                            tint: const Color(0xFFFFE0C5),
                            foreground: const Color(0xFF9E4F11),
                          ),
                          Container(
                            width: 1,
                            height: 15,
                            color: const Color(0xFFF4B178),
                          ),
                          const Text(
                            'OCCUPIED',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEA6614),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDDF5E6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Color(0xFF247246),
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Text(
                            'PAID / CLEAR',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF247246),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyInfoBadge extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool strong;
  final Color? tint;
  final Color? foreground;

  const _TinyInfoBadge({
    this.icon,
    required this.label,
    this.strong = false,
    this.tint,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final color = foreground ?? const Color(0xFF485B66);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tint ?? Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE8ED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCapsule extends StatelessWidget {
  final String label;
  final Color color;
  final Color foreground;

  const _StatusCapsule({
    required this.label,
    required this.color,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: foreground,
        ),
      ),
    );
  }
}

class _StorageOverlayShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _StorageOverlayShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 760),
              child: _glassPanel(
                padding: const EdgeInsets.all(24),
                tint: const Color(0xEAF8FBFD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF18262F),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF566973),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        _CircleGlassButton(
                          icon: Icons.close_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeldOrdersPanel extends StatelessWidget {
  final List<HeldOrderRecord> records;
  final Future<void> Function(HeldOrderRecord record) onResume;

  const _HeldOrdersPanel({required this.records, required this.onResume});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _StorageEmptyState(
        icon: Icons.pause_circle_outline_rounded,
        title: 'No held orders yet',
        message:
            'Any order you place on hold will appear here so the staff can continue it later.',
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: records.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final record = records[index];
        return _HeldOrderCard(record: record, onResume: () => onResume(record));
      },
    );
  }
}

class _OrderHistoryPanel extends StatelessWidget {
  final List<OrderHistoryRecord> records;
  final Future<void> Function() onRegisterManager;
  final Future<void> Function(OrderHistoryRecord record) onPrint;
  final Future<void> Function(OrderHistoryRecord record) onCancel;

  const _OrderHistoryPanel({
    required this.records,
    required this.onRegisterManager,
    required this.onPrint,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ManagerAuthorizationBanner(onRegister: onRegisterManager),
        const SizedBox(height: 14),
        Expanded(
          child: records.isEmpty
              ? const _StorageEmptyState(
                  icon: Icons.history_rounded,
                  title: 'No completed orders yet',
                  message:
                      'Completed payments will be archived here so the staff can review them or print receipts again.',
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: records.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return _OrderHistoryCard(
                      record: record,
                      onPrint: () => onPrint(record),
                      onCancel: () => onCancel(record),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ManagerAuthorizationBanner extends StatelessWidget {
  final Future<void> Function() onRegister;

  const _ManagerAuthorizationBanner({required this.onRegister});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE5F3EA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              color: Color(0xFF1E7B47),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manager cancellation approval',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF18262E),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Register once, then use fingerprint approval before opening completed order cancellation.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5D6E78),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 212,
            height: 52,
            child: _OutlineActionButton(
              label: 'Register Manager',
              icon: Icons.fingerprint_rounded,
              onTap: () => unawaited(onRegister()),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _StorageEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: _softShadow,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: const Color(0xFF46616C)),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A2A33),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF60727C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeldOrderCard extends StatelessWidget {
  final HeldOrderRecord record;
  final VoidCallback onResume;

  const _HeldOrderCard({required this.record, required this.onResume});

  double get _rawSubtotal =>
      record.draft.items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get _discountAmount {
    final discount = record.draft.discount;
    if (!discount.isActive) return 0;
    final calculated = switch (discount.kind) {
      DiscountKind.fixedAmount => discount.value,
      DiscountKind.percentage => _rawSubtotal * (discount.value / 100),
      DiscountKind.none => 0,
    };
    return calculated.clamp(0.0, _rawSubtotal).toDouble();
  }

  double get _total {
    final subtotal = (_rawSubtotal - _discountAmount)
        .clamp(0.0, double.infinity)
        .toDouble();
    final tax = subtotal * 0.05;
    return double.parse((subtotal + tax).toStringAsFixed(3));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
        boxShadow: _softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Ref ${record.orderReference}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF18262E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _OrderMetaChip(label: record.orderType.label),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatStorageDateTime(record.heldAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF71818C),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoBadge(
                      icon: Icons.receipt_long_rounded,
                      label: '${record.draft.items.length} items',
                    ),
                    _InfoBadge(
                      icon: Icons.payments_outlined,
                      label: SunmiReceiptService.money(_total),
                    ),
                    if (record.draft.splitCount > 1)
                      _InfoBadge(
                        icon: Icons.call_split_rounded,
                        label: 'Split ${record.draft.splitCount}',
                      ),
                    if (record.draft.customerReferenceNumber.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.phone_outlined,
                        label: record.draft.customerReferenceNumber,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  record.draft.items
                      .map((item) => '${item.qty}x ${item.product.name}')
                      .take(4)
                      .join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF556873),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 176,
            child: _FilledActionButton(
              label: 'Continue Order',
              onTap: onResume,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  final OrderHistoryRecord record;
  final VoidCallback onPrint;
  final VoidCallback onCancel;

  const _OrderHistoryCard({
    required this.record,
    required this.onPrint,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = record.snapshot;
    // Server-sourced history is terminal + not locally mutable — no cancel.
    final canCancel = !snapshot.isFullyCanceled && !record.fromServer;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
        boxShadow: _softShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Order #${record.orderNumber}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF18262E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _OrderMetaChip(label: record.orderType.label),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatStorageDateTime(record.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF71818C),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (snapshot.paymentMethod.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.credit_card_rounded,
                        label: snapshot.paymentMethod,
                      ),
                    _InfoBadge(
                      icon: snapshot.cancellations.isEmpty
                          ? Icons.task_alt_rounded
                          : Icons.cancel_rounded,
                      label: snapshot.paymentStatus,
                    ),
                    _InfoBadge(
                      icon: Icons.payments_outlined,
                      label: SunmiReceiptService.money(snapshot.payableTotal),
                    ),
                    if (snapshot.splitPayments.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.call_split_rounded,
                        label: '${snapshot.splitPayments.length} splits',
                      ),
                    if (snapshot.cancellations.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.remove_circle_outline_rounded,
                        label:
                            'Canceled ${SunmiReceiptService.money(snapshot.canceledAmount)}',
                      ),
                    if (snapshot.customerReferenceNumber.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.phone_outlined,
                        label: snapshot.customerReferenceNumber,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  snapshot.items
                      .map((item) => '${item['qty']}x ${item['name']}')
                      .take(4)
                      .join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF556873),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 168,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 52,
                  child: _OutlineActionButton(
                    label: 'Print',
                    icon: Icons.print_outlined,
                    onTap: onPrint,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: _HistoryCancelButton(
                    enabled: canCancel,
                    onTap: onCancel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCancelButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _HistoryCancelButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFFFFF1EC)
                  : Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
              boxShadow: _softShadow,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  enabled ? Icons.cancel_outlined : Icons.task_alt_rounded,
                  size: 21,
                  color: enabled
                      ? const Color(0xFFB84524)
                      : const Color(0xFF60727C),
                ),
                const SizedBox(width: 9),
                Text(
                  enabled ? 'Cancel' : 'Canceled',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: enabled
                        ? const Color(0xFF9A351B)
                        : const Color(0xFF60727C),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF39505B)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF344952),
            ),
          ),
        ],
      ),
    );
  }
}

class _FingerprintAuthorizationDialog extends StatefulWidget {
  final String title;
  final String message;
  final Future<bool> Function() action;

  const _FingerprintAuthorizationDialog({
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  State<_FingerprintAuthorizationDialog> createState() =>
      _FingerprintAuthorizationDialogState();
}

class _FingerprintAuthorizationDialogState
    extends State<_FingerprintAuthorizationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    unawaited(_runAuthorization());
  }

  Future<void> _runAuthorization() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final approved = await widget.action();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.of(context).pop(approved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _glassPanel(
              padding: const EdgeInsets.all(30),
              tint: const Color(0xF4F8FBFD),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final pulse = 0.72 + (_controller.value * 0.28);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: 1.45 * pulse,
                            child: Container(
                              width: 118,
                              height: 118,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(
                                    0xFF1E8D54,
                                  ).withValues(alpha: 0.16),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: 1.12 * pulse,
                            child: Container(
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(
                                  0xFFDDF5EA,
                                ).withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                          Container(
                            width: 86,
                            height: 86,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF25A85B), Color(0xFF176D3A)],
                              ),
                            ),
                            child: const Icon(
                              Icons.fingerprint_rounded,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18262E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5B6D77),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1E8D54),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Waiting for fingerprint',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF344A54),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _OrderCancellationSubmit =
    Future<String> Function({
      required bool cancelFullOrder,
      required Set<int> itemIndexes,
    });

class _OrderCancellationPage extends StatefulWidget {
  final OrderHistoryRecord record;
  final _OrderCancellationSubmit onSubmit;

  const _OrderCancellationPage({required this.record, required this.onSubmit});

  @override
  State<_OrderCancellationPage> createState() => _OrderCancellationPageState();
}

class _OrderCancellationPageState extends State<_OrderCancellationPage> {
  final Set<int> _selectedIndexes = <int>{};
  bool _busy = false;

  OrderSnapshot get _snapshot => widget.record.snapshot;

  Future<void> _submit({required bool fullOrder}) async {
    if (_busy) return;
    if (!fullOrder && _selectedIndexes.isEmpty) return;

    setState(() {
      _busy = true;
    });

    final message = await widget.onSubmit(
      cancelFullOrder: fullOrder,
      itemIndexes: fullOrder ? const <int>{} : Set<int>.from(_selectedIndexes),
    );
    if (!mounted) return;
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final selectableCount = snapshot.items.asMap().entries.where((entry) {
      return !snapshot.isItemCanceled(entry.key);
    }).length;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
              child: _glassPanel(
                padding: const EdgeInsets.all(24),
                tint: const Color(0xF2F8FBFD),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFECE7),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.cancel_schedule_send_rounded,
                            color: Color(0xFFB84524),
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cancel Order #${widget.record.orderNumber}',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF18262E),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Manager approved. Cancel the full order or select the completed items to cancel.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(
                                    0xFF566973,
                                  ).withValues(alpha: 0.92),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        _CircleGlassButton(
                          icon: Icons.close_rounded,
                          onTap: _busy
                              ? () {}
                              : () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 318,
                            child: _CancellationSummaryPanel(
                              record: widget.record,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Order Items',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF18262E),
                                      ),
                                    ),
                                    const Spacer(),
                                    _InfoBadge(
                                      icon: Icons.inventory_2_outlined,
                                      label: '$selectableCount cancellable',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ListView.separated(
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: snapshot.items.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final item = snapshot.items[index];
                                      final canceled = snapshot.isItemCanceled(
                                        index,
                                      );
                                      return _CancellationItemRow(
                                        item: item,
                                        selected: _selectedIndexes.contains(
                                          index,
                                        ),
                                        canceled: canceled,
                                        onChanged: canceled || _busy
                                            ? null
                                            : (selected) {
                                                setState(() {
                                                  if (selected) {
                                                    _selectedIndexes.add(index);
                                                  } else {
                                                    _selectedIndexes.remove(
                                                      index,
                                                    );
                                                  }
                                                });
                                              },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: _OutlineActionButton(
                              label: 'Close',
                              icon: Icons.close_rounded,
                              onTap: _busy
                                  ? () {}
                                  : () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: _FilledActionButton(
                              label: _busy
                                  ? 'Saving...'
                                  : 'Cancel Selected (${_selectedIndexes.length})',
                              onTap: _selectedIndexes.isEmpty || _busy
                                  ? null
                                  : () => unawaited(_submit(fullOrder: false)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: _DestructiveActionButton(
                              label: _busy ? 'Saving...' : 'Cancel Full Order',
                              enabled: !_busy && !snapshot.isFullyCanceled,
                              onTap: () => unawaited(_submit(fullOrder: true)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CancellationSummaryPanel extends StatelessWidget {
  final OrderHistoryRecord record;

  const _CancellationSummaryPanel({required this.record});

  @override
  Widget build(BuildContext context) {
    final snapshot = record.snapshot;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF18262E),
            ),
          ),
          const SizedBox(height: 14),
          _CancellationMetric(
            label: 'Paid total',
            value: SunmiReceiptService.money(snapshot.payableTotal),
            icon: Icons.payments_outlined,
          ),
          const SizedBox(height: 10),
          _CancellationMetric(
            label: 'Canceled',
            value: SunmiReceiptService.money(snapshot.canceledAmount),
            icon: Icons.remove_circle_outline_rounded,
          ),
          const SizedBox(height: 10),
          _CancellationMetric(
            label: 'Payment',
            value: snapshot.paymentMethod,
            icon: Icons.credit_card_rounded,
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text(
            'Cancellation Log',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF344A54),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: snapshot.cancellations.isEmpty
                ? const Center(
                    child: Text(
                      'No cancellations recorded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF758690),
                      ),
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: snapshot.cancellations.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = snapshot.cancellations[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5F1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.itemName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF8F351D),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${entry.authorizedBy} - ${SunmiReceiptService.money(entry.amount)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7B675F),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CancellationMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CancellationMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF45606B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF687984),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2E37),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool selected;
  final bool canceled;
  final ValueChanged<bool>? onChanged;

  const _CancellationItemRow({
    required this.item,
    required this.selected,
    required this.canceled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final qty = (item['qty'] as num?)?.toInt() ?? 1;
    final name = item['name']?.toString() ?? 'Item';
    final amount = (item['lineTotal'] as num?)?.toDouble() ?? 0;
    final detailLines = ((item['detailLines'] as List?) ?? const [])
        .map((line) => line.toString())
        .toList();

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: canceled
              ? const Color(0xFFFFF4F0)
              : selected
              ? const Color(0xFFEAF7EF)
              : Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? const Color(0xFF85D6A5)
                : Colors.white.withValues(alpha: 0.86),
          ),
          boxShadow: _softShadow,
        ),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: onChanged == null
                  ? null
                  : (value) => onChanged!(value == true),
              activeColor: const Color(0xFF208849),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$qty x $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: canceled
                                ? const Color(0xFF9A4C37)
                                : const Color(0xFF1D2D36),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        SunmiReceiptService.money(amount),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1D7F4B),
                        ),
                      ),
                    ],
                  ),
                  if (detailLines.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detailLines.take(2).join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF758690),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canceled) ...[
              const SizedBox(width: 12),
              const _InfoBadge(icon: Icons.cancel_rounded, label: 'Canceled'),
            ],
          ],
        ),
      ),
    );
  }
}

class _DestructiveActionButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _DestructiveActionButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE05C32), Color(0xFF9E3218)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              boxShadow: _softShadow,
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveryProviderPickerDialog extends StatelessWidget {
  final List<DeliveryProvider> providers;
  final int? selectedId;

  const _DeliveryProviderPickerDialog({
    required this.providers,
    required this.selectedId,
  });

  Color _providerColor(DeliveryProvider p) {
    final hex = p.color;
    if (hex != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return Color(int.parse('FF${hex.substring(1)}', radix: 16));
    }
    return const Color(0xFF1F7A47);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFEFE),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose Delivery Provider',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF17252C),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F7F8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.close_rounded,
                          size: 25, color: Color(0xFF52626B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Product prices update to the selected provider.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF73828E),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final p in providers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            key: ValueKey('delivery-provider-${p.id}'),
                            onTap: () => Navigator.of(context).pop(p.id),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: p.id == selectedId
                                    ? const Color(0xFFF1FBF4)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: p.id == selectedId
                                      ? const Color(0xFF2C9255)
                                      : const Color(0xFFDCE6EA),
                                  width: p.id == selectedId ? 1.8 : 1.1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _providerColor(p),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF22323B),
                                      ),
                                    ),
                                  ),
                                  if (p.id == selectedId)
                                    const Icon(Icons.check_circle_rounded,
                                        color: Color(0xFF1F7A47)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InAppKeyboardDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String hintText;
  final bool numbersOnly;

  const _InAppKeyboardDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    this.numbersOnly = false,
  });

  @override
  State<_InAppKeyboardDialog> createState() => _InAppKeyboardDialogState();
}

class _InAppKeyboardDialogState extends State<_InAppKeyboardDialog> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  void _append(String key) {
    setState(() {
      if (widget.numbersOnly) {
        if (_value.length >= 15) return;
        _value = '$_value$key';
        return;
      }

      if (_value.length >= 30) return;
      _value = '$_value$key';
    });
  }

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() {
      _value = _value.substring(0, _value.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.numbersOnly
        ? const <List<String>>[
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['0'],
          ]
        : const <List<String>>[
            ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
            ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
            ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
          ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 120, vertical: 60),
      backgroundColor: Colors.transparent,
      child: _glassPanel(
        padding: const EdgeInsets.all(22),
        tint: const Color(0xEFF8FBFD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18262F),
                    ),
                  ),
                ),
                _CircleGlassButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
              ),
              child: Text(
                _value.isEmpty ? widget.hintText : _value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _value.isEmpty
                      ? const Color(0xFF8B9DA8)
                      : const Color(0xFF192B34),
                ),
              ),
            ),
            const SizedBox(height: 18),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: row
                      .map(
                        (key) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _KeyboardKey(
                              label: key,
                              onTap: () => _append(key),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            if (!widget.numbersOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _KeyboardKey(
                        label: 'SPACE',
                        onTap: () => _append(' '),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _OutlineActionButton(
                    label: 'Clear',
                    icon: Icons.refresh_rounded,
                    onTap: () {
                      setState(() {
                        _value = '';
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OutlineActionButton(
                    label: 'Backspace',
                    icon: Icons.backspace_outlined,
                    onTap: _backspace,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilledActionButton(
                    label: 'Done',
                    onTap: () => Navigator.of(context).pop(_value.trim()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyboardKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
          boxShadow: _softShadow,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF2A3A43),
          ),
        ),
      ),
    );
  }
}

/// Live customer search (name / phone / plate) with loyalty balances. Returns
/// the chosen CustomerSearchResult, or null on cancel.
class _CustomerSearchDialog extends StatefulWidget {
  const _CustomerSearchDialog({required this.search});

  final Future<List<CustomerSearchResult>> Function(String) search;

  @override
  State<_CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<_CustomerSearchDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _searched = false;
  String? _error;
  List<CustomerSearchResult> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.search(q);
      if (mounted) {
        setState(() {
          _results = r;
          _searched = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Search failed. Check the connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _points(CustomerSearchResult c) =>
      c.loyalty.fold(0, (s, b) => s + b.points);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _run(),
                      decoration: const InputDecoration(
                        hintText: 'Name, phone, or plate',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _run,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFD23B3B))),
              if (!_busy && _searched && _results.isEmpty && _error == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No customers found.'),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final c = _results[i];
                    final pts = _points(c);
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name.isEmpty ? c.phone : c.name),
                      subtitle: Text([
                        if (c.phone.isNotEmpty) c.phone,
                        if (pts > 0) '$pts points',
                      ].join('  ·  ')),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choose how many loyalty redemption blocks to redeem (1..maxBlocks).
class _RedeemBlocksDialog extends StatefulWidget {
  const _RedeemBlocksDialog({
    required this.maxBlocks,
    required this.pointsPerBlock,
    required this.valuePerBlock,
  });

  final int maxBlocks;
  final int pointsPerBlock;
  final double valuePerBlock;

  @override
  State<_RedeemBlocksDialog> createState() => _RedeemBlocksDialogState();
}

class _RedeemBlocksDialogState extends State<_RedeemBlocksDialog> {
  int _blocks = 1;

  @override
  Widget build(BuildContext context) {
    final points = _blocks * widget.pointsPerBlock;
    final value = _blocks * widget.valuePerBlock;
    return AlertDialog(
      title: const Text('Redeem points'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.pointsPerBlock} points = ${SunmiReceiptService.money(widget.valuePerBlock)} per block',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed:
                    _blocks > 1 ? () => setState(() => _blocks--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_blocks',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800)),
              IconButton(
                onPressed: _blocks < widget.maxBlocks
                    ? () => setState(() => _blocks++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$points points  →  ${SunmiReceiptService.money(value)} off',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _blocks),
          child: const Text('Redeem'),
        ),
      ],
    );
  }
}

class _DiscountDialog extends StatefulWidget {
  final DiscountConfiguration initialDiscount;

  const _DiscountDialog({required this.initialDiscount});

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  late DiscountConfiguration _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDiscount;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 80),
      backgroundColor: Colors.transparent,
      child: _glassPanel(
        padding: const EdgeInsets.all(22),
        tint: const Color(0xEFF8FBFD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add Discount',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18262F),
                    ),
                  ),
                ),
                _CircleGlassButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Percentage Discounts',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF22323B),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DiscountChoice(
                  label: '5%',
                  selected:
                      _selected.kind == DiscountKind.percentage &&
                      _selected.value == 5,
                  onTap: () => setState(() {
                    _selected = const DiscountConfiguration(
                      kind: DiscountKind.percentage,
                      value: 5,
                      label: '5% Discount',
                    );
                  }),
                ),
                _DiscountChoice(
                  label: '10%',
                  selected:
                      _selected.kind == DiscountKind.percentage &&
                      _selected.value == 10,
                  onTap: () => setState(() {
                    _selected = const DiscountConfiguration(
                      kind: DiscountKind.percentage,
                      value: 10,
                      label: '10% Discount',
                    );
                  }),
                ),
                _DiscountChoice(
                  label: '15%',
                  selected:
                      _selected.kind == DiscountKind.percentage &&
                      _selected.value == 15,
                  onTap: () => setState(() {
                    _selected = const DiscountConfiguration(
                      kind: DiscountKind.percentage,
                      value: 15,
                      label: '15% Discount',
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Fixed Discounts',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF22323B),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DiscountChoice(
                  label: '0.500 OMR',
                  selected:
                      _selected.kind == DiscountKind.fixedAmount &&
                      _selected.value == 0.5,
                  onTap: () => setState(() {
                    _selected = const DiscountConfiguration(
                      kind: DiscountKind.fixedAmount,
                      value: 0.5,
                      label: '0.500 OMR Discount',
                    );
                  }),
                ),
                _DiscountChoice(
                  label: '1.000 OMR',
                  selected:
                      _selected.kind == DiscountKind.fixedAmount &&
                      _selected.value == 1,
                  onTap: () => setState(() {
                    _selected = const DiscountConfiguration(
                      kind: DiscountKind.fixedAmount,
                      value: 1,
                      label: '1.000 OMR Discount',
                    );
                  }),
                ),
                _DiscountChoice(
                  label: '2.000 OMR',
                  selected:
                      _selected.kind == DiscountKind.fixedAmount &&
                      _selected.value == 2,
                  onTap: () => setState(() {
                    _selected = const DiscountConfiguration(
                      kind: DiscountKind.fixedAmount,
                      value: 2,
                      label: '2.000 OMR Discount',
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _OutlineActionButton(
                    label: 'Clear Discount',
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const DiscountConfiguration()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilledActionButton(
                    label: _selected.isActive
                        ? 'Apply ${_selected.label}'
                        : 'Close',
                    onTap: _selected.isActive
                        ? () => Navigator.of(context).pop(_selected)
                        : () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscountChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DiscountChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFDFF6E8)
              : Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF2E9155) : const Color(0xFFD8E3E8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: selected ? const Color(0xFF1C7844) : const Color(0xFF2D4048),
          ),
        ),
      ),
    );
  }
}

class _SplitBillDialog extends StatefulWidget {
  final int initialSplitCount;
  final double total;

  const _SplitBillDialog({
    required this.initialSplitCount,
    required this.total,
  });

  @override
  State<_SplitBillDialog> createState() => _SplitBillDialogState();
}

class _SplitBillDialogState extends State<_SplitBillDialog> {
  late int _splitCount;

  @override
  void initState() {
    super.initState();
    _splitCount = widget.initialSplitCount;
  }

  @override
  Widget build(BuildContext context) {
    final share = _splitCount > 1
        ? double.parse((widget.total / _splitCount).toStringAsFixed(3))
        : widget.total;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 180, vertical: 100),
      backgroundColor: Colors.transparent,
      child: _glassPanel(
        padding: const EdgeInsets.all(22),
        tint: const Color(0xEFF8FBFD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Split Bill',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18262F),
                    ),
                  ),
                ),
                _CircleGlassButton(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(6, (index) {
                final count = index + 1;
                return _DiscountChoice(
                  label: count == 1 ? 'Single Bill' : '$count Guests',
                  selected: _splitCount == count,
                  onTap: () => setState(() {
                    _splitCount = count;
                  }),
                );
              }),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _splitCount > 1
                        ? 'Each guest pays'
                        : 'Single payment total',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5D6E79),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    SunmiReceiptService.money(share),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1D8D53),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _OutlineActionButton(
                    label: 'Cancel',
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilledActionButton(
                    label: _splitCount > 1 ? 'Apply Split' : 'Use Single Bill',
                    onTap: () => Navigator.of(context).pop(_splitCount),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _glassPanel({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  double? height,
  Color tint = const Color(0x66FFFFFF),
  Gradient? gradient,
}) {
  final panel = Container(
    height: height,
    padding: padding,
    decoration: BoxDecoration(
      color: gradient == null ? tint : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
      boxShadow: _softShadow,
    ),
    child: child,
  );

  if (!_staffVisualEffectsEnabled) return panel;

  return ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: panel,
    ),
  );
}

Widget _glassInsetCard({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.66)),
      boxShadow: _softShadow,
    ),
    child: child,
  );
}

BoxDecoration _chipDecoration({required bool selected}) {
  return BoxDecoration(
    color: selected
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.68),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: Colors.white.withValues(alpha: selected ? 0.88 : 0.62),
      width: 1.1,
    ),
    boxShadow: _softShadow,
  );
}

const _softShadow = <BoxShadow>[
  BoxShadow(color: Color(0x19000000), blurRadius: 22, offset: Offset(0, 12)),
  BoxShadow(color: Color(0x14FFFFFF), blurRadius: 1, offset: Offset(0, 1)),
];
