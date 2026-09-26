import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 't12_fix3_harness.dart';
import 't12_fix3_draft_transition_test.dart' show saved;
import 't12_fix4_money_workflows_test.dart' show money;
import 'real_io_wait.dart';

Future<void> doneUnchanged(Fix3Rig r) async {
  final field = find.byKey(const ValueKey('payment-customer-number'));
  await r.tester.tapAt(r.tester.getTopLeft(field) + const Offset(20, 20));
  await r.settle();
  await r.tap(r.dialog(find.text(r.l.commonDone)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final route in ['held', 'table']) {
    for (final action in ['done', 'same', 'none', 'clear', 'different']) {
      testWidgets('F58 T1-X02 $route $action preserves attached restore', (
        tester,
      ) async {
        final r = Fix3Rig(tester, online: true);
        if (action != 'same') r.server.customers[5]!['phone'] = 'N/A';
        await r.boot();
        if (route == 'table') {
          await r.tap(find.text('Dine In').first);
          await r.tableOpen('1');
        }
        await r.add();
        await r.payPage();
        await r.attach(5);
        await r.redeem();
        await r.closeNotice();
        await saved(r, route);
        r.server.customers.remove(5);
        final gate = r.gate('details');
        if (route == 'held') {
          await r.tap(find.text('Held Orders').first);
          await r.tap(find.text('Continue Order').first);
        } else {
          await r.tap(find.text('Table 1').first);
        }
        await pumpUntilRealCondition(
          tester,
          () => gate.hits == 1 && !r.tableBusy && r.c.cart.isNotEmpty,
          reason: 'real restored customer check parked',
        );
        await r.payPage();
        if (action == 'done' || action == 'same') {
          await doneUnchanged(r);
        }
        if (action == 'clear') {
          await r.tap(find.byTooltip(r.l.posCustomerClearOption));
        }
        if (action == 'different') {
          await r.keyboard('96890000002');
          await r.chooseEarn();
        }
        if (action == 'done' || action == 'same' || action == 'none') {
          expect(r.lookupBusy, true, reason: 'attached restore survives Done');
          final before = await r.effects();
          await r.finishCash(expected: 2.2);
          expect(r.c.lastPaymentMessage, lookupEn);
          await r.noEffects('F58 pending', before);
        }
        gate.release.complete();
        await pumpUntilRealCondition(
          tester,
          () => gate.delivered == 1 && !r.lookupBusy,
          reason: 'refresh delivered',
        );
        expect(r.c.selectedCustomer?.id, action == 'different' ? 6 : null);
        expect(r.c.loyaltyRedeemRuleId, isNull);
        if (action == 'done' || action == 'same' || action == 'none') {
          expect(r.notices, contains(deletedEn));
        }
        await r.finishCash(expected: 2.7);
        await money(
          r,
          'F58 $route $action',
          customer: action == 'different' ? 6 : null,
        );
        final creates = r.server.events.where(
          (e) => e['event_type'] == 'order.create',
        );
        for (final event in creates) {
          expect(
            r.server.acknowledgements[event['client_event_id']]!['status'],
            'processed',
          );
        }
      });
    }
  }
  testWidgets('F58 T1-X01 same Done keeps attached Details deletion', (
    tester,
  ) async {
    final r = Fix3Rig(tester, online: true);
    await r.ready();
    await r.closeNotice();
    r.server.customers.remove(5);
    final gate = r.gate('details');
    await r.tap(find.byKey(const ValueKey('payment-customer-details')));
    await pumpUntilRealCondition(
      tester,
      () => gate.hits == 1,
      reason: 'Details parked',
    );
    await doneUnchanged(r);
    expect(r.lookupBusy, true, reason: 'same customer Details survives Done');
    final before = await r.effects();
    await r.finishCash(expected: 2.2);
    expect(r.c.lastPaymentMessage, lookupEn);
    await r.noEffects('F58 Details pending', before);
    await r.released(gate);
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(r.notices, contains(deletedEn));
    expect(find.byType(Dialog), findsNothing);
    await r.finishCash(expected: 2.7);
    await money(r, 'F58 Details', customer: null);
  });
}
