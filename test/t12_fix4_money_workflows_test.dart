import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 't12_fix2_customer_harness.dart';
import 't12_fix3_additional_routes_test.dart' show delivery;
import 't12_fix3_draft_transition_test.dart' show saved;
import 'real_io_wait.dart';

Future<void> money(
  Fix3Rig r,
  String name, {
  int? customer = 5,
  int discount = 0,
  int total = 2700,
  bool delivery = false,
  bool redeemed = false,
}) async {
  final kind = delivery ? 'order.deliver' : 'order.pay';
  await pumpUntilRealCondition(
    r.tester,
    () =>
        r.server.events.any((e) => e['event_type'] == kind) &&
        !r.c.isProcessingPayment &&
        r.c.cart.isEmpty,
    reason: 'completed real outbox',
  );
  await r.drive(() async {
    await r.coordinator.settled;
    await r.outbox.flush();
  });
  final creates = r.server.events
      .where((e) => e['event_type'] == 'order.create')
      .toList();
  final pays = r.server.events
      .where((e) => e['event_type'] == 'order.pay')
      .toList();
  final delivers = r.server.events
      .where((e) => e['event_type'] == 'order.deliver')
      .toList();
  expect(creates, hasLength(1));
  expect(pays, hasLength(delivery ? 0 : 1));
  expect(delivers, hasLength(delivery ? 1 : 0));
  final order = creates.single['payload']['order'] as Map;
  final event = (delivery ? delivers : pays).single;
  final payload = event['payload'] as Map;
  expect(order['customer_id'], customer);
  expect(order['subtotal_baisas'], 2700);
  expect(order['discount_total_baisas'], discount);
  expect(order['grand_total_baisas'], total);
  expect(
    payload['loyalty_redeem'],
    redeemed
        ? {
            'rule_id': 11,
            'points': r.stamps ? 0 : 100,
            'stamps': r.stamps ? 5 : 0,
          }
        : null,
  );
  if (!delivery) {
    expect(
      (payload['payments'] as List).fold<int>(
        0,
        (v, p) => v + (p['amount_baisas'] as int),
      ),
      total,
    );
  }
  expect(
    r.server.acknowledgements[event['client_event_id']]!['status'],
    'processed',
  );
  expect(r.server.posts, isEmpty);
  expect(r.server.balances[5]![11], [
    redeemed && !r.stamps ? 100 : 200,
    redeemed && r.stamps ? 5 : 10,
  ]);
  expect(r.server.balances[6]![11], [400, 15]);
  expect(r.server.customers[5]?['plates'] ?? ['A123'], ['A123']);
  expect(r.server.customers[6]!['plates'], ['B123']);
  // ignore: avoid_print
  print(
    'FIX4_MONEY ${jsonEncode({'case': name, 'order': order, 'payments': pays, 'deliveries': delivers, 'checked_baisas': total, 'card_baisas': r.cardAmounts, 'posts': r.server.posts, 'ack': r.server.acknowledgements[event['client_event_id']], 'balances': r.server.balances.map((id, v) => MapEntry('$id', v.map((k, v) => MapEntry('$k', v))))})}',
  );
}

