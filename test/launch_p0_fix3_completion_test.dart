import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_sqlite.dart';
import 'support/fake_order_storage.dart';
import 'support/fix2_release_storage.dart';
import 'launch_p0_fix2_release_upgrade_test.dart' show ReleaseAckApi;

class _FailingHistory extends FakeOrderStorage {
  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async =>
      throw StateError('local history write failed');
}

/// Indoors: no fresh fix, but the platform still knows the last position.
class _IndoorGps extends GeolocatorPlatform {
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Future.error(TimeoutException('no fresh fix indoors'));
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => Position(
    latitude: 23.5922386,
    longitude: 58.3773037,
    timestamp: DateTime.now(),
    accuracy: 30,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

/// The real release T3 stores, the release held bill's product, and a real
/// outbox over the release cache database (offline).
Future<({Product product, AppDatabase db, OrderSyncRepository sync})>
_releaseTill() async {
  final dir = await loadFix2ReleaseStorage();
  final local = await openBusinessDatabase(dir.path + '/mithqal_orders.db');
  final storage = LocalOrderStorageService.forTesting(local);
  final held = (await storage.loadHeldOrders()).singleWhere(
    (h) => h.orderReference == 'FIX2-RELEASE-HELD',
  );
  await local.close();
  final db = AppDatabase.forTesting(
    NativeDatabase(File(dir.path + '/pos_machine_cache.sqlite')),
  );
  final sync = OrderSyncRepository(ReleaseAckApi()..offline = true, db);
  addTearDown(() async {
    await sync.dispose();
    await db.close();
    BusinessBoundary.resetForTest();
  });
  return (product: held.draft.items.first.product, db: db, sync: sync);
}

PosController _cashTill(Product product, OrderStorageService storage) {
  final c = PosController(orderStorage: storage);
  c.applyCatalog(
    categories: [product.category],
    products: [product],
    floors: [],
    tables: [],
  );
  c.addProduct(product);
  c.selectedPaymentMethod = 'Cash';
  c.printReceipts = false;
  c.printKitchenTickets = false;
  c.addListener(() {
    if (c.showCharityRoundUpPrompt) c.confirmCharityRoundUp(false);
  });
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'D3 a local history failure never stops the paid sale reaching the outbox',
    () async {
      final till = await _releaseTill();
      final before = (await till.db.pendingOutbox()).length;
      final c = _cashTill(till.product, _FailingHistory());
      c.onOrderCompleted = (snapshot) =>
          till.sync.enqueue(snapshot, staffId: 7, lat: 23.59, lng: 58.37);

      final result = await c.payAndPrint(
        cashTenderedAmount: till.product.price,
      );

      expect(result, isNotEmpty);
      expect((await till.db.pendingOutbox()).length, before + 1);
      expect(BusinessBoundary.quarantinedCount, 0);
      expect(c.cart, isEmpty);
      expect(c.isProcessingPayment, false);
    },
  );

  test(
    'D3 an outbox failure keeps the paid sale as evidence, tells the cashier and frees the till',
    () async {
      final till = await _releaseTill();
      final c = _cashTill(till.product, FakeOrderStorage());
      c.onOrderCompleted = (_) async => throw StateError('outbox write failed');

      final result = await c.payAndPrint(
        cashTenderedAmount: till.product.price,
      );

      expect(result, contains('manager review'));
      expect(BusinessBoundary.quarantinedCount, 1);
      expect(c.cart, isEmpty);
      expect(c.isProcessingPayment, false);
      c.addProduct(till.product);
      expect(c.cart, isNotEmpty);
    },
  );

  test(
    'D5 the post-sale GPS step falls back to the last known position (release parity)',
    () async {
      final till = await _releaseTill();
      final previous = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = _IndoorGps();
      addTearDown(() => GeolocatorPlatform.instance = previous);
      final c = _cashTill(till.product, FakeOrderStorage());
      String? uuid;
      c.onOrderCompleted = (snapshot) async {
        uuid = snapshot.serverOrderUuid;
        await till.sync.enqueue(snapshot, staffId: 7, enrichGps: true);
      };

      await c.payAndPrint(cashTenderedAmount: till.product.price);

      Map<String, dynamic>? gps;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (gps == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final row = (await till.db.pendingOutbox()).singleWhere(
          (r) => r.orderUuid == uuid,
        );
        final events = (jsonDecode(row.eventsJson) as List).cast<Map>();
        final create = events.firstWhere(
          (e) => e['event_type'] == 'order.create',
        );
        final wire = ((create['payload'] as Map)['order'] as Map)['gps'];
        gps = wire is Map ? wire.cast<String, dynamic>() : null;
      }
      expect(gps, {'lat': 23.5922386, 'lng': 58.3773037});
    },
  );
}
