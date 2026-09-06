import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const oldColumns = [
  'table_id',
  'floor_id',
  'status',
  'order_number',
  'order_reference',
  'updated_at',
  'occupied_at',
  'paid_at',
  'draft_json',
  'paid_snapshot_json',
  'primary_table_id',
  'linked_table_ids_json',
];
const oldMetaColumns = [
  'id',
  'feed_cursor',
  'board_fetched_at',
  'last_feed_ok_at',
  'last_error',
  'consecutive_failures',
];

Future<void> createV5(DatabaseExecutor db) async {
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
  await LocalOrderStorageService.createRemoteTables(db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final at = DateTime.utc(2026, 9, 6, 12);

  Future<Database> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await createV5(db);
          await LocalOrderStorageService.createTableLedger(db);
        },
      ),
    );
    addTearDown(db.close);
    return db;
  }

  test('v5 to v6 preserves every existing local and remote meta column byte-identically', () async {
    late String beforeTables, beforeMeta, beforeRemote, beforeDisagreements;
    var upgrades = 0;
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async {
          await createV5(db);
          await db.insert('dining_tables', {
            'table_id': '1',
            'floor_id': '7',
            'status': 'occupied',
            'order_number': 1449,
            'order_reference': 'REF-1449',
            'updated_at': at.toIso8601String(),
            'occupied_at': at.toIso8601String(),
            'paid_at': null,
            'draft_json': '{ "exact" : [1,2] }',
            'paid_snapshot_json': '{"money":4750}',
            'primary_table_id': null,
            'linked_table_ids_json': '["2"]',
          });
          await db.insert('remote_sync_meta', {
            'id': 1,
            'feed_cursor': 48,
            'board_fetched_at': at.toIso8601String(),
            'last_feed_ok_at': at.toIso8601String(),
            'last_error': 'old-error',
            'consecutive_failures': 2,
          });
          await db.insert('held_orders', {
            'id': 'held',
            'draft_json': 'keep-held',
          });
          await db.insert('order_history', {
            'id': 'paid',
            'snapshot_json': 'keep-paid',
          });
          beforeTables = jsonEncode(
            await db.query('dining_tables', columns: oldColumns),
          );
          beforeMeta = jsonEncode(
            await db.query('remote_sync_meta', columns: oldMetaColumns),
          );
          beforeRemote = jsonEncode(await db.query('remote_table_states'));
          beforeDisagreements = jsonEncode(
            await db.query('remote_table_disagreements'),
          );
          await db.setVersion(5);
        },
        onCreate: (_, _) async => fail('A v5 fixture must upgrade'),
        onUpgrade: (db, old, next) async {
          expect(old, 5);
          expect(next, 6);
          upgrades++;
          await LocalOrderStorageService.createTableLedger(db);
        },
      ),
    );
    addTearDown(db.close);
    expect(upgrades, 1);
    expect(await db.getVersion(), 6);
    expect(
      jsonEncode(await db.query('dining_tables', columns: oldColumns)),
      beforeTables,
    );
    expect(
      jsonEncode(await db.query('remote_sync_meta', columns: oldMetaColumns)),
      beforeMeta,
    );
    expect(jsonEncode(await db.query('remote_table_states')), beforeRemote);
    expect(
      jsonEncode(await db.query('remote_table_disagreements')),
      beforeDisagreements,
    );
    expect(await db.query('held_orders'), [
      {'id': 'held', 'draft_json': 'keep-held'},
    ]);
    expect(await db.query('order_history'), [
      {'id': 'paid', 'snapshot_json': 'keep-paid'},
    ]);
    final row = (await db.query('dining_tables')).single;
    for (final column in LocalOrderStorageService.tableSyncColumns) {
      expect(row.containsKey(column), isTrue);
      expect(row[column], isNull);
    }
    expect(
      (await db.query('remote_sync_meta')).single['last_notified_event_id'],
      isNull,
    );
    // ignore: avoid_print
    print(
      'T6_V5_V6_UPGRADE=version:6 dining_tables:1 old_columns:12 byte_identical:true remote_meta_columns:6 byte_identical:true held:1 history:1',
    );
  });

  test(
    'fresh v6 executes the exact ledger columns and keeps Drift separate',
    () async {
      final db = await fresh();
      expect(
        (await db.rawQuery('PRAGMA table_info(local_table_rounds)'))
            .map((row) => row['name'])
            .toList(),
        [
          'client_request_id',
          'table_id',
          'seating_key',
          'local_round_no',
          'lines_json',
          'submitted_at',
          'printed_at',
          'outbox_key',
          'status',
          'server_round_id',
          'server_round_no',
          'order_uuid',
          'total_baisas',
          'review_reasons_json',
          'held_lines_json',
          'acked_at',
        ],
      );
      expect(
        (await db.rawQuery('PRAGMA table_info(local_line_cancellations)'))
            .map((row) => row['name'])
            .toList(),
        [
          'client_request_id',
          'table_id',
          'seating_key',
          'product_id',
          'addon_ids_json',
          'notes',
          'qty',
          'prepared',
          'reason',
          'authorized_by',
          'cancelled_at',
          'outbox_key',
          'status',
          'cancelled_qty',
          'acked_at',
        ],
      );
      expect(
        (await db.rawQuery('PRAGMA table_info(table_sync_verdicts)'))
            .map((row) => row['name'])
            .toList(),
        [
          'id',
          'observed_at',
          'table_id',
          'seating_key',
          'event_kind',
          'outcome',
          'detail_json',
          'seen',
        ],
      );
      final ddl = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name IN ('dining_tables','remote_sync_meta','local_table_rounds','local_line_cancellations','table_sync_verdicts') ORDER BY name",
      );
      // ignore: avoid_print
      print('T6_V6_DDL=${jsonEncode(ddl)}');
    },
  );

  test('ledger round cancellation and verdict CRUD preserves sent payload and table rows', () async {
    final db = await fresh();
    final store = LocalOrderStorageService.forTesting(db);
    final session = DiningTableSession(
      tableId: '1',
      floorId: '7',
      status: DiningTableStatus.occupied,
      updatedAt: at,
      seatingKey: 'seat',
      serverOrderUuid: 'bill',
    );
    await store.saveDiningTableSession(session);
    final before = jsonEncode(await db.query('dining_tables'));
    final round = LocalTableRound(
      clientRequestId: 'request',
      tableId: '1',
      seatingKey: 'seat',
      localRoundNo: 1,
      lines: [
        {
          'product_id': 8,
          'qty': 2,
          'addon_ids': [3],
          'notes': 'No sugar',
        },
      ],
      submittedAt: at,
      printedAt: at,
      outboxKey: 'tbl:seat:round:request',
    );
    await store.saveLocalTableRound(round);
    expect(
      (await store.readLocalTableRounds(
        tableId: '1',
        seatingKey: 'seat',
      )).single.toRow(),
      round.toRow(),
    );
    final accepted = round.withChanges({
      'status': 'appended',
      'server_round_id': 12,
      'server_round_no': 2,
      'order_uuid': 'bill',
      'total_baisas': 2000,
      'acked_at': at.toIso8601String(),
    });
    await store.saveLocalTableRound(accepted);
    final readRound = (await store.readLocalTableRounds()).single;
    expect(readRound.toRow(), accepted.toRow());
    expect(readRound.lines, round.lines);
    expect(readRound.printedAt, at);
    expect(await store.readLocalTableRounds(tableId: 'other'), isEmpty);
    final cancellation = LocalLineCancellation(
      clientRequestId: 'cancel',
      tableId: '1',
      seatingKey: 'seat',
      productId: 8,
      addonIds: [3],
      qty: 1,
      prepared: true,
      cancelledAt: at,
      outboxKey: 'tbl:seat:cancel:cancel',
      reason: 'Correction',
      authorizedBy: 'Manager',
    );
    await store.saveLocalLineCancellation(cancellation);
    expect(
      (await store.readLocalLineCancellations(seatingKey: 'seat')).single
          .toRow(),
      cancellation.toRow(),
    );
    final cancelled = cancellation.withChanges({
      'status': 'cancelled',
      'cancelled_qty': 1,
      'acked_at': at.toIso8601String(),
    });
    await store.saveLocalLineCancellation(cancelled);
    expect(
      (await store.readLocalLineCancellations()).single.toRow(),
      cancelled.toRow(),
    );
    final verdict = TableSyncVerdict(
      observedAt: at,
      tableId: '1',
      seatingKey: 'seat',
      eventKind: 'open',
      outcome: 'merged',
      detail: {'winner': 'primary'},
    );
    final id = await store.addTableSyncVerdict(verdict);
    expect(
      (await store.readTableSyncVerdicts(unseenOnly: true)).single.toRow(),
      {'id': id, ...verdict.toRow()},
    );
    await store.markTableSyncVerdictsSeen([id]);
    expect(await store.readTableSyncVerdicts(unseenOnly: true), isEmpty);
    expect((await store.readTableSyncVerdicts()).single.seen, isTrue);
    expect(jsonEncode(await db.query('dining_tables')), before);
  });

  test('identity fields round trip and acknowledgement patches cannot change table status', () async {
    final db = await fresh();
    final store = LocalOrderStorageService.forTesting(db);
    final draft = OrderSessionDraft.fromMap({
      'orderReference': 'REF',
      'orderType': 'dine_in',
      'serverOrderUuid': 'old',
    });
    final session = DiningTableSession(
      tableId: '1',
      floorId: '7',
      status: DiningTableStatus.occupied,
      updatedAt: at,
      draft: draft,
      seatingKey: 'key',
      seatingUuid: 'seat',
      seatingState: 'open',
      serverOrderUuid: 'old',
      tempReference: 'T-0906-001',
      winnerSeatingUuid: 'winner',
      lastVerdict: 'attached',
      lastVerdictAt: at,
    );
    expect(
      DiningTableSession.fromMap(session.toMap()).toMap(),
      session.toMap(),
    );
    final legacyMap = session.toMap()
      ..remove('seatingKey')
      ..remove('seatingUuid')
      ..remove('lastVerdictAt');
    expect(DiningTableSession.fromMap(legacyMap).seatingKey, isNull);
    expect(session.copyWith().toMap(), session.toMap());
    expect(session.copyWith(clearSeating: true).seatingKey, isNull);
    await store.saveDiningTableSession(session);
    expect(
      (await store.loadDiningTableSessions()).single.toMap(),
      session.toMap(),
    );
    await store.updateTableSyncFields('1', {
      'server_order_uuid': 'winner-bill',
      'last_verdict': 'merged',
    });
    final rebound = (await store.loadDiningTableSessions()).single;
    expect(rebound.status, DiningTableStatus.occupied);
    expect(rebound.serverOrderUuid, 'winner-bill');
    expect(rebound.draft!.serverOrderUuid, 'winner-bill');
    await store.saveDiningTableSession(session);
    expect((await store.loadDiningTableSessions()).single.toMap(), rebound.toMap());
    await expectLater(
      store.updateTableSyncFields('1', {'status': 'available'}),
      throwsArgumentError,
    );
    expect(
      (await store.loadDiningTableSessions()).single.toMap(),
      rebound.toMap(),
    );
  });

  test('notification watermark survives old-style metadata saves and never moves backwards', () async {
    final db = await fresh();
    final store = LocalOrderStorageService.forTesting(db);
    await store.saveRemoteMeta(
      RemoteSyncMeta(feedCursor: 21, lastNotifiedEventId: 20, lastFeedOkAt: at),
    );
    await store.saveRemoteMeta(
      RemoteSyncMeta(feedCursor: 22, lastFeedOkAt: at),
    );
    expect((await store.readRemoteMeta()).lastNotifiedEventId, 20);
    await store.saveRemoteMeta(
      const RemoteSyncMeta(feedCursor: 23, lastNotifiedEventId: 19),
    );
    expect((await store.readRemoteMeta()).lastNotifiedEventId, 20);
    expect((await store.readRemoteMeta()).feedCursor, 23);
    await store.clearRemoteScope();
    expect((await store.readRemoteMeta()).lastNotifiedEventId, isNull);
  });

  test('failed ledger reads never mutate dining tables', () async {
    final db = await fresh();
    final store = LocalOrderStorageService.forTesting(db);
    await store.saveDiningTableSession(
      DiningTableSession(
        tableId: '1',
        floorId: '7',
        status: DiningTableStatus.occupied,
        updatedAt: at,
      ),
    );
    final before = jsonEncode(await db.query('dining_tables'));
    await db.execute('DROP TABLE local_table_rounds');
    await expectLater(
      store.readLocalTableRounds(),
      throwsA(isA<DatabaseException>()),
    );
    expect(jsonEncode(await db.query('dining_tables')), before);
  });
}
