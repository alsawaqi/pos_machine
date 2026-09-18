import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../bill_combine/combine_models.dart';
import 'recovery_models.dart';
import 'recovery_local.dart' show assertRecoveryUnjoinedCopies;

class RecoveryStore {
  RecoveryStore(this.db, this.scope, {this.onChanged});
  final Database db;
  final String scope;
  final Future<void> Function()? onChanged;
  static const activeStates =
      "('pending','confirmed','delta_ready','delta_pending')";
  static const unresolved = "state NOT IN ('done','not_applied')";
  static const journalColumns = ['id', 'scope', 'state', 'payload'];

  static Future<void> createSchema(DatabaseExecutor db) async {
    await createClosedSchema(db);
    await db.execute(
      '''CREATE TABLE draft_recovery_journal (
      id TEXT PRIMARY KEY, scope TEXT NOT NULL, state TEXT NOT NULL, payload TEXT NOT NULL)''',
    );
    await db.execute('''CREATE UNIQUE INDEX draft_recovery_one_active ON
      draft_recovery_journal(scope) WHERE state IN $activeStates''');
    await db.execute('''CREATE TABLE draft_recovery_retired (
      recovery_id TEXT NOT NULL, order_uuid TEXT NOT NULL, table_id TEXT NOT NULL,
      order_reference TEXT, occupied_at TEXT, seating_key TEXT,
      PRIMARY KEY (recovery_id, table_id))''');
  }

