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
      final directory = await Directory.systemTemp.createTemp(
        'fix1-till-upgrade-',
      );
      final file = File(directory.path + '/release.sqlite');
      SharedPreferences.setMockInitialValues({
        'company_id': 11,
        'branch_id': 21,
        'device_uuid': 'legacy-device',
      });
      // The release format: real v29 Drift tables, no P0 column or event identity.
      var db = AppDatabase.forTesting(NativeDatabase(file));
      await db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: const Value('legacy-paid'),
          createdAt: Value(DateTime.utc(2026)),
          eventsJson: Value(
            jsonEncode([
              {
                'client_event_id': 'old-create',
                'event_type': 'order.create',
                'payload': {},
              },
              {
                'client_event_id': 'old-pay',
                'event_type': 'order.pay',
                'payload': {'amount_baisas': 1200},
              },
            ]),
          ),
        ),
      );
      await db.close();
      final raw = await SharedPreferences.getInstance();
      await BusinessBoundary.initialize(raw);
      await SessionService(
        const FlutterSecureStorage(),
        TenantPreferences(raw),
      ).load();
      db = AppDatabase.forTesting(NativeDatabase(file));
      final api = _Api();
      final sync = OrderSyncRepository(api, db);
      expect(await db.pendingOutbox(), hasLength(1));
      final before = await db.customSelect('PRAGMA schema_version').getSingle();
      await db.prepareTenancy();
      expect(
        (await db.customSelect('PRAGMA schema_version').getSingle()).data,
        before.data,
      );
      await sync.flush();
      expect(api.sent.map((e) => e['client_event_id']), [
        'old-create',
        'old-pay',
      ]);
      expect(api.sent.every((e) => owner.matches(e['identity'])), true);
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
        SharedPreferences.setMockInitialValues({
          BusinessBoundary.identityKey: owner.encoded,
          'terminal_id': 'T',
          '_p0.tag.terminal_id': owner.encoded,
        });
        await BusinessBoundary.initialize(
          await SharedPreferences.getInstance(),
        );
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final sync = OrderSyncRepository(_Api(), db);
        final c = PosController(orderStorage: FakeOrderStorage());
        addTearDown(c.dispose);
        addTearDown(() async {
          await sync.dispose();
          await db.close();
        });
        const product = Product(
          id: '7',
          name: 'Coffee',
          category: 'Drinks',
          price: 2,
        );
        c.applyCatalog(
          categories: const ['Drinks'],
          products: const [product],
          floors: const [],
          tables: const [],
        );
        c.addProduct(product);
        c.selectedPaymentMethod = method;
        c.printReceipts = false;
        c.printKitchenTickets = false;
        c.onOrderCompleted = (snapshot) async {
          await sync.enqueue(snapshot);
        };
        const channel = MethodChannel('com.example.mosambee');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          BusinessBoundary.block('device_reactivation_required');
          return '{"status":"success","responseCode":"00","rrn":"captured-bank-ref"}';
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        if (method == 'Cash') BusinessBoundary.block('company_suspended');
        await c.payAndPrint(cashTenderedAmount: method == 'Cash' ? 2 : null);
        // The production completion path reaches durable outbox or quarantine.
        expect(
          (await db.pendingOutbox()).length + BusinessBoundary.quarantinedCount,
          greaterThanOrEqualTo(1),
        );
        final raw = await SharedPreferences.getInstance();
        if (method == 'Credit Card')
          expect(
            raw.getKeys().map(raw.get).join(' '),
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
