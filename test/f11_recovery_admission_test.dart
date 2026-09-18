import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/draft_recovery/recovery_admission.dart';
import 'package:pos_machine/draft_recovery/recovery_screen.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/qr_quick/qr_quick_store.dart';

final currentScope = jsonEncode(['http://localhost:8088/api/v1', 1, 1, 'TILL']);
final oldScope = jsonEncode([
  'http://localhost:8280/api/v1',
  100,
  10,
  'TD-TILL-1',
]);

void main() {
  sqfliteFfiInit();
  for (final kind in [
    'foreign release',
    'current release',
    'foreign uncertain',
    'current uncertain',
  ]) {
    test('F11 admission: $kind', () async {
      Future<Database> open() => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final checkout = await open(),
          dineIn = await open(),
          quick = await open();
      addTearDown(() async {
        await checkout.close();
        await dineIn.close();
        await quick.close();
      });
      await SqliteCheckoutStore.createSchema(checkout);
      await SqliteDineInStore.createSchema(dineIn);
      await SqliteQrQuickStore.createSchema(quick);
      final a = CheckoutAttempt(
        id: 'attempt',
        orderUuid: 'bill',
        state: kind.endsWith('uncertain') ? 'uncertain' : 'releasing',
        createdAt: DateTime.utc(2026, 9, 12),
      );
      await checkout.insert('qr_checkout_attempts', {
        'id': a.id,
        'scope': kind.startsWith('foreign') ? oldScope : currentScope,
        'state': a.state,
        'payload': jsonEncode(a.json),
      });
      final before = await checkout.query('qr_checkout_attempts');
      Future<void> check() {
        // Run the same behavior assertion on the frozen API, which predates
        // the optional scope argument. This adapter changes no product code.
        dynamic result;
        try {
          result = Function.apply(assertRecoveryJournalsIdle, [], {
            #checkout: checkout,
            #dineIn: dineIn,
            #quick: quick,
            #currentScope: currentScope,
          });
        } on NoSuchMethodError {
          result = assertRecoveryJournalsIdle(
            checkout: checkout,
            dineIn: dineIn,
            quick: quick,
          );
        }
        return result as Future<void>;
      }

      if (kind == 'foreign release') {
        await check();
      } else {
        await expectLater(
          check(),
          throwsA(
            predicate(
              (e) =>
                  e is StateError && e.message.contains('Check payment result'),
            ),
          ),
        );
      }
      expect(await checkout.query('qr_checkout_attempts'), before);
    });
  }
  for (final arabic in [false, true]) {
    testWidgets(
      'F11 recovery never displays raw exception ${arabic ? "AR" : "EN"}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RecoveryScreen(
              arabic: arabic,
              createController: () async =>
                  throw StateError('SQL private host: raw failure'),
            ),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Bad state'), findsNothing);
        expect(find.textContaining('SQL private'), findsNothing);
        expect(
          find.textContaining(
            arabic ? 'احتفظ بكل النسخ الأصلية' : 'Keep every original copy',
          ),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );
  }
}
