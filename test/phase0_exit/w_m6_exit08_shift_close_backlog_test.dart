// W-M6 / EXIT-08 — Shift closes while sale batches are still queued: the
// queued revenue survives the close untouched and a later flush drains it.
//
// Contract (PHASE_0_EXIT_COVERAGE_MATRIX.md Part B, EXIT-08 + authoritative
// carve-out): assert durability + processed-or-visible only; final Z/EOD
// attribution is explicitly OUT of scope (orders carry no shift_id until
// DB-001 — temporal attribution stands).
//
// Investigation (read-only, 2026-08-13) — the machine's shift-close path:
// staff_pos_screen.dart _closeShiftThenLogout → ShiftCloseScreen._close →
// ShiftService.close (a shift.close event via /device/sync/push) → on the
// settled result, session.saveLastShiftSummary + markShiftClosed (prefs
// clearShift). Nothing in that path reads or writes the order outbox; this
// test proves it end-to-end by driving the REAL ShiftCloseScreen against a
// real in-memory Drift outbox holding two money batches.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/shift_close_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'queued sale batches survive a real shift close untouched and a later '
    'flush drains them exactly once',
    (tester) async {
      // A portrait terminal-sized surface so the count step's keypad and
      // submit button are on-screen (the default 800x600 test viewport cuts
      // the scrollable count step off below the fold).
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // print_receipts off keeps the (fail-safe) printer plugin out of the
      // deterministic close path.
      SharedPreferences.setMockInitialValues({'print_receipts': false});
      final preferences = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), preferences);
      await session.saveStaff(const StaffSessionData(id: 8, name: 'Cashier B'));
      await session.saveOpenShift(OpenShiftData(
        uuid: 'shift-2026-08-13-001',
        openingCashBaisas: 10000,
        openedAt: DateTime.utc(2026, 8, 13, 8),
        staffId: 8,
      ));

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final adapter = _ShiftAwareAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
        ..httpClientAdapter = adapter;
      final api = PosApiService(tokenGetter: () => 'device-token', dio: dio);
      final repository = OrderSyncRepository(api, db);

      addTearDown(() async {
        dio.close(force: true);
        await db.close();
      });

      // Two money batches are still queued (offline sales) when the cashier
      // closes the drawer.
      await _enqueueSale(db, 'queued-sale-1',
          createdAt: DateTime.utc(2026, 8, 13, 9, 0));
      await _enqueueSale(db, 'queued-sale-2',
          createdAt: DateTime.utc(2026, 8, 13, 9, 30));
      final before = await db.select(db.orderOutbox).get();
      expect(before, hasLength(2));

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            sessionServiceProvider.overrideWithValue(session),
            appDatabaseProvider.overrideWithValue(db),
            apiServiceProvider.overrideWithValue(api),
            orderSyncRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );

      // Enter the real close screen the way the POS does (pushed route).
      unawaited(navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const ShiftCloseScreen()),
      ));
      await _pumpFrames(tester);
      expect(find.widgetWithText(FilledButton, 'Close shift'), findsOneWidget);

      // Count the drawer (10.000 OMR) and submit the close.
      await tester.tap(find.text('1'));
      await tester.pump();
      for (var zeros = 0; zeros < 2; zeros++) {
        await tester.tap(find.text('00'));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      for (var frame = 0;
          frame < 40 && find.text('Done').evaluate().isEmpty;
          frame++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('Done'), findsOneWidget,
          reason: 'the close must settle and show the result step');
      expect(find.text('Drawer balanced'), findsOneWidget);

      // The close pushed exactly one event — shift.close — and never touched
      // the queued sale batches.
      expect(adapter.requests, hasLength(1));
      final closeEvent = adapter.requests.single.single;
      expect(closeEvent['event_type'], 'shift.close');
      final closePayload =
          (closeEvent['payload'] as Map).cast<String, dynamic>();
      expect(closePayload['shift_uuid'], 'shift-2026-08-13-001');
      expect(closePayload['closing_cash_baisas'], 10000);
      expect(adapter.orderEventIds, isEmpty,
          reason: 'the close path must not flush or mutate sale batches');

      final afterClose = await db.select(db.orderOutbox).get();
      expect(afterClose, before,
          reason: 'every queued sale row must survive the close untouched '
              '(same events, attempts, rejections, still pending)');

      // Finish the close: the shift record is cleared, sales remain queued.
      await tester.tap(find.text('Done'));
      await _pumpFrames(tester);
      expect(session.openShift, isNull,
          reason: 'the settled close clears the cached shift');
      expect(await db.pendingOutbox(), hasLength(2));

      // A later flush drains the surviving batches — exactly once each.
      expect(await _flush(tester, repository), 2);
      expect(await db.pendingOutbox(), isEmpty);
      final sent = adapter.orderEventIds;
      expect(
        {for (final id in sent) id: sent.where((s) => s == id).length},
        {
          'create-queued-sale-1': 1,
          'pay-queued-sale-1': 1,
          'create-queued-sale-2': 1,
          'pay-queued-sale-2': 1,
        },
        reason: 'each surviving sale event drains exactly once',
      );

      // Dispose the provider subscription before the database teardown.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

/// One durable money batch (order.create + order.pay, integer baisas).
Future<void> _enqueueSale(
  AppDatabase db,
  String orderUuid, {
  required DateTime createdAt,
}) =>
    db.enqueueOutbox(OrderOutboxCompanion.insert(
      orderUuid: orderUuid,
      eventsJson: jsonEncode([
        {
          'client_event_id': 'create-$orderUuid',
          'event_type': 'order.create',
          'client_timestamp': createdAt.toIso8601String(),
          'payload': {
            'order': {
              'uuid': orderUuid,
              'total_baisas': 2500,
              'lines': [
                {'product_id': 11, 'qty': 1, 'unit_price_baisas': 2500},
              ],
            },
          },
        },
        {
          'client_event_id': 'pay-$orderUuid',
          'event_type': 'order.pay',
          'client_timestamp': createdAt.toIso8601String(),
          'payload': {
            'order_uuid': orderUuid,
            'method': 'cash',
            'amount_baisas': 2500,
          },
        },
      ]),
      orderNumber: const Value(1001),
      createdAt: createdAt,
    ));

/// Runs flush() to completion under the widget test's fake-async clock using
/// bounded frame pumps (no arbitrary sleeps).
Future<int> _flush(WidgetTester tester, OrderSyncRepository repository) async {
  int? synced;
  unawaited(repository.flush().then((value) => synced = value));
  for (var frame = 0; frame < 40 && synced == null; frame++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(synced, isNotNull,
      reason: 'flush() did not settle under the test pump');
  return synced!;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Answers shift.close with the server's settled reconciliation result
/// (expected cash for a 10.000 opening float and no cash sales; summary block
/// present so the Z-report needs no local fallback) and every order event
/// with a plain processed ACK.
class _ShiftAwareAdapter implements HttpClientAdapter {
  /// Deep-copied request batches in arrival order.
  final List<List<Map<String, dynamic>>> requests = [];

  /// Every non-shift client_event_id sent so far, in order.
  List<String> get orderEventIds => [
        for (final batch in requests)
          for (final event in batch)
            if (event['event_type'] != 'shift.close')
              event['client_event_id'].toString(),
      ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = (options.data as Map).cast<String, dynamic>();
    final events = (jsonDecode(jsonEncode(body['events'])) as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    requests.add(events);
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': 'processed',
                'duplicate': false,
                'result': event['event_type'] == 'shift.close'
                    ? {
                        'status': 'closed',
                        'expected_cash_baisas': 10000,
                        'variance_baisas': 0,
                        'summary': {
                          'order_count': 0,
                          'gross_sales_baisas': 0,
                          'discount_total_baisas': 0,
                          'comp_total_baisas': 0,
                          'tax_total_baisas': 0,
                          'grand_total_baisas': 0,
                          'tenders': <Map<String, dynamic>>[],
                          'void_count': 0,
                          'void_total_baisas': 0,
                          'round_up_baisas': 0,
                          'branch_expenses_baisas': 0,
                        },
                      }
                    : <String, dynamic>{},
              },
          ],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
