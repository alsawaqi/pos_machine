import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/table_sync_models.dart';

/// Serializes flush-pass batches, including repeats arriving while a sheet is
/// open. A row is acknowledged only after an actual presentation is dismissed.
class TableReconciliationPresenter {
  TableReconciliationPresenter({required this.show, required this.markSeen});

  final Future<bool> Function(List<TableSyncVerdict>) show;
  final Future<void> Function(List<TableSyncVerdict>) markSeen;
  final _reserved = <int>{};
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Future<void> present(List<TableSyncVerdict> batch) {
    final rows = batch
        .where((row) => !row.seen && row.id != null && _reserved.add(row.id!))
        .toList();
    if (_disposed || rows.isEmpty) return _tail;
    final next = _tail.then((_) async {
      if (_disposed || !await show(List.unmodifiable(rows))) {
        _reserved.removeAll(rows.map((r) => r.id!));
        return;
      }
      await markSeen(rows);
    });
    _tail = next.catchError((Object _) {
      // The durable rows remain unseen and can be offered by the next pass.
      _reserved.removeAll(rows.map((r) => r.id!));
    });
    return next;
  }

  void dispose() => _disposed = true;
}

int _int(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

String tableReconciliationCopy(L10n l10n, TableSyncVerdict row) {
  final d = row.detail;
  final request = d['request'] is Map ? d['request'] as Map : const {};
  final table = row.tableId;
  if (row.outcome == 'merged') return l10n.tableReconciledMerged(table);
  if (row.eventKind == 'open') {
    if (row.outcome == 'attached') return l10n.tableReconciledAttached(table);
    if (row.outcome == 'already_closed') {
      return l10n.tableReconciledClosed(table);
    }
  }
  if (row.eventKind == 'round') {
    if (row.outcome == 'held') {
      final held = d['held_lines'] is List ? d['held_lines'] as List : const [];
      final reasons = <String>{
        for (final line in held.whereType<Map>())
          if (line['reason'] != null) line['reason'].toString(),
        for (final reason
            in d['review_reasons'] is List
                ? d['review_reasons'] as List
                : const [])
          reason.toString(),
      };
      // held_lines carries original line_index, not qty. Resolve it against
      // this device's immutable request, never the current cart or board.
      final lines = request['lines'] is List
          ? request['lines'] as List
          : const [];
      final indexes = held
          .whereType<Map>()
          .map((line) => int.tryParse(line['line_index']?.toString() ?? ''))
          .whereType<int>()
          .toSet();
      final count = indexes.fold<int>(
        0,
        (sum, index) =>
            sum +
            (index >= 0 && index < lines.length && lines[index] is Map
                ? _int((lines[index] as Map)['qty'])
                : 0),
      );
      final reason = reasons.isEmpty
          ? l10n.tableReviewReasonUnknown
          : reasons.join(', ');
      return l10n.tableReconciledHeld(table, count, reason);
    }
    if (row.outcome == 'bill_terminal' || row.outcome == 'bill_unpaid') {
      return l10n.tableReconciledRoundStopped(table);
    }
  }
  if (row.eventKind == 'move') {
    final from = request['from_table_id']?.toString() ?? table;
    final to = request['to_table_id']?.toString() ?? '—';
    if (row.outcome == 'target_occupied') {
      return l10n.tableReconciledMoveOccupied(to, from);
    }
    // A dead/unknown seating is not evidence that the target is occupied.
    return l10n.tableReconciledMoveStale(from, to);
  }
  if (row.eventKind == 'join') {
    final refused = d['refused'] is List ? d['refused'] as List : const [];
    final ids = refused
        .map((r) => r is Map ? r['table_id']?.toString() ?? '—' : r.toString())
        .join(', ');
    return l10n.tableReconciledJoin(table, ids);
  }
  if (row.eventKind == 'close' && row.outcome == 'bill_unpaid') {
    return l10n.tableReconciledUnpaid(table);
  }
  if (row.eventKind == 'cancel_line') {
    final missing = (_int(request['qty']) - _int(d['cancelled_qty'])).clamp(
      0,
      999,
    );
    return l10n.tableReconciledCancellation(table, missing);
  }
  return l10n.tableReconciledOther(table, row.outcome);
}

class TableReconciliationSheet extends StatelessWidget {
  const TableReconciliationSheet({super.key, required this.rows});
  final List<TableSyncVerdict> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.tableReconciledTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(child: TableReconciliationHistoryPanel(rows: rows)),
            TextButton(
              key: const ValueKey('table-reconciliation-dismiss'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.tableReconciledDismiss),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared read-only rendering for the sheet and Settings' last 200 verdicts.
class TableReconciliationHistoryPanel extends StatelessWidget {
  const TableReconciliationHistoryPanel({super.key, required this.rows});
  final List<TableSyncVerdict> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final visible = rows.take(200).toList(growable: false);
    if (visible.isEmpty) return Center(child: Text(l10n.tableReconciledEmpty));
    return ListView.builder(
      key: const ValueKey('table-reconciliation-rows'),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final row = visible[index];
        return ListTile(
          key: ValueKey('table-verdict-${row.id}'),
          title: Text(tableReconciliationCopy(l10n, row)),
          subtitle: Text(row.observedAt.toLocal().toIso8601String()),
        );
      },
    );
  }
}
