import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix2_customer_harness.dart';
import 't12_fix3_harness.dart';
import 't12_fix4_money_workflows_test.dart' show money;
import 'real_io_wait.dart';

final t0 = DateTime(2026, 9, 26, 10);
const changedTotal =
    'The discount updated the total — check the amount, then pay again';
Future<Fix3Rig> boot(WidgetTester tester) async {
  final r = Fix3Rig(tester, online: true);
  await r.boot();
  final loyalty = r.c.loyaltyRules;
  r.c.clock = () => t0;
  r.c.applyCatalog(
    branchId: 6,
    categories: const ['Drinks'],
    products: const [CustomerRig.coffee],
    floors: const [],
    tables: const [],
    taxes: const [],
    discounts: [
      MerchantDiscount(
        id: 78,
        name: 'Product window',
        scope: 'product',
        amountType: 'percent',
        percent: 10,
        autoApply: true,
        validityStart: t0.add(const Duration(hours: 1)),
        validityEnd: t0.add(const Duration(hours: 3)),
        targets: const [DiscountTarget(targetType: 'product', targetId: 10)],
      ),
    ],
  );
  r.c.loyaltyRules = loyalty;
  await r.add();
  await r.payPage();
  await r.attach(5);
  await r.closeNotice();
  expect(r.c.total, 2.7);
  return r;
}

void activate(Fix3Rig r) => r.c.clock = () => t0.add(const Duration(hours: 2));
Future<void> cardEntered(Fix3Rig r) async {
  await pumpUntilRealCondition(
    r.tester,
    () => r.c.showCharityRoundUpPrompt || r.cardHits > 0,
    reason: 'real card prompt/channel',
  );
  if (r.c.showCharityRoundUpPrompt) {
    await r.tap(find.text(r.l.posCharityKeepOriginalTotal));
  }
  await pumpUntilRealCondition(
    r.tester,
    () => r.cardHits > 0,
    reason: 'hardware boundary entered',
  );
}

Future<void> tapTender(Fix3Rig r, String kind) async {
  if (kind == 'Card') {
    await r.method(r.l.posPaymentCard);
  } else if (kind == 'Bank POS') {
    await r.method(r.l.posPaymentBankPos);
  } else if (kind == 'Mixed') {
    await r.tap(find.text(r.l.posPaymentSplitPayment));
  } else {
    await r.method(r.l.posPaymentCash);
  }
}

