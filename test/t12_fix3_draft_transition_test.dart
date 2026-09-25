import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 't12_fix2_customer_harness.dart';
import 'real_io_wait.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/bill_combine/combine_local.dart';
import 'package:pos_machine/bill_combine/combine_models.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/draft_recovery/recovery_local.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

// Fault injection at the explicitly required throwing leave hook. All real
// bridge/coordinator work still executes; no storage or payment component is replaced.
class ThrowAfterLeave implements DiningTableSyncHooks {
  ThrowAfterLeave(this.real);
  final DiningTableSyncHooks? real;
  @override
  void onTableOccupied(DiningTableSession s) => real?.onTableOccupied(s);
  @override
  void onTableDraftPersisted(DiningTableSession s) =>
      real?.onTableDraftPersisted(s);
  @override
  void onTableLeft(String id) {
    real?.onTableLeft(id);
    throw StateError('test leave hook failure');
  }

  @override
  void onTableTransferred(String id, DiningTableSession s) =>
      real?.onTableTransferred(id, s);
  @override
  void onTablesJoined(DiningTableSession h, DiningTableSession s) =>
      real?.onTablesJoined(h, s);
  @override
  void onTablesCleared(Set<String> ids, DiningTableSession? h) =>
      real?.onTablesCleared(ids, h);
  @override
  void onTablePaid(DiningTableSession s, OrderSnapshot p) =>
      real?.onTablePaid(s, p);
}

Future<void> saved(Fix3Rig r, String route) async {
  await r.exit();
  if (route == 'held') {
    await r.tap(find.text('Hold').first);
    await pumpUntilRealCondition(
      r.tester,
      () => r.c.heldOrders.length == 1 && r.c.cart.isEmpty,
      reason: 'hold finished',
    );
    await r.closeNotice();
  } else {
    await r.floor();
  }
}

