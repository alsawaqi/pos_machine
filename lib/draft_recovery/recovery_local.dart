import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../bill_combine/combine_models.dart';
import '../data/db/app_database.dart';
import 'recovery_models.dart';

/// Another local party head/held copy can reference this table even when its
/// primary table differs. Never silently omit that overlapping original.
Future<void> assertRecoveryUnjoinedCopies(
  DatabaseExecutor db,
  int tableId,
) async {
  final id = '$tableId';
  bool overlaps(Object? primary, Object? links, {required bool selected}) {
    if (links != null && links is! List) {
      throw const FormatException('Unknown local joined-table shape');
    }
    final values = (links as List? ?? const []).map((v) => '$v').toList();
    return (selected &&
            ((primary != null && '$primary'.isNotEmpty) ||
                values.isNotEmpty)) ||
        (primary != null && '$primary' == id) ||
        values.contains(id);
  }

  for (final name in ['held_orders', 'dining_tables']) {
    for (final row in await db.query(name)) {
      final selected = name == 'dining_tables' && row['table_id'] == id;
      if (name == 'dining_tables' &&
          overlaps(
            row['primary_table_id'],
            row['linked_table_ids_json'] == null
                ? null
                : jsonDecode(row['linked_table_ids_json'] as String),
            selected: selected,
          )) {
        throw StateError(
          'An overlapping joined local table must be preserved for separate review.',
        );
      }
      if (row['draft_json'] == null) continue;
      final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
      final own = selected || draft['diningTableId'] == id;
      if (overlaps(
            draft['primaryTableId'],
            draft['linkedTableIds'],
            selected: own,
          ) ||
          overlaps(
            draft['primary_table_id'],
            draft['joined_table_ids'],
            selected: own,
          )) {
        throw StateError(
          'An overlapping joined local draft must be preserved for separate review.',
        );
      }
    }
  }
}

