import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'qr_checkout_fakes.dart';

void main() {
  test(
    'SQLite handover retains the full record and releases only the local active slot',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await SqliteCheckoutStore.createSchema(db);
      final store = SqliteCheckoutStore(db, 'test/server/branch/till');
      final api = CheckoutFakeGateway();
      final c = QrCheckoutController(
        gateway: api,
        store: store,
        now: () => checkoutTime,
        newId: () => 'saved-attempt',
        authorizeGift: () async => false,
        captureCard: (_) async => throw StateError('must not capture'),
        captureBank: (_) async => throw StateError('must not capture'),
      );
      await c.open('qr-bill');
      api.failRelease = true;
      await c.cancel();
      final before = (await store.active())!.json;
      expect(await c.managerTakeover(() async => true), true);
      final reopenedStore = SqliteCheckoutStore(db, 'test/server/branch/till');
      expect(await reopenedStore.active(), isNull);
      final rows = await db.query('qr_checkout_attempts');
      expect(rows, hasLength(1));
      expect(rows.single['state'], 'managed');
      expect(jsonDecode(rows.single['payload'] as String), {
        ...before,
        'state': 'managed',
      });
      expect(api.pushes, isEmpty);
      expect(api.releases, hasLength(1));
      c.dispose();
      await db.close();
    },
  );

  test(
    'manager takeover retains failed release evidence but frees the device slot',
    () async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      f.api.failRelease = true;
      await c.cancel();
      final before = Map<String, dynamic>.from(f.store.value!.json);
      final requests = f.api.releases.length;
      expect(await c.managerTakeover(() async => true), true);
      expect(f.store.value!.state, 'managed');
      expect(f.store.value!.json, {...before, 'state': 'managed'});
      expect(await f.store.active(), isNull);
      expect(f.api.releases.length, requests);
      expect(f.api.pushes, isEmpty);
      expect(f.cards + f.banks, 0);
      final reopened = f.controller();
      await reopened.open(null);
      expect(reopened.phase, CheckoutPhase.empty);
      expect(f.api.claims, 1);
      reopened.dispose();
      c.dispose();
    },
  );

  for (final approved in [false, true]) {
    test(
      'restarted failed release: manager approval=$approved is not payment resolution',
      () async {
        final f = CheckoutFixture();
        final c = f.controller();
        await c.open('qr-bill');
        f.api.failRelease = true;
        await c.cancel();
        c.dispose();
        final resumed = f.controller();
        await resumed.open('another-bill');
        final before = jsonEncode(f.store.value!.json);
        expect(resumed.reference, 'Q-007');
        expect(await resumed.managerTakeover(() async => approved), approved);
        expect(f.api.claims, 1);
        expect(f.api.releases, hasLength(1));
        expect(f.api.pushes, isEmpty);
        expect(resumed.phase, CheckoutPhase.attention);
        if (approved) {
          expect(await f.store.active(), isNull);
          expect(f.store.value!.claim, claimJson());
          expect(f.store.value!.receiptNumber, isNull);
        } else {
          expect(jsonEncode(f.store.value!.json), before);
          expect(await f.store.active(), isNotNull);
        }
        resumed.dispose();
      },
    );
  }

  test(
    'failed durable handover cannot grant exit or discard evidence',
    () async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      f.api.failRelease = true;
      await c.cancel();
      final before = jsonEncode(f.store.value!.json);
      f.store.failState = 'managed';
      expect(await c.managerTakeover(() async => true), false);
      expect(jsonEncode(f.store.value!.json), before);
      expect(await f.store.active(), isNotNull);
      expect(c.canLeave, false);
      expect(c.busy, false);
      expect(c.notice, 'handover_failed');
      c.dispose();
    },
  );

  test(
    'pending immutable payment is never archived by manager takeover',
    () async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      f.api.loseAck = true;
      await c.pay([const CheckoutTender('cash', 4750)]);
      final before = jsonEncode(f.store.value!.json);
      expect(await c.managerTakeover(() async => true), true);
      expect(jsonEncode(f.store.value!.json), before);
      expect(await f.store.active(), isNotNull);
      f.api.loseAck = false;
      await c.retryAcknowledgement();
      expect(f.api.commits, 1);
      expect(c.phase, CheckoutPhase.paid);
      c.dispose();
    },
  );

  test('releasing row with an immutable pay event is not archived', () async {
    final f = CheckoutFixture();
    final c = f.controller();
    await c.open('qr-bill');
    f.api.loseAck = true;
    await c.pay([const CheckoutTender('cash', 4750)]);
    f.store.value = f.store.value!.copy(state: 'releasing');
    c.dispose();
    final resumed = f.controller();
    await resumed.open(null);
    final before = jsonEncode(f.store.value!.json);
    expect(await resumed.managerTakeover(() async => true), true);
    expect(jsonEncode(f.store.value!.json), before);
    expect(await f.store.active(), isNotNull);
    expect(f.api.pushes, hasLength(1));
    expect(f.api.releases, isEmpty);
    resumed.dispose();
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('failed-release manager exit is explicit and durable ($locale)', (
      tester,
    ) async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      f.api.failRelease = true;
      await c.cancel();
      late BuildContext root;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) {
              root = context;
              return const Text('inbox');
            },
          ),
        ),
      );
      Navigator.of(root).push<void>(
        MaterialPageRoute(
          builder: (_) => Localizations.override(
            context: root,
            locale: Locale(locale),
            child: QrCheckoutBoundary(
              controller: c,
              authorizeManager: () async => true,
              paymentPage: (_, _) => const Text('must not offer payment'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('must not offer payment'), findsNothing);
      expect(
        find.text(
          locale == 'en'
              ? 'Manager takeover does not clear or pay this bill. Its payment evidence remains saved for review.'
              : 'تسليم الحالة للمشرف لا يلغي حجز الفاتورة ولا يسددها. تبقى أدلة الدفع محفوظة للمراجعة.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('qr-checkout-exit')));
      await tester.pumpAndSettle();
      expect(find.text('inbox'), findsOneWidget);
      expect(f.store.value!.state, 'managed');
      expect(f.api.releases, hasLength(1));
      expect(f.api.pushes, isEmpty);
      c.dispose();
    });
  }
}