  static Future<void> createClosedSchema(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS draft_recovery_closed_archive (
      order_uuid TEXT PRIMARY KEY, scope TEXT NOT NULL, local_json TEXT NOT NULL,
      proof_json TEXT NOT NULL, archived_at TEXT NOT NULL)''',
    );
  }

  /// No server write, payment, receipt or local void. Original rows + proof and
  /// the retirement fence commit together, before UI state can forget the copy.
  Future<bool> retireClosed(
    RecoveryLocal local, {
    required Map<String, dynamic> bill,
    required Map<String, dynamic> table,
  }) async {
    if (!closedSentProof(local, bill, table)) return false;
    await db.transaction((txn) async {
      await assertNoCombine(txn);
      await assertNonePending(txn);
      await verifyLocal(local, executor: txn);
      await createClosedSchema(txn);
      await txn.insert('draft_recovery_closed_archive', {
        'order_uuid': local.uuid,
        'scope': scope,
        'local_json': local.encoded,
        'proof_json': recoveryJson({'bill': bill, 'table': table}),
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      });
      for (final original in local.rows) {
        final raw = recoveryMap(original['row']);
        await txn.insert('draft_recovery_retired', {
          'recovery_id': 'closed:${local.uuid}',
          'order_uuid': local.uuid,
          'table_id': '${local.tableId}',
          'order_reference': local.json['draft']['orderReference'],
          'occupied_at': raw['occupied_at'],
          'seating_key': raw['seating_key'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final count = await txn.delete(
          original['table'] as String,
          where: '${original['pk']} = ?',
          whereArgs: [original['value']],
        );
        if (count != 1) throw StateError('Original table copy changed');
      }
    });
    await onChanged?.call();
    return true;
  }

  static bool closedSentProof(
    RecoveryLocal local,
    Map<String, dynamic> bill,
    Map<String, dynamic> table,
  ) {
    if (local.kind != 'staff_rounds' ||
        bill['uuid'] != local.uuid ||
        bill['table_id'] != local.tableId ||
        bill['order_type'] != 'dine_in' ||
        !const {'paid', 'void', 'refunded'}.contains(bill['status']) ||
        recoveryMap(table['table'])['id'] != local.tableId ||
        table['occupied'] != false ||
        table['orphaned'] != false ||
        table['seating'] != null ||
        table['bill'] != null) {
      return false;
    }
    Map<String, int> quantities(Iterable<Map<String, dynamic>> lines) {
      final sums = <String, int>{};
      for (final line in lines) {
        final wire = recoveryWire(line);
        final qty = wire.remove('qty') as int;
        final key = recoveryJson(wire);
        sums[key] = (sums[key] ?? 0) + qty;
      }
      return sums;
    }

    final sent = quantities(
      local.rounds.expand(
        (r) => recoveryMaps(jsonDecode(r['lines_json'] as String)),
      ),
    );
    final draft = quantities(
      local.items.map((raw) {
        final line = recoveryLocalLine(raw);
        return {
          ...line,
          'addon_ids': recoveryMaps(
            line['addons'],
          ).map((a) => a['id']).toList(),
        };
      }),
    );
    return recoveryJson(sent) == recoveryJson(draft);
  }

  static Future<bool> pending(DatabaseExecutor db) async {
    var pending = false;
    for (final row in await db.query(
      'draft_recovery_journal',
      columns: journalColumns,
    )) {
      // Completed archives carry the lasting retirement fence too. Corrupt
      // payloads cannot be hidden by changing a state column to 'done'.
      if (!_decodeRow(row).terminal) pending = true;
    }
    return pending;
  }

  static Future<void> assertNonePending(DatabaseExecutor db) async {
    if (await pending(db)) {
      throw StateError(
        'Finish the saved bill draft recovery in Dine-In first.',
      );
    }
  }

  /// Recovery admission validates every older combine journal, including
  /// terminal history and other device scopes. Unknown state is not idle.
  static Future<void> assertNoCombine(DatabaseExecutor db) async {
    for (final row in await db.query(
      'bill_combine_journal',
      columns: ['id', 'scope', 'state', 'payload'],
    )) {
      late CombineAttempt attempt;
      try {
        attempt = CombineAttempt(
          combineMap(jsonDecode(row['payload'] as String)),
        );
        if (attempt.id != row['id'] ||
            attempt.state != row['state'] ||
            row['scope'] is! String ||
            (row['scope'] as String).trim().isEmpty) {
          throw const FormatException('Combine identity disagrees');
        }
      } catch (_) {
        throw const FormatException(
          'Cannot verify the saved combine journal. Keep app data.',
        );
      }
      if (!attempt.terminal) {
        throw StateError('Finish the pending bill combine in Dine-In first.');
      }
    }
  }

  /// Lasting retirement fence: stale callbacks cannot restore a payable copy.
  static Future<void> assertNotRetired(
    DatabaseExecutor db, {
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  }) async {
    final retired = <Map<String, dynamic>>[];
    for (final record in await db.query(
      'draft_recovery_journal',
      columns: journalColumns,
    )) {
      final attempt = _decodeRow(record);
      if (!const {
        'delta_ready',
        'delta_pending',
        'done',
      }.contains(attempt.state)) {
        continue;
      }
      for (final original in attempt.local.rows) {
        final row = recoveryMap(original['row']);
        final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
        retired.add({
          'order_uuid': attempt.local.uuid,
          'table_id': '${attempt.local.tableId}',
          'order_reference': draft['orderReference'],
          'occupied_at': row['occupied_at'],
          'seating_key': row['seating_key'],
        });
      }
    }
    // Older test databases may predate the additive archive table. Production
    // upgrades create it; the originals remain authoritative for the fence.
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='draft_recovery_closed_archive'",
    )).isNotEmpty) {
      for (final record in await db.query('draft_recovery_closed_archive')) {
        final local = RecoveryLocal(
          recoveryMap(jsonDecode(record['local_json'] as String)),
        );
        final proof = recoveryMap(jsonDecode(record['proof_json'] as String));
        if (record['order_uuid'] != local.uuid ||
            !closedSentProof(
              local,
              recoveryMap(proof['bill']),
              recoveryMap(proof['table']),
            )) {
          throw const FormatException('Cannot verify closed-table archive');
        }
        for (final original in local.rows) {
          final row = recoveryMap(original['row']);
          retired.add({
            'order_uuid': local.uuid,
            'table_id': '${local.tableId}',
            'order_reference': local.json['draft']['orderReference'],
            'occupied_at': row['occupied_at'],
            'seating_key': row['seating_key'],
          });
        }
      }
    }
    // Immutable originals are authoritative even if an auxiliary fence row is
    // missing. No server snapshot or current catalogue rebuilds this evidence.
    for (final row in retired) {
      if ((uuid != null && uuid.isNotEmpty && row['order_uuid'] == uuid) ||
          (tableId == row['table_id'] &&
              ((occupiedAt != null && row['occupied_at'] == occupiedAt) ||
                  (seatingKey != null && row['seating_key'] == seatingKey) ||
                  // A display reference alone is not a generation. An old
                  // callback without any durable identity is ambiguous;
                  // callers must supply UUID, occupancy or seating key.
                  ((uuid == null || uuid.isEmpty) &&
                      occupiedAt == null &&
                      seatingKey == null)))) {
        throw StateError(
          'This local bill was archived. Use its canonical Dine-In bill.',
        );
      }
    }
  }

  Future<RecoveryAttempt?> active() async {
    final rows = await db.query(
      'draft_recovery_journal',
      columns: journalColumns,
      where: 'scope = ? AND $unresolved',
      whereArgs: [scope],
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<RecoveryAttempt?> read(String id) async {
    final rows = await db.query(
      'draft_recovery_journal',
      columns: journalColumns,
      where: 'scope = ? AND id = ?',
      whereArgs: [scope, id],
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  RecoveryAttempt _decode(Map<String, Object?> row) => _decodeRow(row);

  static RecoveryAttempt _decodeRow(Map<String, Object?> row) {
    try {
      final attempt = RecoveryAttempt(
        recoveryMap(jsonDecode(row['payload'] as String)),
      );
      if (attempt.id != row['id'] ||
          attempt.state != row['state'] ||
          row['scope'] is! String ||
          (row['scope'] as String).trim().isEmpty) {
        throw const FormatException('Recovery journal columns disagree');
      }
      return attempt;
    } catch (_) {
      throw const FormatException(
        'Cannot read the saved recovery archive. Keep app data.',
      );
    }
  }

  Future<void> assertOwn(String? id) async {
    final rows = await db.query(
      'draft_recovery_journal',
      columns: journalColumns,
    );
    for (final row in rows) {
      final saved = _decode(row);
      if (saved.terminal) continue;
      if (saved.id != id || row['scope'] != scope) {
        throw StateError(
          'Restore the device session for the existing saved recovery.',
        );
      }
    }
  }

  Future<void> verifyLocal(
    RecoveryLocal local, {
    DatabaseExecutor? executor,
  }) async {
    final target = executor ?? db;
    await assertRecoveryUnjoinedCopies(target, local.tableId);
    final expected = local.rows
        .map((r) => recoveryJson([r['table'], r['pk'], r['value']]))
        .toSet();
    final actual = <String>{};
    for (final table in ['held_orders', 'dining_tables']) {
      for (final row in await target.query(table)) {
        var related =
            table == 'dining_tables' && row['table_id'] == '${local.tableId}';
        if (row['draft_json'] != null) {
          final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
          related =
              related ||
              draft['serverOrderUuid'] == local.uuid ||
              draft['diningTableId'] == '${local.tableId}';
        }
        if (related) {
          final pk = table == 'held_orders' ? 'id' : 'table_id';
          actual.add(recoveryJson([table, pk, row[pk]]));
        }
      }
    }
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw StateError(
        'The local draft copy set changed. Keep every recovery copy.',
      );
    }
    for (final record in local.rows) {
      final rows = await target.query(
        record['table'] as String,
        where: '${record['pk']} = ?',
        whereArgs: [record['value']],
      );
      if (rows.length != 1 ||
          recoveryJson(rows.single) != recoveryJson(record['row'])) {
        throw StateError(
          'An original local draft changed. Recovery remains saved.',
        );
      }
    }
    for (final entry in {
      'local_table_rounds': 'rounds',
      'local_line_cancellations': 'cancellations',
    }.entries) {
      final rows = await target.query(
        entry.key,
        where: local.json['generation_scoped'] == true
            ? 'table_id = ? AND seating_key = ?'
            : 'table_id = ?',
        whereArgs: [
          '${local.tableId}',
          if (local.json['generation_scoped'] == true)
            recoveryMap(
              local.rows.singleWhere(
                (r) => r['table'] == 'dining_tables',
              )['row'],
            )['seating_key'],
        ],
        orderBy: entry.value == 'rounds'
            ? 'local_round_no, client_request_id'
            : 'cancelled_at, client_request_id',
      );
      if (recoveryJson(rows) != recoveryJson(local.json[entry.value])) {
        throw StateError('The local round ledger changed.');
      }
    }
    for (final row in await target.query(
      'order_history',
      columns: ['snapshot_json'],
    )) {
      if (recoveryMap(
            jsonDecode(row['snapshot_json'] as String),
          )['serverOrderUuid'] ==
          local.uuid) {
        throw StateError('A payment record appeared. Keep the recovery copy.');
      }
    }
  }

  Future<void> create(RecoveryAttempt attempt) async {
    if (attempt.state != 'pending') {
      throw StateError('Only a new pending recovery may enter the journal.');
    }
    await db.transaction((txn) async {
      await assertNoCombine(txn);
      await assertNonePending(txn);
      await assertNotRetired(txn, uuid: attempt.local.uuid);
      await verifyLocal(attempt.local, executor: txn);
      await txn.insert('draft_recovery_journal', {
        'id': attempt.id,
        'scope': scope,
        'state': attempt.state,
        'payload': attempt.encoded,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
    await onChanged?.call();
  }

  Future<void> replace(
    RecoveryAttempt old,
    RecoveryAttempt next, {
    DatabaseExecutor? executor,
  }) async {
    final allowed = switch (old.state) {
      'pending' => const {'confirmed', 'not_applied'},
      'confirmed' => old.delta.isEmpty ? const {'done'} : const {'delta_ready'},
      'delta_ready' => const {'delta_pending'},
      'delta_pending' => const {'done'},
      _ => const <String>{},
    };
    if (old.id != next.id ||
        !allowed.contains(next.state) ||
        old.local.encoded != next.local.encoded ||
        old.preview.encoded != next.preview.encoded ||
        recoveryJson(old.delta) != recoveryJson(next.delta) ||
        (old.json['ack'] != null &&
            recoveryJson(old.json['ack']) != recoveryJson(next.json['ack'])) ||
        (old.json['delta_request'] != null &&
            recoveryJson(old.json['delta_request']) !=
                recoveryJson(next.json['delta_request']))) {
      throw StateError('Cannot replace the saved recovery identity.');
    }
    final count = await (executor ?? db).update(
      'draft_recovery_journal',
      {'state': next.state, 'payload': next.encoded},
      where: 'scope = ? AND id = ? AND payload = ?',
      whereArgs: [scope, old.id, old.encoded],
    );
    if (count != 1) throw StateError('Recovery changed on another screen.');
    if (executor == null) await onChanged?.call();
  }

  /// Archive evidence, save unsent slices, retire originals and write the fence
  /// in ONE database transaction. No table hooks, outbox, payment or print.
  Future<RecoveryAttempt> retire(RecoveryAttempt attempt) async {
    if (attempt.state != 'confirmed') {
      throw StateError('Recovery is not acknowledged.');
    }
    attempt.validateAck(recoveryMap(attempt.json['ack']));
    final next = attempt.change(attempt.delta.isEmpty ? 'done' : 'delta_ready');
    await db.transaction((txn) async {
      await verifyLocal(attempt.local, executor: txn);
      final orderedRows = attempt.local.rows
        ..sort(
          (a, b) => (a['table'] == 'dining_tables' ? 0 : 1).compareTo(
            b['table'] == 'dining_tables' ? 0 : 1,
          ),
        );
      for (final record in orderedRows) {
        final row = recoveryMap(record['row']);
        final draft = recoveryMap(jsonDecode(row['draft_json'] as String));
        await txn.insert('draft_recovery_retired', {
          'recovery_id': attempt.id,
          'order_uuid': attempt.local.uuid,
          'table_id': '${attempt.local.tableId}',
          'order_reference': draft['orderReference'],
          'occupied_at': row['occupied_at'],
          'seating_key': row['seating_key'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final count = await txn.delete(
          record['table'] as String,
          where: '${record['pk']} = ?',
          whereArgs: [record['value']],
        );
        if (count != 1) {
          throw StateError('An original recovery row disappeared.');
        }
      }
      await replace(attempt, next, executor: txn);
    });
    await onChanged?.call();
    return next;
  }
}
