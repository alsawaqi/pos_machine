import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 'real_io_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final kind in ['none', 'match', 'plate', 'details']) {
    for (final boundary in ['hold', 'clear', 'table']) {
      testWidgets('fix3 n late $kind after $boundary', (tester) async {
        final r = Fix3Rig(tester);
        await r.boot();
        if (boundary == 'table') {
          await r.tap(find.text('Dine In').first);
          await r.tableOpen('1');
        }
        await r.add();
        await r.payPage();
        await r.attach();
        final g = r.gate(kind == 'details' ? 'details' : 'search');
        await r.lookup(
          kind == 'none' || kind == 'match' ? 'keyboard' : kind,
          query: kind == 'none' ? '99999999' : '96890000002',
        );
        expect(g.hits, 1);
        await r.exit();
        if (boundary == 'hold') {
          await r.tap(find.text('Hold').first);
          await pumpUntilRealCondition(
            tester,
            () => r.c.cart.isEmpty && r.c.heldOrders.length == 1,
            reason: 'hold boundary',
          );
          await r.closeNotice();
        } else if (boundary == 'clear') {
          await r.tap(find.text('Clear').first);
        } else {
          await r.floor();
          await r.quickFromFloor();
        }
        await r.add();
        await r.payPage();
        await r.attach();
        await r.redeem();
        final expected = r.identity(), noticeCount = r.notices.length;
        await r.released(g);
        expect(r.identity(), expected);
        expect(r.notices.length, noticeCount);
        expect(find.byType(CheckboxListTile), findsNothing);
        await r.finishCash(expected: 2.2);
        await r.measured('n $kind $boundary');
      });
    }
  }
  for (final next in ['clear', 'newer', 'resume']) {
    testWidgets('fix3 n action supersedes pending $next', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final g = r.gate('search', query: '96890000002');
      await r.keyboard('96890000002');
      if (next == 'clear') {
        await r.tap(find.byTooltip(r.l.posCustomerClearOption));
      } else if (next == 'newer') {
        r.server.customers[8] = {
          'id': 8,
          'name': 'Customer C',
          'phone': '+96890000008',
          'plates': [],
        };
        final newer = r.gate('search', query: '96890000008');
        await r.keyboard('96890000008');
        expect(newer.hits, 1);
        await r.released(newer);
        await r.chooseEarn();
      } else {
        await r.exit();
        await r.tap(find.text('Hold').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.heldOrders.length == 1 && r.c.cart.isEmpty,
          reason: 'hold ended lookup generation',
        );
        await r.closeNotice();
        await r.tap(find.text('Held Orders').first);
        await r.tap(find.text('Continue Order').first);
        await pumpUntilRealCondition(
          tester,
          () => r.c.heldOrders.isEmpty && r.c.cart.isNotEmpty && !r.lookupBusy,
          reason: 'resume finished',
        );
      }
      final before = r.identity();
      await r.released(g);
      expect(r.identity(), before);
      expect(
        r.c.selectedCustomer?.id,
        next == 'clear'
            ? null
            : next == 'newer'
            ? 8
            : 5,
      );
    });
  }
  for (final end in ['error', 'timeout', 'dispose']) {
    testWidgets('fix3 l lifecycle $end', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final g = r.gate('search');
      await r.keyboard('99999999');
      expect(await r.drive<String?>(() => r.c.payAndPrint()), lookupEn);
      if (end == 'dispose') {
        await r.restart();
        g.release.complete();
        await r.add();
        await r.payPage();
        await r.attach();
      } else if (end == 'error') {
        r.server.failSearch = true;
        await r.released(g);
        r.server.failSearch = false;
        await r.closeNotice();
      } else {
        await tester.pump(const Duration(seconds: 3));
        await pumpUntilRealCondition(
          tester,
          () => !r.lookupBusy,
          reason: 'lookup bound elapsed',
        );
        g.release.complete();
        await r.closeNotice();
      }
      expect(r.lookupBusy, false);
      await r.cash();
      await r.measured(
        'l lifecycle $end',
        customer: end == 'dispose' ? 5 : 901,
        redeem: false,
        posts: end == 'dispose' ? 0 : 1,
        earn: end == 'dispose' ? [11] : [11, 12],
        checked: 2.7,
      );
    });
  }
  testWidgets('fix3 q stale reward dialog owns customer id', (tester) async {
    final r = Fix3Rig(tester);
    await r.ready(redeem: false);
    await r.tap(find.text(r.l.posPaymentAddDiscount));
    await r.tap(find.text(r.l.posDiscountRedeemPointsOption));
    r.c.attachCustomer(CustomerSearchResult.fromJson(r.server.profile(6)));
    await r.tap(
      r.dialog(find.widgetWithText(FilledButton, r.l.posRedeemConfirm)),
    );
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(r.c.activePaymentBaseTotal, 2.7);
    expect(r.notices, contains(changedCustomerEn));
    await r.finishCash(expected: 2.7);
    await r.measured(
      'q stale owner',
      customer: 6,
      redeem: false,
      earn: [11, 12],
      checked: 2.7,
    );
  });
  for (final ar in [false, true]) {
    testWidgets('fix3 o split locks identity ar=$ar', (tester) async {
      final r = Fix3Rig(tester, arabic: ar);
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
      final state = r.identity();
      await r.tap(find.byTooltip(r.l.posCustomerClearOption));
      r.c.attachCustomer(CustomerSearchResult.fromJson(r.server.profile(6)));
      r.c.applyDiscount(
        const DiscountConfiguration(kind: DiscountKind.fixedAmount, value: 1),
      );
      r.c.setVehiclePlateNumber('B123');
      expect(r.identity(), state);
      expect(
        r.c.lastPaymentMessage,
        ar
            ? 'تم دفع جزء من هذه الفاتورة — لا يمكن تغيير العميل أو الخصم الآن'
            : splitEn,
      );
      await r.tap(find.byKey(const ValueKey('payment-customer-details')));
      await r.tap(r.dialog(find.widgetWithText(TextButton, r.l.commonClose)));
      expect(r.identity(), state);
      await r.cash();
      await r.measured('o split ar=$ar');
      final payments =
          (r.server.events.firstWhere(
                (e) => e['event_type'] == 'order.pay',
              )['payload']['payments']
              as List);
      expect(
        payments.fold<int>(
          0,
          (sum, p) => sum + (p['amount_baisas'] as num).toInt(),
        ),
        2200,
      );
    });
  }
}
