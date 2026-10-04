import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/auth_wire.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/log_expense_screen.dart';
import 'package:pos_machine/screens/shift_close_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/expense_restock_payload.dart';
import 'package:pos_machine/services/expense_restock_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:pos_machine/services/shift_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 fix order 1 — F6/F7 [WIRE] pay-outs belong to this till's
/// open drawer shift (refused without one), an unclear pay-out stays in the
/// outbox under its own id, and the shift close waits for it like a sale;
/// L8 [WIRE] a close refused `shift_reopened` is rebuilt with the server's
/// re-open count and sent again.
class _Api implements PosApiService {
  bool offline = false;
  ApiException? refusal;
  final pushed = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)? reply;

  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    if (offline) {
      throw ApiException(message: 'offline', code: 'network', isNetwork: true);
    }
    if (refusal != null) throw refusal!;
    pushed.addAll(events);
    return {
      'results':
          reply?.call(events) ??
          [
            for (final e in events)
              {
                'client_event_id': e['client_event_id'],
                'status': 'processed',
                'result': <String, dynamic>{},
              },
          ],
    };
  }

  final shiftReads = <int?>[];

  @override
  Future<OpenShiftData?> fetchCurrentShift({
    int? staffId,
    bool sharedStaffOnly = false,
  }) async {
    shiftReads.add(staffId);
    if (offline) {
      throw ApiException(message: 'offline', code: 'network', isNetwork: true);
    }
    return OpenShiftData(
      uuid: 'shift-1',
      openingCashBaisas: 2000,
      openedAt: DateTime.utc(2026, 10, 4, 5),
      staffId: 4,
    );
  }

  @override
  Future<ApproverVerification?> verifyApprover(String pin) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

