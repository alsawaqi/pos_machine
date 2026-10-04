import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/attendance.dart';
import 'package:pos_machine/core/auth_wire.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/staff_pin_login_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/expense_restock_payload.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 fix order 1, F1 [WIRE] — the signed staff token: kept in
/// secure storage with the staff session and cleared at logout; stamped
/// into every P5 event as its maker's token (kept with the outbox row);
/// sent as `X-Staff-Token` on every call while someone is logged in; a
/// restored session without one logs in again; 403 `staff_unverified`
/// logs out and asks for the PIN again.
class _Api implements PosApiService {
  final pushed = <Map<String, dynamic>>[];
  StaffSessionData? login;

  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    pushed.addAll(events);
    return {
      'results': [
        for (final e in events)
          {
            'client_event_id': e['client_event_id'],
            'status': 'processed',
            'result': <String, dynamic>{},
          },
      ],
    };
  }

  @override
  Future<StaffSessionData> staffLogin({
    required String pin,
    double? lat,
    double? lng,
  }) async => login!;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

/// A real [PosApiService] over a Dio that answers every request itself and
/// records the headers it was sent with.
({PosApiService api, List<Map<String, dynamic>> headers}) _realApi({
  required int status,
  required Object body,
  void Function(String? reason)? onStaffUnverified,
}) {
  final headers = <Map<String, dynamic>>[];
  final dio = Dio(BaseOptions(validateStatus: (_) => true));
  final api = PosApiService(
    tokenGetter: () => 'device-token',
    onStaffUnverified: onStaffUnverified,
    dio: dio,
  );
  // Added after the client's own interceptors: sees the final headers.
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        headers.add(Map<String, dynamic>.from(options.headers));
        handler.resolve(
          Response(requestOptions: options, statusCode: status, data: body),
        );
      },
    ),
  );
  return (api: api, headers: headers);
}

