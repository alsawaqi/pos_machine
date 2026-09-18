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

/// One unresolved intent per device scope. No outbox sending or local table writes.
class SqliteDineInStore implements DineInStore, DineInDraftStore {
  SqliteDineInStore(this.db, this.scope);
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

  @override
  Future<DineInRequest?> load() async {
    final rows = await db.query(
      'dine_in_requests',
      where: 'scope = ?',
      whereArgs: [scope],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
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

  @override
  Future<void> save(DineInRequest request) async {
    await db.transaction((txn) async {
      await txn.insert('dine_in_requests', {
        'scope': scope,
        'table_id': request.tableId,
        'seating_uuid': request.seatingUuid,
        'bill_uuid': request.billUuid,
        'request_id': request.id,
        'payload': request.encoded,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      // The durable send intent takes ownership atomically, even if the process
      // dies before its response. Never restore these lines as a fresh draft.
      await txn.delete(
        'dine_in_drafts',
        where: 'scope = ? AND table_id = ?',
        whereArgs: [scope, request.tableId],
      );
    });
  }

  @override
  Future<void> remove(DineInRequest request) async {
    final count = await db.delete(
      'dine_in_requests',
      where: 'scope = ? AND request_id = ? AND payload = ?',
      whereArgs: [scope, request.id, request.encoded],
    );
    if (count != 1) throw StateError('Round journal changed');
  }
}
