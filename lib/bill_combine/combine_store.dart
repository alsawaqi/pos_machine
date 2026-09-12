import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../draft_recovery/recovery_store.dart';
import 'combine_models.dart';

class CombineStore {
  CombineStore(this.db, this.scope);
  final Database db;
  final String scope;
  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE bill_combine_journal (
      id TEXT PRIMARY KEY, scope TEXT NOT NULL, state TEXT NOT NULL,
      payload TEXT NOT NULL)''');
    await db.execute('''CREATE UNIQUE INDEX bill_combine_one_active ON
      bill_combine_journal(scope) WHERE state IN ('pending', 'confirmed')''');
  }

  static Future<void> assertNonePending(DatabaseExecutor db) async {
    final rows = await db.query(
      'bill_combine_journal',
      columns: ['id'],
      where: "state IN ('pending', 'confirmed')",
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError('Finish the pending bill combine in Dine-In first.');
    }
  }

  Future<CombineAttempt?> active() async {
    final rows = await db.query(
      'bill_combine_journal',
      where: "scope = ? AND state IN ('pending', 'confirmed')",
      whereArgs: [scope],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final attempt = CombineAttempt(
      combineMap(jsonDecode(row['payload'] as String)),
    );
    if (attempt.id != row['id'] || attempt.state != row['state']) {
      throw const FormatException('Combine journal columns disagree');
    }
    return attempt;
  }

  Future<CombineAttempt?> read(String id) async {
    final rows = await db.query(
      'bill_combine_journal',
      where: 'scope = ? AND id = ?',
      whereArgs: [scope, id],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final attempt = CombineAttempt(
      combineMap(jsonDecode(row['payload'] as String)),
    );
    if (attempt.id != row['id'] || attempt.state != row['state']) {
      throw StateError('Journal columns disagree');
    }
    return attempt;
  }

  Future<void> verifyLocal(
    CombineLocal local, {
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? db;
    final expected = local.rows
        .map((r) => combineJson([r['table'], r['pk'], r['value']]))
        .toSet();
    final actual = <String>{};
    // Check the complete set under the archive transaction too: a new copy
    // appearing after preview must not survive as another payable local bill.
    for (final table in ['held_orders', 'dining_tables']) {
      final exists = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      if (exists.isEmpty) continue;
      for (final row in await database.query(table)) {
        var related =
            row['uuid'] == local.uuid ||
            (table == 'dining_tables' &&
                row['table_id'].toString() == local.tableId.toString());
        for (final column in ['draft_json', 'table_json']) {
          if (row[column] == null) continue;
          final value = combineMap(jsonDecode(row[column] as String));
          related =
              related ||
              value['serverOrderUuid'] == local.uuid ||
              value['diningTableId']?.toString() == local.tableId.toString() ||
              value['table_id']?.toString() == local.tableId.toString();
        }
        if (related) {
          final pk = table == 'dining_tables'
              ? 'table_id'
              : row.containsKey('uuid')
              ? 'uuid'
              : 'id';
          actual.add(combineJson([table, pk, row[pk]]));
        }
      }
    }
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw StateError('Local bill copies changed. Keep all recovery copies.');
    }
    for (final record in local.rows) {
      final rows = await (executor ?? db).query(
        record['table'] as String,
        where: '${record['pk']} = ?',
        whereArgs: [record['value']],
      );
      if (rows.length != 1 ||
          combineJson(rows.single) != combineJson(record['row'])) {
        throw StateError(
          'Local bill changed. Its recovery copy has been retained.',
        );
      }
    }
  }

  Future<void> create(CombineAttempt attempt) => db.transaction((txn) async {
    await assertNonePending(txn);
    await RecoveryStore.assertNonePending(txn);
    await verifyLocal(attempt.local, executor: txn);
    await txn.insert('bill_combine_journal', {
      'id': attempt.id,
      'scope': scope,
      'state': attempt.state,
      'payload': attempt.encoded,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  });
  Future<void> replace(
    CombineAttempt old,
    CombineAttempt next, {
    DatabaseExecutor? executor,
  }) async {
    if (old.id != next.id ||
        old.terminal ||
        old.local.encoded != next.local.encoded ||
        old.preview.encoded != next.preview.encoded ||
        (old.state == 'confirmed' &&
            combineJson(old.json['ack']) != combineJson(next.json['ack'])) ||
        !(old.state == 'pending' &&
                const {'confirmed', 'not_applied'}.contains(next.state) ||
            old.state == 'confirmed' && next.state == 'done')) {
      throw StateError('Cannot replace combine identity');
    }
    final count = await (executor ?? db).update(
      'bill_combine_journal',
      {'state': next.state, 'payload': next.encoded},
      where: 'scope = ? AND id = ? AND payload = ?',
      whereArgs: [scope, old.id, old.encoded],
    );
    if (count != 1) throw StateError('Combine changed on another screen');
  }

  /// Only a validated server ACK permits retirement. Original rows + ACK
  /// remain recoverable in this SAME database transaction. Never a clear-table
  /// action, outbox edit, catalogue reprice, payment or print.
  Future<void> retire(CombineAttempt attempt) => db.transaction((txn) async {
    if (attempt.state != 'confirmed') {
      throw StateError('Combine is not confirmed');
    }
    attempt.validateAck(combineMap(attempt.json['ack']));
    await verifyLocal(attempt.local, executor: txn);
    for (final row in attempt.local.rows) {
      final count = await txn.delete(
        row['table'] as String,
        where: '${row['pk']} = ?',
        whereArgs: [row['value']],
      );
      if (count != 1) throw StateError('Local bill changed during retirement');
    }
    await replace(attempt, attempt.withState('done'), executor: txn);
  });
}
