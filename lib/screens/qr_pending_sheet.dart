import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/qr_pending_feed.dart';
import '../l10n/l10n.dart';
import '../models/qr_pending_order.dart';
import '../models/qr_till_models.dart';
import '../providers/providers.dart';
import '../services/qr_till_messages.dart';
import '../widgets/qr_table_money_panel.dart';

/// Presentation host only. Tender, replay, release and exit protection all stay
/// inside the existing money panel and settlement coordinator.
class QrPendingSheet extends ConsumerStatefulWidget {
  const QrPendingSheet({super.key, required this.order, this.openCheckout});
  final QrPendingOrder order;
  final Future<void> Function(String)? openCheckout;

  @override
  ConsumerState<QrPendingSheet> createState() => _QrPendingSheetState();
}

class _QrPendingSheetState extends ConsumerState<QrPendingSheet>
    with WidgetsBindingObserver
    implements QrTableMoneyHost {
  late final QrPendingFeed _feed;
  QrPendingOrder? get _current => _feed.orders
      .where((order) => order.uuid == widget.order.uuid)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _feed = QrPendingFeed(
      ref.read(qrTillServiceProvider),
      initial: [widget.order],
      arabic: () => arabic,
    );
    _feed.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final state = WidgetsBinding.instance.lifecycleState;
        _feed.setForeground(
          state == null || state == AppLifecycleState.resumed,
        );
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _feed.setForeground(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feed.removeListener(_changed);
    _feed.dispose();
    super.dispose();
  }

  @override
  QrTableBoardRow? get row => null;
  @override
  QrActiveOrder? get active => _current?.active;
  @override
  bool get arabic => Localizations.localeOf(context).languageCode == 'ar';
  @override
  Future<void> refresh() => _feed.refresh();
  @override
  void applyOrderAction(QrOrderActionResult result) =>
      _feed.applyOrderAction(result);
  @override
  void notice(String text, {bool success = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final order = _current ?? widget.order;
    final readOnly = _feed.readOnly || _current?.canSettle != true;
    return QrTableMoneyPanel(
      host: this,
      openCheckout: widget.openCheckout,
      standaloneOrder: order.boardOrder,
      forceRefresh: _feed.forceRefresh,
      builder: (context, detail, requestRouteExit, settlementInFlight) => Scaffold(
        key: ValueKey('qr-pending-sheet-${widget.order.uuid}'),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.qrPendingTitle),
          actions: [
            TextButton(
              key: const ValueKey('qr-pending-sheet-close'),
              onPressed: requestRouteExit,
              child: Text(l10n.qrPendingClose),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_feed.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.qrPendingUnavailable),
              ),
            if (_current == null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.qrPendingGone),
              ),
            if (_current?.refusalCode case final code?)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(qrTillMessageForCode(code, arabic: arabic)),
              ),
            Expanded(
              // Only entry controls become read-only. The panel's dialog routes,
              // recovery and PopScope remain outside this hit-test boundary.
              child: ExcludeFocus(
                excluding: readOnly,
                child: IgnorePointer(
                  ignoring: readOnly,
                  child: Opacity(opacity: readOnly ? 0.55 : 1, child: detail),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
