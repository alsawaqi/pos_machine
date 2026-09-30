import '../tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_sqlite.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/pos_models.dart';
import '../models/remote_table_state.dart';
import '../models/table_sync_models.dart';
import '../bill_combine/combine_store.dart';
import '../draft_recovery/recovery_store.dart';
import 'table_action_deadline.dart';
import '../draft_recovery/saved_copy_discard.dart';

/// Optional capability: older test stores need not pretend to persist recovery.
abstract interface class DraftRecoveryGuard {
  ValueListenable<bool> get recoveryBlocked;
  Future<void> refreshRecoveryGuard();
  Future<void> assertDraftNotRetired({
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  });
}

abstract interface class ProvisionalReceiptRemoval {
  Future<void> removeProvisionalReceipt(String uuid);
}

/// A joined party is one saved bill: clearing it must commit all seats or none.
abstract interface class AtomicDiningTableClear {
  Future<void> clearDiningTables(Iterable<String> tableIds);
}

abstract class OrderStorageService {
  Future<void> assertNoPendingCombine() async {}
  Future<int> fetchNextOrderNumber();
  Future<void> saveCompletedOrder(OrderSnapshot snapshot);
  Future<void> updateCompletedOrder(OrderHistoryRecord record);
  Future<List<OrderHistoryRecord>> loadOrderHistory();
  Future<void> saveHeldOrder(OrderSessionDraft draft);
  Future<List<HeldOrderRecord>> loadHeldOrders();
  Future<void> saveDiningTableSession(DiningTableSession session);
  Future<List<DiningTableSession>> loadDiningTableSessions();
  Future<void> clearDiningTable(String tableId);
  Future<void> deleteHeldOrder(String id);
  Future<void> clearHeldOrders();
  Future<void> clearAllData();
}

/// Test-only replacement consulted by [PosController]'s default wiring —
/// same convention as Flutter's `debug*Override` globals. Widget tests pump
/// the REAL app (no constructor injection point), and the sqflite-FFI
/// database cannot complete its I/O inside testWidgets' FakeAsync zone — so
/// tests park an in-memory fake here. Never set in production.
OrderStorageService? debugOrderStorageOverride;

