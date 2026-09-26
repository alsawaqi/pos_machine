import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 't12_fix3_additional_routes_test.dart' show delivery, completeDelivery;
import 't12_fix3_draft_transition_test.dart' show saved, resume;
import 't12_fix4_money_workflows_test.dart' show money;
import 'real_io_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('fix4 G move gate refuses target open and preserves the bill', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.boot();
    await r.tap(find.text('Dine In').first);
    await r.tableOpen('1');
    await r.add();
    await r.payPage();
    await r.attach();
    await r.redeem();
    await r.exit();
    await r.floor();
    final gate = await r.holdDb();
    await r.tap(find.byTooltip(r.l.posDiningTableActionsTooltip));
    await r.tap(find.text(r.l.posDiningActionMove));
    await r.tap(find.text('Table 2 · Main'));
    expect(r.tableBusy, true);
    await r.closeNotice();
    await r.tap(find.text('Table 2').first);
    expect(r.c.lastPaymentMessage, savingEn);
    gate.complete();
    await pumpUntilRealCondition(
      tester,
      () =>
          !r.tableBusy &&
          r.c.diningSessionFor('1') == null &&
          r.c.diningSessionFor('2') != null,
      reason: 'move completed',
    );
    await r.closeNotice();
    await r.tableOpen('2');
    expect(r.c.cart, hasLength(1));
    expect(r.c.selectedCustomer?.id, 5);
    expect(r.c.loyaltyRedeemRuleId, 11);
    await r.payPage();
    await r.finishCash(expected: 2.2);
    await money(r, 'G move', discount: 500, total: 2200, redeemed: true);
  });
  for (final action in ['chip-other', 'chip-same', 'reuse-table']) {
    testWidgets('fix4 B real same-order UI $action preserves pending lookup', (
      tester,
    ) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final g = r.gate('keyboard');
      await r.keyboard('96890000002');
      final generation = r.c.orderGeneration;
      await r.exit();
      if (action == 'reuse-table') {
        await r.tap(find.text('Dine In').first);
        await r.tap(find.text('Table 1').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.activeDiningTableId == '1' && !r.tableBusy,
          reason: 'cart reused while lookup pending',
        );
      } else {
        await r.tap(
          find.text(action == 'chip-other' ? 'To Go' : 'Quick Order').first,
        );
      }
      expect(r.lookupBusy, true);
      expect(r.c.orderGeneration, generation);
      await r.released(g);
      await r.chooseEarn();
      expect(r.c.selectedCustomer?.id, 6);
      await r.payPage();
      await r.finishCash(expected: 2.7);
      await money(r, 'B $action', customer: 6);
    });
  }
  testWidgets(
    'fix4 A same Done supersedes older keyboard response without another search',
    (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final before = r.identity();
      final g = r.gate('keyboard');
      await r.keyboard('96890000002');
      final count = r.server.requestPaths
          .where((p) => p.endsWith('/search'))
          .length;
      await r.keyboard('96890000001');
      expect(r.identity(), before);
      expect(r.lookupBusy, false);
      expect(
        r.server.requestPaths.where((p) => p.endsWith('/search')).length,
        count,
      );
      await r.released(g);
      expect(r.identity(), before);
      expect(r.notices, isEmpty);
      expect(find.byType(CheckboxListTile), findsNothing);
      await r.finishCash(expected: 2.2);
      await money(
        r,
        'A superseded',
        discount: 500,
        total: 2200,
        redeemed: true,
      );
    },
  );
  testWidgets('fix4 H M05 different digits resulting duplicate id wins', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    r.server.customers[90] = {
      'id': 90,
      'name': 'Other identity',
      'phone': '90000001',
      'plates': <String>[],
    };
    await r.ready();
    await r.keyboard('90000001');
    await r.chooseEarn();
    expect(r.c.selectedCustomer?.id, 90);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(
      r.notices,
      contains(
        'Loyalty redemption removed because the customer changed. Redeem again if needed.',
      ),
    );
    await r.finishCash(expected: 2.7);
    await money(r, 'H M05 different id', customer: 90);
  });
  for (final canonical in [false, true]) {
    testWidgets(
      'fix4 A no redemption second order attaches the original customer mode=$canonical',
      (tester) async {
        final r = Fix3Rig(tester);
        r.server.canonicalMode = canonical;
        await r.ready(redeem: false);
        await r.keyboard('96890000001');
        expect(r.c.selectedCustomer?.id, 5);
        await r.finishCash(expected: 2.7);
        await money(r, 'A first plain');
        await r.closeNotice();
        await r.add();
        await r.payPage();
        await r.attach();
        expect(r.c.selectedCustomer?.id, 5);
        expect(r.server.customers.length, 3);
        expect(r.server.posts, isEmpty);
        await r.keyboard('96890000001');
        await r.finishCash(expected: 2.7);
        await pumpUntilRealCondition(
          tester,
          () => r.c.cart.isEmpty && !r.c.isProcessingPayment,
          reason: 'second cash complete',
        );
        await r.drive(() => r.outbox.flush());
        expect(
          r.server.events
              .where((e) => e['event_type'] == 'order.create')
              .map((e) => e['payload']['order']['customer_id'])
              .toList(),
          [5, 5],
        );
        expect(
          r.server.events.where((e) => e['event_type'] == 'order.pay'),
          hasLength(2),
        );
        expect(r.server.posts, isEmpty);
      },
    );
  }
  for (final status in [404, 500]) {
    testWidgets('fix4 D unstructured Details $status retains the customer', (
      tester,
    ) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final before = r.identity();
      r.server.detailsStatus = status;
      await r.tap(find.byKey(const ValueKey('payment-customer-details')));
      expect(r.identity(), before);
      expect(r.notices, isEmpty);
      await r.tap(r.dialog(find.widgetWithText(TextButton, r.l.commonClose)));
      await r.finishCash(expected: 2.2);
      await money(
        r,
        'D generic $status',
        discount: 500,
        total: 2200,
        redeemed: true,
      );
    });
  }
  testWidgets(
    'fix4 D successful restore followed by deleted Details detaches',
    (tester) async {
      final r = Fix3Rig(tester, online: true);
      await r.ready();
      await saved(r, 'held');
      await resume(r, 'held');
      await r.payPage();
      r.server.customers.remove(5);
      await r.tap(find.byKey(const ValueKey('payment-customer-details')));
      expect(r.c.selectedCustomer, isNull);
      expect(r.notices, contains(deletedEn));
      expect(find.byType(Dialog), findsNothing);
      await r.finishCash(expected: 2.7);
      await money(r, 'D restore then delete', customer: null);
    },
  );
  testWidgets('fix4 E double real delivery confirmation records one delivery', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready(redeem: false);
    await delivery(r);
    await r.closeNotice();
    final gate = await r.holdDb();
    await completeDelivery(r);
    expect(r.c.isProcessingPayment, true);
    // The first confirmation closes its dialog; a second real Proceed cannot reopen it.
    await r.tap(find.text(r.l.posPaymentDeliveryProceed));
    expect(
      find.widgetWithText(FilledButton, r.l.posDeliveryProceedConfirm),
      findsNothing,
    );
    gate.complete();
    await money(r, 'E double UI', delivery: true);
  });
  for (final mode in ['mixed', 'delivery', 'label']) {
    testWidgets('fix4 H UI inconsistent redemption $mode has zero effects', (
      tester,
    ) async {
      final r = Fix3Rig(tester);
      await r.ready(redeem: false);
      if (mode == 'delivery') await delivery(r);
      await r.closeNotice();
      if (mode == 'mixed') {
        await r.tap(find.byTooltip(r.l.posCustomerClearOption));
      }
      r.c.loyaltyRedeemRuleId = 11;
      r.c.loyaltyRedeemPoints = mode == 'label' ? 0 : 100;
      r.c.loyaltyRedeemStamps = mode == 'label' ? 5 : 0;
      r.c.loyaltyRedeemCustomerId = mode == 'label'
          ? 5
          : mode == 'delivery'
          ? 6
          : null;
      r.c.discount = const DiscountConfiguration(
        kind: DiscountKind.fixedAmount,
        value: 0.5,
        label: 'Loyalty redemption',
      );
      expect(r.c.loyaltyRedeemRuleId, 11);
      final before = await r.effects();
      if (mode == 'mixed') {
        await r.amount('1');
        await r.tap(find.text(r.l.posPaymentSplitPayment));
      } else if (mode == 'delivery') {
        await completeDelivery(r);
      } else {
        await r.cash();
      }
      expect(
        r.c.lastPaymentMessage,
        'Attach the customer again or remove the loyalty redemption before paying',
      );
      expect(find.text(r.c.lastPaymentMessage), findsWidgets);
      expect(r.c.loyaltyRedeemRuleId, 11);
      await r.noEffects('H $mode', before);
    });
  }
  testWidgets(
    'fix4 H plate keypad done updates the wire from the visible value',
    (tester) async {
      final r = Fix3Rig(tester);
      await r.ready(redeem: false);
      await r.tap(find.byKey(const ValueKey('payment-vehicle-plate')));
      await r.tap(r.dialog(find.text(r.l.posKeyboardClear)));
      for (final ch in ['A', '7', '7', '7']) {
        await r.tap(r.dialog(find.text(ch)));
      }
      await r.tap(r.dialog(find.text(r.l.commonDone)));
      expect(r.c.vehiclePlateNumber, 'A777');
      // Only the external HTTP reply is adversarial; the real completed-order
      // callback must keep the identity already chosen on the screen.
      r.server.plateReplyId = 777;
      r.server.customers[777] = {
        'id': 777,
        'name': 'Reply customer',
        'phone': '777',
        'plates': [],
      };
      await r.finishCash(expected: 2.7);
      await r.measured('H plate A777', redeem: false, posts: 1, checked: 2.7);
      expect(r.server.posts.single['plate_number'], 'A777');
    },
  );
  for (final operation in ['floor', 'open']) {
    testWidgets(
      'fix4 B refused combine $operation keeps customer lookup generation',
      (tester) async {
        final r = Fix3Rig(tester);
        await r.boot();
        await r.tap(find.text('Dine In').first);
        await r.tableOpen('1');
        await r.add();
        await r.payPage();
        await r.attach();
        await r.redeem();
        await r.closeNotice();
        await r.drive(
          () => r.localDb.insert('bill_combine_journal', {
            'id': 'fixture-combine',
            'scope': 'fixture-other-scope',
            'state': 'pending',
            'payload': '{}',
          }),
        );
        final g = r.gate('keyboard');
        await r.keyboard('96890000002');
        final gen = r.c.orderGeneration;
        await r.drive(
          () => operation == 'floor'
              ? r.c.returnToDiningFloorPlan()
              : r.c.openDiningTable('2'),
        );
        expect(
          r.c.lastPaymentMessage,
          'Finish the pending bill combine in Dine-In first.',
        );
        expect(r.c.orderGeneration, gen);
        expect(r.lookupBusy, true);
        await r.drive(
          () => r.localDb.update('bill_combine_journal', {
            'state': 'not_applied',
          }),
        );
        await r.released(g);
        await r.chooseEarn();
        expect(r.c.selectedCustomer?.id, 6);
        await r.finishCash(expected: 2.7);
        await money(r, 'B refused $operation', customer: 6);
      },
    );
  }
  testWidgets(
    'fix4 E refused preflight releases delivery flag then lookup and retry succeed',
    (tester) async {
      final r = Fix3Rig(tester);
      await r.ready(redeem: false);
      await delivery(r);
      await r.closeNotice();
      await r.drive(
        () => r.localDb.insert('bill_combine_journal', {
          'id': 'fixture-combine',
          'scope': 'fixture-other-scope',
          'state': 'pending',
          'payload': '{}',
        }),
      );
      final before = await r.effects();
      final result = await r.drive(
        () => r.c.completeDeliveryOrder(reference: 'REFUSED'),
      );
      expect(result, 'Finish the pending bill combine in Dine-In first.');
      expect(r.c.isProcessingPayment, false);
      expect(r.c.customerTenderStarted, false);
      await r.noEffects('E combine refusal', before);
      await r.drive(
        () =>
            r.localDb.update('bill_combine_journal', {'state': 'not_applied'}),
      );
      await r.keyboard('96890000002');
      await r.chooseEarn();
      expect(r.c.selectedCustomer?.id, 6);
      await r.closeNotice();
      await completeDelivery(r);
      await money(r, 'E combine retry', customer: 6, delivery: true);
    },
  );
}
