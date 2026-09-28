import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/order_workspace/workspace_void.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_gateway.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'real_io_wait.dart';

// Fix 11 (F-61). The real QR screen, controller, gateway, PosApiService/Dio,
// the real cancellation guard (assertWorkspaceVoidJournals) and the real,
// file-backed checkout / dine-in / quick-request journals. Only HTTP is
// supplied. The journals are seeded with the two record shapes found on the
// T3 on 2026-09-28: another table's unsent bill adjustment, and a "managed"
// checkout whose cash payment never reached the server.
const _scope = 'synthetic-scope';
const _a = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'; // expired, safe
const _b = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'; // expired, local cash pay
const _live = 'cccccccc-3333-4333-8333-cccccccccccc'; // active phone session

class F61Http implements HttpClientAdapter {
  final orders = <Map<String, dynamic>>[
    for (final (id, ref, session, total) in [
      (_a, 'T-F61-A', 'closed', 1000),
      (_b, 'T-F61-B', 'expired', 840),
      (_live, 'T-F61-L', 'live', 500),
    ])
      {
        'uuid': id,
        'source': 'qr_web',
        'order_type': 'quick',
        'table_id': null,
        'status': 'held',
        'charge': 'none',
        'session': session,
        'temp_reference': ref,
        'grand_total_baisas': total,
        'items': <dynamic>[],
        'phone_tail': '1234',
        'actions': {'settle': true, 'to_counter': false},
      },
  ];
  final requests = <RequestOptions>[];
  final reviews = <String, List<String>>{};
  final cancelled = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    dynamic data;
    String? code;
    var status = 200;
    if (options.path.endsWith('/cancel-preview')) {
      final uuid = options.queryParameters['order_uuid'];
      final exclude =
          (options.queryParameters['exclude_order_uuids[]'] as List?)
              ?.cast<String>() ??
          const <String>[];
      final review = orders
          .where(
            (o) =>
                o['session'] != 'live' &&
                (uuid == null
                    ? !exclude.contains(o['uuid'])
                    : o['uuid'] == uuid),
          )
          .toList();
      final token = 'review-${reviews.length + 1}';
      reviews[token] = [for (final o in review) o['uuid'] as String];
      data = {
        'orders': [
          for (final o in review)
            {
              'uuid': o['uuid'],
              'reference': o['temp_reference'],
              'total_baisas': o['grand_total_baisas'],
              'prepared': false,
              'items': [
                {'name': 'Synthetic tea', 'qty': 1},
              ],
            },
        ],
        'count': review.length,
        'total_baisas': review.fold<int>(
          0,
          (s, o) => s + (o['grand_total_baisas'] as int),
        ),
        'preview_token': token,
      };
    } else if (options.path.endsWith('/cancel')) {
      final input = options.data as Map;
      if (input['pin'] != '4321') {
        code = 'invalid_pin';
        status = 401;
      } else {
        final ids = reviews[input['preview_token']]!;
        cancelled.addAll(ids);
        orders.removeWhere((o) => ids.contains(o['uuid']));
        data = {
          'count': ids.length,
          'orders': [
            for (final id in ids) {'order_uuid': id, 'status': 'void'},
          ],
          'replayed': false,
        };
      }
    } else if (options.path == '/device/qr/pending-orders') {
      data = {'orders': orders};
    } else {
      throw StateError('Unexpected HTTP ${options.path}');
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': data,
        'errors': code == null
            ? []
            : [
                {'code': code, 'message': 'Synthetic refusal'},
              ],
      }),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _seedJournals() async {
  // Another table's unsent bill adjustment (attach customer), as on the T3.
  final dine = await SqliteDineInStore.open(_scope);
  await dine.db.insert('dine_in_requests', {
    'scope': '$_scope::adjustment:1',
    'table_id': 1,
    'seating_uuid': '4083e8f4-e36f-4952-85a8-d1b7247d8fe5',
    'bill_uuid': 'c67562d7-3b0f-40f7-bd5e-0ae7192060e4',
    'request_id': 'eda63cf8-8c79-4adc-8ed4-62ea4b260ee7',
    'payload': jsonEncode({
      'table_id': 1,
      'seating_key': 'e0776fff-fe3d-4956-ad2e-e6aef8fe410c',
      'client_request_id': 'eda63cf8-8c79-4adc-8ed4-62ea4b260ee7',
      'queued_offline': false,
      'staff_id': 1,
      'adjustment': {'kind': 'customer', 'mode': 'attach', 'customer_id': 1},
    }),
  });
  // Order B: a manager-handed-over checkout whose cash pay never synced.
  const attempt = 'd817c2e7-53e8-4bd8-8a07-046e75880087';
  final payment = {
    'method': 'cash',
    'amount_baisas': 840,
    'status': 'success',
    'change_given_baisas': 160,
  };
  final checkout = await SqliteCheckoutStore.open(_scope);
  await checkout.db.insert('qr_checkout_attempts', {
    'id': attempt,
    'scope': _scope,
    'state': 'managed',
    'payload': jsonEncode({
      'id': attempt,
      'order_uuid': _b,
      'state': 'managed',
      'created_at': '2026-09-18T22:16:09.862778Z',
      'claim': {
        'order_uuid': _b,
        'status': 'awaiting_payment',
        'charge_amount_baisas': 840,
        'charge_claimed_at': '2026-09-18T22:16:08.000Z',
        'charge_deadline_at': '2026-09-18T22:21:08.000Z',
        'already_claimed_by_this_device': false,
      },
      'order_id': 158,
      'reference': 'T-F61-B',
      'event': {
        'client_event_id': attempt,
        'event_type': 'order.pay',
        'client_timestamp': '2026-09-18T22:17:01.158802Z',
        'payload': {
          'order_uuid': _b,
          'paid_at': '2026-09-18T22:17:01.158802Z',
          'payments': [payment],
        },
      },
      'captures': [payment],
      'receipt_number': null,
      'tender_may_have_started': true,
    }),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  Future<(F61Http, QrQuickController)> mount(
    WidgetTester tester, {
    bool arabic = false,
  }) async {
    final adapter = F61Http();
    await tester.runAsync(() async {
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('f61-');
      await databaseFactory.setDatabasesPath(dir.path);
      await _seedJournals();
    });
    final quick = (await tester.runAsync(
      () => SqliteQrQuickStore.open(_scope),
    ))!;
    final dio = Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
      ..httpClientAdapter = adapter;
    final api = PosApiService(tokenGetter: () => 'synthetic-device', dio: dio);
    final gateway = ApiQrQuickGateway(
      api,
      () => _scope,
      cancellationGuard: (uuid) => assertWorkspaceVoidJournals(_scope, uuid),
    );
    final controller = QrQuickController(gateway, quick);
    addTearDown(() => dio.close(force: true));
    await tester.pumpWidget(
      MaterialApp(
        home: QrQuickScreen(
          createController: () async => controller,
          catalogue: () => [],
          arabic: arabic,
        ),
      ),
    );
    await pumpUntilRealCondition(
      tester,
      () => find.byKey(const ValueKey('quick-order-$_a')).evaluate().isNotEmpty,
      reason: 'real SQLite journal and HTTP list loaded',
      timeout: const Duration(seconds: 20),
    );
    return (adapter, controller);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
  }

  Future<void> reviewOpen(WidgetTester tester) => pumpUntilRealCondition(
    tester,
    () =>
        find
            .byKey(const ValueKey('quick-cancel-summary'))
            .evaluate()
            .isNotEmpty ||
        find.byKey(const ValueKey('quick-cancel-error')).evaluate().isNotEmpty,
    reason: 'cancellation review loaded',
    timeout: const Duration(seconds: 20),
  );

  for (final arabic in [false, true]) {
    testWidgets(
      'F61 bulk clean-up leaves out a local-payment order and cancels the rest ${arabic ? 'AR' : 'EN'}',
      (tester) async {
        final (adapter, controller) = await mount(tester, arabic: arabic);
        await tap(tester, 'quick-clear-expired');
        await reviewOpen(tester);
        expect(find.byKey(const ValueKey('quick-cancel-error')), findsNothing);
        expect(
          find.text(arabic ? '1 طلبات · 1.000 OMR' : '1 orders · 1.000 OMR'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('quick-cancel-left-out')),
          findsOneWidget,
        );
        expect(
          find.text(
            arabic
                ? 'T-F61-B · تحتاج إلى مراجعة الدفع'
                : 'T-F61-B · needs a payment review',
          ),
          findsOneWidget,
        );
        // The second preview left order B out on the server side too.
        final previews = adapter.requests
            .where((r) => r.path.endsWith('/cancel-preview'))
            .toList();
        expect(previews, hasLength(2));
        expect(previews.last.queryParameters['exclude_order_uuids[]'], [_b]);
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-reason')),
          'Synthetic cleanup',
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-pin')),
          '4321',
        );
        await tap(tester, 'quick-cancel-confirm');
        await pumpUntilRealCondition(
          tester,
          () =>
              find.byType(AlertDialog).evaluate().isEmpty &&
              controller.orders.length == 2,
          reason: 'only order A cancelled and the list refreshed',
          timeout: const Duration(seconds: 20),
        );
        expect(adapter.cancelled, [_a]);
        expect(controller.orders.map((o) => o.uuid).toSet(), {
          _b,
          _live,
        }, reason: 'order B (local cash payment) and the active order remain');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'F61 another table\'s unsent adjustment does not block a single cancel',
    (tester) async {
      final (adapter, controller) = await mount(tester);
      await tap(tester, 'quick-cancel-$_a');
      await reviewOpen(tester);
      expect(find.byKey(const ValueKey('quick-cancel-error')), findsNothing);
      expect(find.text('1 orders · 1.000 OMR'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('quick-cancel-reason')),
        'Synthetic cleanup',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick-cancel-pin')),
        '4321',
      );
      await tap(tester, 'quick-cancel-confirm');
      await pumpUntilRealCondition(
        tester,
        () =>
            find.byType(AlertDialog).evaluate().isEmpty &&
            controller.orders.length == 2,
        reason: 'order A cancelled',
        timeout: const Duration(seconds: 20),
      );
      expect(adapter.cancelled, [_a]);
    },
  );

  for (final arabic in [false, true]) {
    testWidgets(
      'F61 a local-payment order cannot be cancelled and says why ${arabic ? 'AR' : 'EN'}',
      (tester) async {
        final (adapter, _) = await mount(tester, arabic: arabic);
        await tap(tester, 'quick-cancel-$_b');
        await reviewOpen(tester);
        expect(
          find.text(
            arabic
                ? 'قد يكون دفع هذا الطلب قد تم على هذا الجهاز. يحتاج إلى مراجعة الدفع قبل إلغائه.'
                : 'A payment for this order may already have been taken on this device. It needs a payment review before it can be cancelled.',
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('quick-cancel-confirm')),
              )
              .onPressed,
          isNull,
        );
        expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
        expect(adapter.cancelled, isEmpty);
      },
    );
  }
}
