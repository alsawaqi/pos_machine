import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 't12_fix2_customer_harness.dart';
import 't12_fix3_harness.dart';
import 't12_fix6_tender_freeze_test.dart'
    show boot, t0, changedTotal, tapTender, cardEntered;
import 't12_fix4_money_workflows_test.dart' show money;
import 'real_io_wait.dart';

String changeText(Fix3Rig r) =>
    (r.tester.widget<Text>(find.byKey(const ValueKey('change-amount')))).data!;

Future<void> tapRenderedTender(Fix3Rig r, String kind) async {
  final label = kind == 'Card'
      ? r.l.posPaymentCard
      : kind == 'Bank POS'
      ? r.l.posPaymentBankPos
      : kind == 'Mixed'
      ? r.l.posPaymentSplitPayment
      : r.l.posPaymentCash;
  final target = kind == 'Mixed'
      ? find.text(label)
      : find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PaymentMethodActionButton',
          ),
        );
  expect(target.hitTestable(), findsOneWidget);
  // The normal tap helper pumps before checking reachability. Here the target
  // is already rendered: deliver the tap before a pending background rebuild.
  await r.tester.tap(target.hitTestable());
  await r.settle();
}

void refreshCatalog(Fix3Rig r) {
  r.c.applyCatalog(
    branchId: 6,
    categories: const ['Drinks'],
    products: const [CustomerRig.coffee],
    floors: const [],
    tables: const [],
    taxes: const [],
    discounts: r.c.availableDiscounts,
    loyaltyRules: r.c.loyaltyRules,
  );
}

Future<void> finish(Fix3Rig r, String kind, int total) async {
  await r.closeNotice();
  if (kind == 'Split') {
    await r.finishCash(expected: total / 2000);
    await pumpUntilRealCondition(
      r.tester,
      () => r.c.hasRecordedSplitPayments && !r.c.isProcessingPayment,
      reason: 'first real split persisted',
    );
    await r.finishCash(expected: total / 2000);
  } else if (kind == 'Cash') {
    await r.finishCash(expected: total / 1000);
  } else if (kind == 'Card') {
    await r.finishCard();
  } else if (kind == 'Mixed') {
    await r.amount('1');
    await tapTender(r, kind);
    await cardEntered(r);
  } else {
    await tapTender(r, kind);
  }
  await money(r, 'F59 $kind', total: total, discount: 2700 - total);
  expect(
    r.cardAmounts,
    kind == 'Card'
        ? [total]
        : kind == 'Mixed'
        ? [total - 1000]
        : isEmpty,
  );
  expect(await r.drive(() => r.localDb.query('order_history')), hasLength(1));
}

void displayedAmountCases(List<String> kinds, {bool control = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final kind in kinds) {
    for (final edge in ['opens', 'ends']) {
      for (final trigger in [
        'snapshot',
        'catalog',
        'sixty-seconds',
        'broadcast',
      ]) {
        testWidgets(
          'F59 $kind window $edge after $trigger refuses displayed quote',
          (tester) async {
            final r = await boot(tester);
            final oldTotal = edge == 'opens' ? 2700 : 2430;
            final newTotal = edge == 'opens' ? 2430 : 2700;
            final beforeClock = edge == 'opens'
                ? t0
                : t0.add(const Duration(hours: 2));
            r.c.clock = () => beforeClock;
            refreshCatalog(r);
            if (kind == 'Split') {
              r.c.setSplitCount(2);
            }
            await r.settle();
            // Keys are entered while the original quote is still on screen.
            await r.amount(kind == 'Mixed' ? '1' : '3');
            final oldDue = kind == 'Split' ? oldTotal ~/ 2 : oldTotal;
            final newDue = kind == 'Split' ? newTotal ~/ 2 : newTotal;
            expect(
              find.textContaining((oldDue / 1000).toStringAsFixed(3)),
              findsWidgets,
            );
            expect(
              changeText(r),
              contains(
                ((kind == 'Mixed' ? oldDue - 1000 : 3000 - oldDue) / 1000)
                    .toStringAsFixed(3),
              ),
            );
            final effects = await r.effects();
            final nextClock = edge == 'opens'
                ? t0.add(const Duration(hours: 2))
                : t0.add(const Duration(hours: 4));
            r.c.clock = () => nextClock;
            // Deliberately no frame: these are background readers, not renders.
            if (trigger == 'catalog') refreshCatalog(r);
            if (trigger == 'broadcast') {
              r.c.selectPaymentMethod(r.c.selectedPaymentMethod);
            }
            if (trigger == 'sixty-seconds') {
              expect(
                nextClock.difference(beforeClock).inSeconds,
                greaterThan(60),
              );
              expect(r.c.total, newTotal / 1000);
            } else {
              expect(r.c.snapshot().total, newTotal / 1000);
            }
            expect(
              find.textContaining((oldDue / 1000).toStringAsFixed(3)),
              findsWidgets,
            );
            await tapRenderedTender(r, kind);
            expect(r.c.lastPaymentMessage, changedTotal);
            await r.noEffects('F59 refused $kind $edge $trigger', effects);
            expect(
              find.textContaining((newDue / 1000).toStringAsFixed(3)),
              findsWidgets,
            );
            expect(
              changeText(r),
              contains(
                ((kind == 'Mixed' ? newDue - 1000 : 3000 - newDue) / 1000)
                    .toStringAsFixed(3),
              ),
            );
            await finish(r, kind, newTotal);
          },
        );
      }
    }
  }
  if (control) {
    testWidgets(
      'F59 unchanged quote survives background refresh without refusal',
      (tester) async {
        final r = await boot(tester);
        await r.amount('3');
        r.c.clock = () => t0.add(const Duration(minutes: 2));
        refreshCatalog(r);
        r.c.snapshot();
        await tapTender(r, 'Cash');
        expect(r.c.lastPaymentMessage, isNot(changedTotal));
        await money(r, 'F59 unchanged');
      },
    );
  }
}
