import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/staff_pin_login_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 C4 (PHASE-1A D-9 / D-7) — the login lock: a server 423 locks
/// the pad under a countdown, nothing retries by itself, the lock survives a
/// restart, and a manager unlock clears the server lock.
class _Api implements PosApiService {
  int logins = 0;
  int unlocks = 0;
  int lockSeconds = 90;
  String? unlockName = 'Mona';
  ApiException? loginError;

  @override
  Future<StaffSessionData> staffLogin({
    required String pin,
    double? lat,
    double? lng,
  }) async {
    logins++;
    throw loginError ??
        ApiException(
          message: 'Locked',
          statusCode: 423,
          code: 'pin_locked',
          retryAfterSeconds: lockSeconds,
        );
  }

  @override
  Future<String?> unlockPinLock(String pin) async {
    unlocks++;
    return unlockName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  late SharedPreferences prefs;
  late _Api api;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = _Api();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionServiceProvider.overrideWithValue(
            SessionService(const FlutterSecureStorage(), prefs),
          ),
          apiServiceProvider.overrideWithValue(api),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: StaffPinLoginScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.text(d).first);
      await tester.pump();
    }
  }

  testWidgets('a 423 locks the pad with a countdown, persisted', (
    tester,
  ) async {
    await pumpLogin(tester);
    await typePin(tester, '1234');
    await tester.tap(find.byKey(const ValueKey('pin-login-submit')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
    expect(api.logins, 1);
    expect(find.byKey(const ValueKey('pin-login-locked')), findsOneWidget);
    expect(find.textContaining('Try again in 1:'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.byKey(const ValueKey('pin-login-submit')),
    );
    expect(submit.onPressed, isNull);
    // The pad ignores digits while locked.
    await typePin(tester, '9');
    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == Colors.white,
        );
    expect(dots, isEmpty);
    // The lock survives a restart.
    expect(prefs.getString(loginLockoutKey), contains('locked_until_ms'));
    await pumpLogin(tester);
    expect(find.byKey(const ValueKey('pin-login-locked')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pin-login-manager-unlock')),
      findsOneWidget,
    );
  });

  testWidgets('at zero the pad re-enables, and nothing retries by itself', (
    tester,
  ) async {
    api.lockSeconds = 1;
    await pumpLogin(tester);
    await typePin(tester, '1234');
    await tester.tap(find.byKey(const ValueKey('pin-login-submit')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byKey(const ValueKey('pin-login-locked')), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byKey(const ValueKey('pin-login-locked')), findsNothing);
    expect(api.logins, 1);
  });

  testWidgets('a manager unlock clears the server lock and the pad', (
    tester,
  ) async {
    await pumpLogin(tester);
    await typePin(tester, '1234');
    await tester.tap(find.byKey(const ValueKey('pin-login-submit')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-login-manager-unlock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();
    await tester.tap(find.text('Manager unlock').last);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump();
    expect(api.unlocks, 1);
    expect(find.byKey(const ValueKey('pin-login-locked')), findsNothing);
    expect(find.text('Unlocked by Mona. Enter your PIN.'), findsOneWidget);
    expect(prefs.getString(loginLockoutKey), isNull);
  });

  testWidgets('a rejected unlock keeps the lock', (tester) async {
    api.unlockName = null;
    await pumpLogin(tester);
    await typePin(tester, '1234');
    await tester.tap(find.byKey(const ValueKey('pin-login-submit')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-login-manager-unlock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await tester.tap(find.text('Manager unlock').last);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byKey(const ValueKey('pin-login-locked')), findsOneWidget);
    expect(prefs.getString(loginLockoutKey), isNotNull);
  });

  test('the D-6 body integer is read from errors[0]', () {
    final e = ApiException.fromErrors([
      {'code': 'pin_locked', 'message': 'Locked', 'retry_after_seconds': 120},
    ], 423);
    expect(e.isPinLock, isTrue);
    expect(e.lockDuration, const Duration(seconds: 120));
    final t = ApiException.fromErrors([
      {'code': 'too_many_attempts', 'retry_after_seconds': 30},
    ], 429);
    expect(t.isPinLock, isTrue);
    expect(t.lockDuration, const Duration(seconds: 30));
  });
}
