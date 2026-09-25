import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'real_io_wait.dart';
import 't12_fix2_customer_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final method in [
    'cash',
    'gps',
    'card',
    'bank',
    'mixed',
    'split',
    'gift',
    'plate',
    'raw',
    'delivery',
    'delivery-raw',
    'delivery-back',
    'delivery-cancel',
  ]) {
    testWidgets('T12 fix2 d e tender $method', (tester) async {
      final r = CustomerRig(tester, gpsDelay: method == 'gps');
      await r.start();
      await r.add();
      await r.payPage();
      final raw = method == 'raw';
      if (!raw) await r.attach();
      if (raw) {
        // No catalogue match: the real keyboard keeps this as a raw number.
        await r.tap(find.byKey(const ValueKey('payment-customer-number')));
        for (final digit in '90009999'.split('')) {
          await r.tap(
            find.descendant(
              of: find.byType(Dialog).last,
              matching: find.text(digit),
            ),
          );
        }
        await r.tap(
          find.descendant(
            of: find.byType(Dialog).last,
            matching: find.text(r.l.commonDone),
          ),
        );
        await r.closeNotice();
        expect(r.c.selectedCustomer, isNull);
        expect(r.c.customerReferenceNumber, '90009999');
      }
      if (method == 'plate') {
        await r.tap(find.byKey(const ValueKey('payment-vehicle-plate')));
        for (final key in ['A', '1', '2', '3']) {
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
      }
      if (method.startsWith('delivery')) {
        await r.exit();
        await r.tap(find.text('Delivery').first);
        await r.tap(find.text('Test Delivery').last);
        await r.payPage();
        if (method == 'delivery-back' || method == 'delivery-cancel') {
          await r.exit(cancel: method == 'delivery-cancel');
          await r.payPage();
        }
        await r.tap(find.text(r.l.posPaymentDeliveryProceed));
        await r.tap(find.text(r.l.posDeliveryProceedReference));
        await r.tap(
          find.descendant(
            of: find.byType(Dialog).last,
            matching: find.text('1'),
          ),
        );
        await r.tap(
          find.descendant(
            of: find.byType(Dialog).last,
            matching: find.text(r.l.commonDone),
          ),
        );
        if (method == 'delivery-raw') {
          await r.tap(find.text(r.l.posDeliveryProceedCustomer));
          await r.tap(
            find.descendant(
              of: find.byType(Dialog).last,
              matching: find.text(r.l.posKeyboardClear),
            ),
          );
          for (final digit in '90009999'.split('')) {
            await r.tap(
              find.descendant(
                of: find.byType(Dialog).last,
                matching: find.text(digit),
              ),
            );
          }
          await r.tap(
            find.descendant(
              of: find.byType(Dialog).last,
              matching: find.text(r.l.commonDone),
            ),
          );
        }
        await r.tap(
          find.widgetWithText(FilledButton, r.l.posDeliveryProceedConfirm),
        );
      } else if (method == 'card' || method == 'bank' || method == 'gift') {
        final label = method == 'card'
            ? r.l.posPaymentCard
            : method == 'bank'
            ? r.l.posPaymentBankPos
            : r.l.posPaymentGift;
        await r.tap(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_PaymentMethodActionButton',
            ),
          ),
        );
        if (method == 'gift') {
          await r.tap(find.widgetWithText(FilledButton, r.l.posPaymentGift));
        }
      } else if (method == 'mixed') {
        await r.tap(find.byKey(const ValueKey('payment-key-1')));
        await r.tap(find.text(r.l.posPaymentSplitPayment));
      } else if (method == 'split') {
        await r.tap(find.text(r.l.posPaymentSplitBill));
        await r.tap(find.text(r.l.posSplitDlgGuests(2)));
        await r.tap(find.text(r.l.posSplitDlgApplySplit));
        await r.closeNotice();
        await r.cash();
        await pumpUntilRealCondition(
          tester,
          () => !r.c.isProcessingPayment && r.c.paidSplitCount == 1,
          reason: 'first real split leg',
        );
        await r.closeNotice();
        await r.cash();
      } else {
        await r.cash();
      }
      if (method == 'card' || method == 'mixed') {
        await r.tap(find.text(r.l.posCharityKeepOriginalTotal));
      }
      final posts = raw || method == 'delivery-raw' || method == 'plate'
          ? 1
          : 0;
      await r.checkMoney(
        'd e $method',
        customer: raw || method == 'delivery-raw' ? 901 : 5,
        redeem: false,
        posts: posts,
        gift: method == 'gift',
        delivery: method.startsWith('delivery'),
        earn: raw || method == 'delivery-raw' ? [11, 12] : null,
      );
      if (method == 'gps') {
        expect(r.gpsCalls, greaterThanOrEqualTo(1));
        expect(r.measuredGpsMillis, greaterThan(700));
        // ignore: avoid_print
        print('FIX2_GPS actual_delay_ms=${r.measuredGpsMillis}');
      }
      if (method == 'plate') {
        expect(r.server.posts.single['phone'], '+968 9000 0001');
      }
      if (raw || method == 'delivery-raw') {
        expect(r.server.posts.single['phone'], '90009999');
      }
      if (method == 'card' || method == 'mixed') expect(r.cardCalls, 1);
    });
  }
}
