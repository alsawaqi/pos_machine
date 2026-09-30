import 'dart:convert';
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

/// Install once per table. The trigger reads an owner row, so opening another
/// connection requires no trigger replacement and no schema lock.
Future<void> ensureBusinessTable(DatabaseExecutor db, String name) async {
  if (!BusinessBoundary.initialized || BusinessBoundary.current == null) return;
  final context = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='_p0_owner'",
  );
  if (context.isEmpty) {
    await db.execute(
      'CREATE TABLE _p0_owner (id INTEGER PRIMARY KEY CHECK(id=1), identity TEXT NOT NULL)',
    );
    await db.insert('_p0_owner', {
      'id': 1,
      'identity': BusinessBoundary.current!.encoded,
    });
  } else {
    final rows = await db.query('_p0_owner', where: 'id=1');
    if (rows.isEmpty ||
        rows.single['identity'] != BusinessBoundary.current!.encoded) {
      await db.insert('_p0_owner', {
        'id': 1,
        'identity': BusinessBoundary.current!.encoded,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
  final table = _identifier(name);
  final columns = await db.rawQuery('PRAGMA table_info($table)');
  if (columns.isEmpty) return;
  if (!columns.any((column) => column['name'] == businessIdentityColumn)) {
    await db.execute(
      'ALTER TABLE $table ADD COLUMN $businessIdentityColumn TEXT',
    );
    if (BusinessBoundary.adoptingLegacy) {
      await db.update(name, {
        businessIdentityColumn: BusinessBoundary.current!.encoded,
      });
    }
  }
  final triggerName = '_p0_stamp_v2_' + name;
  final installed = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND name=?",
    [triggerName],
  );
  if (installed.isEmpty) {
    // One-time migration from the first candidate's literal-owner trigger.
    final previous = _identifier('_p0_stamp_' + name);
    final old = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name=?",
      ['_p0_stamp_' + name],
    );
    if (old.isNotEmpty) await db.execute('DROP TRIGGER $previous');
    final trigger = _identifier(triggerName);
    await db.execute(
      "CREATE TRIGGER $trigger AFTER INSERT ON $table WHEN NEW.$businessIdentityColumn IS NULL "
      "BEGIN UPDATE $table SET $businessIdentityColumn=(SELECT identity FROM _p0_owner WHERE id=1) WHERE rowid=NEW.rowid; END",
    );
  }
}

Future<void> prepareBusinessDatabase(Database db) async {
  if (!BusinessBoundary.initialized) return;
  BusinessBoundary.assertWritable();
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' AND name NOT LIKE '_p0_%'",
  );
  for (final row in tables) {
    await ensureBusinessTable(db, row['name'] as String);
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
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' AND name NOT LIKE '_p0_%'",
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

/// Read-only inventory: no migrations, trigger DDL, or second writer on a
/// heartbeat. Corrupt/unreadable storage throws so the caller reports unknown.
Future<int> pendingSqliteBusinessWork() async {
  final directory = await getDatabasesPath();
  var count = 0;
  for (final name in _businessDatabaseNames) {
    final path = '$directory/$name';
    if (!await databaseExists(path)) continue;
    Database? live;
    for (final candidate in _openBusinessDatabases) {
      if (candidate.isOpen &&
          candidate.path.replaceAll(r'\', '/') == path.replaceAll(r'\', '/'))
        live = candidate;
    }
    final db = live ?? await openReadOnlyDatabase(path, singleInstance: false);
    try {
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name']).toSet();
      if (tables.contains('local_table_events')) {
        final rows = await db.query('local_table_events');
        final discarded = <Object?>{};
        for (final row in rows) {
          final event = jsonDecode(row['event_json'] as String) as Map;
          if (event['event_type'] == 'local.table.discard')
            discarded.add((event['payload'] as Map)['discarded_event_id']);
        }
        count += rows
            .where(
              (r) =>
                  r['ack_json'] == null &&
                  !discarded.contains(r['event_id']) &&
                  (jsonDecode(r['event_json'] as String)
                          as Map)['event_type'] !=
                      'local.table.discard',
            )
            .length;
      }
      if (tables.contains('qr_checkout_attempts')) {
        final reviewed = tables.contains('qr_checkout_payment_reviews')
            ? (await db.query(
                'qr_checkout_payment_reviews',
              )).map((r) => r['attempt_id']).toSet()
            : <Object?>{};
        count += (await db.query('qr_checkout_attempts'))
            .where(
              (r) =>
                  !const {'paid', 'released'}.contains(r['state']) &&
                  !reviewed.contains(r['id']),
            )
            .length;
      }
      for (final table in [
        'dine_in_requests',
        'qr_quick_requests',
        'bill_combine_journal',
        'draft_recovery_journal',
      ]) {
        if (!tables.contains(table)) continue;
        for (final row in await db.query(table)) {
          final state = row['state'];
          if (!const {
            'done',
            'not_applied',
            'paid',
            'released',
            'managed',
          }.contains(state))
            count++;
        }
      }
    } finally {
      if (live == null) await db.close();
    }
  }
  return count;
}
