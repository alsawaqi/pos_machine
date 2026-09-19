import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'dine_in_models.dart';

abstract interface class DineInStore {
  Future<DineInRequest?> load();
  Future<void> save(DineInRequest request);
  Future<void> remove(DineInRequest request);
}

abstract interface class DineInDraftStore {
  Future<Map<String, dynamic>?> loadDraft(int tableId);
  Future<void> saveDraft(int tableId, Map<String, dynamic>? draft);
}

/// Legacy round intents stay device-wide; adjustments are isolated per table.
/// Namespaced records use the existing schema; no table or column migration.
class SqliteDineInStore implements DineInStore, DineInDraftStore {
  SqliteDineInStore(this.db, this.scope, {this.tableId});
  final int? tableId;
  SqliteDineInStore forTable(int id) =>
      SqliteDineInStore(db, scope, tableId: id);
  String _adjustScope(int id) => "$scope::adjustment:$id";
  final Database db;
  final String scope;
  static Future<SqliteDineInStore> open(String scope) async {
    final directory = await getDatabasesPath();
    final db = await openDatabase(
      '$directory/dine_in_requests.db',
      version: 2,
      onUpgrade: (db, old, next) => _createDrafts(db),
      onCreate: (db, _) => createSchema(db),
    );
    return SqliteDineInStore(db, scope);
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('''
    CREATE TABLE dine_in_requests (scope TEXT PRIMARY KEY, table_id INTEGER NOT NULL,
      seating_uuid TEXT NOT NULL, bill_uuid TEXT, request_id TEXT NOT NULL, payload TEXT NOT NULL)
  ''');
    await _createDrafts(db);
  }

  static Future<void> _createDrafts(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS dine_in_drafts (scope TEXT NOT NULL,
      table_id INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(scope, table_id))
  ''');

  @override
  Future<Map<String, dynamic>?> loadDraft(int tableId) async {
    final rows = await db.query(
      'dine_in_drafts',
      where: 'scope = ? AND table_id = ?',
      whereArgs: [scope, tableId],
    );
    return rows.isEmpty
        ? null
        : tableMap(jsonDecode(rows.single['payload'] as String));
  }

  @override
  Future<void> saveDraft(int tableId, Map<String, dynamic>? draft) async {
    if (draft == null) {
      await db.delete(
        'dine_in_drafts',
        where: 'scope = ? AND table_id = ?',
        whereArgs: [scope, tableId],
      );
    } else {
      await db.insert('dine_in_drafts', {
        'scope': scope,
        'table_id': tableId,
        'payload': jsonEncode(draft),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  DineInRequest _decode(Map<String, Object?> row) {
    final request = DineInRequest(
      tableId: row['table_id'] as int,
      seatingUuid: row['seating_uuid'] as String,
      billUuid: row['bill_uuid'] as String?,
      payload: tableMap(jsonDecode(row['payload'] as String)),
    );
    if (request.id != row['request_id']) {
      throw StateError('Corrupt round journal');
    }
    return request;
  }

  Future<List<DineInRequest>> _all(DatabaseExecutor executor) async {
    final prefix = '$scope::adjustment:';
    final rows = await executor.query(
      'dine_in_requests',
      where: 'scope = ? OR substr(scope, 1, ?) = ?',
      whereArgs: [scope, prefix.length, prefix],
    );
    return rows.map(_decode).toList();
  }

  @override
  Future<DineInRequest?> load() async {
    final requests = await _all(db);
    return requests
        .where(
          (r) => tableId == null || !r.isAdjustment || r.tableId == tableId,
        )
        .firstOrNull;
  }

  Future<bool> blocksBill(String uuid) async =>
      (await _all(db)).any((r) => !r.isAdjustment || r.billUuid == uuid);

  /// Atomic, append-only discard audit in a separate draft namespace. Retains
  /// the exact original request, with no claim about whether the server applied it.
  Future<void> discardAdjustment(DineInRequest request, int? staffId) async {
    if (!request.isAdjustment) {
      throw StateError('Only adjustments may be discarded');
    }
    await db.transaction((txn) async {
      await txn.insert('dine_in_drafts', {
        'scope': '$scope::discarded-adjustment:${request.id}',
        'table_id': request.tableId,
        'payload': jsonEncode({
          'action': 'adjustment_discarded',
          'at': DateTime.now().toUtc().toIso8601String(),
          'authority': 'existing_manager_gate',
          'requesting_staff_id': staffId,
          'request': {
            'table_id': request.tableId,
            'seating_uuid': request.seatingUuid,
            'bill_uuid': request.billUuid,
            'payload': request.payload,
          },
        }),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await _remove(txn, request);
    });
  }

  @override
  Future<void> save(DineInRequest request) async {
    await db.transaction((txn) async {
      if ((await _all(
        txn,
      )).any((r) => !r.isAdjustment || r.tableId == request.tableId)) {
        throw StateError('Resolve the saved request first');
      }
      await txn.insert('dine_in_requests', {
        'scope': request.isAdjustment ? _adjustScope(request.tableId) : scope,
        'table_id': request.tableId,
        'seating_uuid': request.seatingUuid,
        'bill_uuid': request.billUuid,
        'request_id': request.id,
        'payload': request.encoded,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      // The durable send intent takes ownership atomically, even if the process
      // dies before its response. Never restore these lines as a fresh draft.
      if (!request.isAdjustment) {
        await txn.delete(
          'dine_in_drafts',
          where: 'scope = ? AND table_id = ?',
          whereArgs: [scope, request.tableId],
        );
      }
    });
  }

  @override
  Future<void> remove(DineInRequest request) => _remove(db, request);

  Future<void> _remove(DatabaseExecutor executor, DineInRequest request) async {
    final count = await executor.delete(
      'dine_in_requests',
      where: 'scope IN (?, ?) AND request_id = ? AND payload = ?',
      whereArgs: [
        scope,
        _adjustScope(request.tableId),
        request.id,
        request.encoded,
      ],
    );
    if (count != 1) throw StateError('Round journal changed');
  }
}
