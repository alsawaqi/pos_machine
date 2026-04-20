import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pos_models.dart';
import '../services/sunmi_receipt_service.dart';

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

  @override
  void initState() {
    super.initState();
    debugPrint('CustomerDisplayScreen initialized.');

    _rearDisplayChannel.setMethodCallHandler((call) async {
      if (call.method != 'updateOrder') return;

      final data = call.arguments;
      if (data is Map && data['type'] == 'order_snapshot') {
        debugPrint('CustomerDisplayScreen received order snapshot.');
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
    super.dispose();
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
  bool get _showLoadingOverlay =>
      _sendingCustomerDecision || order.showPaymentLaunchOverlay;

  bool get _isPaid => order.paymentStatus == 'Paid';
  double get _headlineAmount {
    if (_showCharityPrompt) {
      return order.charityRoundUpTotal > 0
          ? order.charityRoundUpTotal
          : order.total;
    }

    if (_showTapToPayPrompt) {
      return order.payableTotal > 0 ? order.payableTotal : order.total;
    }

    return order.total;
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
        final bodyGap = compact ? 16.0 : 24.0;
        final footerGap = compact ? 14.0 : 20.0;

        return Column(
          children: [
            _buildHeader(),
            SizedBox(height: bodyGap),
            Expanded(child: _buildCharityPromptCard()),
            SizedBox(height: footerGap),
            _buildCharityPromptFooter(),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return _customerGlass(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MITHQAL 2.0',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: _headline,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isPaid
                    ? 'Payment completed successfully'
                    : order.items.isEmpty
                    ? 'Your items and total will appear here'
                    : '${order.items.length} item lines in the current order',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _body,
                ),
              ),
            ],
          ),
          const Spacer(),
          _StatusPill(
            label: order.paymentStatus,
            active: order.paymentStatus != 'Waiting',
            success: _isPaid,
          ),
          const SizedBox(width: 12),
          _StatusPill(
            label: order.paymentMethod,
            active: true,
            icon: Icons.payments_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSummary() {
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
                                ? 'Round up for charity'
                                : order.items.isEmpty
                                ? 'Ready for your order'
                                : 'Order total',
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
                                    ? 'The extra rounded amount will be donated to charity.'
                                    : 'Please review your items and total before payment.'
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
                                  label: 'Subtotal',
                                  value: SunmiReceiptService.money(
                                    order.subtotal,
                                  ),
                                  icon: Icons.receipt_long_outlined,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MiniMetricTile(
                                  label: 'Tax',
                                  value: SunmiReceiptService.money(order.tax),
                                  icon: Icons.percent_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _MiniMetricTile(
                                  label: 'Payment',
                                  value: order.paymentMethod,
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
                                        label: 'Subtotal',
                                        value: SunmiReceiptService.money(
                                          order.subtotal,
                                        ),
                                        compact: true,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _MetricCard(
                                        label: 'Tax',
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
                                  label: 'Payment',
                                  value: order.paymentMethod,
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
                                      label: 'Subtotal',
                                      value: SunmiReceiptService.money(
                                        order.subtotal,
                                      ),
                                      compact: true,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MetricCard(
                                      label: 'Tax',
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
                                label: 'Payment',
                                value: order.paymentMethod,
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
                                    label: 'Subtotal',
                                    value: SunmiReceiptService.money(
                                      order.subtotal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _MetricCard(
                                    label: 'Tax',
                                    value: SunmiReceiptService.money(order.tax),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: tight ? 8 : 12),
                            _MetricCard(
                              label: 'Payment',
                              value: order.paymentMethod,
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
    return _customerGlass(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Order Details',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: _headline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Live order view for the customer-facing display',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _body,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
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
                      key: ValueKey('order-items-${order.items.length}'),
                      thumbVisibility: order.items.length > 4,
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: order.items.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = order.items[index];
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
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
                                '${item['name']}_${item['qty']}_${item['lineTotal']}',
                              ),
                              item: item,
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
                  ? 'Thank you for your visit. Your order has been completed.'
                  : 'Please review the order details while the cashier prepares payment.',
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
    return _customerGlass(
      padding: const EdgeInsets.all(30),
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFEEF9FC).withValues(alpha: 0.96),
                    Colors.white.withValues(alpha: 0.78),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
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
                        child: const Icon(
                          Icons.contactless_rounded,
                          size: 48,
                          color: _accentDeep,
                        ),
                      ),
                      const SizedBox(width: 22),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tap Here To Pay',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                color: _headline,
                                letterSpacing: -0.8,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Your payment is ready. Please tap your card or phone on the customer-facing NFC area.',
                              style: TextStyle(
                                fontSize: 17,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                                color: _body,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.96),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ready for contactless payment',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _headline,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                order.note.isEmpty
                                    ? 'Hold the card, phone, or wearable near the rear NFC area until the terminal confirms the transaction.'
                                    : order.note,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                  color: _body,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: const [
                                  _TapHintChip(
                                    icon: Icons.credit_card_rounded,
                                    label: 'Card',
                                  ),
                                  _TapHintChip(
                                    icon: Icons.phone_android_rounded,
                                    label: 'Phone',
                                  ),
                                  _TapHintChip(
                                    icon: Icons.watch_rounded,
                                    label: 'Wearable',
                                  ),
                                ],
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
          const SizedBox(width: 24),
          Expanded(
            flex: 7,
            child: Container(
              height: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1587A6), Color(0xFF0C667F)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
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
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.nfc_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    SunmiReceiptService.money(order.total),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Present your card, phone, or wearable to continue the payment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
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
  }

  Widget _buildTapToPayFooter() {
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
          const Expanded(
            child: Text(
              'Keep the card or phone near the customer-facing NFC area until the terminal confirms the payment.',
              style: TextStyle(
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
    return _customerGlass(
      padding: const EdgeInsets.all(30),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 420;

          return Row(
            children: [
              Expanded(
                flex: 11,
                child: Container(
                  padding: EdgeInsets.all(compact ? 22 : 28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFF6F6E9).withValues(alpha: 0.96),
                        Colors.white.withValues(alpha: 0.82),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
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
                            width: compact ? 80 : 92,
                            height: compact ? 80 : 92,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFF2DCA6), Color(0xFFF8F0CF)],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.volunteer_activism_rounded,
                              size: compact ? 38 : 44,
                              color: const Color(0xFF9F6C00),
                            ),
                          ),
                          const SizedBox(width: 22),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Round Up For Charity?',
                                  style: TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                    color: _headline,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'You can round your payment to the next whole OMR, and the extra amount will be donated to charity.',
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                    color: _body,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 18 : 24),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _CharityAmountCard(
                                title: 'Order Total',
                                amount: order.total,
                                tint: const Color(0xFFE8F8FC),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _CharityAmountCard(
                                title: 'Charity Round Up',
                                amount: order.charityRoundUpAmount,
                                tint: const Color(0xFFFBECC5),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _CharityAmountCard(
                                title: 'New Total',
                                amount: order.charityRoundUpTotal > 0
                                    ? order.charityRoundUpTotal
                                    : order.total,
                                tint: const Color(0xFFDDF5EA),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 22),
                      Row(
                        children: [
                          Expanded(
                            child: _CustomerDecisionButton(
                              label: 'No, keep original total',
                              filled: false,
                              busy: _sendingCustomerDecision,
                              onTap: () => _sendCharityDecision(false),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _CustomerDecisionButton(
                              label: 'Yes, round up for charity',
                              filled: true,
                              busy: _sendingCustomerDecision,
                              onTap: () => _sendCharityDecision(true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 7,
                child: Container(
                  height: double.infinity,
                  padding: EdgeInsets.all(compact ? 22 : 28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF0C34C), Color(0xFFDBA92B)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.26),
                    ),
                    borderRadius: BorderRadius.circular(30),
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
                        width: compact ? 84 : 96,
                        height: compact ? 84 : 96,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.favorite_rounded,
                          size: compact ? 40 : 46,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: compact ? 16 : 20),
                      Text(
                        SunmiReceiptService.money(order.charityRoundUpAmount),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 30 : 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'will go to charity if you choose to round up your payment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 15 : 16,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCharityPromptFooter() {
    return _customerGlass(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: const Row(
        children: [
          _FooterBadge(icon: Icons.volunteer_activism_rounded, success: false),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'The round-up donation is optional. If you choose yes, only the extra amount above the order total will be donated to charity.',
              style: TextStyle(
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

  Future<void> _sendCharityDecision(bool accepted) async {
    if (_sendingCustomerDecision) return;

    setState(() {
      _sendingCustomerDecision = true;
    });

    try {
      debugPrint(
        'CustomerDisplayScreen sending charity decision: accepted=$accepted',
      );

      final delivered =
          await _rearDisplayChannel.invokeMethod<bool>('customerEvent', {
            'type': 'charity_round_up_response',
            'accepted': accepted,
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
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0A1F28).withValues(alpha: 0.16),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Center(
              child: Container(
                width: 360,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 26,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.88),
                      const Color(0xFFF4FBFD).withValues(alpha: 0.84),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.96),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x19000000),
                      blurRadius: 32,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: CircularProgressIndicator(
                        strokeWidth: 4.8,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          _accentDeep,
                        ),
                        backgroundColor: const Color(0xFFE3F4F8),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Preparing Payment',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: _headline,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      order.note.isEmpty
                          ? 'Please wait while the payment terminal is opening.'
                          : order.note,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: _body,
                      ),
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
              isPaid
                  ? 'Thank you. Your payment has been completed.'
                  : 'A cashier will confirm the order and complete payment when ready.',
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

  const _DisplayItemCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final imageAsset = item['imageAsset']?.toString();
    final qty = (item['qty'] as num?)?.toInt() ?? 0;
    final total = (item['lineTotal'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.96)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
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
                  item['name']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _CustomerDisplayScreenState._headline,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quantity: $qty',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _CustomerDisplayScreenState._body,
                  ),
                ),
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
          children: const [
            Icon(
              Icons.receipt_long_outlined,
              size: 50,
              color: _CustomerDisplayScreenState._accentDeep,
            ),
            SizedBox(height: 14),
            Text(
              'No items yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _CustomerDisplayScreenState._headline,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'The display will update as soon as the cashier adds products.',
              textAlign: TextAlign.center,
              style: TextStyle(
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

class _CharityAmountCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color tint;

  const _CharityAmountCard({
    required this.title,
    required this.amount,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.96)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _CustomerDisplayScreenState._body,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            SunmiReceiptService.money(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: _CustomerDisplayScreenState._headline,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerDecisionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback onTap;

  const _CustomerDecisionButton({
    required this.label,
    required this.filled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B7F9E), Color(0xFF0C5F78)],
                )
              : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: filled
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.96),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      filled
                          ? Colors.white
                          : _CustomerDisplayScreenState._accentDeep,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: filled
                      ? Colors.white
                      : _CustomerDisplayScreenState._headline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterBadge extends StatelessWidget {
  final IconData icon;
  final bool success;

  const _FooterBadge({required this.icon, required this.success});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: success
              ? const [Color(0xFFDDF5EA), Color(0xFFF7FBF8)]
              : const [Color(0xFFE7F8FC), Color(0xFFF8FCFD)],
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: success
            ? _CustomerDisplayScreenState._success
            : _CustomerDisplayScreenState._accentDeep,
      ),
    );
  }
}

Widget _customerGlass({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(32),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
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
      ),
    ),
  );
}