class _Shifts extends ShiftService {
  _Shifts(super.api);
  final events = <Map<String, dynamic>>[];
  final reopened = <int>[];

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
    if (reopened.isNotEmpty) throw ShiftReopenedException(reopened.removeAt(0));
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
  late AppDatabase db;
  final opened = DateTime.utc(2026, 10, 4, 5);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'print_receipts': false});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = SessionService(const FlutterSecureStorage(), prefs);
    api = _Api();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await session.saveStaff(
      const StaffSessionData(id: 4, name: 'Sara', position: 'manager'),
    );
  });
  tearDown(() => db.close());

  Future<void> openShift() => session.saveOpenShift(
    OpenShiftData(
      uuid: 'shift-1',
      openingCashBaisas: 2000,
      openedAt: opened,
      staffId: 4,
    ),
  );

  /// Pump until no spinner has shown for a few frames (the close and the
  /// pay-out run real Drift work, slower under load).
  Future<void> settle(WidgetTester tester) async {
    var idle = 0;
    for (var i = 0; i < 1000 && idle < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      idle = find.byType(CircularProgressIndicator).evaluate().isEmpty
          ? idle + 1
          : 0;
    }
  }

  Widget app(Widget home, {ShiftService? shifts}) => ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sessionServiceProvider.overrideWithValue(session),
      apiServiceProvider.overrideWithValue(api),
      appDatabaseProvider.overrideWithValue(db),
      catalogProvider.overrideWith((ref) => const Stream.empty()),
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      if (shifts != null) shiftServiceProvider.overrideWithValue(shifts),
    ],
    child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: home,
    ),
  );

  Future<void> payOut(WidgetTester tester, String digits) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const LogExpenseScreen()));
    await tester.pump();
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.tap(find.byType(FilledButton).last);
    await settle(tester);
  }

  group('F6 — a pay-out belongs to this till\'s open drawer', () {
    test('the event names the drawer shift (pay-outs only)', () {
      final payout = buildExpenseLogEvent(
        category: 'other',
        amountBaisas: 1500,
        paidFromDrawer: true,
        shiftUuid: 'shift-1',
      );
      expect(payout['payload']['shift_uuid'], 'shift-1');
      final expense = buildExpenseLogEvent(
        category: 'other',
        amountBaisas: 1500,
        shiftUuid: 'shift-1',
      );
      expect(expense['payload'], isNot(contains('shift_uuid')));
    });

    testWidgets('refused when no drawer shift is open on this till', (
      tester,
    ) async {
      await payOut(tester, '1500');
      expect(
        find.text('Open a drawer shift on this till before paying out cash.'),
        findsOneWidget,
      );
      expect(api.pushed, isEmpty);
    });

    testWidgets('sent with the open shift\'s uuid', (tester) async {
      await openShift();
      await payOut(tester, '1500');
      final event = api.pushed.single;
      expect(event['event_type'], 'expense.log');
      expect(event['payload']['paid_from_drawer'], isTrue);
      expect(event['payload']['shift_uuid'], 'shift-1');
      expect(event['payload']['amount_baisas'], 1500);
    });
  });

  group('F7 — an unclear pay-out is kept and blocks the close', () {
    test('a lost reply keeps the same event in the outbox', () async {
      final outbox = OrderSyncRepository(api, db);
      final service = ExpenseRestockService(
        api,
        queue: (key, event) => outbox.enqueueEvent(key, event),
      );
      api.offline = true;
      final recorded = await service.logExpense(
        category: 'other',
        amountBaisas: 900,
        paidFromDrawer: true,
        shiftUuid: 'shift-1',
      );
      expect(recorded, isFalse);
      final unsent = await outbox.unsentPayouts('shift-1');
      expect(unsent.single.amountBaisas, 900);
      final kept = (jsonDecode(unsent.single.row.eventsJson) as List).single;
      expect(unsent.single.row.orderUuid, 'payout:${kept['client_event_id']}');
      // Back online: the flush sends that same event.
      api.offline = false;
      await outbox.flush();
      expect(api.pushed.single['client_event_id'], kept['client_event_id']);
      expect(await outbox.unsentPayouts('shift-1'), isEmpty);
    });

    test('a structured refusal is final: nothing is kept', () async {
      final outbox = OrderSyncRepository(api, db);
      final service = ExpenseRestockService(
        api,
        queue: (key, event) => outbox.enqueueEvent(key, event),
      );
      api.refusal = ApiException(
        message: 'Bad category',
        statusCode: 422,
        code: 'invalid_category',
        hasStructuredErrorCode: true,
      );
      await expectLater(
        service.logExpense(
          category: 'other',
          amountBaisas: 900,
          paidFromDrawer: true,
          shiftUuid: 'shift-1',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(await outbox.allRows(), isEmpty);
    });

    Future<void> payoutRow(String shiftUuid, {String id = 'p-1'}) =>
        db.enqueueOutbox(
          OrderOutboxCompanion.insert(
            orderUuid: 'payout:$id',
            eventsJson: jsonEncode([
              buildExpenseLogEvent(
                category: 'other',
                amountBaisas: 1250,
                paidFromDrawer: true,
                shiftUuid: shiftUuid,
                newUuid: () => id,
              ),
            ]),
            createdAt: opened.add(const Duration(hours: 1)),
          ),
        );

    Future<_Shifts> close(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shifts = _Shifts(api);
      await tester.pumpWidget(app(const ShiftCloseScreen(), shifts: shifts));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('5').last);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      await settle(tester);
      return shifts;
    }

    testWidgets('an unsent pay-out of this shift blocks the close', (
      tester,
    ) async {
      await openShift();
      await payoutRow('shift-1');
      api.offline = true; // the flush cannot send it
      final shifts = await close(tester);
      expect(find.byKey(const ValueKey('shift-close-blocked')), findsOneWidget);
      expect(find.text('1 pay-out still sending'), findsOneWidget);
      expect(find.text('Pay-out 1.250 OMR'), findsOneWidget);
      expect(shifts.events, isEmpty);
    });

    testWidgets('another shift\'s pay-out does not block it', (tester) async {
      await openShift();
      await payoutRow('shift-0');
      api.offline = true;
      // Offline closes are refused anyway; go online but keep the other
      // shift's pay-out unsent (the server leaves it failed-retryable).
      api.offline = false;
      api.reply = (events) => [
        for (final e in events)
          {
            'client_event_id': e['client_event_id'],
            'status': e['event_type'] == 'expense.log' ? 'failed' : 'processed',
            'result': <String, dynamic>{'error': 'later'},
          },
      ];
      final shifts = await close(tester);
      expect(find.byKey(const ValueKey('shift-close-blocked')), findsNothing);
      expect(shifts.events, hasLength(1));
    });
  });

  group('L8 — shift_reopened', () {
    test('the refusal carries the current count', () async {
      api.reply = (events) => [
        {
          'client_event_id': events.single['client_event_id'],
          'status': 'failed',
          'duplicate': true, // Part A: a repeat of the processed close
          'result': {
            'error': 'The shift was re-opened.',
            'code': 'shift_reopened',
            'reopen_count': 2,
          },
        },
      ];
      await expectLater(
        ShiftService(api).close(shiftUuid: 'shift-1', closingCashBaisas: 0),
        throwsA(
          isA<ShiftReopenedException>().having(
            (e) => e.reopenCount,
            'reopenCount',
            2,
          ),
        ),
      );
    });

    testWidgets('the close is rebuilt under the new fixed id and sent again', (
      tester,
    ) async {
      await openShift();
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shifts = _Shifts(api)..reopened.add(2);
      await tester.pumpWidget(app(const ShiftCloseScreen(), shifts: shifts));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      await settle(tester);
      expect(shifts.events, hasLength(2));
      expect(
        shifts.events[0]['client_event_id'],
        shiftCloseEventId('shift-1', reopenCount: 0),
      );
      expect(
        shifts.events[1]['client_event_id'],
        shiftCloseEventId('shift-1', reopenCount: 2),
      );
      // Closed: the result step shows.
      expect(find.widgetWithText(FilledButton, 'Close shift'), findsNothing);
    });
  });

  testWidgets(
    'closing another cashier\'s drawer never names them in the shift read',
    (tester) async {
      // Sara (supervisor: shift.close_other ticked) closes Omar's drawer;
      // the server refuses a staff_id the closer's token does not name.
      await session.saveStaff(
        const StaffSessionData(
          id: 4,
          name: 'Sara',
          position: 'supervisor',
          staffToken: 'tok-4',
        ),
        login: true,
      );
      addTearDown(StaffTokenHolder.clear);
      await session.saveOpenShift(
        OpenShiftData(
          uuid: 'shift-1',
          openingCashBaisas: 2000,
          openedAt: opened,
          staffId: 9,
        ),
      );
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shifts = _Shifts(api);
      await tester.pumpWidget(app(const ShiftCloseScreen(), shifts: shifts));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      await settle(tester);
      expect(shifts.events, hasLength(1));
      expect(api.shiftReads, isNotEmpty);
      expect(api.shiftReads, everyElement(isNull));
      // The close names its closer, with the closer's own token.
      final payload = shifts.events.single['payload'] as Map;
      expect(payload['closed_by_staff_id'], 4);
      expect(payload['staff_token'], 'tok-4');
    },
  );

  testWidgets('closing one\'s own drawer reads by the closer first', (
    tester,
  ) async {
    await openShift();
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shifts = _Shifts(api);
    await tester.pumpWidget(app(const ShiftCloseScreen(), shifts: shifts));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await settle(tester);
    expect(shifts.events, hasLength(1));
    expect(api.shiftReads.first, 4);
  });
}