Future<void> resume(Fix3Rig r, String route) async {
  if (route == 'held') {
    await r.tap(find.text('Held Orders').first);
    await r.tap(find.text('Continue Order').first);
    await pumpUntilRealCondition(
      r.tester,
      () => r.c.heldOrders.isEmpty && r.c.cart.isNotEmpty && !r.lookupBusy,
      reason: 'resume and profile refresh finished',
    );
    await r.closeNotice();
  } else {
    await r.tableOpen(route == 'move' ? '2' : '1');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final route in ['held', 'table', 'move', 'startup']) {
    testWidgets('fix3 p own plate restored $route', (tester) async {
      final r = Fix3Rig(tester);
      await r.boot();
      if (route != 'held') {
        await r.tap(find.text('Dine In').first);
        await r.tableOpen('1');
      }
      await r.add();
      await r.payPage();
      await r.attach();
      await r.redeem();
      r.c.setVehiclePlateNumber('A123');
      await saved(r, route);
      if (route != 'held') await r.quickFromFloor();
      await r.add();
      await r.payPage();
      await r.plate('B123');
      await r.chooseEarn();
      await r.exit();
      if (route != 'held') {
        await r.tap(find.text('Dine In').first);
        if (route == 'move') {
          await r.tap(find.byTooltip(r.l.posDiningTableActionsTooltip));
          await r.tap(find.text(r.l.posDiningActionMove));
          await r.tap(find.text('Table 2 · Main'));
          await pumpUntilRealCondition(
            tester,
            () =>
                r.c.diningSessionFor('1') == null &&
                r.c.diningSessionFor('2') != null &&
                !r.tableBusy,
            reason: 'move committed',
          );
          await r.closeNotice();
        }
        if (route == 'startup') {
          await r.restart();
          await r.tap(find.text('Dine In').first);
        }
      }
      await resume(r, route);
      expect(r.c.vehiclePlateNumber, 'A123');
      expect(r.c.selectedCustomer?.id, 5);
      await r.payPage();
      await r.finishCash(expected: 2.2);
      await r.measured('p $route', posts: 1);
      expect(r.server.posts.single['plate_number'], 'A123');
      expect((r.server.customers[5]!['plates'] as List).toSet(), {'A123'});
      expect((r.server.customers[6]!['plates'] as List).toSet(), {'B123'});
    });
  }
  for (final change in ['clear', 'replace', 'none', 'same']) {
    testWidgets('fix3 p plate customer boundary $change', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready(redeem: false);
      if (change == 'clear') {
        await r.plate('A123');
        await r.closeNotice();
      } else {
        r.c.setVehiclePlateNumber('A123');
      }
      if (change == 'clear') {
        await r.tap(find.byTooltip(r.l.posCustomerClearOption));
        await r.attach(6);
      }
      if (change == 'replace') await r.attach(6);
      if (change == 'none') {
        r.clearCustomer();
        r.c.setVehiclePlateNumber('Z999');
        await r.attach();
      }
      if (change == 'same') {
        await r.tap(find.byKey(const ValueKey('payment-customer-details')));
        await r.tap(r.dialog(find.widgetWithText(TextButton, r.l.commonClose)));
      }
      final plate = change == 'none'
          ? 'Z999'
          : change == 'same'
          ? 'A123'
          : '';
      expect(r.c.vehiclePlateNumber, plate);
      await r.finishCash(expected: 2.7);
      await r.measured(
        'p change $change',
        customer: change == 'replace' || change == 'clear' ? 6 : 5,
        redeem: false,
        posts: plate.isEmpty ? 0 : 1,
        checked: 2.7,
      );
      if (plate.isNotEmpty) {
        expect(r.server.posts.single['plate_number'], plate);
      }
    });
  }
  for (final route in ['held', 'table']) {
    for (final outcome in ['deleted', '500', 'empty', 'timeout']) {
      testWidgets('fix3 s refresh $route $outcome', (tester) async {
        final r = Fix3Rig(tester, online: true);
        await r.boot();
        if (route == 'table') {
          await r.tap(find.text('Dine In').first);
          await r.tableOpen('1');
        }
        await r.add();
        await r.payPage();
        await r.attach();
        await r.redeem();
        await saved(r, route);
        // ignore: avoid_print
        print('F43_PHASE saved');
        if (outcome == 'deleted') r.server.customers.remove(5);
        if (outcome == '500') r.server.detailsStatus = 500;
        if (outcome == 'empty') r.server.emptyDetails = true;
        final g = r.gate('details');
        if (route == 'held') {
          await r.tap(find.text('Held Orders').first);
          await r.tap(find.text('Continue Order').first);
          // ignore: avoid_print
          print('F43_PHASE continue tapped');
        } else {
          await r.tap(find.text('Table 1').first);
        }
        await pumpUntilRealCondition(
          tester,
          () => r.c.cart.isNotEmpty,
          reason: 'draft applied',
        );
        await pumpUntilRealCondition(
          tester,
          () => g.hits == 1,
          reason: 'restore profile request reached HTTP',
        );
        final before = await r.effects();
        // ignore: avoid_print
        print('F43_PHASE effects read');
        expect(await r.drive<String?>(() => r.c.payAndPrint()), lookupEn);
        await r.noEffects('s refresh held', before);
        // ignore: avoid_print
        print('F43_PHASE guard checked');
        final noticesBeforeResponse = r.notices.length;
        if (outcome == 'timeout') {
          await tester.pump(const Duration(seconds: 3));
          await pumpUntilRealCondition(
            tester,
            () => !r.lookupBusy,
            reason: 'profile timeout bounded',
          );
          g.release.complete();
        } else {
          await r.released(g);
          // ignore: avoid_print
          print('F43_PHASE response released');
        }
        final deleted = outcome == 'deleted';
        expect(r.c.selectedCustomer?.id, deleted ? null : 5);
        expect(r.c.loyaltyRedeemRuleId, deleted ? null : 11);
        if (deleted) {
          expect(r.notices, contains(deletedEn));
        } else {
          expect(r.notices.skip(noticesBeforeResponse), isEmpty);
        }
        await r.closeNotice();
        await r.payPage();
        await r.finishCash(expected: deleted ? 2.7 : 2.2);
        await r.measured(
          's $route $outcome',
          customer: deleted ? null : 5,
          redeem: !deleted,
          checked: deleted ? 2.7 : 2.2,
        );
      });
    }
  }
  for (final kind in ['leave', 'open', 'move', 'leave-ar']) {
    testWidgets('fix3 r SQLite gated $kind', (tester) async {
      final transition = kind == 'leave-ar' ? 'leave' : kind;
      final r = Fix3Rig(tester, arabic: kind == 'leave-ar');
      await r.boot();
      await r.tap(find.text(r.l.displayOrderTypeDineIn).first);
      await r.tableOpen('1');
      await r.add();
      await r.payPage();
      await r.attach();
      await r.redeem();
      await r.exit();
      if (transition != 'leave') await r.floor();
      final gate = await r.holdDb();
      // ignore: avoid_print
      print('F45_PHASE dbheld');
      bool completed = false;
      Object? error;
      await tester.runAsync(() async {
        final future = transition == 'leave'
            ? r.c.returnToDiningFloorPlan()
            : transition == 'open'
            ? r.c.openDiningTable('2')
            : r.c.transferDiningTable('1', '2');
        unawaited(
          future.then(
            (_) => completed = true,
            onError: (Object e) {
              error = e;
              completed = true;
            },
          ),
        );
      });
      final before = r.identity();
      if (kind == 'leave') {
        await tester.tap(find.text('Quick Order').first);
        await tester.pump();
        expect(r.identity(), before);
      }
      // ignore: avoid_print
      print('F45_PHASE identityread');
      r.c.addProduct(CustomerRig.coffee);
      r.c.attachCustomer(CustomerSearchResult.fromJson(r.server.profile(6)));
      r.clearCustomer();
      r.c.setCustomerReferenceNumber('2');
      r.c.setVehiclePlateNumber('B123');
      r.c.setSelectedEarnRules([12]);
      r.c.applyDiscount(
        const DiscountConfiguration(kind: DiscountKind.fixedAmount, value: 1),
      );
      r.c.clearDiscount();
      r.c.applyLoyaltyRedemption(
        ruleId: 11,
        points: 100,
        valueOmr: 1,
        label: 'Loyalty redemption',
      );
      unawaited(r.c.selectOrderType(OrderType.quickOrder));
      expect(r.identity(), before);
      expect(
        r.c.lastPaymentMessage,
        kind == 'leave-ar'
            ? 'ما زال حفظ الطاولة جارياً — انتظر قليلاً ثم حاول مرة أخرى'
            : savingEn,
      );
      expect(completed, false);
      // ignore: avoid_print
      print('F45_PHASE guardasserted');
      gate.complete();
      // ignore: avoid_print
      print('F45_PHASE dbreleased');
      await pumpUntilRealCondition(
        tester,
        () => completed,
        reason: 'gated table action finished',
      );
      expect(error, isNull);
      // ignore: avoid_print
      print('F45_PHASE transitiondone');
      if (transition == 'open') await r.floor();
      await r.tableOpen(transition == 'move' ? '2' : '1');
      expect(r.c.cart.length, 1);
      expect(r.c.cart.single.qty, 1);
      expect(r.c.selectedCustomer?.id, 5);
      await r.payPage();
      await r.finishCash(expected: 2.2);
      await r.measured('r $transition');
    });
  }
  testWidgets('fix3 p empty plate draft remains byte identical', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready();
    final map = r.c.createDraft().toMap();
    expect(map.containsKey('vehiclePlateNumber'), false);
    final old = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
    expect(jsonEncode(OrderSessionDraft.fromMap(old).toMap()), jsonEncode(map));
    r.c.setVehiclePlateNumber('A123');
    final withPlate = r.c.createDraft().toMap();
    expect(withPlate['vehiclePlateNumber'], 'A123');
    expect(
      OrderSessionDraft.fromMap(
        withPlate,
      ).copyWith(diningTableId: '2').toMap()['vehiclePlateNumber'],
      'A123',
    );
  });
  testWidgets('fix3 r throwing real leave path releases depth', (tester) async {
    final r = Fix3Rig(tester);
    await r.boot();
    await r.tap(find.text('Dine In').first);
    await r.tableOpen('1');
    await r.add();
    final real = r.c.diningTableSyncHooks;
    r.c.diningTableSyncHooks = ThrowAfterLeave(real);
    addTearDown(() => r.c.diningTableSyncHooks = real);
    final gate = await r.holdDb();
    bool done = false;
    Object? error;
    await tester.runAsync(() async {
      unawaited(
        r.c.returnToDiningFloorPlan().then(
          (_) => done = true,
          onError: (Object e) {
            error = e;
            done = true;
          },
        ),
      );
    });
    expect(r.tableBusy, true);
    gate.complete();
    await pumpUntilRealCondition(
      tester,
      () => done,
      reason: 'throwing leave completed',
    );
    expect(error, isA<StateError>());
    expect(r.tableBusy, false);
    r.c.diningTableSyncHooks = real;
    r.c.setVehiclePlateNumber('AFTER');
    expect(r.c.vehiclePlateNumber, 'AFTER');
    await r.floor();
    expect(r.c.activeDiningTableId, isNull);
  });
  testWidgets(
    'fix3 p legacy no-plate table passes real combine and recovery readers',
    (tester) async {
      final r = Fix3Rig(tester);
      await r.boot();
      await r.tap(find.text('Dine In').first);
      await r.tableOpen('1');
      await r.add();
      await r.floor();
      const uuid = '12121212-1212-4212-8212-121212121212';
      final stored = (await r.drive(
        () => r.localDb.query('dining_tables'),
      ))!.single;
      final old = Map<String, dynamic>.from(
        jsonDecode(stored['draft_json'] as String) as Map,
      )..['serverOrderUuid'] = uuid;
      expect(old.containsKey('vehiclePlateNumber'), false);
      await r.drive(
        () => r.localDb.update(
          'dining_tables',
          {'draft_json': jsonEncode(old), 'server_order_uuid': uuid},
          where: 'table_id = ?',
          whereArgs: ['1'],
        ),
      );
      await r.drive(() => r.c.refreshDiningTables());
      final local = (await r.drive(() => loadCombineLocal(r.localDb, 1)))!;
      await r.drive(
        () => CombineStore(r.localDb, 'fixture').verifyLocal(local),
      );
      final recovery = (await r.drive(
        () => loadRecoveryLocal(r.localDb, 1, outboxRow: r.outbox.rowForKey),
      ))!;
      expect(
        combineJson(r.c.diningSessionFor('1')!.draft!.toMap()),
        combineJson(old),
      );
      expect(recovery.rows, hasLength(1));
      final noPlate = r.c.diningSessionFor('1')!.draft!;
      final withPlate = OrderSessionDraft.fromMap({
        ...noPlate.toMap(),
        'vehiclePlateNumber': 'A123',
      });
      final time = DateTime.utc(2026, 9, 25);
      final hold = buildOrderHoldEvent(
        noPlate,
        orderUuid: uuid,
        now: time,
        newUuid: () => uuid,
      );
      final holdPlate = buildOrderHoldEvent(
        withPlate,
        orderUuid: uuid,
        now: time,
        newUuid: () => uuid,
      );
      expect(holdPlate, hold);
      expect(
        buildOrderTransferEvent(
          withPlate,
          orderUuid: uuid,
          targetDeviceId: 2,
          now: time,
          newUuid: () => uuid,
        ),
        buildOrderTransferEvent(
          noPlate,
          orderUuid: uuid,
          targetDeviceId: 2,
          now: time,
          newUuid: () => uuid,
        ),
      );
    },
  );
}
