import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/attendance.dart';
import 'package:pos_machine/core/shift_reminder.dart';
import 'package:pos_machine/core/staff_session_guard.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/clock_in_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'support/fake_order_storage.dart';

/// LAUNCH-P5 C6 (staff-status, clock in/out) and C8 (shift-end reminder).
class _Api implements PosApiService {
  Set<int>? active;
  Object? statusError;
  int statusCalls = 0;
  final pushed = <Map<String, dynamic>>[];

  @override
  Future<Set<int>> fetchActiveStaffIds() async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    return active ?? {};
  }

  @override
  Future<({List<Map<String, dynamic>> approvers, String? asOf})>
  fetchApprovers() async => (approvers: <Map<String, dynamic>>[], asOf: null);

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  // LAUNCH-P5 fix order 2c — never the shared on-disk orders database
  // (.dart_tool/sqflite_common_ffi/databases/mithqal_orders.db): test
  // files running in parallel would lock each other out of it.
  setUp(() => debugOrderStorageOverride = FakeOrderStorage());
  tearDown(() => debugOrderStorageOverride = null);
  late SharedPreferences prefs;
  late SessionService session;
  late _Api api;
  late AppDatabase db;
  final alerts = <DateTime>[];
  var now = DateTime.utc(2026, 10, 4, 18, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = SessionService(const FlutterSecureStorage(), prefs);
    api = _Api();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    alerts.clear();
    now = DateTime.utc(2026, 10, 4, 18, 0);
    StaffSessionGuard.clock = () => now;
    StaffSessionGuard.playAlert = () => alerts.add(now);
  });
  tearDown(() async {
    StaffSessionGuard.clock = DateTime.now;
    await db.close();
  });

  List<Override> overrides() => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    sessionServiceProvider.overrideWithValue(session),
    apiServiceProvider.overrideWithValue(api),
    appDatabaseProvider.overrideWithValue(db),
  ];

  Widget app(Widget home) => ProviderScope(
    overrides: overrides(),
    child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: home,
    ),
  );

  group('login reply', () {
    test('carries attendance and branch ids, at either level', () {
      final staff = StaffSessionData.fromJson({
        'id': 4,
        'name': 'Sara',
        'branch_ids': [1, 2],
        'attendance': {
          'open': true,
          'clock_in_at': '2026-10-04T05:00:00Z',
          'uuid': 'att-1',
        },
      });
      expect(staff.branchIds, [1, 2]);
      expect(staff.attendance!.open, isTrue);
      expect(staff.attendance!.uuid, 'att-1');
      final round = StaffSessionData.fromStored(
        jsonDecode(jsonEncode(staff.toJson())) as Map<String, dynamic>,
      );
      expect(round.attendance!.open, isTrue);
      expect(round.branchIds, [1, 2]);
    });
  });

  group('clock events', () {
    test('staff.clock_in / clock_out go through the outbox', () async {
      final repo = OrderSyncRepository(api, db);
      final attendance = AttendanceService(
        repo,
        clock: () => DateTime.utc(2026, 10, 4, 6),
        newUuid: () => 'u-1',
      );
      final done = await attendance.clockIn(4);
      expect(done.uuid, 'u-1');
      await attendance.clockOut(4, attendanceUuid: 'u-1');
      final rows = await repo.allRows();
      final events = [
        for (final r in rows) ...(jsonDecode(r.eventsJson) as List).cast<Map>(),
      ];
      expect(events.map((e) => e['event_type']), [
        'staff.clock_in',
        'staff.clock_out',
      ]);
      for (final e in events) {
        expect(e['payload']['attendance_uuid'], 'u-1');
        expect(e['payload']['staff_id'], 4);
        expect(e['payload']['auth_v'], 1);
      }
      // Pushed when online (here the fake ACKs them).
      expect(api.pushed.map((e) => e['event_type']), [
        'staff.clock_in',
        'staff.clock_out',
      ]);
    });
  });

  group('clock-in screen', () {
    testWidgets('one tap clocks in and records the attendance', (tester) async {
      await session.saveStaff(
        const StaffSessionData(
          id: 4,
          name: 'Sara',
          position: 'cashier',
          attendance: StaffAttendance(open: false),
        ),
      );
      await tester.pumpWidget(app(const ClockInScreen()));
      await tester.pump();
      expect(find.text('Welcome, Sara'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clock-in-button')));
      for (var i = 0; i < 100 && session.staff!.attendance!.open != true; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(session.staff!.attendance!.open, isTrue);
      expect(api.pushed.single['event_type'], 'staff.clock_in');
    });
  });

  group('staff-status', () {
    Future<void> pumpGuard(WidgetTester tester) async {
      await tester.pumpWidget(
        app(const StaffSessionGuard(child: Text('selling'))),
      );
      await tester.pump();
    }

    setUp(() async {
      await session.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', position: 'cashier'),
      );
    });

    testWidgets('an inactive person is logged out within 60 s', (tester) async {
      api.active = {9};
      await pumpGuard(tester);
      expect(session.staff, isNotNull);
      await tester.pump(const Duration(seconds: 61));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(api.statusCalls, greaterThanOrEqualTo(1));
      expect(session.staff, isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(container.read(signOutNoticeProvider), 'Sara');
    });

    testWidgets('an active person stays; offline changes nothing', (
      tester,
    ) async {
      api.active = {4};
      await pumpGuard(tester);
      await tester.pump(const Duration(seconds: 61));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(session.staff, isNotNull);
      api.statusError = ApiException(message: 'offline', isNetwork: true);
      await tester.pump(const Duration(seconds: 61));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(session.staff, isNotNull);
    });
  });

  group('shift-end reminder', () {
    test('Muscat time, after the shift opened', () {
      // 22:00 Muscat = 18:00 UTC.
      final opened = DateTime.utc(2026, 10, 4, 5);
      expect(
        ShiftEndReminder.dueSince(
          hhmm: '22:00',
          openedAt: opened,
          now: DateTime.utc(2026, 10, 4, 17, 59),
        ),
        isNull,
      );
      expect(
        ShiftEndReminder.dueSince(
          hhmm: '22:00',
          openedAt: opened,
          now: DateTime.utc(2026, 10, 4, 18, 0),
        ),
        DateTime.utc(2026, 10, 4, 18, 0),
      );
      // Still due after midnight Muscat until the shift closes.
      expect(
        ShiftEndReminder.dueSince(
          hhmm: '22:00',
          openedAt: opened,
          now: DateTime.utc(2026, 10, 4, 21, 30),
        ),
        DateTime.utc(2026, 10, 4, 18, 0),
      );
      // A shift opened after today's time is not reminded until tomorrow.
      expect(
        ShiftEndReminder.dueSince(
          hhmm: '22:00',
          openedAt: DateTime.utc(2026, 10, 4, 19),
          now: DateTime.utc(2026, 10, 4, 20),
        ),
        isNull,
      );
      expect(ShiftEndReminder.parse(''), isNull);
      expect(ShiftEndReminder.parse('25:00'), isNull);
    });

    test('repeats every 15 minutes', () {
      final due = DateTime.utc(2026, 10, 4, 18);
      expect(
        ShiftEndReminder.shouldAlert(dueSince: due, lastAlert: null, now: due),
        isTrue,
      );
      expect(
        ShiftEndReminder.shouldAlert(
          dueSince: due,
          lastAlert: due,
          now: due.add(const Duration(minutes: 14)),
        ),
        isFalse,
      );
      expect(
        ShiftEndReminder.shouldAlert(
          dueSince: due,
          lastAlert: due,
          now: due.add(const Duration(minutes: 15)),
        ),
        isTrue,
      );
    });

    testWidgets('banner and sound while the own shift is open', (tester) async {
      await session.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', position: 'cashier'),
      );
      await session.saveOpenShift(
        OpenShiftData(
          uuid: 's-1',
          openingCashBaisas: 0,
          openedAt: DateTime.utc(2026, 10, 4, 5),
          staffId: 4,
        ),
      );
      await session.saveStaffSettings({'shift_end_reminder_at': '22:00'});
      api.active = {4};
      now = DateTime.utc(2026, 10, 4, 17, 50);
      await tester.pumpWidget(
        app(const StaffSessionGuard(child: Text('selling'))),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('shift-end-reminder')), findsNothing);
      now = DateTime.utc(2026, 10, 4, 18, 0, 10);
      await tester.pump(StaffSessionGuard.reminderTick);
      expect(find.byKey(const ValueKey('shift-end-reminder')), findsOneWidget);
      expect(alerts, hasLength(1));
      // Not again within 15 minutes, then again.
      now = DateTime.utc(2026, 10, 4, 18, 10);
      await tester.pump(StaffSessionGuard.reminderTick);
      expect(alerts, hasLength(1));
      now = DateTime.utc(2026, 10, 4, 18, 15, 20);
      await tester.pump(StaffSessionGuard.reminderTick);
      expect(alerts, hasLength(2));
      // Closing the shift ends it.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await tester.runAsync(
        () => container
            .read(sessionControllerProvider.notifier)
            .markShiftClosed(),
      );
      now = DateTime.utc(2026, 10, 4, 18, 31);
      await tester.pump(StaffSessionGuard.reminderTick);
      expect(find.byKey(const ValueKey('shift-end-reminder')), findsNothing);
      expect(alerts, hasLength(2));
    });
  });
}
