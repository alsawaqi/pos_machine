import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mithqal_kitchen_core/mithqal_kitchen_core.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/kitchen/kitchen_domain_store.dart';
import 'package:pos_machine/tenancy/business_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late OrderSyncRepository repo;
  late TillKitchenDomainStore domain;
  final owner = BusinessIdentity(1, 2, 'synthetic-device');
  Future<void> open() async {
    db = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/orders.sqlite')),
    );
    repo = OrderSyncRepository(PosApiService(tokenGetter: () => null), db);
    domain = TillKitchenDomainStore(repo);
  }

  setUp(() async {
    BusinessBoundary.resetForTest();
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    directory = await Directory.systemTemp.createTemp('mithqal-k3-till-');
    await open();
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
    BusinessBoundary.resetForTest();
    if (!directory.path.startsWith(Directory.systemTemp.path))
      throw StateError('unsafe');
    await directory.delete(recursive: true);
  });
  String payload(String id) => jsonEncode({
    'client_event_id': id,
    'event_type': 'order.hold',
    'payload': {'order_uuid': 'synthetic', 'value': 1.25},
  });

  test(
    'review foreign stamped domain event cannot create a current-owner proof',
    () async {
      final id = uuid();
      final event = (jsonDecode(payload(id)) as Map).cast<String, dynamic>();
      event['identity'] = const BusinessIdentity(99, 88, 'old-device').toJson();
      final original = jsonEncode(event);
      await expectLater(domain.persist(id, original), throwsStateError);
      expect(
        await domain.evidence(id, domainDigest(original)),
        isNot(DomainEvidence.matching),
      );
    },
  );
}
