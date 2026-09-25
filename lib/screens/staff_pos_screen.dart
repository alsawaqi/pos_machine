import '../dine_in/table_loyalty.dart';
import '../draft_recovery/closed_round_proof.dart';
import '../qr_checkout/qr_checkout_receipt.dart';
import '../services/server_receipt_history.dart';
import '../services/table_round_validation.dart';
import '../services/qr_settlement_coordinator.dart' show PreparedQrLocation;
import 'dart:async';
import 'card_reversal_sheet.dart';
import 'card_reversal_factory.dart';
import '../strings/softpos_strings.dart';
import '../bill_combine/combine_controller.dart';
import '../bill_combine/combine_gateway.dart';
import '../bill_combine/combine_local.dart';
import '../bill_combine/combine_screen.dart';
import '../bill_combine/combine_store.dart';
import '../bill_combine/combine_models.dart';
import '../draft_recovery/recovery_admission.dart';
import '../draft_recovery/checkout_recovery.dart';
import '../draft_recovery/checkout_recovery_dialog.dart';
import '../draft_recovery/recovery_controller.dart';
import '../draft_recovery/recovery_gateway.dart';
import '../draft_recovery/recovery_local.dart';
import '../draft_recovery/recovery_models.dart';
import '../draft_recovery/recovery_screen.dart';
import '../draft_recovery/recovery_store.dart';
import '../draft_recovery/recovery_preparation_gate.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../order_workspace/current_order_workspace.dart';
import '../services/presentation_service.dart';
import '../order_attention/order_attention.dart';
import '../order_attention/order_attention_host.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../models/qr_till_models.dart' show QrDeviceRound, QrRoundEnvelope;
import '../models/remote_table_state.dart';
import '../data/table_shadow_repository.dart';
import '../data/table_sync_coordinator.dart';
import '../data/table_replay_configuration.dart';
import '../models/table_sync_models.dart';
import '../services/kitchen_ticket.dart';
import '../services/table_shadow_service.dart';
import '../services/audience_service.dart' show AudienceService;
import '../services/display_strings.dart';
import '../services/local_order_storage_service.dart';
import '../services/manager_authorization_service.dart';
import '../services/order_sync_payload.dart'
    show buildOrderTransferEvent, buildTableRoundLines, tableLineFingerprint;
import '../services/pos_api_service.dart' show ApiException, PosApiService;
import '../services/qr_round_printing.dart'
    show QrRoundAutoPrintController, QrRoundPrintNoticeKind;
import '../services/shift_summary.dart';
import '../services/sunmi_receipt_service.dart';
import '../state/pos_controller.dart';
import '../widgets/animated_feedback_widgets.dart';
import '../qr_quick/qr_quick_copy.dart';
import '../qr_quick/qr_quick_gateway.dart';
import '../qr_quick/qr_quick_store.dart';
import '../qr_quick/qr_quick_models.dart';
import '../qr_checkout/qr_checkout_controller.dart';
import '../qr_checkout/qr_checkout_gateway.dart';
import '../qr_checkout/qr_checkout_models.dart';
import '../qr_checkout/qr_checkout_store.dart';
import '../qr_checkout/qr_checkout_widgets.dart';
import '../services/mosambee_payment_service.dart' show MosambeeFailurePhase;
import 'qr_quick_orders_screen.dart';
import '../order_workspace/workspace_void.dart'
    show assertWorkspaceVoidJournals;
import '../table_cancellation/table_bill_cancellation.dart';
import '../table_cancellation/table_bill_cancel_dialog.dart';
import '../widgets/qr_round_print_status_indicator.dart';
import '../widgets/sent_line_cancel_dialog.dart';
import '../widgets/table_degraded_banner.dart';
import '../widgets/table_reconciliation_sheet.dart';
import '../providers/providers.dart';
import 'branch_reports_screen.dart';
import 'kitchen_production_screen.dart';
import 'log_expense_screen.dart';
import 'restock_request_screen.dart';
import 'qr_tables_screen.dart';
import '../dine_in/dine_in_screen.dart';
import '../dine_in/dine_in_controller.dart';
import '../dine_in/dine_in_models.dart';
import '../dine_in/dine_in_gateway.dart';
import '../dine_in/dine_in_store.dart';
import 'stock_count_screen.dart';
import 'waste_product_screen.dart';
import 'settings_screen.dart';
import 'shift_close_preflight.dart';
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

/// Phase C4 — the void/comp reason label to SHOW for [arabic] UI: the
/// merchant's Arabic name when provided, else the English identity name
/// (stored values and payloads always keep the English name).
String _reasonDisplayName(String name, String? nameAr, bool arabic) =>
    arabic && nameAr != null && nameAr.trim().isNotEmpty ? nameAr : name;

/// Mutable source state for the comp dialog's line/quantity selection.
/// Selecting a line always starts at its full quantity; returning to the whole
/// order clears quantity. [normalizedQty] omits that full-line default.
class MachineCompSelectionDraft {
  int? lineIndex;
  int? qty;

  void selectTarget(int? nextLineIndex, List<CartItem> cart) {
    if (nextLineIndex == null ||
        nextLineIndex < 0 ||
        nextLineIndex >= cart.length ||
        cart[nextLineIndex].qty <= 0) {
      lineIndex = null;
      qty = null;
      return;
    }
    lineIndex = nextLineIndex;
    qty = cart[nextLineIndex].qty;
  }

  void changeQty(int delta, List<CartItem> cart) {
    final index = lineIndex;
    if (index == null || index < 0 || index >= cart.length) return;
    final lineQty = cart[index].qty;
    if (lineQty <= 0) return;
    qty = ((qty ?? lineQty) + delta).clamp(1, lineQty).toInt();
  }

  int? normalizedQty(List<CartItem> cart) {
    final index = lineIndex;
    if (index == null || index < 0 || index >= cart.length) return null;
    final lineQty = cart[index].qty;
    if (lineQty <= 0) return null;
    final selectedQty = (qty ?? lineQty).clamp(1, lineQty).toInt();
    return selectedQty == lineQty ? null : selectedQty;
  }
}

/// D-B1 preview law in integer baisas. The net floor and N guard deliberately
/// precede the clamp, matching mithqal_pricing v0.2.0 exactly.
int machineLineCompPreviewBaisas({
  required int lineTotalBaisas,
  required int lineDiscountBaisas,
  required int lineQty,
  int? compQty,
}) {
  final rawNet = lineTotalBaisas - lineDiscountBaisas;
  final net = rawNet < 0 ? 0 : rawNet;
  if (net == 0 || lineQty <= 0) return 0;
  final selectedQty = compQty == null
      ? lineQty
      : compQty.clamp(1, lineQty).toInt();
  return selectedQty == lineQty
      ? net
      : ((2 * net * selectedQty) + lineQty) ~/ (2 * lineQty);
}

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

/// Display-only union; server occupancy never mutates a local table session.
bool customerOccupiesDiningTable({
  required String mode,
  required DiningTableSession? session,
  RemoteTableState? remote,
}) =>
    mode != 'off' &&
    (session == null ||
        remote?.billSource == 'qr_web' ||
        (remote?.needsReviewCount ?? 0) > 0) &&
    const {'open', 'billing'}.contains(remote?.seatingStatus);

bool customerBillEntryBlocked({
  required bool localCheckoutOpen,
  required bool processingPayment,
  required bool charityPrompt,
  required bool paymentLaunchOverlay,
  required bool recordedSplitWithCart,
}) =>
    localCheckoutOpen ||
    processingPayment ||
    charityPrompt ||
    paymentLaunchOverlay ||
    recordedSplitWithCart;

/// Shared production tap seam. Only the legacy local branch opens the cart.
Future<void> routeDiningTableTap({
  required String tableId,
  required String mode,
  required DiningTableSession? session,
  required RemoteTableState? remote,
  required PosController controller,
  required Future<void> Function() openCustomerBill,
  required Future<void> Function() openPaidDialog,
  required VoidCallback localOpened,
}) async {
  if (customerOccupiesDiningTable(
    mode: mode,
    session: session,
    remote: remote,
  )) {
    await openCustomerBill();
  } else if (session?.status == DiningTableStatus.paid) {
    await openPaidDialog();
  } else {
    await controller.openDiningTable(tableId);
    localOpened();
  }
}

class TableActivityNoticeContent extends StatelessWidget {
  const TableActivityNoticeContent({
    super.key,
    required this.notices,
    required this.onTap,
  });
  final List<TableActivityNotice> notices;
  final ValueChanged<TableActivityNotice> onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final notice in notices)
        InkWell(
          key: ValueKey('table-notice-${notice.eventId}'),
          onTap: () => onTap(notice),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tableActivityMessage(L10n.of(context), notice)),
          ),
        ),
    ],
  );
}

Future<String?> showCustomerDiningTableActions(
  BuildContext context, {
  required String mode,
  required bool hasBill,
}) {
  final l10n = L10n.of(context);
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasBill)
            ListTile(
              key: const ValueKey('table-action-customer-bill'),
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(l10n.tableCustomerBillTitle),
              onTap: () => Navigator.pop(context, 'customer_bill'),
            ),
          if (mode != 'off')
            ListTile(
              key: const ValueKey('table-action-add-items'),
              leading: const Icon(Icons.add),
              title: Text(
                mode == 'live' ? l10n.tableAddItems : l10n.tableSeparateLocal,
              ),
              onTap: () => Navigator.pop(context, 'add_items'),
            ),
          ListTile(
            title: Text(l10n.commonCancel),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    ),
  );
}

bool tableBillNeedsSheet(String mode, RemoteTableState? bill) =>
    mode == 'live' &&
    bill?.billOrderUuid != null &&
    ((bill?.needsReviewCount ?? 0) > 0 ||
        bill?.billSource == 'qr_web' ||
        (const {'main_pos', 'handheld'}.contains(bill?.billSource) &&
            (bill?.billCustomerRounds ?? 0) > 0));

/// Screen-only tender read; no repository, ledger or polling writes.
class TableCartPayRouter {
  bool busy = false;
  String? _contextKey;
  int? _tableId;
  DateTime? _readAt;
  RemoteTableState? _row;

  RemoteTableState? known({
    required int tableId,
    required String contextKey,
    required RemoteTableSnapshot board,
  }) {
    final row = board.tables[tableId];
    final boardAt = board.meta.boardFetchedAt ?? row?.fetchedAt;
    if (_tableId == tableId &&
        _contextKey == contextKey &&
        _readAt != null &&
        (boardAt == null || !boardAt.isAfter(_readAt!))) {
      return _row;
    }
    return row;
  }

  Future<void> route({
    required String mode,
    required int? tableId,
    required String contextKey,
    required RemoteTableSnapshot board,
    required Future<List<Map<String, dynamic>>> Function() fetchBoard,
    required bool Function() isCurrent,
    required VoidCallback changed,
    required Future<void> Function() openSheet,
    required Future<void> Function() openLocal,
    RemoteTableSnapshot Function()? latestBoard,
  }) async {
    if (busy || !isCurrent()) return;
    if (mode != 'live' || tableId == null) {
      await openLocal();
      return;
    }
    busy = true;
    changed();
    try {
      var bill = known(tableId: tableId, contextKey: contextKey, board: board);
      // Timestamp at request start: a newer polling snapshot must win later.
      final readAt = DateTime.now();
      try {
        final rows = await fetchBoard();
        final raw = rows.where((row) => row['table_id'] == tableId).firstOrNull;
        final fresh = raw == null
            ? null
            : RemoteTableState.fromBoard(raw, readAt);
        if (!isCurrent()) return;
        bill = fresh;
        _contextKey = contextKey;
        _tableId = tableId;
        _readAt = readAt;
        _row = fresh;
        bill = known(
          tableId: tableId,
          contextKey: contextKey,
          board: latestBoard?.call() ?? board,
        );
      } catch (_) {
        // Offline/read failure uses the last known identity, never a price.
        bill = known(
          tableId: tableId,
          contextKey: contextKey,
          board: latestBoard?.call() ?? board,
        );
      }
      if (!isCurrent()) return;
      changed();
      if (tableBillNeedsSheet(mode, bill)) {
        await openSheet();
      } else {
        await openLocal();
      }
    } finally {
      busy = false;
      changed();
    }
  }
}

Widget buildTableCartPayButtonForTest({
  required double total,
  required bool busy,
  required bool settleBill,
  required VoidCallback onTap,
}) =>
    _PayButton(total: total, busy: busy, settleBill: settleBill, onTap: onTap);

class StaffPosScreen extends ConsumerStatefulWidget {
  const StaffPosScreen({super.key});

  @override
  ConsumerState<StaffPosScreen> createState() => _StaffPosScreenState();
}

/// Screen-owned B3 printer adapter; the coordinator remains the table writer.
class TableKitchenBridge implements DiningTableSyncHooks {
  TableKitchenBridge({
    required this.controller,
    required this.coordinator,
    required this.preferences,
    required this.printer,
    required this.l10n,
    required this.onPrintFailure,
    this.verifySend,
  });

  final PosController controller;
  final TableSyncCoordinator coordinator;
  final SharedPreferences preferences;
  final Future<bool> Function(KitchenTicketData) printer;
  final L10n Function() l10n;
  final void Function() onPrintFailure;
  final Future<String?> Function(DiningTableSession)? verifySend;
  Future<void> _tail = Future.value();
  Future<void> get settled => _tail;

  void attach() {
    controller.diningTableSyncHooks = this;
    controller.onDiningTableFinalRound = (snapshot) async {
      if (!coordinator.live) return false;
      final session = activeSession();
      if (session == null) {
        throw StateError('Missing Live table at final round.');
      }
      if (controller.reservedDiningBillUuid != null) {
        // A live claim freezes the bill. All lines were acknowledged before
        // admission; finalization must verify that proof, never send again.
        await coordinator.settled;
        await validatePending(session);
        if (coordinator.cachedSession(session.tableId)?.serverOrderUuid !=
                controller.reservedDiningBillUuid ||
            (await coordinator.delta(session)).isNotEmpty ||
            hasLocalOnlyDelta(session)) {
          throw StateError(
            'Check payment result: the reserved table draft changed.',
          );
        }
      } else {
        await send(session);
      }
      return true;
    };
    coordinator.printRound = _print;
    coordinator.validateRound = validateSelections;
    coordinator.stockModeForProduct = (id) => controller.allProducts
        .where((product) => product.id == id.toString())
        .firstOrNull
        ?.stockMode;
    coordinator.bindBillIdentity = (session, oldUuid, newUuid) {
      controller.bindDiningTableBillIdentity(
        live: coordinator.live,
        tableId: session.tableId,
        orderReference: session.orderReference,
        seatingKey: session.seatingKey!,
        expectedOrderUuid: oldUuid,
        orderUuid: newUuid,
      );
    };
  }

  void detach() {
    controller.diningTableSyncHooks = null;
    controller.onDiningTableFinalRound = null;
    coordinator.bindBillIdentity = null;
    coordinator.stockModeForProduct = null;
    coordinator.validateRound = null;
  }

  void validateSelections(List<Map<String, dynamic>> lines) {
    validateTableRoundSelections(
      lines,
      productForId: (id) => controller.allProducts
          .where((product) => product.id == id.toString())
          .firstOrNull,
      groupsForProduct: controller.addonGroupsForProduct,
    );
  }

  Future<void> validatePending(DiningTableSession session) async {
    await coordinator.settled;
    if ((await coordinator.heldRounds(session)).isNotEmpty) {
      throw const TableRoundReviewRequired();
    }
    validateSelections(await coordinator.delta(session));
  }

  DiningTableSession? activeSession() {
    final id = controller.activeDiningTableId;
    if (id == null) return null;
    final session = controller.diningSessionFor(id);
    if (session == null) return null;
    return session.copyWith(
      draft: controller.createDraft(
        serverOrderUuid: controller.activeDiningTableBillUuid,
      ),
    );
  }

  String _localKey(DiningTableSession s) =>
      'table_local_kitchen_${s.tableId}_${s.orderReference}_${s.occupiedAt}';

  Map<String, int> _localPrinted(DiningTableSession s) {
    final raw = preferences.getString(_localKey(s));
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    );
  }

  List<CartItem> _localOnly(DiningTableSession s) => (s.draft?.items ?? [])
      .where((i) => buildTableRoundLines([i]).isEmpty)
      .toList();

  bool hasLocalOnlyDelta(DiningTableSession s) {
    final printed = _localPrinted(s);
    return _localOnly(s).any((i) => i.qty > (printed[i.mergeSignature] ?? 0));
  }

  Future<bool> _print(
    DiningTableSession session,
    List<Map<String, dynamic>> items,
  ) async {
    if (!controller.printKitchenTickets) return false;
    final printed = _localPrinted(session);
    final localItems = <Map<String, dynamic>>[];
    for (final item in _localOnly(session)) {
      final qty = item.qty - (printed[item.mergeSignature] ?? 0);
      if (qty <= 0) continue;
      localItems.add({
        ...item.toMap(),
        'name': '${item.product.name} (${l10n().tableLocalOnly})',
        'qty': qty,
      });
    }
    if (items.isEmpty && localItems.isEmpty) return false;
    final temp = session.tempReference?.trim() ?? '';
    var ok = false;
    try {
      ok = await printer(
        KitchenTicketData(
          orderLabel: temp.isEmpty ? session.orderReference : temp,
          orderTypeLabel: localizedOrderType(l10n(), OrderType.dineIn),
          tableLabel:
              controller.diningTableDefinitions
                  .where((t) => t.id == session.tableId)
                  .firstOrNull
                  ?.name ??
              session.tableId,
          time: coordinator.clock().toUtc(),
          isHold: false,
          items: [...items, ...localItems],
        ),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      onPrintFailure();
      return false;
    }
    for (final item in _localOnly(session)) {
      printed[item.mergeSignature] = math.max(
        printed[item.mergeSignature] ?? 0,
        item.qty,
      );
    }
    await preferences.setString(_localKey(session), jsonEncode(printed));
    return true;
  }

  Future<void> send(DiningTableSession session) {
    final operation = _tail.then((_) async {
      if (!coordinator.live) return;
      final refusal = await verifySend?.call(session);
      if (refusal != null) throw StateError(refusal);
      final round = await coordinator.sendRound(session);
      if (round == null && hasLocalOnlyDelta(session)) {
        await _print(session, []);
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  @override
  void onTableOccupied(DiningTableSession s) => coordinator.onTableOccupied(s);
  @override
  void onTableDraftPersisted(DiningTableSession s) =>
      coordinator.onTableDraftPersisted(s);
  @override
  void onTableLeft(String tableId) {
    if (!coordinator.live) return;
    // Capture before the controller resets; a later occupancy must never be
    // mistaken for the cart that just left this table.
    final session = activeSession() ?? coordinator.cachedSession(tableId);
    if (session != null) unawaited(send(session).catchError((Object _) {}));
  }

  @override
  void onTableTransferred(String fromId, DiningTableSession moved) =>
      coordinator.onTableTransferred(fromId, moved);
  @override
  void onTablesJoined(DiningTableSession head, DiningTableSession seat) =>
      coordinator.onTablesJoined(head, seat);
  @override
  void onTablesCleared(Set<String> ids, DiningTableSession? head) {
    // The paid-table card's Clear button frees local furniture, not the sale.
    // Its existing pay row must remain the only money action (even offline).
    if (head?.status == DiningTableStatus.paid) return;
    coordinator.onTablesCleared(ids, head);
  }

  @override
  void onTablePaid(DiningTableSession paid, OrderSnapshot snapshot) =>
      coordinator.onTablePaid(paid, snapshot);
}

/// Local drafts are not a branch catalogue. A Live transition may only replay
/// tables present in the paired device's verified cached configuration.
class TableModeTransition {
  TableModeTransition(this.bridge, {required this.loadConfiguration});
  final TableKitchenBridge bridge;
  final Future<TableReplayConfiguration?> Function() loadConfiguration;
  Future<void> _tail = Future<void>.value();

  Future<Set<String>> enterLive() {
    final next = _tail.then((_) async {
      final coordinator = bridge.coordinator;
      final skipped = <String>{};
      if (!coordinator.live) return skipped;
      await coordinator.settled;
      final ids = (await coordinator.loadSessions())
          .where(
            (s) =>
                s.status == DiningTableStatus.occupied &&
                !(s.seatingKey?.isNotEmpty ?? false),
          )
          .map((s) => s.tableId)
          .toList();
      final configuration = await loadConfiguration();
      if (configuration == null) return ids.toSet();
      Future<bool> admitted(String id) async {
        final current = await loadConfiguration();
        return coordinator.live &&
            current != null &&
            current.scope == configuration.scope &&
            current.tableIds.contains(id);
      }

      for (final id in ids) {
        if (!coordinator.live) return skipped;
        if (!await admitted(id)) {
          skipped.add(id);
          continue;
        }
        // Re-read after each await: a cashier may have cleared/moved the table.
        final stored = (await coordinator.loadSessions())
            .where((s) => s.tableId == id)
            .firstOrNull;
        if (stored == null ||
            stored.status != DiningTableStatus.occupied ||
            (stored.seatingKey?.isNotEmpty ?? false)) {
          continue;
        }
        final active = bridge.activeSession();
        final session = active?.tableId == id ? active! : stored;
        // Finish open/identity adoption before capturing the round. An open
        // ACK may hydrate an older persisted draft, but not the active cart.
        coordinator.onTableOccupied(session);
        await coordinator.settled;
        if (!coordinator.live) return skipped;
        if (!await admitted(id)) {
          skipped.add(id);
          continue;
        }
        final current = (await coordinator.loadSessions())
            .where((s) => s.tableId == id)
            .firstOrNull;
        if (current == null ||
            current.status != DiningTableStatus.occupied ||
            current.orderReference != stored.orderReference ||
            current.occupiedAt != stored.occupiedAt) {
          continue;
        }
        final latest = bridge.activeSession();
        await bridge.send(latest?.tableId == id ? latest! : current);
      }
      return skipped;
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

/// Debounce and stale-response fencing only; has no table/storage capability.
class TableSearchController extends ChangeNotifier {
  TableSearchController(this.search);
  final Future<List<TableSearchResult>> Function(String) search;
  Timer? _timer;
  int _generation = 0;
  String _key = '';
  bool _disposed = false;
  bool offline = false, failed = false, searching = false;
  List<TableSearchResult> results = const [];
  static bool eligible(String text) {
    final q = text.trim();
    return q.length >= 2 &&
        q.length <= 32 &&
        (q.toLowerCase().startsWith('t-') || RegExp(r'^\d{4,}$').hasMatch(q));
  }

  void update(
    String query, {
    required bool enabled,
    required bool degraded,
    String scope = '',
  }) {
    final q = query.trim();
    final key = '$scope|$enabled|$degraded|$q';
    if (_disposed || key == _key) return;
    _key = key;
    final generation = ++_generation;
    _timer?.cancel();
    results = const [];
    failed = false;
    offline = enabled && degraded && eligible(q);
    searching = enabled && !degraded && eligible(q);
    notifyListeners();
    if (!searching) return;
    _timer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final rows = await search(q);
        if (_disposed || generation != _generation) return;
        results = List.unmodifiable(rows);
      } catch (_) {
        if (_disposed || generation != _generation) return;
        failed = true;
      }
      searching = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}

List<DiningTableDefinition> tableSearchMatches({
  required List<DiningTableDefinition> local,
  required List<DiningTableDefinition> definitions,
  required String floorId,
  required List<TableSearchResult> results,
}) {
  final ids = {for (final row in results) row.tableId.toString()};
  return {
    for (final table in local) table.id: table,
    for (final table in definitions)
      if (table.floorId == floorId && ids.contains(table.id)) table.id: table,
  }.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

String tableActivityMessage(L10n l10n, TableActivityNotice notice) {
  final label = notice.reference == null
      ? notice.tableLabel
      : '${notice.tableLabel} · ${notice.reference}';
  return switch (notice.kind) {
    TableActivityKind.pending => l10n.tableCustomerPending(
      label,
      notice.itemCount!,
    ),
    TableActivityKind.kitchen => l10n.tableCustomerKitchen(label),
    TableActivityKind.bill => l10n.tableCustomerBill(label),
  };
}

class TableSearchSummary extends StatelessWidget {
  const TableSearchSummary({super.key, required this.search});
  final TableSearchController search;
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final text = search.offline
        ? l10n.tableSearchOffline
        : search.failed
        ? l10n.tableSearchFailed
        : search.searching
        ? l10n.tableSearchSearching
        : null;
    if (text != null) return Text(text);
    if (search.results.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final result in search.results)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5FC),
                  border: Border.all(color: const Color(0xFF356BDD)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    l10n.tableSearchMatch(
                      result.label,
                      result.reference ?? '—',
                      result.totalBaisas == null
                          ? '—'
                          : (result.totalBaisas! / 1000).toStringAsFixed(3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DiningTableActivityBadge extends StatelessWidget {
  const DiningTableActivityBadge({
    super.key,
    required this.mode,
    this.sending = false,
    this.pendingRounds = 0,
    this.needsReview = 0,
  });
  final String mode;
  final bool sending;
  final int pendingRounds, needsReview;
  @override
  Widget build(BuildContext context) {
    if (mode != 'live') return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final parts = [
      if (sending) l10n.tableSending,
      if (needsReview > 0) l10n.tableActivityReview(needsReview),
      if (pendingRounds > 0) l10n.tablePendingBell(pendingRounds),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Text(
        parts.join(' · '),
        key: const ValueKey('table-activity-badge'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: Color(0xFF755411)),
      ),
    );
  }
}

Future<String?> showTableSearchKeyboard(
  BuildContext context, {
  required String initialValue,
  required ValueChanged<String> onChanged,
}) => showDialog<String>(
  context: context,
  builder: (_) => _InAppKeyboardDialog(
    title: L10n.of(context).posSearchTablesTitle,
    initialValue: initialValue,
    hintText: L10n.of(context).posSearchTablesHint,
    tableSearch: true,
    onChanged: onChanged,
  ),
);

class _StaffPosScreenState extends ConsumerState<StaffPosScreen> {
  TableShadowRepository? _tableShadow;
  RemoteTableSnapshot _remoteTables = const RemoteTableSnapshot();
  String _tableShadowMode = 'off';
  bool _customerBillRouteOpen = false;
  final _tableCartPay = TableCartPayRouter();
  TableKitchenBridge? _tableKitchen;
  Future<void>? _tableKitchenInit;
  StreamSubscription<void>? _tableKitchenChanges;
  StreamSubscription<List<TableSyncVerdict>>? _tableVerdicts;
  final _cancellingWorkspaces =
      <
        String,
        ({CurrentOrderWorkspace workspace, String scope, String? token})
      >{};
  TableReconciliationPresenter? _tableReconciliation;
  TableModeTransition? _tableModeTransition;
  final _tableControllerReady = Completer<void>();
  late final TableSearchController _tableSearch;
  StreamSubscription<void>? _tablePendingChanges;
  Set<String> _pendingTableIds = {};
  final _tablePaymentContexts = <String, Completer<TablePaymentContext>>{};
  Map<String, int> _tableUnsent = {};
  Map<String, DateTime> _tableSentAt = {};
  bool _tableSendBusy = false;
  final _orderPreparations = RecoveryPreparationGate();
  int _tableSentRefresh = 0;
  late final PosController controller;
  late final TextEditingController _customerNumberController;
  late final TextEditingController _vehiclePlateController;
  late final ValueNotifier<DateTime> _clockNow;
  late final ScrollController _currentOrderScrollController;
  late final QrRoundAutoPrintController _qrRoundAutoPrintController;
  final ManagerAuthorizationService _managerAuthorization =
      ManagerAuthorizationService();
  Timer? _clockTimer;
  Timer? _configPollTimer;
  Timer? _popupTimer;

  /// Device↔device order transfer: the inbox of orders other terminals sent
  /// to THIS one (server snapshots, refreshed by [_refreshTransferInbox]).
  Timer? _transferPollTimer;
  List<Map<String, dynamic>> _incomingTransfers = const [];

  /// A transfer this device CLAIMED (owns server-side) but couldn't load
  /// because a tender raced the claim. Parked here and loaded by the poll
  /// tick as soon as the console is idle — never dropped silently.
  Map<String, dynamic>? _claimedTransferPendingLoad;
  bool _showPaymentPage = false;
  bool _normalQrCheckoutOpen = false;
  bool _qrTransferBusy = false;
  bool _qrOrdersListOpen = false;
  CurrentOrderWorkspace? _transferredQrWorkspace;
  CurrentOrderWorkspace? _workspace;
  Widget Function(CurrentOrderWorkspace)? _workspaceEditor;

  void _workspaceChanged() {
    final workspace = _workspace;
    if (workspace == null || !mounted) return;
    _applyAudienceGate();
    void update() {
      if (!mounted || !identical(workspace, _workspace)) return;
      setState(() {});
      if (!_normalQrCheckoutOpen) {
        unawaited(
          PresentationService.instance.showWorkspaceBill(
            workspace,
            workspace.cartBill,
            stale: workspace.stale,
            arabic: ref.read(settingsControllerProvider).language == 'ar',
          ),
        );
      }
    }

    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  /// UI-only entry: all writes remain owned by the guarded bill editor.
  void openServerWorkspace(
    Widget Function(CurrentOrderWorkspace) editor, {
    bool quick = false,
    String? tableLabel,
  }) {
    if (_workspace != null ||
        _showPaymentPage ||
        _normalQrCheckoutOpen ||
        controller.isProcessingPayment ||
        controller.hasRecordedSplitPayments ||
        controller.showPaymentLaunchOverlay ||
        controller.showCharityRoundUpPrompt) {
      return;
    }
    late final CurrentOrderWorkspace workspace;
    workspace = CurrentOrderWorkspace(
      mainCart: quick || tableLabel != null,
      tableLabel: tableLabel,
      editOptions: _editQrCartOptions,
      onExit: () {
        if (!mounted || !identical(_workspace, workspace)) return;
        workspace.removeListener(_workspaceChanged);
        workspace.dispose();
        unawaited(PresentationService.instance.clearWorkspaceBill(workspace));
        setState(() {
          _workspace = null;
          _workspaceEditor = null;
          _customerBillRouteOpen = false;
        });
        _applyAudienceGate();
        if (quick && workspace.returnToList) unawaited(_openQuickOrders());
        if (tableLabel != null && !workspace.returnToLocalCart) {
          unawaited(
            controller.returnToDiningFloorPlan().then((_) async {
              await _retireClosedTableCopies(force: true);
            }),
          );
        }
      },
    )..addListener(_workspaceChanged);
    setState(() {
      _workspace = workspace;
      _workspaceEditor = editor;
    });
    _workspaceChanged();
  }

  Future<void> _openQuickOrders() async {
    final location = ref.read(qrLocationProvider);
    if (location is PreparedQrLocation) unawaited(location.prepare());
    if (_workspace?.mainCart == true) {
      await _workspace!.requestClose();
      return;
    }
    if (_workspace != null ||
        _showPaymentPage ||
        _normalQrCheckoutOpen ||
        controller.isProcessingPayment ||
        controller.hasRecordedSplitPayments) {
      return;
    }
    _qrOrdersListOpen = true;
    _applyAudienceGate();
    String? uuid;
    try {
      uuid = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (routeContext) => QrQuickOrdersScreen(
            openCheckout: _launchQrCheckout,
            onOpen: (uuid) async => Navigator.pop(routeContext, uuid),
          ),
        ),
      );
    } finally {
      _qrOrdersListOpen = false;
      if (mounted) _applyAudienceGate();
    }
    if (!mounted || uuid == null) return;
    openServerWorkspace(
      (workspace) => QrQuickOrdersScreen(
        workspace: workspace,
        workspaceUuid: uuid,
        openCheckout: _launchQrCheckout,
      ),
      quick: true,
    );
  }

  void _catalogueProduct(Product product) {
    final workspace = _workspace;
    if (workspace != null) {
      final available = machineQuickCatalogue(
        ref.read(catalogProvider).asData?.value,
      );
      final picked = available
          .where((p) => p.id.toString() == product.id)
          .firstOrNull;
      if (picked != null) unawaited(workspace.pick(picked));
      return;
    }
    if (!controller.isUnorderable(product)) controller.addProduct(product);
  }

  Future<QrQuickLine?> _editQrCartOptions(Map<String, dynamic> line) async {
    final product = ref
        .read(catalogProvider)
        .asData
        ?.value
        .products
        .where((p) => p.id == '${line['product_id']}')
        .firstOrNull;
    if (product == null) return null;
    // Server orders use only the merchant's catalogue, never demo option IDs.
    final groups = controller.addonGroups.isEmpty
        ? const <_ModifierGroupDefinition>[]
        : _resolveModifierGroups(product);
    final ids = (line['addons'] as List? ?? const [])
        .map((a) => '${qrMap(a)['add_on_id']}')
        .toSet();
    final item = CartItem(
      product: product,
      qty: (line['qty'] as num).toInt(),
      notes: line['notes'] as String? ?? '',
      modifiers: [
        for (final group in groups)
          for (final option in group.options)
            if (ids.contains(option.id))
              CartItemModifier(
                id: option.id,
                group: group.title,
                label: option.label,
                labelAr: option.labelAr,
                price: option.price,
              ),
      ],
    );
    final result = await showDialog<_CartItemCustomizationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomizeCartItemDialog(item: item, groups: groups),
    );
    if (!mounted || result == null) return null;
    return QrQuickLine(
      int.parse(product.id),
      item.qty,
      result.modifiers.map((m) => int.parse(m.id)).toList(),
      notes: result.notes,
    );
  }

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

  // Home was a no-op placeholder ("you're already home") and History is also
  // on the bottom action bar — both removed here to declutter the cramped top
  // bar (the order-history dialog stays reachable from the footer card).
  static const _secondaryNavItems = <_NavItemData>[
    _NavItemData('QR Quick Orders', Icons.receipt_long_outlined),
    _NavItemData('QR Tables', Icons.qr_code_2_rounded),
    _NavItemData('Offers', Icons.local_offer_outlined), // P-F9
    _NavItemData('Kitchen', Icons.soup_kitchen_outlined), // P-G1
    _NavItemData('Messages', Icons.mail_outline), // P-G6
    _NavItemData('Report', Icons.description_outlined),
  ];

  static const _categoryIcons = <String, IconData>{
    'Coffee': Icons.coffee_outlined,
    'Drinks': Icons.local_bar_outlined,
    'Food': Icons.restaurant_outlined,
    'Dessert': Icons.cake_outlined,
    'Bakery': Icons.bakery_dining_outlined,
    'Special': Icons.star_border_rounded,
  };

  late final Object _attentionLease;

  @override
  void initState() {
    super.initState();
    _attentionLease = enterStaffAttention();
    controller = PosController();
    controller.verifyDiningTableTender = () =>
        _verifyLocalTableBill(tender: true);
    _tableSearch = TableSearchController(
      (q) => ref.read(apiServiceProvider).searchTables(q),
    )..addListener(_onTableSearchChanged);
    ref.listenManual(
      sessionControllerProvider,
      (_, _) => _scheduleTableSearch(),
    );
    ref.listenManual(
      settingsControllerProvider,
      (_, _) => _scheduleTableSearch(),
    );
    controller.isLiveSharedTable = () => _liveTable;
    controller.addListener(_onTableCartChanged);
    controller.prepareDiningTableTender = _prepareLiveTableTender;
    controller.liveDiningTotal = () => _liveBill?.total;
    ref.listenManual(tableSessionsModeProvider, (previous, next) {
      _scheduleTableSearch();
      if (previous != 'live' && next == 'live') {
        unawaited(
          _enterLiveTables().catchError((Object _) {
            if (mounted) _showTableActionFailure();
          }),
        );
      }
    });
    // The app-wide attention listener owns both quick and table arrival alerts.
    // The shadow feed still projects tables/printing but cannot ring twice.
    _qrRoundAutoPrintController = ref.read(qrRoundAutoPrintControllerProvider);
    controller.onOrderCompleted = _handleOrderCompleted;
    controller.canonicalDiningBillUuid = () => _tableKitchen?.coordinator
        .cachedSession(controller.activeDiningTableId ?? '')
        ?.serverOrderUuid;
    controller.refreshServerReceipt = (snapshot) async {
      try {
        await ref
            .read(tableSyncCoordinatorProvider)
            .settled
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        /* The durable outbox retains the event for normal retry. */
      }
      final history = ServerReceiptHistory(
        debugOrderStorageOverride ?? LocalOrderStorageService.instance,
      );
      final current = await history.find(snapshot.serverOrderUuid);
      await controller.refreshOrderHistory();
      final earned = ref
          .read(tableSyncCoordinatorProvider)
          .loyaltyEarnedByOrder
          .remove(snapshot.serverOrderUuid);
      if (mounted && current?.serverReceiptConfirmed == true) {
        final text = loyaltyEarnedText(_arabicTable, earned);
        if (text.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text, key: const ValueKey('table-loyalty-earned')),
            ),
          );
        }
      }
      return current ?? snapshot;
    };
    // Phase 3C — push advertising-slide play-time telemetry (best-effort).
    controller.onSliderDisplay = (event) => unawaited(
      ref
          .read(orderSyncRepositoryProvider)
          .pushSliderDisplay(
            // Phase 1A — fold in anonymous audience counts (no-op when off).
            ref.read(audienceServiceProvider).enrich(event),
          ),
    );
    // #3 — persist the local shelf-stock decrement to Drift so the produced
    // count survives a restart (until the next config sync reconciles).
    controller.onShelfStockConsumed = (sold) =>
        unawaited(ref.read(appDatabaseProvider).consumeProductShelfStock(sold));
    controller.onOrderHeld = _handleOrderHeld;
    controller.onOrderVoided = _handleOrderVoided;
    controller.onCompClearedAfterCartEdit = _handleCompClearedAfterCartEdit;
    controller.onDraftRedemptionCleared = (message) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      });
    };
    // P-F8 — merchant order numbering: the controller asks for the next
    // sequential number at payment time through this bridge.
    controller.allocateReceiptNumber = () =>
        ref.read(apiServiceProvider).allocateOrderNumber();
    // Phase G4 — printing is fail-safe (never blocks a sale); this surfaces
    // a throttled staff alert when real hardware fails (paper out / cover).
    controller.onPrintFailed = _handlePrintFailed;
    // Phase C4 — controller/service-authored messages resolve through the
    // device language without a BuildContext (see l10nProvider). Stored
    // messages keep the language they were authored in until the next action.
    controller.localize = () => ref.read(l10nProvider);
    _managerAuthorization.localize = () => ref.read(l10nProvider);
    // Keep the printing toggles in sync with Settings.
    final settings = ref.read(settingsControllerProvider);
    controller.printReceipts = settings.printReceipts;
    controller.printKitchenTickets = settings.printKitchenTickets;
    ref.listenManual(settingsControllerProvider, (prev, next) {
      controller.printReceipts = next.printReceipts;
      controller.printKitchenTickets = next.printKitchenTickets;
      if (prev?.printQrKitchenRounds != next.printQrKitchenRounds) {
        unawaited(
          _qrRoundAutoPrintController.setEnabled(next.printQrKitchenRounds),
        );
      }
      // Phase 1A — re-evaluate the audience camera when the operator toggles
      // the local switch (the server consent still wins, see the gate).
      if (prev?.audienceMeasurement != next.audienceMeasurement) {
        _applyAudienceGate();
      }
    });
    _customerNumberController = TextEditingController();
    _vehiclePlateController = TextEditingController();
    _clockNow = ValueNotifier<DateTime>(DateTime.now());
    _currentOrderScrollController = ScrollController();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final previous = _clockNow.value;
      final now = DateTime.now();
      _clockNow.value = now;
      // Gap sweep G1 — on each minute boundary, let time-windowed product
      // tiles flip available/unavailable (no-op when no windows configured).
      if (now.minute != previous.minute || now.hour != previous.hour) {
        controller.onMinuteTick();
      }
    });

    ref.listenManual(qrRoundPrintNoticeProvider, (previous, next) {
      if (next == null || !mounted) return;
      final arabic = ref.read(settingsControllerProvider).language == 'ar';
      final message = switch (next.kind) {
        QrRoundPrintNoticeKind.expiredUnprinted =>
          arabic
              ? 'انتهت صلاحية ${next.count} جولة غير مطبوعة أثناء توقف الجهاز.'
              : '${next.count} unprinted QR round(s) expired while this device was offline.',
        QrRoundPrintNoticeKind.printerFailed =>
          arabic
              ? 'تعذرت طباعة جولة QR. افحص الطابعة؛ سيعيد الجهاز المحاولة بأمان.'
              : 'A QR kitchen round did not print. Check the printer; this device will retry safely.',
        QrRoundPrintNoticeKind.positionReset =>
          qrRoundPrintPositionResetMessage(arabic: arabic),
        QrRoundPrintNoticeKind.heldForReview =>
          arabic
              ? 'جولة المطبخ معلقة للمراجعة.'
              : 'Kitchen round held for review.',
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        ref.read(qrRoundPrintNoticeProvider.notifier).clear();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _qrRoundAutoPrintController.start(
        enabled: ref.read(settingsControllerProvider).printQrKitchenRounds,
      );
      await controller.init();
      _tableControllerReady.complete();
      if (mounted && ref.read(tableSessionsModeProvider) == 'live') {
        await _ensureTableKitchen();
      }
      await controller.openRearDisplay();
      // Pre-warm a Mosambee login session so the first card payment is fast.
      controller.prewarmCardPayment();
      // Flush any orders queued in a previous session (e.g. completed offline).
      unawaited(
        ref.read(orderSyncRepositoryProvider).flush().catchError((_) => 0),
      );
      // Phase C3 — subscribe to the branch Reverb channel for live config push.
      ref.read(liveSyncProvider).start();
      // Phase 1A — start anonymous audience measurement when the gate allows
      // (off by default; camera + on-device face counting only).
      _applyAudienceGate();
      // Periodic config poll — a safety net for when real-time push is off
      // (e.g. prod BROADCAST_CONNECTION=log or an unreachable Reverb): pull a
      // delta config every 60s so admin slider/menu edits reach the screen
      // within a minute even without a live event.
      _configPollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        // MC-001 — a deterministic refusal needs another bounded attempt even
        // when no new sale or connectivity transition occurs. Transport errors
        // remain retry-forever; the repository parks only server refusals.
        unawaited(
          ref.read(orderSyncRepositoryProvider).flush().catchError((_) => 0),
        );
        unawaited(
          ref
              .read(configRepositoryProvider)
              .syncConfig()
              // Marketing #46 — the poll may have refreshed the server-driven
              // audience consent; apply it without waiting for a restart.
              .then((_) {
                if (mounted) _applyAudienceGate();
              })
              .catchError((_) {}),
        );
      });
      // Device↔device order transfer: poll the incoming inbox so a transfer
      // sent by another terminal shows up (badge on the Transfer card)
      // within seconds. Silent when offline.
      unawaited(_refreshTransferInbox());
      _transferPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _retryPendingClaimedTransfer();
        unawaited(_refreshTransferInbox());
      });
    });

    // Bridge: feed the branch catalog (from the Drift cache, refreshed from
    // pos_api) into the existing controller. fireImmediately covers the case
    // where the cache is already populated before this screen mounts.
    _catalogSub = ref.listenManual(catalogProvider, (previous, next) {
      final catalog = next.asData?.value;
      if (catalog != null) {
        controller.applyCatalog(
          categories: catalog.categories,
          categoryNamesAr: catalog.categoryNamesAr,
          products: catalog.products,
          floors: catalog.floors,
          tables: catalog.tables,
          taxes: catalog.taxes,
          addonGroups: catalog.addonGroups,
          deliveryProviders: catalog.deliveryProviders,
          expenseCategories: catalog.expenseCategories,
          ingredientBalances: catalog.ingredientBalances,
          discounts: catalog.discounts,
          // P-G6 sweep fix — offers were never bridged here, so every
          // catalog emission WIPED controller.availableOffers (the
          // Offers sheet only worked until the first re-emission).
          offers: catalog.offers,
          loyaltyRules: catalog.loyaltyRules,
          customers: catalog.customers,
          cancelOrderPositions: catalog.cancelOrderPositions,
          reportsPositions: catalog.reportsPositions,
          kitchenPositions: catalog.kitchenPositions,
          orderNumbering: catalog.orderNumbering,
          receiptTemplate: catalog.receiptTemplate,
          voidReasons: catalog.voidReasons,
          compReasons: catalog.compReasons,
          categoryAddonGroupIds: catalog.categoryAddonGroupIds,
          staffMessages: catalog.staffMessages,
          adSlides: catalog.adSlides,
          branchId: ref.read(sessionControllerProvider).branchId,
        );
        // P-G6 — pop a notice when a NEW announcement lands for the
        // signed-in staff member (delta sync or live push). The first
        // emission (previous == null) is the initial cache load — silent.
        _maybeAnnounceNewMessages(previous?.asData?.value, catalog);
      }
    }, fireImmediately: true);

    // Back online → refresh the cached config (best effort).
    _connectivitySub = ref.listenManual(connectivityProvider, (previous, next) {
      if (next.asData?.value == true) {
        unawaited(
          ref.read(configRepositoryProvider).syncConfig().catchError((_) {}),
        );
        // Back online → push any orders queued while offline.
        unawaited(
          ref.read(orderSyncRepositoryProvider).flush().catchError((_) => 0),
        );
        // P-G6 — re-send read receipts that failed while offline.
        final staffId = ref.read(sessionServiceProvider).staff?.id;
        if (staffId != null) {
          _flushMessageReceipts(staffId);
        }
      }
    });
  }

  /// Push a finalized order to pos_api. Captures the device GPS (required at a
  /// geofenced branch — the server fails closed without it) + the staff id,
  /// then enqueues to the durable outbox, which persists the order before any
  /// network I/O and retries it on the next reconnect.
  Future<void> _handleOrderCompleted(OrderSnapshot snapshot) =>
      _orderPreparations.run(() => _prepareCompletedOrder(snapshot));

  Future<void> _prepareCompletedOrder(OrderSnapshot snapshot) async {
    final sharedTable =
        ref.read(tableSessionsModeProvider) == 'live' &&
        snapshot.diningTableId.isNotEmpty;
    final sharedContext = sharedTable ? Completer<TablePaymentContext>() : null;
    if (sharedContext != null) {
      _tablePaymentContexts[snapshot.serverOrderUuid] = sharedContext;
    }
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
    final earnedRuleIds = List<int>.from(controller.effectiveEarnRuleIds);
    // Soft POS evidence for a single (non-split) card payment — read now, before
    // the controller's next-order reset clears it (split tenders carry their own
    // evidence on the snapshot's SplitPaymentRecords).
    final cardCharge = controller.lastCardCharge;
    final tableCheckout = _tableCheckout;
    // Joined tables (v2) — the head party's joined seats, read NOW: the
    // controller frees them the instant the order is marked paid, just after
    // this callback returns its synchronous prefix.
    final joinedTableIds = controller.joinedTableIdsFor(snapshot.diningTableId);

    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        lat = last?.latitude;
        lng = last?.longitude;
      } catch (_) {
        // No immediate fix available. The durable outbox flush holds fenced
        // create/pay events locally until it can add a fresh GPS fix.
      }
    }

    if (sharedContext != null) {
      sharedContext.complete(
        TablePaymentContext(
          lat: lat,
          lng: lng,
          cardCharge: cardCharge,
          eventId: tableCheckout?.attempt?.id,
          prepareEvent: tableCheckout?.journalTablePay,
        ),
      );
      return; // B2 onTablePaid emits pay only; no customer/create/donation path.
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
      if (plate.isNotEmpty && searchedCustomer.phone.isNotEmpty) {
        try {
          // Register against the exact stored phone; never replace the attached id.
          await ref
              .read(apiServiceProvider)
              .saveCustomer(
                name: searchedCustomer.name,
                phone: searchedCustomer.phone,
                plateNumber: plate,
              );
        } catch (_) {
          // Plate linkage remains best-effort; the sale still carries the plate.
        }
      }
    } else if (phone.isNotEmpty) {
      try {
        customerId = await ref
            .read(apiServiceProvider)
            .saveCustomer(
              name:
                  phone, // no separate name field at the POS; phone is the key
              phone: phone,
              plateNumber: plate.isEmpty ? null : plate,
            );
      } catch (_) {
        // leave customerId null; the order is not blocked on this
      }
    }

    // Loyalty earn (v2 #3): an identified customer accrues under every active
    // earn program — unless P-F3's picker recorded an explicit choice for
    // this order (effectiveEarnRuleIds). Phase D4 — a GIFTED order earns
    // nothing (no spend ⇒ no points; the server also guards this).
    final loyaltyRuleIds =
        customerId != null && snapshot.paymentMethod != 'Gift'
        ? earnedRuleIds
        : const <int>[];

    try {
      await ref
          .read(orderSyncRepositoryProvider)
          .enqueue(
            snapshot,
            lat: lat,
            lng: lng,
            staffId: staffId,
            tableId: tableId,
            joinedTableIds: joinedTableIds,
            customerId: customerId,
            plateNumber: plate.isEmpty ? null : plate,
            deliveryProviderName: deliveryProviderName,
            cardCharge: cardCharge,
            loyaltyRuleIds: loyaltyRuleIds,
          );
    } catch (_) {
      // The outbox persists the order before any network call, so it is queued
      // even if this throws; flush() retries on the next reconnect.
    }
  }

  /// Phase C2 — mirror a held order to pos_api via the durable outbox (an
  /// order.hold). Fire-and-forget: the local hold already succeeded, and the
  /// outbox persists + retries the mirror independently of the network.
  Future<void> _handleOrderHeld(OrderSessionDraft draft) =>
      _orderPreparations.run(() => _prepareHeldOrder(draft));

  Future<void> _prepareHeldOrder(OrderSessionDraft draft) async {
    final staffId = ref.read(sessionServiceProvider).staff?.id;
    try {
      await ref
          .read(orderSyncRepositoryProvider)
          .enqueueHold(
            draft,
            staffId: staffId,
            tableId: int.tryParse(draft.diningTableId),
            joinedTableIds: controller.joinedTableIdsFor(draft.diningTableId),
          );
    } catch (_) {
      // The outbox persists the mirror before any network call; flush()
      // retries it on the next reconnect.
    }
  }

  // ── Device↔device order transfer ────────────────────────────────────────────

  /// Refreshes the incoming-transfer inbox (badge on the Transfer card).
  /// Silent on failure — offline just keeps the last known list.
  Future<void> _refreshTransferInbox() async {
    try {
      final rows = await ref.read(apiServiceProvider).fetchIncomingTransfers();
      if (!mounted) return;
      setState(() => _incomingTransfers = rows);
    } catch (_) {
      // Offline / unauthorized — leave the current list intact.
    }
  }

  /// The Transfer card: send the current order to another device at this
  /// branch, or receive one waiting in the inbox. Online-only by design.
  Future<void> _openTransferDialog({
    QrCheckoutController? checkout,
    VoidCallback? exit,
  }) async {
    if (_qrTransferBusy) return;
    final workspace = _workspace?.mainCart == true ? _workspace : null;
    if (workspace != null && workspace.cartControls?.transfer == null) return;
    final l10n = L10n.of(context);

    List<Map<String, dynamic>> devices;
    try {
      devices = await ref.read(apiServiceProvider).listBranchDevices();
    } on ApiException catch (e) {
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: e.message,
        tone: FeedbackTone.warning,
      );
      return;
    } catch (_) {
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: l10n.posTransferNoDevices,
        tone: FeedbackTone.warning,
      );
      return;
    }
    unawaited(_refreshTransferInbox());
    if (!mounted) return;

    final result = await showDialog<_TransferDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _TransferDialog(
        devices: devices,
        incoming: workspace == null ? _incomingTransfers : const [],
        canSend: workspace == null
            ? controller.cart.isNotEmpty
            : (workspace.bill?.total ?? 0) > 0,
      ),
    );
    if (!mounted || result == null) return;

    switch (result) {
      case _TransferSend(:final device):
        if (workspace == null) {
          await _sendTransferTo(device);
          break;
        }
        _qrTransferBusy = true;
        try {
          if (checkout != null) {
            await checkout.cancel();
            if (!checkout.canLeave) return;
          }
          final ok = await workspace.cartControls!.transfer!(
            (device['id'] as num).toInt(),
          );
          if (checkout != null) {
            if (ok) _transferredQrWorkspace = workspace;
            exit?.call();
          } else if (ok && mounted && identical(_workspace, workspace)) {
            workspace.onExit();
          }
        } finally {
          _qrTransferBusy = false;
        }
      case _TransferReceive(:final transfer):
        await _receiveTransfer(transfer);
    }
  }

  /// Send leg: park the current cart on the server addressed to [device].
  /// Pushed ONLINE with an inline ACK (a transfer targets a live colleague's
  /// terminal); the cart clears only after the server confirms.
  Future<void> _sendTransferTo(Map<String, dynamic> device) =>
      _orderPreparations.run(() => _prepareTransferTo(device));

  Future<void> _prepareTransferTo(Map<String, dynamic> device) async {
    await controller.assertNoPendingCombine();
    if (!mounted) return;
    final l10n = L10n.of(context);

    // Money state that doesn't survive the hop (the receiving cart rebuilds
    // from plain lines: no discount/comp/gift/bundle flags, and no delivery-
    // provider identity — the provider decides payout + commission %): fail
    // closed rather than silently repricing on the other terminal.
    if (controller.discount.isActive ||
        controller.appliedComp != null ||
        controller.hasRecordedSplitPayments ||
        controller.hasGiftedLines ||
        controller.cart.any((item) => item.bundleKey.isNotEmpty) ||
        controller.selectedOrderType == OrderType.delivery ||
        controller.selectedDeliveryProviderId != null) {
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: l10n.posTransferBlockedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final draft = controller.prepareTransferDraft();
    if (draft == null) {
      _showPopupMessage(
        title: l10n.posTransferEmptyCartTitle,
        message: l10n.posTransferEmptyCartMessage,
        tone: FeedbackTone.info,
      );
      return;
    }

    final event = buildOrderTransferEvent(
      draft,
      orderUuid: draft.serverOrderUuid,
      targetDeviceId: ((device['id'] as num?) ?? 0).toInt(),
      staffId: ref.read(sessionServiceProvider).staff?.id,
      tableId: int.tryParse(draft.diningTableId),
      joinedTableIds: controller.joinedTableIdsFor(draft.diningTableId),
    );
    if (event == null) {
      // Demo-only cart (no server products) — nothing referable to send.
      _showPopupMessage(
        title: l10n.posTransferEmptyCartTitle,
        message: l10n.posTransferEmptyCartMessage,
        tone: FeedbackTone.info,
      );
      return;
    }

    if (!mounted) return;
    // Freeze the console while the push is in flight (online-only, inline
    // ACK): a tender started mid-push would race completeTransfer's reset —
    // the resumed payment would then snapshot an emptied cart while the
    // server keeps the order claimable on the target device.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    Map<String, dynamic> data;
    try {
      data = await ref.read(apiServiceProvider).pushSync([event]);
    } on ApiException catch (e) {
      _dismissTransferBarrier();
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: e.message,
        tone: FeedbackTone.warning,
      );
      return;
    } catch (_) {
      _dismissTransferBarrier();
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: l10n.posTransferFailedTitle,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final results = (data['results'] as List?) ?? const [];
    final first = results.isNotEmpty
        ? (results.first as Map).cast<String, dynamic>()
        : null;
    if (first?['status'] == 'processed') {
      // Barrier stays up through the reset so no tap can interleave with it.
      final cleared = await controller.completeTransfer();
      _dismissTransferBarrier();
      if (!mounted) return;
      if (cleared) {
        setState(() {
          _showPaymentPage = false;
          _cashTenderInput = '';
          _customerNumberController.clear();
        });
        _showPopupMessage(
          title: l10n.posTransferSentTitle,
          message: (device['name'] ?? '').toString(),
          tone: FeedbackTone.success,
        );
      } else {
        // A tender raced the ACK: the server parked the order for the target,
        // but this cart was deliberately left alone for the running payment.
        _showPopupMessage(
          title: l10n.posTransferSentTitle,
          message: l10n.posTransferConflictMessage,
          tone: FeedbackTone.warning,
        );
      }
    } else {
      _dismissTransferBarrier();
      final error = ((first?['result'] as Map?)?['error'])?.toString() ?? '';
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: error.isEmpty ? l10n.posTransferFailedTitle : error,
        tone: FeedbackTone.warning,
      );
    }
  }

  /// Pops the modal barrier [_sendTransferTo] raises around the online push.
  void _dismissTransferBarrier() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  /// Receive leg: claim [transfer] (server-atomic — a double-grab 409s) and
  /// hydrate the cart from the returned snapshot. Payment then finalises the
  /// SAME server order uuid.
  Future<void> _receiveTransfer(Map<String, dynamic> transfer) =>
      _orderPreparations.run(() => _prepareReceiveTransfer(transfer));

  Future<void> _prepareReceiveTransfer(Map<String, dynamic> transfer) async {
    await controller.assertNoPendingCombine();
    if (!mounted) return;
    final l10n = L10n.of(context);

    // Fail closed BEFORE taking server-side ownership: mid-tender (or between
    // split legs, when recorded money waits for the final push) the cart must
    // not be replaced — and a claimed order the cart can't load would strand,
    // because the server never re-lists claimed transfers.
    if (controller.isProcessingPayment || controller.hasRecordedSplitPayments) {
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: l10n.posTransferReceiveBlockedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    if (controller.cart.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.posTransferReplaceCartTitle),
          content: Text(l10n.posTransferReplaceCartMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.posTransferReceive),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      // The confirm can sit open while a tender starts elsewhere — re-check.
      if (controller.isProcessingPayment ||
          controller.hasRecordedSplitPayments) {
        _showPopupMessage(
          title: l10n.posTransferFailedTitle,
          message: l10n.posTransferReceiveBlockedMessage,
          tone: FeedbackTone.warning,
        );
        return;
      }
    }

    final uuid = (transfer['uuid'] ?? '').toString();
    try {
      final order = await ref.read(apiServiceProvider).claimTransfer(uuid);
      if (!mounted) return;
      if (order['source'] == 'qr_web' && order['order_type'] == 'quick') {
        openServerWorkspace(
          (w) => QrQuickOrdersScreen(
            workspace: w,
            workspaceUuid: uuid,
            openCheckout: _launchQrCheckout,
          ),
          quick: true,
        );
        unawaited(_refreshTransferInbox());
        return;
      }
      final loaded = _hydrateFromTransfer(order);
      setState(() {
        _incomingTransfers = _incomingTransfers
            .where((t) => (t['uuid'] ?? '') != uuid)
            .toList();
        if (loaded) {
          // The hydrated order must not inherit the previous order's screen
          // residue — the submit paths push these fields at pay time.
          _cashTenderInput = '';
          _customerNumberController.clear();
          _vehiclePlateController.clear();
        }
      });
      if (loaded) {
        _showPopupMessage(
          title: l10n.posTransferReceivedTitle,
          message: (transfer['transferred_from_name'] ?? '').toString(),
          tone: FeedbackTone.success,
        );
      } else {
        // Claimed (this device owns it server-side) but a tender raced the
        // claim: park the snapshot — the poll tick loads it once the console
        // is idle. Never show success for a cart that didn't load.
        _claimedTransferPendingLoad = order;
        _showPopupMessage(
          title: l10n.posTransferReceivedTitle,
          message: l10n.posTransferClaimedPendingMessage,
          tone: FeedbackTone.info,
        );
      }
    } on ApiException catch (e) {
      // Most likely claimed by another device first — refresh the truth.
      unawaited(_refreshTransferInbox());
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: e.message,
        tone: FeedbackTone.warning,
      );
    } catch (_) {
      _showPopupMessage(
        title: l10n.posTransferFailedTitle,
        message: l10n.posTransferFailedTitle,
        tone: FeedbackTone.warning,
      );
    }
  }

  /// Rebuilds CartItems from a claimed transfer's server snapshot. Catalog
  /// products supply identity/image/add-on groups; the snapshot price seeds
  /// each line, but a later catalog emission re-prices open lines from the
  /// live menu (_applyDeliveryPricing) — same-branch devices share one
  /// catalog, so this only surfaces when a price changed mid-transfer.
  /// Returns the controller's verdict: false means the cart was NOT replaced
  /// (tender running / split legs recorded) and the caller must not report
  /// success.
  bool _hydrateFromTransfer(Map<String, dynamic> order) {
    final items = <CartItem>[];
    for (final raw
        in ((order['items'] as List?) ?? const []).whereType<Map>()) {
      final m = raw.cast<String, dynamic>();
      final productId = (m['product_id'] as num?)?.toInt();

      final modifiers = <CartItemModifier>[];
      for (final a in ((m['addons'] as List?) ?? const []).whereType<Map>()) {
        final am = a.cast<String, dynamic>();
        modifiers.add(
          CartItemModifier(
            id: '${(am['add_on_id'] as num?)?.toInt() ?? ''}',
            group: '',
            label: (am['add_on_name'] ?? '').toString(),
            price: ((am['price_delta_baisas'] as num?)?.toInt() ?? 0) / 1000.0,
          ),
        );
      }

      final unitPrice =
          ((m['unit_price_baisas'] as num?)?.toInt() ?? 0) / 1000.0;
      final addonTotal = modifiers.fold(0.0, (sum, mo) => sum + mo.price);
      final basePrice = double.parse(
        (unitPrice - addonTotal).toStringAsFixed(3),
      );

      final catalog = productId != null
          ? controller.productById(productId)
          : null;
      items.add(
        CartItem(
          product: Product(
            id: '${productId ?? ''}',
            name: catalog?.name ?? (m['product_name'] ?? '').toString(),
            nameAr: catalog?.nameAr ?? '',
            category: catalog?.category ?? '',
            categoryId: catalog?.categoryId,
            price: basePrice,
            imageAsset: catalog?.imageAsset,
            addonGroupIds: catalog?.addonGroupIds ?? const <int>[],
          ),
          qty: ((m['qty'] as num?) ?? 1).round(),
          modifiers: modifiers,
          notes: (m['notes'] ?? '').toString(),
        ),
      );
    }

    return controller.receiveTransferredOrder(
      orderUuid: (order['uuid'] ?? '').toString(),
      orderType: OrderTypeLabel.fromStorage(
        (order['order_type'] ?? '').toString(),
      ),
      items: items,
    );
  }

  /// Loads a claimed-but-parked transfer (see [_receiveTransfer]) once the
  /// console is idle again. Runs on the inbox poll tick; only fills an EMPTY
  /// cart so it never clobbers an order the cashier started meanwhile.
  void _retryPendingClaimedTransfer() {
    final order = _claimedTransferPendingLoad;
    if (order == null || !mounted) return;
    if (controller.isProcessingPayment ||
        controller.hasRecordedSplitPayments ||
        controller.cart.isNotEmpty) {
      return;
    }
    if (!_hydrateFromTransfer(order)) return;
    _claimedTransferPendingLoad = null;
    setState(() {
      _cashTenderInput = '';
      _customerNumberController.clear();
      _vehiclePlateController.clear();
    });
    _showPopupMessage(
      title: L10n.of(context).posTransferReceivedTitle,
      message: (order['order_reference'] ?? '').toString(),
      tone: FeedbackTone.success,
    );
  }

  /// Mirror a full order cancellation to pos_api via the durable outbox (an
  /// order.void). Fire-and-forget: the local cancel already succeeded, and the
  /// outbox persists + retries the void independently of the network.
  void _handleOrderVoided(
    String orderUuid, {
    int? orderNumber,
    String? reason,
    int? voidReasonId,
  }) {
    final staffId = ref.read(sessionServiceProvider).staff?.id;
    unawaited(
      _orderPreparations.run(
        () => ref
            .read(orderSyncRepositoryProvider)
            .resolveTableBillUuid(orderUuid)
            .then(
              (billUuid) => ref
                  .read(orderSyncRepositoryProvider)
                  .enqueueVoid(
                    billUuid,
                    orderNumber: orderNumber,
                    reason: reason,
                    voidReasonId: voidReasonId,
                    staffId: staffId,
                    authorizedBy: 'Manager',
                  ),
            )
            .catchError((_) {}),
      ),
    );
  }

  /// Phase B — manager comp: write off one line or the whole order under a
  /// company comp reason (Additions §1.2). Manager fingerprint approval is
  /// ALWAYS required; the amount is derived (the line's discounted total, or
  /// the whole discounted subtotal) and validated against the reason's cap.
  Future<void> _openCompDialog({
    DineInDetail? serverDetail,
    void Function(Map<String, dynamic>)? picked,
  }) async {
    if (serverDetail == null && (_liveTable || _workspace?.dineIn == true)) {
      await _adjustLiveBill('comp');
      return;
    }
    final serverBill = serverDetail?.bill;
    final serverLines = serverBill == null
        ? <Map<String, dynamic>>[]
        : (serverBill['items'] as List)
              .map(tableMap)
              .where(
                (line) => (line['qty'] as num) > 0 && line['status'] != 'void',
              )
              .toList();
    final cart = serverBill == null
        ? controller.cart
        : serverLines.map(WorkspaceCartItem.new).toList();
    final existing = serverBill?['adjustment_state'] is Map
        ? tableMap(tableMap(serverBill!['adjustment_state'])['comp'] ?? {})
        : <String, dynamic>{};
    final net = serverBill == null
        ? controller.subtotal
        : ((serverBill['grand_total_baisas'] as int) -
                  (serverBill['tax_total_baisas'] as int)) /
              1000;
    var replaceExisting = false;
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    if (cart.isEmpty) {
      _showPopupMessage(
        title: l10n.posCompNothingTitle,
        message: l10n.posCompNothingMessage,
        tone: FeedbackTone.info,
      );
      return;
    }

    // An existing comp can be removed without re-authorization (it only
    // RESTORES money owed); applying one always needs the manager.
    if (serverBill == null
        ? controller.appliedComp != null
        : existing.isNotEmpty) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.posCompAppliedTitle),
          content: Text(
            l10n.posCompExistingMessage(
              serverBill == null
                  ? controller.appliedComp!.reasonName
                  : (existing['reason_name'] ?? '').toString(),
              SunmiReceiptService.money(
                serverBill == null
                    ? controller.compAmount
                    : (serverBill['comp_total_baisas'] as int) / 1000,
              ),
            ),
          ),
          actions: [
            if (serverBill != null)
              TextButton(
                onPressed: () {
                  replaceExisting = true;
                  Navigator.pop(ctx, true);
                },
                child: Text(isAr ? 'استبدال' : 'Replace'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.posCompRemoveButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.posCompKeepButton),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (keep == false) {
        if (serverBill != null) {
          picked?.call({'kind': 'comp', 'mode': 'clear'});
          return;
        }
        controller.removeComp();
        _showPopupMessage(
          title: l10n.posCompRemovedTitle,
          message: l10n.posCompRemovedMessage,
          tone: FeedbackTone.info,
        );
      }
      if (!replaceExisting) return;
    }

    // P-F1 — fingerprint with manager-PIN fallback.
    final authorized = await _authorizeManager(
      subtitle: l10n.posCompManagerApprovalMessage,
    );
    if (!mounted) return;
    if (!authorized) {
      _showPopupMessage(
        title: l10n.posCompLockedTitle,
        message: l10n.posManagerFingerprintNotApprovedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final selection = MachineCompSelectionDraft();
    CompReasonRef? reason;
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double amountFor(int? index, int? qty) {
            if (index == null) return net;
            final item = cart[index];
            final amountBaisas = machineLineCompPreviewBaisas(
              lineTotalBaisas: serverBill == null
                  ? (item.unitPrice * 1000).round() * item.qty
                  : serverLines[index]['line_total_baisas'] as int,
              lineDiscountBaisas: serverBill == null
                  ? (controller.lineDiscountFor(item).amount * 1000).round()
                  : serverLines[index]['line_discount_baisas'] as int? ?? 0,
              lineQty: item.qty,
              compQty: qty,
            );
            return pricing.baisasToOmr(
              serverBill == null
                  ? amountBaisas.clamp(0, pricing.omrToBaisas(net))
                  : amountBaisas,
            );
          }

          final amount = amountFor(selection.lineIndex, selection.qty);
          final cap = reason?.maxAmount;
          final overCap = cap != null && amount > cap + 0.0005;

          return AlertDialog(
            title: Text(l10n.posCompDialogTitle),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.posCompWhatLabel),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    key: const ValueKey('comp-target-dropdown'),
                    value: selection.lineIndex ?? -1,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: -1,
                        child: Text(l10n.posCompWholeOrderOption),
                      ),
                      for (var i = 0; i < cart.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            '${cart[i].product.displayName(isAr)} ×${cart[i].qty}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() {
                      selection.selectTarget(
                        (v == null || v == -1) ? null : v,
                        cart,
                      );
                    }),
                  ),
                  if (selection.lineIndex != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(l10n.restockQtyHint),
                        const SizedBox(width: 12),
                        IconButton(
                          key: const ValueKey('comp-qty-decrement'),
                          onPressed: selection.qty == 1
                              ? null
                              : () => setDialogState(
                                  () => selection.changeQty(-1, cart),
                                ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '${selection.qty} / ${cart[selection.lineIndex!].qty}',
                          key: const ValueKey('comp-qty-value'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          key: const ValueKey('comp-qty-increment'),
                          onPressed:
                              selection.qty == cart[selection.lineIndex!].qty
                              ? null
                              : () => setDialogState(
                                  () => selection.changeQty(1, cart),
                                ),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(l10n.posCompReasonLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in controller.compReasons)
                        ChoiceChip(
                          label: Text(
                            _reasonDisplayName(r.name, r.nameAr, isAr),
                          ),
                          selected: reason?.id == r.id,
                          onSelected: (selected) => setDialogState(
                            () => reason = selected ? r : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.posCompAmountLabel(SunmiReceiptService.money(amount)),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (overCap)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.posCompExceedsCapMessage(
                          _reasonDisplayName(
                            reason!.name,
                            reason!.nameAr,
                            isAr,
                          ),
                          SunmiReceiptService.money(cap),
                        ),
                        style: const TextStyle(color: Color(0xFFB84524)),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: (reason == null || overCap)
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(l10n.posCompApplyButton),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || applied != true || reason == null) return;

    if (serverBill != null) {
      picked?.call({
        'kind': 'comp',
        'mode': 'apply',
        'comp_reason_id': reason!.id,
        'authorized_by': 'Manager',
        'target': selection.lineIndex == null
            ? 'bill'
            : {
                'order_item_id': serverLines[selection.lineIndex!]['id'],
                'qty':
                    selection.normalizedQty(cart) ??
                    cart[selection.lineIndex!].qty,
              },
      });
      return;
    }
    controller.applyComp(
      AppliedComp(
        reasonId: reason!.id,
        reasonName: reason!.name,
        lineIndex: selection.lineIndex,
        qty: selection.normalizedQty(controller.cart),
      ),
    );
    _showPopupMessage(
      title: l10n.posCompAppliedTitle,
      message: l10n.posCompAppliedMessage(
        _reasonDisplayName(reason!.name, reason!.nameAr, isAr),
        SunmiReceiptService.money(controller.compAmount),
      ),
      tone: FeedbackTone.success,
    );
  }

  void _handleCompClearedAfterCartEdit() {
    // Defer so an edit's own immediate success popup (notably Add Bundle)
    // cannot overwrite the safety notice before the operator sees it.
    scheduleMicrotask(() {
      if (!mounted) return;
      final l10n = L10n.of(context);
      _showPopupMessage(
        title: l10n.posCompRemovedTitle,
        message: l10n.posCompRemovedMessage,
        tone: FeedbackTone.info,
      );
    });
  }

  /// Captured for [dispose] — Riverpod forbids `ref.read` once the element
  /// is unmounting, so the teardown target is grabbed while `ref` is live.
  AudienceService? _audienceService;

  /// Marketing #46 — the EFFECTIVE audience-measurement gate: the
  /// server-driven consent (admin-set per merchant, from /device/config meta)
  /// SUPERSEDES the device-local Settings toggle; the local switch only
  /// matters while the server hasn't stated a policy (older pos_api).
  /// start()/stop() are both idempotent, so re-applying is always safe.
  bool _audienceHostActive = true;
  bool? _audienceDesired;
  Future<void> _audienceTransition = Future.value();

  void _applyAudienceGate() {
    if (!mounted || !_audienceHostActive) return;
    final server = ref.read(sessionServiceProvider).serverAudienceMeasurement;
    final consent =
        server ?? ref.read(settingsControllerProvider).audienceMeasurement;
    final operating =
        _workspace != null ||
        _qrOrdersListOpen ||
        _normalQrCheckoutOpen ||
        _showPaymentPage ||
        controller.cart.isNotEmpty ||
        controller.isProcessingPayment;
    final enabled = consent && !operating;
    if (_audienceDesired == enabled) return;
    _audienceDesired = enabled;
    final audience = ref.read(audienceServiceProvider);
    // Serialize camera transitions so a slow start cannot reopen it after a
    // checkout pause; queued transitions always use the latest desired state.
    _audienceTransition = _audienceTransition
        .then((_) async {
          if (!mounted) return;
          if (_audienceDesired == true) {
            await audience.start();
          } else {
            await audience.stop();
          }
        })
        .catchError((Object error) {
          debugPrint('Audience gate: $error');
        });
  }

  @override
  void deactivate() {
    _audienceHostActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _audienceHostActive = true;
    _applyAudienceGate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audienceService = ref.read(audienceServiceProvider);
  }

  @override
  void dispose() {
    _liveEditor?.removeListener(_liveEditorChanged);
    _liveEditor?.dispose();
    _tableCheckout?.dispose();
    controller.removeListener(_onTableCartChanged);
    if (_workspace case final workspace?) {
      workspace.removeListener(_workspaceChanged);
      workspace.dispose();
      unawaited(PresentationService.instance.clearWorkspaceBill(workspace));
    }
    leaveStaffAttention(_attentionLease);
    if (_tableKitchen?.coordinator.paymentAcknowledged == _tablePaymentAck) {
      _tableKitchen!.coordinator.paymentAcknowledged = null;
    }
    _tableKitchen?.detach();
    unawaited(_tableKitchenChanges?.cancel());
    _tableReconciliation?.dispose();
    unawaited(_tableVerdicts?.cancel());
    unawaited(_tablePendingChanges?.cancel());
    _tableSearch.dispose();
    _qrRoundAutoPrintController.stop();
    _tableShadow?.setFloorPlanVisible(false);
    _tableShadow?.localTables = null;
    _clockTimer?.cancel();
    _configPollTimer?.cancel();
    _transferPollTimer?.cancel();
    _popupTimer?.cancel();
    _clockNow.dispose();
    _currentOrderScrollController.dispose();
    _customerNumberController.dispose();
    _vehiclePlateController.dispose();
    unawaited(controller.shutdown());
    controller.dispose();
    _catalogSub?.close();
    _connectivitySub?.close();
    // Phase 1A — release the audience camera when leaving the POS.
    unawaited(_audienceService?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qrRoundPrintPollingUnavailable = ref.watch(
      qrRoundPrintPollingUnavailableProvider,
    );
    _tableShadowMode = ref.watch(tableSessionsModeProvider);
    final tableDegraded = _tableShadowMode == 'live'
        ? ref.watch(degradedStateProvider)
        : const TableDegradedState();
    if (_tableShadowMode == 'live') {
      ref.listen(degradedStateProvider, (_, _) => _scheduleTableSearch());
    }
    _remoteTables = _tableShadowMode == 'off'
        ? const RemoteTableSnapshot()
        : ref.watch(remoteBoardProvider).asData?.value ??
              const RemoteTableSnapshot();
    if (_tableShadowMode == 'live') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_retireClosedTableCopies());
      });
    }
    if (_tableShadowMode != 'off') {
      if (_liveTable &&
          _workspace == null &&
          tableBillNeedsSheet(_tableShadowMode, _cartBill)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_adoptOpenStaffBill().catchError((Object _) {}));
        });
      }
      _tableShadow = ref.read(tableShadowRepositoryProvider);
      _tableShadow!.localTables = () => [
        for (final table in controller.diningTableDefinitions)
          LocalTableShadowView(
            tableId: table.id,
            status:
                controller.diningSessionFor(table.id)?.status.storageValue ??
                'available',
            reference: controller.diningSessionFor(table.id)?.orderReference,
          ),
      ];
    }
    final arabic = ref.watch(settingsControllerProvider).language == 'ar';

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        _tableShadow?.setFloorPlanVisible(
          _tableShadowMode != 'off' &&
              _showDineInFloorPlan &&
              !_showPaymentPage &&
              (ModalRoute.of(context)?.isCurrent ?? true),
        );
        return _buildPosShell(
          surface: _buildTableAwareSurface(
            _designHeight - _topBarHeight - _bottomBarHeight - (_panelGap * 2),
            tableDegraded,
          ),
          overlays: [
            if (_savedTablePaymentPending)
              PositionedDirectional(
                bottom: 12,
                start: 12,
                end: 12,
                child: Material(
                  color: const Color(0xFFFFE6A6),
                  child: ListTile(
                    title: Text(
                      _savedTablePaymentNotice != null
                          ? checkoutText(context, _savedTablePaymentNotice!)
                          : arabic
                          ? 'الدفع محفوظ ولم تتأكد نتيجته. لا تأخذ دفعة أخرى.'
                          : 'Payment is saved; its result is not confirmed. Do not take payment again.',
                    ),
                    trailing: TextButton(
                      key: const ValueKey('table-check-payment-result'),
                      onPressed: _checkingTablePayment
                          ? null
                          : () async {
                              if (_savedTablePaymentNotice != null) {
                                await _launchQrCheckout(null);
                              } else {
                                await _retireClosedTableCopies(force: true);
                              }
                            },
                      child: Text(
                        _savedTablePaymentNotice != null
                            ? checkoutText(context, 'manager')
                            : arabic
                            ? 'تحقق من نتيجة الدفع'
                            : 'Check payment result',
                      ),
                    ),
                  ),
                ),
              ),
            PositionedDirectional(
              top: 12,
              start: 12,
              end: 12,
              child: Align(
                alignment: Alignment.topCenter,
                child: QrRoundPrintStatusIndicator(
                  unavailable: qrRoundPrintPollingUnavailable,
                  arabic: arabic,
                ),
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
        );
      },
    );
  }

  /// The original till shell is shared by local and server-owned orders.
  Widget _buildPosShell({
    required Widget surface,
    List<Widget> overlays = const [],
  }) => Scaffold(
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
              final outerPadding = constraints.maxWidth < 1400 ? 10.0 : 16.0;
              final availableWidth = constraints.maxWidth - (outerPadding * 2);
              final availableHeight =
                  constraints.maxHeight - (outerPadding * 2);
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
                      child: surface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        ...overlays,
      ],
    ),
  );

  bool get _showDineInFloorPlan =>
      _workspace == null &&
      controller.selectedOrderType == OrderType.dineIn &&
      !controller.isEditingDiningTable;

  bool get _isEditingDiningTable => controller.isEditingDiningTable;

  QrCheckoutController? _tableCheckout;
  Future<Map<String, dynamic>> _prepareLiveTableTender(
    double? cashTendered,
  ) async {
    final identity = _tablePayContext;
    final editor = await _ensureLiveEditor();
    if (editor?.detail?.billUuid == null ||
        !editor!.canPay ||
        _hasTableUnsent ||
        controller.splitCount != 1) {
      throw StateError(
        'Open the canonical bill and finish pending items before payment.',
      );
    }
    final checkout = await _newQrCheckout();
    _tableCheckout?.dispose();
    _tableCheckout = checkout;
    await checkout.open(editor.detail!.billUuid);
    if (!mounted || identity != _tablePayContext || !checkout.ready) {
      if (checkout.ready) await checkout.cancel();
      throw StateError('Check payment result before another payment.');
    }
    if (controller.selectedPaymentMethod == 'Cash' &&
        cashTendered != null &&
        (cashTendered * 1000).round() < checkout.total) {
      await checkout.cancel();
      throw StateError(
        'The bill changed. Review the amount before taking cash.',
      );
    }
    final snapshot = await checkout.beginTableTender();
    if (snapshot == null) {
      throw StateError('Check payment result before another payment.');
    }
    return Map<String, dynamic>.from(snapshot.order);
  }

  bool _checkingTablePayment = false;
  bool _savedTablePaymentPending = false;
  String? _savedTablePaymentNotice;
  DateTime? _lastTablePaymentCheck;

  Future<void> _checkSavedTablePayment({bool force = false}) async {
    if (!mounted ||
        _checkingTablePayment ||
        controller.isLoadingStorage ||
        controller.isProcessingPayment ||
        _normalQrCheckoutOpen ||
        ref.read(tableSessionsModeProvider) != 'live') {
      return;
    }
    if (!force &&
        _lastTablePaymentCheck != null &&
        DateTime.now().difference(_lastTablePaymentCheck!).inSeconds < 10) {
      return;
    }
    if ((debugOrderStorageOverride ?? LocalOrderStorageService.instance)
        is! LocalOrderStorageService) {
      return;
    }
    _checkingTablePayment = true;
    if (_savedTablePaymentPending) setState(() {});
    _lastTablePaymentCheck = DateTime.now();
    var pending = false;
    String? notice;
    try {
      await _ensureTableKitchen();
      final checkout = await _newQrCheckout();
      try {
        final saved = await checkout.store.active();
        if (saved == null ||
            saved.paymentContract == 'qr' ||
            !const {'pending', 'refused', 'uncertain'}.contains(saved.state) ||
            saved.event == null) {
          return;
        }
        final sessions = await _tableKitchen!.coordinator.loadSessions();
        if (saved.paymentContract != 'table' &&
            !sessions.any((s) => s.serverOrderUuid == saved.orderUuid)) {
          return;
        }
        pending = true;
        if (saved.state == 'pending') {
          await ref
              .read(orderSyncRepositoryProvider)
              .recoverTablePayment(saved.orderUuid, saved.id);
        }
        final remaining = await checkout.store.active();
        pending = remaining?.id == saved.id;
        if (pending &&
            const {'refused', 'uncertain'}.contains(remaining!.state)) {
          notice =
              remaining.state == 'refused' &&
                  !remaining.captures.any(
                    (c) => const {'card', 'bank_pos'}.contains(c['method']),
                  )
              ? 'return_cash'
              : 'recovery';
        }
      } finally {
        checkout.dispose();
      }
    } catch (_) {
      // Retain original payment and expose the same safe retry. Never collect
      // tender, invent a receipt, or clear missing server proof.
      pending = true;
    } finally {
      _checkingTablePayment = false;
      if (mounted && (pending || _savedTablePaymentPending)) {
        setState(() {
          _savedTablePaymentPending = pending;
          _savedTablePaymentNotice = notice;
        });
      }
    }
  }

  Future<void> _tablePaymentAck(
    Map<String, dynamic> event,
    Map<String, dynamic> ack,
  ) async {
    final existing = _tableCheckout;
    final checkout = existing?.attempt?.id == event['client_event_id']
        ? existing!
        : await _newQrCheckout();
    try {
      await checkout.acceptTablePayAck(event, ack);
    } finally {
      if (!identical(checkout, existing)) checkout.dispose();
    }
  }

  DineInController? _liveEditor;
  String? _liveEditorKey;
  Future<DineInController?>? _liveEditorLoading;
  WorkspaceBill? get _liveBill {
    final editor = _liveEditor;
    if (!_liveTable ||
        editor?.tableId.toString() != controller.activeDiningTableId ||
        editor?.detail?.bill == null ||
        !const {
          'open',
          'awaiting_payment',
        }.contains(editor!.detail!.bill?['status']) ||
        _liveEditorKey?.endsWith(
              ':${controller.activeDiningTableId}:${controller.currentOrderReference}',
            ) !=
            true) {
      return null;
    }
    final reserved = _tableCheckout?.snapshot;
    return WorkspaceBill(
      reserved?.uuid == editor.detail!.billUuid
          ? {...reserved!.order, 'customer': reserved.customer}
          : editor.detail!.bill!,
    );
  }

  void _liveEditorChanged() {
    if (mounted) setState(() {});
  }

  Future<DineInController?> _ensureLiveEditor() async {
    if (!_liveTable || _workspace != null) return null;
    final pending = _liveEditorLoading;
    if (pending != null) return pending;
    final api = ref.read(apiServiceProvider);
    final session = ref.read(sessionServiceProvider);
    String scope() => quickDeviceScope(
      api.quickOrderBaseUrl,
      session.companyId,
      session.branchId,
      session.kioskId,
    );
    final id = int.tryParse(controller.activeDiningTableId ?? '');
    if (id == null) return null;
    final key = '${scope()}:$id:${controller.currentOrderReference}';
    if (_liveEditorKey == key && _liveEditor != null) return _liveEditor;
    final task = () async {
      final gateway = ApiDineInGateway(
        api,
        scope,
        mutationGuard: controller.assertNoPendingCombine,
      );
      final editor = DineInController(
        gateway,
        await SqliteDineInStore.open(gateway.scope),
        id,
        staffId: session.staff?.id,
      );
      await editor.start();
      if (!mounted ||
          !_liveTable ||
          controller.activeDiningTableId != '$id' ||
          key != '${scope()}:$id:${controller.currentOrderReference}') {
        editor.dispose();
        return null;
      }
      _liveEditor?.removeListener(_liveEditorChanged);
      _liveEditor?.dispose();
      _liveEditorKey = key;
      _liveEditor = editor..addListener(_liveEditorChanged);
      _liveEditorChanged();
      return editor;
    }();
    _liveEditorLoading = task;
    try {
      return await task;
    } finally {
      _liveEditorLoading = null;
    }
  }

  Future<Map<String, dynamic>?> _pickTableAdjustment(
    DineInDetail detail,
    String kind,
  ) async {
    Map<String, dynamic>? picked;
    if (kind == 'loyalty') {
      return pickTableLoyalty(
        context,
        bill: detail.bill!,
        rules: [
          for (final rule in controller.loyaltyRules)
            {
              'id': rule.id,
              'name': rule.name,
              'type': rule.type,
              'config': rule.config,
              'active': rule.isActive,
            },
        ],
        customer: ref.read(apiServiceProvider).tableLoyaltyCustomer,
        // The registered fingerprint stores only a boolean, never a staff id.
        // Always fall through to the existing PIN control for this flow.
        approve: () => showDialog<LoyaltyApprover>(
          context: context,
          builder: (_) => _ManagerPinDialog(
            api: ref.read(apiServiceProvider),
            identityRequired: true,
          ),
        ),
      );
    }
    if (kind == 'discount') {
      await _openDiscountDialog(
        serverDetail: detail,
        picked: (value) => picked = value,
      );
    } else if (kind == 'comp') {
      await _openCompDialog(
        serverDetail: detail,
        picked: (value) => picked = value,
      );
    } else {
      final l10n = L10n.of(context);
      final current = detail.bill?['customer'] is Map
          ? tableMap(detail.bill!['customer'])
          : null;
      if (current != null) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.posCustomerAttachedTitle),
            content: Text(
              '${current['name'] ?? ''}\n${current['phone'] ?? ''}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'detach'),
                child: Text(dineInText(_arabicTable, 'detach_customer')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: Text(dineInText(_arabicTable, 'replace')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        );
        if (!mounted || action == null) return null;
        if (action == 'detach') return {'kind': 'customer', 'mode': 'detach'};
      }
      final customer = await showDialog<CustomerSearchResult>(
        context: context,
        builder: (_) => _CustomerSearchDialog(
          search: ref.read(apiServiceProvider).searchCustomers,
        ),
      );
      if (customer != null) {
        picked = {
          'kind': 'customer',
          'mode': 'attach',
          'customer_id': customer.id,
        };
      }
    }
    return picked;
  }

  bool get _arabicTable => Localizations.localeOf(context).languageCode == 'ar';

  Future<void> _adjustLiveBill(String kind) async {
    if (_workspace?.dineIn == true) {
      final controls = _workspace?.cartControls;
      await (switch (kind) {
        'discount' => controls?.discount,
        'comp' => controls?.comp,
        'loyalty' => controls?.loyalty,
        _ => controls?.customer,
      })?.call();
      return;
    }
    if (!_liveTable) return;
    try {
      final editor = await _ensureLiveEditor();
      await _refreshTableSentState();
      if (!mounted || editor == null) return;
      await editor.refresh();
      if (_hasTableUnsent ||
          _pendingTableIds.contains(controller.activeDiningTableId)) {
        _showPopupMessage(
          title: dineInText(_arabicTable, 'title'),
          message: dineInText(_arabicTable, 'adjustment_unsent'),
          tone: FeedbackTone.info,
        );
        return;
      }
      await editor.adjust((detail) => _pickTableAdjustment(detail, kind));
      _showTableAdjustmentNotice(editor);
    } catch (_) {
      if (mounted) _showTableActionFailure();
    }
  }

  void _showTableAdjustmentNotice(DineInController editor) {
    if (mounted && editor.notice != null) {
      _showPopupMessage(
        title: dineInText(_arabicTable, 'title'),
        message: dineInText(_arabicTable, editor.notice!),
        tone: FeedbackTone.info,
      );
    }
  }

  Future<void> _retryTableAdjustment(DineInController editor) async {
    await editor.retry();
    _showTableAdjustmentNotice(editor);
  }

  Widget _billAdjustmentContext(
    WorkspaceBill bill, {
    bool showCustomer = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showCustomer && bill.customer != null)
        Chip(
          key: const ValueKey('table-bill-customer'),
          avatar: const Icon(Icons.person_outline),
          label: Text(
            '${bill.customer!['name'] ?? ''} · ${bill.customer!['phone'] ?? ''}',
          ),
        ),
      if (bill.adjustmentState['loyalty'] case final Map reward)
        Text(
          '${dineInText(_arabicTable, 'loyalty')} ${reward['name'] ?? ''}: −${((reward['amount_baisas'] as num? ?? 0) / 1000).toStringAsFixed(3)} OMR',
          key: const ValueKey('table-loyalty-line'),
        ),
      if (bill.adjustmentStale)
        Text(
          dineInText(_arabicTable, 'adjustment_stale'),
          key: const ValueKey('table-adjustment-stale'),
        ),
    ],
  );

  Widget _tableAdjustmentControls({
    WorkspaceCartControls? workspaceControls,
    bool compact = false,
  }) {
    final editor = _liveEditor;
    final enabled =
        workspaceControls == null &&
        editor?.canAdjust == true &&
        !_hasTableUnsent &&
        !_pendingTableIds.contains(controller.activeDiningTableId);
    final blocked = workspaceControls == null
        ? (_hasTableUnsent
              ? 'adjustment_unsent'
              : editor?.adjustmentBlocked ??
                    (editor == null ? 'refresh' : null))
        : workspaceControls.adjustmentBlocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final kind in ['discount', 'comp', 'customer', 'loyalty'])
              TextButton(
                key: ValueKey('table-adjust-$kind'),
                style: compact
                    ? TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      )
                    : null,
                onPressed: workspaceControls != null
                    ? switch (kind) {
                        'discount' => workspaceControls.discount,
                        'comp' => workspaceControls.comp,
                        'loyalty' => workspaceControls.loyalty,
                        _ => workspaceControls.customer,
                      }
                    : enabled &&
                          (kind != 'loyalty' ||
                              editor?.detail?.bill?['customer'] is Map)
                    ? () => _adjustLiveBill(kind)
                    : null,
                child: Text(dineInText(_arabicTable, kind)),
              ),
            if (workspaceControls == null &&
                editor?.pending?.isAdjustment == true)
              TextButton(
                key: const ValueKey('table-adjust-retry'),
                onPressed: editor!.busy
                    ? null
                    : () => _retryTableAdjustment(editor),
                child: Text(dineInText(_arabicTable, 'retry_adjustment')),
              ),
            if (workspaceControls == null &&
                editor?.canDiscardAdjustment == true)
              TextButton(
                key: const ValueKey('table-adjust-discard'),
                onPressed: () => _discardLiveAdjustment(editor!),
                child: Text(dineInText(_arabicTable, 'discard_adjustment')),
              ),
          ],
        ),
        if (blocked != null && !compact)
          Text(dineInText(_arabicTable, blocked)),
        if (blocked != null && compact)
          Tooltip(
            message: dineInText(_arabicTable, blocked),
            child: TextButton(
              onPressed: () => _showPopupMessage(
                title: dineInText(_arabicTable, 'title'),
                message: dineInText(_arabicTable, blocked),
                tone: FeedbackTone.info,
              ),
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _arabicTable ? 'لماذا غير متاح؟' : 'Why unavailable?',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _discardLiveAdjustment(DineInController editor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(dineInText(_arabicTable, 'discard_adjustment')),
        content: Text(dineInText(_arabicTable, 'discard_adjustment_explain')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(_arabicTable ? 'رجوع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(dineInText(_arabicTable, 'discard_adjustment')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await editor.discardPendingAdjustment(
        () => _authorizeManager(
          subtitle: dineInText(_arabicTable, 'discard_adjustment'),
        ),
      );
      _showTableAdjustmentNotice(editor);
    }
  }

  bool get _liveTable =>
      ref.read(tableSessionsModeProvider) == 'live' &&
      controller.selectedOrderType == OrderType.dineIn &&
      controller.activeDiningTableId != null;

  Widget _buildTableAwareSurface(
    double contentHeight,
    TableDegradedState state,
  ) {
    Widget surface(double height) => _showPaymentPage
        ? _buildPaymentPageSurface()
        : _showDineInFloorPlan
        ? _buildDineInFloorPlanSurface(height)
        : _buildCatalogSurface(height);
    if (!state.hasWarning || controller.selectedOrderType != OrderType.dineIn) {
      return surface(contentHeight);
    }
    return Column(
      children: [
        TableDegradedBanner(mode: _tableShadowMode, state: state),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => surface(
              constraints.maxHeight -
                  _topBarHeight -
                  _bottomBarHeight -
                  (_panelGap * 2),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _enterLiveTables() async {
    await _tableControllerReady.future;
    if (!mounted || ref.read(tableSessionsModeProvider) != 'live') return;
    await _ensureTableKitchen();
    if (!mounted || ref.read(tableSessionsModeProvider) != 'live') return;
    final scope = _tableReplayScope();
    final skipped = await _tableModeTransition!.enterLive();
    if (mounted &&
        scope != null &&
        _tableReplayScope() == scope &&
        ref.read(tableSessionsModeProvider) == 'live' &&
        skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(l10nProvider).tableReplayUnverified(skipped.length),
          ),
        ),
      );
    }
  }

  String? _tableReplayScope() {
    if (!mounted) return null;
    final session = ref.read(sessionServiceProvider);
    if (session.deviceToken?.isNotEmpty != true ||
        session.companyId == null ||
        session.branchId == null ||
        session.kioskId?.isNotEmpty != true) {
      return null;
    }
    final base = ref.read(settingsServiceProvider).effectiveBaseUrl;
    return '$base|${session.companyId}|${session.branchId}|${session.kioskId}';
  }

  Future<TableReplayConfiguration?> _loadTableReplayConfiguration() async {
    final scope = _tableReplayScope();
    if (scope == null) return null;
    final session = ref.read(sessionServiceProvider).snapshot();
    final db = ref.read(appDatabaseProvider);
    final configuration = await TableReplayConfiguration.read(
      db,
      scope: scope,
      companyId: session.companyId,
      branchId: session.branchId,
    );
    return _tableReplayScope() == scope ? configuration : null;
  }

  void _showTableActionFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(l10nProvider).tableActionFailed)),
    );
  }

  Future<void> _ensureTableKitchen() async {
    if (_tableKitchen != null) return;
    if (_tableKitchenInit != null) return _tableKitchenInit;
    final operation = () async {
      final coordinator = ref.read(tableSyncCoordinatorProvider);
      await coordinator.hydrate();
      if (!mounted) return;
      final bridge = TableKitchenBridge(
        controller: controller,
        coordinator: coordinator,
        preferences: ref.read(sharedPreferencesProvider),
        printer: SunmiReceiptService.printKitchenTicket,
        l10n: () => ref.read(l10nProvider),
        onPrintFailure: () => _handlePrintFailed('kitchen'),
        verifySend: (session) => _verifyLocalTableBill(source: session),
      );
      coordinator.paymentContext = (snapshot) =>
          _tablePaymentContexts.remove(snapshot.serverOrderUuid)?.future ??
          Future.value(const TablePaymentContext());
      _tableKitchen = bridge..attach();
      _tablePendingChanges = ref
          .read(orderSyncRepositoryProvider)
          .watchPending()
          .map((rows) {
            final ids = <String>{};
            for (final row in rows) {
              final events = (jsonDecode(row.eventsJson) as List)
                  .whereType<Map>();
              for (final event in events) {
                final payload = event['payload'] as Map? ?? {};
                if ((event['event_type']?.toString() ?? '').startsWith(
                      'table.session.',
                    ) &&
                    payload['table_id'] != null) {
                  ids.add(payload['table_id'].toString());
                } else {
                  for (final table in controller.diningTableSessions) {
                    final bill =
                        coordinator
                            .cachedSession(table.tableId)
                            ?.serverOrderUuid ??
                        table.serverOrderUuid;
                    if (bill != null && bill == payload['order_uuid']) {
                      ids.add(table.tableId);
                    }
                  }
                }
              }
            }
            if (mounted) setState(() => _pendingTableIds = ids);
          })
          .listen((_) {});
      coordinator.paymentAcknowledged = _tablePaymentAck;
      _tableModeTransition = TableModeTransition(
        bridge,
        loadConfiguration: _loadTableReplayConfiguration,
      );
      _tableReconciliation = TableReconciliationPresenter(
        show: (rows) async {
          if (!mounted) return false;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => TableReconciliationSheet(rows: rows),
          );
          return true;
        },
        markSeen: coordinator.markVerdictsSeen,
      );
      _tableVerdicts = coordinator.verdicts.listen((rows) {
        for (final row in rows) {
          if (row.eventKind != 'cancel_bill') continue;
          final uuid = row.detail['order_uuid'];
          final waiting = _cancellingWorkspaces[uuid];
          if (waiting == null ||
              !const {'cancelled', 'replayed'}.contains(row.outcome)) {
            continue;
          }
          final api = ref.read(apiServiceProvider),
              session = ref.read(sessionServiceProvider);
          final currentScope = quickDeviceScope(
            api.quickOrderBaseUrl,
            session.companyId,
            session.branchId,
            session.kioskId,
          );
          if (!mounted ||
              waiting.scope != currentScope ||
              waiting.token != api.tokenGetter() ||
              !identical(waiting.workspace, _workspace)) {
            continue;
          }
          if ((waiting.workspace.cartControls?.draftRows ?? []).isNotEmpty ||
              (waiting.workspace.cartControls?.pendingRows ?? []).isNotEmpty) {
            continue;
          }
          _cancellingWorkspaces.remove(uuid);
          // The coordinator has validated this exact cancellation ACK. Leaving
          // only releases the editor; the existing closed-copy proof still
          // owns archival and checks canonical history, pending work and drafts.
          waiting.workspace.onExit();
        }
        unawaited(
          _tableReconciliation!.present(rows).catchError((Object _) {
            if (mounted) _showTableActionFailure();
          }),
        );
      });
      _tableKitchenChanges = coordinator.changes.listen((_) {
        unawaited(
          _ensureLiveEditor()
              .then((editor) => editor?.refresh())
              .catchError((Object _) {}),
        );
        unawaited(_refreshTableSentState().catchError((Object _) {}));
      });
      await _refreshTableSentState();
    }();
    _tableKitchenInit = operation;
    try {
      await operation;
    } finally {
      _tableKitchenInit = null;
    }
  }

  void _onTableCartChanged() {
    if (mounted) _applyAudienceGate();
    _updateTableSearch();
    if (_liveTable) {
      unawaited(
        _ensureLiveEditor()
            .then((editor) => editor?.refresh())
            .catchError((Object _) {}),
      );
      unawaited(_refreshTableSentState().catchError((Object _) {}));
    } else {
      _tableSentRefresh++;
      _tableUnsent = {};
      _tableSentAt = {};
    }
  }

  Future<void> _refreshTableSentState() async {
    final refresh = ++_tableSentRefresh;
    final bridge = _tableKitchen;
    if (!mounted || !_liveTable || bridge == null) return;
    final session = bridge.activeSession();
    if (session == null) return;
    await bridge.coordinator.settled;
    final delta = await bridge.coordinator.delta(session);
    final seat = bridge.coordinator.cachedSession(session.tableId)?.seatingKey;
    final rounds = seat == null
        ? <LocalTableRound>[]
        : await bridge.coordinator.store.readLocalTableRounds(seatingKey: seat);
    if (!mounted ||
        refresh != _tableSentRefresh ||
        controller.activeDiningTableId != session.tableId ||
        controller.currentOrderReference != session.orderReference) {
      return;
    }
    await _proveSentDraft(session.tableId);
    if (!mounted || refresh != _tableSentRefresh) return;
    setState(() {
      _heldTableRounds = rounds.where((round) => round.status == 'held').length;
      _tableUnsent = {
        for (final line in delta)
          tableLineFingerprint(line): line['qty'] as int,
      };
      _tableSentAt = {
        for (final round in rounds)
          if (!{
            'bill_terminal',
            'bill_unpaid',
            'failed',
            'held',
            'rejected',
          }.contains(round.status))
            for (final line in round.lines)
              tableLineFingerprint(line): round.submittedAt.toLocal(),
      };
    });
  }

  Future<void> _sendTableRound() async {
    if (!_liveTable || _tableSendBusy) return;
    setState(() => _tableSendBusy = true);
    try {
      await _ensureTableKitchen();
      final session = _tableKitchen?.activeSession();
      if (session != null) await _tableKitchen!.send(session);
      await _refreshTableSentState();
    } on TableRoundSelectionException catch (error) {
      _showTableSelectionFailure(error);
    } on TableRoundReviewRequired catch (error) {
      _showHeldReviewFailure(error);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).tableActionFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _tableSendBusy = false);
    }
  }

  int _heldTableRounds = 0;

  void _showHeldReviewFailure(TableRoundReviewRequired error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.message(
            arabic: ref.read(settingsControllerProvider).language == 'ar',
          ),
        ),
      ),
    );
  }

  bool _hasHeldLocalTable(String id) => _heldLocalTables[id] == true;

  Future<void> _returnToLocalTableItems(String tableId) async {
    if (!mounted ||
        controller.diningSessionFor(tableId) == null ||
        controller.isProcessingPayment ||
        _showPaymentPage) {
      return;
    }
    final workspace = _workspace;
    if (workspace != null) {
      workspace.returnToLocalCart = true;
      workspace.onExit();
    }
    // Deliberately keep/open the original cart. Leaving a table is a separate
    // action and would auto-send before staff had a chance to correct anything.
    await controller.openDiningTable(tableId);
  }

  Future<void> _correctHeldTableRounds({String? tableId}) async {
    if (ref.read(tableSessionsModeProvider) != 'live' || _tableSendBusy) return;
    await _ensureTableKitchen();
    final bridge = _tableKitchen;
    final id = tableId ?? controller.activeDiningTableId;
    final session = id == controller.activeDiningTableId
        ? bridge?.activeSession()
        : controller.diningSessionFor(id ?? '');
    if (bridge == null || session == null) return;
    final identity = _tablePayContext;
    bool current() {
      final saved = controller.diningSessionFor(session.tableId);
      return mounted &&
          identity == _tablePayContext &&
          saved?.orderReference == session.orderReference &&
          saved?.occupiedAt == session.occupiedAt;
    }

    if ((await bridge.coordinator.heldRounds(session)).isEmpty || !current()) {
      return;
    }
    if (!mounted) return;
    final arabic = ref.read(settingsControllerProvider).language == 'ar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(arabic ? 'تصحيح الجولة المعلّقة؟' : 'Correct held round?'),
        content: Text(
          arabic
              ? 'سيتم رفض الجولة المعلّقة فقط مع الاحتفاظ بالسجل. ستبقى الأصناف في السلة لتصحيحها. قد تكون تذكرة المطبخ قد طُبعت؛ لن تتم إعادة الطباعة تلقائياً.'
              : 'Reject the held round and keep its audit record. Items stay in your cart for correction. A kitchen ticket may already have printed; this action will not print or resend it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(arabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(arabic ? 'رفض وتصحيح' : 'Reject and correct'),
          ),
        ],
      ),
    );
    if (confirmed != true || !current()) return;
    setState(() => _tableSendBusy = true);
    try {
      await controller.assertNoPendingCombine();
      final api = ref.read(apiServiceProvider);
      await bridge.coordinator.rejectHeldRounds(
        session,
        readDetail: () => api.dineInDetail(int.parse(session.tableId)),
        reject: (seat, round) =>
            api.dineInReview(seat, round, staff: true, accept: false),
        isCurrent: current,
      );
      await _refreshTableSentState();
      if (mounted) await _returnToLocalTableItems(session.tableId);
    } catch (_) {
      if (mounted) _showTableActionFailure();
    } finally {
      if (mounted) setState(() => _tableSendBusy = false);
    }
  }

  void _showTableSelectionFailure(TableRoundSelectionException error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.message(
            arabic: ref.read(settingsControllerProvider).language == 'ar',
          ),
        ),
      ),
    );
  }

  Future<bool> _allowTableSelections() async {
    if (!_liveTable) return true;
    await _ensureTableKitchen();
    final bridge = _tableKitchen;
    final session = bridge?.activeSession();
    if (bridge == null || session == null) return false;
    final identity = _tablePayContext;
    try {
      await bridge.validatePending(session);
      return mounted && identity == _tablePayContext;
    } on TableRoundSelectionException catch (error) {
      _showTableSelectionFailure(error);
      return false;
    } on TableRoundReviewRequired catch (error) {
      _showHeldReviewFailure(error);
      return false;
    }
  }

  bool get _hasTableUnsent {
    final session = _tableKitchen?.activeSession();
    return _tableUnsent.values.any((qty) => qty > 0) ||
        (session != null && _tableKitchen!.hasLocalOnlyDelta(session));
  }

  String? get _tableSelectionMessage {
    if (!_liveTable || _tableKitchen == null) return null;
    if (_heldTableRounds > 0) {
      return const TableRoundReviewRequired().message(
        arabic: ref.read(settingsControllerProvider).language == 'ar',
      );
    }
    final lines = buildTableRoundLines(controller.cart)
        .map(
          (line) => <String, dynamic>{
            ...line,
            'qty': _tableUnsent[tableLineFingerprint(line)] ?? 0,
          },
        )
        .toList();
    try {
      _tableKitchen!.validateSelections(lines);
      return null;
    } on TableRoundSelectionException catch (error) {
      return error.message(
        arabic: ref.read(settingsControllerProvider).language == 'ar',
      );
    }
  }

  DateTime? _sentTimeFor(CartItem item) {
    final wire = buildTableRoundLines([item]);
    if (wire.isEmpty) return null;
    final key = tableLineFingerprint(wire.single);
    return (_tableUnsent[key] ?? 0) <= 0 ? _tableSentAt[key] : null;
  }

  Future<bool> _approveSentReduction(CartItem item, int reduction) async {
    if (!_liveTable) return true;
    await _ensureTableKitchen();
    final bridge = _tableKitchen!;
    final session = bridge.activeSession();
    final wire = buildTableRoundLines([item]);
    if (session == null || wire.isEmpty) return true;
    await bridge.coordinator.settled;
    final fingerprint = tableLineFingerprint(wire.single);
    final delta = await bridge.coordinator.delta(session);
    final unsent =
        delta
                .where((l) => tableLineFingerprint(l) == fingerprint)
                .firstOrNull?['qty']
            as int? ??
        0;
    final sentReduction = math.max(0, reduction - math.max(0, unsent)).toInt();
    if (sentReduction == 0) return true;
    if (!mounted) return false;
    final approval = await requestSentLineCancellation(
      context,
      authorizeManager: () =>
          _authorizeManager(subtitle: L10n.of(context).tableCancelSentApproval),
    );
    if (!mounted ||
        approval == null ||
        controller.activeDiningTableId != session.tableId ||
        controller.currentOrderReference != session.orderReference) {
      return false;
    }
    await bridge.coordinator.cancelLine(
      session,
      line: wire.single,
      qty: sentReduction,
      prepared: approval.prepared,
      authorizedBy: 'Manager',
      reason: approval.reason,
    );
    bridge.coordinator.clearApproval = TableVoidApproval(
      authorizedBy: 'Manager',
      reason: approval.reason ?? 'staff_close',
    );
    return true; // Never undo a local edit in response to a business verdict.
  }

  Future<void> _reduceTableItem(CartItem item, {bool remove = false}) async {
    if (_tableSendBusy) return;
    setState(() => _tableSendBusy = true);
    try {
      if (!await _approveSentReduction(item, remove ? item.qty : 1)) return;
      if (!mounted) return;
      if (remove) {
        controller.removeCartItem(item);
      } else {
        controller.decreaseCartItem(item);
      }
      await _refreshTableSentState();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).tableActionFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _tableSendBusy = false);
    }
  }

  Future<bool> _clearSharedTable(
    String tableId, {
    bool emptyOnly = false,
  }) async {
    if (emptyOnly && ref.read(tableSessionsModeProvider) != 'live') {
      return false;
    }
    if (ref.read(tableSessionsModeProvider) == 'live') {
      await _ensureTableKitchen();
      final coordinator = _tableKitchen!.coordinator;
      await coordinator.settled;
      final source = controller.diningSessionFor(tableId);
      final refusal = await _verifyLocalTableBill(source: source);
      if (refusal != null) {
        if (refusal == _closedTableMessage && mounted) {
          if (controller.activeDiningTableId != null) {
            await controller.returnToDiningFloorPlan();
          }
          if (await _retireClosedTableCopies(tableId: tableId, force: true)) {
            return true;
          }
          if (mounted &&
              const {
                'proof',
                'server',
              }.contains(_closedCopyBlockers[tableId])) {
            final ar = Localizations.localeOf(context).languageCode == 'ar';
            final retry = await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: Text(
                  ar
                      ? 'التحقق وأرشفة النسخة المغلقة'
                      : 'Check and archive closed copy',
                ),
                content: Text(
                  ar
                      ? 'دليل الخادم غير مكتمل. يمكن للمشرف إعادة التحقق. لن تتم الأرشفة إلا بعد إثبات إغلاق نفس الفاتورة ورفض الجولات المعلقة. تبقى العناصر غير المرسلة محفوظة. لا تأخذ دفعة أخرى.'
                      : 'Server proof is incomplete. A manager can check again. Archiving requires proof that this same bill is closed and its held rounds were rejected. Unsent items stay saved. Do not take payment again.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text(ar ? 'إلغاء' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(
                      ar ? 'تحقق بموافقة المشرف' : 'Manager check and archive',
                    ),
                  ),
                ],
              ),
            );
            if (retry == true && mounted && await _authorizeManager()) {
              if (await _retireClosedTableCopies(
                tableId: tableId,
                force: true,
                managerApproved: true,
              )) {
                return true;
              }
            }
          }
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(_closedCopyReason(tableId))));
          }
        }
        return false;
      }
      final headId = source?.primaryTableId ?? tableId;
      final session =
          coordinator.cachedSession(headId) ??
          controller.diningSessionFor(headId);
      final rounds = session?.seatingKey == null
          ? <LocalTableRound>[]
          : await coordinator.store.readLocalTableRounds(
              seatingKey: session!.seatingKey,
            );
      if (emptyOnly &&
          (rounds.isNotEmpty ||
              session == null ||
              (session.draft?.items.isNotEmpty ?? false) ||
              (controller.activeDiningTableId == tableId &&
                  controller.cart.isNotEmpty))) {
        return false;
      }
      if (emptyOnly &&
          rounds.isEmpty &&
          session != null &&
          !(session.draft?.items.isNotEmpty ?? false) &&
          !(controller.activeDiningTableId == tableId &&
              controller.cart.isNotEmpty)) {
        try {
          final id = int.tryParse(headId);
          if (id == null) return false;
          final api = ref.read(apiServiceProvider);
          final detail = DineInDetail(await api.dineInDetail(id));
          if (!detail.canClearEmpty) return false;
          if (detail.canClearEmpty) {
            if (!mounted) return false;
            final confirmed =
                await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Clear empty session?'),
                    content: const Text(
                      'Close this empty session and free the table? No order will be cancelled.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Clear session'),
                      ),
                    ],
                  ),
                ) ??
                false;
            if (!mounted || !confirmed) return false;
            await api.dineInClear(id, seatingUuid: detail.seatingUuid!);
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not clear the session. Refresh the table and try again.',
                ),
              ),
            );
          }
          return false;
        }
      }
      if (rounds.isNotEmpty && source?.status != DiningTableStatus.paid) {
        if (!mounted ||
            !await _authorizeManager(
              subtitle: L10n.of(context).tableCancelSentApproval,
            )) {
          return false;
        }
        coordinator.clearApproval = const TableVoidApproval(
          authorizedBy: 'Manager',
          reason: 'staff_close',
        );
      }
    }
    await controller.clearDiningTableById(tableId);
    return true;
  }

  String get _activeDiningTableLabel =>
      controller.activeDiningTableDefinition?.name ?? '';

  bool _hasServerBillFor(String tableId) =>
      _tableShadowMode != 'off' &&
      _remoteTables.tables[int.tryParse(tableId)]?.billOrderUuid != null;

  final Map<String, String> _sentDraftProofs = {};
  final Map<String, bool> _heldLocalTables = {};
  bool _adoptingStaffBill = false;

  DiningTableSession? _tableDraft(String id) =>
      controller.activeDiningTableId == id
      ? _tableKitchen?.activeSession() ?? controller.diningSessionFor(id)
      : controller.diningSessionFor(id);

  String _draftProof(DiningTableSession session) => jsonEncode([
    session.orderReference,
    session.occupiedAt?.toIso8601String(),
    session.draft?.toMap(),
  ]);

  bool _tableDraftBlocks(String id) {
    if (controller.recoveryBlocked || _pendingTableIds.contains(id)) {
      return true;
    }
    final local = _tableDraft(id);
    if (local == null ||
        local.status == DiningTableStatus.paid ||
        !(local.draft?.items.isNotEmpty ?? false)) {
      return false;
    }
    return _sentDraftProofs[id] != _draftProof(local);
  }

  Future<void> _proveSentDraft(String id) async {
    final bridge = _tableKitchen;
    if (bridge == null) return;
    await bridge.coordinator.settled;
    final local = _tableDraft(id);
    if (local == null) return;
    final proof = _draftProof(local);
    final delta = await bridge.coordinator.delta(local);
    final bound = bridge.coordinator.cachedSession(id);
    final rounds = bound?.seatingKey == null
        ? <LocalTableRound>[]
        : await bridge.coordinator.store.readLocalTableRounds(
            seatingKey: bound!.seatingKey,
          );
    final acknowledged =
        rounds.any((r) => r.status == 'appended') &&
        rounds.every(
          (r) =>
              r.status == 'rejected' ||
              (r.status == 'appended' &&
                  r.ackedAt != null &&
                  r.serverRoundId != null &&
                  r.orderUuid == bound?.serverOrderUuid),
        );
    if (!mounted ||
        _tableDraft(id) == null ||
        _draftProof(_tableDraft(id)!) != proof) {
      return;
    }
    _heldLocalTables[id] = rounds.any((r) => r.status == 'held');
    if (acknowledged && delta.isEmpty && !bridge.hasLocalOnlyDelta(local)) {
      _sentDraftProofs[id] = proof;
    } else {
      _sentDraftProofs.remove(id);
    }
  }

  Future<void> _adoptOpenStaffBill() async {
    final id = controller.activeDiningTableId;
    if (_adoptingStaffBill ||
        !mounted ||
        id == null ||
        !_liveTable ||
        _workspace != null ||
        _showPaymentPage ||
        _normalQrCheckoutOpen ||
        controller.isProcessingPayment ||
        _tableSendBusy ||
        !tableBillNeedsSheet(_tableShadowMode, _cartBill)) {
      return;
    }
    _adoptingStaffBill = true;
    try {
      await _ensureTableKitchen();
      await _proveSentDraft(id);
      if (mounted &&
          controller.activeDiningTableId == id &&
          !_tableDraftBlocks(id)) {
        await _openCustomerBill(id);
      }
    } finally {
      _adoptingStaffBill = false;
    }
  }

  Future<void> _openCustomerBill(String tableId, {String? tableLabel}) async {
    final id = int.tryParse(tableId);
    if (!mounted ||
        id == null ||
        _customerBillRouteOpen ||
        _workspace != null) {
      return;
    }
    // A snackbar lives above the local checkout's pointer barriers. It must
    // not open a second money surface or abandon a partially paid local bill.
    if (customerBillEntryBlocked(
      localCheckoutOpen: _showPaymentPage,
      processingPayment: controller.isProcessingPayment,
      charityPrompt: controller.showCharityRoundUpPrompt,
      paymentLaunchOverlay: controller.showPaymentLaunchOverlay,
      recordedSplitWithCart:
          controller.hasRecordedSplitPayments && controller.cart.isNotEmpty,
    )) {
      return;
    }
    await _ensureTableKitchen();
    await _proveSentDraft(tableId);
    if (!mounted || _workspace != null) return;
    final table = controller.diningTableDefinitionById(tableId);
    openServerWorkspace(
      (workspace) => DineInScreen(
        workspace: workspace,
        onCorrectHeldRound: _hasHeldLocalTable(tableId)
            ? () => _correctHeldTableRounds(tableId: tableId)
            : null,
        label: tableLabel ?? table?.name ?? tableId,
        arabic: ref.read(settingsControllerProvider).language == 'ar',
        writesAllowed: ref.read(tableSessionsModeProvider) == 'live',
        localDraftBlocked: _tableDraftBlocks(tableId),
        localDraftBlockedNow: () => _tableDraftBlocks(tableId),
        onEditLocalItems: () => _returnToLocalTableItems(tableId),
        hasHeldLocalRound: () => _hasHeldLocalTable(tableId),
        createController: () async {
          final api = ref.read(apiServiceProvider);
          final session = ref.read(sessionServiceProvider);
          final gateway = ApiDineInGateway(
            api,
            () => quickDeviceScope(
              api.quickOrderBaseUrl,
              session.companyId,
              session.branchId,
              session.kioskId,
            ),
            mutationGuard: controller.assertNoPendingCombine,
          );
          return DineInController(
            gateway,
            await SqliteDineInStore.open(gateway.scope),
            id,
            staffId: session.staff?.id,
            recordCancellationWaste: (request, qty) async {
              gateway.check();
              final cancel = request.cancellation;
              final product = controller.allProducts
                  .where((p) => p.id == '${cancel['product_id']}')
                  .firstOrNull;
              if (product?.stockMode != 'unit' &&
                  product?.stockMode != 'cooked') {
                return;
              }
              await ref.read(orderSyncRepositoryProvider).enqueueEvent(
                'table-cancel-waste:${request.id}',
                {
                  'client_event_id': cancel['waste_event_id'],
                  'event_type': 'product.waste',
                  'client_timestamp': cancel['cancelled_at'],
                  'payload': {
                    'table_cancellation_request_id': request.id,
                    'lines': [
                      {
                        'product_id': cancel['product_id'],
                        'qty': qty,
                        'reason': 'other',
                      },
                    ],
                    'note': 'cancelled after preparation — table $tableId',
                    'staff_id': request.payload['staff_id'],
                    'wasted_at': cancel['cancelled_at'],
                  },
                },
                createdAt: DateTime.parse(cancel['cancelled_at'] as String),
              );
              gateway.check();
            },
            printAccepted: (detail, round) async {
              gateway.check();
              if (!ref.read(settingsControllerProvider).printKitchenTickets) {
                return true;
              }
              return ref
                  .read(qrRoundAutoPrintControllerProvider)
                  .printConfirmedRound(
                    QrRoundEnvelope(
                      round: QrDeviceRound.fromJson(round),
                      orderUuid: detail.billUuid!,
                      tableLabel: detail.table['label'] as String,
                      receiptNumber: detail.bill?['receipt_number'] as String?,
                      tempReference: detail.reference,
                      ticketKey: 'round:${round['id']}',
                      printedAt: DateTime.tryParse(
                        round['kitchen_printed_at']?.toString() ?? '',
                      ),
                    ),
                  );
            },
            localDraftTables: () => {
              for (final local in controller.diningTableSessions)
                if (_tableDraftBlocks(local.tableId)) ...{
                  ?int.tryParse(local.tableId),
                  ?int.tryParse(local.primaryTableId ?? ''),
                  ...local.linkedTableIds.map(int.tryParse).whereType<int>(),
                },
              if (controller.activeDiningTableId != null &&
                  _tableDraftBlocks(controller.activeDiningTableId!))
                ?int.tryParse(controller.activeDiningTableId!),
              ..._pendingTableIds.map(int.tryParse).whereType<int>(),
            },
          );
        },
        catalogue: () =>
            machineQuickCatalogue(ref.read(catalogProvider).asData?.value),
        onPay: _launchQrCheckout,
        pickAdjustment: _pickTableAdjustment,
        onVoid: (uuid) => _cancelTableBill(id, uuid),
        approveAdjustmentDiscard: () => _authorizeManager(
          subtitle: dineInText(_arabicTable, 'discard_adjustment'),
        ),
        approveCancellation: () async {
          final approval = await requestSentLineCancellation(
            context,
            authorizeManager: () => _authorizeManager(
              subtitle: L10n.of(context).tableCancelSentApproval,
            ),
          );
          if (!mounted || approval == null) return null;
          return {'prepared': approval.prepared, 'reason': approval.reason};
        },
        onCombine: () => _openBillCombine(id),
        onRecover: () => _openDraftRecovery(id),
      ),
      tableLabel: tableLabel ?? table?.name ?? tableId,
    );
    _customerBillRouteOpen = _workspace != null;
  }

  bool _tableCancellationBusy = false;

  Future<bool> _cancelTableBill(int tableId, String uuid) async {
    if (_tableCancellationBusy) return false;
    setState(() => _tableCancellationBusy = true);
    final api = ref.read(apiServiceProvider),
        session = ref.read(sessionServiceProvider);
    String scope() => quickDeviceScope(
      api.quickOrderBaseUrl,
      session.companyId,
      session.branchId,
      session.kioskId,
    );
    final captured = scope(), token = api.tokenGetter();
    final workspace = _workspace;
    if (workspace != null) {
      _cancellingWorkspaces[uuid] = (
        workspace: workspace,
        scope: captured,
        token: token,
      );
    }
    void check() {
      if (!mounted || captured != scope() || token != api.tokenGetter()) {
        throw StateError('cancel_blocked');
      }
    }

    try {
      final result = await ref
          .read(tableSyncCoordinatorProvider)
          .cancelBill(
            tableId: tableId,
            billUuid: uuid,
            read: () async {
              check();
              try {
                final d = DineInDetail(await api.dineInDetail(tableId));
                check();
                return d;
              } on ApiException catch (error) {
                // These reads precede the durable intent. Never claim that a
                // request was saved when the fresh bill could not be read.
                throw StateError(
                  error.isNetwork ? 'cancel_offline' : 'cancel_blocked',
                );
              }
            },
            pick: (d) => showBillCancelDialog(
              context,
              BillCancelGroup.fromRounds(d.rounds),
              d.bill!['grand_total_baisas'] as int,
              arabic: _arabicTable,
            ),
            approve: () => _authorizeManager(
              subtitle: _arabicTable
                  ? 'إلغاء فاتورة الطاولة'
                  : 'Cancel table bill',
            ),
            guard: () async {
              check();
              if (_tableDraftBlocks('$tableId') || _tableSendBusy) {
                throw StateError('cancel_blocked');
              }
              await controller.assertNoPendingCombine();
              if (ref
                      .read(qrSettlementCoordinatorProvider)
                      .pendingManagerRecoveries
                      .isNotEmpty ||
                  await ref
                      .read(orderSyncRepositoryProvider)
                      .hasUnresolvedStandaloneQrPay(uuid)) {
                throw StateError('cancel_blocked');
              }
              await assertWorkspaceVoidJournals(captured, uuid);
              check();
            },
          );
      check();
      if (result == null || !mounted) {
        _cancellingWorkspaces.remove(uuid);
        return false;
      }
      if (result['outcome'] == 'refused') _cancellingWorkspaces.remove(uuid);
      final code =
          result['refusal_code'] ??
          (result['outcome'] == 'uncertain'
              ? 'cancel_pending'
              : result['outcome']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            [
              tableCancelText(code as String, _arabicTable),
              if (cancellationWasteNotice(result, _arabicTable)
                  case final String notice)
                notice,
            ].join('\n'),
          ),
        ),
      );
      if (const {'cancelled', 'replayed'}.contains(result['outcome'])) {
        await ref.read(orderSyncRepositoryProvider).flush();
        if (workspace == null &&
            _workspace == null &&
            controller.activeDiningTableId == '$tableId' &&
            !_tableDraftBlocks('$tableId')) {
          // Release this editor only. Canonical closure proof, not this ACK
          // alone, owns archival of the original local copy.
          await controller.returnToDiningFloorPlan();
        }
        await ref.read(tableShadowRepositoryProvider).pollNow();
        await _retireClosedTableCopies(tableId: '$tableId', force: true);
        return true;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tableCancelText(
                error is StateError
                    ? error.message.toString()
                    : 'cancel_pending',
                _arabicTable,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _tableCancellationBusy = false);
    }
    return false;
  }

  Future<void> _openRemoteDiningTableActions(
    DiningTableDefinition table, {
    bool canAddItems = true,
  }) async {
    await _openCustomerBill(table.id);
  }

  Future<void> _openBillCombine(int tableId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CombineScreen(
          arabic: ref.read(settingsControllerProvider).language == 'ar',
          createController: () async {
            final api = ref.read(apiServiceProvider),
                session = ref.read(sessionServiceProvider);
            String scope() => quickDeviceScope(
              api.quickOrderBaseUrl,
              session.companyId,
              session.branchId,
              session.kioskId,
            );
            final gateway = ApiCombineGateway(api, scope);
            final db = await LocalOrderStorageService.instance.database;
            return CombineController(
              store: CombineStore(db, gateway.scope),
              gateway: gateway,
              tableId: tableId,
              loadLocal: (id) async {
                final local = await loadCombineLocal(db, id);
                final inMemory = controller.diningSessionFor('$id');
                if (inMemory?.draft != null &&
                    inMemory!.draft!.items.isNotEmpty) {
                  final saved = local.rows
                      .where((r) => r['table'] == 'dining_tables')
                      .toList();
                  if (saved.length != 1 ||
                      combineJson(inMemory.draft!.toMap()) !=
                          combineJson(
                            jsonDecode(
                              combineMap(saved.single['row'])['draft_json']
                                  as String,
                            ),
                          )) {
                    throw StateError(
                      'An in-memory table draft differs from storage. Keep it unchanged.',
                    );
                  }
                }
                return local;
              },
              checkIdle: () async {
                gateway.check();
                await LocalOrderStorageService.instance.assertRecoveryIdle();
                await controller.assertIdleForCombine();
                if (!mounted ||
                    _showPaymentPage ||
                    _normalQrCheckoutOpen ||
                    _pendingTableIds.isNotEmpty ||
                    controller.showPaymentLaunchOverlay ||
                    controller.showCharityRoundUpPrompt ||
                    ref
                        .read(qrSettlementCoordinatorProvider)
                        .pendingManagerRecoveries
                        .isNotEmpty) {
                  throw StateError(
                    'Finish pending payment or table work before combining.',
                  );
                }
                await ref
                    .read(orderSyncRepositoryProvider)
                    .assertIdleForCombine();
                if (await (await SqliteCheckoutStore.open(
                          gateway.scope,
                        )).active() !=
                        null ||
                    await (await SqliteDineInStore.open(
                          gateway.scope,
                        )).load() !=
                        null ||
                    (await (await SqliteQrQuickStore.open(
                      gateway.scope,
                    )).load()).isNotEmpty) {
                  throw StateError(
                    'Resolve saved payments and item additions first.',
                  );
                }
                gateway.check();
                await controller.assertIdleForCombine();
              },
            );
          },
        ),
      ),
    );
    await controller.refreshHeldOrders();
    await controller.refreshDiningTables();
  }

  bool _retiringClosedCopies = false;
  final Map<String, DateTime> _closedCopyChecks = {};
  final Map<String, String> _closedCopyBlockers = {};

  String _closedCopyReason(String tableId) {
    final arabic = ref.read(settingsControllerProvider).language == 'ar';
    final key =
        _closedCopyBusyReason ?? _closedCopyBlockers[tableId] ?? 'proof';
    final messages = <String, (String, String)>{
      'loading': (
        'Wait for saved table data to finish loading.',
        'انتظر اكتمال تحميل بيانات الطاولة المحفوظة.',
      ),
      'checking': (
        'The saved copy is being checked. Wait, then retry.',
        'يتم التحقق من النسخة المحفوظة. انتظر ثم أعد المحاولة.',
      ),
      'mode': (
        'Reconnect in live table mode before clearing this copy.',
        'أعد الاتصال بوضع الطاولات المباشر قبل مسح هذه النسخة.',
      ),
      'workspace': (
        'Close the open bill and return to the floor plan first.',
        'أغلق الفاتورة المفتوحة وعد إلى مخطط الطاولات أولاً.',
      ),
      'payment': (
        'Finish or check the open payment result first. Do not take payment again.',
        'أكمل عملية الدفع المفتوحة أو تحقق من نتيجتها أولاً. لا تأخذ دفعة أخرى.',
      ),
      'cart': (
        'Return to the floor plan with no active cart first. Unsent items remain saved.',
        'عد إلى مخطط الطاولات دون سلة نشطة أولاً. تبقى العناصر غير المرسلة محفوظة.',
      ),
      'sending': (
        'Wait for the current kitchen request to finish, then retry.',
        'انتظر اكتمال طلب المطبخ الحالي ثم أعد المحاولة.',
      ),
      'sync': (
        'A table or outbox operation is still pending. Finish its sync, then retry.',
        'لا تزال عملية طاولة أو إرسال معلقة. أكمل مزامنتها ثم أعد المحاولة.',
      ),
      'local': (
        'Open Order History and Check payment result to review any saved payment. If this copy still cannot be cleared, keep app data and give support the table and order reference. Do not take payment again.',
        'افتح سجل الطلبات وتحقق من نتيجة الدفع لمراجعة أي دفعة محفوظة. إذا تعذر مسح النسخة، احتفظ ببيانات التطبيق وأرسل رقم الطاولة ومرجع الطلب إلى الدعم. لا تأخذ دفعة أخرى.',
      ),
      'server': (
        'Could not verify this bill with the server. Reconnect and retry.',
        'تعذر التحقق من هذه الفاتورة مع الخادم. أعد الاتصال والمحاولة.',
      ),
      'occupied': (
        'The server still has an open seating or bill for this table.',
        'لا يزال لدى الخادم جلسة أو فاتورة مفتوحة لهذه الطاولة.',
      ),
      'unsent': (
        'Local items differ from the acknowledged kitchen rounds. Review the unsent or changed items; this copy is kept.',
        'تختلف العناصر المحلية عن جولات المطبخ المؤكدة. راجع العناصر غير المرسلة أو المعدلة؛ تم الاحتفاظ بالنسخة.',
      ),
      'journals': (
        'Resolve saved checkout or order requests before archiving this copy. Use Check payment result for an uncertain payment.',
        'أكمل طلبات الدفع أو الطلبات المحفوظة قبل أرشفة النسخة. استخدم التحقق من نتيجة الدفع لأي دفعة غير مؤكدة.',
      ),
      'proof': (
        'The server has not proved this closed bill and its held rounds. Reconnect, then use Clear Table for a manager check. Keep the copy; do not take payment again.',
        'لم يثبت الخادم إغلاق الفاتورة وحالة جولاتها المعلقة. أعد الاتصال ثم استخدم مسح الطاولة للتحقق بموافقة المشرف. احتفظ بالنسخة ولا تأخذ دفعة أخرى.',
      ),
    };
    final message = messages[key] ?? messages['local']!;
    return arabic ? message.$2 : message.$1;
  }

  String? get _closedCopyBusyReason {
    if (controller.isLoadingStorage) return 'loading';
    if (_retiringClosedCopies) return 'checking';
    if (_tableShadowMode != 'live') return 'mode';
    if (_workspace != null) return 'workspace';
    if (_normalQrCheckoutOpen ||
        _showPaymentPage ||
        controller.isProcessingPayment) {
      return 'payment';
    }
    if (controller.activeDiningTableId != null || controller.cart.isNotEmpty) {
      return 'cart';
    }
    if (_tableSendBusy) return 'sending';
    return null;
  }

  Future<bool> _retireClosedTableCopies({
    String? tableId,
    bool force = false,
    bool managerApproved = false,
  }) async {
    await _checkSavedTablePayment(force: force);
    if (!mounted || _closedCopyBusyReason != null) return false;
    final storage =
        debugOrderStorageOverride ?? LocalOrderStorageService.instance;
    if (storage is! LocalOrderStorageService) return false;
    _retiringClosedCopies = true;
    var retired = false;
    try {
      final api = ref.read(apiServiceProvider),
          session = ref.read(sessionServiceProvider);
      String scope() => quickDeviceScope(
        api.quickOrderBaseUrl,
        session.companyId,
        session.branchId,
        session.kioskId,
      );
      final captured = scope(), token = api.tokenGetter();
      void sameScope() {
        if (!mounted || scope() != captured || token != api.tokenGetter()) {
          throw StateError('Device changed');
        }
        if (_workspace != null ||
            _showPaymentPage ||
            _normalQrCheckoutOpen ||
            controller.activeDiningTableId != null ||
            controller.cart.isNotEmpty ||
            controller.isProcessingPayment ||
            _tableSendBusy) {
          throw StateError(
            'Wait until the till returns to the idle floor plan',
          );
        }
      }

      final outbox = ref.read(orderSyncRepositoryProvider);
      final coordinator = ref.read(tableSyncCoordinatorProvider);
      // ACKs persist identity directly, while the active cart intentionally
      // keeps its own copy. At the idle floor use the authoritative saved
      // generation, including fresh staff tables whose memory lacks the ACK.
      final savedCandidates = await storage.loadDiningTableSessions();
      sameScope();
      for (final candidate in savedCandidates) {
        if (tableId != null && candidate.tableId != tableId) continue;
        _closedCopyBlockers[candidate.tableId] = 'proof';
        final id = int.tryParse(candidate.tableId);
        if (id == null ||
            candidate.seatingUuid == null ||
            candidate.serverOrderUuid == null ||
            _remoteTables.tables[id]?.occupied != false) {
          continue;
        }
        final last = _closedCopyChecks[candidate.tableId];
        if (!force &&
            last != null &&
            DateTime.now().difference(last).inSeconds < 15) {
          continue;
        }
        _closedCopyChecks[candidate.tableId] = DateTime.now();
        var stage = 'sync';
        try {
          _orderPreparations.assertIdle();
          await controller.assertIdleForCombine();
          await _tableKitchen?.settled;
          await coordinator.settled;
          await outbox.assertIdleForCombine();
          sameScope();
          stage = 'local';
          final db = await storage.database;
          final local = await loadRecoveryLocal(
            db,
            id,
            outboxRow: outbox.rowForKey,
            currentGenerationOnly: true,
          );
          stage = 'server';
          final detail = DineInDetail(await api.dineInDetail(id));
          if (detail.occupied ||
              detail.orphaned ||
              detail.seating != null ||
              detail.bill != null) {
            _closedCopyBlockers[candidate.tableId] = 'occupied';
            continue;
          }
          final bill = await api.closedTableBill(local.uuid, id);
          if (bill == null) {
            _closedCopyBlockers[candidate.tableId] = 'proof';
            continue;
          }
          if ((local.cancellations.isNotEmpty ||
                  local.rounds.any((r) => r['status'] != 'appended')) &&
              !closedRoundProof(local, bill)) {
            _closedCopyBlockers[candidate.tableId] = 'proof';
            continue;
          }
          if (!RecoveryStore.closedSentProof(local, bill, detail.json)) {
            _closedCopyBlockers[candidate.tableId] = 'unsent';
            continue;
          }
          stage = 'journals';
          sameScope();
          final checkout = await SqliteCheckoutStore.open(captured);
          final dine = await SqliteDineInStore.open(captured);
          final quick = await SqliteQrQuickStore.open(captured);
          storage.beginRecoveryAdmission();
          try {
            await outbox.admitDraftRecovery(() async {
              sameScope();
              await controller.assertIdleForCombine();
              _orderPreparations.assertIdle();
              await assertRecoveryJournalsIdle(
                checkout: checkout.db,
                dineIn: dine.db,
                quick: quick.database,
                currentScope: captured,
              );
              sameScope();
              stage = 'local';
              if (await RecoveryStore(db, captured).retireClosed(
                local,
                bill: bill,
                table: detail.json,
                reconcileRejectedRounds: true,
                managerApproved: managerApproved,
              )) {
                retired = true;
                for (final original in local.rows.where(
                  (r) => r['table'] == 'dining_tables',
                )) {
                  final row = recoveryMap(original['row']);
                  coordinator.forgetRecoveredSession(
                    tableId: '$id',
                    uuid: local.uuid,
                    occupiedAt: row['occupied_at'] as String?,
                    seatingKey: row['seating_key'] as String?,
                  );
                  controller.forgetRecoveredOccupancy(
                    '$id',
                    local.json['draft']['orderReference'] as String,
                    row['occupied_at'] as String?,
                  );
                }
              }
            });
          } finally {
            await storage.endRecoveryAdmission();
          }
          if (retired) {
            await controller.refreshHeldOrders();
            await controller.refreshDiningTables();
          }
        } catch (_) {
          _closedCopyBlockers[candidate.tableId] = stage;
          // No proof/admission: retain all originals. F-10 still blocks tender.
        }
      }
    } catch (_) {
      // Scope/storage unavailable: retry on the next fresh board, never delete.
    } finally {
      _retiringClosedCopies = false;
    }
    return retired;
  }

  Future<void> _openDraftRecovery(int tableId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecoveryScreen(
          arabic: ref.read(settingsControllerProvider).language == 'ar',
          createController: () async {
            final api = ref.read(apiServiceProvider),
                session = ref.read(sessionServiceProvider);
            String scope() => quickDeviceScope(
              api.quickOrderBaseUrl,
              session.companyId,
              session.branchId,
              session.kioskId,
            );
            final storage = LocalOrderStorageService.instance;
            final db = await storage.database;
            final store = RecoveryStore(
              db,
              scope(),
              onChanged: storage.refreshRecoveryGuard,
            );
            final gateway = ApiRecoveryGateway(api, scope, store);
            final outbox = ref.read(orderSyncRepositoryProvider);
            final coordinator = ref.read(tableSyncCoordinatorProvider);
            final checkout = await SqliteCheckoutStore.open(gateway.scope);
            final rounds = await SqliteDineInStore.open(gateway.scope);
            final quick = await SqliteQrQuickStore.open(gateway.scope);
            Future<void> idle({bool insideAdmission = false}) async {
              gateway.check();
              _orderPreparations.assertIdle();
              if (ref.read(tableSessionsModeProvider) != 'live') {
                throw StateError(
                  'Return to Live table mode to recover this saved draft.',
                );
              }
              await controller.assertIdleForCombine();
              if (!mounted ||
                  _showPaymentPage ||
                  _normalQrCheckoutOpen ||
                  _tableSendBusy ||
                  controller.showPaymentLaunchOverlay ||
                  controller.showCharityRoundUpPrompt ||
                  _claimedTransferPendingLoad != null ||
                  ref
                      .read(qrSettlementCoordinatorProvider)
                      .pendingManagerRecoveries
                      .isNotEmpty) {
                throw StateError(
                  'Finish pending payment or table work before recovery.',
                );
              }
              // These callbacks may prepare an outbox event. Never wait for them
              // from inside the outbox admission slot (which they may need).
              if (!insideAdmission) {
                await _tableKitchenInit;
                await _tableKitchen?.settled;
                await coordinator.settled;
                await outbox.assertIdleForCombine();
              }
              await RecoveryStore.assertNoCombine(db);
              await assertRecoveryJournalsIdle(
                checkout: checkout.db,
                currentScope: gateway.scope,
                dineIn: rounds.db,
                quick: quick.database,
              );
              gateway.check();
              await controller.assertIdleForCombine();
              _orderPreparations.assertIdle();
              if (ref.read(tableSessionsModeProvider) != 'live') {
                throw StateError(
                  'Table mode changed. The recovery copy remains saved.',
                );
              }
            }

            return RecoveryController(
              store: store,
              gateway: gateway,
              dineIn: gateway,
              tableId: tableId,
              staffId: session.staff?.id,
              loadLocal: (id) async {
                final local = await loadRecoveryLocal(
                  db,
                  id,
                  outboxRow: outbox.rowForKey,
                );
                final inMemory = controller.diningSessionFor('$id');
                if (inMemory?.draft != null &&
                    inMemory!.draft!.items.isNotEmpty) {
                  final saved = local.rows
                      .where((r) => r['table'] == 'dining_tables')
                      .toList();
                  if (saved.length != 1 ||
                      recoveryJson(inMemory.draft!.toMap()) !=
                          recoveryJson(
                            jsonDecode(
                              recoveryMap(saved.single['row'])['draft_json']
                                  as String,
                            ),
                          )) {
                    throw StateError(
                      'An in-memory table draft differs from storage. Keep it unchanged.',
                    );
                  }
                }
                return local;
              },
              checkIdle: idle,
              admit: (operation) async {
                // Stop synchronous cart edits before the final asynchronous check.
                storage.beginRecoveryAdmission();
                try {
                  await idle();
                  await outbox.admitDraftRecovery(() async {
                    await idle(insideAdmission: true);
                    await operation();
                  });
                } finally {
                  await storage.endRecoveryAdmission();
                }
              },
              onRetired: (local) async {
                for (final record in local.rows.where(
                  (r) => r['table'] == 'dining_tables',
                )) {
                  final row = recoveryMap(record['row']);
                  coordinator.forgetRecoveredSession(
                    tableId: '${local.tableId}',
                    uuid: local.uuid,
                    occupiedAt: row['occupied_at'] as String?,
                    seatingKey: row['seating_key'] as String?,
                  );
                  controller.forgetRecoveredOccupancy(
                    '${local.tableId}',
                    recoveryMap(
                          jsonDecode(row['draft_json'] as String),
                        )['orderReference']
                        as String,
                    row['occupied_at'] as String?,
                  );
                }
                await controller.refreshHeldOrders();
                await controller.refreshDiningTables();
              },
            );
          },
        ),
      ),
    );
    await controller.refreshHeldOrders();
    await controller.refreshDiningTables();
  }

  String _formatOccupancyDuration(DateTime? value) =>
      _formatOccupancyDurationAt(value, _clockNow.value);

  void _onTableSearchChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleTableSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTableSearch();
    });
  }

  void _updateTableSearch([String? draft]) {
    final live = ref.read(tableSessionsModeProvider) == 'live';
    final session = ref.read(sessionServiceProvider);
    _tableSearch.update(
      draft ?? controller.diningTableSearchQuery,
      enabled: live,
      degraded: live && ref.read(degradedStateProvider).degraded,
      scope:
          '${ref.read(settingsServiceProvider).effectiveBaseUrl}|'
          '${session.companyId}|${session.branchId}|${session.kioskId}',
    );
  }

  Widget _buildCatalogSurface(double contentHeight) {
    return Column(
      children: [
        SizedBox(
          height: _topBarHeight,
          child: IgnorePointer(
            ignoring: _workspace != null && !_workspace!.mainCart,
            child: _buildTopBar(),
          ),
        ),
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
    final tables = _tableShadowMode != 'live'
        ? controller.visibleDiningTables
        : tableSearchMatches(
            local: controller.visibleDiningTables,
            definitions: controller.diningTableDefinitions,
            floorId: controller.selectedDiningFloorId,
            results: _tableSearch.results,
          );

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
                  width: _tableShadowMode == 'off' ? 530 : 660,
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
                      if (_tableShadowMode != 'off') ...[
                        const SizedBox(width: 8),
                        _DiningLegendDot(
                          color: const Color(0xFF687873),
                          label: L10n.of(context).tableServerView,
                        ),
                      ],
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
          if (_tableShadowMode == 'live')
            TableSearchSummary(search: _tableSearch),
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
                                final remote = _remoteTables
                                    .tables[int.tryParse(table.id)];
                                final customerOccupied =
                                    customerOccupiesDiningTable(
                                      mode: _tableShadowMode,
                                      session: session,
                                      remote: remote,
                                    );

                                // Joined tables — a linked seat shows a
                                // "Joined → head" badge + the shared bill total
                                // and routes everything to the head; a head
                                // shows how many seats are joined under it.
                                final bool isLinkedSeat =
                                    session != null &&
                                    session.isLinkedSecondary;
                                String? linkedToLabel;
                                double? groupTotal;
                                int linkedCount = 0;
                                if (isLinkedSeat) {
                                  final headId = session.primaryTableId!;
                                  linkedToLabel =
                                      controller
                                          .diningTableDefinitionById(headId)
                                          ?.name ??
                                      headId;
                                  groupTotal = controller
                                      .diningSessionFor(headId)
                                      ?.total;
                                } else if (session != null &&
                                    session.hasJoinedTables) {
                                  linkedCount = session.linkedTableIds.length;
                                }

                                // Gap sweep G2 / P-F1 — occupied tables expose
                                // Move / Join via a visible actions button (and
                                // still on long-press). A linked seat has no
                                // actions of its own; manage it from the head.
                                final openActions = customerOccupied
                                    ? () => unawaited(
                                        _openRemoteDiningTableActions(table),
                                      )
                                    : isLinkedSeat &&
                                          _hasServerBillFor(table.id) &&
                                          status != DiningTableStatus.paid
                                    ? () => unawaited(
                                        _openRemoteDiningTableActions(
                                          table,
                                          canAddItems: false,
                                        ),
                                      )
                                    : status == DiningTableStatus.occupied &&
                                          session != null &&
                                          !isLinkedSeat
                                    ? () => unawaited(
                                        _openDiningTableActionsSheet(
                                          table,
                                          session,
                                        ),
                                      )
                                    : null;
                                return _DiningTableCard(
                                  table: table,
                                  session: session,
                                  status: status,
                                  clock: _clockNow,
                                  now: _clockNow.value,
                                  remote: remote,
                                  customerOccupied: customerOccupied,
                                  customerReference: remote?.tempReference,
                                  remoteFailures:
                                      _remoteTables.meta.consecutiveFailures,
                                  lastFeedOkAt: _remoteTables.meta.lastFeedOkAt,
                                  live: _tableShadowMode == 'live',
                                  sending: _pendingTableIds.contains(table.id),
                                  pendingRounds:
                                      _tableShadow
                                          ?.displayActivityBoard[int.tryParse(
                                            table.id,
                                          )]
                                          ?.pendingCount ??
                                      0,
                                  searchMatch:
                                      _tableShadowMode == 'live' &&
                                      _tableSearch.results.any(
                                        (r) => r.tableId.toString() == table.id,
                                      ),
                                  onLongPress:
                                      openActions ??
                                      () => unawaited(
                                        _openCustomerBill(table.id),
                                      ),
                                  onActions: openActions,
                                  linkedToLabel: linkedToLabel,
                                  groupTotal: groupTotal,
                                  linkedCount: linkedCount,
                                  onTap: () async {
                                    await routeDiningTableTap(
                                      tableId: table.id,
                                      mode: _tableShadowMode,
                                      session: session,
                                      remote: remote,
                                      controller: controller,
                                      openCustomerBill: () =>
                                          _openCustomerBill(table.id),
                                      openPaidDialog: () =>
                                          _openPaidDiningTableDialog(
                                            table,
                                            session!,
                                          ),
                                      localOpened: () {
                                        if (mounted) {
                                          setState(
                                            () => _showPaymentPage = false,
                                          );
                                        }
                                      },
                                    );
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

  String get _tablePayContext {
    final session = ref.read(sessionServiceProvider);
    final local = controller.diningSessionFor(
      controller.activeDiningTableId ?? '',
    );
    return jsonEncode([
      ref.read(settingsServiceProvider).effectiveBaseUrl,
      session.companyId,
      session.branchId,
      session.kioskId,
      session.deviceToken,
      session.staff?.id,
      session.openShift?.uuid,
      controller.activeDiningTableId,
      local?.orderReference,
      local?.occupiedAt?.toIso8601String(),
      local?.seatingKey,
      controller.activeDiningTableBillUuid,
    ]);
  }

  static const _closedTableMessage =
      'This bill was paid or closed. Any unsent local items remain saved. Use Clear Table to review the saved copy.';
  final Map<String, String> _tableBillRefusals = {};

  String _localBillKey(DiningTableSession? session) =>
      '${session?.tableId}|${session?.orderReference}|${session?.occupiedAt}';

  String? get _localTableRefusal {
    if (!_liveTable || _workspace != null) return null;
    final local = controller.diningSessionFor(controller.activeDiningTableId!);
    final saved = _tableBillRefusals[_localBillKey(local)];
    if (saved != null) return saved;
    final bound =
        _tableKitchen?.coordinator.cachedSession(local?.tableId ?? '') ?? local;
    final row = _cartBill;
    // A board fetched before this generation was acknowledged open (including held) cannot
    // close it. Keep the fresh send preflight and all newer-board refusals.
    final boardAt = row?.fetchedAt ?? _remoteTables.meta.boardFetchedAt;
    final ackAt = bound?.lastVerdictAt;
    final boardPredatesOpenAck =
        bound?.seatingState == 'open' &&
        const {
          'opened',
          'attached',
          'appended',
          'held',
          'seating_created',
        }.contains(bound?.lastVerdict) &&
        boardAt != null &&
        ackAt != null &&
        boardAt.isBefore(ackAt);
    if (bound?.seatingUuid != null &&
        !boardPredatesOpenAck &&
        (_remoteTables.meta.boardFetchedAt != null || row != null) &&
        (row == null ||
            !row.occupied ||
            row.seatingUuid != bound!.seatingUuid ||
            const {
              'paid',
              'voided',
              'cancelled',
              'closed',
            }.contains(row.billStatus))) {
      return _closedTableMessage;
    }
    return null;
  }

  Future<String?> _verifyLocalTableBill({
    DiningTableSession? source,
    bool tender = false,
  }) async {
    if (ref.read(tableSessionsModeProvider) != 'live') return null;
    final id = source?.tableId ?? controller.activeDiningTableId;
    if (id == null) return null;
    final local = source ?? controller.diningSessionFor(id);
    final bound = _tableKitchen?.coordinator.cachedSession(id) ?? local;
    // Initial/offline drafts may still be queued. Once acknowledged, a send
    // must never turn a closed generation into another order.
    if (!tender && bound?.seatingUuid == null) return null;
    final identity = _tablePayContext;
    final key = _localBillKey(local);
    String? refusal;
    try {
      final detail = DineInDetail(
        await ref.read(apiServiceProvider).dineInDetail(int.parse(id)),
      );
      if (!mounted || (tender && identity != _tablePayContext)) {
        return 'The active table changed. Reopen it before payment.';
      }
      final uuid =
          bound?.serverOrderUuid ?? controller.activeDiningTableBillUuid;
      if (!detail.occupied ||
          (bound?.seatingUuid != null &&
              detail.seatingUuid != bound!.seatingUuid) ||
          (detail.billUuid != null &&
              uuid.isNotEmpty &&
              detail.billUuid != uuid) ||
          const {
            'paid',
            'voided',
            'cancelled',
            'closed',
          }.contains(detail.bill?['status']) ||
          const {'closed', 'expired'}.contains(detail.seating?['status'])) {
        refusal = _closedTableMessage;
      } else if (tender && (detail.billUuid == null || detail.pendingReview)) {
        refusal =
            'Open the table bill and confirm or reject pending rounds before payment.';
      } else if (tender &&
          (detail.bill?['grand_total_baisas'] is! int ||
              (detail.bill!['grand_total_baisas'] as int) < 1)) {
        refusal =
            'The bill must have a positive server balance before payment.';
      } else if (!detail.canAppend) {
        refusal =
            'This table bill is reserved or unavailable. Refresh it before continuing.';
      }
      if (refusal == null && tender) {
        final editor = await _ensureLiveEditor();
        if (editor != null) {
          editor.detail = detail;
          editor.stale = false;
        }
      }
    } catch (_) {
      refusal = 'Could not verify the table bill. Reconnect and try again.';
    }
    if (mounted) {
      setState(() {
        if (refusal == null) {
          _tableBillRefusals.remove(key);
        } else {
          _tableBillRefusals[key] = refusal;
        }
      });
    }
    return refusal;
  }

  RemoteTableState? get _cartBill {
    final id = int.tryParse(controller.activeDiningTableId ?? '');
    if (id == null || _tableShadowMode == 'off') return null;
    return _tableCartPay.known(
      tableId: id,
      contextKey: _tablePayContext,
      board: _remoteTables,
    );
  }

  Future<void> _openPaymentPage() async {
    if (_workspace case final workspace? when workspace.mainCart) {
      await workspace.requestPay();
      return;
    }
    final mode = ref.read(tableSessionsModeProvider);
    final tableId = int.tryParse(controller.activeDiningTableId ?? '');
    if (mode != 'live' || tableId == null) {
      await _openLocalPaymentPage();
      return;
    }
    if (tableBillNeedsSheet(mode, _cartBill)) {
      await _openCustomerBill(tableId.toString());
      return;
    }
    if (await _verifyLocalTableBill(tender: true) != null) return;
    final contextKey = _tablePayContext;
    bool current() =>
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false) &&
        !_showPaymentPage &&
        !_customerBillRouteOpen &&
        !controller.isProcessingPayment &&
        !controller.showCharityRoundUpPrompt &&
        !controller.showPaymentLaunchOverlay &&
        !(controller.hasRecordedSplitPayments && controller.cart.isNotEmpty) &&
        ref.read(tableSessionsModeProvider) == mode &&
        _tablePayContext == contextKey;
    await _tableCartPay.route(
      mode: mode,
      tableId: tableId,
      contextKey: contextKey,
      board: _remoteTables,
      latestBoard: () => _remoteTables,
      fetchBoard: ref.read(apiServiceProvider).fetchTableBoard,
      isCurrent: current,
      changed: () {
        if (mounted) setState(() {});
      },
      openSheet: () => _openCustomerBill(tableId.toString()),
      openLocal: () => _openLocalPaymentPage(stillCurrent: current),
    );
  }

  Future<void> _openLocalPaymentPage({bool Function()? stillCurrent}) async {
    if (!await _allowTableSelections()) return;
    if (stillCurrent != null && !stillCurrent()) return;
    if (stillCurrent != null &&
        tableBillNeedsSheet(_tableShadowMode, _cartBill)) {
      await _openCustomerBill(controller.activeDiningTableId!);
      return;
    }
    if (controller.cart.isEmpty || controller.isProcessingPayment) {
      if (!mounted || controller.isProcessingPayment) return;
      _showPopupMessage(
        title: 'Order Required',
        message: 'Add at least one item before paying.',
        tone: FeedbackTone.warning,
      );
      return;
    }

    // P-F4 — re-check order-scope auto discounts at the till (time windows
    // are evaluated against "now"; a no-op when one is applied/suppressed).
    controller.maybeAutoApplyOrderDiscount();
    setState(() {
      _showPaymentPage = true;
      _cashTenderInput = '';
    });
    _customerNumberController.text = controller.customerReferenceNumber;
    _vehiclePlateController.text = controller.vehiclePlateNumber;
  }

  // Re-check at dispatch too: a customer may adopt the bill while its local
  // tender page is open. Existing tender/accounting code runs only if local.
  Future<bool> _allowLocalTableTender() async {
    final mode = ref.read(tableSessionsModeProvider);
    final tableId = int.tryParse(controller.activeDiningTableId ?? '');
    if (mode != 'live' || tableId == null) return true;
    if (await _verifyLocalTableBill(tender: true) != null) return false;
    final contextKey = _tablePayContext;
    var allowed = false;
    bool current() =>
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false) &&
        _showPaymentPage &&
        !_customerBillRouteOpen &&
        !controller.isProcessingPayment &&
        !controller.showCharityRoundUpPrompt &&
        !controller.showPaymentLaunchOverlay &&
        ref.read(tableSessionsModeProvider) == mode &&
        _tablePayContext == contextKey;
    await _tableCartPay.route(
      mode: mode,
      tableId: tableId,
      contextKey: contextKey,
      board: _remoteTables,
      latestBoard: () => _remoteTables,
      fetchBoard: ref.read(apiServiceProvider).fetchTableBoard,
      isCurrent: current,
      changed: () {
        if (mounted) setState(() {});
      },
      openLocal: () async {
        allowed = await _allowTableSelections();
      },
      openSheet: () async {
        if (controller.hasRecordedSplitPayments && controller.cart.isNotEmpty) {
          return;
        }
        setState(() => _showPaymentPage = false);
        await _openCustomerBill(tableId.toString());
      },
    );
    return allowed && current();
  }

  /// P-F5 — gift ONE cart line (a 100% write-off riding the comp plumbing,
  /// marked is_gift on the wire). Gifting needs a manager (fingerprint or
  /// PIN); un-gifting is free — it only increases what the customer pays.
  Future<void> _handleGiftItemToggle(CartItem item) async {
    if (_liveTable) return;
    final l10n = L10n.of(context);
    if (!item.gifted) {
      final authorized = await _authorizeManager(
        subtitle: l10n.posGiftItemApprovalMessage,
      );
      if (!mounted) return;
      if (!authorized) {
        _showPopupMessage(
          title: l10n.posManagerApprovalRequiredTitle,
          message: l10n.posPayGiftDeniedMessage,
          tone: FeedbackTone.warning,
        );
        return;
      }
    }
    final wasGifted = item.gifted;
    final changed = controller.toggleGiftItem(item);
    if (!mounted) return;
    if (!changed) {
      _showPopupMessage(
        title: l10n.posGiftItemBlockedTitle,
        message: l10n.posGiftItemBlockedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    _showPopupMessage(
      title: wasGifted
          ? l10n.posGiftItemRemovedTitle
          : l10n.posGiftItemGiftedTitle,
      message: item.product.displayName(isAr),
      tone: FeedbackTone.success,
    );
  }

  /// P-F5 — the customer paid on the bank's standalone terminal; record the
  /// exact amount (no charge launch, no change math, wire method bank_pos).
  Future<void> _submitBankPosPayment() async {
    if (_liveTable && !await _allowLocalTableTender()) return;
    if (!mounted || controller.isProcessingPayment) return;
    controller.setCustomerReferenceNumber(_customerNumberController.text);
    controller.selectPaymentMethod('Bank POS');
    final message = await controller.payAndPrint();
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

  Future<void> _submitCardPayment() async {
    if (_liveTable && !await _allowLocalTableTender()) return;
    if (!mounted || controller.isProcessingPayment) return;
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
    if (_liveTable && !await _allowLocalTableTender()) return;
    if (!mounted || controller.isProcessingPayment) return;
    final l10n = L10n.of(context);
    final tendered = _tenderedCashAmount;
    if (tendered < controller.activePaymentBaseTotal) {
      _showPopupMessage(
        title: l10n.posPayTenderedTooLowTitle,
        message: l10n.posPayTenderedTooLowMessage(
          SunmiReceiptService.money(controller.activePaymentBaseTotal),
        ),
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

  /// Phase D4 (blueprint §6.8) — gift the WHOLE order: zero charged to the
  /// customer, inventory still deducts, manager approval required (the same
  /// fingerprint gate the comp flow uses, registering one if absent).
  Future<void> _submitGiftPayment() async {
    if (_liveTable) return;
    if (controller.isProcessingPayment || controller.cart.isEmpty) return;
    final l10n = L10n.of(context);

    // P-F1 — fingerprint with manager-PIN fallback.
    final authorized = await _authorizeManager(
      subtitle: l10n.posPayGiftManagerApprovalMessage,
    );
    if (!mounted) return;
    if (!authorized) {
      _showPopupMessage(
        title: l10n.posManagerApprovalRequiredTitle,
        message: l10n.posPayGiftDeniedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.posPayGiftConfirmTitle),
        content: Text(
          l10n.posPayGiftConfirmMessage(
            SunmiReceiptService.money(controller.activePaymentBaseTotal),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.posPaymentGift),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    controller.setCustomerReferenceNumber(_customerNumberController.text);
    // Label must be exactly 'Gift' — mapPaymentMethod matches 'card' before
    // 'gift', so e.g. 'Gift Card' would mis-map to a card tender.
    controller.selectPaymentMethod('Gift');
    final message = await controller.payAndPrint();
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

  Future<void> _submitMixedPayment() async {
    if (_liveTable && !await _allowLocalTableTender()) return;
    if (!mounted || controller.isProcessingPayment) return;
    final l10n = L10n.of(context);
    if (controller.splitCount > 1 || controller.hasRecordedSplitPayments) {
      _showPopupMessage(
        title: l10n.posPayClearSplitFirstTitle,
        message: l10n.posPayClearSplitFirstMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final cashAmount = _tenderedCashAmount;
    if (cashAmount <= 0 ||
        cashAmount + 0.0005 >= controller.activePaymentBaseTotal) {
      _showPopupMessage(
        title: l10n.posPayEnterCashPortionTitle,
        message: l10n.posPayEnterCashPortionMessage(
          SunmiReceiptService.money(controller.activePaymentBaseTotal),
        ),
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
    });
  }

  Future<void> _handleHoldOrder() async {
    final l10n = L10n.of(context);
    final message = await controller.holdCurrentOrder();
    if (!mounted || message == null) return;

    setState(() {
      _showPaymentPage = false;
      _cashTenderInput = '';
      _customerNumberController.clear();
    });
    _showPopupMessage(
      title: l10n.posHoldOrderHeldTitle,
      message: message,
      tone: FeedbackTone.success,
    );
  }

  Future<void> _openHeldOrdersDialog() async {
    final l10n = L10n.of(context);
    await controller.refreshHeldOrders();
    if (!mounted) return;

    final resumed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.posHeldOrdersTitle,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _StorageOverlayShell(
          title: l10n.posHeldOrdersTitle,
          subtitle: l10n.posHeldOrdersSubtitle,
          child: _HeldOrdersPanel(
            records: controller.heldOrders,
            onResume: (record) async {
              final message = await controller.resumeHeldOrder(record);
              if (!context.mounted) return;
              Navigator.of(context).pop(true);
              if (message != null && mounted) {
                _showPopupMessage(
                  title: l10n.posHeldResumedTitle,
                  message: message,
                  tone: FeedbackTone.success,
                );
              }
            },
            onDiscard: (record) async {
              // Phase C2 — confirm, then delete locally + void the server
              // mirror so it leaves every terminal's held list.
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(l10n.posHeldDiscardConfirmTitle),
                  content: Text(
                    l10n.posHeldDiscardConfirmMessage(record.orderReference),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(l10n.posHeldKeepButton),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(l10n.posHeldDiscardButton),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              final message = await controller.discardHeldOrder(record);
              if (!context.mounted) return;
              Navigator.of(context).pop(false);
              if (mounted) {
                _showPopupMessage(
                  title: l10n.posHeldDiscardedTitle,
                  message: message,
                  tone: FeedbackTone.warning,
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
    final l10n = L10n.of(context);
    // Branch-wide history (cross-device) from the server when online; fall back
    // to the device-local store offline. This is what lets a freshly-paired or
    // second device at the branch see prior orders rung on other devices.
    try {
      final serverOrders = await ref
          .read(apiServiceProvider)
          .fetchBranchOrders();
      controller.applyServerOrderHistory(serverOrders);
    } catch (_) {
      await controller.refreshOrderHistory();
    }
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.posHistoryTitle,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _StorageOverlayShell(
          title: l10n.posHistoryTitle,
          subtitle: l10n.posHistorySubtitle,
          child: _OrderHistoryPanel(
            records: controller.orderHistory,
            onReversal: (record) async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CardReversalScreen(
                    controller: createMachineReversalController(
                      ref,
                      header:
                          controller.receiptTemplate?.headerLines ?? const [],
                      reference:
                          record.snapshot.staffReference ??
                          record.orderNumber.toString(),
                      receipt: record.snapshot.receiptNumber,
                    ),
                    orderUuid: record.snapshot.serverOrderUuid.isEmpty
                        ? record.id
                        : record.snapshot.serverOrderUuid,
                    operatorName:
                        ref.read(sessionServiceProvider).staff?.name ?? '',
                    voidReasons: [
                      for (final reason in controller.voidReasons)
                        {
                          'id': reason.id,
                          'name':
                              Localizations.localeOf(context).languageCode ==
                                  'ar'
                              ? reason.nameAr ?? reason.name
                              : reason.name,
                        },
                    ],
                  ),
                ),
              );
              final refreshed = await ref
                  .read(apiServiceProvider)
                  .fetchBranchOrders();
              controller.applyServerOrderHistory(refreshed);
              if (mounted) setState(() {});
            },
            onRegisterManager: _registerManagerFingerprint,
            onPrint: (record) async {
              final printed = await controller.printHistoricalReceipt(record);
              if (!mounted) return;
              // Phase G4 — no false-success popup; the failure alert comes
              // through the throttled onPrintFailed channel.
              if (printed) {
                _showPopupMessage(
                  title: l10n.posHistoryReceiptPrintedTitle,
                  message: l10n.posHistoryReceiptPrintedMessage(
                    record.orderNumber,
                  ),
                  tone: FeedbackTone.success,
                );
              }
            },
            onPrintKitchen: (record) => _handleKitchenTicketReprint(record),
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

  /// Phase C1 — kitchen-ticket reprint, manager-gated (blueprint §6.10:
  /// "kitchen ticket reprint requires Manager permission"; the customer
  /// receipt reprint stays free).
  Future<void> _handleKitchenTicketReprint(OrderHistoryRecord record) async {
    final l10n = L10n.of(context);
    final ok = await _authorizeManager(
      subtitle: l10n.posKitchenReprintSubtitle,
      description: l10n.posKitchenReprintDescription(record.orderNumber),
    );
    if (!mounted) return;
    if (!ok) {
      _showPopupMessage(
        title: l10n.posKitchenApprovalRequiredTitle,
        message: l10n.posKitchenApprovalDeniedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final printed = await controller.printHistoricalKitchenTicket(record);
    if (!mounted || !printed) return; // failure surfaces via onPrintFailed
    _showPopupMessage(
      title: l10n.posKitchenTicketPrintedTitle,
      message: l10n.posKitchenTicketPrintedMessage(record.orderNumber),
      tone: FeedbackTone.success,
    );
  }

  /// Phase G4 — staff alert for a failed print, throttled so a dead printer
  /// during a rush shows ONE popup per window, not one per order (the popup
  /// slot is shared with payment feedback). The sale/hold itself is never
  /// affected — printing is fail-safe by design.
  DateTime? _lastPrintFailureAlertAt;

  void _handlePrintFailed(String jobKind) {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastPrintFailureAlertAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _lastPrintFailureAlertAt = now;

    final l10n = L10n.of(context);
    final (title, message, tone) = switch (jobKind) {
      'kitchen' => (
        l10n.posPrintFailedKitchenTitle,
        l10n.posPrintFailedKitchenBody,
        FeedbackTone.warning,
      ),
      'shift' => (
        l10n.posPrintFailedShiftTitle,
        l10n.posPrintFailedShiftBody,
        FeedbackTone.error,
      ),
      _ => (
        l10n.posPrintFailedReceiptTitle,
        l10n.posPrintFailedReceiptBody,
        FeedbackTone.error,
      ),
    };
    _showPopupMessage(title: title, message: message, tone: tone);
  }

  Future<void> _registerManagerFingerprint() async {
    final l10n = L10n.of(context);
    final registered = await _showFingerprintAuthorizationOverlay(
      title: l10n.posManagerRegisterFingerprintTitle,
      message: l10n.posManagerRegisterSensorMessage,
      action: _managerAuthorization.registerManagerFingerprint,
    );
    if (!mounted) return;

    _showPopupMessage(
      title: registered
          ? l10n.posManagerRegisteredTitle
          : l10n.posManagerRegistrationNotCompletedTitle,
      message: registered
          ? l10n.posManagerRegisteredMessage
          : l10n.posManagerNotRegisteredMessage,
      tone: registered ? FeedbackTone.success : FeedbackTone.warning,
    );
  }

  Future<void> _handleOrderCancellationRequest({
    required BuildContext historyDialogContext,
    required OrderHistoryRecord record,
  }) async {
    final l10n = L10n.of(context);
    // v2 #14 — company policy gate: only allowed staff positions may cancel an
    // order at the POS (on top of the manager-fingerprint step below).
    final position = ref.read(sessionServiceProvider).staff?.position;
    if (!controller.positionCanCancelOrders(position)) {
      if (historyDialogContext.mounted) {
        Navigator.of(historyDialogContext).pop();
      }
      _showPopupMessage(
        title: l10n.posCancelReqNotAllowedTitle,
        message: l10n.posCancelReqNotAllowedMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    // P-F1 — fingerprint with manager-PIN fallback.
    final authorized = await _authorizeManager(
      subtitle: l10n.posCancelReqUnlockMessage,
    );
    if (!mounted) return;

    if (!authorized) {
      if (historyDialogContext.mounted) {
        Navigator.of(historyDialogContext).pop();
      }
      _showPopupMessage(
        title: l10n.posCancelReqLockedTitle,
        message: l10n.posManagerFingerprintNotApprovedMessage,
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
      title: message.contains('fully')
          ? l10n.posCancelReqOrderCanceledTitle
          : l10n.posCancelReqItemsCanceledTitle,
      message: message,
      tone: FeedbackTone.success,
    );
  }

  /// P-F1 — THE manager-authorization gate, used by every sensitive flow
  /// (comp, gift, cancel, reprints, approval-required discounts, reports):
  /// fingerprint first when one is registered (works offline), then a
  /// manager-PIN fallback verified by pos_api against the merchant's
  /// manager_approval_positions policy (online-only). A device with no
  /// registered fingerprint goes straight to the PIN dialog.
  Future<bool> _authorizeManager({
    String? subtitle,
    String? description,
  }) async {
    if (await _managerAuthorization.isManagerRegistered()) {
      if (!mounted) return false;
      final ok = await _managerAuthorization.authenticateManagerApproval(
        subtitle: subtitle,
        description: description,
      );
      if (ok) return true;
      if (!mounted) return false;
    }
    if (!mounted) return false;
    return _openManagerPinDialog();
  }

  Future<bool> _openManagerPinDialog() async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ManagerPinDialog(api: ref.read(apiServiceProvider)),
    );
    return approved ?? false;
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
      barrierLabel: L10n.of(context).posCancelReqDialogTitle,
      barrierColor: Colors.black.withValues(alpha: 0.36),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _OrderCancellationPage(
          record: record,
          // P-F1 — server-history records void whole-order only (the wire has
          // no cross-device partial cancel).
          fullOrderOnly: record.fromServer,
          voidReasons: controller.voidReasons,
          onSubmit:
              ({
                required bool cancelFullOrder,
                required Set<int> itemIndexes,
                VoidReasonRef? voidReason,
              }) {
                return controller.cancelCompletedOrder(
                  record,
                  cancelFullOrder: cancelFullOrder,
                  itemIndexes: itemIndexes,
                  voidReason: voidReason,
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
    final l10n = L10n.of(context);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: l10n.posSearchProductsTitle,
        initialValue: controller.productSearchQuery,
        hintText: l10n.posSearchProductsHint,
      ),
    );

    if (value == null) return;
    controller.setProductSearchQuery(value);
  }

  /// P-F3 — when the merchant runs MORE THAN ONE active earn program (e.g. a
  /// stamp card AND points), ask which one(s) this order earns under — the
  /// customer's pick. Asked once per attached customer per order; cancel or
  /// a single-program merchant keeps the earn-under-all default.
  Future<void> _maybePickEarnPrograms() async {
    final customer = controller.selectedCustomer;
    if (customer == null) return;
    if (controller.selectedEarnRuleIds != null) return; // already chosen
    final rules = controller.loyaltyRules.where((r) => r.isActive).toList();
    if (rules.length < 2) return;

    final picked = await showDialog<List<int>>(
      context: context,
      builder: (_) =>
          _EarnProgramPickerDialog(rules: rules, customer: customer),
    );
    if (!mounted || picked == null) return;
    controller.setSelectedEarnRules(picked);
  }

  /// P-F2 — the customer Details button: resolve the customer (the attached
  /// one, else look the typed number up), refresh the full profile from the
  /// server when reachable, attach them to the order, and open the details
  /// dialog (plates to pick from + per-rule loyalty + redeem).
  Future<void> _openCustomerDetails() async {
    if (_liveTable || _workspace?.dineIn == true) {
      await _adjustLiveBill('customer');
      return;
    }
    final l10n = L10n.of(context);
    CustomerSearchResult? customer = controller.selectedCustomer;
    final q = _customerNumberController.text.trim();

    if (customer == null && q.isNotEmpty) {
      List<CustomerSearchResult> matches;
      try {
        matches = await ref.read(apiServiceProvider).searchCustomers(q);
      } catch (_) {
        matches = controller.searchCachedCustomers(q);
      }
      if (!mounted) return;
      for (final c in matches) {
        if (c.phone == q) {
          customer = c;
          break;
        }
      }
      customer ??= matches.isNotEmpty ? matches.first : null;
    }
    if (customer == null) {
      _showPopupMessage(
        title: l10n.posCustomerNotFoundTitle,
        message: l10n.posCustomerNotFoundMessage(q),
        tone: FeedbackTone.info,
      );
      return;
    }

    // Freshest profile (latest plates + balances) when the server answers;
    // otherwise keep the search/cache copy we already hold.
    var profile = customer;
    try {
      final fresh = await ref
          .read(apiServiceProvider)
          .fetchCustomerDetails(profile.id);
      if (fresh != null) profile = fresh;
    } catch (_) {}
    if (!mounted) return;

    // Viewing details attaches the customer (loyalty earn rides the order).
    controller.attachCustomer(profile);
    setState(
      () => _customerNumberController.text = controller.customerReferenceNumber,
    );

    final action = await showDialog<String>(
      context: context,
      builder: (_) => _CustomerDetailsDialog(
        customer: profile,
        rules: controller.loyaltyRules,
        currentPlate: controller.vehiclePlateNumber,
      ),
    );
    if (!mounted || action == null) {
      if (mounted) await _maybePickEarnPrograms();
      return;
    }
    if (action == 'redeem') {
      await _openLoyaltyRedeem();
    } else if (action.startsWith('plate:')) {
      final plate = action.substring('plate:'.length);
      controller.setVehiclePlateNumber(plate);
      setState(() => _vehiclePlateController.text = plate);
      _showPopupMessage(
        title: l10n.posPaymentVehiclePlateLabel,
        message: plate,
        tone: FeedbackTone.success,
      );
    }
    if (mounted) await _maybePickEarnPrograms();
  }

  /// P-F2 — search by vehicle plate: who is linked to this car? (A plate can
  /// belong to several customers and vice versa.) Picking a match attaches
  /// the customer AND sets the plate on the order.
  Future<void> _openPlateCustomerSearch() async {
    if (_liveTable || _workspace?.dineIn == true) {
      await _adjustLiveBill('customer');
      return;
    }
    final l10n = L10n.of(context);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: l10n.posPlateSearchTitle,
        initialValue: _vehiclePlateController.text,
        hintText: l10n.posPlateHint,
      ),
    );
    if (value == null || !mounted) return;
    final plate = value.trim().toUpperCase();
    if (plate.isEmpty) return;

    List<CustomerSearchResult> matches;
    try {
      matches = await ref.read(apiServiceProvider).searchCustomers(plate);
    } catch (_) {
      matches = controller.searchCachedCustomers(plate);
    }
    if (!mounted) return;
    // The endpoint also matches names/phones — keep true plate matches when
    // any exist.
    final plateMatches = matches
        .where((c) => c.plates.any((p) => p.contains(plate)))
        .toList();
    final candidates = plateMatches.isNotEmpty ? plateMatches : matches;
    if (candidates.isEmpty) {
      _showPopupMessage(
        title: l10n.posCustomerNotFoundTitle,
        message: l10n.posPlateSearchNoMatches(plate),
        tone: FeedbackTone.info,
      );
      return;
    }

    CustomerSearchResult? picked;
    if (candidates.length == 1) {
      picked = candidates.single;
    } else {
      picked = await showDialog<CustomerSearchResult>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(l10n.posPlateSearchPickCustomer(plate)),
          children: [
            for (final c in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(c),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_rounded),
                  title: Text(c.name),
                  subtitle: Text(
                    [
                      if (c.phone.isNotEmpty) c.phone,
                      if (c.plates.isNotEmpty) c.plates.join(' · '),
                    ].join('  ·  '),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (picked == null || !mounted) return;

    controller.attachCustomer(picked);
    controller.setVehiclePlateNumber(plate);
    setState(() {
      _customerNumberController.text = controller.customerReferenceNumber;
      _vehiclePlateController.text = plate;
    });
    _showPopupMessage(
      title: l10n.posCustomerAttachedTitle,
      message: l10n.posCustomerAttachedSummary(
        picked.name,
        _loyaltySummary(l10n, picked),
      ),
      tone: FeedbackTone.success,
    );
    await _maybePickEarnPrograms();
  }

  Future<void> _openCustomerSearch() async {
    if (_liveTable || _workspace?.dineIn == true) {
      await _adjustLiveBill('customer');
      return;
    }
    final l10n = L10n.of(context);
    final result = await showDialog<CustomerSearchResult>(
      context: context,
      builder: (_) => _CustomerSearchDialog(
        search: (q) async {
          try {
            return await ref.read(apiServiceProvider).searchCustomers(q);
          } catch (_) {
            // Offline / search error → fall back to the cached customer slice
            // (with cached loyalty), so attach + redeem still work offline.
            return controller.searchCachedCustomers(q);
          }
        },
      ),
    );
    if (!mounted || result == null) return;
    controller.attachCustomer(result);
    setState(
      () => _customerNumberController.text = controller.customerReferenceNumber,
    );
    final pts = controller.activeEarnRule != null
        ? result.pointsForRule(controller.activeEarnRule!.id)
        : 0;
    _showPopupMessage(
      title: l10n.posCustomerAttachedTitle,
      message: pts > 0
          ? l10n.posCustomerAttachedWithPoints(result.name, pts)
          : result.name,
      tone: FeedbackTone.success,
    );
    await _maybePickEarnPrograms();
  }

  Future<void> _openCustomerNumberKeyboard() async {
    if (_liveTable || _workspace?.dineIn == true) {
      await _adjustLiveBill('customer');
      return;
    }
    final l10n = L10n.of(context);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: l10n.posCustomerNumberTitle,
        initialValue: _customerNumberController.text,
        hintText: l10n.posCustomerNumberHint,
        numbersOnly: true,
      ),
    );

    if (value == null) return;

    setState(() {
      _customerNumberController.text = value;
    });

    // Fetch-on-Enter (#3): look the number up (phone), attach the customer so
    // their loyalty loads, and surface the balances. Falls back to the offline
    // cache, then to keeping the value as a bare reference.
    final q = value.trim();
    if (q.isEmpty) {
      controller.setCustomerReferenceNumber('');
      return;
    }

    List<CustomerSearchResult> matches;
    try {
      matches = await ref.read(apiServiceProvider).searchCustomers(q);
    } catch (_) {
      matches = controller.searchCachedCustomers(q);
    }
    if (!mounted) return;

    CustomerSearchResult? match;
    for (final c in matches) {
      if (c.phone == q) {
        match = c;
        break;
      }
    }
    match ??= matches.isNotEmpty ? matches.first : null;

    if (match == null) {
      controller.setCustomerReferenceNumber(value);
      _showPopupMessage(
        title: l10n.posCustomerNotFoundTitle,
        message: l10n.posCustomerNotFoundMessage(q),
        tone: FeedbackTone.info,
      );
      return;
    }

    controller.attachCustomer(match);
    setState(
      () => _customerNumberController.text = controller.customerReferenceNumber,
    );
    _showPopupMessage(
      title: l10n.posCustomerAttachedTitle,
      message: l10n.posCustomerAttachedSummary(
        match.name,
        _loyaltySummary(l10n, match),
      ),
      tone: FeedbackTone.success,
    );
    await _maybePickEarnPrograms();
  }

  /// A short loyalty summary (total points + stamps across rules) for the
  /// attach confirmation — the "check loyalty" readout.
  String _loyaltySummary(L10n l10n, CustomerSearchResult c) {
    final pts = c.loyalty.fold<int>(0, (s, b) => s + b.points);
    final stamps = c.loyalty.fold<int>(0, (s, b) => s + b.stamps);
    final parts = <String>[];
    if (pts > 0) parts.add(l10n.posLoyaltySummaryPoints(pts));
    if (stamps > 0) parts.add(l10n.posLoyaltySummaryStamps(stamps));
    return parts.isEmpty ? l10n.posLoyaltyNoneYet : parts.join('  ·  ');
  }

  Future<void> _openVehiclePlateKeyboard() async {
    final l10n = L10n.of(context);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: l10n.posPlateTitle,
        initialValue: _vehiclePlateController.text,
        hintText: l10n.posPlateHint,
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
    final workspace = _workspace;
    if (workspace != null) {
      workspace.returnToList = false;
      await workspace.requestClose();
      if (_workspace != null) {
        workspace.returnToList = true;
        return;
      }
    }
    await controller.selectOrderType(type);
    if (!mounted) return;
    // Entering delivery: pick the provider first — its prices drive the menu.
    if (type == OrderType.delivery &&
        controller.selectedDeliveryProviderId == null) {
      await _openDeliveryProviderPicker();
    }
  }

  Future<void> _openDeliveryProviderPicker() async {
    final l10n = L10n.of(context);
    final providers = controller.deliveryProviders;
    if (providers.isEmpty) {
      _showPlaceholderMessage(
        l10n.posMsgNoDeliveryProvidersTitle,
        l10n.posMsgNoDeliveryProvidersMessage,
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
    if (ref.read(tableSessionsModeProvider) == 'live') {
      final value = await showTableSearchKeyboard(
        context,
        initialValue: controller.diningTableSearchQuery,
        onChanged: _updateTableSearch,
      );
      if (!mounted) return;
      if (value != null) controller.setDiningTableSearchQuery(value);
      _updateTableSearch();
      return;
    }
    final l10n = L10n.of(context);
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _InAppKeyboardDialog(
        title: l10n.posSearchTablesTitle,
        initialValue: controller.diningTableSearchQuery,
        hintText: l10n.posSearchTablesHint,
      ),
    );

    if (value == null) return;
    controller.setDiningTableSearchQuery(value);
  }

  /// Gap sweep G2 — long-press actions for an OCCUPIED table: open it,
  /// move the party to a free table, or merge its order into another
  /// occupied table.
  Future<void> _openDiningTableActionsSheet(
    DiningTableDefinition table,
    DiningTableSession session,
  ) async {
    final l10n = L10n.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_restaurant_rounded),
              title: Text(l10n.posDiningActionsTitle(table.name)),
              subtitle: Text(
                '${SunmiReceiptService.money(session.total)} · ${_formatOccupancyDuration(session.occupiedAt)}',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.login_rounded),
              title: Text(l10n.posDiningActionOpen),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (_hasServerBillFor(table.id))
              ListTile(
                key: const ValueKey('table-action-customer-bill'),
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(l10n.tableCustomerBillTitle),
                onTap: () => Navigator.pop(ctx, 'customer_bill'),
              ),
            if (!session.hasJoinedTables &&
                session.total == 0 &&
                !(session.draft?.items.isNotEmpty ?? false))
              ListTile(
                key: const ValueKey('table-action-clear-empty'),
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(
                  ref.read(settingsControllerProvider).language == 'ar'
                      ? 'إخلاء الجلسة الفارغة'
                      : 'Clear empty session',
                ),
                onTap: () => Navigator.pop(ctx, 'clear_empty'),
              ),
            // A joined party can't be moved piecemeal — Move only shows for a
            // standalone occupied table.
            if (!session.hasJoinedTables)
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: Text(l10n.posDiningActionMove),
                subtitle: Text(l10n.posDiningActionMoveHint),
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
            ListTile(
              leading: const Icon(Icons.call_merge_rounded),
              title: Text(l10n.posDiningActionMerge),
              subtitle: Text(l10n.posDiningActionMergeHint),
              onTap: () => Navigator.pop(ctx, 'merge'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l10n.commonCancel),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'clear_empty':
        await _clearSharedTable(table.id, emptyOnly: true);
      case 'customer_bill':
        await _openCustomerBill(table.id);
      case 'open':
        await controller.openDiningTable(table.id);
        if (mounted) setState(() => _showPaymentPage = false);
      case 'move':
        await _openTableTargetPicker(table, session, merge: false);
      case 'merge':
        await _openTableTargetPicker(table, session, merge: true);
    }
  }

  /// Pick a FREE target table — for a move (relocate the party there) or a
  /// join (pull the free table into this party's ONE bill; confirms first).
  Future<void> _openTableTargetPicker(
    DiningTableDefinition source,
    DiningTableSession sourceSession, {
    required bool merge,
  }) async {
    final l10n = L10n.of(context);
    final targets = controller.diningTableDefinitions.where((t) {
      if (t.id == source.id) return false;
      final session = controller.diningSessionFor(t.id);
      // Join AND move both target a FREE table: join pulls a free neighbour
      // into this party (one shared bill); move relocates the party to it.
      // Never join two running orders — only empty tables are offered.
      return session == null;
    }).toList();

    if (targets.isEmpty) {
      _showPopupMessage(
        title: merge ? l10n.posDiningActionMerge : l10n.posDiningActionMove,
        message: merge
            ? l10n.posDiningNoMergeTargets
            : l10n.posDiningNoFreeTables,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final targetId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
          merge ? l10n.posDiningPickMergeTarget : l10n.posDiningPickFreeTable,
        ),
        children: [
          for (final t in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t.id),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${t.name} · ${controller.floorLabelFor(t.floorId)}'),
                  if (merge)
                    Text(
                      l10n.posDiningSeats(t.seats),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || targetId == null) return;

    if (merge) {
      final targetSession = controller.diningSessionFor(targetId);
      final targetDef = targets.firstWhere((t) => t.id == targetId);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.posDiningMergeConfirmTitle),
          content: Text(
            l10n.posDiningMergeConfirmBody(
              source.name,
              SunmiReceiptService.money(sourceSession.total),
              targetDef.name,
              SunmiReceiptService.money(targetSession?.total ?? 0),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.posDiningActionMerge),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final message = merge
        ? await controller.joinDiningTables(source.id, targetId)
        : await controller.transferDiningTable(source.id, targetId);
    if (!mounted) return;
    if (message == null) {
      _showPopupMessage(
        title: merge ? l10n.posDiningActionMerge : l10n.posDiningActionMove,
        message: l10n.posDiningActionFailed,
        tone: FeedbackTone.warning,
      );
      return;
    }
    _showPopupMessage(
      title: merge
          ? l10n.posDiningTablesMergedTitle
          : l10n.posDiningTableMovedTitle,
      message: message,
      tone: FeedbackTone.success,
    );
  }

  Future<void> _openPaidDiningTableDialog(
    DiningTableDefinition table,
    DiningTableSession session,
  ) async {
    final l10n = L10n.of(context);
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
                        l10n.posDiningTablePaidTitle(table.name),
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
                  l10n.posDiningTicketPaidMessage(
                    '${session.orderNumber ?? snapshot?.orderNumber ?? '-'}',
                  ),
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
                          title: l10n.posDiningPaidTotalLabel,
                          amount: snapshot?.payableTotal ?? session.total,
                          tint: const Color(0xFFDDF5EA),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _glassInsetCard(
                        child: _fallbackAmountBlock(
                          title: l10n.posDiningFloorLabel,
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
                        label: l10n.commonClose,
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FilledActionButton(
                        label: l10n.posDiningClearTableButton,
                        onTap: () async {
                          Navigator.of(context).pop();
                          if (!await _clearSharedTable(table.id)) return;
                          if (!mounted) return;
                          _showPopupMessage(
                            title: l10n.posDiningTableClearedTitle(table.name),
                            message: l10n.posDiningTableClearedMessage(
                              table.name,
                            ),
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
  Future<void> _openDiscountDialog({
    DineInDetail? serverDetail,
    void Function(Map<String, dynamic>)? picked,
  }) async {
    if (serverDetail == null && (_liveTable || _workspace?.dineIn == true)) {
      await _adjustLiveBill('discount');
      return;
    }
    final l10n = L10n.of(context);
    final branchId = ref.read(sessionControllerProvider).branchId ?? 0;
    final now = DateTime.now();
    final applicable = controller.availableDiscounts
        .where((d) => d.isOrderScope && d.appliesAt(now, branchId: branchId))
        .toList();
    final redeem = serverDetail == null ? _redeemable() : null;
    final redeemStamp = serverDetail == null ? _redeemableStamp() : null;

    if (applicable.isEmpty && redeem == null && redeemStamp == null) {
      await _openManualDiscountDialog(
        serverDetail: serverDetail,
        picked: picked,
      );
      return;
    }

    final action =
        await showModalBottomSheet<({String type, MerchantDiscount? rule})>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.posDiscountSheetTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (redeem != null)
                  ListTile(
                    leading: const Icon(Icons.card_giftcard_rounded),
                    title: Text(l10n.posDiscountRedeemPointsOption),
                    subtitle: Text(
                      l10n.posDiscountRedeemPointsSubtitle(
                        redeem.points,
                        redeem.rule.name,
                      ),
                    ),
                    onTap: () =>
                        Navigator.pop(ctx, (type: 'redeem', rule: null)),
                  ),
                if (redeemStamp != null)
                  ListTile(
                    leading: const Icon(Icons.workspace_premium_rounded),
                    title: Text(l10n.posDiscountRedeemStampOption),
                    subtitle: Text(
                      l10n.posDiscountStampRewardSubtitle(
                        redeemStamp.stamps,
                        SunmiReceiptService.money(redeemStamp.valueOmr),
                        redeemStamp.rule.name,
                      ),
                    ),
                    onTap: () =>
                        Navigator.pop(ctx, (type: 'redeem_stamp', rule: null)),
                  ),
                for (final d in applicable)
                  ListTile(
                    leading: const Icon(Icons.local_offer_outlined),
                    title: Text(d.name),
                    subtitle: Text(
                      _discountSubtitle(l10n, d) +
                          (d.requiresManagerApproval
                              ? '  ·  ${l10n.posDiscountManagerApprovalTag}'
                              : ''),
                    ),
                    onTap: () => Navigator.pop(ctx, (type: 'rule', rule: d)),
                  ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.posDiscountCustomAmountOption),
                  onTap: () => Navigator.pop(ctx, (type: 'custom', rule: null)),
                ),
                if (serverDetail == null
                    ? controller.discount.isActive
                    : (serverDetail.bill?['manual_discount_baisas'] as int? ??
                              0) >
                          0)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(l10n.posDiscountRemoveOption),
                    onTap: () =>
                        Navigator.pop(ctx, (type: 'remove', rule: null)),
                  ),
              ],
            ),
          ),
        );

    if (!mounted || action == null) return;
    switch (action.type) {
      case 'custom':
        await _openManualDiscountDialog(
          serverDetail: serverDetail,
          picked: picked,
        );
      case 'remove':
        if (serverDetail != null) {
          picked?.call({'kind': 'discount', 'mode': 'clear'});
          return;
        }
        controller.clearDiscount();
        _showPopupMessage(
          title: l10n.posDiscountClearedTitle,
          message: l10n.posDiscountClearedMessage,
          tone: FeedbackTone.info,
        );
      case 'rule':
        await _applyMerchantDiscount(action.rule!, picked: picked);
      case 'redeem':
        await _openRedeemDialog();
      case 'redeem_stamp':
        await _redeemStamp();
    }
  }

  /// The redeemable spend-based rule for the attached customer (enough points
  /// for at least one redemption block), or null.
  ({LoyaltyRule rule, CustomerSearchResult customer, int points})?
  _redeemable() {
    final c = controller.selectedCustomer;
    if (c == null) return null;
    for (final r in controller.loyaltyRules) {
      if (!r.isActive || !r.isSpendBased) continue;
      if (r.redemptionPoints <= 0 || r.redemptionValue <= 0) continue;
      final pts = c.availablePointsForRule(r.id);
      final minNeeded = r.minRedemptionPoints > 0
          ? r.minRedemptionPoints
          : r.redemptionPoints;
      if (pts >= minNeeded && pts >= r.redemptionPoints) {
        return (rule: r, customer: c, points: pts);
      }
    }
    return null;
  }

  /// The redeemable visit_based (stamp-card) rule for the attached customer:
  /// enough stamps for one reward, with a resolvable OMR value, or null.
  ({
    LoyaltyRule rule,
    CustomerSearchResult customer,
    int stamps,
    double valueOmr,
  })?
  _redeemableStamp() {
    final c = controller.selectedCustomer;
    if (c == null) return null;
    final subtotal = controller.rawSubtotal;
    if (subtotal <= 0) return null;
    for (final r in controller.loyaltyRules) {
      if (!r.isActive || !r.isVisitBased || r.stampsRequired <= 0) continue;
      if (c.availableStampsForRule(r.id) < r.stampsRequired) continue;
      final value = _stampRewardValue(r, subtotal);
      if (value <= 0) continue;
      final capped = value > subtotal ? subtotal : value;
      return (rule: r, customer: c, stamps: r.stampsRequired, valueOmr: capped);
    }
    return null;
  }

  /// OMR value of one stamp reward: percent_off → % of [subtotal];
  /// free_product → the reward product's current catalogue price (fallback to
  /// an explicit reward_value). 0 = not redeemable on the device.
  double _stampRewardValue(LoyaltyRule r, double subtotal) {
    switch (r.rewardType) {
      case 'percent_off':
        final pct = r.rewardValue;
        if (pct <= 0) return 0;
        return subtotal * (pct > 100 ? 100 : pct) / 100.0;
      case 'free_product':
        final id = r.rewardProductId;
        if (id == null) return 0;
        final p = controller.productById(id);
        return p?.price ?? (r.rewardValue > 0 ? r.rewardValue : 0);
      default:
        return r.rewardValue > 0 ? r.rewardValue : 0;
    }
  }

  /// Confirm + apply a visit_based stamp reward (spends stampsRequired stamps
  /// for a one-off discount; the stamps ride as loyalty_redeem on pay).
  Future<void> _redeemStamp() async {
    final l10n = L10n.of(context);
    final redeem = _redeemableStamp();
    if (redeem == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.posDiscountRedeemStampOption),
        content: Text(
          l10n.posDiscountStampRewardSubtitle(
            redeem.stamps,
            SunmiReceiptService.money(redeem.valueOmr),
            redeem.rule.name,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.posLoyaltyRedeemButton),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    controller.applyLoyaltyRedemption(
      ruleId: redeem.rule.id,
      stamps: redeem.stamps,
      valueOmr: redeem.valueOmr,
      label: 'Stamp reward',
    );
    _showPopupMessage(
      title: l10n.posLoyaltyRewardRedeemedTitle,
      message: l10n.posLoyaltyStampRedeemedMessage(
        redeem.stamps,
        SunmiReceiptService.money(redeem.valueOmr),
      ),
      tone: FeedbackTone.success,
    );
  }

  /// Entry point for the payment-console "Redeem Loyalty" action: surfaces
  /// points + stamp redemption (via the discount sheet) or a helpful message.
  Future<void> _openLoyaltyRedeem() async {
    if (_liveTable) return;
    final l10n = L10n.of(context);
    if (controller.selectedCustomer == null) {
      _showPopupMessage(
        title: l10n.posLoyaltyNoCustomerTitle,
        message: l10n.posLoyaltyNoCustomerMessage,
        tone: FeedbackTone.info,
      );
      return;
    }
    if (_redeemable() == null && _redeemableStamp() == null) {
      _showPopupMessage(
        title: l10n.posLoyaltyNothingToRedeemTitle,
        message: l10n.posLoyaltyNothingToRedeemMessage,
        tone: FeedbackTone.info,
      );
      return;
    }
    await _openDiscountDialog();
  }

  Future<void> _openRedeemDialog() async {
    final l10n = L10n.of(context);
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
        title: l10n.posLoyaltyCannotRedeemTitle,
        message: l10n.posLoyaltyCannotRedeemMessage,
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
      title: l10n.posLoyaltyPointsRedeemedTitle,
      message: l10n.posLoyaltyPointsRedeemedMessage(
        blocks * rule.redemptionPoints,
        SunmiReceiptService.money(blocks * rule.redemptionValue),
      ),
      tone: FeedbackTone.success,
    );
  }

  String _discountSubtitle(L10n l10n, MerchantDiscount d) =>
      d.amountType == 'percent'
      ? l10n.posDiscountPercentOff((d.percent ?? 0).toStringAsFixed(0))
      : l10n.posDiscountAmountOff(
          SunmiReceiptService.money(d.fixedAmount ?? 0),
        );

  Future<void> _applyMerchantDiscount(
    MerchantDiscount d, {
    void Function(Map<String, dynamic>)? picked,
  }) async {
    final l10n = L10n.of(context);
    if (d.requiresManagerApproval) {
      final ok = await _authorizeManager(
        subtitle: l10n.posDiscountApproveSubtitle,
        description: l10n.posDiscountApproveDescription(d.name),
      );
      if (!mounted) return;
      if (!ok) {
        _showPopupMessage(
          title: l10n.posDiscountApprovalRequiredTitle,
          message: l10n.posDiscountApprovalDeniedMessage(d.name),
          tone: FeedbackTone.warning,
        );
        return;
      }
    }
    if (picked != null) {
      picked({
        'kind': 'discount',
        'mode': 'rule',
        'discount_id': d.id,
        if (d.requiresManagerApproval) 'authorized_by': 'Manager',
      });
      return;
    }
    controller.applyDiscount(d.toConfiguration());
    _showPopupMessage(
      title: l10n.posDiscountAppliedTitle,
      message: l10n.posDiscountAppliedMessage(d.name),
      tone: FeedbackTone.success,
    );
  }

  Future<void> _openManualDiscountDialog({
    DineInDetail? serverDetail,
    void Function(Map<String, dynamic>)? picked,
  }) async {
    if (serverDetail == null && (_liveTable || _workspace?.dineIn == true)) {
      await _adjustLiveBill('discount');
      return;
    }
    final l10n = L10n.of(context);
    final value = await showDialog<DiscountConfiguration>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _DiscountDialog(
        initialDiscount: serverDetail == null
            ? controller.discount
            : const DiscountConfiguration(),
      ),
    );

    if (value == null) return;
    if (serverDetail != null) {
      picked?.call(
        !value.isActive
            ? {'kind': 'discount', 'mode': 'clear'}
            : {
                'kind': 'discount',
                'mode': value.kind == DiscountKind.percentage
                    ? 'percent'
                    : 'fixed',
                if (value.kind == DiscountKind.percentage)
                  'percent_bp': (value.value * 100).round()
                else
                  'amount_baisas': (value.value * 1000).round(),
                'label': value.label.isEmpty
                    ? l10n.posDiscountDefaultLabel
                    : value.label,
                if (value.reason.isNotEmpty) 'reason': value.reason,
              },
      );
      return;
    }
    if (value.isActive) {
      controller.applyDiscount(value);
      _showPopupMessage(
        title: l10n.posDiscountAppliedTitle,
        message: l10n.posDiscountAppliedMessage(
          value.label.isEmpty ? l10n.posDiscountDefaultLabel : value.label,
        ),
        tone: FeedbackTone.success,
      );
    } else {
      controller.clearDiscount();
      _showPopupMessage(
        title: l10n.posDiscountClearedTitle,
        message: l10n.posDiscountClearedMessage,
        tone: FeedbackTone.info,
      );
    }
  }

  Future<void> _openSplitBillDialog() async {
    final l10n = L10n.of(context);
    if (controller.hasRecordedSplitPayments) {
      _showPopupMessage(
        title: l10n.posSplitInProgressTitle,
        message: l10n.posSplitInProgressMessage,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final result = await showDialog<_SplitBillResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SplitBillDialog(
        initialSplitCount: controller.splitCount,
        initialPlan: controller.splitPlanAmounts,
        total: controller.total,
      ),
    );

    if (result == null) return;

    if (result.splitCount <= 1) {
      controller.clearSplit();
      _showPopupMessage(
        title: l10n.posSplitClearedTitle,
        message: l10n.posSplitClearedMessage,
        tone: FeedbackTone.info,
      );
    } else if (result.customAmounts != null) {
      // A rejected plan (e.g. the cart changed under the open dialog) must
      // never be announced as active — the next tender would charge the full
      // total while the cashier believes a split is running.
      final applied = controller.setSplitPlan(result.customAmounts!);
      if (applied) {
        _showPopupMessage(
          title: l10n.posSplitReadyTitle,
          message: l10n.posSplitCustomReadyMessage(
            result.splitCount,
            SunmiReceiptService.money(controller.activePaymentBaseTotal),
          ),
          tone: FeedbackTone.success,
        );
      } else {
        _showPopupMessage(
          title: l10n.posSplitDlgTitle,
          message: l10n.posSplitPlanRejectedMessage,
          tone: FeedbackTone.warning,
        );
      }
    } else {
      controller.setSplitCount(result.splitCount);
      _showPopupMessage(
        title: l10n.posSplitReadyTitle,
        message: l10n.posSplitReadyMessage(
          result.splitCount,
          SunmiReceiptService.money(controller.activePaymentBaseTotal),
        ),
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
    final l10n = L10n.of(context);
    return switch (controller.paymentStatus) {
      'Paid' =>
        controller.selectedPaymentMethod == 'Cash'
            ? l10n.posMsgCashPaymentCompleteTitle
            : l10n.posMsgPaymentApprovedTitle,
      'Split payment pending' => l10n.posMsgSplitPaymentRecordedTitle,
      'Payment canceled' => l10n.posMsgPaymentCanceledTitle,
      'Payment failed' => l10n.posMsgPaymentFailedTitle,
      _ => l10n.posMsgPaymentUpdateTitle,
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
          // Phase C4 — merchant Arabic names, display-only (the English
          // title/label stay the identity in selections and payloads).
          titleAr: group.nameAr ?? '',
          multiSelect: group.multiSelect,
          // Phase B — merchant-configured constraints + defaults.
          requiredSelection: group.isRequired,
          minSelections: group.effectiveMin,
          maxSelections: group.maxSelections,
          defaultOptionIds: {
            for (final option in group.options)
              if (option.isDefault) option.id.toString(),
          },
          options: group.options
              .map(
                (option) => _ModifierOptionDefinition(
                  id: option.id.toString(),
                  label: option.label,
                  labelAr: option.labelAr ?? '',
                  price: option.priceDelta,
                  // P-G3 — grey the option when its linked product is
                  // sold out at this branch.
                  soldOut: controller.isAddonOptionUnavailable(option),
                ),
              )
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
    await showDialog<_CartItemCustomizationResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomizeCartItemDialog(
        item: item,
        groups: _resolveModifierGroups(item.product),
        apply: (result) => _applyCartCustomization(item, result),
      ),
    );
  }

  Future<bool> _applyCartCustomization(
    CartItem item,
    _CartItemCustomizationResult result,
  ) async {
    if (!mounted || !controller.cart.contains(item)) return false;
    if (_liveTable) {
      final before = buildTableRoundLines([item]);
      final after = buildTableRoundLines([
        CartItem(
          product: item.product,
          qty: item.qty,
          modifiers: result.modifiers,
          notes: result.notes,
        ),
      ]);
      final changed =
          before.isNotEmpty &&
          after.isNotEmpty &&
          tableLineFingerprint(before.single) !=
              tableLineFingerprint(after.single);
      if (changed && !await _approveSentReduction(item, item.qty)) return false;
    }
    controller.updateCartItemCustomization(
      item,
      modifiers: result.modifiers,
      notes: result.notes,
    );
    await _refreshTableSentState();
    return true;
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

  List<int> _quickCashAmounts({double? total}) {
    final base = (total ?? controller.activePaymentBaseTotal).ceil();
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
    final l10n = L10n.of(context);
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
                  Text(
                    l10n.posCharityConfirmRoundUpTitle,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF16242B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.posCharityConfirmRoundUpBody,
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
                            title: l10n.posCharityOrderTotal,
                            amount: controller.activePaymentBaseTotal,
                            tint: const Color(0xFFE9F7FB),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _glassInsetCard(
                          child: _fallbackAmountBlock(
                            title: l10n.posCharityRoundUp,
                            amount: controller.charityRoundUpAmount,
                            tint: const Color(0xFFFCEBC6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _glassInsetCard(
                          child: _fallbackAmountBlock(
                            title: l10n.posCharityNewTotal,
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
                            label: l10n.posCharityKeepOriginalTotal,
                            filled: false,
                            onTap: () =>
                                controller.confirmCharityRoundUp(false),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildCharityFallbackAction(
                            label: l10n.posCharityRoundUpYes,
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
                      label: l10n.commonCancel,
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
    final l10n = L10n.of(context);
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
              // Escalated (2+ min unanswered): a danger ring pulls a
              // distracted cashier back — the prompt never self-cancels,
              // because the customer's card may genuinely have been charged.
              border: controller.pendingReconEscalated
                  ? Border.all(color: const Color(0xFFC0392B), width: 3)
                  : null,
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
                        color: controller.pendingReconEscalated
                            ? const Color(0xFFFAD7D2)
                            : const Color(0xFFFCEBC6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: controller.pendingReconEscalated
                            ? const Color(0xFFC0392B)
                            : const Color(0xFFB9770E),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        l10n.posReconCardNotConfirmedTitle,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16242B),
                        ),
                      ),
                    ),
                  ],
                ),
                if (controller.pendingReconEscalated) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAD7D2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.posReconStillWaitingBanner,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7B241C),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.posReconCardNotConfirmedBody(
                    SunmiReceiptService.money(
                      controller.pendingReconciliationAmount,
                    ),
                  ),
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
                        label: l10n.commonCancel,
                        filled: false,
                        onTap: () => controller.resolvePendingReconciliation(
                          PendingReconChoice.cancel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _pendingReconButton(
                        label: l10n.commonRetry,
                        filled: false,
                        onTap: () => controller.resolvePendingReconciliation(
                          PendingReconChoice.retry,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: _pendingReconButton(
                    label: l10n.posReconMarkPaidPending,
                    filled: true,
                    onTap: () => controller.resolvePendingReconciliation(
                      PendingReconChoice.record,
                    ),
                  ),
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
    final l10n = L10n.of(context);
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
                    ? l10n.posPaymentPreparingTitle
                    : controller.paymentOverlayTitle,
                message: controller.displayNote.isEmpty
                    ? l10n.posPaymentPreparingMessage
                    : controller.displayNote,
                badge: l10n.posPaymentSecureCardBadge,
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
    final l10n = L10n.of(context);
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
                title: l10n.posPaymentRecordingCashTitle,
                message: controller.displayNote.isEmpty
                    ? l10n.posPaymentRecordingCashMessage
                    : controller.displayNote,
                badge: l10n.posPaymentCashCheckoutBadge,
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

  Future<QrCheckoutController> _newQrCheckout() async {
    final api = ref.read(apiServiceProvider);
    final session = ref.read(sessionServiceProvider);
    final gateway = ApiCheckoutGateway(
      api: api,
      mutationGuard: controller.assertNoPendingCombine,
      currentScope: () => quickDeviceScope(
        api.quickOrderBaseUrl,
        session.companyId,
        session.branchId,
        session.kioskId,
      ),
      location: ref.read(qrLocationProvider).currentFix,
      legacyGuard: (orderUuid) async {
        await controller.assertNoPendingCombine();
        if (ref
                .read(qrSettlementCoordinatorProvider)
                .pendingManagerRecoveries
                .isNotEmpty ||
            await ref
                .read(orderSyncRepositoryProvider)
                .hasUnresolvedStandaloneQrPay(orderUuid)) {
          throw StateError('An earlier QR settlement requires recovery.');
        }
        final requests = await SqliteQrQuickStore.open(
          quickDeviceScope(
            api.quickOrderBaseUrl,
            session.companyId,
            session.branchId,
            session.kioskId,
          ),
        );
        if ((await requests.load()).any((r) => r.orderUuid == orderUuid)) {
          throw StateError('Resolve the pending item addition before payment.');
        }
        final tableRequests = await SqliteDineInStore.open(
          quickDeviceScope(
            api.quickOrderBaseUrl,
            session.companyId,
            session.branchId,
            session.kioskId,
          ),
        );
        if (await tableRequests.blocksBill(orderUuid)) {
          throw StateError('Resolve the saved table round before payment.');
        }
      },
    );
    final store = await SqliteCheckoutStore.open(gateway.scope);
    late QrCheckoutController checkout;
    checkout = QrCheckoutController(
      gateway: gateway,
      store: store,
      projectReceipt: (snapshot, attempt) => projectMachineCheckoutReceipt(
        ServerReceiptHistory(
          debugOrderStorageOverride ?? LocalOrderStorageService.instance,
        ),
        snapshot,
        attempt,
      ),
      authorizeGift: () async {
        if (!mounted ||
            !await _authorizeManager(
              subtitle: L10n.of(context).posPayGiftManagerApprovalMessage,
            )) {
          return false;
        }
        if (!mounted) return false;
        return await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: Text(L10n.of(context).posPayGiftConfirmTitle),
                content: Text(
                  L10n.of(context).posPayGiftConfirmMessage(
                    SunmiReceiptService.money(checkout.total / 1000),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text(L10n.of(context).commonCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(L10n.of(context).posPaymentGift),
                  ),
                ],
              ),
            ) ??
            false;
      },
      captureBank: (amount) {
        gateway.checkScope();
        return confirmCheckoutBank(context, amount);
      },
      captureCard: (amount) async {
        gateway.checkScope();
        final result = await ref
            .read(qrCardTerminalProvider)
            .captureBaisas(amount);
        final state = result.isSuccess && !result.isCanceled
            ? CheckoutCaptureState.approved
            : result.isCanceled && !result.isSuccess
            ? CheckoutCaptureState.cancelled
            : result.failurePhase == MosambeeFailurePhase.preDispatch
            ? CheckoutCaptureState.notDispatched
            : CheckoutCaptureState.uncertain;
        return CheckoutCapture(
          state,
          evidence: {
            if (result.softposReference != null)
              'softpos_reference': result.softposReference,
            if (result.softposAuthCode != null)
              'softpos_auth_code': result.softposAuthCode,
            'bank_response': result.payload,
          },
        );
      },
    );
    return checkout;
  }

  Future<void> _launchQrCheckout(String? uuid) async {
    if (_normalQrCheckoutOpen ||
        controller.isProcessingPayment ||
        controller.hasRecordedSplitPayments ||
        controller.showPaymentLaunchOverlay) {
      return;
    }
    _normalQrCheckoutOpen = true;
    _applyAudienceGate();
    QrCheckoutController? checkout;
    VoidCallback? displayListener;
    try {
      checkout = await _newQrCheckout();
      if (!mounted) return;
      final payment = checkout;
      final workspace = _workspace;
      if (workspace != null) {
        displayListener = () {
          if (!mounted ||
              !identical(_workspace, workspace) ||
              payment.snapshot == null) {
            return;
          }
          unawaited(
            PresentationService.instance.showWorkspaceBill(
              workspace,
              WorkspaceBill({
                ...payment.snapshot!.order,
                if (payment.phase == CheckoutPhase.paid) 'status': 'paid',
              }),
              stale:
                  payment.phase == CheckoutPhase.attention ||
                  payment.phase == CheckoutPhase.pending,
              arabic: ref.read(settingsControllerProvider).language == 'ar',
            ),
          );
        };
        payment.addListener(displayListener);
      }
      unawaited(payment.open(uuid));
      await showQrCheckout(payment);
    } catch (_) {
      if (mounted) {
        _showPopupMessage(
          title: checkoutText(context, 'title'),
          message: checkoutText(context, 'unavailable'),
          tone: FeedbackTone.warning,
        );
      }
    } finally {
      if (displayListener != null) checkout?.removeListener(displayListener);
      checkout?.dispose();
      _normalQrCheckoutOpen = false;
      if (mounted) {
        _applyAudienceGate();
        // onExit may have attempted retirement while this route still owned
        // checkout. Retry after its guard is released, in the same session.
        setState(() {});
        await _retireClosedTableCopies(force: true);
      }
      final transferred = _transferredQrWorkspace;
      _transferredQrWorkspace = null;
      if (transferred != null &&
          identical(_workspace, transferred) &&
          mounted) {
        transferred.onExit();
      }
    }
  }

  /// Close the selected quick bill only after checkout confirms payment and
  /// the cashier dismisses its result. Cancel/recovery keeps the bill open.
  Future<void> showQrCheckout(QrCheckoutController payment) async {
    final workspace = _workspace;
    final originalBillUuid = workspace?.bill?.uuid;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QrCheckoutBoundary(
          controller: payment,
          authorizeManager: () =>
              _authorizeManager(subtitle: checkoutText(context, 'manager')),
          paymentPage: (_, exit) => buildQrPaymentPage(payment, exit),
          statusPage: (_, exit, status) =>
              buildQrPaymentStatus(payment, exit, status),
        ),
      ),
    );
    if (!mounted ||
        payment.phase != CheckoutPhase.paid ||
        workspace == null ||
        !workspace.mainCart ||
        !identical(_workspace, workspace) ||
        originalBillUuid != payment.snapshot?.order['uuid'] ||
        (workspace.bill != null && workspace.bill!.uuid != originalBillUuid)) {
      return;
    }
    workspace.returnToList = false;
    workspace.onExit();
    if (workspace.dineIn) {
      await controller.selectOrderType(OrderType.dineIn);
      await controller.returnToDiningFloorPlan();
    } else {
      await controller.selectOrderType(OrderType.quickOrder);
    }
  }

  /// Only the data and supported callbacks differ for a server-owned bill.
  Widget buildQrPaymentPage(QrCheckoutController payment, VoidCallback exit) =>
      _buildPosShell(
        surface: _buildPaymentPageSurface(qr: payment, exit: exit),
      );

  Widget buildQrPaymentStatus(
    QrCheckoutController payment,
    VoidCallback exit,
    Widget status,
  ) => _buildPosShell(
    surface: IgnorePointer(
      child: payment.snapshot == null
          ? Column(
              children: [
                SizedBox(
                  height: _paymentHeaderHeight,
                  child: _buildPaymentHeader(qr: payment, exit: exit),
                ),
                const SizedBox(height: _panelGap),
                Expanded(child: _glassPanel(child: const SizedBox.expand())),
              ],
            )
          : _buildPaymentPageSurface(qr: payment, exit: exit),
    ),
    overlays: [
      Positioned.fill(
        child: Material(
          color: Colors.black.withValues(alpha: 0.62),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: status,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _payQr(QrCheckoutController qr, String method) async {
    if (!qr.ready) return;
    if (method == 'cash' && qr.cashBaisas < qr.total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(checkoutText(context, 'amount_error'))),
      );
      return;
    }
    await qr.pay([
      CheckoutTender(
        method,
        qr.total,
        change: method == 'cash' ? qr.changeBaisas : 0,
      ),
    ]);
  }

  Future<void> _splitQr(QrCheckoutController qr) async {
    if (!qr.ready) return;
    final plan = await checkoutMixedPlan(context, qr.total);
    if (plan != null && qr.ready) await qr.pay(plan);
  }

  Widget _buildPaymentPageSurface({
    QrCheckoutController? qr,
    VoidCallback? exit,
  }) {
    return Column(
      children: [
        SizedBox(
          height: _paymentHeaderHeight,
          child: _buildPaymentHeader(qr: qr, exit: exit),
        ),
        const SizedBox(height: _panelGap),
        Expanded(
          child: _buildPaymentBody(qr: qr, exit: exit),
        ),
      ],
    );
  }

  Widget _buildPaymentHeader({QrCheckoutController? qr, VoidCallback? exit}) {
    final l10n = L10n.of(context);
    return _glassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          _CircleGlassButton(
            icon: Icons.arrow_back_rounded,
            onTap: exit ?? _closePaymentPage,
          ),
          const SizedBox(width: 14),
          Text(
            l10n.posPaymentTitle,
            style: const TextStyle(
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
              (qr?.reference ?? controller.currentOrderReference).isEmpty
                  ? l10n.posPaymentNewOrder
                  : l10n.posPaymentOrderRef(
                      qr?.reference ?? controller.currentOrderReference,
                    ),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF22523B),
              ),
            ),
          ),
          if (qr == null && _isEditingDiningTable) ...[
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
                l10n.posPaymentTableChip(_activeDiningTableLabel),
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
          IgnorePointer(ignoring: qr != null, child: _buildProfileBlock()),
        ],
      ),
    );
  }

  Widget _buildPaymentBody({QrCheckoutController? qr, VoidCallback? exit}) {
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
          SizedBox(width: 330, child: _buildPaymentOrderPanel(qr: qr)),
          const SizedBox(width: 18),
          Expanded(
            child: _buildPaymentConsole(qr: qr, exit: exit),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOrderPanel({QrCheckoutController? qr}) {
    final l10n = L10n.of(context);
    final bill = qr == null
        ? _liveBill
        : WorkspaceBill({
            ...qr.snapshot!.order,
            'customer': qr.snapshot!.customer,
          });
    final cart = bill?.cartItems ?? controller.cart;
    final rawSubtotal = bill == null
        ? controller.rawSubtotal
        : bill.subtotal / 1000;
    final discount = bill == null
        ? controller.discountAmount
        : bill.discount / 1000;
    final comp = bill == null ? controller.compAmount : bill.comp / 1000;
    final subtotal = bill == null
        ? controller.subtotal
        : rawSubtotal - discount;
    final total = bill == null
        ? controller.activePaymentBaseTotal
        : bill.total / 1000;

    return _glassPanel(
      tint: Colors.white.withValues(alpha: 0.72),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.posPaymentOrderItems,
            style: const TextStyle(
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
                itemCount: cart.length,
                separatorBuilder: (_, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = cart[index];
                  return _PaymentOrderItemCard(item: item);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (bill == null &&
              controller.selectedOrderType == OrderType.delivery) ...[
            _buildDeliveryProviderField(),
            const SizedBox(height: 16),
          ],
          if (qr == null && _liveTable)
            _tableAdjustmentControls()
          else
            _buildCustomerReferenceField(qr: qr),
          if (bill != null)
            _billAdjustmentContext(bill, showCustomer: qr == null),
          const SizedBox(height: 16),
          _buildVehiclePlateField(qr: qr),
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
                _paymentTotalRow(l10n.posPaymentSubtotal, rawSubtotal),
                if (discount > 0) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow(
                    bill != null || controller.discount.label.isEmpty
                        ? l10n.posPaymentDiscountFallback
                        : controller.discount.label,
                    -discount,
                  ),
                ],
                const SizedBox(height: 10),
                _paymentTotalRow(l10n.posPaymentNetSubtotal, subtotal),
                // Phase B — the manager comp write-off (given away, not sold).
                if (comp > 0) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow(
                    l10n.posPaymentCompRow(
                      bill == null
                          ? controller.appliedComp?.reasonName ?? ''
                          : bill.compReason,
                    ),
                    -comp,
                  ),
                ],
                if (bill != null && bill.tax != 0) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow(
                    checkoutText(context, 'tax'),
                    bill.tax / 1000,
                  ),
                ],
                if (bill == null)
                  for (final t in controller.taxLines) ...[
                    const SizedBox(height: 10),
                    _paymentTotalRow(
                      l10n.posPaymentTaxLine(t.name, t.rateLabel),
                      t.amount,
                    ),
                  ],
                if (bill == null && controller.splitCount > 1) ...[
                  const SizedBox(height: 10),
                  _paymentTotalRow(
                    l10n.posPaymentGuestShareRow(controller.activeSplitIndex),
                    total,
                  ),
                ],
                const SizedBox(height: 14),
                Container(height: 1, color: const Color(0xFFD9E5EA)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bill == null && controller.splitCount > 1
                            ? l10n.posPaymentShareDue
                            : l10n.posPaymentTotalDue,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF192831),
                        ),
                      ),
                    ),
                    Text(
                      SunmiReceiptService.money(total),
                      key: bill == null
                          ? null
                          : const ValueKey('qr-checkout-total'),
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

  /// A small trailing action inside the customer/plate fields. Its own
  /// InkWell wins the gesture arena over the field's main tap.
  Widget _fieldTrailingAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    Key? key,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: const Color(0xFFEDF4F7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: const Color(0xFF3D5563)),
        ),
      ),
    ),
  );

  Widget _buildCustomerReferenceField({QrCheckoutController? qr}) {
    final l10n = L10n.of(context);
    final value = qr?.snapshot?.customerLabel ?? _customerNumberController.text;
    final hasValue =
        value.isNotEmpty || (qr == null && controller.selectedCustomer != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posPaymentCustomerNumberLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF192831),
          ),
        ),
        const SizedBox(height: 8),
        // P-F2 — tapping the field opens the NUMBER KEYPAD directly (no
        // chooser popup); search and details are the trailing buttons.
        InkWell(
          key: const ValueKey('payment-customer-number'),
          onTap: qr == null
              ? () => unawaited(_openCustomerNumberKeyboard())
              : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                    value.isEmpty ? l10n.posPaymentCustomerNumberHint : value,
                    key: qr == null
                        ? null
                        : const ValueKey('qr-checkout-customer'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: value.isEmpty
                          ? const Color(0xFF91A0AB)
                          : const Color(0xFF22323B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (hasValue) ...[
                  _fieldTrailingAction(
                    icon: Icons.badge_outlined,
                    tooltip: l10n.posCustomerDetailsTooltip,
                    onTap: qr == null
                        ? () => unawaited(_openCustomerDetails())
                        : null,
                    key: const ValueKey('payment-customer-details'),
                  ),
                  const SizedBox(width: 6),
                ],
                _fieldTrailingAction(
                  icon: Icons.person_search_rounded,
                  tooltip: l10n.posCustomerSearchOption,
                  onTap: qr == null
                      ? () => unawaited(_openCustomerSearch())
                      : null,
                ),
                if (hasValue) ...[
                  const SizedBox(width: 6),
                  _fieldTrailingAction(
                    icon: Icons.close_rounded,
                    tooltip: l10n.posCustomerClearOption,
                    onTap: qr == null
                        ? () {
                            setState(() => _customerNumberController.clear());
                            controller.setCustomerReferenceNumber('');
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVehiclePlateField({QrCheckoutController? qr}) {
    final l10n = L10n.of(context);
    final value = qr == null
        ? _vehiclePlateController.text
        : qr.snapshot?.order['plate_number']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posPaymentVehiclePlateLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF192831),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('payment-vehicle-plate'),
          onTap: qr == null ? _openVehiclePlateKeyboard : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDCE8EC)),
              boxShadow: _softShadow,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.directions_car_outlined,
                  color: Color(0xFF70818E),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value.isEmpty ? l10n.posPaymentVehiclePlateHint : value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: value.isEmpty
                          ? const Color(0xFF91A0AB)
                          : const Color(0xFF22323B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // P-F2 — find the customers linked to a plate.
                _fieldTrailingAction(
                  icon: Icons.person_search_rounded,
                  tooltip: l10n.posPlateSearchTooltip,
                  onTap: qr == null
                      ? () => unawaited(_openPlateCustomerSearch())
                      : null,
                  key: const ValueKey('payment-plate-search'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryProviderField() {
    final l10n = L10n.of(context);
    final provider = controller.selectedDeliveryProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.posPaymentDeliveryProviderLabel,
          style: const TextStyle(
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
                const Icon(
                  Icons.delivery_dining_outlined,
                  color: Color(0xFF70818E),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider == null
                        ? l10n.posPaymentDeliveryProviderHint
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

  Widget _buildPaymentConsole({QrCheckoutController? qr, VoidCallback? exit}) {
    final l10n = L10n.of(context);
    final quickAmounts = _quickCashAmounts(
      total: qr == null ? null : qr.total / 1000,
    );
    final liveTable = qr == null && _liveTable;
    final qrMixed = qr != null && qr.cashBaisas > 0 && qr.cashBaisas < qr.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Device↔device order transfer (replaced the Loyalty shortcut —
            // loyalty redemption stays reachable from the customer panel).
            // The count is the incoming inbox waiting to be received.
            Expanded(
              child: _PaymentTopActionCard(
                icon: Icons.swap_horiz_rounded,
                title: _incomingTransfers.isEmpty
                    ? l10n.posPaymentTransfer
                    : '${l10n.posPaymentTransfer} (${_incomingTransfers.length})',
                accent: const Color(0xFF0FA3B1),
                onTap: qr == null
                    ? () => unawaited(_openTransferDialog())
                    : (_workspace?.cartControls?.transfer != null && qr.ready
                          ? () => unawaited(
                              _openTransferDialog(checkout: qr, exit: exit),
                            )
                          : null),
              ),
            ),
            SizedBox(width: 16),
            if (!liveTable)
              Expanded(
                child: _PaymentTopActionCard(
                  icon: Icons.percent_rounded,
                  title: l10n.posPaymentAddDiscount,
                  accent: const Color(0xFFFF8A2B),
                  onTap: qr == null
                      ? () => unawaited(_openDiscountDialog())
                      : null,
                ),
              ),
            SizedBox(width: 16),
            Expanded(
              child: _PaymentTopActionCard(
                icon: Icons.call_split_rounded,
                title: l10n.posPaymentSplitBill,
                onTap: qr == null
                    ? () => unawaited(_openSplitBillDialog())
                    : null,
              ),
            ),
            // Phase B — manager comp (write-off a line / the whole order).
            // Shown only when the company configured comp reasons.
            if (!liveTable && controller.compReasons.isNotEmpty) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _PaymentTopActionCard(
                  icon: Icons.volunteer_activism_rounded,
                  title: qr != null || controller.appliedComp == null
                      ? l10n.posPaymentComp
                      : l10n.posPaymentCompApplied,
                  accent: const Color(0xFF7C5CCB),
                  onTap: qr == null ? () => unawaited(_openCompDialog()) : null,
                ),
              ),
            ],
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
                                    Text(
                                      l10n.posPaymentTendered,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6B7A86),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      SunmiReceiptService.money(
                                        qr == null
                                            ? _tenderedCashAmount
                                            : qr.cashBaisas / 1000,
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
                                      (qr == null
                                              ? _showMixedCardBalance
                                              : qrMixed)
                                          ? l10n.posPaymentCardBalance
                                          : l10n.posPaymentChange,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF6B7A86),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      SunmiReceiptService.money(
                                        qr == null
                                            ? (_showMixedCardBalance
                                                  ? _mixedCardBalance
                                                  : _cashChangeAmount)
                                            : (qrMixed
                                                  ? (qr.total - qr.cashBaisas) /
                                                        1000
                                                  : qr.changeBaisas / 1000),
                                      ),
                                      key: const ValueKey('change-amount'),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        color:
                                            (qr == null
                                                ? _showMixedCardBalance
                                                : qrMixed)
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
                                      padding: EdgeInsetsDirectional.only(
                                        end: amount == quickAmounts.last
                                            ? 0
                                            : 10,
                                      ),
                                      child: _QuickCashButton(
                                        label: l10n.posPaymentQuickCash(amount),
                                        onTap: () => qr == null
                                            ? _setQuickCashAmount(amount)
                                            : qr.cashAmount(amount * 1000),
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
                                if (qr == null && controller.splitCount > 1)
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
                                      l10n.posPaymentCollectingGuest(
                                        controller.activeSplitIndex,
                                        controller.splitCount,
                                        SunmiReceiptService.money(
                                          controller.activePaymentBaseTotal,
                                        ),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF25414B),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  // Keep the digit grid LTR-stable under RTL.
                                  child: Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Row(
                                      children: [
                                        _buildPaymentKeyCell('1', qr: qr),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('2', qr: qr),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('3', qr: qr),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Row(
                                      children: [
                                        _buildPaymentKeyCell('4', qr: qr),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('5', qr: qr),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('6', qr: qr),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Row(
                                      children: [
                                        _buildPaymentKeyCell('7', qr: qr),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('8', qr: qr),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('9', qr: qr),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Row(
                                      children: [
                                        _buildPaymentKeyCell(
                                          '.',
                                          qr: qr,
                                          buttonKey: const ValueKey(
                                            'payment-key-decimal',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        _buildPaymentKeyCell('0', qr: qr),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _PaymentKeyButton(
                                            buttonKey: const ValueKey(
                                              'payment-key-backspace',
                                            ),
                                            icon: Icons.backspace_outlined,
                                            onTap: qr == null
                                                ? _backspaceCashKey
                                                : () => qr.cashKey('back'),
                                          ),
                                        ),
                                      ],
                                    ),
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
                        // P-G7 — a delivery-provider order takes NO tender:
                        // the provider pays later, minus commission. Proceed
                        // collects the provider's order number (+ optional
                        // contacts) and completes as pending verification.
                        children:
                            qr == null &&
                                controller.selectedOrderType ==
                                    OrderType.delivery
                            ? [
                                Expanded(
                                  child: _PaymentMethodActionButton(
                                    label: l10n.posPaymentDeliveryProceed,
                                    icon: Icons.delivery_dining_rounded,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF2E5E8C),
                                        Color(0xFF234A72),
                                      ],
                                    ),
                                    onTap: _openDeliveryProceedDialog,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 86,
                                  child: _PaymentBottomActionButton(
                                    label: l10n.commonCancel,
                                    icon: Icons.close_rounded,
                                    onTap: _closePaymentPage,
                                  ),
                                ),
                              ]
                            : [
                                // Expanded (not square AspectRatio): the fixed
                                // 1600x900 canvas leaves this column 592px, so two
                                // 236px squares can never fit — share the height.
                                Expanded(
                                  child: _PaymentMethodActionButton(
                                    label: l10n.posPaymentCash,
                                    icon: Icons.payments_outlined,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF1DB14A),
                                        Color(0xFF17A243),
                                      ],
                                    ),
                                    onTap: qr == null
                                        ? _submitCashPayment
                                        : () => _payQr(qr, 'cash'),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: _PaymentMethodActionButton(
                                    label: l10n.posPaymentCard,
                                    subtitle:
                                        ref
                                            .read(sessionServiceProvider)
                                            .softpos
                                            .canPay(
                                              terminalId: ref
                                                  .read(sessionServiceProvider)
                                                  .terminalId,
                                              terminalPin: ref
                                                  .read(sessionServiceProvider)
                                                  .terminalPin,
                                            )
                                        ? '${softposText(context, 'payingVia')} ${ref.read(sessionServiceProvider).softpos.bankName}'
                                        : softposText(
                                            context,
                                            ref
                                                .read(sessionServiceProvider)
                                                .softpos
                                                .unavailableReason(
                                                  terminalId: ref
                                                      .read(
                                                        sessionServiceProvider,
                                                      )
                                                      .terminalId,
                                                  terminalPin: ref
                                                      .read(
                                                        sessionServiceProvider,
                                                      )
                                                      .terminalPin,
                                                )!,
                                          ),
                                    icon: Icons.credit_card_rounded,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF2A8B42),
                                        Color(0xFF1F7236),
                                      ],
                                    ),
                                    onTap:
                                        !ref
                                            .read(sessionServiceProvider)
                                            .softpos
                                            .canPay(
                                              terminalId: ref
                                                  .read(sessionServiceProvider)
                                                  .terminalId,
                                              terminalPin: ref
                                                  .read(sessionServiceProvider)
                                                  .terminalPin,
                                            )
                                        ? null
                                        : qr == null
                                        ? _submitCardPayment
                                        : () => _payQr(qr, 'card'),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                // P-F5 — record a payment taken on the bank's own
                                // standalone terminal (no integration; NOT card
                                // money for the commission split).
                                SizedBox(
                                  height: 64,
                                  child: _PaymentMethodActionButton(
                                    label: l10n.posPaymentBankPos,
                                    icon: Icons.account_balance_rounded,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF2E5E8C),
                                        Color(0xFF234A72),
                                      ],
                                    ),
                                    onTap: qr == null
                                        ? _submitBankPosPayment
                                        : () => _payQr(qr, 'bank_pos'),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                // Phase D4 — gift the whole order (manager-gated;
                                // §6.8 "zero charged… inventory still deducts").
                                if (qr != null || !_liveTable)
                                  SizedBox(
                                    height: 64,
                                    child: _PaymentMethodActionButton(
                                      label: l10n.posPaymentGift,
                                      icon: Icons.card_giftcard_rounded,
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF8E5BA6),
                                          Color(0xFF6E4385),
                                        ],
                                      ),
                                      onTap: qr == null
                                          ? _submitGiftPayment
                                          : () => _payQr(qr, 'gift'),
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  height: 86,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _PaymentBottomActionButton(
                                          label: l10n.commonCancel,
                                          icon: Icons.close_rounded,
                                          onTap: exit ?? _closePaymentPage,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: _PaymentBottomActionButton(
                                          label: l10n.posPaymentSplitPayment,
                                          icon: Icons.call_split_rounded,
                                          filled: true,
                                          onTap: qr == null
                                              ? _submitMixedPayment
                                              : () => _splitQr(qr),
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

  /// P-G7 — the delivery Proceed popup: provider order number (REQUIRED) +
  /// optional customer/driver numbers, then a no-tender completion. The
  /// order lands pending verification; the merchant settles it on the
  /// portal Deliveries page when the provider's statement arrives.
  Future<void> _openDeliveryProceedDialog() async {
    if (controller.isProcessingPayment) return;
    final l10n = L10n.of(context);
    // No provider (e.g. it was retired mid-order, or the pick was somehow
    // skipped): route through the picker instead of silently no-opping.
    if (controller.selectedDeliveryProviderId == null) {
      await _openDeliveryProviderPicker();
      if (!mounted || controller.selectedDeliveryProviderId == null) return;
    }
    final result =
        await showDialog<({String reference, String customer, String driver})>(
          context: context,
          builder: (_) => _DeliveryProceedDialog(
            initialCustomer: _customerNumberController.text,
          ),
        );
    if (!mounted || result == null) return;

    _customerNumberController.text = result.customer;
    final message = await controller.completeDeliveryOrder(
      reference: result.reference,
      customerPhone: result.customer,
      driverPhone: result.driver,
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
      title: l10n.posDeliveryRecordedTitle,
      message: message,
      tone: FeedbackTone.success,
    );
  }

  Widget _paymentTotalRow(String title, double amount) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  Widget _buildPaymentKeyCell(
    String keyLabel, {
    Key? buttonKey,
    QrCheckoutController? qr,
  }) {
    return Expanded(
      child: _PaymentKeyButton(
        buttonKey: buttonKey ?? ValueKey('payment-key-$keyLabel'),
        label: keyLabel,
        onTap: () =>
            qr == null ? _appendCashKey(keyLabel) : qr.cashKey(keyLabel),
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
    final attentionSalesCount =
        ref.watch(orderSyncAttentionProvider).asData?.value.length ?? 0;
    return _glassPanel(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 13,
            child: _buildOrderTypeGroup(
              alignment: AlignmentDirectional.centerStart,
            ),
          ),
          const SizedBox(width: 12),
          _buildBrandBlock(),
          const SizedBox(width: 12),
          Expanded(
            flex: 10,
            child: _buildSecondaryNavGroup(
              alignment: AlignmentDirectional.centerEnd,
            ),
          ),
          const SizedBox(width: 8),
          _buildTimeBlock(),
          const SizedBox(width: 8),
          OrderAttentionBell(
            onQuickOrders: () => unawaited(_openQuickOrders()),
            onTables: () => unawaited(_handleOrderTypeTap(OrderType.dineIn)),
          ),
          const SizedBox(width: 8),
          // P-F1 — the gear opens Settings (which now hosts the operational
          // actions that used to crowd the logout sheet).
          _CircleGlassButton(
            icon: Icons.settings_outlined,
            badgeCount: attentionSalesCount,
            onTap: () => unawaited(_openSettings()),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 5,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _buildProfileBlock(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeGroup({required AlignmentGeometry alignment}) {
    final l10n = L10n.of(context);
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
                  padding: EdgeInsetsDirectional.only(
                    end: entry.key == _primaryOrderTypes.length - 1 ? 0 : 8,
                  ),
                  child: _HeaderNavChip(
                    title: localizedOrderType(l10n, entry.value),
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

  Widget _buildSecondaryNavGroup({required AlignmentGeometry alignment}) {
    final l10n = L10n.of(context);
    final navItems = _secondaryNavItems
        .where((item) => item.title != 'QR Tables')
        .toList();
    // The stored _NavItemData titles stay English IDENTITY values (the switch
    // below compares them); only the rendered chip label is localized.
    String navChipTitle(String identity) => switch (identity) {
      'Home' => l10n.posNavHome,
      'Offers' => l10n.posNavOffers,
      'Kitchen' => l10n.posNavKitchen,
      'Messages' => l10n.posNavMessages,
      'Report' => l10n.posNavReport,
      'History' => l10n.posNavHistory,
      'QR Quick Orders' => QuickCopy(
        Localizations.localeOf(context).languageCode == 'ar',
      ).title,
      _ => identity,
    };
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Row(
          children: navItems
              .asMap()
              .entries
              .map(
                (entry) => Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: entry.key == navItems.length - 1 ? 0 : 8,
                  ),
                  child: _HeaderNavChip(
                    title: navChipTitle(entry.value.title),
                    icon: entry.value.icon,
                    selected: false,
                    // P-G6 — unread-announcements bubble on the Messages chip.
                    badgeCount: entry.value.title == 'Messages'
                        ? _unreadMessagesCount()
                        : 0,
                    onTap: () {
                      switch (entry.value.title) {
                        case 'QR Quick Orders':
                          unawaited(_openQuickOrders());
                          break;
                        case 'QR Tables':
                          // QR orders remain server-owned. This route passes
                          // configuration labels only; it never imports QR
                          // occupancy into DiningTableSession or PosController.
                          unawaited(
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => QrTablesScreen(
                                  openCheckout: _launchQrCheckout,
                                  floors: List<DiningFloor>.unmodifiable(
                                    controller.diningFloors,
                                  ),
                                  tables:
                                      List<DiningTableDefinition>.unmodifiable(
                                        controller.diningTableDefinitions,
                                      ),
                                ),
                              ),
                            ),
                          );
                          break;
                        case 'Messages':
                          // P-G6 — staff announcements from the portal.
                          unawaited(_openMessagesSheet());
                          break;
                        case 'Offers':
                          // P-F9 — the merchant's promotions: bundles to
                          // pick, autos shown with their live status.
                          unawaited(_openOffersSheet());
                          break;
                        case 'Kitchen':
                          // P-G1 — cooked-product batches; gated by the
                          // merchant's kitchen_positions policy (the
                          // reports pattern). Online-only.
                          unawaited(_openKitchen());
                          break;
                        case 'Report':
                          // P-F6 — chooser: the full branch dashboard
                          // (reports_positions-gated) or the G3 mid-shift
                          // X-report (manager-gated).
                          unawaited(_openReportChooser());
                          break;
                        default:
                          _showPlaceholderMessage(
                            l10n.posNavHome,
                            l10n.posNavAlreadyHomeBody,
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
    final l10n = L10n.of(context);
    return Container(
      width: 156,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _chipDecoration(selected: false),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'MITHQAL 2.0',
              maxLines: 1,
              style: TextStyle(
                color: Color(0xFF65789C),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.posNavBrandTagline,
              maxLines: 1,
              style: const TextStyle(
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
    final l10n = L10n.of(context);
    final staff = ref.read(sessionControllerProvider).staff;
    final name = (staff?.name.isNotEmpty ?? false)
        ? staff!.name
        : l10n.posNavStaffFallback;
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
            alignment: AlignmentDirectional.centerStart,
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

  /// Staff chip menu. With a shift OPEN the sheet asks THE question — are
  /// you closing the shift, or just logging out? Closing counts the drawer,
  /// prints the Z-report, then FORCES the sign-out so the next staff member
  /// logs in with their own PIN. "Just log out" leaves the drawer record open,
  /// but the next cashier cannot inherit it: they must resume as its owner,
  /// settle it, or open their own float after settlement.
  Future<void> _openStaffMenu() async {
    final hasOpenShift = ref.read(sessionControllerProvider).openShift != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final l10n = L10n.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasOpenShift) ...[
                ListTile(
                  leading: const Icon(Icons.point_of_sale_rounded),
                  title: Text(l10n.posMenuCloseShiftAndLogout),
                  subtitle: Text(l10n.posMenuCloseShiftAndLogoutSub),
                  onTap: () => Navigator.pop(ctx, 'close_shift_logout'),
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.posMenuLogoutOnly),
                  subtitle: Text(l10n.posMenuLogoutOnlySub),
                  onTap: () => Navigator.pop(ctx, 'logout'),
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.commonLogout),
                  subtitle: Text(l10n.posMenuLogoutSub),
                  onTap: () => Navigator.pop(ctx, 'logout'),
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(l10n.commonCancel),
                onTap: () => Navigator.pop(ctx, null),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (action == 'logout') {
      await _confirmLogout();
    } else if (action == 'close_shift_logout') {
      await _closeShiftThenLogout();
    }
  }

  /// Close the shift (count → Z-report print → server settle), then sign the
  /// staff member out so the next one starts with their own PIN + opening
  /// float. Backing out of the close screen leaves the shift open and stays
  /// logged in.
  Future<void> _closeShiftThenLogout() async {
    await runShiftClosePreflight(context, ref);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShiftCloseScreen()));
    if (!mounted) return;
    // The close screen pops without a result — the shift being GONE is the
    // success signal (an X-out keeps it open).
    final stillOpen = ref.read(sessionControllerProvider).openShift != null;
    if (stillOpen) return;
    await ref.read(sessionControllerProvider.notifier).logoutStaff();
  }

  /// P-F1 — the top-bar gear: Settings, which now hosts the operational
  /// actions (close shift, expense, restock, stock count, shift summary).
  /// The screen pops an action key so the flows keep running with this
  /// screen's controller/session context.
  Future<void> _openCheckoutRecovery() async {
    final api = ref.read(apiServiceProvider),
        session = ref.read(sessionServiceProvider);
    String scope() => quickDeviceScope(
      api.quickOrderBaseUrl,
      session.companyId,
      session.branchId,
      session.kioskId,
    );
    final captured = scope();
    try {
      final checkout = await SqliteCheckoutStore.open(captured);
      if (!mounted || scope() != captured) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CheckoutRecoveryDialog(
          recovery: CheckoutRecovery(checkout.db, scope),
          staffId: session.staff?.id ?? 0,
          arabic: ref.read(settingsControllerProvider).language == 'ar',
          authorize: () async {
            _orderPreparations.assertIdle();
            await controller.assertIdleForCombine();
            if (!mounted || _normalQrCheckoutOpen || _showPaymentPage) {
              return false;
            }
            return _authorizeManager(subtitle: 'Archive old reservation');
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recoveryMessage(
                e,
                arabic: ref.read(settingsControllerProvider).language == 'ar',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _openSettings() async {
    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(showOperations: true),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'checkout_recovery':
        await _openCheckoutRecovery();
      case 'close_shift':
        // Closing a shift always ends the session (same policy as the
        // logout sheet) — the next staff member opens their own shift.
        await _closeShiftThenLogout();
      case 'log_expense':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LogExpenseScreen()));
      case 'restock_request':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RestockRequestScreen()));
      case 'stock_count':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const StockCountScreen()));
      case 'waste_product':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WasteProductScreen()));
      case 'shift_summary':
        await _reprintLastShiftSummary();
    }
  }

  /// P-G6 — unread announcements for the signed-in staff member (the badge
  /// on the Messages chip). 0 when nobody is signed in.
  int _unreadMessagesCount() {
    final staffId = ref.read(sessionServiceProvider).staff?.id;
    if (staffId == null) return 0;
    return controller.unreadMessageCountFor(staffId);
  }

  /// P-G6 — pop a notice when a catalog refresh brings a NEW unread
  /// announcement for the signed-in staff member. [prev] null = initial
  /// load (no popup — the badge already shows the backlog).
  void _maybeAnnounceNewMessages(CatalogSnapshot? prev, CatalogSnapshot next) {
    if (prev == null) return;
    final staffId = ref.read(sessionServiceProvider).staff?.id;
    if (staffId == null) return;
    final prevIds = prev.staffMessages.map((m) => m.id).toSet();
    for (final m in next.staffMessages) {
      if (prevIds.contains(m.id)) continue;
      if (!m.visibleTo(staffId) || m.isReadBy(staffId)) continue;
      final l10n = L10n.of(context);
      final title = m.title?.trim() ?? '';
      _showPopupMessage(
        title: title.isNotEmpty ? title : l10n.posMessagesPopupTitle,
        message: m.body,
        tone: FeedbackTone.info,
        duration: const Duration(seconds: 6),
      );
      return; // one popup per refresh — the sheet shows the rest.
    }
  }

  /// P-G6 — re-send every receipt not yet ACKed for [staffId]. Success
  /// ACKs the batch; failure keeps it pending for the next sheet open /
  /// reconnect, so an offline read still reaches the portal's "seen by"
  /// list eventually.
  void _flushMessageReceipts(int staffId) {
    final pending = controller.pendingMessageReceiptIds(staffId);
    if (pending.isEmpty) return;
    unawaited(
      ref
          .read(apiServiceProvider)
          .markMessagesRead(staffId: staffId, messageIds: pending)
          .then((_) => controller.markMessageReceiptsAcked(staffId, pending))
          .catchError((_) {}),
    );
  }

  /// P-G6 — the staff announcements sheet. Opening it marks the visible
  /// unread messages read: locally at once (the badge clears) plus a
  /// read-receipt POST so the portal's "seen by" list updates ("sent is
  /// not the same as seen"). A failed POST stays pending and is retried
  /// on the next open / reconnect — the server upsert is idempotent.
  Future<void> _openMessagesSheet() async {
    final l10n = L10n.of(context);
    final staffId = ref.read(sessionServiceProvider).staff?.id;
    if (staffId == null) return;
    final messages = controller.visibleMessagesFor(staffId);
    if (messages.isEmpty) {
      _showPopupMessage(
        title: l10n.posNavMessages,
        message: l10n.posMessagesNone,
        tone: FeedbackTone.info,
      );
      return;
    }
    // Snapshot unread BEFORE marking, so the sheet can still bold them.
    final unreadIds = messages
        .where((m) => !controller.isMessageReadBy(m, staffId))
        .map((m) => m.id)
        .toList();
    final unreadSet = unreadIds.toSet();
    controller.markMessagesReadLocal(staffId, unreadIds);
    // POST the pending batch — the fresh reads PLUS any receipt whose
    // earlier POST failed (offline till). The server upsert is idempotent
    // and ACKed ids stop retrying.
    _flushMessageReceipts(staffId);

    String stamp(DateTime at) {
      final v = at.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${v.year}-${two(v.month)}-${two(v.day)} ${two(v.hour)}:${two(v.minute)}';
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final sheetL10n = L10n.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in messages)
                  ListTile(
                    leading: Icon(
                      m.targetType == 'staff'
                          ? Icons.person_outline_rounded
                          : Icons.campaign_outlined,
                    ),
                    title: Text(
                      (m.title?.trim().isNotEmpty ?? false)
                          ? m.title!.trim()
                          : sheetL10n.posMessagesUntitled,
                      style: TextStyle(
                        fontWeight: unreadSet.contains(m.id)
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      [
                        m.body,
                        [
                          if ((m.createdByName ?? '').trim().isNotEmpty)
                            m.createdByName!.trim(),
                          if (m.createdAt != null) stamp(m.createdAt!),
                        ].join(' · '),
                      ].where((s) => s.isNotEmpty).join('\n'),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.close),
                  title: Text(sheetL10n.commonClose),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// P-F9 — the Offers sheet: the merchant's currently-valid promotions.
  /// BUNDLES are tappable (→ the group picker adds the items priced as the
  /// bundle); auto offers are informational rows showing whether they're
  /// applied to the current cart right now.
  Future<void> _openOffersSheet() async {
    final l10n = L10n.of(context);
    // P-G7 — no promotions on delivery-provider orders: say so instead of
    // offering bundles whose price would never apply.
    if (controller.selectedOrderType == OrderType.delivery) {
      _showPopupMessage(
        title: l10n.posNavOffers,
        message: l10n.posOffersNotForDelivery,
        tone: FeedbackTone.info,
      );
      return;
    }
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final branchId = ref.read(sessionControllerProvider).branchId ?? 0;
    final now = DateTime.now();
    final offers = controller.availableOffers
        .where((o) => o.appliesAt(now, branchId: branchId))
        .toList();
    if (offers.isEmpty) {
      _showPopupMessage(
        title: l10n.posNavOffers,
        message: l10n.posOffersNone,
        tone: FeedbackTone.info,
      );
      return;
    }
    final appliedById = {
      for (final a in controller.appliedOffers) a.offerId: a,
    };

    String typeLabel(String type) => switch (type) {
      'bogo' => l10n.posOfferTypeBogo,
      'bundle' => l10n.posOfferTypeBundle,
      'multi_buy' => l10n.posOfferTypeMultiBuy,
      'cheapest_free' => l10n.posOfferTypeCheapestFree,
      'spend_get' => l10n.posOfferTypeSpendGet,
      _ => type,
    };

    final picked = await showModalBottomSheet<Offer>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final offer in offers)
                ListTile(
                  leading: Icon(
                    offer.isBundle
                        ? Icons.lunch_dining_rounded
                        : Icons.local_offer_outlined,
                  ),
                  title: Text(offer.displayName(isAr)),
                  subtitle: Text(typeLabel(offer.type)),
                  trailing: offer.isBundle
                      ? const Icon(Icons.add_circle_outline_rounded)
                      : appliedById.containsKey(offer.id)
                      ? Chip(
                          label: Text(
                            l10n.posOffersAppliedTimes(
                              appliedById[offer.id]!.applications,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                  onTap: offer.isBundle
                      ? () => Navigator.pop(ctx, offer)
                      : null,
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(l10n.commonClose),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    await _openBundlePicker(picked);
  }

  /// P-F9 — pick the bundle's items group by group, then add the whole set
  /// priced as the bundle.
  Future<void> _openBundlePicker(Offer offer) async {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final groups = ((offer.config['groups'] as List?) ?? const [])
        .whereType<Map>()
        .map((g) => g.cast<String, dynamic>())
        .toList();
    if (groups.isEmpty) return;

    final productById = {
      for (final p in controller.allProducts) int.tryParse(p.id): p,
    };
    // counts[group][productId] = picked qty
    final counts = [for (final _ in groups) <int, int>{}];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var allSatisfied = true;
          final sections = <Widget>[];
          for (var g = 0; g < groups.length; g++) {
            final group = groups[g];
            final need = (group['qty'] as num?)?.toInt() ?? 1;
            final ids = ((group['product_ids'] as List?) ?? const [])
                .map((e) => (e as num?)?.toInt())
                .whereType<int>()
                .toList();
            final pickedCount = counts[g].values.fold(0, (s, v) => s + v);
            if (pickedCount != need) allSatisfied = false;
            final label =
                isAr &&
                    (group['label_ar']?.toString().trim().isNotEmpty ?? false)
                ? group['label_ar'].toString()
                : (group['label']?.toString() ?? '');
            sections.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      '$label — ${l10n.posOffersBundleNeed(need)}'
                      '  ($pickedCount/$need)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in ids)
                        if (productById[id] != null)
                          FilterChip(
                            label: Text(
                              counts[g][id] != null && counts[g][id]! > 0
                                  ? '${productById[id]!.displayName(isAr)} ×${counts[g][id]}'
                                  : productById[id]!.displayName(isAr),
                            ),
                            selected: (counts[g][id] ?? 0) > 0,
                            onSelected: (_) => setDialogState(() {
                              final current = counts[g][id] ?? 0;
                              final total = counts[g].values.fold(
                                0,
                                (s, v) => s + v,
                              );
                              if (current > 0 && total >= need) {
                                // Tapping a selected chip at capacity clears it.
                                counts[g].remove(id);
                              } else if (total < need) {
                                counts[g][id] = current + 1;
                              }
                            }),
                          ),
                    ],
                  ),
                ],
              ),
            );
          }
          return AlertDialog(
            title: Text(offer.displayName(isAr)),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.posOffersBundlePrice} '
                      '${SunmiReceiptService.money(((offer.config['price_baisas'] as num?)?.toInt() ?? 0) / 1000.0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E8D54),
                      ),
                    ),
                    ...sections,
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: allSatisfied ? () => Navigator.pop(ctx, true) : null,
                child: Text(l10n.posOffersBundleAdd),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || confirmed != true) return;

    final picks = <Product>[];
    for (var g = 0; g < groups.length; g++) {
      counts[g].forEach((id, qty) {
        final product = productById[id];
        if (product == null) return;
        for (var i = 0; i < qty; i++) {
          picks.add(product);
        }
      });
    }
    controller.addBundle(offer, picks);
    final isArNow = Localizations.localeOf(context).languageCode == 'ar';
    _showPopupMessage(
      title: l10n.posNavOffers,
      message: offer.displayName(isArNow),
      tone: FeedbackTone.success,
    );
  }

  /// P-F6 — the Report chip's chooser: the full branch dashboard or the
  /// mid-shift X-report.
  Future<void> _openReportChooser() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final l10n = L10n.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.insights_rounded),
                title: Text(l10n.reportsTitle),
                subtitle: Text(l10n.reportsChooserDashboardSub),
                onTap: () => Navigator.pop(ctx, 'dashboard'),
              ),
              ListTile(
                leading: const Icon(Icons.print_rounded),
                title: Text(l10n.posMidShiftReportTitle),
                subtitle: Text(l10n.reportsChooserXReportSub),
                onTap: () => Navigator.pop(ctx, 'xreport'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(l10n.commonCancel),
                onTap: () => Navigator.pop(ctx, null),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'dashboard') {
      await _openBranchReports();
    } else if (action == 'xreport') {
      await _openMidShiftReport();
    }
  }

  /// P-F6 — the full-screen branch Reports dashboard, allowed only for the
  /// staff positions the merchant configured (settings.reports_positions).
  Future<void> _openBranchReports() async {
    final l10n = L10n.of(context);
    final position = ref.read(sessionServiceProvider).staff?.position;
    if (!controller.positionCanViewReports(position)) {
      _showPopupMessage(
        title: l10n.reportsNotAllowedTitle,
        message: l10n.reportsNotAllowedBody,
        tone: FeedbackTone.warning,
      );
      return;
    }
    final branch = await ref.read(configRepositoryProvider).getBranch();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BranchReportsScreen(branchName: branch?.name ?? ''),
      ),
    );
  }

  /// P-G1 — the full-screen Kitchen production screen, allowed only for the
  /// staff positions the merchant configured (settings.kitchen_positions).
  /// Online-only: the screen fetches fresh balances from pos_api on open.
  ///
  /// P-G1.6 — the walk-up gate: when the logged-in staff member is NOT
  /// allowed, instead of a dead end we prompt for a kitchen staff member's
  /// code (verified server-side against the same policy) and the Kitchen
  /// session runs AS them — the chef punches their code on the cashier's
  /// till, no logout/login dance. Batches attribute to the actual chef.
  Future<void> _openKitchen() async {
    final l10n = L10n.of(context);
    final staff = ref.read(sessionServiceProvider).staff;

    int? kitchenStaffId = staff?.id;
    String? kitchenStaffName;

    if (!controller.positionCanUseKitchen(staff?.position)) {
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => PinPromptDialog(
          title: l10n.kitchenGateTitle,
          hint: l10n.kitchenGateHint,
          confirmLabel: l10n.kitchenGateConfirm,
          confirmColor: const Color(0xFF35C28B),
        ),
      );
      if (pin == null || pin.isEmpty || !mounted) return;

      try {
        final verified = await ref
            .read(apiServiceProvider)
            .verifyKitchenPin(pin);
        if (!mounted) return;
        if (verified == null) {
          _showPopupMessage(
            title: l10n.kitchenNotAllowedTitle,
            message: l10n.kitchenGateInvalid,
            tone: FeedbackTone.warning,
          );
          return;
        }
        kitchenStaffId = verified.id;
        kitchenStaffName = verified.name;
      } on ApiException catch (e) {
        if (!mounted) return;
        _showPopupMessage(
          title: l10n.kitchenNotAllowedTitle,
          message: e.isNetwork ? l10n.kitchenOffline : e.message,
          tone: FeedbackTone.warning,
        );
        return;
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KitchenProductionScreen(
          staffId: kitchenStaffId,
          staffName: kitchenStaffName,
        ),
      ),
    );
    // Whatever the kitchen did (started/finished/cancelled a batch), the
    // server stock changed — refresh the cached config so the tiles agree.
    unawaited(ref.read(configRepositoryProvider).syncConfig());
  }

  /// Gap sweep G3 — the mid-shift X-report behind the top-bar Report chip:
  /// the CURRENT shift's sales so far, computed from the device-local order
  /// log (other terminals' sales are absent — tagged as such). Manager-gated
  /// for consistency with the Z-report (blueprint Phase 9 #88 "Daily sales
  /// summary (Manager only)"). Shows an opening-float + cash-taken MEMO,
  /// never a fabricated expected/variance.
  Future<void> _openMidShiftReport() async {
    final l10n = L10n.of(context);
    final shift = ref.read(sessionControllerProvider).openShift;
    if (shift == null) {
      _showPopupMessage(
        title: l10n.posMidShiftNoOpenShiftTitle,
        message: l10n.posMidShiftNoOpenShiftBody,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final ok = await _authorizeManager(
      subtitle: l10n.posMidShiftAuthSubtitle,
      description: l10n.posMidShiftAuthDesc,
    );
    if (!mounted) return;
    if (!ok) {
      _showPopupMessage(
        title: l10n.posManagerApprovalRequiredTitle,
        message: l10n.posMidShiftAuthDeniedBody,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final history = await LocalOrderStorageService.instance.loadOrderHistory();
    if (!mounted) return;
    final asOf = DateTime.now();
    final summary = buildLocalShiftSummary(
      history,
      openedAt: shift.openedAt,
      closedAt: asOf,
    );
    final session = ref.read(sessionServiceProvider);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _MidShiftReportDialog(
        summary: summary,
        openedAt: shift.openedAt,
        asOf: asOf,
        openingBaisas: shift.openingCashBaisas,
        onPrint: () async {
          final printed = await SunmiReceiptService.printTicketLines(
            buildMidShiftSummaryLines(
              summary,
              deviceCode: session.kioskId ?? '',
              staffName: session.staff?.name ?? '',
              openedAt: shift.openedAt,
              asOf: asOf,
              openingBaisas: shift.openingCashBaisas,
            ),
          );
          if (!printed) _handlePrintFailed('shift');
        },
      ),
    );
  }

  /// Phase C6 — manager-gated reprint of the LAST closed shift's Z-report
  /// (blueprint Phase 9 #88: "Daily sales summary (Manager only)").
  Future<void> _reprintLastShiftSummary() async {
    final l10n = L10n.of(context);
    final snapshot = ref.read(sessionServiceProvider).lastShiftSummary;
    final ticket = ShiftSummaryTicket.fromJson(snapshot, isReprint: true);
    if (ticket == null) {
      _showPopupMessage(
        title: l10n.posMenuNoShiftSummaryTitle,
        message: l10n.posMenuNoShiftSummaryBody,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final ok = await _authorizeManager(
      subtitle: l10n.posMenuShiftSummaryShort,
      description: l10n.posMenuShiftSummaryAuthDesc,
    );
    if (!mounted) return;
    if (!ok) {
      _showPopupMessage(
        title: l10n.posMenuApprovalRequiredTitle,
        message: l10n.posMenuApprovalNotGrantedBody,
        tone: FeedbackTone.warning,
      );
      return;
    }

    final printed = await SunmiReceiptService.printShiftSummary(ticket);
    if (!mounted) return;
    if (!printed) {
      _handlePrintFailed('shift');
      return;
    }
    _showPopupMessage(
      title: l10n.posMenuShiftSummaryPrintedTitle,
      message: l10n.posMenuShiftSummaryPrintedBody,
      tone: FeedbackTone.success,
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = L10n.of(ctx);
        return AlertDialog(
          title: Text(l10n.posMenuLogoutConfirmTitle),
          content: Text(l10n.posMenuLogoutConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.commonLogout),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref.read(sessionControllerProvider.notifier).logoutStaff();
    }
  }

  Widget _buildCurrentOrderPanel() {
    final l10n = L10n.of(context);
    final workspace = _workspace?.mainCart == true ? _workspace : null;
    final bill = workspace?.cartBill ?? _liveBill;
    final cart = workspace == null
        ? controller.cart
        : bill?.cartItems ?? <CartItem>[];
    final rawSubtotal = bill == null
        ? controller.rawSubtotal
        : bill.subtotal / 1000;
    final discount = bill == null
        ? controller.discountAmount
        : bill.discount / 1000;
    final comp = bill == null ? controller.compAmount : bill.comp / 1000;
    final subtotal = bill == null
        ? controller.subtotal
        : rawSubtotal - discount;
    final total = bill == null ? controller.total : bill.total / 1000;
    final dining =
        workspace?.dineIn == true ||
        (workspace == null && _isEditingDiningTable);
    final liveTable = workspace == null && _liveTable;
    final cancelAcceptedTable =
        liveTable &&
        _liveEditor?.detail?.billUuid != null &&
        BillCancelGroup.fromRounds(_liveEditor!.detail!.rounds).isNotEmpty;
    final reference = workspace == null
        ? controller.currentOrderReference
        : bill?.reference ?? '';
    if (_workspaceEditor != null && workspace == null) {
      return _glassPanel(
        tint: const Color(0xCCB9F1F4),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.posOrderPanelTitle,
              key: const ValueKey('workspace-current-order'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Expanded(child: _workspaceEditor!(_workspace!)),
          ],
        ),
      );
    }
    return _glassPanel(
      tint: const Color(0xCCB9F1F4),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The QR controller supplies state/actions; the cart below is shared.
          if (workspace != null) _workspaceEditor!(workspace),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.posOrderPanelTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF16252A),
                      ),
                    ),
                    Text(
                      '(${cart.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF24353B),
                      ),
                    ),
                    _OrderMetaChip(
                      label:
                          '${reference.isEmpty ? l10n.posOrderPanelNewOrder : l10n.posOrderPanelRef(reference)} | ${localizedOrderType(l10n, workspace == null
                              ? controller.selectedOrderType
                              : workspace.dineIn
                              ? OrderType.dineIn
                              : OrderType.quickOrder)}',
                    ),
                    if (dining) ...[
                      _OrderMetaChip(
                        label: l10n.posOrderPanelTableChip(
                          workspace?.tableLabel ?? _activeDiningTableLabel,
                        ),
                      ),
                      if (workspace == null &&
                          controller.activeDiningTableDefinition != null)
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
                icon: dining
                    ? Icons.grid_view_rounded
                    : Icons.cleaning_services_outlined,
                label: dining
                    ? l10n.posOrderPanelFloorPlan
                    : l10n.posOrderPanelClear,
                onTap: workspace != null
                    ? workspace.cartControls?.clear
                    : dining
                    ? () {
                        unawaited(controller.returnToDiningFloorPlan());
                      }
                    : controller.clearForNextOrder,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (dining &&
              _tableShadowMode != 'off' &&
              (_cartBill?.billSource == 'qr_web' ||
                  tableBillNeedsSheet(_tableShadowMode, _cartBill)))
            TextButton.icon(
              key: const ValueKey('cart-customer-bill'),
              onPressed: () =>
                  _openCustomerBill(controller.activeDiningTableId!),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(l10n.tableCustomerBillTitle),
            ),
          Expanded(
            child: cart.isEmpty
                ? const _EmptyOrderState()
                : Scrollbar(
                    controller: _currentOrderScrollController,
                    thumbVisibility: cart.length > 3,
                    child: ListView.separated(
                      controller: _currentOrderScrollController,
                      primary: false,
                      itemCount: cart.length,
                      physics: const BouncingScrollPhysics(),
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = cart[index];
                        final pulseNonce =
                            workspace == null &&
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
                            deleteKey:
                                workspace != null &&
                                    bill!.items[index]['draft_index'] is int
                                ? ValueKey(
                                    'workspace-remove-draft-${bill.items[index]['draft_index']}',
                                  )
                                : null,
                            onAdd: workspace != null
                                ? (workspace.cartControls?.quantity == null ||
                                          bill!.items[index]['pending_round_id'] !=
                                              null ||
                                          bill.items[index]['product_id']
                                              is! int
                                      ? null
                                      : () => workspace.cartControls!.quantity!(
                                          bill.items[index],
                                          item.qty + 1,
                                        ))
                                : () => controller.incrementCartItem(item),
                            onRemove: workspace != null
                                ? (workspace.cartControls?.quantity == null ||
                                          bill!.items[index]['pending_round_id'] !=
                                              null
                                      ? null
                                      : () => workspace.cartControls!.quantity!(
                                          bill.items[index],
                                          item.qty - 1,
                                        ))
                                : () => liveTable
                                      ? unawaited(_reduceTableItem(item))
                                      : controller.decreaseCartItem(item),
                            onDelete: workspace != null
                                ? (workspace.cartControls?.quantity == null ||
                                          bill!.items[index]['pending_round_id'] !=
                                              null
                                      ? null
                                      : () => workspace.cartControls!.quantity!(
                                          bill.items[index],
                                          0,
                                        ))
                                : () => liveTable
                                      ? unawaited(
                                          _reduceTableItem(item, remove: true),
                                        )
                                      : controller.removeCartItem(item),
                            onCustomize: workspace != null
                                ? (workspace.cartControls?.customize == null ||
                                          bill!.items[index]['pending_round_id'] !=
                                              null ||
                                          bill.items[index]['product_id']
                                              is! int
                                      ? null
                                      : () =>
                                            workspace.cartControls!.customize!(
                                              bill.items[index],
                                            ))
                                : () {
                                    unawaited(_openCustomizeDialog(item));
                                  },
                            onGift: workspace != null
                                ? null
                                : () => unawaited(_handleGiftItemToggle(item)),
                            allowGift: !liveTable,
                            sentAt: liveTable ? _sentTimeFor(item) : null,
                            highlighted: pulseNonce > 0,
                            pulseNonce: pulseNonce,
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          if (workspace != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: _buildWorkspaceCartStatus(workspace),
              ),
            ),
          if (liveTable || workspace?.dineIn == true) ...[
            if (workspace == null && _localTableRefusal != null)
              Text(_localTableRefusal!)
            else if (workspace == null &&
                (_cartBill?.needsReviewCount ?? 0) > 0)
              Text(
                ref.read(settingsControllerProvider).language == 'ar'
                    ? 'الجولة معلّقة للمراجعة. افتح فاتورة الطاولة قبل الدفع.'
                    : (_tableDraftBlocks(controller.activeDiningTableId!)
                          ? 'Send or remove unsent local items and finish sync before reviewing the customer round.'
                          : 'Round held for review. Open the table bill before payment.'),
              )
            else if (workspace == null && _tableSelectionMessage != null)
              Text(_tableSelectionMessage!),
            if (workspace == null &&
                _heldTableRounds > 0 &&
                _localTableRefusal != _closedTableMessage)
              TextButton(
                key: const ValueKey('table-correct-held-round'),
                onPressed: _tableSendBusy ? null : _correctHeldTableRounds,
                child: Text(
                  ref.read(settingsControllerProvider).language == 'ar'
                      ? 'تصحيح الجولة المعلّقة'
                      : 'Correct held round',
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('table-send-to-kitchen'),
                    onPressed: workspace != null
                        ? workspace.cartControls?.submit
                        : !_tableSendBusy &&
                              _localTableRefusal != _closedTableMessage &&
                              _hasTableUnsent &&
                              _tableSelectionMessage == null
                        ? _sendTableRound
                        : null,
                    icon: const Icon(Icons.soup_kitchen_outlined),
                    label: Text(l10n.tableSendToKitchen),
                  ),
                ),
                if ((workspace == null && _localTableRefusal == null) ||
                    workspace?.cartControls?.adjustmentSupported == true)
                  Flexible(
                    child: _tableAdjustmentControls(
                      workspaceControls: workspace?.cartControls,
                      compact: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (bill != null) _billAdjustmentContext(bill),
          _glassInsetCard(
            child: Column(
              children: [
                _summaryRow(l10n.posOrderPanelSubtotal, rawSubtotal),
                if (discount > 0) ...[
                  const SizedBox(height: 6),
                  _summaryRow(
                    bill != null
                        ? (bill.discountLabel.isEmpty
                              ? l10n.posOrderPanelDiscount
                              : bill.discountLabel)
                        : controller.discount.label.isEmpty
                        ? l10n.posOrderPanelDiscount
                        : controller.discount.label,
                    -discount,
                  ),
                ],
                const SizedBox(height: 6),
                _summaryRow(l10n.posOrderPanelNetSubtotal, subtotal),
                // Phase B — the manager comp write-off (given away, not sold).
                if (comp > 0) ...[
                  const SizedBox(height: 6),
                  _summaryRow(
                    l10n.posOrderPanelComp(
                      bill == null
                          ? controller.appliedComp?.reasonName ?? ''
                          : bill.compReason,
                    ),
                    -comp,
                  ),
                ],
                if (bill != null && bill.tax != 0) ...[
                  const SizedBox(height: 6),
                  _summaryRow(checkoutText(context, 'tax'), bill.tax / 1000),
                ],
                if (bill == null)
                  for (final t in controller.taxLines) ...[
                    const SizedBox(height: 6),
                    _summaryRow('${t.name} (${t.rateLabel}%)', t.amount),
                  ],
                if (workspace == null && controller.splitCount > 1) ...[
                  const SizedBox(height: 6),
                  _summaryRow(
                    l10n.posOrderPanelPerShare(controller.splitCount),
                    controller.activePaymentBaseTotal,
                  ),
                ],
                const SizedBox(height: 6),
                _summaryRow(l10n.posOrderPanelTotal, total, emphasize: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: dining
                    ? _ActionSquareCard(
                        icon: Icons.grid_view_rounded,
                        title: l10n.posOrderPanelBackToFloor,
                        tint: Color(0xFFDDF1FF),
                        foreground: Color(0xFF1C4257),
                        iconColor: Color(0xFF1B6B91),
                        onTap: () {
                          if (workspace != null) {
                            unawaited(workspace.requestClose());
                          } else {
                            unawaited(controller.returnToDiningFloorPlan());
                          }
                        },
                      )
                    : _ActionSquareCard(
                        icon: Icons.pause_circle_outline_rounded,
                        title: workspace == null
                            ? l10n.posOrderPanelHold
                            : (Localizations.localeOf(context).languageCode ==
                                      'ar'
                                  ? 'العودة إلى طلبات QR'
                                  : 'Back to QR Orders'),
                        tint: Color(0xFFFFD7A4),
                        iconColor: Color(0xFFA56A15),
                        onTap: () {
                          unawaited(
                            workspace != null
                                ? workspace.requestClose()
                                : _handleHoldOrder(),
                          );
                        },
                      ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _ActionSquareCard(
                  key: workspace != null
                      ? const ValueKey('workspace-void')
                      : null,
                  icon: dining
                      ? Icons.delete_sweep_rounded
                      : Icons.delete_outline_rounded,
                  title: workspace?.tableLabel != null || cancelAcceptedTable
                      ? (_arabicTable
                            ? 'إلغاء فاتورة الطاولة'
                            : 'Cancel table bill')
                      : dining
                      ? l10n.posOrderPanelClearTable
                      : l10n.posOrderPanelVoid,
                  tint: Color(0xFFF6F0F0),
                  foreground: Color(0xFF1F2A31),
                  iconColor: Color(0xFF6B757C),
                  onTap: workspace != null
                      ? workspace.cartControls?.voidBill
                      : cancelAcceptedTable
                      ? (_tableCancellationBusy || _tableSendBusy
                            ? null
                            : () async {
                                final id = controller.activeDiningTableId!;
                                final uuid = _liveEditor!.detail!.billUuid!;
                                await _ensureTableKitchen();
                                await _proveSentDraft(id);
                                if (mounted) {
                                  await _cancelTableBill(int.parse(id), uuid);
                                }
                              })
                      : dining
                      ? () {
                          if (liveTable) {
                            unawaited(
                              _clearSharedTable(
                                controller.activeDiningTableId!,
                              ),
                            );
                          } else {
                            unawaited(controller.clearActiveDiningTable());
                          }
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

  Widget _buildWorkspaceCartStatus(CurrentOrderWorkspace workspace) {
    final controls = workspace.cartControls;
    final copy = QuickCopy(
      Localizations.localeOf(context).languageCode == 'ar',
    );
    final notices =
        controls?.notices ?? (workspace.stale ? [copy.stale] : <String>[]);
    if (notices.isEmpty &&
        controls?.drafts.isNotEmpty != true &&
        controls?.actions.isNotEmpty != true) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notices.isNotEmpty || controls?.drafts.isNotEmpty == true)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 90),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final notice in notices.toSet()) Text(notice),
                  if (controls?.drafts.isNotEmpty == true &&
                      controls?.draftRows.isNotEmpty != true)
                    Text(copy.draft),
                  for (
                    var i = 0;
                    i <
                        (controls?.draftRows.isNotEmpty == true
                            ? 0
                            : controls?.drafts.length ?? 0);
                    i++
                  )
                    Row(
                      children: [
                        Expanded(child: Text(controls!.drafts[i])),
                        IconButton(
                          key: ValueKey('workspace-remove-draft-$i'),
                          tooltip: copy.pair(
                            'Remove unsent item',
                            'إزالة صنف غير مرسل',
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: controls.removeDraft == null
                              ? null
                              : () => controls.removeDraft!(i),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (controls != null &&
            (controls.draftRows.isEmpty ||
                controls.submit != null ||
                controls.retry != null ||
                workspace.stale))
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('workspace-refresh'),
                onPressed: controls.refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(copy.refresh),
              ),
              if (controls.retry != null)
                TextButton(
                  onPressed: controls.retry,
                  key: const ValueKey('workspace-retry'),
                  child: Text(copy.retry),
                ),
              if (controls.submit != null && !workspace.dineIn)
                TextButton(
                  onPressed: controls.submit,
                  key: const ValueKey('workspace-submit'),
                  child: Text(copy.submit),
                ),
              for (final action in controls.actions)
                TextButton(onPressed: action.run, child: Text(action.label)),
              if (controls.move != null)
                TextButton(
                  onPressed: controls.move,
                  key: const ValueKey('workspace-move'),
                  child: Text(copy.move),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCategoriesPanel() {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
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
          Text(
            l10n.posCatalogCategories,
            style: const TextStyle(
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
                  // Phase C4 — render the merchant Arabic label; the English
                  // [category] stays the identity (selection + icon key).
                  title: controller.categoryDisplayName(category, isAr),
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
            title: l10n.posCatalogFavourites,
            onTap: () {
              _showPlaceholderMessage(
                l10n.posCatalogFavouritesComingTitle,
                l10n.posCatalogFavouritesComingBody,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductsPanel() {
    final l10n = L10n.of(context);
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
          Text(
            l10n.posCatalogProducts,
            style: const TextStyle(
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
                      ? l10n.posCatalogSearchHint
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
                label: l10n.posCatalogViewList,
                selected: controller.productViewMode == ProductViewMode.list,
                onTap: () =>
                    controller.setProductViewMode(ProductViewMode.list),
              ),
              const SizedBox(width: 8),
              _TinyToggleChip(
                icon: Icons.grid_view_rounded,
                label: l10n.posCatalogViewGrid,
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
                                _catalogueProduct(product);
                              },
                              outOfStock:
                                  controller.isOutOfStock(product) ||
                                  (_workspace == null &&
                                      controller.isAtShelfCap(product)),
                              outsideHours: controller.isOutsideHours(product),
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
                              _catalogueProduct(product);
                            },
                            outOfStock:
                                controller.isOutOfStock(product) ||
                                (_workspace == null &&
                                    controller.isAtShelfCap(product)),
                            outsideHours: controller.isOutsideHours(product),
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
    final l10n = L10n.of(context);
    if (_workspace case final workspace? when !workspace.mainCart) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('workspace-pay'),
              onPressed: workspace.canPay ? workspace.requestPay : null,
              icon: const Icon(Icons.payments_outlined),
              label: Text(
                '${QuickCopy(ref.read(settingsControllerProvider).language == 'ar').pay} · ${SunmiReceiptService.money((workspace.bill?.total ?? 0) / 1000)}',
              ),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            key: const ValueKey('workspace-return'),
            onPressed: workspace.requestClose,
            icon: const Icon(Icons.arrow_back),
            label: Text(
              ref.read(settingsControllerProvider).language == 'ar'
                  ? 'العودة إلى القائمة'
                  : 'Back to list',
            ),
          ),
        ],
      );
    }
    final workspace = _workspace?.mainCart == true ? _workspace : null;
    return Row(
      children: [
        SizedBox(
          width: _currentOrderPanelWidth,
          child: _PayButton(
            total: workspace == null
                ? controller.activePaymentBaseTotal
                : (workspace.cartBill?.total ?? 0) / 1000,
            enabled:
                workspace?.canPay ??
                (_localTableRefusal != _closedTableMessage &&
                    (_cartBill?.needsReviewCount ?? 0) == 0),
            neutralBusy: _tableCancellationBusy,
            busy:
                _tableCancellationBusy ||
                (workspace == null
                    ? controller.isProcessingPayment || _tableCartPay.busy
                    : workspace.cartControls?.busy ?? false),
            settleBill:
                workspace == null &&
                tableBillNeedsSheet(_tableShadowMode, _cartBill),
            onTap: () {
              unawaited(_openPaymentPage());
            },
          ),
        ),
        const SizedBox(width: _panelGap),
        Expanded(
          child: IgnorePointer(
            ignoring: false,
            child: Opacity(
              opacity: 1,
              child: _glassPanel(
                height: 120,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: _FooterActionCard(
                        enabled: workspace == null,
                        icon: Icons.print_outlined,
                        title: l10n.commonPrint,
                        onTap: () async {
                          final printed = await controller.printOnly();
                          if (!mounted || !printed) return;
                          _showPopupMessage(
                            title: l10n.posNavReceiptPrintedTitle,
                            message: l10n.posNavReceiptPrintedBody,
                            tone: FeedbackTone.success,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FooterActionCard(
                        enabled: workspace == null,
                        icon: Icons.history_rounded,
                        title: l10n.posNavOrderHistory,
                        onTap: () {
                          unawaited(_openOrderHistoryDialog());
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FooterActionCard(
                        enabled: workspace == null,
                        icon: Icons.pause_circle_outline_rounded,
                        title: l10n.posNavHeldOrders,
                        onTap: () {
                          unawaited(_openHeldOrdersDialog());
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!_liveTable)
                      Expanded(
                        child: _FooterActionCard(
                          enabled: workspace == null,
                          icon: Icons.loyalty_outlined,
                          title: l10n.posNavLoyalty,
                          onTap: () {
                            unawaited(_openLoyaltyRedeem());
                          },
                        ),
                      ),
                    const SizedBox(width: 12),
                    // Device↔device transfer must be reachable with an EMPTY cart
                    // too (the payment console needs items), or this terminal
                    // could never RECEIVE a handheld's order.
                    Expanded(
                      child: _FooterActionCard(
                        enabled:
                            workspace == null ||
                            workspace.cartControls?.transfer != null,
                        icon: Icons.swap_horiz_rounded,
                        title: _incomingTransfers.isEmpty
                            ? l10n.posPaymentTransfer
                            : '${l10n.posPaymentTransfer} (${_incomingTransfers.length})',
                        onTap: () {
                          unawaited(_openTransferDialog());
                        },
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
    final l10n = L10n.of(context);
    return SizedBox(
      width: 132,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: ValueListenableBuilder<DateTime>(
          valueListenable: nowListenable,
          builder: (context, now, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _formatTime(l10n, now),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(l10n, now),
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

  String _formatTime(L10n l10n, DateTime value) {
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? l10n.posClockPm : l10n.posClockAm;
    return '${hour.toString().padLeft(2, '0')}:$minute:$second $meridiem';
  }

  String _formatDate(L10n l10n, DateTime value) {
    final months = [
      l10n.posClockMonthJan,
      l10n.posClockMonthFeb,
      l10n.posClockMonthMar,
      l10n.posClockMonthApr,
      l10n.posClockMonthMay,
      l10n.posClockMonthJun,
      l10n.posClockMonthJul,
      l10n.posClockMonthAug,
      l10n.posClockMonthSep,
      l10n.posClockMonthOct,
      l10n.posClockMonthNov,
      l10n.posClockMonthDec,
    ];

    return l10n.posClockDate(months[value.month - 1], value.day, value.year);
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
  // P-G6 — optional unread bubble (the Messages chip); 0 = no bubble.
  final int badgeCount;

  const _HeaderNavChip({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final chip = InkWell(
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
    if (badgeCount <= 0) return chip;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        chip,
        PositionedDirectional(
          top: -4,
          end: -4,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _CircleGlassButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: _chipDecoration(selected: false),
        child: Icon(icon, color: const Color(0xFF2A3136)),
      ),
    );
    if (badgeCount <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        PositionedDirectional(
          top: -5,
          end: -5,
          child: IgnorePointer(
            child: Container(
              key: const ValueKey('settings-stuck-sales-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OutlinePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

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
    final l10n = L10n.of(context);
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
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  size: 34,
                  color: Color(0xFF35505A),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.posCartEmptyTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A3F48),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.posCartEmptySubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
  final Key? deleteKey;
  final CartItem item;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final VoidCallback? onDelete;
  final VoidCallback? onCustomize;
  // P-F5 — toggle this line as a GIFT (manager-gated at the call site).
  final VoidCallback? onGift;
  final bool allowGift;
  final DateTime? sentAt;
  final bool highlighted;
  final int pulseNonce;

  const _OrderItemCard({
    super.key,
    this.deleteKey,
    required this.item,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
    required this.onCustomize,
    required this.onGift,
    this.allowGift = true,
    this.sentAt,
    this.highlighted = false,
    this.pulseNonce = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final detailLines = item.detailLinesFor(isAr);
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
                        item.product.displayName(isAr).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF19262E),
                        ),
                      ),
                    ),
                    InkWell(
                      key: deleteKey,
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
                if (sentAt != null)
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        l10n.tableSentAt(
                          '${sentAt!.hour.toString().padLeft(2, '0')}:'
                          '${sentAt!.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    const Spacer(),
                    // P-F5 — gift this line (purple when active).
                    if (allowGift)
                      InkWell(
                        onTap: onGift,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: item.gifted
                                ? const Color(0xFFEFE3F6)
                                : const Color(0xFFF2F8F9),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: item.gifted
                                  ? const Color(0xFFD4B8E4)
                                  : Colors.white.withValues(alpha: 0.86),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.card_giftcard_rounded,
                                size: 15,
                                color: item.gifted
                                    ? const Color(0xFF6E4385)
                                    : const Color(0xFF2F3E46),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item.gifted
                                    ? l10n.posCartGifted
                                    : l10n.posCartGift,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: item.gifted
                                      ? const Color(0xFF6E4385)
                                      : const Color(0xFF28363E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.posCartAddOn,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF28363E),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
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
                        '${item is WorkspaceCartItem && (item as WorkspaceCartItem).serverQuantity % 1 != 0 ? (item as WorkspaceCartItem).serverQuantity : item.qty}',
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
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final detailLines = item.detailLinesFor(isAr);

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
                  l10n.posCartQtyTimesName(
                    item.qty,
                    item.product.displayName(isAr),
                  ),
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
            l10n.posCartQtyTimesPrice(
              item.qty,
              SunmiReceiptService.money(item.unitPrice),
            ),
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
  // Phase C4 — the merchant's Arabic group name, display-only (empty = none;
  // [title] stays the identity used for selection keys and modifier groups).
  final String titleAr;
  final bool multiSelect;
  final bool requiredSelection;
  // Phase B — selection constraints (Additions §1.2): the sheet blocks Add
  // until every group holds at least [minSelections] options, and refuses
  // picks beyond [maxSelections]. 0 / null-equivalent = unbounded.
  final int minSelections;
  final int? maxSelections;
  // Option ids pre-selected when the sheet opens (merchant defaults).
  final Set<String> defaultOptionIds;
  final List<_ModifierOptionDefinition> options;

  const _ModifierGroupDefinition({
    required this.step,
    required this.title,
    this.titleAr = '',
    this.multiSelect = false,
    this.requiredSelection = false,
    this.minSelections = 0,
    this.maxSelections,
    this.defaultOptionIds = const <String>{},
    required this.options,
  });

  /// The group title to SHOW for [arabic] UI (English stays the identity).
  String displayTitle(bool arabic) =>
      arabic && titleAr.trim().isNotEmpty ? titleAr : title;
}

class _ModifierOptionDefinition {
  final String id;
  final String label;
  // Phase C4 — the merchant's Arabic option label, display-only (empty = none).
  final String labelAr;
  final double price;
  // P-G3 — the product behind this option is sold out at the branch (or
  // missing from the catalog): the tile greys out and refuses selection.
  final bool soldOut;

  const _ModifierOptionDefinition({
    required this.id,
    required this.label,
    this.labelAr = '',
    required this.price,
    this.soldOut = false,
  });

  /// The option label to SHOW for [arabic] UI (English stays the identity).
  String displayLabel(bool arabic) =>
      arabic && labelAr.trim().isNotEmpty ? labelAr : label;
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

  final Future<bool> Function(_CartItemCustomizationResult)? apply;
  const _CustomizeCartItemDialog({
    required this.item,
    required this.groups,
    this.apply,
  });

  @override
  State<_CustomizeCartItemDialog> createState() =>
      _CustomizeCartItemDialogState();
}

class _CustomizeCartItemDialogState extends State<_CustomizeCartItemDialog> {
  late final TextEditingController _notesController;
  late final Map<String, Set<String>> _selectedByGroup;
  bool _applying = false;
  bool _applyFailed = false;

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
      final selected = _selectedByGroup[group.title]!;
      // Phase B — pre-select the merchant defaults on a fresh line (an edit
      // keeps what the cashier already picked). Cap at the group max.
      if (selected.isEmpty && group.defaultOptionIds.isNotEmpty) {
        for (final id in group.defaultOptionIds) {
          if (group.maxSelections != null &&
              selected.length >= group.maxSelections!) {
            break;
          }
          // P-G3 — a sold-out default stays unselected.
          if (group.options.any((o) => o.id == id && !o.soldOut)) {
            selected.add(id);
          }
        }
      }
      if (group.requiredSelection && selected.isEmpty) {
        // P-G3 — auto-pick the first option that's actually sellable (all
        // sold out leaves the group empty and Apply blocked).
        for (final option in group.options) {
          if (!option.soldOut) {
            selected.add(option.id);
            break;
          }
        }
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
            labelAr: option.labelAr,
            price: option.price,
          ),
        );
      }
    }

    return modifiers;
  }

  bool get _canSubmit => widget.groups.every((group) {
    final selected = _selectedByGroup[group.title] ?? const <String>{};
    // Phase B — every group must reach its minimum (a legacy required
    // group without an explicit min behaves as min 1).
    final min = group.minSelections > 0
        ? group.minSelections
        : (group.requiredSelection ? 1 : 0);
    return selected.length >= min;
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
    // P-G3 — a sold-out option can't be picked (deselecting an already
    // selected one — e.g. on an edited line — stays allowed).
    if (option.soldOut &&
        !(_selectedByGroup[group.title]?.contains(option.id) ?? false)) {
      return;
    }
    setState(() {
      final selected = _selectedByGroup.putIfAbsent(
        group.title,
        () => <String>{},
      );

      if (group.multiSelect) {
        if (selected.contains(option.id)) {
          selected.remove(option.id);
        } else {
          // Phase B — refuse picks beyond the group's maximum.
          if (group.maxSelections != null &&
              selected.length >= group.maxSelections!) {
            return;
          }
          selected.add(option.id);
        }
        return;
      }

      selected
        ..clear()
        ..add(option.id);
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || _applying) return;
    final result = _CartItemCustomizationResult(
      modifiers: _selectedModifiers,
      notes: _notesController.text.trim(),
    );
    setState(() {
      _applying = true;
      _applyFailed = false;
    });
    try {
      if (widget.apply != null && !await widget.apply!(result)) return;
      if (mounted) Navigator.of(context).pop(result);
    } catch (_) {
      if (mounted) setState(() => _applyFailed = true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return PopScope(
      canPop: !_applying,
      child: AbsorbPointer(
        absorbing: _applying,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 56,
            vertical: 40,
          ),
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
                              l10n.posCustomizeTitle(
                                widget.item.product.displayName(isAr),
                              ),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF17252C),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.posCustomizeSubtitle,
                              style: const TextStyle(
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
                                  _selectedByGroup[group.title] ??
                                  const <String>{},
                              onToggle: (option) =>
                                  _toggleOption(group, option),
                            ),
                            const SizedBox(height: 18),
                          ],
                          Text(
                            l10n.posCustomizeNotesLabel,
                            style: const TextStyle(
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
                              hintText: l10n.posCustomizeNotesHint,
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
                  if (_applyFailed)
                    Text(
                      isAr
                          ? 'تعذر تطبيق التغييرات. أعد المحاولة.'
                          : 'Could not apply changes. Try again.',
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 70,
                          child: _OutlineActionButton(
                            label: l10n.commonCancel,
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
                            label: _applying
                                ? (isAr ? 'جارٍ التطبيق…' : 'Applying…')
                                : l10n.posCustomizeApply(
                                    SunmiReceiptService.money(
                                      _previewLineTotal,
                                    ),
                                  ),
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
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    // Phase B follow-up — surface WHY Apply is disabled: a group below its
    // minimum shows the requirement instead of leaving a silent dead button.
    final requiredMin = group.minSelections > 0
        ? group.minSelections
        : (group.requiredSelection ? 1 : 0);
    final unsatisfied = selectedIds.length < requiredMin;
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
              group.displayTitle(isAr),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF17252C),
              ),
            ),
            if (unsatisfied) ...[
              const SizedBox(width: 10),
              Text(
                l10n.posCustomizeMinHint(requiredMin),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB3261E),
                ),
              ),
            ],
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
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final l10n = L10n.of(context);
    // P-G3 — a sold-out option renders grey and refuses the tap (an already
    // selected one on an edited line stays tappable so it can be removed).
    final blocked = option.soldOut && !selected;
    return InkWell(
      key: ValueKey('customize-option-${option.id}'),
      onTap: blocked ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: multiSelect ? 12 : 10,
          vertical: multiSelect ? 14 : 16,
        ),
        decoration: BoxDecoration(
          color: option.soldOut
              ? const Color(0xFFF4F6F8)
              : selected
              ? const Color(0xFFF1FBF4)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: option.soldOut
                ? const Color(0xFFE0E7EB)
                : selected
                ? const Color(0xFF2C9255)
                : const Color(0xFFDCE6EA),
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
                      option.displayLabel(isAr),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: option.soldOut
                            ? const Color(0xFF9AA8B1)
                            : selected
                            ? const Color(0xFF175E36)
                            : const Color(0xFF2C3C45),
                      ),
                    ),
                  ),
                  if (option.soldOut)
                    Text(
                      l10n.posProductSoldOutBadge,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFB3261E),
                        letterSpacing: 0.5,
                      ),
                    )
                  else if (option.price > 0)
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
                          option.displayLabel(isAr),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: option.soldOut
                                ? const Color(0xFF9AA8B1)
                                : selected
                                ? const Color(0xFF175E36)
                                : const Color(0xFF364852),
                          ),
                        ),
                        if (option.soldOut) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.posProductSoldOutBadge,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFB3261E),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ] else if (option.price > 0) ...[
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
  final VoidCallback? onTap;

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
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? Colors.grey : const Color(0xFF2E3D45),
        ),
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
  final VoidCallback? onTap;

  const _ActionSquareCard({
    super.key,
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
    final l10n = L10n.of(context);
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
                    ? l10n.posProductsEmptySearchTitle
                    : l10n.posProductsEmptyCategoryTitle,
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
                    ? l10n.posProductsEmptySearchSubtitle
                    : l10n.posProductsEmptyCategorySubtitle,
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
                  label: l10n.posProductsClearSearch,
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
  // Gap sweep G1 — outside the product's daily window (distinct from sold out).
  final bool outsideHours;

  const _ProductListTile({
    required this.product,
    required this.onAdd,
    this.highlighted = false,
    this.pulseNonce = 0,
    this.outOfStock = false,
    this.outsideHours = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
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
        onTap: (outOfStock || outsideHours) ? null : onAdd,
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
                            product.displayName(isAr),
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
                            child: Text(
                              l10n.posProductSoldOutBadge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFB42318),
                              ),
                            ),
                          )
                        else if (outsideHours)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3E8F7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              l10n.posProductOutsideHoursBadge,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF3A4A8C),
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
                            child: Text(
                              l10n.posProductLowStockBadge,
                              style: const TextStyle(
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
                        _FilledMiniAction(
                          label: l10n.posProductAdd,
                          onTap: onAdd,
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
  // Gap sweep G1 — outside the product's daily window (distinct from sold out).
  final bool outsideHours;

  const _ProductTile({
    required this.product,
    required this.onAdd,
    this.compact = false,
    this.highlighted = false,
    this.pulseNonce = 0,
    this.outOfStock = false,
    this.outsideHours = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
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
            onTap: (outOfStock || outsideHours) ? null : onAdd,
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
                    child: Text(
                      l10n.posProductSoldOutBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                )
              else if (outsideHours)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF26315B).withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.posProductOutsideHoursBadge,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
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
                          l10n.posProductLowStockBadge,
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
                        product.displayName(isAr),
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
  final VoidCallback? onTap;

  const _PaymentTopActionCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.accent = const Color(0xFFAF6CFF),
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: InkWell(
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
  final String? subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback? onTap;

  const _PaymentMethodActionButton({
    required this.label,
    this.subtitle,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The stacked icon+label content is ~96px tall — slim buttons
            // (the 64px Gift pill) lay out horizontally instead so the
            // content always fits the given height.
            final compact = constraints.maxHeight < 110;
            if (compact) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              );
            }
            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 42, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
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
  final bool enabled;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _FooterActionCard({
    this.enabled = true,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
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
  final bool neutralBusy;
  final bool enabled;
  final bool settleBill;
  final VoidCallback onTap;

  const _PayButton({
    required this.total,
    required this.busy,
    required this.onTap,
    this.neutralBusy = false,
    this.settleBill = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return InkWell(
      onTap: busy || !enabled ? null : onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: busy || !enabled
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
                    neutralBusy
                        ? (Localizations.localeOf(context).languageCode == 'ar'
                              ? 'جارٍ مراجعة الإلغاء'
                              : 'Reviewing cancellation')
                        : busy
                        ? l10n.posPayBtnProcessing
                        : settleBill
                        ? l10n.tableSettleBill
                        : l10n.posPayBtnProcessToPay,
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
                    neutralBusy
                        ? (Localizations.localeOf(context).languageCode == 'ar'
                              ? 'بانتظار قرار الموظف'
                              : 'Waiting for staff decision')
                        : busy
                        ? l10n.posPayBtnCompletingOrder
                        : settleBill
                        ? l10n.tableCustomerBillTitle
                        : l10n.posPayBtnPayAmount(
                            SunmiReceiptService.money(total),
                          ),
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

/// Shared "seated for" formatter — pure so the table card can re-derive it
/// from the live clock tick (P-F1: the badge used to be a frozen snapshot).
String _formatOccupancyDurationAt(DateTime? value, DateTime now) {
  if (value == null) return '0m';
  final difference = now.difference(value);
  if (difference.inHours >= 1) {
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  final minutes = difference.inMinutes;
  return '${minutes < 1 ? 1 : minutes}m';
}

class _DiningTableCard extends StatelessWidget {
  final bool live, sending, searchMatch;
  final bool customerOccupied;
  final String? customerReference;
  final int pendingRounds;
  final RemoteTableState? remote;
  final DateTime now;
  final int remoteFailures;
  final DateTime? lastFeedOkAt;
  final DiningTableDefinition table;
  final DiningTableSession? session;
  final DiningTableStatus status;
  // P-F1 — the card derives the seated-for badge from the live clock so it
  // ticks while the cashier watches the floor plan.
  final ValueListenable<DateTime> clock;
  final VoidCallback onTap;
  // Gap sweep G2 — long-press opens the table actions sheet (move/merge);
  // null = no actions for this status. P-F1 adds [onActions], a VISIBLE
  // button for the same sheet (long-press alone was undiscoverable).
  final VoidCallback? onLongPress;
  final VoidCallback? onActions;
  // Joined tables: on a linked seat, [linkedToLabel] is the head's name and
  // [groupTotal] is the shared bill; on a head, [linkedCount] is how many seats
  // are joined under it.
  final String? linkedToLabel;
  final double? groupTotal;
  final int linkedCount;

  const _DiningTableCard({
    required this.table,
    required this.session,
    required this.status,
    required this.clock,
    required this.now,
    required this.onTap,
    this.remote,
    this.remoteFailures = 0,
    this.lastFeedOkAt,
    this.onLongPress,
    this.onActions,
    this.linkedToLabel,
    this.groupTotal,
    this.linkedCount = 0,
    this.live = false,
    this.sending = false,
    this.searchMatch = false,
    this.pendingRounds = 0,
    this.customerOccupied = false,
    this.customerReference,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final staffOpened = const {
      'main_pos',
      'handheld',
      'staff_till',
      'staff_handheld',
    }.contains(remote?.origin);
    final occupiedLabel = staffOpened
        ? (Localizations.localeOf(context).languageCode == 'ar'
              ? 'مشغولة · فتحها الموظف'
              : 'Occupied · opened by staff')
        : l10n.tableCustomerOccupied;
    final displayStatus = customerOccupied
        ? DiningTableStatus.occupied
        : status;
    final statusColor = switch (displayStatus) {
      DiningTableStatus.available => const Color(0xFF218947),
      DiningTableStatus.occupied => const Color(0xFFC9470F),
      DiningTableStatus.paid => const Color(0xFF277C4E),
    };
    final ticketColor = switch (displayStatus) {
      DiningTableStatus.available => const Color(0xFFDAF4E4),
      DiningTableStatus.occupied => const Color(0xFFFF7C22),
      DiningTableStatus.paid => const Color(0xFF3C8A57),
    };
    final background = switch (displayStatus) {
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
    final hasTicket =
        customerOccupied ||
        (status != DiningTableStatus.available && session != null);
    final greyed =
        !customerOccupied &&
        remote?.origin == 'station' &&
        const {'open', 'billing'}.contains(remote?.seatingStatus) &&
        status == DiningTableStatus.available;

    // Same grid-slot size + position, but the card takes the table's SHAPE.
    // Children clip to it: the centered name + status sit inside every shape;
    // the corner ticket badge / dot show only on the rectangular shapes.
    final cardShape = _diningCardShape(
      table.shape,
      BorderSide(
        color: searchMatch
            ? const Color(0xFF356BDD)
            : displayStatus == DiningTableStatus.available
            ? const Color(0xFFE8EEF0)
            : statusColor.withValues(alpha: 0.2),
        width: 2,
      ),
    );

    final card = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      customBorder: cardShape,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: greyed
                ? [
                    for (final color in background)
                      Color.alphaBlend(
                        const Color(0xFF808080).withValues(alpha: 0.08),
                        color,
                      ),
                  ]
                : background,
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
            if (displayStatus == DiningTableStatus.occupied)
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
                      Icon(
                        customerOccupied && !staffOpened
                            ? Icons.phone_android_rounded
                            : Icons.receipt_long_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        customerOccupied
                            ? customerReference ?? remote?.reference ?? ''
                            : status == DiningTableStatus.paid
                            ? l10n.posDiningTicketNumber(
                                '${session!.orderNumber ?? '-'}',
                              )
                            : l10n.posDiningRefNumber(session!.orderReference),
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
            // P-F1 — the occupied marker is now a real button into the
            // Move/Merge actions sheet (it was a decorative dot; long-press
            // was the only — and invisible — way in). Its own InkWell wins
            // the gesture arena over the card's onTap.
            if (displayStatus == DiningTableStatus.occupied &&
                onActions != null)
              Positioned(
                top: 10,
                right: 10,
                child: Tooltip(
                  message: l10n.posDiningTableActionsTooltip,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFFF7A1A,
                          ).withValues(alpha: 0.42),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: const Color(0xFFFF7A1A),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onActions,
                        child: const SizedBox(
                          width: 30,
                          height: 30,
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (displayStatus == DiningTableStatus.occupied)
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
                    if (customerOccupied)
                      _StatusCapsule(
                        label: occupiedLabel,
                        color: const Color(0xFFFFE0C5),
                        foreground: const Color(0xFF9E3410),
                      )
                    else if (status == DiningTableStatus.available)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _TinyInfoBadge(
                            icon: Icons.people_alt_outlined,
                            label: l10n.posDiningSeats(table.seats),
                          ),
                          _StatusCapsule(
                            label: l10n.posDiningStatusAvailable,
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
                            label: SunmiReceiptService.money(
                              groupTotal ?? session!.total,
                            ),
                            strong: true,
                            foreground: const Color(0xFF9E3410),
                          ),
                          // P-F1 — only this tiny badge listens to the
                          // 1-second clock, so the seated-for time ticks
                          // without rebuilding the whole floor plan.
                          ValueListenableBuilder<DateTime>(
                            valueListenable: clock,
                            builder: (context, now, _) => _TinyInfoBadge(
                              icon: Icons.schedule_rounded,
                              label: _formatOccupancyDurationAt(
                                session?.occupiedAt,
                                now,
                              ),
                              tint: const Color(0xFFFFE0C5),
                              foreground: const Color(0xFF9E4F11),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 15,
                            color: const Color(0xFFF4B178),
                          ),
                          Text(
                            l10n.posDiningStatusOccupied,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEA6614),
                            ),
                          ),
                          // Joined-tables markers (device-local).
                          if (linkedToLabel != null)
                            _TinyInfoBadge(
                              icon: Icons.link_rounded,
                              label: l10n.posDiningJoinedWith(linkedToLabel!),
                              tint: const Color(0xFFEDE7FB),
                              foreground: const Color(0xFF6B4FBB),
                            ),
                          if (linkedCount > 0)
                            _TinyInfoBadge(
                              icon: Icons.link_rounded,
                              label: '+$linkedCount',
                              tint: const Color(0xFFEDE7FB),
                              foreground: const Color(0xFF6B4FBB),
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
                          Text(
                            l10n.posDiningStatusPaidClear,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF247246),
                            ),
                          ),
                        ],
                      ),
                    if (status == DiningTableStatus.occupied &&
                        remote?.billSource == 'qr_web') ...[
                      const SizedBox(height: 5),
                      _TinyInfoBadge(
                        label: l10n.tableShared,
                        icon: Icons.link_rounded,
                        tint: const Color(0xFFFFE0C5),
                      ),
                    ],
                    if (remote != null) ...[
                      const SizedBox(height: 5),
                      DiningServerBadge(
                        remote: remote!,
                        localStatus: status,
                        localReference: session?.orderReference,
                        now: now,
                        failures: remoteFailures,
                        lastFeedOkAt: lastFeedOkAt,
                      ),
                    ],
                    if (live)
                      DiningTableActivityBadge(
                        mode: 'live',
                        sending: sending,
                        pendingRounds: pendingRounds,
                        needsReview: remote?.needsReviewCount ?? 0,
                      )
                    else if (pendingRounds > 0 && remote != null)
                      Text(
                        l10n.tablePendingBell(pendingRounds),
                        key: const ValueKey('customer-table-pending'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF755411),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return customerOccupied
        ? Semantics(label: '${table.name} · $occupiedLabel', child: card)
        : card;
  }
}

/// Pure informational projection; it has no callbacks or controller dependency.
class DiningServerBadge extends StatelessWidget {
  const DiningServerBadge({
    super.key,
    required this.remote,
    required this.localStatus,
    required this.now,
    this.localReference,
    this.failures = 0,
    this.lastFeedOkAt,
  });
  final RemoteTableState remote;
  final DiningTableStatus localStatus;
  final String? localReference;
  final DateTime now;
  final int failures;
  final DateTime? lastFeedOkAt;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // An empty successful feed validates the unchanged board too. Display age
    // from that observation without rewriting the stored board timestamp.
    final verifiedAt =
        lastFeedOkAt != null && lastFeedOkAt!.isAfter(remote.fetchedAt)
        ? lastFeedOkAt!
        : remote.fetchedAt;
    final seconds = math.max(0, now.difference(verifiedAt).inSeconds);
    final age = seconds < 60
        ? l10n.tableServerAgeSeconds(seconds)
        : l10n.tableServerAgeMinutes(seconds ~/ 60);
    final stale = seconds > 60 || failures > 0;
    final qrParty =
        remote.origin == 'station' &&
        const {'open', 'billing'}.contains(remote.seatingStatus) &&
        localStatus == DiningTableStatus.available;
    final payment = remote.awaitingPayment || remote.chargeClaimLive;
    var label = stale
        ? l10n.tableServerStale(age)
        : payment
        ? l10n.tableServerPayment
        : !remote.occupied
        ? l10n.tableServerFree(age)
        : qrParty
        ? l10n.tableServerQr(remote.reference ?? '—', age)
        : l10n.tableServerOccupied(age);
    if (!stale &&
        !payment &&
        remote.occupied &&
        localStatus == DiningTableStatus.occupied &&
        remote.reference != localReference &&
        // Local REF aliases and server T references are different namespaces.
        !(localReference?.startsWith('REF-') == true &&
            remote.reference?.startsWith('T-') == true)) {
      label += l10n.tableServerReferenceDiffers;
    }
    if (remote.needsReviewCount > 0) {
      label += l10n.tableServerNeedsReview(remote.needsReviewCount);
    }
    final color = remote.needsReviewCount > 0
        ? const Color(0xFFB42318)
        : !stale && (qrParty || payment)
        ? const Color(0xFF9A6700)
        : const Color(0xFF687873);
    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          key: ValueKey('table-server-badge-${remote.tableId}'),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            border: !stale && qrParty ? Border.all(color: color) : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontStyle: stale ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Exercises the actual private card, not a replica of its gestures or layout.
@visibleForTesting
Widget buildDiningTableCardForTest({
  required DiningTableDefinition table,
  required DiningTableStatus status,
  required ValueListenable<DateTime> clock,
  required VoidCallback onTap,
  DiningTableSession? session,
  RemoteTableState? remote,
  int failures = 0,
  DateTime? lastFeedOkAt,
  bool live = false,
  bool sending = false,
  bool searchMatch = false,
  int pendingRounds = 0,
  bool customerOccupied = false,
  String? customerReference,
  VoidCallback? onLongPress,
}) => _DiningTableCard(
  table: table,
  session: session,
  status: status,
  clock: clock,
  now: clock.value,
  onTap: onTap,
  remote: remote,
  remoteFailures: failures,
  lastFeedOkAt: lastFeedOkAt,
  live: live,
  sending: sending,
  searchMatch: searchMatch,
  pendingRounds: pendingRounds,
  customerOccupied: customerOccupied,
  customerReference: customerReference,
  onLongPress: onLongPress,
);

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

/// Gap sweep G3 — the compact on-screen mid-shift (X-report) dialog. Money
/// = baisas/1000 with the standard 3-dp format; figures are DEVICE-LOCAL.
class _MidShiftReportDialog extends StatelessWidget {
  final ShiftSalesSummary summary;
  final DateTime openedAt;
  final DateTime asOf;
  final int openingBaisas;
  final Future<void> Function() onPrint;

  const _MidShiftReportDialog({
    required this.summary,
    required this.openedAt,
    required this.asOf,
    required this.openingBaisas,
    required this.onPrint,
  });

  static String _money(int baisas) {
    final sign = baisas < 0 ? '-' : '';
    return '$sign${(baisas.abs() / 1000).toStringAsFixed(3)}';
  }

  String _tenderLabel(L10n l10n, String method) => switch (method) {
    'cash' => l10n.displayMethodCash,
    'card' => l10n.displayMethodCard,
    'gift' => l10n.displayMethodGift,
    _ => method,
  };

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color color = Colors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: bold ? 18 : 14,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final s = summary;
    final cashTaken = s.tenders
        .where((t) => t.method == 'cash')
        .fold<int>(0, (sum, t) => sum + t.amountBaisas);

    return Dialog(
      backgroundColor: const Color(0xFF102028),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.posMidShiftReportTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.posMidShiftThisDeviceOnly,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE0A93B), fontSize: 12),
              ),
              const Divider(color: Colors.white24, height: 24),
              _row(l10n.posMidShiftOrders, '${s.orderCount}'),
              _row(l10n.posMidShiftGross, _money(s.grossBaisas)),
              if (s.discountBaisas > 0)
                _row(l10n.posMidShiftDiscounts, '-${_money(s.discountBaisas)}'),
              if (s.compBaisas > 0)
                _row(l10n.posMidShiftComps, '-${_money(s.compBaisas)}'),
              if (s.taxBaisas > 0)
                _row(l10n.posMidShiftTax, _money(s.taxBaisas)),
              _row(l10n.posMidShiftTotal, _money(s.grandBaisas), bold: true),
              if (s.tenders.isNotEmpty) ...[
                const Divider(color: Colors.white24, height: 24),
                for (final tender in s.tenders)
                  _row(
                    '${_tenderLabel(l10n, tender.method)} (${tender.count})',
                    _money(tender.amountBaisas),
                  ),
              ],
              if (s.roundUpBaisas > 0)
                _row(l10n.posMidShiftRoundUp, _money(s.roundUpBaisas)),
              if (s.voidCount > 0)
                _row(
                  '${l10n.posMidShiftVoids} (${s.voidCount})',
                  _money(s.voidTotalBaisas),
                  color: const Color(0xFFFF6B6B),
                ),
              const Divider(color: Colors.white24, height: 24),
              _row(l10n.posMidShiftOpeningFloat, _money(openingBaisas)),
              _row(l10n.posMidShiftCashTaken, _money(cashTaken)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPrint,
                      icon: const Icon(
                        Icons.print_outlined,
                        color: Colors.white70,
                      ),
                      label: Text(
                        l10n.commonPrint,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonClose),
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

class _HeldOrdersPanel extends StatelessWidget {
  final List<HeldOrderRecord> records;
  final Future<void> Function(HeldOrderRecord record) onResume;
  final Future<void> Function(HeldOrderRecord record) onDiscard;

  const _HeldOrdersPanel({
    required this.records,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (records.isEmpty) {
      return _StorageEmptyState(
        icon: Icons.pause_circle_outline_rounded,
        title: l10n.posStorageHeldEmptyTitle,
        message: l10n.posStorageHeldEmptyMessage,
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: records.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final record = records[index];
        return _HeldOrderCard(
          record: record,
          onResume: () => onResume(record),
          onDiscard: () => onDiscard(record),
        );
      },
    );
  }
}

class _OrderHistoryPanel extends StatelessWidget {
  final List<OrderHistoryRecord> records;
  final Future<void> Function() onRegisterManager;
  final Future<void> Function(OrderHistoryRecord record) onPrint;
  final Future<void> Function(OrderHistoryRecord record) onPrintKitchen;
  final Future<void> Function(OrderHistoryRecord record) onCancel;
  final Future<void> Function(OrderHistoryRecord record) onReversal;

  const _OrderHistoryPanel({
    required this.records,
    required this.onReversal,
    required this.onRegisterManager,
    required this.onPrint,
    required this.onPrintKitchen,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      children: [
        _ManagerAuthorizationBanner(onRegister: onRegisterManager),
        const SizedBox(height: 14),
        Expanded(
          child: records.isEmpty
              ? _StorageEmptyState(
                  icon: Icons.history_rounded,
                  title: l10n.posStorageHistoryEmptyTitle,
                  message: l10n.posStorageHistoryEmptyMessage,
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
                      onPrintKitchen: () => onPrintKitchen(record),
                      onCancel: () => onCancel(record),
                      onReversal: () => onReversal(record),
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
    final l10n = L10n.of(context);
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.posFingerprintBannerTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF18262E),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.posFingerprintBannerMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
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
              label: l10n.posFingerprintRegisterManager,
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
  final VoidCallback onDiscard;

  const _HeldOrderCard({
    required this.record,
    required this.onResume,
    required this.onDiscard,
  });

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
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
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
                      l10n.posStorageHeldRef(record.orderReference),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF18262E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _OrderMetaChip(
                      label: localizedOrderType(l10n, record.orderType),
                    ),
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
                      label: l10n.posStorageItemsCount(
                        record.draft.items.length,
                      ),
                    ),
                    _InfoBadge(
                      icon: Icons.payments_outlined,
                      label: SunmiReceiptService.money(_total),
                    ),
                    if (record.draft.splitCount > 1)
                      _InfoBadge(
                        icon: Icons.call_split_rounded,
                        label: l10n.posStorageSplitBadge(
                          record.draft.splitCount,
                        ),
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
                      .map(
                        (item) => l10n.posStorageItemQtyName(
                          item.qty,
                          item.product.displayName(isAr),
                        ),
                      )
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FilledActionButton(
                  label: l10n.posStorageContinueOrder,
                  onTap: onResume,
                ),
                const SizedBox(height: 10),
                // Phase C2 — discard (voids the server mirror too).
                SizedBox(
                  height: 52,
                  child: _OutlineActionButton(
                    label: l10n.posStorageDiscard,
                    icon: Icons.delete_outline_rounded,
                    onTap: onDiscard,
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

class _OrderHistoryCard extends StatelessWidget {
  final VoidCallback onReversal;
  final OrderHistoryRecord record;
  final VoidCallback onPrint;
  final VoidCallback onPrintKitchen;
  final VoidCallback onCancel;

  const _OrderHistoryCard({
    required this.record,
    required this.onReversal,
    required this.onPrint,
    required this.onPrintKitchen,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final snapshot = record.snapshot;
    // P-F1 — paid server-history records ARE cancellable (full-order void,
    // mirrored to pos_api); only genuinely terminal states stay locked.
    final canCancel =
        !snapshot.isFullyCanceled &&
        !record.isServerTerminal &&
        (!record.fromServer || snapshot.serverOrderUuid.isNotEmpty);

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
                      // Prefer the official receipt, then the QR temporary
                      // reference, else the existing 'Order #N' fallback.
                      switch (snapshot.staffReference) {
                        final ref? => 'Order $ref',
                        null => l10n.posStorageOrderNumber(record.orderNumber),
                      },
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF18262E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _OrderMetaChip(
                      label: localizedOrderType(l10n, record.orderType),
                    ),
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
                        label: localizedPaymentMethod(
                          l10n,
                          snapshot.paymentMethod,
                        ),
                      ),
                    _InfoBadge(
                      icon: snapshot.cancellations.isEmpty
                          ? Icons.task_alt_rounded
                          : Icons.cancel_rounded,
                      label: localizedPaymentStatus(
                        l10n,
                        snapshot.paymentStatus,
                      ),
                    ),
                    _InfoBadge(
                      icon: Icons.payments_outlined,
                      label: SunmiReceiptService.money(snapshot.payableTotal),
                    ),
                    if (snapshot.splitPayments.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.call_split_rounded,
                        label: l10n.posStorageSplitsCount(
                          snapshot.splitPayments.length,
                        ),
                      ),
                    if (snapshot.cancellations.isNotEmpty)
                      _InfoBadge(
                        icon: Icons.remove_circle_outline_rounded,
                        label: l10n.posStorageCanceledAmount(
                          SunmiReceiptService.money(snapshot.canceledAmount),
                        ),
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
                      .map(
                        (item) => l10n.posStorageItemQtyName(
                          (item['qty'] as num?)?.toInt() ?? 1,
                          // Phase C4 — prefer the snapshot's Arabic name when
                          // the UI locale is Arabic ('name' stays the identity).
                          isAr &&
                                  (item['nameAr']?.toString().isNotEmpty ??
                                      false)
                              ? item['nameAr'].toString()
                              : item['name']?.toString() ?? '',
                        ),
                      )
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
                    label: l10n.commonPrint,
                    icon: Icons.print_outlined,
                    onTap: onPrint,
                  ),
                ),
                TextButton(
                  onPressed: onReversal,
                  child: Text(softposText(context, 'title')),
                ),
                const SizedBox(height: 10),
                // Phase C1 — manager-gated kitchen-ticket reprint (§6.10).
                SizedBox(
                  height: 52,
                  child: _OutlineActionButton(
                    label: l10n.posStorageKitchen,
                    icon: Icons.restaurant_rounded,
                    onTap: onPrintKitchen,
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
    final l10n = L10n.of(context);
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
                  enabled ? l10n.commonCancel : l10n.posStorageCanceled,
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

/// P-F3 — "which loyalty program does this order earn under?" Shown on
/// customer attach when the merchant runs 2+ active earn programs. All
/// programs start checked (the default behavior); the customer/cashier
/// unticks the ones to skip. Pops the chosen rule ids, or null on cancel
/// (= keep earning under all).
class _EarnProgramPickerDialog extends StatefulWidget {
  final List<LoyaltyRule> rules;
  final CustomerSearchResult customer;

  const _EarnProgramPickerDialog({required this.rules, required this.customer});

  @override
  State<_EarnProgramPickerDialog> createState() =>
      _EarnProgramPickerDialogState();
}

class _EarnProgramPickerDialogState extends State<_EarnProgramPickerDialog> {
  late final Set<int> _selected = widget.rules.map((r) => r.id).toSet();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.posEarnPickerTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.posEarnPickerSubtitle(widget.customer.name),
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 10),
            for (final rule in widget.rules)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(rule.id),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selected.add(rule.id);
                  } else {
                    _selected.remove(rule.id);
                  }
                }),
                title: Row(
                  children: [
                    Icon(
                      rule.isVisitBased
                          ? Icons.local_activity_outlined
                          : Icons.stars_rounded,
                      size: 18,
                      color: const Color(0xFF8E5BA6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 26),
                  child: Text(
                    rule.isVisitBased
                        ? l10n.posCustomerDetailsStampProgress(
                            widget.customer.stampsForRule(rule.id),
                            rule.stampsRequired,
                          )
                        : l10n.posLoyaltySummaryPoints(
                            widget.customer.pointsForRule(rule.id),
                          ),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: Text(l10n.posEarnPickerConfirm),
        ),
      ],
    );
  }
}

/// P-F2 — the customer profile dialog: vehicle plates (tap one to put it on
/// the order), per-rule loyalty balances (points / stamp progress), wallet.
/// Pops `plate:PLATE` when a plate is picked, `redeem` for the redeem flow.
class _CustomerDetailsDialog extends StatelessWidget {
  final CustomerSearchResult customer;
  final List<LoyaltyRule> rules;
  final String currentPlate;

  const _CustomerDetailsDialog({
    required this.customer,
    required this.rules,
    required this.currentPlate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final activeRules = rules.where((r) => r.isActive).toList();
    final hasRedeemables = customer.loyalty.any(
      (b) => b.points > 0 || b.stamps > 0,
    );

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
          color: Color(0xFF6B7E8A),
        ),
      ),
    );

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF1E8D54)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (customer.phone.isNotEmpty)
                  Text(
                    customer.phone,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7E8A),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (customer.walletBalance > 0)
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                      color: Color(0xFF3D5563),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${l10n.posCustomerDetailsWallet}: '
                      '${SunmiReceiptService.money(customer.walletBalance)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              sectionLabel(l10n.posCustomerDetailsPlates.toUpperCase()),
              if (customer.plates.isEmpty)
                Text(
                  l10n.posCustomerDetailsNoPlates,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B9DA8),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final plate in customer.plates)
                      ActionChip(
                        avatar: Icon(
                          plate == currentPlate
                              ? Icons.check_circle_rounded
                              : Icons.directions_car_outlined,
                          size: 18,
                          color: const Color(0xFF1E8D54),
                        ),
                        label: Text(
                          plate,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onPressed: () =>
                            Navigator.of(context).pop('plate:$plate'),
                      ),
                  ],
                ),
              sectionLabel(l10n.posCustomerDetailsLoyalty.toUpperCase()),
              if (activeRules.isEmpty)
                Text(
                  l10n.posLoyaltyNoneYet,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B9DA8),
                  ),
                )
              else
                Column(
                  children: [
                    for (final rule in activeRules)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              rule.isVisitBased
                                  ? Icons.local_activity_outlined
                                  : Icons.stars_rounded,
                              size: 18,
                              color: const Color(0xFF8E5BA6),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                rule.name,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              rule.isVisitBased
                                  ? l10n.posCustomerDetailsStampProgress(
                                      customer.stampsForRule(rule.id),
                                      rule.stampsRequired,
                                    )
                                  : l10n.posLoyaltySummaryPoints(
                                      customer.pointsForRule(rule.id),
                                    ),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E8D54),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).commonClose),
        ),
        FilledButton.icon(
          onPressed: hasRedeemables
              ? () => Navigator.of(context).pop('redeem')
              : null,
          icon: const Icon(Icons.redeem_rounded, size: 18),
          label: Text(L10n.of(context).posCustomerDetailsRedeem),
        ),
      ],
    );
  }
}

/// P-F1 — the manager-PIN fallback dialog: masked PIN entry on an on-screen
/// keypad, verified server-side (pos_api checks the PIN against active staff
/// whose position is in the merchant's manager_approval_positions policy).
/// Pops true on approval; null/false = declined. Online-only — offline the
/// fingerprint remains the approval path.
class _ManagerPinDialog extends StatefulWidget {
  final PosApiService api;

  const _ManagerPinDialog({required this.api, this.identityRequired = false});
  final bool identityRequired;

  @override
  State<_ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<_ManagerPinDialog> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  void _append(String digit) {
    if (_busy || _pin.length >= 8) return;
    setState(() {
      _pin = '$_pin$digit';
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    if (_busy || _pin.length < 4) return;
    final l10n = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Object? approver = widget.identityRequired
          ? await widget.api.verifyLoyaltyApprover(_pin)
          : await widget.api.verifyManagerPin(_pin);
      if (!mounted) return;
      if (approver == null) {
        setState(() {
          _busy = false;
          _pin = '';
          _error = l10n.posManagerPinInvalid;
        });
        return;
      }
      Navigator.of(context).pop(widget.identityRequired ? approver : true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isNetwork ? l10n.posManagerPinOffline : e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final dots = List<Widget>.generate(
      _pin.length,
      (_) => Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: const BoxDecoration(
          color: Color(0xFF1E8D54),
          shape: BoxShape.circle,
        ),
      ),
    );

    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: const Color(0xFFF2F7FA),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : (onTap ?? () => _append(label)),
            child: SizedBox(
              height: 52,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 20, color: const Color(0xFF39505B))
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF20323C),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    return AlertDialog(
      title: Text(l10n.posManagerPinTitle),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.posManagerPinSubtitle,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 16),
            Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _pin.isEmpty
                  ? const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: Color(0xFF8B9DA8),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: dots,
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB84524),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Keypad stays LTR in Arabic (digit order never mirrors).
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Row(children: [key('1'), key('2'), key('3')]),
                  Row(children: [key('4'), key('5'), key('6')]),
                  Row(children: [key('7'), key('8'), key('9')]),
                  Row(
                    children: [
                      key(
                        '',
                        icon: Icons.backspace_outlined,
                        onTap: _backspace,
                      ),
                      key('0'),
                      key('', icon: Icons.check_rounded, onTap: _verify),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(
                  context,
                ).pop(widget.identityRequired ? null : false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _busy || _pin.length < 4 ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.posManagerPinVerify),
        ),
      ],
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
    final l10n = L10n.of(context);
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1E8D54),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          l10n.posFingerprintWaiting,
                          style: const TextStyle(
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
      VoidReasonRef? voidReason,
    });

class _OrderCancellationPage extends StatefulWidget {
  final OrderHistoryRecord record;
  final _OrderCancellationSubmit onSubmit;
  // Phase B — company void reason codes. Non-empty = a reason is REQUIRED
  // before the cancel can be submitted (Additions §1.2).
  final List<VoidReasonRef> voidReasons;
  // P-F1 — server-history records: per-item selection is unavailable, only
  // the full-order cancel applies.
  final bool fullOrderOnly;

  const _OrderCancellationPage({
    required this.record,
    required this.onSubmit,
    this.voidReasons = const <VoidReasonRef>[],
    this.fullOrderOnly = false,
  });

  @override
  State<_OrderCancellationPage> createState() => _OrderCancellationPageState();
}

class _OrderCancellationPageState extends State<_OrderCancellationPage> {
  final Set<int> _selectedIndexes = <int>{};
  bool _busy = false;
  VoidReasonRef? _selectedReason;
  bool _reasonMissing = false;

  OrderSnapshot get _snapshot => widget.record.snapshot;

  Future<void> _submit({required bool fullOrder}) async {
    if (_busy) return;
    if (!fullOrder && _selectedIndexes.isEmpty) return;
    // Phase B — the company configured void reasons: picking one is mandatory.
    if (widget.voidReasons.isNotEmpty && _selectedReason == null) {
      setState(() => _reasonMissing = true);
      return;
    }

    setState(() {
      _busy = true;
    });

    final message = await widget.onSubmit(
      cancelFullOrder: fullOrder,
      itemIndexes: fullOrder ? const <int>{} : Set<int>.from(_selectedIndexes),
      voidReason: _selectedReason,
    );
    if (!mounted) return;
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
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
                                l10n.posCancelPageTitle(
                                  widget.record.orderNumber,
                                ),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF18262E),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                l10n.posCancelPageSubtitle,
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
                    // Phase B — required void reason chips (when configured).
                    if (widget.voidReasons.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in widget.voidReasons)
                            ChoiceChip(
                              label: Text(
                                _reasonDisplayName(r.name, r.nameAr, isAr),
                              ),
                              selected: _selectedReason?.id == r.id,
                              onSelected: _busy
                                  ? null
                                  : (selected) => setState(() {
                                      _selectedReason = selected ? r : null;
                                      _reasonMissing = false;
                                    }),
                            ),
                        ],
                      ),
                      if (_reasonMissing)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.posCancelPageReasonRequired,
                            style: const TextStyle(
                              color: Color(0xFFB84524),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                    if (widget.fullOrderOnly) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: Color(0xFF566973),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.posCancelPageServerFullOnly,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF566973),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                                    Text(
                                      l10n.posCancelPageOrderItems,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF18262E),
                                      ),
                                    ),
                                    const Spacer(),
                                    _InfoBadge(
                                      icon: Icons.inventory_2_outlined,
                                      label: l10n.posCancelPageCancellableCount(
                                        selectableCount,
                                      ),
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
                                        onChanged:
                                            canceled ||
                                                _busy ||
                                                widget.fullOrderOnly
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
                              label: l10n.commonClose,
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
                                  ? l10n.posCancelPageSaving
                                  : l10n.posCancelPageCancelSelected(
                                      _selectedIndexes.length,
                                    ),
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
                              label: _busy
                                  ? l10n.posCancelPageSaving
                                  : l10n.posCancelPageCancelFullOrder,
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
    final l10n = L10n.of(context);
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
          Text(
            l10n.posCancelPageOrderSummary,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF18262E),
            ),
          ),
          const SizedBox(height: 14),
          _CancellationMetric(
            label: l10n.posCancelPagePaidTotal,
            value: SunmiReceiptService.money(snapshot.payableTotal),
            icon: Icons.payments_outlined,
          ),
          const SizedBox(height: 10),
          _CancellationMetric(
            label: l10n.posCancelPageCanceledMetric,
            value: SunmiReceiptService.money(snapshot.canceledAmount),
            icon: Icons.remove_circle_outline_rounded,
          ),
          const SizedBox(height: 10),
          _CancellationMetric(
            label: l10n.posCancelPagePaymentMetric,
            value: localizedPaymentMethod(l10n, snapshot.paymentMethod),
            icon: Icons.credit_card_rounded,
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            l10n.posCancelPageCancellationLog,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF344A54),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: snapshot.cancellations.isEmpty
                ? Center(
                    child: Text(
                      l10n.posCancelPageNoCancellations,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
              textAlign: TextAlign.end,
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
    final l10n = L10n.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final qty = (item['qty'] as num?)?.toInt() ?? 1;
    // Phase C4 — prefer the snapshot's Arabic name when the UI locale is
    // Arabic ('name' stays the identity key everywhere else).
    final nameAr = item['nameAr']?.toString() ?? '';
    final name = isAr && nameAr.isNotEmpty
        ? nameAr
        : item['name']?.toString() ?? l10n.posCancelPageItemFallback;
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
                          l10n.posCancelPageItemQtyName(qty, name),
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
              _InfoBadge(
                icon: Icons.cancel_rounded,
                label: l10n.posStorageCanceled,
              ),
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
    final l10n = L10n.of(context);
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
                  Expanded(
                    child: Text(
                      l10n.posDeliveryPickerTitle,
                      style: const TextStyle(
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
                      child: const Icon(
                        Icons.close_rounded,
                        size: 25,
                        color: Color(0xFF52626B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.posDeliveryPickerSubtitle,
                style: const TextStyle(
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
                                horizontal: 16,
                                vertical: 16,
                              ),
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
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF1F7A47),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// P-G7 — the delivery Proceed popup. Collects the PROVIDER's order number
/// (required — alphanumeric, e.g. "TLB-88421") plus optional customer and
/// driver numbers (digits), each through the kiosk's in-app keyboard. Pops
/// a record on confirm, null on cancel.
class _DeliveryProceedDialog extends StatefulWidget {
  final String initialCustomer;

  const _DeliveryProceedDialog({this.initialCustomer = ''});

  @override
  State<_DeliveryProceedDialog> createState() => _DeliveryProceedDialogState();
}

class _DeliveryProceedDialogState extends State<_DeliveryProceedDialog> {
  String _reference = '';
  late String _customer = widget.initialCustomer;
  String _driver = '';

  Future<void> _edit({
    required String title,
    required String initial,
    required bool numbersOnly,
    required ValueChanged<String> onDone,
    bool uppercase = false,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _InAppKeyboardDialog(
        title: title,
        initialValue: initial,
        hintText: '',
        numbersOnly: numbersOnly,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => onDone(uppercase ? result.toUpperCase() : result));
  }

  Widget _fieldRow({
    required String label,
    required String value,
    required String placeholder,
    required VoidCallback onTap,
    bool required = false,
  }) {
    final hasValue = value.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: required && !hasValue
                  ? const Color(0xFFE0A23A)
                  : const Color(0xFFE2E8EC),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5B6770),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasValue ? value : placeholder,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: hasValue
                            ? const Color(0xFF21262C)
                            : const Color(0xFFA6B0B8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.edit_rounded,
                size: 18,
                color: Color(0xFF5B6770),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final canConfirm = _reference.trim().isNotEmpty;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.posDeliveryProceedTitle,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF21262C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.posDeliveryProceedSubtitle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5B6770),
                ),
              ),
              const SizedBox(height: 16),
              _fieldRow(
                label: l10n.posDeliveryProceedReference,
                value: _reference,
                placeholder: l10n.posDeliveryProceedReferenceHint,
                required: true,
                onTap: () => _edit(
                  title: l10n.posDeliveryProceedReference,
                  initial: _reference,
                  numbersOnly: false,
                  uppercase: true,
                  onDone: (v) => _reference = v,
                ),
              ),
              _fieldRow(
                label: l10n.posDeliveryProceedCustomer,
                value: _customer,
                placeholder: l10n.posDeliveryProceedOptionalHint,
                onTap: () => _edit(
                  title: l10n.posDeliveryProceedCustomer,
                  initial: _customer,
                  numbersOnly: true,
                  onDone: (v) => _customer = v,
                ),
              ),
              _fieldRow(
                label: l10n.posDeliveryProceedDriver,
                value: _driver,
                placeholder: l10n.posDeliveryProceedOptionalHint,
                onTap: () => _edit(
                  title: l10n.posDeliveryProceedDriver,
                  initial: _driver,
                  numbersOnly: true,
                  onDone: (v) => _driver = v,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: const Color(0xFF5B6770),
                      ),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: canConfirm
                          ? () => Navigator.of(context).pop((
                              reference: _reference.trim(),
                              customer: _customer.trim(),
                              driver: _driver.trim(),
                            ))
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E5E8C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(l10n.posDeliveryProceedConfirm),
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

class _InAppKeyboardDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String hintText;
  final bool numbersOnly;
  final bool tableSearch;
  final ValueChanged<String>? onChanged;

  const _InAppKeyboardDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    this.numbersOnly = false,
    this.tableSearch = false,
    this.onChanged,
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

      if (_value.length >= (widget.tableSearch ? 32 : 30)) return;
      _value = '$_value$key';
    });
    widget.onChanged?.call(_value);
  }

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() {
      _value = _value.substring(0, _value.length - 1);
    });
    widget.onChanged?.call(_value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final rows = widget.numbersOnly
        ? const <List<String>>[
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['0'],
          ]
        : const <List<String>>[
            // P-F1 — vehicle plates are alphanumeric: the full layout leads
            // with a digit row (it previously had letters only).
            ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
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
            // Keypad stays LTR in Arabic so the QWERTY/digit order never
            // mirrors (digits + Latin letters must keep their layout).
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: rows
                    .map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: row
                              .map(
                                (key) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
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
                    )
                    .toList(),
              ),
            ),
            if (!widget.numbersOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _KeyboardKey(
                        label: l10n.posKeyboardSpace,
                        onTap: () => _append(' '),
                      ),
                    ),
                    if (widget.tableSearch)
                      Expanded(
                        child: _KeyboardKey(
                          label: '-',
                          onTap: () => _append('-'),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _OutlineActionButton(
                    label: l10n.posKeyboardClear,
                    icon: Icons.refresh_rounded,
                    onTap: () {
                      setState(() {
                        _value = '';
                      });
                      widget.onChanged?.call(_value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _OutlineActionButton(
                    label: l10n.posKeyboardBackspace,
                    icon: Icons.backspace_outlined,
                    onTap: _backspace,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilledActionButton(
                    label: l10n.commonDone,
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
    // Captured before the await so it stays valid after the async gap.
    final l10n = L10n.of(context);
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
        setState(() => _error = l10n.posCustomerSearchFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _points(CustomerSearchResult c) =>
      c.loyalty.fold(0, (s, b) => s + b.points);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
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
                      decoration: InputDecoration(
                        hintText: l10n.posCustomerSearchHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _run,
                    child: Text(l10n.posCustomerSearchButton),
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
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.posCustomerSearchNoResults),
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
                      subtitle: Text(
                        [
                          if (c.phone.isNotEmpty) c.phone,
                          if (pts > 0) l10n.posCustomerSearchPoints(pts),
                        ].join('  ·  '),
                      ),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
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
    final l10n = L10n.of(context);
    final points = _blocks * widget.pointsPerBlock;
    final value = _blocks * widget.valuePerBlock;
    return AlertDialog(
      title: Text(l10n.posRedeemTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.posRedeemPerBlock(
              widget.pointsPerBlock,
              SunmiReceiptService.money(widget.valuePerBlock),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _blocks > 1 ? () => setState(() => _blocks--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_blocks',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
            l10n.posRedeemSummary(points, SunmiReceiptService.money(value)),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _blocks),
          child: Text(l10n.posRedeemConfirm),
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
  // P-F4 — free-entry custom percent / fixed amount (they take precedence
  // over a preset pick) + the reason, REQUIRED for free-entry values.
  late final TextEditingController _percentCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _reasonCtrl;
  bool _reasonMissing = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDiscount;
    _percentCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _reasonCtrl = TextEditingController(text: widget.initialDiscount.reason);
  }

  @override
  void dispose() {
    _percentCtrl.dispose();
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  double? get _customPercent {
    final v = double.tryParse(_percentCtrl.text.trim());
    return v != null && v > 0 && v <= 100 ? v : null;
  }

  double? get _customAmount {
    final v = double.tryParse(_amountCtrl.text.trim());
    return v != null && v > 0 ? v : null;
  }

  bool get _hasCustomEntry => _customPercent != null || _customAmount != null;

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// What Apply pops: a free entry wins over a preset; the reason rides
  /// whichever configuration is chosen. (Labels stay English — they are
  /// persisted in snapshots, pushed to the server, and printed.)
  DiscountConfiguration get _effective {
    final reason = _reasonCtrl.text.trim();
    final pct = _customPercent;
    if (pct != null) {
      return DiscountConfiguration(
        kind: DiscountKind.percentage,
        value: pct,
        label: '${_trimNum(pct)}% Discount',
        reason: reason,
      );
    }
    final amt = _customAmount;
    if (amt != null) {
      return DiscountConfiguration(
        kind: DiscountKind.fixedAmount,
        value: amt,
        label: '${amt.toStringAsFixed(3)} OMR Discount',
        reason: reason,
      );
    }
    if (_selected.isActive && reason.isNotEmpty) {
      return DiscountConfiguration(
        kind: _selected.kind,
        value: _selected.value,
        label: _selected.label,
        discountId: _selected.discountId,
        reason: reason,
      );
    }
    return _selected;
  }

  void _apply() {
    if (_hasCustomEntry && _reasonCtrl.text.trim().isEmpty) {
      setState(() => _reasonMissing = true);
      return;
    }
    Navigator.of(context).pop(_effective);
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: Color(0xFF8B9DA8),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    isDense: true,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.86),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE8EC)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE8EC)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
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
                Expanded(
                  child: Text(
                    l10n.posDiscountDlgTitle,
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
            Text(
              l10n.posDiscountDlgPercentageSection,
              style: const TextStyle(
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
            Text(
              l10n.posDiscountDlgFixedSection,
              style: const TextStyle(
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
            const SizedBox(height: 18),
            // P-F4 — free-entry custom values + the (required) reason.
            Text(
              l10n.posDiscountDlgCustomSection,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF22323B),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('discount-custom-percent'),
                    controller: _percentCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      l10n.posDiscountDlgCustomPercentHint,
                    ),
                    onChanged: (v) => setState(() {
                      if (v.trim().isNotEmpty) _amountCtrl.clear();
                      _reasonMissing = false;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('discount-custom-amount'),
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _fieldDecoration(
                      l10n.posDiscountDlgCustomAmountHint,
                    ),
                    onChanged: (v) => setState(() {
                      if (v.trim().isNotEmpty) _percentCtrl.clear();
                      _reasonMissing = false;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('discount-reason'),
              controller: _reasonCtrl,
              maxLength: 160,
              decoration: _fieldDecoration(
                l10n.posDiscountDlgReasonHint,
              ).copyWith(counterText: ''),
              onChanged: (_) => setState(() => _reasonMissing = false),
            ),
            if (_reasonMissing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.posDiscountDlgReasonRequired,
                  style: const TextStyle(
                    color: Color(0xFFB84524),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _OutlineActionButton(
                    label: l10n.posDiscountDlgClear,
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const DiscountConfiguration()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilledActionButton(
                    // The stored discount label stays English (it is persisted
                    // in snapshots, pushed to the server, and printed).
                    label: _selected.isActive || _hasCustomEntry
                        ? l10n.posDiscountDlgApply(_effective.label)
                        : l10n.commonClose,
                    onTap: _selected.isActive || _hasCustomEntry
                        ? _apply
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

/// What the Transfer dialog resolved to: send the cart to a device, or
/// receive one of the incoming transfers.
sealed class _TransferDialogResult {
  const _TransferDialogResult();
}

class _TransferSend extends _TransferDialogResult {
  const _TransferSend(this.device);
  final Map<String, dynamic> device;
}

class _TransferReceive extends _TransferDialogResult {
  const _TransferReceive(this.transfer);
  final Map<String, dynamic> transfer;
}

/// Device↔device order transfer dialog: pick a colleague's device to SEND the
/// current order to, and/or RECEIVE one waiting in this device's inbox.
class _TransferDialog extends StatelessWidget {
  const _TransferDialog({
    required this.devices,
    required this.incoming,
    required this.canSend,
  });

  /// The branch's OTHER devices (GET /device/branch-devices rows).
  final List<Map<String, dynamic>> devices;

  /// Orders waiting to be claimed by THIS device (transfer inbox rows).
  final List<Map<String, dynamic>> incoming;

  /// False when the cart is empty — the send section hides.
  final bool canSend;

  IconData _iconFor(String type) => switch (type) {
    'handheld' => Icons.point_of_sale_rounded,
    'customer_tablet' => Icons.tablet_android_rounded,
    _ => Icons.desktop_windows_rounded,
  };

  bool _seenRecently(Map<String, dynamic> device) {
    final raw = device['last_seen_at']?.toString() ?? '';
    final seen = DateTime.tryParse(raw);
    return seen != null && DateTime.now().difference(seen).inMinutes < 5;
  }

  String _money(Map<String, dynamic> transfer) {
    final baisas = (transfer['grand_total_baisas'] as num?)?.toInt() ?? 0;
    return '${(baisas / 1000).toStringAsFixed(3)} OMR';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 160, vertical: 80),
      backgroundColor: Colors.transparent,
      child: _glassPanel(
        padding: const EdgeInsets.all(22),
        tint: const Color(0xEFF8FBFD),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.swap_horiz_rounded,
                    size: 28,
                    color: Color(0xFF0FA3B1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.posTransferDialogTitle,
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
              if (canSend) ...[
                Text(
                  l10n.posTransferSendSection,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4E5E6A),
                  ),
                ),
                const SizedBox(height: 10),
                if (devices.isEmpty)
                  Text(
                    l10n.posTransferNoDevices,
                    style: const TextStyle(color: Color(0xFF7A8A96)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final device in devices)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.of(
                                  context,
                                ).pop(_TransferSend(device)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _iconFor(
                                          (device['device_type'] ?? '')
                                              .toString(),
                                        ),
                                        color: const Color(0xFF0FA3B1),
                                        size: 26,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          (device['name'] ?? 'Device')
                                              .toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF18262F),
                                          ),
                                        ),
                                      ),
                                      // Advisory online dot (recent heartbeat).
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _seenRecently(device)
                                              ? const Color(0xFF2B9E5F)
                                              : const Color(0xFFD3DCE2),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Color(0xFF7A8A96),
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
                const SizedBox(height: 16),
              ],
              Text(
                l10n.posTransferIncomingSection,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4E5E6A),
                ),
              ),
              const SizedBox(height: 10),
              if (incoming.isEmpty)
                Text(
                  l10n.posTransferNoIncoming,
                  style: const TextStyle(color: Color(0xFF7A8A96)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final transfer in incoming)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.move_to_inbox_rounded,
                                    color: Color(0xFF0FA3B1),
                                    size: 26,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (transfer['transferred_from_name'] ??
                                                  'Device')
                                              .toString(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF18262F),
                                          ),
                                        ),
                                        Text(
                                          _money(transfer),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0FA3B1),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF0FA3B1),
                                    ),
                                    onPressed: () => Navigator.of(
                                      context,
                                    ).pop(_TransferReceive(transfer)),
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 18,
                                    ),
                                    label: Text(l10n.posTransferReceive),
                                  ),
                                ],
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

/// The split dialog's outcome: how many guests, and — when the cashier
/// customized the shares — each guest's exact amount (already closing to the
/// total, the last entry being the remainder).
class _SplitBillResult {
  final int splitCount;
  final List<double>? customAmounts;

  const _SplitBillResult(this.splitCount, this.customAmounts);
}

class _SplitBillDialog extends StatefulWidget {
  final int initialSplitCount;
  final List<double>? initialPlan;
  final double total;

  const _SplitBillDialog({
    required this.initialSplitCount,
    required this.initialPlan,
    required this.total,
  });

  @override
  State<_SplitBillDialog> createState() => _SplitBillDialogState();
}

class _SplitBillDialogState extends State<_SplitBillDialog> {
  late int _splitCount;
  bool _customize = false;
  final List<TextEditingController> _amountCtrls = [];

  @override
  void initState() {
    super.initState();
    _splitCount = widget.initialSplitCount;
    final plan = widget.initialPlan;
    if (plan != null && plan.length == _splitCount && _splitCount > 1) {
      _customize = true;
      for (var i = 0; i < _splitCount - 1; i++) {
        _amountCtrls.add(
          TextEditingController(text: plan[i].toStringAsFixed(3)),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _amountCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  /// Guests 1..N-1 get a field; guest N is always the remainder. Re-seeds
  /// with equal shares whenever the guest count changes.
  void _seedControllers() {
    // The old controllers may still be attached to mounted TextFields until
    // the setState rebuild lands — dispose them after this frame, not now.
    final stale = List<TextEditingController>.of(_amountCtrls);
    if (stale.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final ctrl in stale) {
          ctrl.dispose();
        }
      });
    }
    _amountCtrls.clear();
    final share = _splitCount > 1
        ? double.parse((widget.total / _splitCount).toStringAsFixed(3))
        : widget.total;
    for (var i = 0; i < _splitCount - 1; i++) {
      _amountCtrls.add(TextEditingController(text: share.toStringAsFixed(3)));
    }
  }

  double? _parsedAmount(int index) {
    var text = _amountCtrls[index].text.trim();
    // Arabic-keyboard entry: Arabic-Indic digits, the Arabic decimal
    // separator, and the comma many cashiers type for a decimal point.
    const easternDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var d = 0; d < easternDigits.length; d++) {
      text = text.replaceAll(easternDigits[d], '$d');
    }
    text = text.replaceAll('٫', '.').replaceAll(',', '.');
    final value = double.tryParse(text);
    if (value == null) return null;
    // Round FIRST, then validate — '0.0004' rounds to 0.000 and must be
    // rejected here exactly like setSplitPlan rejects it, or the dialog
    // would bless a plan the controller then refuses.
    final rounded = double.parse(value.toStringAsFixed(3));
    if (rounded < 0.001) return null;
    return rounded;
  }

  double get _customRemainder {
    var head = 0.0;
    for (var i = 0; i < _amountCtrls.length; i++) {
      head += _parsedAmount(i) ?? 0;
    }
    return double.parse((widget.total - head).toStringAsFixed(3));
  }

  bool get _customPlanValid {
    for (var i = 0; i < _amountCtrls.length; i++) {
      if (_parsedAmount(i) == null) return false;
    }
    // The remainder guest must get at least a baisa too (setSplitPlan's rule).
    return _customRemainder >= 0.001;
  }

  List<double> get _customAmounts => [
    for (var i = 0; i < _amountCtrls.length; i++) _parsedAmount(i)!,
    _customRemainder,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final share = _splitCount > 1
        ? double.parse((widget.total / _splitCount).toStringAsFixed(3))
        : widget.total;
    final customizing = _customize && _splitCount > 1;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 180, vertical: 100),
      backgroundColor: Colors.transparent,
      child: _glassPanel(
        padding: const EdgeInsets.all(22),
        tint: const Color(0xEFF8FBFD),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.posSplitDlgTitle,
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(6, (index) {
                  final count = index + 1;
                  return _DiscountChoice(
                    label: count == 1
                        ? l10n.posSplitDlgSingleBill
                        : l10n.posSplitDlgGuests(count),
                    selected: _splitCount == count,
                    onTap: () => setState(() {
                      final changed = count != _splitCount;
                      _splitCount = count;
                      if (_customize && count > 1) {
                        // Re-tapping the selected chip must not wipe amounts
                        // the cashier already typed.
                        if (changed) _seedControllers();
                      } else {
                        _customize = false;
                      }
                    }),
                  );
                }),
              ),
              if (_splitCount > 1) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.posSplitDlgCustomAmounts,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF18262F),
                        ),
                      ),
                    ),
                    Switch(
                      value: _customize,
                      activeThumbColor: const Color(0xFF1D8D53),
                      onChanged: (value) => setState(() {
                        _customize = value;
                        if (value) _seedControllers();
                      }),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (customizing)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 230),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var i = 0; i < _amountCtrls.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: TextField(
                                    controller: _amountCtrls[i],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      labelText: l10n.posSplitDlgGuestN(i + 1),
                                      suffixText: 'OMR',
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                      errorText: _parsedAmount(i) == null
                                          ? l10n.posSplitDlgAmountsInvalid
                                          : null,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.posSplitDlgLastGuestRemainder(_splitCount),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF5D6E79),
                              ),
                            ),
                          ),
                          Text(
                            SunmiReceiptService.money(
                              _customRemainder < 0 ? 0 : _customRemainder,
                            ),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _customRemainder > 0
                                  ? const Color(0xFF1D8D53)
                                  : const Color(0xFFC0392B),
                            ),
                          ),
                        ],
                      ),
                      if (_customRemainder <= 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            l10n.posSplitDlgAmountsInvalid,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFC0392B),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _splitCount > 1
                            ? l10n.posSplitDlgEachGuestPays
                            : l10n.posSplitDlgSinglePaymentTotal,
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
                      label: l10n.commonCancel,
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FilledActionButton(
                      label: _splitCount > 1
                          ? l10n.posSplitDlgApplySplit
                          : l10n.posSplitDlgUseSingleBill,
                      // Null while invalid — the button greys out instead of
                      // silently swallowing taps.
                      onTap: customizing && !_customPlanValid
                          ? null
                          : () => Navigator.of(context).pop(
                              _SplitBillResult(
                                _splitCount,
                                customizing ? _customAmounts : null,
                              ),
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
