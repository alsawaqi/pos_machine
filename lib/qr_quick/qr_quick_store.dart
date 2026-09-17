import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'qr_quick_models.dart';

abstract interface class QrQuickStore {
  Future<List<QrQuickRequest>> load();
  Future<void> save(QrQuickRequest request);
  Future<void> remove(QrQuickRequest request);
}

/// A durable request journal, NOT a sync outbox: nothing sends automatically.
/// Uses its own DB, leaving sales, dining tables and existing migrations intact.
class SqliteQrQuickStore implements QrQuickStore {
  SqliteQrQuickStore(this.database, this.scope);
  final Database database;
  final String scope;

  static Future<SqliteQrQuickStore> open(String scope) async {
    final directory = await getDatabasesPath();
    final db = await openDatabase(
      '$directory/qr_quick_requests.db',
      version: 1,
      onCreate: (db, _) => createSchema(db),
    );
    return SqliteQrQuickStore(db, scope);
  }

  static Future<void> createSchema(Database db) => db.execute('''
    CREATE TABLE qr_quick_requests (
      scope TEXT NOT NULL, order_uuid TEXT NOT NULL, request_id TEXT NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY (scope, order_uuid))
  ''');
  @override
  Future<List<QrQuickRequest>> load() async {
    final rows = await database.query(
      'qr_quick_requests',
      where: 'scope = ?',
      whereArgs: [scope],
    );
    // Corrupt storage fails closed; do not silently discard an uncertain request.
    return rows.map((row) {
      final payload = qrMap(jsonDecode(row['payload'] as String));
      if (payload['client_request_id'] != row['request_id']) {
        throw const FormatException('Request journal identity mismatch');
      }
      return QrQuickRequest(
        row['order_uuid'] as String,
        row['request_id'] as String,
        (payload['lines'] as List? ?? const [])
            .map((line) => QrQuickLine.fromJson(qrMap(line)))
            .toList(),
        change: payload.containsKey('operation')
            ? (Map<String, dynamic>.from(payload)
                ..remove('client_request_id')
                ..remove('lines'))
            : null,
      );
    }).toList();
  }

  @override
  Future<void> save(QrQuickRequest request) async {
    // Abort on conflict; another screen can never replace the original payload.
    await database.insert('qr_quick_requests', {
      'scope': scope,
      'order_uuid': request.orderUuid,
      'request_id': request.id,
      'payload': jsonEncode(request.payload),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> remove(QrQuickRequest request) async {
    await database.delete(
      'qr_quick_requests',
      where: 'scope = ? AND order_uuid = ? AND request_id = ?',
      whereArgs: [scope, request.orderUuid, request.id],
    );
  }
}
