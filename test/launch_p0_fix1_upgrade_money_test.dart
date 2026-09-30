import 'package:pos_machine/tenancy/tenant_sqlite.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'support/fix2_release_storage.dart';
import 'launch_p0_fix2_money_test.dart' show BlockedCapture;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'support/fake_order_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = BusinessIdentity(11, 21, 'legacy-device');
  setUp(() {
    BusinessBoundary.resetForTest();
    FlutterSecureStorage.setMockInitialValues({
      'device_token': 'legacy-token',
      'terminal_pin': '1234',
    });
  });
  tearDown(BusinessBoundary.resetForTest);
  test(
    'B1 main-format Drift outbox survives upgrade and sends its original events',
    () async {
      final directory = await loadFix2ReleaseStorage();
      final expected =
          jsonDecode(
                File(
                  'test/fixtures/release_01d17de/expected.json',
                ).readAsStringSync(),
              )
              as Map;
      final db = AppDatabase.forTesting(
        NativeDatabase(File(directory.path + '/pos_machine_cache.sqlite')),
      );
      final api = _Api();
      final sync = OrderSyncRepository(api, db);
      expect(await db.pendingOutbox(), hasLength(3));
      final before = await db.customSelect('PRAGMA schema_version').getSingle();
      await db.prepareTenancy();
      expect(
        (await db.customSelect('PRAGMA schema_version').getSingle()).data,
        before.data,
      );
      await sync.flush();
      expect(
        api.sent.map((e) => e['client_event_id']),
        containsAll(expected['generated_event_ids']),
      );
      expect(api.sent.every((e) => !e.containsKey('identity')), true);
      expect(await db.pendingOutbox(), isEmpty);
      expect(BusinessBoundary.quarantinedCount, 0);
      await sync.dispose();
      await db.close();
      await directory.delete(recursive: true);
    },
  );
  for (final method in ['Cash', 'Credit Card']) {
    test(
      'B2 real till completion preserves ' + method + ' after block',
      () async {
        final directory = await loadFix2ReleaseStorage();
        final db = AppDatabase.forTesting(
          NativeDatabase(File(directory.path + '/pos_machine_cache.sqlite')),
        );
        final sync = OrderSyncRepository(_Api(), db);
        final c = PosController(
          orderStorage: FakeOrderStorage(),
          paymentBridge: BlockedCapture(),
        );
        addTearDown(c.dispose);
        addTearDown(() async {
          await sync.dispose();
          await db.close();
        });
        final local = await openBusinessDatabase(
          directory.path + '/mithqal_orders.db',
        );
        final held =
            (await LocalOrderStorageService.forTesting(local).loadHeldOrders())
                .singleWhere((h) => h.orderReference == 'FIX2-RELEASE-HELD');
        final product = held.draft.items.first.product;
        addTearDown(local.close);
        c.applyCatalog(
          categories: const ['Drinks'],
          products: [product],
          floors: const [],
          tables: const [],
        );
        c.addProduct(product);
        c.selectedPaymentMethod = method;
        c.printReceipts = false;
        c.printKitchenTickets = false;
        c.onOrderCompleted = (snapshot) async {
          BusinessBoundary.block('company_suspended');
          await sync.enqueue(snapshot, cardCharge: c.lastCardCharge);
        };
        c.addListener(() {
          if (c.showCharityRoundUpPrompt) c.confirmCharityRoundUp(false);
        });
        await c.payAndPrint(cashTenderedAmount: method == 'Cash' ? 2 : null);
        // The production completion path reaches durable outbox or quarantine.
        expect(
          (await db.pendingOutbox()).length + BusinessBoundary.quarantinedCount,
          greaterThanOrEqualTo(1),
        );
        final raw = await SharedPreferences.getInstance();
        if (method == 'Credit Card')
          expect(
            (await db.pendingOutbox()).map((r) => r.eventsJson).join(' '),
            contains('captured-bank-ref'),
          );
      },
    );
  }
}

class _Api extends PosApiService {
  _Api() : super(tokenGetter: () => null);
  final sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    sent.addAll(events);
    return {
      'results': [
        for (final e in events)
          {
            'client_event_id': e['client_event_id'],
            'status': 'processed',
            'result': {},
          },
      ],
    };
  }
}
