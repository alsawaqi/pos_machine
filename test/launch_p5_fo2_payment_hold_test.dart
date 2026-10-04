import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/payment_hold.dart';
import 'package:pos_machine/core/staff_session_guard.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 fix order 2 — T13: a forced sign-out (staff-status says the
/// person is no longer active, or the server refuses their staff token)
/// waits while a payment is in progress, then happens right after it.
class _Api implements PosApiService {
  Set<int> active = {};

  @override
  Future<Set<int>> fetchActiveStaffIds() async => active;

  @override
  Future<({List<Map<String, dynamic>> approvers, String? asOf})>
  fetchApprovers() async => (approvers: <Map<String, dynamic>>[], asOf: null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  late SharedPreferences prefs;
  late SessionService session;
  late _Api api;
  late AppDatabase db;
  final payment = Object();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = SessionService(const FlutterSecureStorage(), prefs);
    api = _Api();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PaymentHold.reset();
    await session.saveStaff(
      const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok-4'),
      login: true,
    );
  });
  tearDown(() async {
    PaymentHold.reset();
    await db.close();
  });

  group('the hold', () {
    test('an owner holds it until it is released', () async {
      expect(PaymentHold.active, isFalse);
      await PaymentHold.idle(); // at once
      PaymentHold.set(payment, true);
      expect(PaymentHold.active, isTrue);
      var done = false;
      unawaited(PaymentHold.idle().then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      PaymentHold.set(payment, false);
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      expect(PaymentHold.active, isFalse);
    });

    test('a tracked tender holds it too (card, cash, QR settle)', () async {
      final charge = Completer<void>();
      final tender = BusinessBoundary.trackPayment(() => charge.future);
      expect(PaymentHold.active, isTrue);
      var done = false;
      unawaited(PaymentHold.idle().then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      charge.complete();
      await tender;
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionServiceProvider.overrideWithValue(session),
        apiServiceProvider.overrideWithValue(api),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('staff_unverified during a payment signs out right after it', () async {
    final c = container();
    PaymentHold.set(payment, true);
    final pending = c
        .read(sessionControllerProvider.notifier)
        .staffUnverified(reason: 'token_invalid');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(session.staff, isNotNull, reason: 'the card sale is not lost');
    // A second refusal during the same payment adds nothing.
    await c
        .read(sessionControllerProvider.notifier)
        .staffUnverified(reason: 'token_invalid');
    expect(session.staff, isNotNull);
    PaymentHold.set(payment, false);
    await pending;
    expect(session.staff, isNull);
    expect(c.read(staffReverifyNoticeProvider), isTrue);
  });

  test('a deferred sign-out never signs out the next person', () async {
    final c = container();
    PaymentHold.set(payment, true);
    final pending = c
        .read(sessionControllerProvider.notifier)
        .staffUnverified(reason: 'token_invalid');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Sara signs out herself and Omar signs in before the payment ends.
    await c.read(sessionControllerProvider.notifier).logoutStaff();
    await c
        .read(sessionControllerProvider.notifier)
        .saveStaff(
          const StaffSessionData(id: 5, name: 'Omar', staffToken: 'tok-5'),
        );
    PaymentHold.set(payment, false);
    await pending;
    expect(session.staff?.id, 5);
  });

  testWidgets('an inactive person is signed out after the payment', (
    tester,
  ) async {
    api.active = {9};
    PaymentHold.set(payment, true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionServiceProvider.overrideWithValue(session),
          apiServiceProvider.overrideWithValue(api),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: StaffSessionGuard(child: Text('selling')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(session.staff, isNotNull, reason: 'held during the payment');
    PaymentHold.set(payment, false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(session.staff, isNull);
  });

  test('the POS screen holds while a split, checkout or tender is open', () {
    // Wired in the real screen (a 21 000-line widget); the hold above is
    // what the sign-outs wait for.
    final screen = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
    expect(
      RegExp(
        r'PaymentHold\.set\(\s*this,\s*_normalQrCheckoutOpen \|\|\s*'
        r'controller\.isProcessingPayment \|\|\s*'
        r'controller\.showPaymentLaunchOverlay \|\|\s*'
        r'\(controller\.hasRecordedSplitPayments && controller\.cart\.isNotEmpty\)',
      ).hasMatch(screen),
      isTrue,
    );
    expect(screen, contains('PaymentHold.set(this, false);'));
  });
}
