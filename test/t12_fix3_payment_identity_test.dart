import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 'real_io_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final kind in ['keyboard', 'plate', 'details']) {
    for (final tender in [
      'Cash',
      'Card',
      'Bank POS',
      'Mixed',
      'Gift',
      'Redeem',
      'direct-cash',
      'direct-mixed',
      'direct-delivery',
    ]) {
      testWidgets('fix3 l pending $kind $tender', (tester) async {
        final r = Fix3Rig(tester);
        await r.ready(redeem: tender != 'Gift');
        r.c.orderNumbering = const OrderNumberingConfig(enabled: true);
        r.c.printReceipts = true;
        r.c.printKitchenTickets = true;
        final before = await r.effects(), identity = r.identity();
        final g = r.gate(kind);
        await r.lookup(kind);
        expect(g.hits, 1);
        String? result;
        if (tender == 'direct-cash') {
          result = await r.drive<String?>(() => r.c.payAndPrint());
        } else if (tender == 'direct-mixed') {
          result = await r.drive<String?>(
            () => r.c.payMixedCashAndCard(cashAmount: 1),
          );
        } else if (tender == 'direct-delivery') {
          result = await r.drive<String?>(
            () => r.c.completeDeliveryOrder(reference: '1'),
          );
        } else if (tender == 'Redeem') {
          r.c.applyDiscount(
            const DiscountConfiguration(
              kind: DiscountKind.fixedAmount,
              value: 1,
            ),
          );
          r.c.clearDiscount();
          r.c.applyLoyaltyRedemption(
            ruleId: 11,
            points: 100,
            valueOmr: 0.5,
            label: 'Loyalty redemption',
          );
          await r.tap(find.text(r.l.posPaymentAddDiscount));
        } else if (tender == 'Mixed') {
          await r.amount('1');
          await r.tap(find.text(r.l.posPaymentSplitPayment));
        } else {
          if (tender == 'Cash') await r.amount('2.200');
          await r.method(
            tender == 'Cash'
                ? r.l.posPaymentCash
                : tender == 'Card'
                ? r.l.posPaymentCard
                : tender == 'Gift'
                ? r.l.posPaymentGift
                : r.l.posPaymentBankPos,
          );
        }
        expect(r.c.lastPaymentMessage, lookupEn);
        if (tender.startsWith('direct')) expect(result, lookupEn);
        expect(r.identity(), identity);
        await r.noEffects('$kind $tender', before);
        await r.released(g);
        if (kind == 'details') {
          await r.tap(
            r.dialog(find.widgetWithText(TextButton, r.l.commonClose)),
          );
        } else {
          await r.chooseEarn();
        }
        await r.closeNotice();
        r.c.printReceipts = false;
        r.c.printKitchenTickets = false;
        final kept = kind == 'details';
        await r.finishCash(expected: kept && tender != 'Gift' ? 2.2 : 2.7);
        await r.measured(
          'l $kind $tender',
          customer: kept ? 5 : 6,
          redeem: kept && tender != 'Gift',
          posts: kind == 'plate' ? 1 : 0,
          checked: kept && tender != 'Gift' ? 2.2 : 2.7,
        );
      });
    }
  }
  for (final phone in ['٩٦٨٩٠٠٠٠٠٠١', '-']) {
    for (final method in ['cash', 'card', 'enter', 'clear']) {
      testWidgets('fix3 m digitless $phone $method', (tester) async {
        final r = Fix3Rig(tester);
        r.server.customers[5]!['phone'] = phone;
        await r.ready();
        if (method == 'enter') {
          await r.tap(find.byKey(const ValueKey('payment-customer-number')));
          await r.tap(r.dialog(find.text(r.l.commonDone)));
          expect(r.c.selectedCustomer?.id, 5);
          expect(r.c.loyaltyRedeemRuleId, 11);
          expect(r.notices, isEmpty);
          await r.finishCash(expected: 2.2);
        } else if (method == 'clear') {
          await r.tap(find.byTooltip(r.l.posCustomerClearOption));
          expect(r.c.selectedCustomer, isNull);
          expect(r.c.loyaltyRedeemRuleId, isNull);
          await r.finishCash(expected: 2.7);
        } else if (method == 'card') {
          await r.finishCard();
        } else {
          await r.finishCash(expected: 2.2);
        }
        await r.measured(
          'm $phone $method',
          customer: method == 'clear' ? null : 5,
          redeem: method != 'clear',
          checked: method == 'clear' ? 2.7 : 2.2,
        );
        if (method == 'card') expect(r.cardAmounts, [2200]);
      });
    }
  }
  testWidgets('fix3 C8 faithful spaced-phone keyboard no match', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready();
    await r.keyboard('96890000003');
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(find.text(r.l.posCustomerNotFoundTitle), findsOneWidget);
    await r.finishCash(expected: 2.7);
    await r.measured(
      'C8 no match',
      customer: 901,
      redeem: false,
      posts: 1,
      earn: [11, 12],
      checked: 2.7,
    );
  });
  testWidgets('fix3 m contrast keypad deletes normal customer', (tester) async {
    final r = Fix3Rig(tester);
    await r.ready();
    await r.keyboard('');
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(
      r.notices,
      contains(
        'Loyalty redemption removed because the customer changed. Redeem again if needed.',
      ),
    );
    await r.finishCash(expected: 2.7);
    await r.measured('m contrast', customer: null, redeem: false, checked: 2.7);
  });
  for (final window in ['card', 'roundup', 'printer']) {
    testWidgets('fix3 o identity immutable during $window', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      r.c.setVehiclePlateNumber('A123');
      final state = r.identity();
      if (window == 'printer') {
        r.c.printReceipts = true;
        r.printGate = Completer<void>();
        await r.finishCash(expected: 2.2);
        await pumpUntilRealCondition(
          tester,
          () => r.printHits > 0,
          reason: 'printer in flight',
        );
      } else {
        r.cardGate = Completer<void>();
        await r.method(r.l.posPaymentCard);
        await pumpUntilRealCondition(
          tester,
          () => r.c.showCharityRoundUpPrompt,
          reason: 'roundup awaiting response',
        );
        if (window == 'card') {
          await r.tap(find.text(r.l.posCharityKeepOriginalTotal));
          await pumpUntilRealCondition(
            tester,
            () => r.cardHits > 0,
            reason: 'card charge in flight',
          );
        }
      }
      final n = r.notices.length;
      r.c.attachCustomer(CustomerSearchResult.fromJson(r.server.profile(6)));
      r.c.setCustomerReferenceNumber('2');
      r.clearCustomer();
      r.c.setVehiclePlateNumber('B123');
      r.c.setSelectedEarnRules([12]);
      r.c.applyLoyaltyRedemption(
        ruleId: 11,
        points: 100,
        valueOmr: 1,
        label: 'Loyalty redemption',
      );
      r.c.applyDiscount(
        const DiscountConfiguration(kind: DiscountKind.fixedAmount, value: 1),
      );
      r.c.clearDiscount();
      expect(r.identity(), state);
      expect(r.notices.length, n);
      if (window == 'roundup') {
        await r.tap(find.text(r.l.posCharityKeepOriginalTotal));
      }
      if (r.cardGate != null) r.cardGate!.complete();
      if (r.printGate != null) r.printGate!.complete();
      await r.measured('o $window', posts: 1);
      if (window != 'printer') expect(r.cardAmounts, [2200]);
      expect(r.c.selectedCustomer, isNull);
    });
  }
  for (final direct in [false, true]) {
    testWidgets('fix3 t gift refusal direct=$direct', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final before = await r.effects(), state = r.identity();
      if (direct) {
        r.c.selectPaymentMethod('Gift');
        expect(await r.drive<String?>(() => r.c.payAndPrint()), giftEn);
      } else {
        await r.method(r.l.posPaymentGift);
        expect(find.text(giftEn), findsWidgets);
      }
      expect(r.identity(), state);
      await r.noEffects('gift $direct', before);
    });
  }
  testWidgets('fix3 q stale redemption invalidates cached price before tender', (
    tester,
  ) async {
    final r = Fix3Rig(tester);
    await r.ready();
    await r.exit();
    expect(r.c.activePaymentBaseTotal, 2.2);
    // The old draft has a cached discounted price, but no attached identity.
    r.c.selectedCustomer = null;
    r.c.customerReferenceNumber = '';
    expect(r.c.activePaymentBaseTotal, 2.2);
    await r.payPage();
    expect(r.c.activePaymentBaseTotal, 2.7);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(
      r.notices,
      contains(
        'Saved loyalty discount removed because its redemption details are missing. Please redeem the reward again.',
      ),
    );
    final before = await r.effects();
    await r.finishCash(expected: 2.2);
    await r.noEffects('q low cash', before);
    expect(find.text(r.l.posPayTenderedTooLowTitle), findsWidgets);
  });
}
