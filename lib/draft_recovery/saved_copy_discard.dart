import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/db/app_database.dart';
import 'recovery_admission.dart';
import 'recovery_local.dart';
import 'recovery_models.dart';

/// Separate from automatic sent-copy retirement: a manager may preserve and
/// discard unsent merchandise, but can never decide the outcome of a tender.
class SavedCopyDiscard {
  SavedCopyDiscard(this.json) {
    if (json['kind'] != 'manager_discard' ||
        json['table_id'] is! int ||
        uuid.isEmpty ||
        rows.isEmpty ||
        rows.any(
          (r) => !const {'dining_tables', 'held_orders'}.contains(r['table']),
        )) {
      throw const FormatException('Invalid saved-copy archive');
    }
    for (final record in rows) {
      final row = recoveryMap(record['row']);
      final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
      if (record['pk'] !=
              (record['table'] == 'dining_tables' ? 'table_id' : 'id') ||
          row[record['pk']] != record['value'] ||
          draft['diningTableId'] != '$tableId' ||
          draft['serverOrderUuid'] != uuid) {
        throw const FormatException('Saved-copy identity differs');
      }
    }
  }
  final Map<String, dynamic> json;
  int get tableId => json['table_id'] as int;
  String get uuid => json['uuid'] as String;
  List<Map<String, dynamic>> get rows => recoveryMaps(json['rows']);
  List<Map<String, dynamic>> get outbox => recoveryMaps(json['outbox']);
  Map<String, dynamic> get draft => recoveryMap(json['draft']);

  bool proves(Map<String, dynamic> proof) {
    final bill = recoveryMap(proof['bill']);
    final table = recoveryMap(proof['table']);
    return proof['authority'] == 'existing_manager_approval' &&
        proof['requested_by_staff_id'] is int &&
        (proof['requested_by_staff_id'] as int) > 0 &&
        bill['uuid'] is String &&
        (bill['uuid'] as String).isNotEmpty &&
        bill['table_id'] == tableId &&
        bill['order_type'] == 'dine_in' &&
        const {
          'paid',
          'void',
          'voided',
          'cancelled',
          'refunded',
        }.contains(bill['status']) &&
        recoveryMap(table['table'])['id'] == tableId &&
        table['occupied'] == false &&
        table['orphaned'] == false &&
        table['seating'] == null &&
        table['bill'] == null;
  }

  static Future<SavedCopyDiscard> read(
    DatabaseExecutor db,
    int tableId,
    List<OrderOutboxRow> outboxRows,
  ) async {
    await assertRecoveryUnjoinedCopies(db, tableId);
    final tables = await db.query(
      'dining_tables',
      where: 'table_id = ?',
      whereArgs: ['$tableId'],
    );
    if (tables.length != 1 ||
        tables.single['status'] != 'occupied' ||
        tables.single['paid_at'] != null ||
        tables.single['paid_snapshot_json'] != null) {
      throw StateError('Saved table copy changed');
    }
    final row = tables.single;
    final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
    final uuid = draft['serverOrderUuid'];
    if (uuid is! String ||
        uuid.isEmpty ||
        draft['orderType'] != 'dine_in' ||
        (row['server_order_uuid'] != null &&
            row['server_order_uuid'] != uuid)) {
      throw StateError('Saved copy has no durable identity');
    }
    await assertRecoveryPaymentHistory(
      db,
      uuid,
      allowConfirmedServerReceipt: true,
    );
    final records = <Map<String, dynamic>>[
      {
        'table': 'dining_tables',
        'pk': 'table_id',
        'value': '$tableId',
        'row': row,
      },
    ];
    for (final held in await db.query(
      'held_orders',
      where: 'order_type = ?',
      whereArgs: ['dine_in'],
    )) {
      final saved = recoveryMap(jsonDecode(held['draft_json'] as String));
      if (saved['diningTableId'] != '$tableId') continue;
      if (saved['serverOrderUuid'] != uuid) {
        throw StateError('Different held copy needs review');
      }
      records.add({
        'table': 'held_orders',
        'pk': 'id',
        'value': held['id'],
        'row': held,
      });
    }
    final originals = <Map<String, dynamic>>[];
    for (final entry in outboxRows) {
      final events = recoveryMaps(jsonDecode(entry.eventsJson));
      final related =
          events.any((event) {
            final payload = recoveryMap(event['payload']);
            return payload['order_uuid'] == uuid ||
                (row['seating_key'] != null &&
                    payload['seating_key'] == row['seating_key']);
          }) ||
          entry.orderUuid == uuid ||
          entry.orderUuid.startsWith('$uuid:');
      if (!related) continue;
      if (entry.syncedAt == null &&
          events.any(
            (e) =>
                e['event_type'] == 'order.pay' ||
                recoveryMap(e['payload'])['payments'] != null ||
                !const {
                  'table.session.open',
                  'table.session.round',
                  'order.hold',
                }.contains(e['event_type']),
          )) {
        throw StateError('own_saved_payment');
      }
      originals.add({
        'key': entry.orderUuid,
        'events_json': entry.eventsJson,
        'synced_at': entry.syncedAt?.toIso8601String(),
        'attempts': entry.attempts,
        'server_rejections': entry.serverRejections,
        'last_error': entry.lastError,
        'created_at': entry.createdAt.toIso8601String(),
      });
    }
    return SavedCopyDiscard({
      'kind': 'manager_discard',
      'table_id': tableId,
      'uuid': uuid,
      'rows': records,
      'draft': draft,
      'outbox': originals,
      'rounds': await db.query(
        'local_table_rounds',
        where: 'table_id = ?',
        whereArgs: ['$tableId'],
      ),
      'cancellations': await db.query(
        'local_line_cancellations',
        where: 'table_id = ?',
        whereArgs: ['$tableId'],
      ),
    });
  }

  Future<void> assertNoCheckout(Database checkout) async {
    for (final row in await checkout.query(
      'qr_checkout_attempts',
      columns: ['id', 'scope', 'state', 'payload'],
    )) {
      final attempt = recoveryCheckoutAttempt(row);
      if (attempt.orderUuid == uuid &&
          (!attempt.terminal || checkoutMoneyUncertain(attempt))) {
        throw StateError('own_saved_payment');
      }
    }
  }
}

/// Capability used by the outbox without claiming that archived requests were
/// acknowledged. Their immutable rows remain available in the outbox/archive.
abstract interface class ArchivedTableOutbox {
  Future<bool> tableOutboxArchived(String key, String eventsJson);
}
