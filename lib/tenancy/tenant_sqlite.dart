import 'package:sqflite/sqflite.dart';
import 'business_identity.dart';

const businessIdentityColumn = '_business_identity';
final _openBusinessDatabases = <Database>{};
const _businessDatabaseNames = [
  'mithqal_orders.db',
  'pos_orders.db',
  'pos_machine_orders.db',
  'held_orders.db',
  'order_log.db',
  'dine_in_requests.db',
  'qr_checkout_attempts.db',
  'qr_quick_requests.db',
  'table_lifecycle.db',
];
String _identifier(String value) => '"' + value.replaceAll('"', '""') + '"';

/// Additive identity stamps cover every table, including combine/recovery,
/// archived drafts, history and print evidence. Existing untagged rows are never
/// silently adopted. The trigger stamps the identity that opened this handle.
Future<void> prepareBusinessDatabase(Database db) async {
  if (!BusinessBoundary.initialized) return;
  BusinessBoundary.assertWritable();
  final identity = BusinessBoundary.current!.encoded.replaceAll("'", "''");
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
  );
  for (final row in tables) {
    final name = row['name'] as String;
    final table = _identifier(name);
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((column) => column['name'] == businessIdentityColumn)) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $businessIdentityColumn TEXT',
      );
    }
    final trigger = _identifier('_p0_stamp_' + name);
    await db.execute('DROP TRIGGER IF EXISTS $trigger');
    await db.execute(
      "CREATE TRIGGER $trigger AFTER INSERT ON $table WHEN NEW.$businessIdentityColumn IS NULL BEGIN UPDATE $table SET $businessIdentityColumn = '$identity' WHERE rowid = NEW.rowid; END",
    );
  }
  await scrubBusinessRows(db);
}

/// Quarantine precedes removal, so a failed archive write leaves the original
/// intact. Readers of combine/recovery call this before testing pending work.
Future<void> scrubBusinessRows(
  DatabaseExecutor db, {
  bool all = false,
  Set<String>? onlyTables,
}) async {
  if (!BusinessBoundary.initialized) return;
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
  );
  for (final item in tables) {
    final name = item['name'] as String;
    if (onlyTables != null && !onlyTables.contains(name)) continue;
    final table = _identifier(name);
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final tagged = columns.any(
      (column) => column['name'] == businessIdentityColumn,
    );
    final where = all || !tagged
        ? ''
        : ' WHERE $businessIdentityColumn IS NULL OR $businessIdentityColumn != ?';
    final args = where.isEmpty
        ? <Object?>[]
        : [BusinessBoundary.current?.encoded ?? 'unactivated'];
    final rows = await db.rawQuery(
      'SELECT rowid AS _p0_rowid, * FROM $table$where',
      args,
    );
    for (final row in rows) {
      if (BusinessBoundary.financialStore(name) ||
          name.contains('request') ||
          name.contains('attempt')) {
        await BusinessBoundary.quarantine(
          'sqlite:$name',
          (row[businessIdentityColumn]?.toString() ?? 'unknown') +
              ':' +
              row['_p0_rowid'].toString(),
          row,
        );
      }
      await db.delete(name, where: 'rowid = ?', whereArgs: [row['_p0_rowid']]);
    }
  }
}

Future<Database> openBusinessDatabase(
  String path, {
  int? version,
  OnDatabaseCreateFn? onCreate,
  OnDatabaseVersionChangeFn? onUpgrade,
  OnDatabaseConfigureFn? onConfigure,
  OnDatabaseOpenFn? onOpen,
}) async {
  if (BusinessBoundary.initialized) BusinessBoundary.assertWritable();
  final db = await openDatabase(
    path,
    version: version,
    onCreate: onCreate,
    onUpgrade: onUpgrade,
    onConfigure: onConfigure,
    onOpen: onOpen,
  );
  await prepareBusinessDatabase(db);
  _openBusinessDatabases.add(db);
  return db;
}

/// Called only after a successful server activation. No database files belonging
/// to another application are enumerated or touched.
Future<void> wipeBusinessDatabases() async {
  for (final db in List<Database>.of(_openBusinessDatabases)) {
    if (!db.isOpen) continue;
    await scrubBusinessRows(db, all: true);
    await db.close();
  }
  _openBusinessDatabases.clear();
  final directory = await getDatabasesPath();
  for (final name in _businessDatabaseNames) {
    final path = '$directory/$name';
    if (!await databaseExists(path)) continue;
    final db = await openDatabase(path);
    try {
      await scrubBusinessRows(db, all: true);
    } finally {
      await db.close();
    }
  }
}
