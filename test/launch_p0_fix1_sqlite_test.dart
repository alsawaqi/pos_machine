import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_sqlite.dart';
import 'package:pos_machine/qr_checkout/payment_review_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  const owner = BusinessIdentity(11, 21, 'device');
  setUp(() async {
    BusinessBoundary.resetForTest();
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE held_orders(id TEXT PRIMARY KEY, payload TEXT)',
    );
    await prepareBusinessDatabase(db);
  });
  tearDown(() async {
    await db.close();
    BusinessBoundary.resetForTest();
  });
  test(
    'B12g reopening a business database does not change its schema',
    () async {
      final before = await db.rawQuery('PRAGMA schema_version');
      await prepareBusinessDatabase(db);
      expect(await db.rawQuery('PRAGMA schema_version'), before);
    },
  );
  test('B12b runtime payment reviews survive a reopen and scrub', () async {
    await recordPaymentReview(
      db,
      'scope',
      'order',
      const PaymentReviewEvidence(),
      'request',
      {},
    );
    await db.insert(paymentReviewTable, {
      'attempt_id': 'attempt',
      'order_uuid': 'order',
      'scope': 'scope',
      'original_row': '{}',
      'decision': 'paid',
      'reference': 'bank-ref',
      'request_id': 'request',
      'server_result': '{}',
      'reviewed_at': '2026-09-30',
    });
    await prepareBusinessDatabase(db);
    expect(await paymentReviewDecisions(db), {'attempt': 'paid'});
    expect(BusinessBoundary.quarantinedCount, 0);
  });
  test(
    'B1 handheld table events are quarantined before identity change removes them',
    () async {
      await db.execute(
        'CREATE TABLE local_table_events(id INTEGER PRIMARY KEY, event_json TEXT)',
      );
      await prepareBusinessDatabase(db);
      await db.insert('local_table_events', {
        'id': 1,
        'event_json': jsonEncode({
          'client_event_id': 'pending-table',
          'event_type': 'table.open',
        }),
      });
      BusinessBoundary.registerWiper(() => scrubBusinessRows(db, all: true));
      await BusinessBoundary.accept(const BusinessIdentity(99, 88, 'device'));
      expect(await db.query('local_table_events'), isEmpty);
      expect(BusinessBoundary.quarantinedCount, 1);
    },
  );
}
