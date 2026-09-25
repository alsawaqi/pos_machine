import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 't12_fix3_harness.dart';
import 'real_io_wait.dart';

Future<void> delivery(Fix3Rig r) async {
  await r.exit();
  await r.tap(find.text('Delivery').first);
  await r.tap(find.text('Test Delivery').last);
  await r.payPage();
}

Future<void> completeDelivery(Fix3Rig r, {String? number}) async {
  await r.tap(find.text(r.l.posPaymentDeliveryProceed));
  await r.tap(find.text(r.l.posDeliveryProceedReference));
  await r.tap(r.dialog(find.text('1')));
  await r.tap(r.dialog(find.text(r.l.commonDone)));
  if (number != null) {
    await r.tap(find.text(r.l.posDeliveryProceedCustomer));
    await r.tap(r.dialog(find.text(r.l.posKeyboardClear)));
    for (final ch in number.split('')) {
      await r.tap(r.dialog(find.text(ch)));
    }
    await r.tap(r.dialog(find.text(r.l.commonDone)));
  }
  await r.tap(find.widgetWithText(FilledButton, r.l.posDeliveryProceedConfirm));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final kind in ['keyboard', 'plate', 'details']) {
    testWidgets('fix3 l pending $kind Delivery UI', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready(redeem: false);
      await delivery(r);
      final before = await r.effects(), identity = r.identity();
      final g = r.gate(kind);
      await r.lookup(kind);
      expect(g.hits, 1);
      await r.tap(find.text(r.l.posPaymentDeliveryProceed));
      expect(r.c.lastPaymentMessage, lookupEn);
      expect(r.identity(), identity);
      await r.noEffects('l $kind delivery', before);
      await r.released(g);
      if (kind == 'details') {
        await r.tap(r.dialog(find.widgetWithText(TextButton, r.l.commonClose)));
      } else {
        await r.chooseEarn();
      }
      await r.closeNotice();
      await completeDelivery(r);
      await r.measured(
        'l $kind delivery',
        customer: kind == 'details' ? 5 : 6,
        redeem: false,
        delivery: true,
        posts: kind == 'plate' ? 1 : 0,
        checked: 2.7,
      );
    });
    testWidgets('fix3 l pending $kind split leg two', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      await r.tap(find.text(r.l.posPaymentSplitBill));
      await r.tap(find.text(r.l.posSplitDlgGuests(2)));
      await r.tap(find.text(r.l.posSplitDlgApplySplit));
      await r.closeNotice();
      await r.cash();
      await pumpUntilRealCondition(
        tester,
        () => r.c.paidSplitCount == 1 && !r.c.isProcessingPayment,
        reason: 'split leg one recorded',
      );
      await r.closeNotice();
      final before = await r.effects(), identity = r.identity();
      final g = r.gate(kind);
      await r.lookup(kind);
      expect(g.hits, 1);
      await r.amount('1.100');
      await r.method(r.l.posPaymentCash);
      expect(r.c.lastPaymentMessage, lookupEn);
      expect(r.identity(), identity);
      await r.noEffects('l $kind split UI', before);
      expect(await r.drive<String?>(() => r.c.payAndPrint()), lookupEn);
      await r.noEffects('l $kind split direct', before);
      await r.released(g);
      if (kind == 'details') {
        await r.tap(r.dialog(find.widgetWithText(TextButton, r.l.commonClose)));
      } else {
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(r.c.lastPaymentMessage, splitEn);
      }
      expect(r.identity(), identity);
      await r.finishCash(expected: 1.1);
      await r.measured('l $kind split');
      final pay = r.server.events.firstWhere(
        (e) => e['event_type'] == 'order.pay',
      )['payload'];
      expect(
        (pay['payments'] as List).fold<int>(
          0,
          (sum, p) => sum + (p['amount_baisas'] as num).toInt(),
        ),
        2200,
      );
    });
  }
  for (final phone in ['٩٦٨٩٠٠٠٠٠٠١', '-']) {
    testWidgets('fix3 m digitless $phone delivery unchanged', (tester) async {
      final r = Fix3Rig(tester);
      r.server.customers[5]!['phone'] = phone;
      await r.ready(redeem: false);
      await delivery(r);
      expect(r.c.selectedCustomer?.id, 5);
      await completeDelivery(r);
      await r.measured(
        'm $phone delivery',
        redeem: false,
        delivery: true,
        checked: 2.7,
      );
      expect(r.notices, isEmpty);
    });
  }
  testWidgets('fix3 t gift refusal precedes pending lookup', (tester) async {
    final r = Fix3Rig(tester);
    await r.ready();
    final state = r.identity(), before = await r.effects();
    final g = r.gate('search');
    await r.keyboard('96890000002');
    await r.method(r.l.posPaymentGift);
    expect(r.c.lastPaymentMessage, giftEn);
    expect(r.identity(), state);
    await r.noEffects('gift priority UI', before);
    r.c.selectPaymentMethod('Gift');
    expect(await r.drive<String?>(() => r.c.payAndPrint()), giftEn);
    await r.noEffects('gift priority controller', before);
    await r.released(g);
    await r.chooseEarn();
  });
  testWidgets('fix3 p manual plate from B never links to restored A', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready();
    await r.exit();
    await r.tap(find.text('Hold').first);
    await pumpUntilRealCondition(
      tester,
      () => r.c.cart.isEmpty && r.c.heldOrders.length == 1,
      reason: 'A held',
    );
    await r.closeNotice();
    await r.add();
    await r.payPage();
    await r.attach(6);
    await r.tap(find.byKey(const ValueKey('payment-vehicle-plate')));
    for (final ch in 'Z999'.split('')) {
      await r.tap(r.dialog(find.text(ch)));
    }
    await r.tap(r.dialog(find.text(r.l.commonDone)));
    expect(r.c.vehiclePlateNumber, 'Z999');
    await r.exit();
    await r.tap(find.text('Held Orders').first);
    await r.tap(find.text('Continue Order').first);
    await pumpUntilRealCondition(
      tester,
      () => r.c.heldOrders.isEmpty && !r.lookupBusy,
      reason: 'A restored',
    );
    await r.closeNotice();
    expect(r.c.vehiclePlateNumber, '');
    await r.payPage();
    await r.finishCash(expected: 2.2);
    await r.measured('p manual restore');
    expect(r.server.customers[5]!['plates'], ['A123']);
    expect(r.server.customers[6]!['plates'], ['B123']);
    await r.closeNotice();
    await r.add();
    await r.payPage();
    await r.plate('Z999');
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.vehiclePlateNumber, '');
  });
  testWidgets('fix3 p free table cannot inherit B plate', (tester) async {
    final r = Fix3Rig(tester);
    await r.ready(redeem: false, customer: 6);
    r.c.setVehiclePlateNumber('B123');
    await r.exit();
    r.c.removeCartItem(r.c.cart.single);
    await r.tap(find.text('Dine In').first);
    await r.tableOpen('1');
    expect(r.c.vehiclePlateNumber, '');
    await r.add();
    await r.payPage();
    await r.keyboard('99999999');
    await r.closeNotice();
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.customerReferenceNumber, '99999999');
    await r.finishCash(expected: 2.7);
    await r.measured(
      'p free table raw',
      customer: 901,
      redeem: false,
      posts: 1,
      earn: [11, 12],
      checked: 2.7,
    );
    expect(r.server.posts.single.containsKey('plate_number'), false);
  });
  testWidgets('fix3 n current lookup survives a same-order cart edit', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready(redeem: false);
    final g = r.gate('search');
    await r.keyboard('96890000002');
    await r.exit();
    r.c.incrementCartItem(r.c.cart.single);
    r.c.decreaseCartItem(r.c.cart.single);
    await r.released(g);
    await r.chooseEarn();
    expect(r.c.selectedCustomer?.id, 6);
    await r.closeNotice();
    await r.payPage();
    await r.finishCash(expected: 2.7);
    await r.measured(
      'n same order cart edit',
      customer: 6,
      redeem: false,
      checked: 2.7,
    );
  });
}
