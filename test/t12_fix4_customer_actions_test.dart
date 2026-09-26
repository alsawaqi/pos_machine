import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/models/pos_models.dart';
import 't12_fix3_harness.dart';
import 'real_io_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final variant in [
    'spaced',
    'offline',
    'duplicate',
    'plain',
    'no-redemption',
    'canonical-spaced',
    'canonical-offline',
    'canonical-plain',
    'canonical-no-redemption',
    'search-held',
    'canonical-search-held',
    'canonical-duplicate',
  ]) {
    testWidgets('fix4 A same-number Done $variant', (tester) async {
      final r = Fix3Rig(tester);
      if (variant.endsWith('plain')) {
        r.server.customers[5]!['phone'] = '+96890000001';
      }
      r.server.canonicalMode = variant.startsWith('canonical');
      if (variant == 'duplicate' || variant == 'canonical-duplicate') {
        r.server.customers[90] = {
          'id': 90,
          'name': 'Duplicate A',
          'phone': '96890000001',
          'plates': <String>[],
        };
      }
      await r.ready(redeem: !variant.endsWith('no-redemption'));
      r.server.failSearch = variant.endsWith('offline');
      await r.closeNotice();
      await pumpUntilRealCondition(
        tester,
        () => find.text(r.l.posCustomerAttachedTitle).evaluate().isEmpty,
        reason: 'initial attach popup closed',
      );
      final searchGate = variant.endsWith('search-held')
          ? r.gate('keyboard')
          : null;
      final state = r.identity();
      final searches = r.server.requestPaths
          .where((p) => p.endsWith('/search'))
          .length;
      await r.tap(find.byKey(const ValueKey('payment-customer-number')));
      await r.tap(r.dialog(find.text(r.l.commonDone)));
      expect(r.identity(), state);
      expect(
        r.server.requestPaths.where((p) => p.endsWith('/search')).length,
        searches,
        reason: 'Same-number Done must not issue any search',
      );
      if (searchGate != null) {
        expect(searchGate.hits, 0);
        searchGate.release.complete();
        expect(r.lookupBusy, false);
      }
      expect(r.notices, isEmpty);
      expect(find.text(r.l.posCustomerNotFoundTitle), findsNothing);
      expect(find.text(r.l.posCustomerAttachedTitle), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await r.finishCash(
        expected: variant.endsWith('no-redemption') ? 2.7 : 2.2,
      );
      await r.measured(
        'A $variant',
        customer: 5,
        redeem: !variant.endsWith('no-redemption'),
        checked: variant.endsWith('no-redemption') ? 2.7 : 2.2,
      );
    });
  }
  for (final action in [
    'person-cancel',
    'plate-search',
    'plate-keypad',
    'plate-controller',
    'same-type',
    'other-type',
    'missing-table',
  ]) {
    testWidgets('fix4 B pending lookup survives $action', (tester) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final gate = r.gate('keyboard');
      await r.keyboard('96890000002');
      expect(gate.hits, 1);
      final generation = (r.c as dynamic).orderGeneration;
      if (action == 'person-cancel') {
        await r.tap(find.byTooltip(r.l.posCustomerSearchOption));
        await r.tap(r.dialog(find.text(r.l.commonCancel)));
      } else if (action == 'plate-search') {
        await r.tap(find.byKey(const ValueKey('payment-plate-search')));
        expect(find.byType(Dialog), findsNothing);
        expect(r.c.lastPaymentMessage, lookupEn);
      } else if (action == 'plate-keypad') {
        await r.tap(find.byKey(const ValueKey('payment-vehicle-plate')));
        expect(find.byType(Dialog), findsNothing);
        expect(r.c.lastPaymentMessage, lookupEn);
      } else if (action == 'plate-controller') {
        expect(r.c.setVehiclePlateNumber('B777'), false);
        expect(r.c.vehiclePlateNumber, '');
        expect(r.c.lastPaymentMessage, lookupEn);
      } else if (action == 'missing-table') {
        await r.drive(() => r.c.openDiningTable('missing'));
      } else {
        await r.drive(
          () => r.c.selectOrderType(
            action == 'same-type' ? OrderType.quickOrder : OrderType.toGo,
          ),
        );
      }
      expect((r.c as dynamic).orderGeneration, generation);
      expect(r.lookupBusy, true);
      await r.released(gate);
      await r.chooseEarn();
      expect(r.c.selectedCustomer?.id, 6);
      expect(r.c.loyaltyRedeemRuleId, isNull);
      await r.finishCash(expected: 2.7);
      await r.measured('B $action', customer: 6, redeem: false, checked: 2.7);
    });
  }
  testWidgets('fix4 D Details structured deletion detaches', (tester) async {
    final r = Fix3Rig(tester);
    await r.ready();
    r.server.customers.remove(5);
    await r.tap(find.byKey(const ValueKey('payment-customer-details')));
    expect(r.c.selectedCustomer, isNull);
    expect(r.c.loyaltyRedeemRuleId, isNull);
    expect(r.notices, contains(deletedEn));
    expect(find.byType(Dialog), findsNothing);
    await r.finishCash(expected: 2.7);
    await r.measured(
      'D deleted details',
      customer: null,
      redeem: false,
      checked: 2.7,
    );
  });
  for (final label in ['Loyalty redemption', 'Stamp reward']) {
    testWidgets('fix4 F manual caller cannot manufacture $label', (
      tester,
    ) async {
      final r = Fix3Rig(tester);
      await r.ready();
      final before = r.identity();
      expect(
        r.c.applyDiscount(
          DiscountConfiguration(
            kind: DiscountKind.fixedAmount,
            value: 0.5,
            label: label,
          ),
        ),
        false,
      );
      expect(r.identity(), before);
      await r.finishCash(expected: 2.2);
      await r.measured(
        'F caller $label',
        customer: 5,
        redeem: true,
        checked: 2.2,
      );
    });
  }
}
