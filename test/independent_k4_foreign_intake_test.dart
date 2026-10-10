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

  Json orderEvent() => {
    'client_event_id': uuid(),
    'event_type': 'order.create',
    'client_timestamp': '2026-10-09T01:00:00Z',
    'payload': {
      'order': {
        'uuid': uuid(),
        'order_type': 'quick',
        'source': 'main_pos',
        'lines': [
          {'product_id': 10, 'qty': 2},
        ],
      },
    },
  };
  Json? build(Json event) => kitchenDomainIntent(
    event: event,
    source: 'main_pos',
    settings: {
      'mode': 'active',
      'epoch': 1,
      'applied_version': 1,
      'identity': {
        'company_id': 1,
        'branch_id': 2,
        'device_id': 3,
        'assignment': 'test',
      },
    },
    products: {
      '10': {'name': 'Rice', 'category_id': 1},
    },
  );


  test('foreign original event cannot produce current-branch kitchen intake',() async {
    repo.kitchenIntentBuilder=build;
    final event=orderEvent();
    event['identity']=const BusinessIdentity(99,88,'foreign-device').toJson();
    try {await repo.enqueueEvent('foreign',event);} catch (_) {}
    final rows=await domain.pendingKitchen();
    expect(rows,isEmpty,reason:'Foreign financial stamp must not receive current-owner kitchen proof');
    expect(await domain.evidence(event['client_event_id'],domainDigest(jsonEncode(event))),isNot(DomainEvidence.matching));
  });
}
