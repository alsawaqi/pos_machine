import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/qr_board_feed.dart';
import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../models/qr_till_models.dart';
import '../providers/providers.dart';
import '../state/pos_controller.dart';
import '../widgets/qr_table_money_panel.dart';

Future<bool> confirmSeparateLocalTable(BuildContext context) async {
  final l10n = L10n.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('table-separate-local-warning'),
          title: Text(l10n.tableSeparateLocal),
          content: Text(l10n.tableSeparateLocalWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: const ValueKey('table-separate-local-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.tableSeparateLocal),
            ),
          ],
        ),
      ) ??
      false;
}

/// A one-table host for the unchanged, server-priced QR money panel.
class DiningTableQrSheet extends ConsumerStatefulWidget {
  const DiningTableQrSheet({
    super.key,
    required this.controller,
    required this.tableId,
    required this.tableLabel,
    required this.floorLabel,
  });

  final PosController controller;
  final int tableId;
  final String tableLabel;
  final String floorLabel;

  @override
  ConsumerState<DiningTableQrSheet> createState() => _DiningTableQrSheetState();
}

class _DiningTableQrSheetState extends ConsumerState<DiningTableQrSheet>
    with WidgetsBindingObserver
    implements QrTableMoneyHost {
  late final QrBoardFeed _feed;
  late final ProviderSubscription<String> _modeSubscription;
  bool _openingLocal = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _feed = QrBoardFeed(
      ref.read(qrTillServiceProvider),
      readService: () => ref.read(qrTillServiceProvider),
      arabic: () => arabic,
      floors: [DiningFloor(id: 'sheet', label: widget.floorLabel)],
      tables: [
        DiningTableDefinition(
          id: widget.tableId.toString(),
          floorId: 'sheet',
          name: widget.tableLabel,
          sizeLabel: '',
          seats: 0,
          sortOrder: 0,
        ),
      ],
    );
    _feed.select(widget.tableId.toString());
    if (!_foreground || ref.read(tableSessionsModeProvider) == 'off') {
      _feed.setForeground(false);
    }
    _feed.addListener(_changed);
    _modeSubscription = ref.listenManual(tableSessionsModeProvider, (_, next) {
      _feed.setForeground(_foreground && next != 'off');
    });
    WidgetsBinding.instance.addObserver(this);
    // The panel's post-frame refresh starts the existing ten-second budget.
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _feed.setForeground(
      _foreground && ref.read(tableSessionsModeProvider) != 'off',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _modeSubscription.close();
    _feed.removeListener(_changed);
    _feed.dispose();
    super.dispose();
  }

  @override
  QrTableBoardRow? get row => _feed.board
      .where((candidate) => candidate.tableId == widget.tableId)
      .firstOrNull;

  @override
  QrActiveOrder? get active => _feed.active[row?.order?.uuid];

  @override
  bool get arabic => ref.read(settingsControllerProvider).language == 'ar';

  @override
  Future<void> refresh() => _feed.refresh();

  @override
  void applyOrderAction(QrOrderActionResult result) =>
      _feed.applyOrderAction(result);

  @override
  void notice(String text, {bool success = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: success
              ? const Color(0xFF12694F)
              : const Color(0xFF9B2C2C),
        ),
      );
  }

  Future<void> _addItems(Future<void> Function() requestRouteExit) async {
    if (_openingLocal) return;
    final mode = ref.read(tableSessionsModeProvider);
    if (mode != 'live' && mode != 'shadow') return;
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = widget.controller;
    final tableId = widget.tableId.toString();
    setState(() => _openingLocal = true);
    try {
      if (mode == 'shadow' && !await confirmSeparateLocalTable(context)) {
        return;
      }
      if (!mounted) return;
      if (container.read(tableSessionsModeProvider) != mode) return;
      await requestRouteExit();
      // A refused claim/manager exit must never open or mutate the local table.
      if (route != null &&
          !route.isActive &&
          container.read(tableSessionsModeProvider) == mode) {
        await controller.openDiningTable(tableId);
      }
    } finally {
      if (mounted) setState(() => _openingLocal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final mode = ref.watch(tableSessionsModeProvider);
    ref.watch(settingsControllerProvider);
    final reference = row?.order?.tempReference ?? row?.order?.receiptNumber;
    return QrTableMoneyPanel(
      host: this,
      tableKey: row?.tableId.toString(),
      tableLabel: widget.tableLabel,
      forceRefresh: _feed.forceRefresh,
      builder: (context, detail, requestRouteExit, settlementInFlight) =>
          Scaffold(
            key: ValueKey('dining-table-qr-sheet-${widget.tableId}'),
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.tableCustomerBillTitle),
                  Text(
                    [
                      widget.floorLabel,
                      widget.tableLabel,
                      ?reference,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  key: const ValueKey('table-sheet-close'),
                  tooltip: l10n.tableSheetClose,
                  onPressed: requestRouteExit,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_feed.error case final error?)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      error,
                      key: const ValueKey('table-sheet-error'),
                      style: const TextStyle(color: Color(0xFF9B2C2C)),
                    ),
                  ),
                Expanded(child: detail),
              ],
            ),
            bottomNavigationBar: settlementInFlight
                ? null
                : SafeArea(
                    child: Padding(
                      key: const ValueKey('table-sheet-footer'),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          if (mode == 'live' || mode == 'shadow')
                            Expanded(
                              child: OutlinedButton(
                                key: const ValueKey('table-sheet-add-items'),
                                onPressed: _openingLocal
                                    ? null
                                    : () => _addItems(requestRouteExit),
                                child: Text(
                                  mode == 'live'
                                      ? l10n.tableAddItems
                                      : l10n.tableSeparateLocal,
                                ),
                              ),
                            ),
                          const SizedBox(width: 12),
                          TextButton(
                            key: const ValueKey('table-sheet-footer-close'),
                            onPressed: requestRouteExit,
                            child: Text(l10n.tableSheetClose),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
    );
  }
}
