import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 'real_io_wait.dart';

const guardEn =
    'Attach the customer again or remove the loyalty redemption before paying';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('fix3 u M03 explicit clear digitless customer', (tester) async {
    final r = Fix3Rig(tester);
    r.server.customers[5]!['phone'] = '-';
    await r.ready();
    await r.tap(find.byTooltip(r.l.posCustomerClearOption));
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(r.c.discountAmount, 0);
  });
  testWidgets('fix3 u M05 resulting id wins over typed digits', (tester) async {
    final r = Fix3Rig(tester);
    r.server.customers[5]!['phone'] = '+96890000001';
    await r.ready();
    await r.keyboard('90000001');
    expect(r.c.selectedCustomer?.id, 5);
    expect(r.c.loyaltyRedeemRuleId, 11);
    expect(r.c.selectedEarnRuleIds, [11]);
    expect(r.notices, isEmpty);
    expect(find.byType(CheckboxListTile), findsNothing);
    await r.finishCash(expected: 2.2);
    await r.measured('u M05');
  });
  testWidgets('fix3 u M07c plate reply cannot replace attached identity', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready(redeem: false);
    r.c.setVehiclePlateNumber('A123');
    r.server.plateReplyId = 777;
    r.server.customers[777] = {
      'id': 777,
      'name': 'Reply customer',
      'phone': '777',
      'plates': [],
    };
    await r.finishCash(expected: 2.7);
    await r.measured('u M07c', redeem: false, posts: 1, checked: 2.7);
    expect(r.server.posts.single, {
      'name': 'Customer A',
      'phone': '+968 9000 0001',
      'plate_number': 'A123',
    });
  });
  testWidgets('fix3 u M09 no-customer restore removes previous identity', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.boot();
    await r.add();
    await r.tap(find.text('Hold').first);
    await pumpUntilRealCondition(
      tester,
      () => r.c.heldOrders.length == 1 && r.c.cart.isEmpty,
      reason: 'held no-customer draft',
    );
    await r.closeNotice();
    await r.add();
    await r.payPage();
    await r.attach(6);
    await r.exit();
    await r.tap(find.text('Held Orders').first);
    await r.tap(find.text('Continue Order').first);
    await pumpUntilRealCondition(
      tester,
      () => r.c.heldOrders.isEmpty,
      reason: 'no-customer restore finished',
    );
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.selectedEarnRuleIds, isNull);
    expect(r.c.customerReferenceNumber, '');
  });
  testWidgets('fix3 u M12 free table clears before adding', (tester) async {
    final r = Fix3Rig(tester);
    await r.ready();
    await r.exit();
    r.c.removeCartItem(r.c.cart.single);
    await r.tap(find.text('Dine In').first);
    await r.tableOpen('1');
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.selectedEarnRuleIds, isNull);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(r.c.loyaltyRedeemCustomerId, isNull);
    expect(r.c.discount.kind, DiscountKind.none);
  });
  for (final tender in ['Mixed', 'Delivery', 'label', 'kind']) {
    testWidgets(
      'fix3 u ${tender == 'Mixed'
          ? 'M14'
          : tender == 'Delivery'
          ? 'M15'
          : 'M19'} $tender entry guard',
      (tester) async {
        final r = Fix3Rig(tester);
        await r.boot();
        await r.add();
        if (tender == 'label' || tender == 'kind') {
          await r.payPage();
          await r.attach();
        }
        if (tender == 'Delivery') {
          await r.drive(() => r.c.selectOrderType(OrderType.delivery));
          r.c.selectedDeliveryProviderId = 1;
        }
        r.inject();
        if (tender == 'label') {
          r.c.discount = const DiscountConfiguration(
            kind: DiscountKind.fixedAmount,
            value: 0.5,
            label: 'Manual discount',
          );
        }
        if (tender == 'kind') {
          r.c.discount = const DiscountConfiguration(
            kind: DiscountKind.percentage,
            value: 0.5,
            label: 'Loyalty redemption',
          );
        }
        final before = await r.effects();
        String? result;
        bool done = false;
        if (tender == 'Mixed') {
          unawaited(
            r.c.payMixedCashAndCard(cashAmount: 1).then((v) {
              result = v;
              done = true;
            }),
          );
          await pumpUntilRealCondition(
            tester,
            () => done || r.c.isProcessingPayment,
            reason: 'mixed accepted or refused',
          );
        } else if (tender == 'Delivery') {
          result = await r.drive<String?>(
            () => r.c.completeDeliveryOrder(reference: '1'),
          );
        } else {
          result = await r.drive<String?>(() => r.c.payAndPrint());
        }
        expect(result, guardEn);
        expect(r.c.lastPaymentMessage, guardEn);
        expect(r.c.loyaltyRedeemRuleId, 11);
        await r.noEffects('u $tender', before);
      },
    );
  }
}
