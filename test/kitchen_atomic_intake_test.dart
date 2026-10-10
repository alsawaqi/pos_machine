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

  test(
    'original outbox event and kitchen request commit together, survive reopen and acknowledge independently',
    () async {
      repo.kitchenIntentBuilder = build;
      final event = orderEvent(), raw = jsonEncode(event);
      await repo.enqueueEvent('sale', event);
      final rows = await repo.allRows();
      expect(rows, hasLength(1));
      expect(
        rows.single.eventsJson,
        jsonEncode([BusinessBoundary.stampEvent(event)]),
      );
      await repo.dispose();
      await db.close();
      await open();
      final pending = (await domain.pendingKitchen()).single;
      expect(pending['original_json'], raw);
      expect(
        await domain.evidence(event['client_event_id'], domainDigest(raw)),
        DomainEvidence.matching,
      );
      await domain.acknowledgeKitchen(event['client_event_id'], {
        'durable': true,
        'event_id': pending['intent']['event_id'],
      });
      expect(await domain.pendingKitchen(), isEmpty);
      expect(await repo.allRows(), hasLength(1));
    },
  );
  test(
    'intake persistence failure rolls back both intent and financial enqueue',
    () async {
      repo.kitchenIntentBuilder = build;
      await repo.enqueueEvent('first', orderEvent());
      await db.customStatement(
        "CREATE TRIGGER fail_intake BEFORE INSERT ON kitchen_domain_intake BEGIN SELECT RAISE(ABORT,'disk full'); END",
      );
      final event = orderEvent();
      await expectLater(repo.enqueueEvent('second', event), throwsA(anything));
      expect(await repo.allRows(), hasLength(1));
      expect(
        await domain.evidence(
          event['client_event_id'],
          domainDigest(jsonEncode(event)),
        ),
        DomainEvidence.absent,
      );
    },
  );
  test(
    'hold/payment and foreign branch never become executable pending intake',
    () async {
      repo.kitchenIntentBuilder = build;
      await repo.enqueueEvent('held', {
        ...orderEvent(),
        'event_type': 'order.hold',
      });
      expect(await domain.pendingKitchen(), isEmpty);
      await repo.enqueueEvent('sale', orderEvent());
      await BusinessBoundary.accept(BusinessIdentity(1, 3, 'other'));
      expect(await domain.pendingKitchen(), isEmpty);
    },
  );
}