void auto(Fix3Rig r, DateTime t) {
  final rules = r.c.loyaltyRules;
  r.c.applyCatalog(
    branchId: 6,
    categories: const ['Drinks'],
    products: const [CustomerRig.coffee],
    floors: const [],
    tables: const [],
    taxes: const [],
    discounts: [
      MerchantDiscount(
        id: 77,
        name: 'Auto 10',
        scope: 'order',
        amountType: 'percent',
        percent: 10,
        autoApply: true,
        validityStart: t.add(const Duration(hours: 1)),
        validityEnd: t.add(const Duration(hours: 3)),
      ),
    ],
  );
  r.c.loyaltyRules = rules;
  r.c.clock = () => t;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final mode in [false, true]) {
    for (final query in ['96890000003', '96890000002']) {
      testWidgets('fix4 A-prime mode=$mode query=$query', (tester) async {
        final r = Fix3Rig(tester);
        r.server.canonicalMode = mode;
        await r.ready();
        await r.keyboard(query);
        if (mode || query.endsWith('2')) await r.chooseEarn();
        final expected = query.endsWith('2')
            ? 6
            : mode
            ? 7
            : null;
        expect(r.c.selectedCustomer?.id, expected);
        expect(r.c.loyaltyRedeemRuleId, isNull);
        expect(
          r.notices,
          contains(
            'Loyalty redemption removed because the customer changed. Redeem again if needed.',
          ),
        );
        await r.finishCash(expected: 2.7);
        if (expected == null) {
          await r.measured(
            'A-prime raw',
            customer: 901,
            redeem: false,
            posts: 1,
            earn: [11, 12],
            checked: 2.7,
          );
        } else {
          await money(r, 'A-prime $mode $query', customer: expected);
        }
      });
    }
  }
  for (final origin in ['keyboard', 'restore']) {
    for (final tender in ['Cash', 'Card', 'Bank POS']) {
      testWidgets('fix4 C auto after $origin before $tender', (tester) async {
        final r = Fix3Rig(tester, online: true);
        await r.boot();
        final t = DateTime(2026, 9, 26, 10);
        auto(r, t);
        await r.add();
        await r.payPage();
        await r.attach();
        if (origin == 'restore') {
          await saved(r, 'held');
        }
        final g = r.gate(origin == 'restore' ? 'details' : 'keyboard');
        if (origin == 'restore') {
          await r.tap(find.text('Held Orders').first);
          await r.tap(find.text('Continue Order').first);
          await r.payPage();
        } else {
          await r.keyboard('96890000002');
        }
        expect(g.hits, 1);
        r.c.clock = () => t.add(const Duration(hours: 2));
        r.c.maybeAutoApplyOrderDiscount();
        expect(r.c.total, 2.7);
        await r.released(g);
        if (origin == 'keyboard') await r.chooseEarn();
        await r.closeNotice();
        expect(r.c.discount.discountId, 77);
        expect(r.c.total, 2.43);
        if (tender == 'Cash') {
          await r.finishCash(expected: 2.43);
        } else if (tender == 'Card') {
          await r.finishCard();
        } else {
          await r.method(r.l.posPaymentBankPos);
        }
        await money(
          r,
          'C $origin $tender',
          customer: origin == 'keyboard' ? 6 : 5,
          discount: 270,
          total: 2430,
        );
        if (tender == 'Card') expect(r.cardAmounts, [2430]);
      });
    }
  }
  for (final tender in ['Cash', 'Card', 'Bank POS', 'Mixed']) {
    testWidgets('fix4 C auto at $tender tap refuses side effects', (
      tester,
    ) async {
      final r = Fix3Rig(tester, online: true);
      await r.boot();
      final t = DateTime(2026, 9, 26, 10);
      auto(r, t);
      await r.add();
      await r.payPage();
      await r.attach();
      await r.closeNotice();
      final before = await r.effects();
      r.c.clock = () => t.add(const Duration(hours: 2));
      if (tender == 'Cash') {
        await r.finishCash(expected: 2.7);
      } else if (tender == 'Mixed') {
        await r.amount('1');
        await r.tap(find.text(r.l.posPaymentSplitPayment));
      } else {
        await r.method(
          tender == 'Card' ? r.l.posPaymentCard : r.l.posPaymentBankPos,
        );
      }
      expect(r.c.total, 2.43);
      expect(
        r.c.lastPaymentMessage,
        'The discount updated the total — check the amount, then pay again',
      );
      await r.noEffects('C tap $tender', before);
      await r.finishCash(expected: 2.43);
      await money(r, 'C tap $tender', discount: 270, total: 2430);
    });
  }
  for (final route in ['held', 'table']) {
    for (final action in [
      'same-done',
      'details',
      'plate',
      'person-cancel',
      'type',
    ]) {
      testWidgets('fix4 D $route restore survives $action', (tester) async {
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
        r.server.customers.remove(5);
        final g = r.gate('details');
        if (route == 'held') {
          await r.tap(find.text('Held Orders').first);
          await r.tap(find.text('Continue Order').first);
        } else {
          await r.tap(find.text('Table 1').first);
        }
        await pumpUntilRealCondition(
          tester,
          () => g.hits == 1 && !r.tableBusy,
          reason: 'restored refresh pending',
        );
        await r.payPage();
        if (action == 'same-done') {
          await r.tap(find.byKey(const ValueKey('payment-customer-number')));
          await r.tap(r.dialog(find.text(r.l.commonDone)));
        } else if (action == 'details') {
          await r.tap(find.byKey(const ValueKey('payment-customer-details')));
          expect(r.c.lastPaymentMessage, lookupEn);
        } else if (action == 'plate') {
          await r.tap(find.byKey(const ValueKey('payment-vehicle-plate')));
          expect(r.c.lastPaymentMessage, lookupEn);
        } else if (action == 'type') {
          await r.drive(
            () => r.c.selectOrderType(
              route == 'table' ? OrderType.dineIn : OrderType.toGo,
            ),
          );
        } else {
          await r.tap(find.byTooltip(r.l.posCustomerSearchOption));
          await r.tap(r.dialog(find.text(r.l.commonCancel)));
        }
        expect(r.lookupBusy, true);
        await r.released(g);
        expect(r.c.selectedCustomer, isNull);
        expect(r.notices, contains(deletedEn));
        await r.finishCash(expected: 2.7);
        await money(r, 'D $route $action', customer: null);
      });
    }
  }
  for (final stamps in [false, true]) {
    for (final action in ['empty', 'reason', 'direct-editor', 'manual']) {
      testWidgets('fix4 F manual editor stamps=$stamps $action', (
        tester,
      ) async {
        final r = Fix3Rig(tester, stamps: stamps);
        await r.ready();
        final before = r.identity();
        if (action == 'direct-editor') {
          r.c.loyaltyRules = [];
        }
        await r.tap(find.text(r.l.posPaymentAddDiscount));
        if (action != 'direct-editor') {
          await r.tap(find.text(r.l.posDiscountCustomAmountOption));
        }
        expect(
          find.text(
            r.l.posDiscountDlgApply(
              stamps ? 'Stamp reward' : 'Loyalty redemption',
            ),
          ),
          findsNothing,
        );
        if (action == 'reason' || action == 'manual') {
          await tester.enterText(
            find.byKey(const ValueKey('discount-reason')),
            'Cashier request',
          );
        }
        if (action == 'manual') {
          await tester.enterText(
            find.byKey(const ValueKey('discount-custom-amount')),
            '0.300',
          );
        }
        await r.settle();
        await r.tap(
          find.text(
            r.l.posDiscountDlgApply(
              action == 'manual' ? '0.300 OMR Discount' : '',
            ),
          ),
        );
        if (action == 'manual') {
          expect(r.c.discount.label, '0.300 OMR Discount');
          expect(r.c.discount.reason, 'Cashier request');
          expect(r.c.loyaltyRedeemRuleId, isNull);
          expect(find.text(r.l.posDiscountAppliedTitle), findsOneWidget);
          expect(r.notices, isEmpty);
          await r.finishCash(expected: 2.4);
          await money(r, 'F $stamps $action', discount: 300, total: 2400);
        } else {
          expect(r.identity(), before);
          expect(r.notices, isEmpty);
          await r.finishCash(expected: 2.2);
          await money(
            r,
            'F $stamps $action',
            discount: 500,
            total: 2200,
            redeemed: true,
          );
        }
      });
    }
  }
  for (final action in ['second-call', 'keyboard', 'clear']) {
    testWidgets('fix4 E delivery freezes before SQLite $action', (
      tester,
    ) async {
      final r = Fix3Rig(tester);
      await r.ready(redeem: false);
      await delivery(r);
      await r.closeNotice();
      final gate = await r.holdDb();
      var firstDone = false;
      await tester.runAsync(() async {
        unawaited(
          r.c.completeDeliveryOrder(reference: 'FIRST').then((_) {
            firstDone = true;
          }),
        );
      });
      expect(r.c.isProcessingPayment, true);
      if (action == 'second-call') {
        await r.drive(() => r.c.completeDeliveryOrder(reference: 'SECOND'));
      } else if (action == 'keyboard') {
        final searches = r.server.requestPaths
            .where((p) => p.endsWith('/search'))
            .length;
        await r.keyboard('96890000002');
        expect(
          r.server.requestPaths.where((p) => p.endsWith('/search')).length,
          searches,
        );
      } else {
        await r.tap(find.byTooltip(r.l.posCustomerClearOption));
      }
      expect(r.c.selectedCustomer?.id, 5);
      gate.complete();
      await pumpUntilRealCondition(
        tester,
        () => firstDone,
        reason: 'first delivery complete',
      );
      await money(r, 'E $action', delivery: true);
    });
  }
}
