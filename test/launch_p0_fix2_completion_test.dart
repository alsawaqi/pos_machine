import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/device_heartbeat.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fix2_release_storage.dart';
import 'launch_p0_fix2_release_upgrade_test.dart' show ReleaseAckApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(BusinessBoundary.resetForTest);
  test(
    'F11 same-owner activation waits for durable completion; existing controller uses fresh storage',
    () async {
      await loadFix2ReleaseStorage();
      final controller = PosController();
      await controller.refreshHeldOrders();
      final gate = Completer<void>();
      final flight = DeviceHeartbeat.trackTender(() => gate.future);
      var activated = false;
      final before = BusinessBoundary.generation.value;
      final identity = BusinessBoundary.current!;
      final activation =
          BusinessBoundary.accept(
            BusinessIdentity(
              identity.companyId,
              identity.branchId,
              'identity-from-server',
            ),
          ).then((_) {
            activated = true;
          });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(activated, false);
      expect(BusinessBoundary.generation.value, before);
      gate.complete();
      await flight;
      await activation;
      await controller.refreshHeldOrders();
      expect(
        controller.heldOrders.any(
          (h) => h.orderReference == 'FIX2-RELEASE-HELD',
        ),
        true,
      );
      controller.dispose();
    },
  );
  test('F11 token clearing on 401 waits for payment persistence', () async {
    await loadFix2ReleaseStorage();
    final session = SessionService(
      const FlutterSecureStorage(),
      TenantPreferences(await SharedPreferences.getInstance()),
    );
    await session.load();
    final gate = Completer<void>();
    final flight = DeviceHeartbeat.trackTender(() => gate.future);
    var cleared = false;
    final clear = session.clearForRePair().then((_) {
      cleared = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cleared, false);
    expect(session.deviceToken, isNotNull);
    gate.complete();
    await flight;
    await clear;
    expect(session.deviceToken, isNull);
  });
  test(
    'F11 slow customer lookup cannot delay durable completion; F5 table pay survives block',
    () async {
      final dir = await loadFix2ReleaseStorage();
      final db = AppDatabase.forTesting(
        NativeDatabase(File(dir.path + '/pos_machine_cache.sqlite')),
      );
      final api = ReleaseAckApi()..offline = true;
      final sync = OrderSyncRepository(api, db);
      final snapshots =
          jsonDecode(
                File(
                  'test/fixtures/release_01d17de/snapshots.json',
                ).readAsStringSync(),
              )
              as List;
      final wire =
          jsonDecode(
                File(
                  'test/fixtures/release_01d17de/payloads.json',
                ).readAsStringSync(),
              )
              as List;
      final snapshot = OrderSnapshot.fromMap(
        Map<String, dynamic>.from(snapshots.first),
      ).copyWith(serverOrderUuid: wire.first['payload']['order']['uuid']);
      final customer = Completer<int?>();
      await sync
          .enqueue(
            snapshot,
            staffId: 7,
            lat: wire.first['payload']['order']['gps']['lat'],
            lng: wire.first['payload']['order']['gps']['lng'],
            resolveCustomer: () => customer.future,
          )
          .timeout(const Duration(seconds: 2));
      expect(await db.getOutbox(snapshot.serverOrderUuid), isNotNull);
      expect(customer.isCompleted, false);
      customer.complete(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final pay = buildOrderPayEvent(
        snapshot,
        orderUuid: snapshot.serverOrderUuid,
        lat: wire.first['payload']['order']['gps']['lat'],
        lng: wire.first['payload']['order']['gps']['lng'],
      );
      BusinessBoundary.block('company_suspended');
      await sync.enqueueEvent(
        snapshot.serverOrderUuid + ':table-payment-test',
        pay,
      );
      expect(
        (await db.getOutbox(
          snapshot.serverOrderUuid + ':table-payment-test',
        ))!.eventsJson,
        contains('order.pay'),
      );
      expect(BusinessBoundary.quarantinedCount, 0);
      await BusinessBoundary.confirmHeartbeat(
        BusinessBoundary.generation.value,
      );
      api.offline = false;
      await sync.flush();
      expect(await db.pendingOutbox(), isEmpty);
      await sync.dispose();
      await db.close();
    },
  );
}