/// Reads original persisted records; never uses the catalogue or a cart decoder.
Future<RecoveryLocal> loadRecoveryLocal(
  Database db,
  int tableId, {
  required Future<OrderOutboxRow?> Function(String) outboxRow,
  bool currentGenerationOnly = false,
}) async {
  await assertRecoveryUnjoinedCopies(db, tableId);
  final records = <Map<String, dynamic>>[];
  Map<String, dynamic>? draft, table;
  void add(String name, String pk, Map<String, Object?> row) {
    final value = recoveryMap(jsonDecode(row['draft_json'] as String));
    if (value['diningTableId'] != '$tableId') return;
    if (!combineUuid(value['serverOrderUuid']) ||
        value['orderType'] != 'dine_in' ||
        value['splitCount'] != 1 ||
        recoveryMap(value['discount'])['value'] != 0) {
      throw StateError('The original local bill needs separate review.');
    }
    if (draft != null && recoveryJson(draft) != recoveryJson(value)) {
      throw StateError(
        'Local draft copies disagree. Keep every original copy.',
      );
    }
    draft = value;
    records.add({'table': name, 'pk': pk, 'value': row[pk], 'row': row});
  }

  for (final row in await db.query(
    'held_orders',
    where: 'order_type = ?',
    whereArgs: ['dine_in'],
    orderBy: 'id',
  )) {
    add('held_orders', 'id', row);
  }
  for (final row in await db.query(
    'dining_tables',
    where: 'table_id = ?',
    whereArgs: ['$tableId'],
  )) {
    table = Map<String, dynamic>.from(row);
    if (row['status'] != 'occupied' ||
        row['paid_at'] != null ||
        row['paid_snapshot_json'] != null ||
        (row['primary_table_id'] ?? '') != '' ||
        (row['linked_table_ids_json'] != null &&
            row['linked_table_ids_json'] != '[]') ||
        row['winner_seating_uuid'] != null ||
        row['seating_state'] == 'merged' ||
        row['seating_state'] == 'closed') {
      throw StateError(
        'Joined, paid or changed table generations need separate review.',
      );
    }
    add('dining_tables', 'table_id', row);
  }
  if (draft == null) {
    throw StateError('No original local draft exists on this device.');
  }
  final uuid = draft!['serverOrderUuid'] as String;
  if (table?['server_order_uuid'] != null &&
      table!['server_order_uuid'] != uuid) {
    throw StateError('The local bill identities disagree.');
  }
  // Closed copies keep their ledger. A later occupancy of this table must
  // prove only its own generation, without deleting earlier round history.
  if (currentGenerationOnly && !combineUuid(table?['seating_key'])) {
    throw StateError('Missing original table generation.');
  }
  final ledgerWhere = currentGenerationOnly
      ? 'table_id = ? AND seating_key = ?'
      : 'table_id = ?';
  final ledgerArgs = <Object?>[
    '$tableId',
    if (currentGenerationOnly) table!['seating_key'],
  ];
  final rounds = await db.query(
    'local_table_rounds',
    where: ledgerWhere,
    whereArgs: ledgerArgs,
    orderBy: 'local_round_no, client_request_id',
  );
  final cancellations = await db.query(
    'local_line_cancellations',
    where: ledgerWhere,
    whereArgs: ledgerArgs,
    orderBy: 'cancelled_at, client_request_id',
  );
  if (cancellations.isNotEmpty) {
    throw StateError('Cancellation history needs separate reconciliation.');
  }
  final outbox = <Map<String, dynamic>>[];
  final ids = <String>{}, serverIds = <int>{};
  if (rounds.isNotEmpty &&
      (table == null ||
          !combineUuid(table['seating_uuid']) ||
          !combineUuid(table['seating_key']) ||
          table['seating_state'] != 'open')) {
    throw StateError('Missing acknowledged local table generation.');
  }
  for (final round in rounds) {
    final id = round['client_request_id'];
    if (!combineUuid(id) ||
        !ids.add(id as String) ||
        round['status'] != 'appended' ||
        round['server_round_id'] is! int ||
        !serverIds.add(round['server_round_id'] as int) ||
        (round['server_round_id'] as int) < 1 ||
        round['server_round_no'] is! int ||
        (round['server_round_no'] as int) < 1 ||
        round['acked_at'] is! String ||
        DateTime.tryParse(round['acked_at'] as String) == null ||
        round['order_uuid'] != uuid ||
        round['seating_key'] != table!['seating_key'] ||
        recoveryMaps(
          jsonDecode(round['held_lines_json'] as String? ?? '[]'),
        ).isNotEmpty ||
        (jsonDecode(round['review_reasons_json'] as String? ?? '[]') as List)
            .isNotEmpty) {
      throw StateError(
        'Every original staff round must be fully acknowledged and accepted.',
      );
    }
    final row = await outboxRow(round['outbox_key'] as String);
    if (row == null || row.syncedAt == null) {
      throw StateError('Original staff sync evidence is unresolved.');
    }
    final events = recoveryMaps(jsonDecode(row.eventsJson));
    if (events.length != 1 ||
        events.single['event_type'] != 'table.session.round' ||
        events.single['client_event_id'] != id) {
      throw StateError('Staff sync identity differs from its ledger.');
    }
    final payload = recoveryMap(events.single['payload']);
    if (payload['client_request_id'] != id ||
        payload['seating_key'] != round['seating_key'] ||
        payload['table_id'] != tableId ||
        payload['order_uuid'] != uuid ||
        recoveryJson(payload['lines']) !=
            recoveryJson(jsonDecode(round['lines_json'] as String))) {
      throw StateError('Original staff request changed.');
    }
    outbox.add({
      'key': row.orderUuid,
      'events_json': row.eventsJson,
      'synced_at': row.syncedAt!.toIso8601String(),
    });
  }
  if (rounds.isEmpty &&
      (table?['seating_key'] != null || table?['seating_uuid'] != null)) {
    throw StateError(
      'A shared local draft without acknowledged rounds needs separate review.',
    );
  }
  for (final row in await db.query(
    'order_history',
    columns: ['snapshot_json'],
  )) {
    if (recoveryMap(
          jsonDecode(row['snapshot_json'] as String),
        )['serverOrderUuid'] ==
        uuid) {
      throw StateError('Local payment history exists for this bill.');
    }
  }
  return RecoveryLocal({
    if (currentGenerationOnly) 'generation_scoped': true,
    'table_id': tableId,
    'uuid': uuid,
    'kind': rounds.isEmpty ? 'legacy_hold' : 'staff_rounds',
    'seating_uuid': table?['seating_uuid'],
    'rows': records,
    'draft': draft,
    'rounds': rounds,
    'cancellations': cancellations,
    'outbox': outbox,
  });
}
