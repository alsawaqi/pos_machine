import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('v5 fresh remote schema has exactly the ordered columns and singleton constraint', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await LocalOrderStorageService.createRemoteTables(db);
    final columns = await db.rawQuery('PRAGMA table_info(remote_table_states)');
    expect(columns.map((row) => row['name']).toList(), [
      'table_id',
      'seating_uuid',
      'seating_status',
      'origin',
      'temp_reference',
      'opened_at',
      'expires_at',
      'needs_review_count',
      'joined_table_ids_json',
      'bill_order_uuid',
      'bill_status',
      'bill_grand_total_baisas',
      'bill_receipt_number',
      'bill_temp_reference',
      'charge_claim_live',
      'fetched_at',
      'source',
    ]);
    await expectLater(
      db.insert('remote_sync_meta', {'id': 2}),
      throwsA(isA<DatabaseException>()),
    );
    final ddl = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name LIKE 'remote_%' ORDER BY name",
    );
    // Literal executed DDL retained in the test log for the handback.
    // ignore: avoid_print
    print('T5_REMOTE_DDL=${jsonEncode(ddl)}');
  });

  test('v4 to v5 additive upgrade preserves every local row byte-identically', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE dining_tables (
        table_id TEXT PRIMARY KEY, floor_id TEXT NOT NULL, status TEXT NOT NULL,
        order_number INTEGER, order_reference TEXT, updated_at TEXT NOT NULL,
        occupied_at TEXT, paid_at TEXT, draft_json TEXT, paid_snapshot_json TEXT,
        primary_table_id TEXT, linked_table_ids_json TEXT
      )
    ''');
    await db.execute(
      'CREATE TABLE held_orders (id TEXT PRIMARY KEY, draft_json TEXT)',
    );
    await db.execute(
      'CREATE TABLE order_history (id TEXT PRIMARY KEY, snapshot_json TEXT)',
    );
    for (final id in ['1', '2', '999']) {
      await db.insert('dining_tables', {
        'table_id': id,
        'floor_id': '7',
        'status': id == '2' ? 'paid' : 'occupied',
        'order_number': 1449,
        'order_reference': 'REF-$id',
        'updated_at': '2026-09-06T12:00:00.000Z',
        'occupied_at': '2026-09-06T11:00:00.000Z',
        'paid_at': id == '2' ? '2026-09-06T11:50:00.000Z' : null,
        'draft_json': '{ "exact" : [1,2] }',
        'paid_snapshot_json': '{"money":4750}',
        'primary_table_id': id == '2' ? '1' : null,
        'linked_table_ids_json': id == '1' ? '["2"]' : null,
      });
    }
    await db.insert('held_orders', {'id': 'held', 'draft_json': 'keep-held'});
    await db.insert('order_history', {
      'id': 'paid',
      'snapshot_json': 'keep-paid',
    });
    await db.setVersion(4);
    final before = jsonEncode(
      await db.query('dining_tables', orderBy: 'table_id'),
    );
    // Exactly the same additive step used by the production onUpgrade callback.
    await db.transaction(
      (txn) => LocalOrderStorageService.createRemoteTables(txn),
    );
    await db.setVersion(5);
    final store = LocalOrderStorageService.forTesting(db);
    expect(await db.getVersion(), 5);
    expect(
      jsonEncode(await db.query('dining_tables', orderBy: 'table_id')),
      before,
    );
    expect(await store.readRemoteTables(), isEmpty);
    final at = DateTime.utc(2026, 9, 6);
    final row = RemoteTableState(
      tableId: 1,
      fetchedAt: at,
      seatingUuid: 'seating',
      seatingStatus: 'open',
      origin: 'station',
      tempReference: 'T-0906-001',
      needsReviewCount: 2,
      joinedTableIds: [2],
      billOrderUuid: 'bill',
      billStatus: 'awaiting_payment',
      billGrandTotalBaisas: 4750,
      chargeClaimLive: true,
    );
    await store.replaceRemoteBoard([row], at);
    expect((await store.readRemoteTables()).single.toRow(), row.toRow());
    expect((await store.readRemoteMeta()).boardFetchedAt, at);
    await store.replaceRemoteBoard([], at);
    expect(await store.readRemoteTables(), isEmpty);
    await store.clearRemoteScope();
    await db.execute('DROP TABLE remote_table_states');
    await expectLater(
      store.readRemoteTables(),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      jsonEncode(await db.query('dining_tables', orderBy: 'table_id')),
      before,
    );
    expect(await db.query('held_orders'), [
      {'id': 'held', 'draft_json': 'keep-held'},
    ]);
    expect(await db.query('order_history'), [
      {'id': 'paid', 'snapshot_json': 'keep-paid'},
    ]);
    // ignore: avoid_print
    print(
      'T5_V4_V5_UPGRADE=version:5 dining_tables:3 byte_identical:true held:1 history:1',
    );
  });
}
