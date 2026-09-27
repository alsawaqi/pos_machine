import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 't12_fix6_tender_freeze_test.dart'
    show boot, activate, changedTotal, tapTender;
import 't12_fix4_money_workflows_test.dart' show money;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('C14 pending-combine refusal releases freeze before next tap', (
    tester,
  ) async {
    final r = await boot(tester);
    await r.drive(
      () => r.localDb.insert('bill_combine_journal', {
        'id': 'fix7-combine',
        'scope': 'fixture-other-scope',
        'state': 'pending',
        'payload': '{}',
      }),
    );
    await r.amount('3');
    final effects = await r.effects();
    await tapTender(r, 'Cash');
    expect(
      r.c.lastPaymentMessage,
      'Finish the pending bill combine in Dine-In first.',
    );
    expect(r.c.isProcessingPayment, false);
    await r.noEffects('C14 existing combine guard', effects);
    await r.drive(
      () => r.localDb.update('bill_combine_journal', {'state': 'not_applied'}),
    );
    await r.closeNotice();
    activate(r);
    // A real background reader must see a fresh price after the refusal.
    expect(
      r.c.snapshot().total,
      2.43,
      reason: 'guard refusal released the tender freeze',
    );
    await tapTender(r, 'Cash');
    expect(r.c.lastPaymentMessage, changedTotal);
    await r.noEffects('C14 changed quote', effects);
    expect(find.textContaining('2.430'), findsWidgets);
    await r.finishCash(expected: 2.43);
    await money(r, 'C14 guard release', total: 2430, discount: 270);
  });
}
