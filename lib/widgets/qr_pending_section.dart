import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/qr_pending_feed.dart';
import '../l10n/l10n.dart';
import '../models/qr_pending_order.dart';
import '../providers/providers.dart';
import '../screens/qr_pending_sheet.dart';
import '../services/pos_api_service.dart';
import '../services/qr_till_messages.dart';
import '../services/qr_till_service.dart';

/// Pure composition: the existing held list and all of its callbacks are intact.
class QrPendingStorageLayout extends StatelessWidget {
  const QrPendingStorageLayout({super.key, required this.heldOrders});
  final Widget heldOrders;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final children = [
        Expanded(child: heldOrders),
        const SizedBox(width: 16, height: 16),
        const Expanded(child: QrPendingSection()),
      ];
      return constraints.maxWidth >= 1000
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
    },
  );
}

class QrPendingSection extends ConsumerStatefulWidget {
  const QrPendingSection({super.key, this.visible = true});
  final bool visible;

  @override
  ConsumerState<QrPendingSection> createState() => _QrPendingSectionState();
}

class _QrPendingSectionState extends ConsumerState<QrPendingSection>
    with WidgetsBindingObserver {
  late final QrPendingFeed _feed;
  bool _foreground = true;
  bool _sheetOpen = false;
  String? _moving;
  bool get _arabic => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _feed = QrPendingFeed(
      ref.read(qrTillServiceProvider),
      arabic: () => _arabic,
    );
    _feed.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _visibility();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _visibility() =>
      _feed.setForeground(_foreground && widget.visible && !_sheetOpen);

  @override
  void didUpdateWidget(QrPendingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _visibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feed.removeListener(_changed);
    _feed.dispose();
    super.dispose();
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _move(QrPendingOrder order) async {
    if (_feed.readOnly || !order.canMove || _moving != null) return;
    setState(() => _moving = order.uuid);
    try {
      await ref.read(qrTillServiceProvider).moveQrPendingToCounter(order.uuid);
      if (!mounted) return;
      _notice(L10n.of(context).qrPendingMoved);
      await _feed.forceRefresh();
    } on ApiException catch (error) {
      if (mounted) {
        _notice(qrTillMessageForCode(error.code, arabic: _arabic));
        await _feed.forceRefresh();
      }
    } catch (_) {
      if (mounted) {
        _notice(L10n.of(context).qrPendingUnavailable);
        await _feed.forceRefresh();
      }
    } finally {
      if (mounted) setState(() => _moving = null);
    }
  }

  Future<void> _open(QrPendingOrder order) async {
    if (_feed.readOnly || !order.canSettle || _moving != null || _sheetOpen) {
      return;
    }
    _sheetOpen = true;
    _visibility();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => QrPendingSheet(order: order)),
      );
    } finally {
      _sheetOpen = false;
      if (mounted) {
        _visibility();
        await _feed.forceRefresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => QrPendingList(
    orders: _feed.orders,
    readOnly: _feed.readOnly || _moving != null,
    updatedAt: _feed.updatedAt,
    error: _feed.error,
    refreshing: _feed.refreshing,
    onRefresh: _feed.forceRefresh,
    onMove: _move,
    onOpen: _open,
  );
}

/// Server snapshots only: no controller, cart, local held order or mutation.
class QrPendingList extends StatelessWidget {
  const QrPendingList({
    super.key,
    required this.orders,
    required this.readOnly,
    required this.onMove,
    required this.onOpen,
    required this.onRefresh,
    this.updatedAt,
    this.error,
    this.refreshing = false,
  });
  final List<QrPendingOrder> orders;
  final bool readOnly;
  final DateTime? updatedAt;
  final String? error;
  final bool refreshing;
  final Future<void> Function(QrPendingOrder) onMove;
  final Future<void> Function(QrPendingOrder) onOpen;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return Material(
      key: const ValueKey('qr-pending-section'),
      color: const Color(0xFFF5F8F7),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.qr_code_2, color: Color(0xFF12694F)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.qrPendingTitle,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Badge(
                  key: const ValueKey('qr-pending-count'),
                  label: Text('${orders.length}'),
                  child: const SizedBox(width: 14, height: 14),
                ),
                const SizedBox(width: 12),
                IconButton(
                  key: const ValueKey('qr-pending-refresh'),
                  tooltip: l10n.qrPendingRefresh,
                  onPressed: refreshing ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (refreshing) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              key: const ValueKey('qr-pending-stale'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                [
                  if (updatedAt != null)
                    l10n.qrPendingStale(
                      '${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}',
                    ),
                  l10n.qrPendingUnavailable,
                  error!,
                ].join('\n'),
                style: const TextStyle(color: Color(0xFF963D1E)),
              ),
            ),
          Expanded(
            child: orders.isEmpty
                ? Center(child: Text(l10n.qrPendingEmpty))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final canMove = !readOnly && order.canMove;
                      final canSettle = !readOnly && order.canSettle;
                      final reason = order.refusalCode == null
                          ? null
                          : qrTillMessageForCode(
                              order.refusalCode,
                              arabic: arabic,
                            );
                      return Card(
                        key: ValueKey('qr-pending-${order.uuid}'),
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: Colors.white,
                        child: InkWell(
                          onTap: canSettle ? () => onOpen(order) : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        order.reference,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'OMR ${(order.active.grandTotalBaisas / 1000).toStringAsFixed(3)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      l10n.qrPendingItems(
                                        order.active.items.length,
                                      ),
                                    ),
                                    Text(
                                      l10n.qrPendingAge(order.ageSeconds ~/ 60),
                                    ),
                                    if (order.phoneTail != null)
                                      Text(
                                        l10n.qrPendingPhone(order.phoneTail!),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Chip(
                                  label: Text(qrPendingStateLabel(order, l10n)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                if (reason != null)
                                  Text(
                                    reason,
                                    key: ValueKey(
                                      'qr-pending-refusal-${order.uuid}',
                                    ),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      key: ValueKey(
                                        'qr-pending-move-${order.uuid}',
                                      ),
                                      onPressed: canMove
                                          ? () => onMove(order)
                                          : null,
                                      child: Text(l10n.qrPendingSendToCounter),
                                    ),
                                    FilledButton(
                                      key: ValueKey(
                                        'qr-pending-settle-${order.uuid}',
                                      ),
                                      onPressed: canSettle
                                          ? () => onOpen(order)
                                          : null,
                                      child: Text(l10n.qrPendingSettle),
                                    ),
                                    TextButton(
                                      key: ValueKey(
                                        'qr-pending-void-${order.uuid}',
                                      ),
                                      onPressed: canSettle
                                          ? () => onOpen(order)
                                          : null,
                                      child: Text(l10n.qrPendingVoid),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
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

String qrPendingStateLabel(QrPendingOrder order, L10n l10n) {
  switch (order.charge) {
    case 'live_claim':
      return l10n.qrPendingCardInProgress;
    case 'uncertain':
      return l10n.qrPendingRecovery;
    case 'declined':
      return l10n.qrPendingDeclined;
    case 'cancelled':
      return l10n.qrPendingCancelled;
  }
  if (const {'expired', 'closed', 'missing'}.contains(order.session)) {
    return l10n.qrPendingSessionEnded;
  }
  return order.route == 'counter'
      ? l10n.qrPendingAtCounter
      : l10n.qrPendingWaitingStation;
}