Map<String, dynamic> priced(Fix3Rig r) {
  final x = r.c.snapshot();
  return {
    'items': x.items,
    'raw': x.rawSubtotal,
    'discount': x.discountAmount,
    'subtotal': x.subtotal,
    'tax': x.tax,
    'total': x.total,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final kind in ['Cash', 'Card', 'Bank POS', 'Mixed', 'Split']) {
    testWidgets(
      'F57 product window before $kind tap refuses without effects T2-X4',
      (tester) async {
        final r = await boot(tester);
        if (kind == 'Split') {
          r.c.setSplitCount(2);
          await r.settle();
        }
        await r.amount(
          kind == 'Mixed'
              ? '1'
              : kind == 'Split'
              ? '1.350'
              : '2.700',
        );
        await r.closeNotice();
        final before = await r.effects();
        activate(
          r,
        ); // No pump: window opens between the rendered price and tap.
        await tapTender(r, kind);
        expect(r.c.lastPaymentMessage, changedTotal);
        expect(r.c.total, 2.43);
        expect(find.textContaining('2.430'), findsWidgets);
        await r.noEffects('F57 pre-$kind', before);
        if (kind == 'Split') {
          await r.finishCash(expected: 1.215);
          await pumpUntilRealCondition(
            tester,
            () => r.c.hasRecordedSplitPayments && !r.c.isProcessingPayment,
            reason: 'first split persisted',
          );
          await r.finishCash(expected: 1.215);
        } else if (kind == 'Cash') {
          await r.finishCash(expected: 2.43);
        } else if (kind == 'Card') {
          await r.finishCard();
        } else if (kind == 'Mixed') {
          await r.closeNotice();
          await r.amount('1');
          await tapTender(r, kind);
          await cardEntered(r);
        } else {
          await r.closeNotice();
          await tapTender(r, kind);
        }
        await money(r, 'F57 pre-$kind', total: 2430, discount: 270);
        expect(
          r.cardAmounts,
          kind == 'Card'
              ? [2430]
              : kind == 'Mixed'
              ? [1430]
              : isEmpty,
        );
      },
    );
    testWidgets('F57 $kind keeps complete priced order across await T2-C8', (
      tester,
    ) async {
      final r = await boot(tester);
      if (kind == 'Split') {
        r.c.setSplitCount(2);
        await r.settle();
        await r.finishCash(expected: 1.35);
        await pumpUntilRealCondition(
          tester,
          () => r.c.hasRecordedSplitPayments && !r.c.isProcessingPayment,
          reason: 'leg one paid',
        );
        await r.closeNotice();
      }
      final frozen = priced(r);
      HttpGate? gate;
      if (kind == 'Card' || kind == 'Mixed') {
        r.cardGate = Completer<void>();
      } else {
        r.c.orderNumbering = const OrderNumberingConfig(enabled: true);
        r.c.receiptNumber = '';
        gate = HttpGate((o) => o.path.endsWith('/next-number'));
        r.server.gates.add(gate);
      }
      await r.amount(
        kind == 'Mixed'
            ? '1'
            : kind == 'Split'
            ? '1.350'
            : '2.700',
      );
      await tapTender(r, kind);
      if (r.cardGate != null) {
        await cardEntered(r);
      } else {
        await pumpUntilRealCondition(
          tester,
          () => gate!.hits == 1,
          reason: 'real number allocation held',
        );
      }
      expect(r.c.isProcessingPayment, true);
      activate(r);
      await r.settle(2);
      expect(
        priced(r),
        frozen,
        reason: 'lines, discounts, tax and total frozen',
      );
      if (r.cardGate != null) {
        r.cardGate!.complete();
      } else {
        gate!.release.complete();
      }
      await money(r, 'F57 during-$kind');
      expect(
        r.cardAmounts,
        kind == 'Card'
            ? [2700]
            : kind == 'Mixed'
            ? [1700]
            : isEmpty,
      );
      final rows = await r.drive(() => r.localDb.query('order_history'));
      expect(rows, hasLength(1));
    });
  }
  testWidgets(
    'F57 split retains leg-one price when window opens before leg two',
    (tester) async {
      final r = await boot(tester);
      r.c.setSplitCount(2);
      await r.settle();
      final frozen = priced(r);
      await r.finishCash(expected: 1.35);
      await pumpUntilRealCondition(
        tester,
        () => r.c.hasRecordedSplitPayments && !r.c.isProcessingPayment,
        reason: 'leg one paid',
      );
      activate(r);
      await r.settle();
      expect(priced(r), frozen);
      await r.finishCash(expected: 1.35);
      await money(r, 'F57 split between legs');
    },
  );
  testWidgets('F57 cancelled prompt releases freeze for next tap', (
    tester,
  ) async {
    final r = await boot(tester);
    await r.method(r.l.posPaymentCard);
    await pumpUntilRealCondition(
      tester,
      () => r.c.showCharityRoundUpPrompt,
      reason: 'roundup prompt',
    );
    activate(r);
    r.c.cancelCharityRoundUpPrompt();
    await pumpUntilRealCondition(
      tester,
      () => !r.c.isProcessingPayment,
      reason: 'cancel finished',
    );
    expect(r.cardHits, 0);
    await r.finishCash(expected: 2.43);
    if (r.c.lastPaymentMessage == changedTotal) {
      await r.finishCash(expected: 2.43);
    }
    await money(r, 'F57 cancel/retry', total: 2430, discount: 270);
  });
}
