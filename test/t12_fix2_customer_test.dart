import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'real_io_wait.dart';
import 't12_fix2_customer_harness.dart';

const changedEn =
    'Loyalty redemption removed because the customer changed. Redeem again if needed.';
const changedAr =
    'تمت إزالة استبدال نقاط الولاء لتغيّر العميل. أعد الاستبدال إذا لزم.';
const legacyNotice =
    'Saved loyalty discount removed because its redemption details are missing. Please redeem the reward again.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final stamps in [false, true]) {
    for (final cancel in [false, true]) {
      for (final width in [1600.0, 1920.0]) {
        final name =
            'a ${stamps ? 'stamps' : 'points'} ${cancel ? 'Cancel' : 'Back'} width=$width';
        testWidgets('T12 fix2 $name', (tester) async {
          final r = CustomerRig(tester, stamps: stamps, width: width);
          await r.start();
          await r.add();
          await r.payPage();
          await r.attach();
          await r.redeem();
          await r.exit(cancel: cancel);
          await r.payPage();
          await r.cash();
          await r.checkMoney(name);
        });
      }
    }
  }
  for (final ar in [false, true]) {
    testWidgets('T12 fix2 b explicit clear ${ar ? 'AR' : 'EN'}', (
      tester,
    ) async {
      final r = CustomerRig(tester, arabic: ar);
      await r.start();
      await r.add();
      await r.payPage();
      await r.attach();
      await r.redeem();
      await r.tap(find.byTooltip(r.l.posCustomerClearOption));
      expect(find.text(ar ? changedAr : changedEn), findsOneWidget);
      expect(r.c.loyaltyRedeemRuleId, isNull);
      expect(r.c.discountAmount, 0);
      await r.cash();
      await r.checkMoney('b clear ar=$ar', customer: null, redeem: false);
    });
    for (final card in [false, true]) {
      testWidgets(
        'T12 fix2 i guard ${card ? 'Card' : 'Cash'} ${ar ? 'AR' : 'EN'}',
        (tester) async {
          final r = CustomerRig(tester, arabic: ar);
          await r.start();
          await r.add();
          await r.payPage();
          r.c.loyaltyRedeemRuleId = 11;
          r.c.loyaltyRedeemPoints = 100;
          r.c.discount = const DiscountConfiguration(
            kind: DiscountKind.fixedAmount,
            value: 0.5,
            label: 'Loyalty redemption',
          );
          r.c.setVehiclePlateNumber(r.c.vehiclePlateNumber);
          r.c.orderNumbering = const OrderNumberingConfig(enabled: true);
          r.c.printReceipts = true;
          r.c.printKitchenTickets = true;
          await r.settle();
          final before = r.c.snapshot().items;
          final number = r.c.currentOrderNumber;
          r.cardCalls = 0;
          r.printerCalls = 0;
          if (card) {
            await r.tap(
              find.ancestor(
                of: find.text(r.l.posPaymentCard),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w.runtimeType.toString() == '_PaymentMethodActionButton',
                ),
              ),
            );
          } else {
            await r.cash();
          }
          final msg = ar
              ? 'أعد إرفاق العميل أو أزل استبدال نقاط الولاء قبل الدفع'
              : 'Attach the customer again or remove the loyalty redemption before paying';
          expect(find.text(msg), findsWidgets);
          expect(r.c.lastPaymentMessage, msg);
          expect(r.c.snapshot().items, before);
          expect(r.c.currentOrderNumber, number);
          expect(r.c.receiptNumber, isEmpty);
          expect(r.c.loyaltyRedeemRuleId, 11);
          expect(r.c.discountAmount, 0.5);
          expect(r.c.isProcessingPayment, false);
          final rows = await r.drive(
            () => r.driftDb.select(r.driftDb.orderOutbox).get(),
          );
          final history = await r.drive(() => r.localDb.query('order_history'));
          expect(rows, isEmpty);
          expect(history, isEmpty);
          expect(r.cardCalls, 0);
          expect(r.printerCalls, 0);
          expect(r.server.allocations, 0);
          // ignore: avoid_print
          print(
            'FIX2_GUARD ar=$ar card=$card outbox=${rows!.length} history=${history!.length} card=${r.cardCalls} printer=${r.printerCalls} allocation=${r.server.allocations}',
          );
        },
      );
    }
  }
  for (final mode in [
    'search',
    'same-details',
    'same-enter',
    'keyboard',
    'details',
    'plate',
  ]) {
    testWidgets('T12 fix2 c identity $mode', (tester) async {
      final r = CustomerRig(tester);
      if (mode == 'same-enter') {
        r.server.customers[5]!['phone'] = '+96890000001';
      }
      await r.start();
      await r.add();
      await r.payPage();
      await r.attach();
      await r.redeem();
      final same = mode.startsWith('same');
      Iterable<Element>? changeNotice;
      if (mode == 'search') {
        await r.attach(6);
      } else if (mode == 'plate') {
        await r.tap(find.byKey(const ValueKey('payment-plate-search')));
        for (final key in ['B', '1', '2', '3']) {
          await r.tap(
            find.descendant(of: find.byType(Dialog), matching: find.text(key)),
          );
        }
        await r.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(r.l.commonDone),
          ),
        );
        await r.chooseEarn();
      } else if (mode == 'same-details') {
        await r.tap(find.byKey(const ValueKey('payment-customer-details')));
        await r.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.widgetWithText(TextButton, r.l.commonClose),
          ),
        );
      } else {
        await r.tap(find.byKey(const ValueKey('payment-customer-number')));
        if (!same) {
          await r.tap(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byIcon(Icons.backspace_outlined),
            ),
          );
          await r.tap(
            find.descendant(of: find.byType(Dialog), matching: find.text('2')),
          );
        }
        await r.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(r.l.commonDone),
          ),
        );
        if (!same) await r.chooseEarn();
        if (mode == 'details') {
          expect(find.text(changedEn), findsOneWidget);
          changeNotice = find.text(changedEn).evaluate().toList();
          await r.closeNotice();
          await r.tap(find.byKey(const ValueKey('payment-customer-details')));
          await r.tap(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.widgetWithText(TextButton, r.l.commonClose),
            ),
          );
        }
      }
      if (mode == 'same-enter') {
        expect(r.c.selectedCustomer?.id, 5);
        expect(r.c.selectedEarnRuleIds, [11]);
        expect(find.byType(CheckboxListTile), findsNothing);
      }
      expect(
        changeNotice ?? find.text(changedEn).evaluate(),
        same ? isEmpty : hasLength(1),
      );
      await r.closeNotice();
      await r.cash();
      await r.checkMoney(
        'c $mode',
        customer: same ? 5 : 6,
        redeem: same,
        posts: mode == 'plate' ? 1 : 0,
      );
    });
  }
  for (final stamps in [false, true]) {
    for (final route in ['hold-back', 'hold-cancel', 'table', 'move']) {
      final name = 'f $route ${stamps ? 'stamps' : 'points'}';
      testWidgets('T12 fix2 $name', (tester) async {
        final r = CustomerRig(tester, stamps: stamps);
        await r.start();
        final table = route == 'table' || route == 'move';
        if (table) {
          await r.tap(find.text('Dine In').first);
          await r.tap(find.text('Table 1').first);
          await pumpUntilRealCondition(
            tester,
            () =>
                r.c.activeDiningTableId == '1' && !r.tableBusy && !r.lookupBusy,
            reason: 'table 1 open finished',
          );
        }
        await r.add();
        await r.payPage();
        await r.attach();
        await r.redeem();
        await r.exit(cancel: route.endsWith('cancel'));
        if (table) {
          await r.tap(find.text('Back To Floor').first);
          await pumpUntilRealCondition(
            tester,
            () => r.c.activeDiningTableId == null && !r.tableBusy,
            reason: 'table flush finished',
          );
          await pumpUntilRealCondition(
            tester,
            () => r.c.activeDiningTableId == null,
            reason: 'table draft saved',
          );
          if (route == 'move') {
            await r.tap(find.byTooltip(r.l.posDiningTableActionsTooltip));
            await r.tap(find.text(r.l.posDiningActionMove));
            await r.tap(find.text('Table 2 · Main'));
            await pumpUntilRealCondition(
              tester,
              () =>
                  r.c.diningSessionFor('1') == null &&
                  r.c.diningSessionFor('2')?.status ==
                      DiningTableStatus.occupied,
              reason: 'move persisted and source cleared',
            );
            await r.closeNotice();
          }
          await r.tap(find.text(route == 'move' ? 'Table 2' : 'Table 1').first);
          await pumpUntilRealCondition(
            tester,
            () =>
                r.c.activeDiningTableId == (route == 'move' ? '2' : '1') &&
                !r.tableBusy &&
                !r.lookupBusy,
            reason: 'table opened and customer refresh finished',
          );
        } else {
          await r.tap(find.text('Hold').first);
          await pumpUntilRealCondition(
            tester,
            () => r.c.heldOrders.length == 1,
            reason: 'held draft persisted',
          );
          await r.closeNotice();
          await r.tap(find.text('Held Orders').first);
          await r.tap(find.text('Continue Order').first);
          await pumpUntilRealCondition(
            tester,
            () => r.c.heldOrders.isEmpty && r.c.cart.isNotEmpty,
            reason: 'held draft restored',
          );
          await r.closeNotice();
        }
        await pumpUntilRealCondition(
          tester,
          () => !r.lookupBusy,
          reason: 'restore customer refresh finished',
        );
        expect(r.c.selectedCustomer?.id, 5);
        expect(r.c.selectedCustomer?.name, 'Customer A');
        expect(r.c.selectedCustomer?.phone, '+968 9000 0001');
        expect(r.c.selectedCustomer?.plates, ['A123']);
        expect(r.c.selectedCustomer?.loyalty.single.ruleId, 11);
        expect(r.c.selectedCustomer?.loyalty.single.points, 200);
        expect(r.c.selectedCustomer?.loyalty.single.stamps, 10);
        expect(r.c.selectedCustomer?.loyalty.single.availablePoints, 200);
        expect(r.c.selectedCustomer?.loyalty.single.availableStamps, 10);
        expect(r.c.selectedEarnRuleIds, [11]);
        await r.payPage();
        await r.cash();
        await r.checkMoney(name);
      });
    }
  }
  for (final route in [
    'hold',
    'table',
    'none-hold',
    'no-redeem-hold',
    'no-redeem-table',
  ]) {
    testWidgets('T12 fix2 f2 cross customer $route', (tester) async {
      final r = CustomerRig(tester);
      await r.start();
      final table = route.endsWith('table');
      final none = route == 'none-hold';
      final debit = !none && !route.startsWith('no-redeem');
      if (table) {
        await r.tap(find.text('Dine In').first);
        await r.tap(find.text('Table 1').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.activeDiningTableId == '1' && !r.tableBusy && !r.lookupBusy,
          reason: 'table 1 open finished',
        );
      }
      await r.add();
      await r.payPage();
      if (!none) await r.attach();
      if (debit) await r.redeem();
      await r.exit();
      if (table) {
        await r.tap(find.text('Back To Floor').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.activeDiningTableId == null && !r.tableBusy,
          reason: 'table flush finished',
        );
        await pumpUntilRealCondition(
          tester,
          () => r.c.activeDiningTableId == null && !r.tableBusy,
          reason: 'leave table finished',
        );
        await r.tap(find.byIcon(Icons.arrow_back_rounded).first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.selectedOrderType == OrderType.quickOrder && !r.tableBusy,
          reason: 'floor plan back finished',
        );
      } else {
        await r.tap(find.text('Hold').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.heldOrders.length == 1,
          reason: 'held',
        );
        await r.closeNotice();
      }
      await r.add();
      await r.payPage();
      await r.attach(6);
      await r.exit();
      if (table) {
        await r.tap(find.text('Dine In').first);
        await r.tap(find.text('Table 1').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.activeDiningTableId == '1' && !r.tableBusy && !r.lookupBusy,
          reason: 'table 1 open finished',
        );
      } else {
        await r.tap(find.text('Held Orders').first);
        await r.tap(find.text('Continue Order').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.heldOrders.isEmpty,
          reason: 'restored',
        );
        await r.closeNotice();
      }
      await r.payPage();
      await r.cash();
      await r.checkMoney('f2 $route', customer: none ? null : 5, redeem: debit);
    });
  }
  for (final reference in ['', '96890000001']) {
    for (final source in ['held', 'table-reopen', 'table-startup']) {
      final table = source != 'held';
      testWidgets(
        'T12 fix2 g orphan redemption reference=$reference source=$source',
        (tester) async {
          final r = CustomerRig(tester);
          await r.start();
          if (table) {
            await r.tap(find.text('Dine In').first);
            await r.tap(find.text('Table 1').first);
            await pumpUntilRealCondition(
              tester,
              () =>
                  r.c.activeDiningTableId == '1' &&
                  !r.tableBusy &&
                  !r.lookupBusy,
              reason: 'table 1 open finished',
            );
          }
          await r.add();
          await r.payPage();
          await r.attach();
          await r.redeem();
          await r.exit();
          if (table) {
            await r.tap(find.text('Back To Floor').first);
            await pumpUntilRealCondition(
              tester,
              () => r.c.activeDiningTableId == null && !r.tableBusy,
              reason: 'table flush finished',
            );
          } else {
            await r.tap(find.text('Hold').first);
            await pumpUntilRealCondition(
              tester,
              () => r.c.heldOrders.length == 1,
              reason: 'held',
            );
            await r.closeNotice();
          }
          await r.drive(() async {
            final name = table ? 'dining_tables' : 'held_orders';
            final rows = await r.localDb.query(name);
            final row = rows.firstWhere((v) => v['draft_json'] != null);
            final map =
                jsonDecode(row['draft_json'] as String) as Map<String, dynamic>;
            map.remove('customer');
            map.remove('earnRuleIds');
            map.remove('loyaltyRedeemCustomerId');
            map['customerReferenceNumber'] = reference;
            await r.localDb.update(name, {'draft_json': jsonEncode(map)});
            if (table) {
              await r.c.refreshDiningTables();
            } else {
              await r.c.refreshHeldOrders();
            }
          });
          if (source == 'table-startup') {
            await r.restart();
            await r.tap(find.text('Dine In').first);
          }
          if (table) {
            await r.tap(find.text('Table 1').first);
            await pumpUntilRealCondition(
              tester,
              () =>
                  r.c.activeDiningTableId == '1' &&
                  !r.tableBusy &&
                  !r.lookupBusy,
              reason: 'table 1 open finished',
            );
          } else {
            await r.tap(find.text('Held Orders').first);
            await r.tap(find.text('Continue Order').first);
            await pumpUntilRealCondition(
              tester,
              () => r.c.heldOrders.isEmpty,
              reason: 'restored',
            );
            await r.closeNotice();
          }
          expect(r.c.selectedCustomer, isNull);
          expect(r.c.loyaltyRedeemRuleId, isNull);
          expect(r.c.discountAmount, 0);
          expect(r.c.customerReferenceNumber, reference);
          await pumpUntilRealCondition(
            tester,
            () => find.text(legacyNotice).evaluate().isNotEmpty,
            reason: 'legacy notice built',
          );
          expect(find.text(legacyNotice), findsOneWidget);
          expect(
            r.server.posts,
            isEmpty,
            reason: 'restore must not resolve digits into a customer',
          );
          await r.payPage();
          await r.cash();
          await r.checkMoney(
            'g ref=$reference source=$source',
            customer: reference.isEmpty ? null : 901,
            redeem: false,
            posts: reference.isEmpty ? 0 : 1,
            earn: reference.isEmpty ? [] : [11, 12],
          );
        },
      );
    }
  }

  testWidgets('T12 fix2 h auto rule cannot retain a stale debit', (
    tester,
  ) async {
    final r = CustomerRig(tester);
    await r.start();
    await r.add();
    r.c.applyLoyaltyRedemption(
      ruleId: 11,
      points: 100,
      valueOmr: 0.5,
      label: 'Loyalty redemption',
    );
    // A stale field set left by the base's non-reuse discount writer.
    r.c.discount = const DiscountConfiguration();
    r.c.maybeAutoApplyOrderDiscount();
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(r.c.discountAmount, 0);
    await r.payPage();
    await r.cash();
    await r.checkMoney('h auto stale', customer: null, redeem: false);
  });
  for (final reset in ['clear', 'free-table']) {
    testWidgets('T12 fix2 h k reset $reset', (tester) async {
      final r = CustomerRig(tester);
      await r.start();
      await r.add();
      await r.payPage();
      await r.attach();
      await r.redeem();
      await r.exit();
      if (reset == 'clear') {
        await r.tap(find.text('Clear').first);
      } else {
        await r.tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_OrderItemCard',
            ),
            matching: find.byIcon(Icons.delete_outline_rounded),
          ),
        );
        await r.tap(find.text('Dine In').first);
        await r.tap(find.text('Table 1').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.activeDiningTableId == '1' && !r.tableBusy && !r.lookupBusy,
          reason: 'table 1 open finished',
        );
      }
      await r.tap(find.byIcon(Icons.add_rounded).last);
      await r.payPage();
      await r.cash();
      await r.checkMoney('h k $reset', customer: null, redeem: false);
    });
  }
}