class LocalOrderStorageService
    implements
        OrderStorageService,
        RemoteTableStore,
        TableLedgerStore,
        DraftRecoveryGuard,
        ArchivedTableOutbox,
        AtomicDiningTableClear,
        ProvisionalReceiptRemoval {
  LocalOrderStorageService._();

  @visibleForTesting
  LocalOrderStorageService.forTesting(Database database) : _database = database;

  static LocalOrderStorageService _instance = LocalOrderStorageService._();
  static LocalOrderStorageService get instance {
    if (_instance._ownerGeneration != BusinessBoundary.generation.value) {
      _instance = LocalOrderStorageService._();
    }
    return _instance;
  }

  final _ownerGeneration = BusinessBoundary.generation.value;

  @override
  Future<bool> tableOutboxArchived(String key, String eventsJson) async {
    final saved = (await archivedTableOutbox())[key];
    if (saved == null) return false;
    if (saved != eventsJson) throw StateError('Archived request changed');
    return true;
  }

  /// Every verified manager-discard archive is read once; an archive that no
  /// longer proves itself fails closed for sending (callers decide display).
  @override
  Future<Map<String, String>> archivedTableOutbox() async {
    final db = await database;
    if ((await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='draft_recovery_closed_archive'",
    )).isEmpty) {
      return const {};
    }
    final archived = <String, String>{};
    for (final row in await db.query('draft_recovery_closed_archive')) {
      final raw =
          jsonDecode(row['local_json'] as String) as Map<String, dynamic>;
      if (raw['kind'] != 'manager_discard') continue;
      final copy = SavedCopyDiscard(raw);
      if (row['order_uuid'] != copy.uuid ||
          !copy.proves(
            jsonDecode(row['proof_json'] as String) as Map<String, dynamic>,
          )) {
        throw const FormatException('Invalid saved-copy archive');
      }
      for (final event in copy.outbox) {
        archived.putIfAbsent(
          event['key'] as String,
          () => event['events_json'] as String,
        );
      }
    }
    return archived;
  }

  Database? _database;
  Future<Database>? _opening;
  final _recoveryBlocked = ValueNotifier<bool>(true);
  bool _recoveryAdmission = false;

  @override
  ValueListenable<bool> get recoveryBlocked => _recoveryBlocked;

  void beginRecoveryAdmission() {
    if (_recoveryAdmission) {
      throw StateError('Recovery admission is already running.');
    }
    _recoveryAdmission = true;
    _recoveryBlocked.value = true;
  }

  Future<void> endRecoveryAdmission() async {
    _recoveryAdmission = false;
    await refreshRecoveryGuard();
  }

  @override
  Future<void> refreshRecoveryGuard() async {
    _recoveryBlocked.value = true;
    final pending = await RecoveryStore.pending(await database);
    _recoveryBlocked.value = _recoveryAdmission || pending;
  }

  Future<void> assertRecoveryIdle() async {
    if (_recoveryAdmission) throw StateError('Recovery admission is running.');
    await RecoveryStore.assertNonePending(await database);
  }

  @override
  Future<void> assertDraftNotRetired({
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  }) async => RecoveryStore.assertNotRetired(
    await database,
    uuid: uuid,
    tableId: tableId,
    reference: reference,
    occupiedAt: occupiedAt,
    seatingKey: seatingKey,
  );

  Future<void> _guard(
    DatabaseExecutor db, {
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  }) async {
    TableActionDeadline.current?.check();
    if (_recoveryAdmission) throw StateError('Recovery admission is running.');
    await RecoveryStore.assertNonePending(db);
    await RecoveryStore.assertNotRetired(
      db,
      uuid: uuid,
      tableId: tableId,
      reference: reference,
      occupiedAt: occupiedAt,
      seatingKey: seatingKey,
    );
    TableActionDeadline.current?.check();
  }

  Future<void> guardTableSession(DiningTableSession s) async {
    await assertRecoveryIdle();
    await assertDraftNotRetired(
      uuid: s.serverOrderUuid ?? s.draft?.serverOrderUuid,
      tableId: s.tableId,
      reference: s.orderReference,
      occupiedAt: s.occupiedAt?.toIso8601String(),
      seatingKey: s.seatingKey,
    );
  }

  Future<Database> get database async {
    BusinessBoundary.assertGeneration(_ownerGeneration);
    if (_database != null) {
      if (_database!.isOpen) return _database!;
      _database = null;
      _opening = null;
    }
    try {
      _database = await (_opening ??= _openDatabase());
      return _database!;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<void> assertNoPendingCombine() async {
    await CombineStore.assertNonePending(await database);
    await assertRecoveryIdle();
  }

  @override
  Future<int> fetchNextOrderNumber() async {
    final db = await database;
    var highest = 1449;
    for (final row in await db.query(
      'order_history',
      columns: ['order_number', 'snapshot_json'],
    )) {
      var serverReceipt = false;
      try {
        final snapshot = jsonDecode(row['snapshot_json'] as String);
        serverReceipt = snapshot is Map && snapshot['serverReceipt'] == true;
      } catch (_) {
        // Unrecognised history must still reserve its legacy local number.
      }
      if (serverReceipt) continue;
      final number = row['order_number'];
      if (number is int && number > highest) highest = number;
    }
    return highest + 1;
  }

  @override
  Future<void> removeProvisionalReceipt(String uuid) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final row in await txn.query('order_history')) {
        final value = jsonDecode(row['snapshot_json'] as String) as Map;
        if (value['serverOrderUuid'] == uuid &&
            value['serverReceipt'] == true &&
            value['serverReceiptConfirmed'] != true &&
            (value['receiptNumber'] == null || value['receiptNumber'] == '')) {
          await txn.delete(
            'order_history',
            where: 'id = ? AND snapshot_json = ?',
            whereArgs: [row['id'], row['snapshot_json']],
          );
        }
      }
    });
  }

  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {
    final db = await database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await _guard(
        txn,
        uuid: snapshot.serverOrderUuid,
        tableId: snapshot.diningTableId,
      );
      await txn.insert('order_history', {
        'id': 'history_${snapshot.orderNumber}_${now.microsecondsSinceEpoch}',
        'order_number': snapshot.orderNumber,
        'order_type': snapshot.orderType,
        'created_at': now.toIso8601String(),
        'snapshot_json': jsonEncode(snapshot.toMap()),
      });
    });
  }

  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {
    final db = await database;
    await db.transaction((txn) async {
      await _guard(
        txn,
        uuid: record.snapshot.serverOrderUuid,
        tableId: record.snapshot.diningTableId,
      );
      await txn.update(
        'order_history',
        {
          'order_number': record.orderNumber,
          'order_type': record.orderType.storageValue,
          'snapshot_json': jsonEncode(record.snapshot.toMap()),
        },
        where: 'id = ?',
        whereArgs: [record.id],
      );
    });
  }

  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async {
    final db = await database;
    final rows = await db.query('order_history', orderBy: 'created_at DESC');
    return rows.map(_mapHistoryRecord).toList();
  }

  @override
  Future<void> saveHeldOrder(OrderSessionDraft draft) async {
    final db = await database;
    final now = DateTime.now();
    final orderReference = draft.orderReference.trim();
    await db.transaction((txn) async {
      await _guard(
        txn,
        uuid: draft.serverOrderUuid,
        tableId: draft.diningTableId,
        reference: draft.orderReference,
      );
      if (orderReference.isNotEmpty) {
        await txn.delete(
          'held_orders',
          where: 'order_reference = ?',
          whereArgs: [orderReference],
        );
      }
      await txn.insert('held_orders', {
        'id':
            'held_${_storageKey(orderReference)}_${now.microsecondsSinceEpoch}',
        'order_number': draft.orderNumber,
        'order_reference': orderReference,
        'order_type': draft.orderType.storageValue,
        'held_at': now.toIso8601String(),
        'draft_json': jsonEncode(draft.toMap()),
      });
    });
  }

  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async {
    final db = await database;
    final rows = await db.query('held_orders', orderBy: 'held_at DESC');
    return rows.map(_mapHeldRecord).toList();
  }

  @override
  Future<void> saveDiningTableSession(DiningTableSession session) async {
    final db = await database;

    if (session.status == DiningTableStatus.available) {
      await clearDiningTable(session.tableId);
      return;
    }

    await db.transaction((txn) async {
      await _guard(
        txn,
        uuid: session.serverOrderUuid ?? session.draft?.serverOrderUuid,
        tableId: session.tableId,
        reference: session.orderReference,
        occupiedAt: session.occupiedAt?.toIso8601String(),
        seatingKey: session.seatingKey,
      );
      final existing = await txn.query(
        'dining_tables',
        columns: tableSyncColumns,
        where: 'table_id = ?',
        whereArgs: [session.tableId],
      );
      // Cashier snapshots can predate an acknowledgement. Identity changes
      // go through updateTableSyncFields; ordinary saves cannot undo them.
      final sync = <String, Object?>{
        'seating_key': session.seatingKey,
        'seating_uuid': session.seatingUuid,
        'seating_state': session.seatingState,
        'server_order_uuid': session.serverOrderUuid,
        'temp_reference': session.tempReference,
        'winner_seating_uuid': session.winnerSeatingUuid,
        'last_verdict': session.lastVerdict,
        'last_verdict_at': session.lastVerdictAt?.toIso8601String(),
        if (existing.isNotEmpty) ...existing.single,
      };
      final draft = session.draft?.toMap();
      if (draft != null && sync['server_order_uuid'] is String) {
        draft['serverOrderUuid'] = sync['server_order_uuid'];
      }
      await txn.insert('dining_tables', {
        'table_id': session.tableId,
        'floor_id': session.floorId,
        'status': session.status.storageValue,
        'order_number': session.orderNumber,
        'order_reference': session.orderReference,
        'updated_at': session.updatedAt.toIso8601String(),
        'occupied_at': session.occupiedAt?.toIso8601String(),
        'paid_at': session.paidAt?.toIso8601String(),
        'draft_json': draft == null ? null : jsonEncode(draft),
        'paid_snapshot_json': session.paidSnapshot == null
            ? null
            : jsonEncode(session.paidSnapshot!.toMap()),
        'primary_table_id': session.primaryTableId,
        'linked_table_ids_json': session.linkedTableIds.isEmpty
            ? null
            : jsonEncode(session.linkedTableIds),
        ...sync,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      TableActionDeadline.current?.check();
    });
  }

  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async {
    final db = await database;
    final rows = await db.query('dining_tables', orderBy: 'updated_at DESC');
    return rows.map(_mapDiningTableSession).toList();
  }

  @override
  Future<void> clearDiningTable(String tableId) => clearDiningTables([tableId]);

  @override
  Future<void> clearDiningTables(Iterable<String> tableIds) async {
    final ids = tableIds.toSet();
    final db = await database;
    await db.transaction((txn) async {
      await _guard(txn);
      for (final id in ids) {
        await txn.delete(
          'dining_tables',
          where: 'table_id = ?',
          whereArgs: [id],
        );
      }
      TableActionDeadline.current?.check();
    });
  }

  @override
  Future<void> deleteHeldOrder(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await _guard(txn);
      await txn.delete('held_orders', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> clearHeldOrders() async {
    final db = await database;
    await db.transaction((txn) async {
      await _guard(txn);
      await txn.delete('held_orders');
    });
  }

  @override
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await _guard(txn);
      await txn.delete('order_history');
      await txn.delete('held_orders');
      await txn.delete('dining_tables');
    });
  }

  Future<Database> _openDatabase() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final databasePath = await databaseFactory.getDatabasesPath();
    final path = p.join(databasePath, 'mithqal_orders.db');

    return openBusinessDatabase(
      path,
      version: 10,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE order_history (
            id TEXT PRIMARY KEY,
            order_number INTEGER NOT NULL,
            order_type TEXT NOT NULL,
            created_at TEXT NOT NULL,
            snapshot_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE held_orders (
            id TEXT PRIMARY KEY,
            order_number INTEGER,
            order_reference TEXT NOT NULL,
            order_type TEXT NOT NULL,
            held_at TEXT NOT NULL,
            draft_json TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE dining_tables (
            table_id TEXT PRIMARY KEY,
            floor_id TEXT NOT NULL,
            status TEXT NOT NULL,
            order_number INTEGER,
            order_reference TEXT,
            updated_at TEXT NOT NULL,
            occupied_at TEXT,
            paid_at TEXT,
            draft_json TEXT,
            paid_snapshot_json TEXT,
            primary_table_id TEXT,
            linked_table_ids_json TEXT
          )
        ''');
        await createRemoteTables(db);
        await createTableLedger(db);
        await createRemoteBillIdentity(db);
        await CombineStore.createSchema(db);
        await RecoveryStore.createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 10) await RecoveryStore.createClosedSchema(db);
        if (oldVersion < 9) await RecoveryStore.createSchema(db);
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS dining_tables (
              table_id TEXT PRIMARY KEY,
              floor_id TEXT NOT NULL,
              status TEXT NOT NULL,
              order_number INTEGER,
              updated_at TEXT NOT NULL,
              occupied_at TEXT,
              paid_at TEXT,
              draft_json TEXT,
              paid_snapshot_json TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE held_orders RENAME TO held_orders_old');
          await db.execute('''
            CREATE TABLE held_orders (
              id TEXT PRIMARY KEY,
              order_number INTEGER,
              order_reference TEXT NOT NULL,
              order_type TEXT NOT NULL,
              held_at TEXT NOT NULL,
              draft_json TEXT NOT NULL
            )
          ''');
          await db.execute('''
            INSERT INTO held_orders (
              id,
              order_number,
              order_reference,
              order_type,
              held_at,
              draft_json
            )
            SELECT
              id,
              order_number,
              'REF-' || order_number,
              order_type,
              held_at,
              draft_json
            FROM held_orders_old
          ''');
          await db.execute('DROP TABLE held_orders_old');
          await db.execute(
            'ALTER TABLE dining_tables ADD COLUMN order_reference TEXT',
          );
          await db.execute('''
            UPDATE dining_tables
            SET order_reference = CASE
              WHEN order_number IS NULL THEN ''
              ELSE 'REF-' || order_number
            END
            WHERE order_reference IS NULL
          ''');
        }
        if (oldVersion < 4) {
          // Joined tables: a linked seat points at its party's head, the head
          // lists its linked seats.
          await db.execute(
            'ALTER TABLE dining_tables ADD COLUMN primary_table_id TEXT',
          );
          await db.execute(
            'ALTER TABLE dining_tables ADD COLUMN linked_table_ids_json TEXT',
          );
        }
        if (oldVersion < 5) {
          await createRemoteTables(db);
        }
        if (oldVersion < 6) {
          await createTableLedger(db);
        }
        if (oldVersion < 8) {
          await CombineStore.createSchema(db);
        }
        if (oldVersion < 7) {
          await createRemoteBillIdentity(db);
        }
      },
    );
  }

  /// Shared by fresh creation and the additive v4-to-v5 upgrade.
  static Future<void> createRemoteTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE remote_table_states (
        table_id INTEGER PRIMARY KEY,
        seating_uuid TEXT, seating_status TEXT, origin TEXT, temp_reference TEXT,
        opened_at TEXT, expires_at TEXT,
        needs_review_count INTEGER NOT NULL DEFAULT 0,
        joined_table_ids_json TEXT,
        bill_order_uuid TEXT, bill_status TEXT, bill_grand_total_baisas INTEGER,
        bill_receipt_number TEXT, bill_temp_reference TEXT,
        charge_claim_live INTEGER NOT NULL DEFAULT 0,
        fetched_at TEXT NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE remote_sync_meta (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        feed_cursor INTEGER,
        board_fetched_at TEXT, last_feed_ok_at TEXT, last_error TEXT,
        consecutive_failures INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE remote_table_disagreements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        observed_at TEXT NOT NULL, table_id TEXT NOT NULL,
        local_status TEXT NOT NULL,
        server_status TEXT NOT NULL,
        server_origin TEXT, server_reference TEXT, local_reference TEXT,
        kind TEXT NOT NULL
      )
    ''');
  }

  /// Additive v5-to-v6 schema; also applied after the v5 fresh schema.
  static Future<void> createTableLedger(DatabaseExecutor db) async {
    for (final column in tableSyncColumns) {
      await db.execute('ALTER TABLE dining_tables ADD COLUMN $column TEXT');
    }
    await db.execute(
      'ALTER TABLE remote_sync_meta ADD COLUMN last_notified_event_id INTEGER',
    );
    await db.execute('''
      CREATE TABLE local_table_rounds (
        client_request_id TEXT PRIMARY KEY,
        table_id TEXT NOT NULL, seating_key TEXT NOT NULL,
        local_round_no INTEGER NOT NULL, lines_json TEXT NOT NULL,
        submitted_at TEXT NOT NULL, printed_at TEXT, outbox_key TEXT NOT NULL,
        status TEXT NOT NULL, server_round_id INTEGER, server_round_no INTEGER,
        order_uuid TEXT, total_baisas INTEGER, review_reasons_json TEXT,
        held_lines_json TEXT, acked_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE local_line_cancellations (
        client_request_id TEXT PRIMARY KEY,
        table_id TEXT NOT NULL, seating_key TEXT NOT NULL,
        product_id INTEGER NOT NULL, addon_ids_json TEXT NOT NULL, notes TEXT,
        qty INTEGER NOT NULL, prepared INTEGER NOT NULL, reason TEXT, authorized_by TEXT,
        cancelled_at TEXT NOT NULL, outbox_key TEXT NOT NULL, status TEXT NOT NULL,
        cancelled_qty INTEGER, acked_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE table_sync_verdicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        observed_at TEXT NOT NULL, table_id TEXT NOT NULL, seating_key TEXT,
        event_kind TEXT NOT NULL, outcome TEXT NOT NULL, detail_json TEXT,
        seen INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Additive v6-to-v7 board identity; local tables and the Drift outbox are untouched.
  static Future<void> createRemoteBillIdentity(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE remote_table_states ADD COLUMN bill_source TEXT',
    );
    await db.execute(
      'ALTER TABLE remote_table_states ADD COLUMN bill_customer_rounds INTEGER',
    );
    await db.execute(
      'ALTER TABLE remote_table_states ADD COLUMN bill_staff_rounds INTEGER',
    );
    await db.execute(
      'ALTER TABLE remote_table_states ADD COLUMN credential_status TEXT',
    );
  }

  static const tableSyncColumns = [
    'seating_key',
    'seating_uuid',
    'seating_state',
    'server_order_uuid',
    'temp_reference',
    'winner_seating_uuid',
    'last_verdict',
    'last_verdict_at',
  ];

  @override
  Future<void> saveLocalTableRound(LocalTableRound round) async {
    final db = await database;
    await db.transaction((txn) async {
      await _guard(
        txn,
        uuid: round.orderUuid,
        tableId: round.tableId,
        seatingKey: round.seatingKey,
      );
      await txn.insert(
        'local_table_rounds',
        round.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<LocalTableRound>> readLocalTableRounds({
    String? tableId,
    String? seatingKey,
  }) async {
    final db = await database;
    return (await db.query(
      'local_table_rounds',
      where: _ledgerWhere(tableId, seatingKey),
      whereArgs: [?tableId, ?seatingKey],
      orderBy: 'local_round_no, client_request_id',
    )).map(LocalTableRound.fromRow).toList(growable: false);
  }

  @override
  Future<void> saveLocalLineCancellation(
    LocalLineCancellation cancellation,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await _guard(
        txn,
        tableId: cancellation.tableId,
        seatingKey: cancellation.seatingKey,
      );
      await txn.insert(
        'local_line_cancellations',
        cancellation.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<List<LocalLineCancellation>> readLocalLineCancellations({
    String? tableId,
    String? seatingKey,
  }) async {
    final db = await database;
    return (await db.query(
      'local_line_cancellations',
      where: _ledgerWhere(tableId, seatingKey),
      whereArgs: [?tableId, ?seatingKey],
      orderBy: 'cancelled_at, client_request_id',
    )).map(LocalLineCancellation.fromRow).toList(growable: false);
  }

  String? _ledgerWhere(String? tableId, String? seatingKey) {
    final clauses = [
      if (tableId != null) 'table_id = ?',
      if (seatingKey != null) 'seating_key = ?',
    ];
    return clauses.isEmpty ? null : clauses.join(' AND ');
  }

  @override
  Future<int> addTableSyncVerdict(TableSyncVerdict verdict) async {
    final db = await database;
    return db.insert('table_sync_verdicts', verdict.toRow());
  }

  @override
  Future<List<TableSyncVerdict>> readTableSyncVerdicts({
    bool unseenOnly = false,
    int limit = 200,
  }) async {
    final db = await database;
    return (await db.query(
      'table_sync_verdicts',
      where: unseenOnly ? 'seen = 0' : null,
      orderBy: 'id DESC',
      limit: limit.clamp(1, 200),
    )).map(TableSyncVerdict.fromRow).toList(growable: false);
  }

  @override
  Future<void> markTableSyncVerdictsSeen(List<int> ids) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'table_sync_verdicts',
          {'seen': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  /// Own-event acknowledgements may change identity metadata, never table status.
  @override
  Future<void> updateTableSyncFields(
    String tableId,
    Map<String, Object?> fields,
  ) async {
    if (fields.keys.any((key) => !tableSyncColumns.contains(key))) {
      throw ArgumentError(
        'Only seating metadata may be patched by a table acknowledgement',
      );
    }
    if (fields.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final values = Map<String, Object?>.of(fields);
      await _guard(
        txn,
        uuid: fields['server_order_uuid'] as String?,
        tableId: tableId,
        seatingKey: fields['seating_key'] as String?,
      );
      final uuid = fields['server_order_uuid'];
      if (uuid is String && uuid.isNotEmpty) {
        final rows = await txn.query(
          'dining_tables',
          columns: ['draft_json'],
          where: 'table_id = ?',
          whereArgs: [tableId],
        );
        if (rows.isNotEmpty && rows.single['draft_json'] != null) {
          final draft = _decodeJsonMap(rows.single['draft_json']);
          values['draft_json'] = jsonEncode({
            ...draft,
            'serverOrderUuid': uuid,
          });
        }
      }
      await txn.update(
        'dining_tables',
        values,
        where: 'table_id = ?',
        whereArgs: [tableId],
      );
    });
  }

  @override
  Future<List<RemoteTableState>> readRemoteTables() async {
    final db = await database;
    return (await db.query(
      'remote_table_states',
    )).map(RemoteTableState.fromRow).toList(growable: false);
  }

  @override
  Future<RemoteSyncMeta> readRemoteMeta() async {
    final db = await database;
    final rows = await db.query('remote_sync_meta', where: 'id = 1');
    return rows.isEmpty
        ? const RemoteSyncMeta()
        : RemoteSyncMeta.fromRow(rows.single);
  }

  @override
  Future<void> replaceRemoteBoard(
    List<RemoteTableState> rows,
    DateTime at,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('remote_table_states');
      for (final row in rows) {
        await txn.insert('remote_table_states', row.toRow());
      }
      await txn.rawInsert(
        'INSERT OR IGNORE INTO remote_sync_meta (id) VALUES (1)',
      );
      await txn.update('remote_sync_meta', {
        'board_fetched_at': at.toIso8601String(),
      }, where: 'id = 1');
    });
  }

  @override
  Future<void> saveRemoteMeta(RemoteSyncMeta meta) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = await txn.query('remote_sync_meta', where: 'id = 1');
      final row = meta.toRow();
      final watermark = existing.isEmpty
          ? null
          : existing.single['last_notified_event_id'];
      if (watermark is int &&
          (meta.lastNotifiedEventId == null ||
              watermark > meta.lastNotifiedEventId!)) {
        row['last_notified_event_id'] = watermark;
      }
      await txn.insert(
        'remote_sync_meta',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> clearRemoteScope() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('remote_table_states');
      await txn.delete('remote_sync_meta');
      await txn.delete('remote_table_disagreements');
    });
  }

  @override
  Future<List<Map<String, Object?>>> readRemoteDisagreements({
    int limit = 200,
  }) async {
    final db = await database;
    return db.query(
      'remote_table_disagreements',
      orderBy: 'id DESC',
      limit: limit,
    );
  }

  @override
  Future<void> addRemoteDisagreement(Map<String, Object?> row) async {
    final db = await database;
    await db.insert('remote_table_disagreements', row);
  }

  OrderHistoryRecord _mapHistoryRecord(Map<String, Object?> row) {
    final snapshotMap = _decodeJsonMap(row['snapshot_json']);
    final snapshot = OrderSnapshot.fromMap(snapshotMap);
    return OrderHistoryRecord(
      id: row['id']?.toString() ?? '',
      orderNumber:
          (row['order_number'] as num?)?.toInt() ?? snapshot.orderNumber,
      orderType: OrderTypeLabel.fromStorage(row['order_type']?.toString()),
      createdAt: _parseStoredDate(row['created_at']) ?? DateTime.now(),
      snapshot: snapshot,
    );
  }

  HeldOrderRecord _mapHeldRecord(Map<String, Object?> row) {
    final draftMap = _decodeJsonMap(row['draft_json']);
    final draft = OrderSessionDraft.fromMap(draftMap);
    return HeldOrderRecord(
      id: row['id']?.toString() ?? '',
      orderNumber: (row['order_number'] as num?)?.toInt() ?? draft.orderNumber,
      orderReference:
          row['order_reference']?.toString() ?? draft.orderReference,
      orderType: OrderTypeLabel.fromStorage(row['order_type']?.toString()),
      heldAt: _parseStoredDate(row['held_at']) ?? DateTime.now(),
      draft: draft,
    );
  }

  DiningTableSession _mapDiningTableSession(Map<String, Object?> row) {
    final draftMap = _decodeJsonMap(row['draft_json']);
    final snapshotMap = _decodeJsonMap(row['paid_snapshot_json']);

    final draft = draftMap.isEmpty ? null : OrderSessionDraft.fromMap(draftMap);
    final paidSnapshot = snapshotMap.isEmpty
        ? null
        : OrderSnapshot.fromMap(snapshotMap);

    return DiningTableSession(
      tableId: row['table_id']?.toString() ?? '',
      floorId: row['floor_id']?.toString() ?? '',
      status: DiningTableStatusLabel.fromStorage(row['status']?.toString()),
      orderNumber: (row['order_number'] as num?)?.toInt(),
      orderReference:
          row['order_reference']?.toString() ?? draft?.orderReference ?? '',
      updatedAt: _parseStoredDate(row['updated_at']) ?? DateTime.now(),
      occupiedAt: _parseStoredDate(row['occupied_at']),
      paidAt: _parseStoredDate(row['paid_at']),
      draft: draft,
      paidSnapshot: paidSnapshot,
      primaryTableId:
          (row['primary_table_id'] as String?)?.trim().isNotEmpty == true
          ? row['primary_table_id'] as String
          : null,
      linkedTableIds: _decodeStringList(row['linked_table_ids_json']),
      seatingKey: row['seating_key'] as String?,
      seatingUuid: row['seating_uuid'] as String?,
      seatingState: row['seating_state'] as String?,
      serverOrderUuid: row['server_order_uuid'] as String?,
      tempReference: row['temp_reference'] as String?,
      winnerSeatingUuid: row['winner_seating_uuid'] as String?,
      lastVerdict: row['last_verdict'] as String?,
      lastVerdictAt: _parseStoredDate(row['last_verdict_at']),
    );
  }

  /// Decode a JSON string array column into a List&lt;String&gt; (joined-table
  /// links). Null / blank / malformed → empty list.
  List<String> _decodeStringList(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // fall through
    }
    return const [];
  }

  Map<String, dynamic> _decodeJsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }

  DateTime? _parseStoredDate(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      return null;
    }

    return DateTime.tryParse(text);
  }

  String _storageKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'draft';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }
}
