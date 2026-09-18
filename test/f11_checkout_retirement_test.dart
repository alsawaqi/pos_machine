import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/draft_recovery/checkout_recovery.dart';
import 'f11_recovery_admission_test.dart' show currentScope, oldScope;

void main() {
  sqfliteFfiInit();
  for (final scenario in [
    'allowed',
    'denied',
    'current',
    'uncertain',
    'captured',
    'changed',
    'scope changed',
  ]) {
    test('F11 audited retirement $scenario', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await SqliteCheckoutStore.createSchema(db);
      final attempt = CheckoutAttempt(
        id: 'id',
        orderUuid: 'bill',
        createdAt: DateTime.utc(2026, 9, 12),
        state: scenario == 'uncertain' ? 'uncertain' : 'releasing',
        tenderMayHaveStarted: scenario == 'captured' ? true : null,
      );
      await db.insert('qr_checkout_attempts', {
        'id': attempt.id,
        'scope': scenario == 'current' ? currentScope : oldScope,
        'state': attempt.state,
        'payload': jsonEncode(attempt.json),
      });
      var scope = currentScope;
      final service = CheckoutRecovery(db, () => scope);
      final original = (await service.rows()).single;
      final result = service.retire(
        original,
        staffId: 9,
        authorize: () async {
          if (scenario == 'changed') {
            await db.update('qr_checkout_attempts', {'state': 'uncertain'});
          }
          if (scenario == 'scope changed') scope = oldScope;
          return scenario != 'denied';
        },
      );
      if (scenario == 'changed' || scenario == 'scope changed') {
        await expectLater(result, throwsStateError);
      } else {
        expect(await result, scenario == 'allowed');
      }
      if (scenario == 'allowed') {
        final archive = (await db.query('qr_checkout_recovery_archive')).single;
        expect(jsonDecode(archive['original_row'] as String), original);
        expect(archive['requested_by_staff_id'], 9);
        expect(archive['current_scope'], currentScope);
        expect(archive['authority'], 'existing_manager_approval');
        expect(
          (await db.query('qr_checkout_attempts')).single['state'],
          'managed',
        );
        expect(await service.rows(), isEmpty);
        // Neither a release success nor a payment result was invented.
        final retained = CheckoutAttempt.decode(
          (await db.query('qr_checkout_attempts')).single['payload'] as String,
        );
        expect(retained.event, isNull);
        expect(retained.captures, isEmpty);
        expect(retained.claim, attempt.claim);
      } else {
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name='qr_checkout_recovery_archive'",
          ),
          isEmpty,
        );
      }
    });
  }
}
