import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/qr_checkout/checkout_close_hold.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/screens/shift_close_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:pos_machine/services/shift_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'f27_saved_gps_recovery_test.dart' show oldPending;
import 'qr_checkout_fakes.dart' show checkoutTime;

/// LAUNCH-P5 fix order 2 — T4 (QR and table-workspace payments of this
/// till hold the shift close and go into `order_uuids`; a pending one is
/// pushed first) and T5 (a parked sale the server names as missing is
/// un-parked and pushed; one that stays parked is shown as parked, with a
/// Retry — never "still sending").
class _Api implements PosApiService {
  final pushed = <Map<String, dynamic>>[];

  /// The status the server answers each pushed event with.
  String status = 'processed';

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
            'status': status,
            // A paid sale's ACK (a standalone QR pay row needs "paid").
            'result': status == 'processed'
                ? <String, dynamic>{'status': 'paid'}
                : {
                    'error':
                        'Could not save this update. Retry the same request.',
                  },
          },
      ],
    };
  }

  @override
  Future<OpenShiftData?> fetchCurrentShift({
    int? staffId,
    bool sharedStaffOnly = false,
  }) async => null;

  @override
  Future<ApproverVerification?> verifyApprover(String pin) async => null;

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

/// A gateway that answers the saved order.pay of a pending attempt.
class _Gateway implements CheckoutGateway {
  final pushed = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> push(Map<String, dynamic> event) async {
    pushed.add(event);
    return [
      {
        'client_event_id': event['client_event_id'],
        'status': 'processed',
        'result': {'status': 'paid', 'order_id': 12, 'receipt_number': 'R-9'},
      },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

Future<Database> _journal() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await SqliteCheckoutStore.createSchema(db);
  return db;
}

CheckoutAttempt _attempt(String id, String order, String state) =>
    CheckoutAttempt(
      id: id,
      orderUuid: order,
      state: state,
      createdAt: checkoutTime.add(const Duration(hours: 1)),
      reference: 'REF-$order',
      receiptNumber: state == 'paid' ? 'R-1' : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final opened = checkoutTime.subtract(const Duration(hours: 1));

  group('T4 — the checkout journal at the close', () {
    test('unsent attempts hold; paid and unsent go into order_uuids', () async {
      final db = await _journal();
      addTearDown(db.close);
      final store = SqliteCheckoutStore(db, 'scope');
      await store.create(oldPending()); // the one open attempt of the scope
      for (final a in [
        _attempt('p-1', 'qr-paid', 'paid'),
        _attempt('r-1', 'qr-released', 'released'),
      ]) {
        await db.insert('qr_checkout_attempts', {
          'id': a.id,
          'scope': 'scope',
          'state': a.state,
          'payload': jsonEncode(a.json),
        });
      }
      // Another till's journal scope and an older shift's sale are ignored.
      await db.insert('qr_checkout_attempts', {
        'id': 'o-1',
        'scope': 'other',
        'state': 'paid',
        'payload': jsonEncode(_attempt('o-1', 'qr-other', 'paid').json),
      });
      final hold = CheckoutCloseHold(db: db, scope: 'scope');
      final result = await hold.since(opened);
      expect(result.unsent.map((a) => a.orderUuid), ['qr-bill']);
      expect(result.orderUuids, unorderedEquals(['qr-bill', 'qr-paid']));
      final later = await hold.since(checkoutTime.add(const Duration(days: 1)));
      expect(later.unsent, isEmpty);
      expect(later.orderUuids, isEmpty);
    });

    test('every money state holds the close', () {
      expect(CheckoutCloseHold.holdingStates, {
        'capturing',
        'pending',
        'uncertain',
        'refused',
      });
    });

    test(
      'flush pushes the pending attempt (same event) and settles it',
      () async {
        final db = await _journal();
        addTearDown(db.close);
        final store = SqliteCheckoutStore(db, 'scope');
        await store.create(oldPending());
        final gateway = _Gateway();
        final hold = CheckoutCloseHold(
          db: db,
          scope: 'scope',
          resume: () => QrCheckoutController(
            gateway: gateway,
            store: store,
            captureCard: refuseCheckoutCapture,
            captureBank: refuseCheckoutCapture,
            authorizeGift: () async => false,
          ),
        );
        await hold.flush();
        expect(gateway.pushed.single['client_event_id'], oldPending().id);
        final result = await hold.since(opened);
        expect(result.unsent, isEmpty);
        expect(result.orderUuids, ['qr-bill']);
      },
    );
  });

  group('T5 — parked sales in the outbox', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> parkedSale(String uuid) async {
      final at = opened.add(const Duration(hours: 1));
      await db.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: '$uuid:pay',
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
      await db.markOutboxServerRejection(
        '$uuid:pay',
        1,
        OrderSyncRepository.maxServerRejections,
        'Could not save this update. Retry the same request.',
      );
    }

    test(
      'listed as parked, not unsent; un-parked and pushed by uuid',
      () async {
        final api = _Api();
        final repo = OrderSyncRepository(api, db);
        await parkedSale('o-2');
        final before = await repo.paidSalesSince(opened);
        expect(before.unsent, isEmpty);
        expect(before.parked.single.orderUuid, 'o-2:pay');
        expect(before.orderUuids, ['o-2']);
        // A flush skips it...
        await repo.flush();
        expect(api.pushed, isEmpty);
        // ...the server's missing list un-parks and pushes it.
        expect(await repo.unparkAndPush(['o-9']), 0);
        expect(await repo.unparkAndPush(['o-2']), 1);
        expect(api.pushed.single['client_event_id'], 'pay-o-2');
        final after = await repo.paidSalesSince(opened);
        expect(after.parked, isEmpty);
        expect(after.unsent, isEmpty);
      },
    );
  });

  group('the close screen', () {
    late SharedPreferences prefs;
    late SessionService session;
    late _Api api;
    late _Shifts shifts;
    late AppDatabase db;
    CheckoutCloseHold? checkout;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'print_receipts': false});
      FlutterSecureStorage.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      session = SessionService(const FlutterSecureStorage(), prefs);
      api = _Api();
      shifts = _Shifts(api);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      checkout = null;
      await session.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', position: 'manager'),
      );
      await session.saveOpenShift(
        OpenShiftData(
          uuid: 'shift-1',
          openingCashBaisas: 2000,
          openedAt: opened,
          staffId: 4,
        ),
      );
    });
    tearDown(() => db.close());

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

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2200);
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
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
            checkoutCloseHoldProvider.overrideWithValue(() async => checkout),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: ShiftCloseScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      await settle(tester);
    }

    testWidgets('a QR payment still sending holds the close', (tester) async {
      final journal = await tester.runAsync(_journal);
      addTearDown(() => tester.runAsync(journal!.close));
      await tester.runAsync(
        () => SqliteCheckoutStore(journal!, 'scope').create(oldPending()),
      );
      checkout = CheckoutCloseHold(db: journal!, scope: 'scope');
      await pump(tester);
      await submit(tester);
      expect(find.byKey(const ValueKey('shift-close-blocked')), findsOneWidget);
      expect(find.text('1 sale still sending'), findsOneWidget);
      expect(find.text('QR payment T-F27-OLD'), findsOneWidget);
      expect(shifts.events, isEmpty);
    });

    testWidgets('a settled QR payment goes into order_uuids', (tester) async {
      final journal = await tester.runAsync(_journal);
      addTearDown(() => tester.runAsync(journal!.close));
      final paid = _attempt('p-1', 'qr-paid', 'paid');
      await tester.runAsync(
        () => journal!.insert('qr_checkout_attempts', {
          'id': paid.id,
          'scope': 'scope',
          'state': paid.state,
          'payload': jsonEncode(paid.json),
        }),
      );
      checkout = CheckoutCloseHold(db: journal!, scope: 'scope');
      await pump(tester);
      await submit(tester);
      expect(
        shifts.events.single['client_event_id'],
        shiftCloseEventId('shift-1'),
      );
      expect(shifts.events.single['payload']['order_uuids'], ['qr-paid']);
    });

    testWidgets(
      'unsynced_sales: the named parked sale is un-parked and pushed',
      (tester) async {
        await tester.runAsync(() async {
          final at = opened.add(const Duration(hours: 1));
          await db.enqueueOutbox(
            OrderOutboxCompanion.insert(
              orderUuid: 'o-2:pay',
              eventsJson: jsonEncode([
                {
                  'client_event_id': 'pay-o-2',
                  'event_type': 'order.pay',
                  'client_timestamp': at.toIso8601String(),
                  'payload': {'order_uuid': 'o-2'},
                },
              ]),
              createdAt: at,
            ),
          );
          await db.markOutboxServerRejection(
            'o-2:pay',
            1,
            OrderSyncRepository.maxServerRejections,
            'transient',
          );
        });
        shifts.missing.add(['o-2']);
        await pump(tester);
        await submit(tester);
        expect(api.pushed.map((e) => e['client_event_id']), ['pay-o-2']);
        expect(shifts.events, hasLength(2));
        expect(shifts.events[1]['payload']['order_uuids'], ['o-2']);
        expect(find.byKey(const ValueKey('shift-close-blocked')), findsNothing);
      },
    );

    testWidgets('a sale that stays parked says parked and offers Retry', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final at = opened.add(const Duration(hours: 1));
        await db.enqueueOutbox(
          OrderOutboxCompanion.insert(
            orderUuid: 'o-3:pay',
            eventsJson: jsonEncode([
              {
                'client_event_id': 'pay-o-3',
                'event_type': 'order.pay',
                'client_timestamp': at.toIso8601String(),
                'payload': {'order_uuid': 'o-3'},
              },
            ]),
            createdAt: at,
          ),
        );
        await db.markOutboxServerRejection(
          'o-3:pay',
          1,
          OrderSyncRepository.maxServerRejections,
          'transient',
        );
      });
      api.status = 'failed'; // the push fails again: parked again
      shifts.missing.addAll([
        ['o-3'],
        ['o-3'],
      ]);
      await pump(tester);
      await submit(tester);
      expect(find.byKey(const ValueKey('shift-close-parked')), findsOneWidget);
      expect(find.text('1 sale parked after server errors'), findsOneWidget);
      expect(find.text('1 sale still sending'), findsNothing);
      expect(
        find.byKey(const ValueKey('shift-close-retry-parked')),
        findsOneWidget,
      );
      // Retry once the server is back: sent, then the close goes through.
      api.status = 'processed';
      await tester.tap(find.byKey(const ValueKey('shift-close-retry-parked')));
      await settle(tester);
      expect(shifts.events, hasLength(3));
      expect(find.byKey(const ValueKey('shift-close-parked')), findsNothing);
      expect(api.pushed.last['client_event_id'], 'pay-o-3');
    });
  });
}
