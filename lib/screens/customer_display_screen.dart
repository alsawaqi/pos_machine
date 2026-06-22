import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../services/display_strings.dart';
import '../services/sunmi_receipt_service.dart';
import '../widgets/animated_feedback_widgets.dart';

const bool _customerVisualEffectsEnabled = bool.fromEnvironment(
  'POS_ENABLE_VISUAL_EFFECTS',
  defaultValue: false,
);

class CustomerDisplayScreen extends StatefulWidget {
  const CustomerDisplayScreen({super.key});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  static const MethodChannel _rearDisplayChannel = MethodChannel(
    'pos_machine/rear_display_channel',
  );

  static const Color _pageBackground = Color(0xFFF5F1EA);
  static const Color _panelBorder = Color(0x9AFFFFFF);
  static const Color _headline = Color(0xFF1B2B3A);
  static const Color _body = Color(0xFF49606F);
  static const Color _accentDeep = Color(0xFF0C6782);
  static const Color _success = Color(0xFF2B8E64);

  OrderSnapshot order = OrderSnapshot.initial();
  bool _sendingCustomerDecision = false;
  late final ScrollController _orderItemsScrollController;

  // Customer-panel taps are intercepted on the main display (MainActivity) and forwarded here as
  // normalized points; we replay them as synthetic pointers so the customer UI reacts to them.
  int _syntheticPointerId = 1000;
  bool _syntheticPointerDown = false;

