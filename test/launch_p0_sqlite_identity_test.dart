import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/tenancy/business_identity.dart';
import '../lib/tenancy/tenant_sqlite.dart';
import '../lib/bill_combine/combine_store.dart';
import '../lib/draft_recovery/recovery_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  const owner = BusinessIdentity(1, 2, 'device');
  setUp(() async {
    BusinessBoundary.resetForTest();
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await openDatabase(inMemoryDatabasePath);
    await CombineStore.createSchema(db);
    await RecoveryStore.createSchema(db);
    await db.execute(
      'CREATE TABLE held_orders (uuid TEXT PRIMARY KEY, payload TEXT)',
    );
    await prepareBusinessDatabase(db);
  });
  tearDown(() async {
    await db.close();
    BusinessBoundary.resetForTest();
  });
  test(
    'W2 SQLite stamps every record and foreign financial journals cannot block work',
    () async {
      await db.insert('held_orders', {'uuid': 'mine', 'payload': 'customer'});
      expect(
        (await db.query('held_orders')).single[businessIdentityColumn],
        owner.encoded,
      );
      for (final table in ['bill_combine_journal', 'draft_recovery_journal']) {
        final values = <String, Object?>{
          'id': table,
          'scope': 'old-scope',
          'state': 'pending',
          'payload': '{}',
          businessIdentityColumn: const BusinessIdentity(
            9,
            8,
            'other-device',
          ).encoded,
        };
        await db.insert(table, values);
      }
      await CombineStore.assertNonePending(db);
      await RecoveryStore.assertNonePending(db);
      expect(BusinessBoundary.quarantinedCount, 2);
      expect(await db.query('bill_combine_journal'), isEmpty);
      expect(await db.query('draft_recovery_journal'), isEmpty);
      expect(await db.query('held_orders'), hasLength(1));
    },
  );
  test(
    'W2 successful new activation wipes held history and quarantines pending money',
    () async {
      await db.insert('held_orders', {'uuid': 'mine', 'payload': 'customer'});
      await db.insert('bill_combine_journal', {
        'id': 'pending',
        'scope': 'scope',
        'state': 'pending',
        'payload': '{}',
      });
      Future<void> wipe() => scrubBusinessRows(db, all: true);
      BusinessBoundary.registerWiper(wipe);
      await BusinessBoundary.accept(const BusinessIdentity(1, 99, 'device'));
      expect(await db.query('held_orders'), isEmpty);
      expect(await db.query('bill_combine_journal'), isEmpty);
      expect(BusinessBoundary.quarantinedCount, 1);
    },
  );
}