void main() {
  late SharedPreferences prefs;
  late SessionService session;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = SessionService(const FlutterSecureStorage(), prefs);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    StaffTokenHolder.clear();
  });
  tearDown(() async {
    StaffTokenHolder.clear();
    await db.close();
  });

  ProviderContainer container({PosApiService? api}) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionServiceProvider.overrideWithValue(session),
        appDatabaseProvider.overrideWithValue(db),
        if (api != null) apiServiceProvider.overrideWithValue(api),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the login reply carries the token, at the data level or in staff', () {
    for (final body in [
      {
        'data': {
          'staff': {'id': 4, 'name': 'Sara'},
          'staff_token': 'tok-4',
        },
        'errors': <Object>[],
      },
      {
        'data': {
          'staff': {'id': 4, 'name': 'Sara', 'staff_token': 'tok-4'},
        },
        'errors': <Object>[],
      },
    ]) {
      final api = _realApi(status: 200, body: body).api;
      expect(
        api.staffLogin(pin: '1234').then((s) => s.staffToken),
        completion('tok-4'),
      );
    }
  });

  test(
    'a login keeps the token in secure storage only; logout clears it',
    () async {
      final c = container(api: _Api());
      await c
          .read(sessionControllerProvider.notifier)
          .saveStaff(
            const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok-4'),
          );
      expect(
        await const FlutterSecureStorage().read(key: 'staff_token'),
        'tok-4',
      );
      expect(session.staffToken, 'tok-4');
      expect(StaffTokenHolder.token, 'tok-4');
      expect(StaffTokenHolder.staffId, 4);
      // Never in the (not secret) preferences.
      for (final key in prefs.getKeys()) {
        expect('${prefs.get(key)}', isNot(contains('tok-4')), reason: key);
      }
      // An attendance update keeps the token of the session it updates.
      await c
          .read(sessionControllerProvider.notifier)
          .updateAttendance(const StaffAttendance(open: true, uuid: 'a-1'));
      expect(session.staffToken, 'tok-4');

      await c.read(sessionControllerProvider.notifier).logoutStaff();
      expect(
        await const FlutterSecureStorage().read(key: 'staff_token'),
        isNull,
      );
      expect(session.staffToken, isNull);
      expect(StaffTokenHolder.token, isNull);
    },
  );

  test(
    'a new login without a token (older server) drops the old one',
    () async {
      final c = container(api: _Api());
      final controller = c.read(sessionControllerProvider.notifier);
      await controller.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok-4'),
      );
      await controller.saveStaff(const StaffSessionData(id: 5, name: 'Omar'));
      expect(session.staffToken, isNull);
      expect(StaffTokenHolder.token, isNull);
    },
  );

  test('every P5 event carries its maker\'s token', () {
    StaffTokenHolder.set(4, 'tok-4');
    final events = <Map<String, dynamic>>[
      buildOrderVoidEvent(orderUuid: 'o-1', staffId: 4),
      buildExpenseLogEvent(
        category: 'other',
        amountBaisas: 500,
        staffId: 4,
        paidFromDrawer: true,
        shiftUuid: 'shift-1',
      ),
      buildShiftCloseEvent(
        shiftUuid: 'shift-1',
        closingCashBaisas: 0,
        closedByStaffId: 4,
      ),
      buildClockEvent(
        clockIn: true,
        attendanceUuid: 'a-1',
        staffId: 4,
        at: DateTime.utc(2026, 10, 4),
      ),
      buildTableSessionEvent(
        'cancel_line',
        tableId: '3',
        seatingKey: 's-1',
        queuedOffline: false,
        payload: const {},
        staffId: 4,
      ),
    ];
    for (final e in events) {
      expect(e['payload']['auth_v'], 1, reason: e['event_type'] as String);
      expect(
        e['payload']['staff_token'],
        'tok-4',
        reason: e['event_type'] as String,
      );
    }
    // An event attributed to somebody else never carries this person's.
    expect(
      buildOrderVoidEvent(orderUuid: 'o-1', staffId: 9)['payload'],
      isNot(contains('staff_token')),
    );
    // Nobody logged in: no token, still a P5 event.
    StaffTokenHolder.clear();
    final anon = buildOrderVoidEvent(orderUuid: 'o-1', staffId: 4)['payload'];
    expect(anon['auth_v'], 1);
    expect(anon, isNot(contains('staff_token')));
  });

  test(
    'a queued event keeps its maker\'s token after the next login',
    () async {
      final api = _Api();
      final repo = OrderSyncRepository(api, db);
      StaffTokenHolder.set(4, 'tok-4');
      final event = buildExpenseLogEvent(
        category: 'other',
        amountBaisas: 750,
        staffId: 4,
      );
      // Durable while offline...
      await db.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: 'expense:1',
          eventsJson: jsonEncode([event]),
          createdAt: DateTime.utc(2026, 10, 4, 6),
        ),
      );
      // ...then Omar logs in and the till comes back online.
      StaffTokenHolder.set(5, 'tok-5');
      await repo.flush();
      expect(api.pushed.single['payload']['staff_token'], 'tok-4');
    },
  );

  test('the PIN-screen clock names the clocking person', () async {
    final api = _Api();
    final repo = OrderSyncRepository(api, db);
    final attendance = AttendanceService(
      repo,
      clock: () => DateTime.utc(2026, 10, 4, 6),
      newUuid: () => 'u-1',
    );
    // Nobody is logged in on the till.
    await attendance.clockIn(5, staffToken: 'tok-5');
    await attendance.clockOut(5, attendanceUuid: 'u-1', staffToken: 'tok-5');
    expect(api.pushed.map((e) => e['payload']['staff_token']), [
      'tok-5',
      'tok-5',
    ]);
  });

  testWidgets('the PIN screen clock button sends the token of that login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _Api()
      ..login = const StaffSessionData(
        id: 5,
        name: 'Omar',
        attendance: StaffAttendance(open: false),
        staffToken: 'tok-5',
      );
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
          home: StaffPinLoginScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pin-login-clock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5555');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 100 && api.pushed.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final event = api.pushed.single;
    expect(event['event_type'], 'staff.clock_in');
    expect(event['payload']['staff_token'], 'tok-5');
    // Clocking is not a login: nobody is signed in, no token is kept.
    expect(session.staff, isNull);
    expect(session.staffToken, isNull);
  });

  test('X-Staff-Token rides every call while someone is logged in', () async {
    final real = _realApi(
      status: 200,
      body: {
        'data': {'active_staff_ids': <int>[], 'as_of': null},
        'errors': <Object>[],
      },
    );
    StaffTokenHolder.set(4, 'tok-4');
    await real.api.fetchActiveStaffIds();
    expect(real.headers.last['X-Staff-Token'], 'tok-4');
    StaffTokenHolder.clear();
    await real.api.fetchActiveStaffIds();
    expect(real.headers.last.containsKey('X-Staff-Token'), isFalse);
  });

  test('a restored session without a token must log in again', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'device_token': 'dev'});
    prefs = await SharedPreferences.getInstance();
    // As an older build left it: a staff session and an open shift.
    await SessionService(
      const FlutterSecureStorage(),
      prefs,
    ).saveStaff(const StaffSessionData(id: 4, name: 'Sara'));
    await SessionService(const FlutterSecureStorage(), prefs).saveOpenShift(
      OpenShiftData(
        uuid: 'shift-1',
        openingCashBaisas: 0,
        openedAt: DateTime.utc(2026, 10, 4),
        staffId: 4,
      ),
    );
    final upgraded = SessionService(const FlutterSecureStorage(), prefs);
    await upgraded.load();
    expect(upgraded.staff, isNull);
    expect(upgraded.reloginRequired, isTrue);
    // The drawer stays open for the next login.
    expect(upgraded.openShift?.uuid, 'shift-1');

    // With its token the session is restored as it was.
    await upgraded.saveStaff(
      const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok-4'),
      login: true,
    );
    StaffTokenHolder.clear();
    final restarted = SessionService(const FlutterSecureStorage(), prefs);
    await restarted.load();
    expect(restarted.staff?.id, 4);
    expect(restarted.staffToken, 'tok-4');
    expect(restarted.reloginRequired, isFalse);
    expect(StaffTokenHolder.token, 'tok-4');
  });

  test(
    '403 staff_unverified fires the callback (any reason); others do not',
    () async {
      var fired = 0;
      final reasons = <String?>[];
      for (final reason in const [
        'token_missing',
        'token_invalid',
        'token_other_device',
        'token_other_staff',
        'staff_inactive',
      ]) {
        final refused = _realApi(
          status: 403,
          body: {
            'data': {'reason': reason},
            'errors': [
              {'code': 'staff_unverified', 'message': 'Log in again.'},
            ],
          },
          onStaffUnverified: reasons.add,
        );
        await expectLater(
          refused.api.fetchActiveStaffIds(),
          throwsA(
            isA<ApiException>().having((e) => e.reason, 'reason', reason),
          ),
        );
      }
      expect(reasons, [
        'token_missing',
        'token_invalid',
        'token_other_device',
        'token_other_staff',
        'staff_inactive',
      ]);
      final refused = _realApi(
        status: 403,
        body: {
          'data': null,
          'errors': [
            {'code': 'staff_unverified', 'message': 'Log in again.'},
          ],
        },
        onStaffUnverified: (_) => fired++,
      );
      await expectLater(
        refused.api.fetchActiveStaffIds(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isStaffUnverified,
            'unverified',
            true,
          ),
        ),
      );
      expect(fired, 1);
      final other = _realApi(
        status: 403,
        body: {
          'data': null,
          'errors': [
            {'code': 'approval_required', 'message': 'No.'},
          ],
        },
        onStaffUnverified: (_) => fired++,
      );
      await expectLater(
        other.api.fetchActiveStaffIds(),
        throwsA(isA<ApiException>()),
      );
      expect(fired, 1);
    },
  );

  testWidgets('staff_unverified logs out and the PIN screen asks again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await session.saveStaff(
      const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok-4'),
      login: true,
    );
    final c = container(api: _Api());
    await c
        .read(sessionControllerProvider.notifier)
        .staffUnverified(reason: 'token_invalid');
    expect(session.staff, isNull);
    expect(session.staffToken, isNull);
    expect(c.read(staffReverifyNoticeProvider), isTrue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: StaffPinLoginScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Please enter your PIN again.'), findsOneWidget);
    // Shown once.
    expect(c.read(staffReverifyNoticeProvider), isFalse);
  });

  test(
    'the shift read runs only after a login, with that person\'s token',
    () async {
      final real = _realApi(
        status: 200,
        body: {
          'data': {'shift': null},
          'errors': <Object>[],
        },
      );
      final c = container(api: real.api);
      final controller = c.read(sessionControllerProvider.notifier);
      // Nobody logged in (start-up, PIN screen): no shift read at all.
      expect(await controller.reconcileShiftForStaff(4), isNull);
      expect(real.headers, isEmpty);
      // After the login both lookups (by staff, then by device) name them.
      await controller.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok-4'),
      );
      await controller.reconcileShiftForStaff(4);
      expect(real.headers, hasLength(2));
      for (final h in real.headers) {
        expect(h['X-Staff-Token'], 'tok-4');
      }
    },
  );
}