  @override
  void initState() {
    super.initState();
    _orderItemsScrollController = ScrollController();
    debugPrint('CustomerDisplayScreen initialized.');

    _rearDisplayChannel.setMethodCallHandler((call) async {
      if (call.method == 'syntheticTouch') {
        _handleSyntheticTouch(call.arguments);
        return;
      }
      if (call.method != 'updateOrder') return;

      final data = call.arguments;
      if (data is Map && data['type'] == 'order_snapshot') {
        setState(() {
          order = OrderSnapshot.fromMap(Map<String, dynamic>.from(data));
          if (!order.showCharityRoundUpPrompt) {
            _sendingCustomerDecision = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _rearDisplayChannel.setMethodCallHandler(null);
    _orderItemsScrollController.dispose();
    super.dispose();
  }

  /// Replays a customer-panel touch (forwarded from the main display) onto this customer UI.
  /// [arguments] carries `action` (down/move/up/cancel) and `nx`/`ny` (0..1 fractions of the panel).
  void _handleSyntheticTouch(dynamic arguments) {
    if (!mounted) return;
    if (arguments is! Map) return;
    final action = arguments['action']?.toString();
    final nx = (arguments['nx'] as num?)?.toDouble();
    final ny = (arguments['ny'] as num?)?.toDouble();
    if (action == null || nx == null || ny == null) return;

    final size = MediaQuery.maybeOf(context)?.size;
    if (size == null || size.isEmpty) return;
    final position = Offset(nx * size.width, ny * size.height);
    _dispatchSyntheticPointer(action, position);
  }

  void _dispatchSyntheticPointer(String action, Offset position) {
    final binding = GestureBinding.instance;
    switch (action) {
      case 'down':
        _syntheticPointerId += 1;
        _syntheticPointerDown = true;
        binding.handlePointerEvent(
          PointerDownEvent(
            pointer: _syntheticPointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
        break;
      case 'move':
        if (!_syntheticPointerDown) return;
        binding.handlePointerEvent(
          PointerMoveEvent(
            pointer: _syntheticPointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
        break;
      case 'up':
        if (!_syntheticPointerDown) return;
        _syntheticPointerDown = false;
        binding.handlePointerEvent(
          PointerUpEvent(
            pointer: _syntheticPointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
        break;
      case 'cancel':
        if (!_syntheticPointerDown) return;
        _syntheticPointerDown = false;
        binding.handlePointerEvent(
          PointerCancelEvent(
            pointer: _syntheticPointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTapPrompt = _showTapToPayPrompt;
    final content = _showCharityPrompt
        ? _buildCharityRoundUpLayout()
        : showTapPrompt
        ? _buildTapToPayLayout()
        : _buildOrderLayout();

    return Scaffold(
      backgroundColor: _pageBackground,
      body: Stack(
        children: [
          const _CustomerBackdrop(),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(padding: const EdgeInsets.all(28), child: content),
          ),
          if (_showLoadingOverlay) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  bool get _showTapToPayPrompt =>
      order.paymentStatus == 'Processing payment' &&
      order.paymentMethod.toLowerCase() != 'cash';
  bool get _showCharityPrompt => order.showCharityRoundUpPrompt;
  // The cashier alone resolves an unconfirmed card charge ("Card charge not
  // confirmed"); the customer screen must never show the failure or its prompt.
  bool get _isAwaitingCashier =>
      order.paymentStatus == 'Card charge not confirmed';
  bool get _showLoadingOverlay =>
      _sendingCustomerDecision ||
      order.showPaymentLaunchOverlay ||
      _isAwaitingCashier;
  String get _loadingOverlayTitle {
    final l10n = L10n.of(context);
    if (_sendingCustomerDecision) return l10n.cdProcessingSelectionTitle;
    if (_isAwaitingCashier) return l10n.cdPreparingPaymentTitle;
    return order.paymentOverlayTitle.isEmpty
        ? l10n.cdPreparingPaymentTitle
        : order.paymentOverlayTitle;
  }

  String get _loadingOverlayMessage {
    final l10n = L10n.of(context);
    if (_sendingCustomerDecision) {
      return l10n.cdProcessingSelectionMessage;
    }
    // Neutral wait copy — never surface the card-failure note to the customer.
    if (_isAwaitingCashier) return l10n.cdPreparingPaymentMessage;

    return order.note.isEmpty ? l10n.cdPreparingPaymentMessage : order.note;
  }

  bool get _isPaid => order.paymentStatus == 'Paid';
  double get _charityBaseAmount => order.activePaymentBaseTotal > 0
      ? order.activePaymentBaseTotal
      : order.total;
  double get _headlineAmount {
    if (_showCharityPrompt) {
      return order.charityRoundUpTotal > 0
          ? order.charityRoundUpTotal
          : _charityBaseAmount;
    }

    if (_showTapToPayPrompt) {
      return order.payableTotal > 0 ? order.payableTotal : _charityBaseAmount;
    }

    return _charityBaseAmount;
  }

  Widget _buildOrderLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final bodyGap = compact ? 16.0 : 24.0;
        final footerGap = compact ? 14.0 : 20.0;

        return Column(
          children: [
            _buildHeader(),
            SizedBox(height: bodyGap),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 9, child: _buildHeroSummary()),
                  const SizedBox(width: 20),
                  Expanded(flex: 11, child: _buildItemsPanel()),
                ],
              ),
            ),
            SizedBox(height: footerGap),
            _buildBottomBanner(),
          ],
        );
      },
    );
  }

  Widget _buildTapToPayLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final bodyGap = compact ? 16.0 : 24.0;
        final footerGap = compact ? 14.0 : 20.0;

        return Column(
          children: [
            _buildHeader(),
            SizedBox(height: bodyGap),
            Expanded(child: _buildTapPromptCard()),
            SizedBox(height: footerGap),
            _buildTapToPayFooter(),
          ],
        );
      },
    );
  }

  Widget _buildCharityRoundUpLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final bodyGap = compact ? 12.0 : 18.0;

        return Column(
          children: [
            _buildHeader(compact: true, showPaymentMethod: false),
            SizedBox(height: bodyGap),
            Expanded(child: _buildCharityPromptCard()),
          ],
        );
      },
    );
  }

  Widget _buildHeader({bool compact = false, bool showPaymentMethod = true}) {
    final l10n = L10n.of(context);
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 22, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 26, vertical: 20);
    final titleSize = compact ? 24.0 : 30.0;
    final subtitleSize = compact ? 13.0 : 15.0;
    final spacing = compact ? 10.0 : 12.0;

    return _customerGlass(
      padding: padding,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MITHQAL 2.0',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: _headline,
                  letterSpacing: 0.4,
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              Text(
                _isPaid
                    ? l10n.cdHeaderPaymentCompleted
                    : _showCharityPrompt
                    ? l10n.cdHeaderReviewCharity
                    : order.items.isEmpty
                    ? l10n.cdHeaderItemsWillAppear
                    : order.diningTableName.trim().isEmpty
                    ? l10n.cdHeaderItemLineCount(order.items.length)
                    : l10n.cdHeaderTableItemLineCount(
                        order.diningTableName.trim(),
                        order.items.length,
                      ),
                style: TextStyle(
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w600,
                  color: _body,
                ),
              ),
            ],
          ),
          const Spacer(),
          _StatusPill(
            label: _isAwaitingCashier
                ? localizedPaymentStatus(l10n, 'Processing payment')
                : localizedPaymentStatus(l10n, order.paymentStatus),
            active: order.paymentStatus != 'Waiting',
            success: _isPaid,
          ),
          if (showPaymentMethod) ...[
            SizedBox(width: spacing),
            _StatusPill(
              label: localizedPaymentMethod(l10n, order.paymentMethod),
              active: true,
              icon: Icons.payments_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroSummary() {
    final l10n = L10n.of(context);
    return _customerGlass(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tight = constraints.maxHeight < 500;
          final compact = constraints.maxHeight < 580;
          final panelPadding = tight ? 18.0 : (compact ? 22.0 : 26.0);
          final headerGap = tight ? 12.0 : (compact ? 16.0 : 22.0);
          final noteGap = tight ? 12.0 : (compact ? 16.0 : 20.0);
          final totalFont = tight ? 42.0 : (compact ? 48.0 : 58.0);
          final labelFont = tight ? 16.0 : 18.0;
          final receiptOrb = tight ? 78.0 : (compact ? 92.0 : 108.0);
          final orbIcon = tight ? 34.0 : (compact ? 40.0 : 48.0);
          final notePaddingX = tight ? 14.0 : 18.0;
          final notePaddingY = tight ? 12.0 : 16.0;
          final noteIconSize = tight ? 36.0 : 42.0;
          final noteTextSize = tight ? 13.0 : (compact ? 14.0 : 15.0);
          final summaryPadding = tight ? 16.0 : (compact ? 18.0 : 22.0);

          return Padding(
            padding: EdgeInsets.all(panelPadding),
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
                            _showCharityPrompt
                                ? l10n.cdHeroRoundUpForCharity
                                : order.items.isEmpty
                                ? l10n.cdHeroReadyForOrder
                                : l10n.cdHeroOrderTotal,
                            style: TextStyle(
                              fontSize: labelFont,
                              fontWeight: FontWeight.w700,
                              color: _body,
                            ),
                          ),
                          SizedBox(height: tight ? 8 : 12),
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: _headlineAmount),
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) {
                              return Text(
                                SunmiReceiptService.money(value),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: totalFont,
                                  fontWeight: FontWeight.w900,
                                  color: _headline,
                                  letterSpacing: -1.6,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: tight ? 12 : 16),
                    Container(
                      width: receiptOrb,
                      height: receiptOrb,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF9FDDEA).withValues(alpha: 0.92),
                            const Color(0xFFE5F8FC).withValues(alpha: 0.88),
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 30,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        size: orbIcon,
                        color: _accentDeep,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: headerGap),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: notePaddingX,
                    vertical: notePaddingY,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.74),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xA9FFFFFF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: noteIconSize,
                        height: noteIconSize,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8FC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: tight ? 20 : 24,
                          color: _accentDeep,
                        ),
                      ),
                      SizedBox(width: tight ? 10 : 12),
                      Expanded(
                        child: Text(
                          order.note.isEmpty
                              ? _showCharityPrompt
                                    ? l10n.cdHeroCharityNote
                                    : l10n.cdHeroReviewNote
                              : order.note,
                          maxLines: tight ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: noteTextSize,
                            height: tight ? 1.3 : 1.45,
                            fontWeight: FontWeight.w600,
                            color: _body,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: noteGap),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(summaryPadding),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.82),
                          const Color(0xFFF4FBFD).withValues(alpha: 0.72),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 24,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final veryCompact = constraints.maxHeight < 190;
                        final compact = constraints.maxHeight < 285;

                        if (veryCompact) {
                          return Row(
                            children: [
                              Expanded(
                                child: _MiniMetricTile(
                                  label: l10n.cdSubtotalLabel,
                                  value: SunmiReceiptService.money(
                                    order.subtotal,
                                  ),
                                  icon: Icons.receipt_long_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MiniMetricTile(
                                  label: l10n.cdTaxLabel,
                                  value: SunmiReceiptService.money(order.tax),
                                  icon: Icons.percent_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MiniMetricTile(
                                  label: l10n.cdPaymentLabel,
                                  value: localizedPaymentMethod(
                                    l10n,
                                    order.paymentMethod,
                                  ),
                                  icon: Icons.credit_score_outlined,
                                ),
                              ),
                            ],
                          );
                        }

                        if (compact) {
                          final lowerCompact = constraints.maxHeight < 250;

                          if (lowerCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _MetricCard(
                                        label: l10n.cdSubtotalLabel,
                                        value: SunmiReceiptService.money(
                                          order.subtotal,
                                        ),
                                        compact: true,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _MetricCard(
                                        label: l10n.cdTaxLabel,
                                        value: SunmiReceiptService.money(
                                          order.tax,
                                        ),
                                        compact: true,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _MetricCard(
                                  label: l10n.cdPaymentLabel,
                                  value: localizedPaymentMethod(
                                    l10n,
                                    order.paymentMethod,
                                  ),
                                  wide: true,
                                  compact: true,
                                  icon: Icons.credit_score_outlined,
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _MetricCard(
                                      label: l10n.cdSubtotalLabel,
                                      value: SunmiReceiptService.money(
                                        order.subtotal,
                                      ),
                                      compact: true,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MetricCard(
                                      label: l10n.cdTaxLabel,
                                      value: SunmiReceiptService.money(
                                        order.tax,
                                      ),
                                      compact: true,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _MetricCard(
                                label: l10n.cdPaymentLabel,
                                value: localizedPaymentMethod(
                                  l10n,
                                  order.paymentMethod,
                                ),
                                wide: true,
                                compact: true,
                                icon: Icons.credit_score_outlined,
                              ),
                              const SizedBox(height: 10),
                              _SummaryBanner(isPaid: _isPaid, compact: true),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricCard(
                                    label: l10n.cdSubtotalLabel,
                                    value: SunmiReceiptService.money(
                                      order.subtotal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _MetricCard(
                                    label: l10n.cdTaxLabel,
                                    value: SunmiReceiptService.money(order.tax),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: tight ? 8 : 12),
                            _MetricCard(
                              label: l10n.cdPaymentLabel,
                              value: localizedPaymentMethod(
                                l10n,
                                order.paymentMethod,
                              ),
                              wide: true,
                              icon: Icons.credit_score_outlined,
                            ),
                            const Spacer(),
                            _SummaryBanner(isPaid: _isPaid),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemsPanel() {
    final l10n = L10n.of(context);
    return _customerGlass(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cdOrderDetailsTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: _headline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.cdOrderDetailsSubtitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _body,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AnimatedSwitcher(
              duration: _customerVisualEffectsEnabled
                  ? const Duration(milliseconds: 260)
                  : Duration.zero,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: order.items.isEmpty
                  ? const _CustomerEmptyState(key: ValueKey('empty-order'))
                  : Scrollbar(
                      key: const ValueKey('order-items'),
                      controller: _orderItemsScrollController,
                      thumbVisibility: order.items.length > 4,
                      child: ListView.separated(
                        controller: _orderItemsScrollController,
                        primary: false,
                        physics: const BouncingScrollPhysics(),
                        itemCount: order.items.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = order.items[index];
                          final pulseNonce =
                              order.recentProductId == item['id']?.toString()
                              ? order.orderUpdateNonce
                              : 0;
                          return AnimatedSwitcher(
                            duration: _customerVisualEffectsEnabled
                                ? const Duration(milliseconds: 280)
                                : Duration.zero,
                            switchInCurve: Curves.easeOutBack,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.08, 0.08),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: _DisplayItemCard(
                              key: ValueKey(
                                '${item['name']}_${item['qty']}_${item['lineTotal']}_${item['detailLines']}_${item['notes']}_$pulseNonce',
                              ),
                              item: item,
                              highlighted: pulseNonce > 0,
                              pulseNonce: pulseNonce,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBanner() {
    final l10n = L10n.of(context);
    return _customerGlass(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isPaid
                    ? const [Color(0xFFDDF5EA), Color(0xFFF7FBF8)]
                    : const [Color(0xFFE7F8FC), Color(0xFFF8FCFD)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPaid
                  ? Icons.check_circle_outline_rounded
                  : Icons.waving_hand_rounded,
              color: _isPaid ? _success : _accentDeep,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _isPaid
                  ? l10n.cdBannerThankYou
                  : l10n.cdBannerReviewWhileCashier,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _headline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapPromptCard() {
    final l10n = L10n.of(context);
    final amountToPay = order.payableTotal > 0
        ? order.payableTotal
        : _charityBaseAmount;
    final showsCharityTotal =
        order.charityRoundUpAccepted && order.charityRoundUpAmount > 0.0001;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 420;
        final outerPadding = compact ? 18.0 : 30.0;
        final panelPadding = compact ? 18.0 : 28.0;
        final panelRadius = compact ? 24.0 : 30.0;
        final cardGap = compact ? 18.0 : 24.0;
        final heroGap = compact ? 16.0 : 26.0;
        final iconBox = compact ? 70.0 : 92.0;
        final iconSize = compact ? 38.0 : 48.0;
        final titleSize = compact ? 28.0 : 40.0;
        final subtitleSize = compact ? 14.0 : 17.0;
        final infoTitleSize = compact ? 18.0 : 22.0;
        final infoBodySize = compact ? 14.0 : 16.0;
        final chipSpacing = compact ? 10.0 : 12.0;
        final nfcBox = compact ? 78.0 : 96.0;
        final nfcIcon = compact ? 40.0 : 48.0;
        final amountLabelSize = compact ? 13.0 : 15.0;
        final amountSize = compact ? 34.0 : 40.0;
        final captionSize = compact ? 12.0 : 13.0;
        final tapBodySize = compact ? 14.0 : 16.0;

        return _customerGlass(
          padding: EdgeInsets.all(outerPadding),
          child: Row(
            children: [
              Expanded(
                flex: 11,
                child: Container(
                  padding: EdgeInsets.all(panelPadding),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFEEF9FC).withValues(alpha: 0.96),
                        Colors.white.withValues(alpha: 0.78),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(panelRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.96),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: iconBox,
                            height: iconBox,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFBEECF4), Color(0xFFEAF9FC)],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.contactless_rounded,
                              size: iconSize,
                              color: _accentDeep,
                            ),
                          ),
                          SizedBox(width: compact ? 16 : 22),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.cdTapToPayTitle,
                                  style: TextStyle(
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w900,
                                    color: _headline,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                                SizedBox(height: compact ? 6 : 8),
                                Text(
                                  l10n.cdTapToPaySubtitle,
                                  style: TextStyle(
                                    fontSize: subtitleSize,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                    color: _body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: heroGap),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Container(
                            padding: EdgeInsets.all(compact ? 16 : 22),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.76),
                              borderRadius: BorderRadius.circular(
                                compact ? 22 : 26,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.96),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l10n.cdContactlessReadyTitle,
                                        style: TextStyle(
                                          fontSize: infoTitleSize,
                                          fontWeight: FontWeight.w800,
                                          color: _headline,
                                        ),
                                      ),
                                      SizedBox(height: compact ? 10 : 12),
                                      Text(
                                        order.note.isEmpty
                                            ? l10n.cdContactlessHoldHint
                                            : order.note,
                                        style: TextStyle(
                                          fontSize: infoBodySize,
                                          height: 1.45,
                                          fontWeight: FontWeight.w600,
                                          color: _body,
                                        ),
                                      ),
                                      SizedBox(height: compact ? 14 : 20),
                                      Wrap(
                                        spacing: chipSpacing,
                                        runSpacing: chipSpacing,
                                        children: [
                                          _TapHintChip(
                                            icon: Icons.credit_card_rounded,
                                            label: l10n.cdChipCard,
                                          ),
                                          _TapHintChip(
                                            icon: Icons.phone_android_rounded,
                                            label: l10n.cdChipPhone,
                                          ),
                                          _TapHintChip(
                                            icon: Icons.watch_rounded,
                                            label: l10n.cdChipWearable,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: cardGap),
              Expanded(
                flex: 7,
                child: Container(
                  height: double.infinity,
                  padding: EdgeInsets.all(compact ? 20 : 28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1587A6), Color(0xFF0C667F)],
                    ),
                    borderRadius: BorderRadius.circular(panelRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 26,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: nfcBox,
                        height: nfcBox,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.nfc_rounded,
                          size: nfcIcon,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 20),
                      Text(
                        l10n.cdTotalToPay,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: amountLabelSize,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        SunmiReceiptService.money(amountToPay),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: amountSize,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.8,
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 12),
                      if (showsCharityTotal) ...[
                        Text(
                          l10n.cdIncludesCharityRoundUp(
                            SunmiReceiptService.money(
                              order.charityRoundUpAmount,
                            ),
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: captionSize,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 12),
                      ],
                      Text(
                        l10n.cdPresentToContinue,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: tapBodySize,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.90),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTapToPayFooter() {
    final l10n = L10n.of(context);
    return _customerGlass(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE5F8FC), Color(0xFFF6FCFD)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.nfc_rounded, color: _accentDeep),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              l10n.cdTapFooterKeepNear,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _headline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharityPromptCard() {
    final l10n = L10n.of(context);
    return _customerGlass(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 500 || constraints.maxWidth < 980;
          final dense =
              !compact &&
              (constraints.maxHeight < 620 || constraints.maxWidth < 1160);
          final compactControls = compact || dense;
          final outerPadding = compact ? 12.0 : (dense ? 16.0 : 22.0);
          final titleSize = compact ? 23.0 : (dense ? 28.0 : 34.0);
          final bodySize = compact ? 12.5 : (dense ? 14.0 : 17.0);
          final iconBox = compact ? 48.0 : (dense ? 58.0 : 72.0);
          final iconSize = compact ? 22.0 : (dense ? 27.0 : 34.0);
          final spacing = compact ? 8.0 : (dense ? 12.0 : 16.0);
          final summaryPadding = compact ? 12.0 : (dense ? 14.0 : 18.0);
          final summaryGap = compact ? 10.0 : (dense ? 12.0 : 14.0);
          final actionHeight = compact ? 74.0 : (dense ? 84.0 : 100.0);

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFF6F6E9).withValues(alpha: 0.96),
                  Colors.white.withValues(alpha: 0.90),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.96)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 24,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(outerPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: iconBox,
                                height: iconBox,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFF2DCA6),
                                      Color(0xFFF8F0CF),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.volunteer_activism_rounded,
                                  size: iconSize,
                                  color: const Color(0xFF9F6C00),
                                ),
                              ),
                              SizedBox(width: compact ? 12 : 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.cdCharityTitle,
                                      style: TextStyle(
                                        fontSize: titleSize,
                                        fontWeight: FontWeight.w900,
                                        color: _headline,
                                        letterSpacing: -0.8,
                                      ),
                                    ),
                                    SizedBox(height: compact ? 4 : 6),
                                    Text(
                                      l10n.cdCharityQuestion,
                                      maxLines: compact ? 3 : (dense ? 2 : 3),
                                      overflow: TextOverflow.fade,
                                      style: TextStyle(
                                        fontSize: bodySize,
                                        height: compact ? 1.25 : 1.35,
                                        fontWeight: FontWeight.w600,
                                        color: _body,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: spacing),
                          Container(
                            padding: EdgeInsets.all(summaryPadding),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.94),
                                  const Color(
                                    0xFFFFFCF2,
                                  ).withValues(alpha: 0.96),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 20,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact
                                        ? 10
                                        : (dense ? 12 : 14),
                                    vertical: compact ? 8 : (dense ? 10 : 12),
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFFFF4CF),
                                        Color(0xFFFFFBEE),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: compact ? 30 : (dense ? 34 : 40),
                                        height: compact
                                            ? 30
                                            : (dense ? 34 : 40),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFE9A8),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.favorite_rounded,
                                          size: compact
                                              ? 16
                                              : (dense ? 18 : 20),
                                          color: const Color(0xFFAD7300),
                                        ),
                                      ),
                                      SizedBox(
                                        width: compact ? 8 : (dense ? 10 : 12),
                                      ),
                                      Expanded(
                                        child: Text(
                                          l10n.cdCharityEncouragement,
                                          style: TextStyle(
                                            fontSize: compact
                                                ? 10.5
                                                : (dense ? 12.0 : 13.0),
                                            height: 1.35,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF6E5200),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: summaryGap),
                                LayoutBuilder(
                                  builder: (context, summaryConstraints) {
                                    final stacked =
                                        summaryConstraints.maxWidth < 700;

                                    final tiles = [
                                      _CharityBreakdownTile(
                                        label: l10n.cdCharityTileOrderTotal,
                                        caption: l10n
                                            .cdCharityTileOrderTotalCaption,
                                        amount: _charityBaseAmount,
                                        icon: Icons.receipt_long_rounded,
                                        accent: const Color(0xFF0C6782),
                                        gradientColors: const [
                                          Color(0xFFD9F1F8),
                                          Color(0xFFF2FBFD),
                                        ],
                                        compact: compact,
                                        dense: dense,
                                      ),
                                      _CharityBreakdownTile(
                                        label: l10n.cdCharityTileRoundUp,
                                        caption:
                                            l10n.cdCharityTileRoundUpCaption,
                                        amount: order.charityRoundUpAmount,
                                        icon: Icons.volunteer_activism_rounded,
                                        accent: const Color(0xFFAC7600),
                                        gradientColors: const [
                                          Color(0xFFFFE9C2),
                                          Color(0xFFFFF7E5),
                                        ],
                                        compact: compact,
                                        dense: dense,
                                      ),
                                      _CharityBreakdownTile(
                                        label: l10n.cdCharityTileNewTotal,
                                        caption:
                                            l10n.cdCharityTileNewTotalCaption,
                                        amount: order.charityRoundUpTotal > 0
                                            ? order.charityRoundUpTotal
                                            : _charityBaseAmount,
                                        icon: Icons.payments_rounded,
                                        accent: const Color(0xFF2B8E64),
                                        gradientColors: const [
                                          Color(0xFFDDF2E5),
                                          Color(0xFFF2FBF6),
                                        ],
                                        spotlight: true,
                                        compact: compact,
                                        dense: dense,
                                      ),
                                    ];

                                    if (stacked) {
                                      return Column(
                                        children: [
                                          for (
                                            var index = 0;
                                            index < tiles.length;
                                            index++
                                          ) ...[
                                            if (index > 0)
                                              SizedBox(
                                                height: compact ? 10 : 12,
                                              ),
                                            tiles[index],
                                          ],
                                        ],
                                      );
                                    }

                                    return Row(
                                      children: [
                                        Expanded(child: tiles[0]),
                                        const SizedBox(width: 12),
                                        Expanded(child: tiles[1]),
                                        const SizedBox(width: 12),
                                        Expanded(child: tiles[2]),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 10 : (dense ? 12 : 14)),
                  SizedBox(
                    height: actionHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _CustomerDecisionButton(
                            title: l10n.cdCharityNo,
                            subtitle: compactControls
                                ? l10n.cdCharityNoSubtitleShort
                                : l10n.cdCharityNoSubtitle,
                            icon: Icons.payments_outlined,
                            filled: false,
                            busy: _sendingCustomerDecision,
                            compact: compact,
                            dense: dense,
                            onTap: () => _sendCharityDecision(false),
                          ),
                        ),
                        SizedBox(width: compact ? 12 : (dense ? 14 : 16)),
                        Expanded(
                          child: _CustomerDecisionButton(
                            title: l10n.cdCharityYes,
                            subtitle: compactControls
                                ? l10n.cdCharityYesSubtitleShort
                                : l10n.cdCharityYesSubtitle,
                            icon: Icons.favorite_rounded,
                            filled: true,
                            busy: _sendingCustomerDecision,
                            compact: compact,
                            dense: dense,
                            onTap: () => _sendCharityDecision(true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendCharityDecision(bool accepted) async {
    if (_sendingCustomerDecision) return;

    setState(() {
      _sendingCustomerDecision = true;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      debugPrint(
        'CustomerDisplayScreen sending charity decision: accepted=$accepted',
      );

      final delivered =
          await _rearDisplayChannel.invokeMethod<bool>('customerEvent', {
            'type': 'charity_round_up_response',
            'accepted': accepted,
            'promptId': order.charityRoundUpPromptId,
          }) ??
          false;

      if (!delivered) {
        debugPrint(
          'CustomerDisplayScreen could not deliver the charity decision back to the staff controller.',
        );
        if (mounted) {
          setState(() {
            _sendingCustomerDecision = false;
          });
        }
      }
    } catch (error) {
      debugPrint(
        'CustomerDisplayScreen failed to send charity decision: $error',
      );
      if (mounted) {
        setState(() {
          _sendingCustomerDecision = false;
        });
      }
    }
  }

  Widget _buildLoadingOverlay() {
    final l10n = L10n.of(context);
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F28).withValues(alpha: 0.24),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  child: ProfessionalProcessingCard(
                    title: _loadingOverlayTitle,
                    message: _loadingOverlayMessage,
                    badge: _sendingCustomerDecision
                        ? l10n.cdBadgeUpdatingChoice
                        : l10n.cdBadgeSecureCardPayment,
                    icon: _sendingCustomerDecision
                        ? Icons.volunteer_activism_rounded
                        : Icons.credit_card_rounded,
                    accent: _sendingCustomerDecision
                        ? const Color(0xFFAD7300)
                        : _accentDeep,
                    accentGlow: _sendingCustomerDecision
                        ? const Color(0xFFF0BC53)
                        : const Color(0xFF1498B9),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerBackdrop extends StatelessWidget {
  const _CustomerBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF7F1E8), Color(0xFFF5F8FB), Color(0xFFF0F6F8)],
            ),
          ),
        ),
        Positioned(
          top: -110,
          left: -70,
          child: _GlowBlob(size: 320, color: const Color(0x66BEEBF4)),
        ),
        Positioned(
          top: 120,
          right: -120,
          child: _GlowBlob(size: 360, color: const Color(0x44DCCEBB)),
        ),
        Positioned(
          bottom: -140,
          left: 140,
          child: _GlowBlob(size: 420, color: const Color(0x33A8DCE5)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.85, -0.4),
                radius: 1.2,
                colors: [
                  Colors.white.withValues(alpha: 0.60),
                  Colors.white.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 170, spreadRadius: 42),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool success;
  final IconData icon;

  const _StatusPill({
    required this.label,
    required this.active,
    this.success = false,
    this.icon = Icons.bolt_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final background = success
        ? const Color(0xFFDDF5EA)
        : active
        ? const Color(0xFFE5F7FB)
        : Colors.white.withValues(alpha: 0.68);

    final border = success
        ? const Color(0xFFC7E7D6)
        : active
        ? const Color(0xFFD4EDF3)
        : Colors.white.withValues(alpha: 0.96);

    final foreground = success
        ? const Color(0xFF2A7E5B)
        : active
        ? const Color(0xFF0E708B)
        : const Color(0xFF526875);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final bool wide;
  final bool compact;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    this.wide = false,
    this.compact = false,
    this.icon = Icons.receipt_long_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 38 : 44,
            height: compact ? 38 : 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF8FC),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: compact ? 18 : 22,
              color: _CustomerDisplayScreenState._accentDeep,
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w700,
                    color: _CustomerDisplayScreenState._body,
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w800,
                    color: _CustomerDisplayScreenState._headline,
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

class _MiniMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF8FC),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 14,
              color: _CustomerDisplayScreenState._accentDeep,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _CustomerDisplayScreenState._body,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _CustomerDisplayScreenState._headline,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final bool isPaid;
  final bool compact;

  const _SummaryBanner({required this.isPaid, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isPaid
              ? const [Color(0xFFDDF5EA), Color(0xFFF6FCF8)]
              : const [Color(0xFFE6F7FB), Color(0xFFF9FCFD)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isPaid ? const Color(0xFFC9EAD8) : const Color(0xFFD6EDF3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPaid ? Icons.verified_rounded : Icons.thumb_up_alt_outlined,
            size: compact ? 18 : 22,
            color: isPaid
                ? _CustomerDisplayScreenState._success
                : _CustomerDisplayScreenState._accentDeep,
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Text(
              isPaid ? l10n.cdSummaryPaid : l10n.cdSummaryAwaitingCashier,
              maxLines: compact ? 2 : null,
              overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
              style: TextStyle(
                fontSize: compact ? 13 : 15,
                height: compact ? 1.25 : 1.45,
                fontWeight: FontWeight.w700,
                color: _CustomerDisplayScreenState._headline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapHintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TapHintChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _CustomerDisplayScreenState._accentDeep),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _CustomerDisplayScreenState._headline,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisplayItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool highlighted;
  final int pulseNonce;

  const _DisplayItemCard({
    super.key,
    required this.item,
    this.highlighted = false,
    this.pulseNonce = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final imageAsset = item['imageAsset']?.toString();
    final qty = (item['qty'] as num?)?.toInt() ?? 0;
    final total = (item['lineTotal'] as num?)?.toDouble() ?? 0;
    // Phase C4 — prefer the snapshot's Arabic product name when the display
    // locale is Arabic ('name' stays the identity key in the snapshot map).
    final nameAr = item['nameAr']?.toString() ?? '';
    final displayName = isAr && nameAr.isNotEmpty
        ? nameAr
        : item['name']?.toString() ?? '';
    final detailLines = ((item['detailLines'] as List?) ?? const [])
        .map((line) => line.toString())
        .where((line) => line.isNotEmpty)
        .toList();

    return TweenAnimationBuilder<double>(
      key: ValueKey('customer-pulse-${item['id']}_$pulseNonce'),
      tween: Tween<double>(begin: highlighted ? 1 : 0, end: 0),
      duration: _customerVisualEffectsEnabled
          ? const Duration(milliseconds: 620)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, pulse, child) {
        final effectPulse = _customerVisualEffectsEnabled ? pulse : 0.0;
        return Transform.scale(
          scale: 1 + (effectPulse * 0.014),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.white.withValues(alpha: 0.78),
                const Color(0xFFF2FDFF),
                effectPulse * 0.76,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.96),
                  const Color(0xFF86DCEC),
                  effectPulse,
                )!,
              ),
              boxShadow: [
                const BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 16,
                  offset: Offset(0, 10),
                ),
                if (effectPulse > 0.001)
                  BoxShadow(
                    color: const Color(
                      0x2658CAE2,
                    ).withValues(alpha: 0.14 + (effectPulse * 0.18)),
                    blurRadius: 20 + (effectPulse * 12),
                    offset: const Offset(0, 12),
                  ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 74,
              height: 74,
              child: imageAsset == null
                  ? _displayPlaceholder()
                  : Image.asset(
                      imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _displayPlaceholder();
                      },
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _CustomerDisplayScreenState._headline,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.cdQuantity(qty),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _CustomerDisplayScreenState._body,
                  ),
                ),
                if (detailLines.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...detailLines.map(
                    (detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6A7E8D),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F8FB),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              SunmiReceiptService.money(total),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _CustomerDisplayScreenState._accentDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _displayPlaceholder() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD9EEF4), Color(0xFFEDF8FB)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.local_cafe_outlined,
          color: _CustomerDisplayScreenState._accentDeep,
        ),
      ),
    );
  }
}

class _CustomerEmptyState extends StatelessWidget {
  const _CustomerEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.96)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 50,
              color: _CustomerDisplayScreenState._accentDeep,
            ),
            const SizedBox(height: 14),
            Text(
              l10n.cdNoItemsYet,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _CustomerDisplayScreenState._headline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cdEmptyStateHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _CustomerDisplayScreenState._body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharityBreakdownTile extends StatefulWidget {
  final String label;
  final String caption;
  final double amount;
  final IconData icon;
  final Color accent;
  final List<Color> gradientColors;
  final bool spotlight;
  final bool compact;
  final bool dense;

  const _CharityBreakdownTile({
    required this.label,
    required this.caption,
    required this.amount,
    required this.icon,
    required this.accent,
    required this.gradientColors,
    this.spotlight = false,
    this.compact = false,
    this.dense = false,
  });

  @override
  State<_CharityBreakdownTile> createState() => _CharityBreakdownTileState();
}

class _CharityBreakdownTileState extends State<_CharityBreakdownTile>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _configurePulse();
  }

  @override
  void didUpdateWidget(covariant _CharityBreakdownTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spotlight != widget.spotlight) {
      _configurePulse();
    }
  }

  void _configurePulse() {
    if (widget.spotlight) {
      _pulseController ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat(reverse: true);
      return;
    }

    _pulseController?.dispose();
    _pulseController = null;
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final animation = _pulseController ?? const AlwaysStoppedAnimation(0.0);
    final labelSize = widget.compact ? 12.0 : (widget.dense ? 13.0 : 14.0);
    final amountSize = widget.compact ? 21.0 : (widget.dense ? 24.0 : 28.0);
    final captionSize = widget.compact ? 11.0 : (widget.dense ? 11.5 : 12.5);
    final badgeSize = widget.compact ? 36.0 : (widget.dense ? 40.0 : 46.0);
    final badgeIconSize = widget.compact ? 19.0 : (widget.dense ? 21.0 : 24.0);
    final padding = widget.compact ? 14.0 : (widget.dense ? 16.0 : 18.0);
    final radius = widget.compact ? 22.0 : (widget.dense ? 24.0 : 26.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final pulse = animation.value;
        final scale = widget.spotlight ? 1 + (pulse * 0.01) : 1.0;
        final glowOpacity = widget.spotlight ? 0.10 + (pulse * 0.06) : 0.05;
        final glowBlur = widget.spotlight ? 18.0 + (pulse * 4) : 12.0;
        final minHeight = widget.compact
            ? 110.0
            : (widget.dense ? 124.0 : 142.0);

        return Transform.scale(
          scale: scale,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.gradientColors,
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: 0.96)),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: glowOpacity),
                  blurRadius: glowBlur,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -18,
                  right: -10,
                  child: IgnorePointer(
                    child: Container(
                      width: widget.compact ? 64 : (widget.dense ? 72.0 : 82.0),
                      height: widget.compact
                          ? 64
                          : (widget.dense ? 72.0 : 82.0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.accent.withValues(
                              alpha: widget.spotlight
                                  ? 0.10 + (pulse * 0.08)
                                  : 0.05,
                            ),
                            blurRadius: widget.compact
                                ? 26.0
                                : (widget.dense ? 32.0 : 40.0),
                            spreadRadius: widget.compact
                                ? 2.0
                                : (widget.dense ? 4.0 : 6.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: badgeSize,
                          height: badgeSize,
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            widget.icon,
                            size: badgeIconSize,
                            color: widget.accent,
                          ),
                        ),
                        const Spacer(),
                        if (widget.spotlight)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.compact
                                  ? 8
                                  : (widget.dense ? 9.0 : 10.0),
                              vertical: widget.compact
                                  ? 5
                                  : (widget.dense ? 5.5 : 6.0),
                            ),
                            decoration: BoxDecoration(
                              color: widget.accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: widget.accent.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              l10n.cdFinalBadge,
                              style: TextStyle(
                                fontSize: widget.compact
                                    ? 9
                                    : (widget.dense ? 9.5 : 10.0),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                                color: widget.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(
                      height: widget.compact
                          ? 12
                          : (widget.dense ? 14.0 : 16.0),
                    ),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: labelSize,
                        fontWeight: FontWeight.w800,
                        color: widget.accent.withValues(alpha: 0.92),
                      ),
                    ),
                    SizedBox(height: widget.compact ? 6 : 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: widget.amount),
                      duration: const Duration(milliseconds: 520),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return Text(
                          SunmiReceiptService.money(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: amountSize,
                            fontWeight: FontWeight.w900,
                            color: widget.accent,
                            letterSpacing: -0.6,
                          ),
                        );
                      },
                    ),
                    SizedBox(height: widget.compact ? 4 : 6),
                    Text(
                      widget.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: captionSize,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: _CustomerDisplayScreenState._body,
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
}

class _CustomerDecisionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool filled;
  final bool busy;
  final bool compact;
  final bool dense;
  final VoidCallback onTap;

  const _CustomerDecisionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.filled,
    required this.busy,
    this.compact = false,
    this.dense = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = filled
        ? Colors.white
        : _CustomerDisplayScreenState._headline;
    final subtitleColor = filled
        ? Colors.white.withValues(alpha: 0.88)
        : _CustomerDisplayScreenState._body;
    final iconBackground = filled
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFEAF8FC);
    final iconColor = filled
        ? Colors.white
        : _CustomerDisplayScreenState._accentDeep;
    final minHeight = compact ? 62.0 : (dense ? 86.0 : 112.0);
    final horizontalPadding = compact ? 14.0 : (dense ? 18.0 : 22.0);
    final verticalPadding = compact ? 8.0 : (dense ? 14.0 : 20.0);
    final iconBoxSize = compact ? 30.0 : (dense ? 42.0 : 54.0);
    final iconSize = compact ? 18.0 : (dense ? 22.0 : 28.0);
    final titleSize = compact ? 16.0 : (dense ? 20.0 : 26.0);
    final subtitleSize = compact ? 12.5 : (dense ? 13.5 : 15.0);
    final subtitleHeight = compact ? 1.2 : (dense ? 1.25 : 1.35);
    final indicatorSize = compact ? 20.0 : (dense ? 22.0 : 24.0);
    final arrowSize = compact ? 24.0 : (dense ? 26.0 : 28.0);

    return Opacity(
      opacity: busy ? 0.94 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(26),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              gradient: filled
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0B7F9E), Color(0xFF0C5F78)],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.92),
                        const Color(0xFFF3FBFD).withValues(alpha: 0.88),
                      ],
                    ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: filled
                    ? Colors.white.withValues(alpha: 0.24)
                    : Colors.white.withValues(alpha: 0.96),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: iconColor, size: iconSize),
                ),
                SizedBox(width: compact ? 10 : 16),
                Expanded(
                  child: compact
                      ? Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w900,
                            color: titleColor,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.w900,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: subtitleSize,
                                fontWeight: FontWeight.w700,
                                height: subtitleHeight,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                ),
                SizedBox(width: compact ? 6 : 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: busy
                      ? SizedBox(
                          key: const ValueKey('busy'),
                          width: indicatorSize,
                          height: indicatorSize,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              filled
                                  ? Colors.white
                                  : _CustomerDisplayScreenState._accentDeep,
                            ),
                            backgroundColor: filled
                                ? Colors.white.withValues(alpha: 0.20)
                                : const Color(0xFFD6EEF5),
                          ),
                        )
                      : Icon(
                          key: const ValueKey('arrow'),
                          Icons.arrow_forward_rounded,
                          color: filled
                              ? Colors.white
                              : _CustomerDisplayScreenState._accentDeep,
                          size: arrowSize,
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

Widget _customerGlass({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
}) {
  final panel = Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.78),
          Colors.white.withValues(alpha: 0.58),
        ],
      ),
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: _CustomerDisplayScreenState._panelBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 28,
          offset: Offset(0, 16),
        ),
        BoxShadow(
          color: Color(0x18FFFFFF),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: child,
  );

  if (!_customerVisualEffectsEnabled) return panel;

  return ClipRRect(
    borderRadius: BorderRadius.circular(32),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: panel,
    ),
  );
}
