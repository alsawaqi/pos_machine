import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/manager_auth.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/shift_close_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:pos_machine/services/shift_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 C5 — the shift close screen: flush first, block while a paid
/// sale is unsent, "needs the internet" offline, the fixed close event with
/// its closer and orders, `unsynced_sales`, closing another cashier's drawer,
/// and clock out with the close.
class _Api implements PosApiService {
  bool offline = false;
  final pushed = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    if (offline) {
      throw ApiException(message: 'offline', code: 'network', isNetwork: true);
    }
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
  Future<ApproverVerification?> verifyApprover(String pin) async => null;

  int reopenCount = 0;
  int shiftLookups = 0;
  @override
  Future<OpenShiftData?> fetchCurrentShift({
    int? staffId,
    bool sharedStaffOnly = false,
  }) async {
    shiftLookups++;
    if (offline) {
      throw ApiException(message: 'offline', code: 'network', isNetwork: true);
    }
    return OpenShiftData(
      uuid: 'shift-1',
      openingCashBaisas: 2000,
      openedAt: DateTime.utc(2026, 10, 4, 5),
      staffId: staffId ?? 7,
      reopenCount: reopenCount,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

class _Shifts extends ShiftService {
  _Shifts(super.api);
  final events = <Map<String, dynamic>>[];
  final missing = <List<String>>[];

  @override
  Future<ShiftCloseResult> close({
    required String shiftUuid,
    required int closingCashBaisas,
    int? closedByStaffId,
    List<String> orderUuids = const <String>[],
    Map<String, dynamic>? authorization,
    int reopenCount = 0,
    Map<String, dynamic>? event,
  }) async {
    events.add(event!);
    if (missing.isNotEmpty) {
      throw ShiftUnsyncedSalesException(missing.removeAt(0));
    }
    return const ShiftCloseResult(
      expectedCashBaisas: 5000,
      varianceBaisas: 0,
      summaryJson: {},
    );
  }
}

void main() {
  late SharedPreferences prefs;
  late SessionService session;
  late _Api api;
  late _Shifts shifts;
  late AppDatabase db;
  var online = true;
  final opened = DateTime.utc(2026, 10, 4, 5);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'print_receipts': false});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = SessionService(const FlutterSecureStorage(), prefs);
    api = _Api();
    shifts = _Shifts(api);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    online = true;
    await session.saveStaff(
      const StaffSessionData(
        id: 4,
        name: 'Sara',
        position: 'cashier',
        attendance: StaffAttendance(open: true, uuid: 'att-1'),
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> shift({int staffId = 4}) => session.saveOpenShift(
    OpenShiftData(
      uuid: 'shift-1',
      openingCashBaisas: 2000,
      openedAt: opened,
      staffId: staffId,
    ),
  );

  Future<void> paidSale(String uuid, {bool synced = false}) async {
    final at = opened.add(const Duration(hours: 1));
    await db.enqueueOutbox(
      OrderOutboxCompanion.insert(
        orderUuid: uuid,
        eventsJson: jsonEncode([
          {
            'client_event_id': 'pay-$uuid',
            'event_type': 'order.pay',
            'client_timestamp': at.toIso8601String(),
            'payload': {'order_uuid': uuid},
          },
        ]),
        createdAt: at,
      ),
    );
    if (synced) await db.markOutboxSynced(uuid, at);
  }

  Future<void> pump(WidgetTester tester, {bool forced = false}) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionServiceProvider.overrideWithValue(session),
          apiServiceProvider.overrideWithValue(api),
          appDatabaseProvider.overrideWithValue(db),
          shiftServiceProvider.overrideWithValue(shifts),
          connectivityProvider.overrideWith((ref) => Stream.value(online)),
        ],
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: ShiftCloseScreen(forcedHandover: forced),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, [int rounds = 30]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> count(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await settle(tester);
  }

  testWidgets('an unsent paid sale blocks the close and is listed', (
    tester,
  ) async {
    await shift();
    await paidSale('o-1', synced: true);
    await paidSale('o-2');
    api.offline = true; // the flush cannot send it
    await pump(tester);
    await count(tester, '5');
    await submit(tester);
    expect(find.byKey(const ValueKey('shift-close-blocked')), findsOneWidget);
    expect(find.text('1 sale still sending'), findsOneWidget);
    expect(shifts.events, isEmpty);
  });

  testWidgets('offline: closing needs the internet', (tester) async {
    online = false;
    await shift();
    await pump(tester);
    await submit(tester);
    expect(
      find.text('Closing needs the internet. Connect and try again.'),
      findsOneWidget,
    );
    expect(shifts.events, isEmpty);
  });

  testWidgets('the close names its closer and orders; clock out too', (
    tester,
  ) async {
    await shift();
    await paidSale('o-1', synced: true);
    await paidSale('o-2');
    api.reopenCount = 1;
    await pump(tester);
    expect(find.byKey(const ValueKey('shift-close-clock-out')), findsOneWidget);
    await count(tester, '5');
    await submit(tester);
    final event = shifts.events.single;
    // The re-open count is read fresh from the server for the fixed id.
    expect(api.shiftLookups, greaterThanOrEqualTo(1));
    expect(
      event['client_event_id'],
      shiftCloseEventId('shift-1', reopenCount: 1),
    );
    expect(event['payload']['closed_by_staff_id'], 4);
    expect(event['payload']['order_uuids'], ['o-1', 'o-2']);
    expect(event['payload'].containsKey('authorization'), isFalse);
    // The flush sent the unsent sale first.
    expect(api.pushed.map((e) => e['event_type']), contains('order.pay'));
    // Clocked out with the close (default yes).
    expect(
      api.pushed
          .where((e) => e['event_type'] == 'staff.clock_out')
          .single['payload']['attendance_uuid'],
      'att-1',
    );
    expect(session.staff!.attendance!.open, isFalse);
  });

  testWidgets('unsynced_sales: flush, retry once, then list what is missing', (
    tester,
  ) async {
    await shift();
    shifts.missing.addAll([
      ['o-9'],
      ['o-9'],
    ]);
    await pump(tester);
    await count(tester, '7');
    await submit(tester);
    expect(shifts.events, hasLength(2));
    // The retry goes under the same fixed id (the server replaces a refused
    // close's payload).
    expect(
      shifts.events[1]['client_event_id'],
      shifts.events[0]['client_event_id'],
    );
    expect(find.text('1 sale still sending'), findsOneWidget);
    expect(find.text('Sale o-9'), findsOneWidget);
    await submit(tester);
    expect(shifts.events, hasLength(3));
    expect(
      shifts.events[2]['client_event_id'],
      shifts.events[0]['client_event_id'],
    );
  });

  testWidgets('closing another cashier\'s drawer asks for an approver', (
    tester,
  ) async {
    await shift(staffId: 7);
    await pump(tester);
    await submit(tester);
    expect(find.byType(ManagerApprovalSheet), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
    expect(find.text('Approval was not given.'), findsOneWidget);
    expect(shifts.events, isEmpty);
  });

  testWidgets('a supervisor closes another drawer with the tick', (
    tester,
  ) async {
    await session.saveStaff(
      const StaffSessionData(id: 4, name: 'Sara', position: 'supervisor'),
    );
    await shift(staffId: 7);
    await pump(tester);
    await submit(tester);
    expect(find.byType(ManagerApprovalSheet), findsNothing);
    final block = shifts.events.single['payload']['authorization'] as Map;
    expect(block['action'], 'shift.close_other');
    expect(block['mode'], 'position');
    expect(block['actor_staff_id'], 4);
  });
}
