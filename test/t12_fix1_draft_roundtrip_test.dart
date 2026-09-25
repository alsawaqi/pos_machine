import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 't12_table_loyalty_screen_test.dart' show realLocalDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final stamps in [false, true]) {
    test(
      'P2 real SQLite draft maps carry ${stamps ? 'stamps' : 'points'} including copyWith',
      () async {
        databaseFactory = databaseFactoryFfi;
        final directory = await Directory.systemTemp.createTemp('p2-draft-');
        await databaseFactory.setDatabasesPath(directory.path);
        final db = await realLocalDatabase();
        final storage = LocalOrderStorageService.forTesting(db);
        await storage.refreshRecoveryGuard();
        final c = PosController(orderStorage: storage);
        final watch = Stopwatch()..start();
        while (c.isLoadingStorage &&
            watch.elapsed < const Duration(seconds: 20)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(c.isLoadingStorage, false);
        addTearDown(() async {
          c.dispose();
          await db.close();
        });
        c.printReceipts = false;
        c.printKitchenTickets = false;
        const item = Product(
          id: '10',
          name: 'Coffee',
          category: 'Drinks',
          price: 2,
        );
        c.applyCatalog(
          categories: const ['Drinks'],
          products: const [item],
          floors: const [],
          tables: const [],
          taxes: const [],
        );
        c.addProduct(item);
        c.attachCustomer(
          const CustomerSearchResult(
            id: 5,
            name: 'Loyal Customer',
            phone: '+968 9000 0001',
          ),
        );
        c.applyLoyaltyRedemption(
          ruleId: 11,
          valueOmr: 0.5,
          label: stamps ? 'Stamp reward' : 'Loyalty redemption',
          points: stamps ? 0 : 100,
          stamps: stamps ? 5 : 0,
        );
        final outgoing = c.prepareTransferDraft()!;
        final map = outgoing.toMap();
        expect(map['loyaltyRedeemRuleId'], 11);
        expect(
          map[stamps ? 'loyaltyRedeemStamps' : 'loyaltyRedeemPoints'],
          stamps ? 5 : 100,
        );
        final copied = OrderSessionDraft.fromMap(
          map,
        ).copyWith(note: 'copy tested');
        expect(copied.toMap()['loyaltyRedeemRuleId'], 11);
        expect(
          copied.toMap()[stamps
              ? 'loyaltyRedeemStamps'
              : 'loyaltyRedeemPoints'],
          stamps ? 5 : 100,
        );
        await storage.saveHeldOrder(copied);
        await c.refreshHeldOrders();
        c.clearForNextOrder();
        await c.resumeHeldOrder(c.heldOrders.single);
        final payload = buildOrderSyncPayload(c.snapshot(), customerId: 5);
        expect((payload.events[1]['payload'] as Map)['loyalty_redeem'], {
          'rule_id': 11,
          'points': stamps ? 0 : 100,
          'stamps': stamps ? 5 : 0,
        });
        expect(c.discountAmount, 0.5);
        expect(c.selectedCustomer?.id, 5);
        expect(c.selectedCustomer?.phone, '+968 9000 0001');
        // Receiving uses the existing server item-only contract, which does not
        // carry trustworthy redemption metadata: clear BOTH discount and debit.
        expect(
          c.receiveTransferredOrder(
            orderUuid: 'received',
            orderType: OrderType.quickOrder,
            items: copied.items,
          ),
          true,
        );
        expect(c.discountAmount, 0);
        expect(c.loyaltyRedeemRuleId, isNull);
        expect(c.loyaltyRedeemPoints, 0);
        expect(c.loyaltyRedeemStamps, 0);
        expect(
          (buildOrderSyncPayload(c.snapshot()).events[1]['payload'] as Map)
              .containsKey('loyalty_redeem'),
          false,
        );
      },
    );
  }

  test(
    'P2 draft without an attached customer removes debit with notice',
    () async {
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp(
        'p2-no-customer-',
      );
      await databaseFactory.setDatabasesPath(directory.path);
      final db = await realLocalDatabase();
      final storage = LocalOrderStorageService.forTesting(db);
      await storage.refreshRecoveryGuard();
      final c = PosController(orderStorage: storage);
      final watch = Stopwatch()..start();
      while (c.isLoadingStorage &&
          watch.elapsed < const Duration(seconds: 20)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.isLoadingStorage, false);
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      c.printReceipts = false;
      c.printKitchenTickets = false;
      const item = Product(
        id: '10',
        name: 'Coffee',
        category: 'Drinks',
        price: 2,
      );
      c.applyCatalog(
        categories: const ['Drinks'],
        products: const [item],
        floors: const [],
        tables: const [],
        taxes: const [],
      );
      c.addProduct(item);
      c.applyLoyaltyRedemption(
        ruleId: 11,
        points: 100,
        valueOmr: 0.5,
        label: 'Loyalty redemption',
      );
      final draft = OrderSessionDraft.fromMap(c.createDraft().toMap());
      await storage.saveHeldOrder(draft);
      await c.refreshHeldOrders();
      c.clearForNextOrder();
      String? notice;
      c.onDraftRedemptionCleared = (message) => notice = message;
      await c.resumeHeldOrder(c.heldOrders.single);
      expect(c.selectedCustomer, isNull);
      expect(c.loyaltyRedeemRuleId, isNull);
      expect(c.loyaltyRedeemPoints, 0);
      expect(c.discountAmount, 0);
      expect(
        notice,
        'Saved loyalty discount removed because its redemption details are missing. Please redeem the reward again.',
      );
    },
  );
  test(
    'P2 legacy map has no invented debit and manual discounts stay manual',
    () {
      final draft = OrderSessionDraft.fromMap({
        'orderType': 'quick_order',
        'items': <dynamic>[],
        'splitCount': 1,
        'discount': const DiscountConfiguration(
          kind: DiscountKind.fixedAmount,
          value: 0.5,
          label: 'Manual',
        ).toMap(),
      });
      expect(draft.toMap().containsKey('loyaltyRedeemRuleId'), false);
      expect(draft.discount.value, 0.5);
      expect(draft.discount.label, 'Manual');
    },
  );
}
