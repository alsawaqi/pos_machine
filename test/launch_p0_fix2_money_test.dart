import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_sqlite.dart';
import 'support/fix2_release_storage.dart';
import 'launch_p0_fix2_release_upgrade_test.dart' show ReleaseAckApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final method in ['Cash', 'Credit Card']) {
    test(
      'F5 real release held bill ' +
          method +
          ' finishes into outbox during suspension and next sale works',
      () async {
        final dir = await loadFix2ReleaseStorage();
        final local = await openBusinessDatabase(
          dir.path + '/mithqal_orders.db',
        );
        final storage = LocalOrderStorageService.forTesting(local);
        await storage.refreshRecoveryGuard();
        final held = (await storage.loadHeldOrders()).singleWhere(
          (h) => h.orderReference == 'FIX2-RELEASE-HELD',
        );
        final product = held.draft.items.first.product;
        final db = AppDatabase.forTesting(
          NativeDatabase(File(dir.path + '/pos_machine_cache.sqlite')),
        );
        final api = ReleaseAckApi()..offline = true;
        final sync = OrderSyncRepository(api, db);
        final before = (await db.pendingOutbox()).length;
        final c = PosController(
          orderStorage: storage,
          paymentBridge: BlockedCapture(),
        );
        c.applyCatalog(
          categories: [product.category],
          products: [product],
          floors: [],
          tables: [],
        );
        c.addProduct(product);
        c.selectedPaymentMethod = method;
        c.printReceipts = false;
        c.printKitchenTickets = false;
        c.onOrderCompleted = (snapshot) async {
          BusinessBoundary.observeError(503, 'company_suspended');
          await sync.enqueue(
            snapshot,
            staffId: 7,
            lat: 23.5,
            lng: 58.5,
            cardCharge: c.lastCardCharge,
          );
        };
        addTearDown(() async {
          c.dispose();
          await sync.dispose();
          await db.close();
          await local.close();
          BusinessBoundary.resetForTest();
        });
        c.addListener(() {
          if (c.showCharityRoundUpPrompt) c.confirmCharityRoundUp(false);
        });
        final result = await c.payAndPrint(
          cashTenderedAmount: method == 'Cash' ? product.price : null,
        );
        print('payment completion: ' + result.toString());
        expect((await db.pendingOutbox()).length, before + 1);
        expect(BusinessBoundary.quarantinedCount, 0);
        expect(c.isProcessingPayment, false);
        expect(c.cart, isEmpty);
        if (method == 'Credit Card')
          expect(
            (await db.pendingOutbox()).map((r) => r.eventsJson).join(),
            contains('fix2-captured-bank-ref'),
          );
        await BusinessBoundary.confirmHeartbeat(
          BusinessBoundary.generation.value,
        );
        api.offline = false;
        await sync.flush();
        expect(await db.pendingOutbox(), isEmpty);
        c.addProduct(product);
        expect(c.cart, isNotEmpty);
        expect(c.isProcessingPayment, false);
      },
    );
  }
  test(
    'F5 release QR pay builder persists captured card evidence through a 503',
    () async {
      final dir = await loadFix2ReleaseStorage();
      final db = AppDatabase.forTesting(
        NativeDatabase(File(dir.path + '/pos_machine_cache.sqlite')),
      );
      final api = ReleaseAckApi()..offline = true;
      final sync = OrderSyncRepository(api, db);
      final wire = jsonDecode(
        File('test/fixtures/release_01d17de/card-pay.json').readAsStringSync(),
      );
      final pay = wire['payload'];
      final before = (await db.pendingOutbox()).length;
      addTearDown(() async {
        await sync.dispose();
        await db.close();
        BusinessBoundary.resetForTest();
      });
      BusinessBoundary.observeError(503, 'company_suspended');
      final result = await sync.enqueueStandaloneQrPay(
        orderUuid: pay['order_uuid'],
        frozenAmountBaisas: pay['payments'][0]['amount_baisas'],
        method: 'card',
        cardCharge: CardCharge(
          softposReference: 'fix2-qr-bank-ref',
          bankResponse: {'rrn': 'fix2-qr-bank-ref'},
        ),
      );
      expect(result.state, StandaloneQrPayState.pending);
      expect((await db.pendingOutbox()).length, before + 1);
      expect(
        (await db.pendingOutbox()).map((r) => r.eventsJson).join(),
        contains('fix2-qr-bank-ref'),
      );
      expect(BusinessBoundary.quarantinedCount, 0);
    },
  );
  test(
    'F11 real release local storage retries a failed open after unblock',
    () async {
      await loadFix2ReleaseStorage();
      final storage = LocalOrderStorageService.instance;
      BusinessBoundary.block('company_suspended');
      await expectLater(storage.database, throwsStateError);
      await BusinessBoundary.confirmHeartbeat(
        BusinessBoundary.generation.value,
      );
      expect(
        (await storage.loadHeldOrders()).any(
          (h) => h.orderReference == 'FIX2-RELEASE-HELD',
        ),
        true,
      );
      await (await storage.database).close();
      BusinessBoundary.resetForTest();
    },
  );
}

class BlockedCapture extends MosambeePaymentService {
  @override
  Future<MosambeePaymentResult> payWithPreparedSession(double amountOmr) async {
    BusinessBoundary.observeError(503, 'company_suspended');
    return MosambeePaymentResult.fromRaw(
      '{"status":"success","responseCode":"00","rrn":"fix2-captured-bank-ref"}',
    );
  }
}
