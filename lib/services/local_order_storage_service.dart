import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/pos_models.dart';

abstract class OrderStorageService {
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

class LocalOrderStorageService implements OrderStorageService {
  LocalOrderStorageService._();

  static final LocalOrderStorageService instance = LocalOrderStorageService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  @override
  Future<int> fetchNextOrderNumber() async {
    final db = await database;
    final historyMax = Sqflite.firstIntValue(
      await db.rawQuery('SELECT MAX(order_number) FROM order_history'),
    );
    final highest = [historyMax].whereType<int>().fold<int>(
      1449,
      (current, value) => value > current ? value : current,
    );
    return highest + 1;
  }

  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {
    final db = await database;
    final now = DateTime.now();
    await db.insert('order_history', {
      'id': 'history_${snapshot.orderNumber}_${now.microsecondsSinceEpoch}',
      'order_number': snapshot.orderNumber,
      'order_type': snapshot.orderType,
      'created_at': now.toIso8601String(),
      'snapshot_json': jsonEncode(snapshot.toMap()),
    });
  }

  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {
    final db = await database;
    await db.update(
      'order_history',
      {
        'order_number': record.orderNumber,
        'order_type': record.orderType.storageValue,
        'snapshot_json': jsonEncode(record.snapshot.toMap()),
      },
      where: 'id = ?',
      whereArgs: [record.id],
    );
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
    if (orderReference.isNotEmpty) {
      await db.delete(
        'held_orders',
        where: 'order_reference = ?',
        whereArgs: [orderReference],
      );
    }
    await db.insert('held_orders', {
      'id': 'held_${_storageKey(orderReference)}_${now.microsecondsSinceEpoch}',
      'order_number': draft.orderNumber,
      'order_reference': orderReference,
      'order_type': draft.orderType.storageValue,
      'held_at': now.toIso8601String(),
      'draft_json': jsonEncode(draft.toMap()),
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

    await db.insert('dining_tables', {
      'table_id': session.tableId,
      'floor_id': session.floorId,
      'status': session.status.storageValue,
      'order_number': session.orderNumber,
      'order_reference': session.orderReference,
      'updated_at': session.updatedAt.toIso8601String(),
      'occupied_at': session.occupiedAt?.toIso8601String(),
      'paid_at': session.paidAt?.toIso8601String(),
      'draft_json': session.draft == null
          ? null
          : jsonEncode(session.draft!.toMap()),
      'paid_snapshot_json': session.paidSnapshot == null
          ? null
          : jsonEncode(session.paidSnapshot!.toMap()),
      'primary_table_id': session.primaryTableId,
      'linked_table_ids_json': session.linkedTableIds.isEmpty
          ? null
          : jsonEncode(session.linkedTableIds),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async {
    final db = await database;
    final rows = await db.query('dining_tables', orderBy: 'updated_at DESC');
    return rows.map(_mapDiningTableSession).toList();
  }

  @override
  Future<void> clearDiningTable(String tableId) async {
    final db = await database;
    await db.delete(
      'dining_tables',
      where: 'table_id = ?',
      whereArgs: [tableId],
    );
  }

  @override
  Future<void> deleteHeldOrder(String id) async {
    final db = await database;
    await db.delete('held_orders', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearHeldOrders() async {
    final db = await database;
    await db.delete('held_orders');
  }

  @override
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('order_history');
    await db.delete('held_orders');
    await db.delete('dining_tables');
  }

  Future<Database> _openDatabase() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final databasePath = await databaseFactory.getDatabasesPath();
    final path = p.join(databasePath, 'mithqal_orders.db');

    return openDatabase(
      path,
      version: 4,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
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
      },
    );
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
      primaryTableId: (row['primary_table_id'] as String?)?.trim().isNotEmpty == true
          ? row['primary_table_id'] as String
          : null,
      linkedTableIds: _decodeStringList(row['linked_table_ids_json']),
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
