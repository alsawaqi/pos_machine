import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/bill_combine/combine_local.dart';
import 'package:pos_machine/bill_combine/combine_models.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'bill_combine_test.dart' show sourceId, previewJson;

void main() {
  sqfliteFfiInit();
  late Database db;
  late Map<String, dynamic> draft;
  Future<void> save() async {
    await db.update('held_orders', {'draft_json': jsonEncode(draft)});
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE held_orders (id TEXT PRIMARY KEY, order_type TEXT, draft_json TEXT)',
    );
    await db.execute(
      'CREATE TABLE dining_tables (table_id TEXT PRIMARY KEY, draft_json TEXT)',
    );
    await db.execute('CREATE TABLE local_table_rounds (table_id TEXT)');
    await db.execute('CREATE TABLE local_line_cancellations (table_id TEXT)');
    await db.execute('CREATE TABLE order_history (snapshot_json TEXT)');
    draft = {
      'serverOrderUuid': sourceId,
      'diningTableId': '1',
      'orderType': 'dine_in',
      'splitCount': 1,
      'discount': {'value': 0},
      'items': [
        {
          'id': '7',
          'name': 'Coffee',
          'qty': 1,
          'basePrice': 1.0,
          'unitPrice': 1.0,
          'lineTotal': 1.0,
          'notes': '',
          'modifiers': [],
        },
      ],
    };
    await db.insert('held_orders', {
      'id': 'local-held',
      'order_type': 'dine_in',
      'draft_json': jsonEncode(draft),
    });
  });
  tearDown(() => db.close());
  test(
    'original parked draft proves exact frozen lines without cart conversion',
    () async {
      final rows = await db.query('held_orders');
      final local = await loadCombineLocal(db, 1);
      local.matches(CombinePreview(previewJson()));
      expect(local.uuid, sourceId);
      expect(local.rows.single['row'], rows.single);
      expect(await db.query('held_orders'), rows);
    },
  );
  test('inconsistent stored unit or aggregate price is refused', () async {
    (draft['items'] as List).first['unitPrice'] = 9;
    await save();
    await expectLater(loadCombineLocal(db, 1), throwsStateError);
  });
  test('discount without durable accounting attribution is refused', () async {
    draft['discount'] = {'value': 10};
    await save();
    await expectLater(loadCombineLocal(db, 1), throwsStateError);
  });
  test('local shared rounds cannot be imported a second time', () async {
    await db.insert('local_table_rounds', {'table_id': '1'});
    await expectLater(loadCombineLocal(db, 1), throwsStateError);
  });
  test(
    'local paid history blocks even before its sync reaches server',
    () async {
      await db.insert('order_history', {
        'snapshot_json': jsonEncode({'serverOrderUuid': sourceId}),
      });
      await expectLater(loadCombineLocal(db, 1), throwsStateError);
    },
  );
  test('two local UUIDs on one table are not guessed or discarded', () async {
    final other = {
      ...draft,
      'serverOrderUuid': '22222222-2222-4222-8222-222222222222',
    };
    await db.insert('held_orders', {
      'id': 'second',
      'order_type': 'dine_in',
      'draft_json': jsonEncode(other),
    });
    await expectLater(loadCombineLocal(db, 1), throwsStateError);
    expect(await db.query('held_orders'), hasLength(2));
  });
  test(
    'additive journal schema preserves every old row and enables storage guard',
    () async {
      final before = await db.query('held_orders');
      await CombineStore.createSchema(db);
      expect(await db.query('held_orders'), before);
      final storage = LocalOrderStorageService.forTesting(db);
      await storage.assertNoPendingCombine();
      final local = await loadCombineLocal(db, 1);
      final attempt = CombineAttempt({
        'id': '33333333-3333-4333-8333-333333333333',
        'state': 'pending',
        'local': local.json,
        'preview': previewJson(),
      });
      await CombineStore(db, 'scope').create(attempt);
      await expectLater(storage.assertNoPendingCombine(), throwsStateError);
      expect(await db.query('held_orders'), before);
    },
  );
}
