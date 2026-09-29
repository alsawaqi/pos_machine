import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/order_workspace/workspace_void.dart';
import 'package:pos_machine/qr_checkout/payment_review_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_gateway.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'real_io_wait.dart';

// Payment review (owner 2026-09-29, a1 b1 c1). The real QR screen, controller,
// gateway, PosApiService/Dio, the real cancellation guard and the real
// file-backed checkout journal; only HTTP and the GPS fix are supplied.
// Order B has the T3 shape of T-0918-028: the server says the charge was
// cancelled, while this till holds a manager-handed-over cash capture that
// the server refused.
const _scope = 'synthetic-scope';
const _b = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'; // local cash capture
const _u = 'dddddddd-4444-4444-8444-dddddddddddd'; // uncertain on the server
const _n = 'eeeeeeee-5555-4555-8555-eeeeeeeeeeee'; // nothing to review
const _attempt = 'd817c2e7-53e8-4bd8-8a07-046e75880087';

class ReviewHttp implements HttpClientAdapter {
  final orders = <Map<String, dynamic>>[
    for (final (id, ref, status, charge, session, total) in [
      (_b, 'T-0918-028', 'awaiting_payment', 'cancelled', 'expired', 840),
      (_u, 'T-0929-001', 'awaiting_payment', 'uncertain', 'closed', 4750),
      (_n, 'T-0929-002', 'held', 'none', 'live', 500),
    ])
      {
        'uuid': id,
        'source': 'qr_web',
        'order_type': 'quick',
        'table_id': null,
        'status': status,
        'charge': charge,
        'session': session,
        'temp_reference': ref,
        'grand_total_baisas': total,
        'items': <dynamic>[],
        'phone_tail': '1234',
        'actions': {'settle': status == 'held', 'to_counter': false},
      },
  ];
  final requests = <RequestOptions>[];
  final reviewPosts = <Map<String, dynamic>>[];
  final results = <String, Map<String, dynamic>>{};
  final cancelled = <String>[];
  bool loseNextAnswer = false;

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
    if (options.path.endsWith('/payment-review')) {
      final uuid = options.path.split('/')[4];
      final input = (options.data as Map).cast<String, dynamic>();
      reviewPosts.add(input);
      final id = input['client_request_id'] as String;
      if (input['pin'] != '4321') {
        code = 'invalid_pin';
        status = 401;
      } else if (results[id] case final prior?) {
        data = {...prior, 'replayed': true};
      } else {
        final order = orders.singleWhere((o) => o['uuid'] == uuid);
        final paid = input['decision'] == 'paid';
        if (paid) {
          orders.remove(order);
        } else {
          order
            ..['status'] = 'held'
            ..['charge'] = 'none'
            ..['actions'] = {'settle': true, 'to_counter': false};
        }
        data = results[id] = {
          'order_uuid': uuid,
          'decision': input['decision'],
          'reference': input['reference'],
          'status': paid ? 'paid' : 'held',
          'receipt_number': paid ? 'KLD-0200' : null,
          'temp_reference': order['temp_reference'],
          'approved_by_staff_id': 7,
          'replayed': false,
        };
        if (loseNextAnswer) {
          loseNextAnswer = false;
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }
      }
    } else if (options.path.endsWith('/cancel-preview')) {
      final uuid = options.queryParameters['order_uuid'];
      final order = orders.singleWhere((o) => o['uuid'] == uuid);
      data = {
        'orders': [
          {
            'uuid': uuid,
            'reference': order['temp_reference'],
            'total_baisas': order['grand_total_baisas'],
            'prepared': false,
            'items': [
              {'name': 'Synthetic tea', 'qty': 1},
            ],
          },
        ],
        'count': 1,
        'total_baisas': order['grand_total_baisas'],
        'preview_token': 'review-$uuid',
      };
    } else if (options.path.endsWith('/cancel')) {
      final uuid = (options.data['preview_token'] as String).substring(7);
      cancelled.add(uuid);
      orders.removeWhere((o) => o['uuid'] == uuid);
      data = {
        'count': 1,
        'orders': [
          {'order_uuid': uuid, 'status': 'void'},
        ],
        'replayed': false,
      };
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

Map<String, dynamic> _attemptJson(String state, {String order = _b}) {
  final payment = {
    'method': 'cash',
    'amount_baisas': 840,
    'status': 'success',
    'change_given_baisas': 160,
  };
  return {
    'id': _attempt,
    'order_uuid': order,
    'state': state,
    'created_at': '2026-09-18T22:16:09.862778Z',
    'claim': {
      'order_uuid': order,
      'status': 'awaiting_payment',
      'charge_amount_baisas': 840,
      'charge_claimed_at': '2026-09-18T22:16:08.000Z',
      'charge_deadline_at': '2026-09-18T22:21:08.000Z',
      'already_claimed_by_this_device': false,
    },
    'order_id': 158,
    'reference': 'T-0918-028',
    'event': {
      'client_event_id': _attempt,
      'event_type': 'order.pay',
      'client_timestamp': '2026-09-18T22:17:01.158802Z',
      'payload': {
        'order_uuid': order,
        'paid_at': '2026-09-18T22:17:01.158802Z',
        'payments': [payment],
      },
    },
    'captures': [payment],
    'receipt_number': null,
    'tender_may_have_started': true,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  Future<(ReviewHttp, QrQuickController)> mount(
    WidgetTester tester, {
    bool arabic = false,
    String attemptState = 'managed',
    String attemptOrder = _b,
  }) async {
    final adapter = ReviewHttp();
    // Tall enough that the lazy list builds all three orders.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('payreview-');
      await databaseFactory.setDatabasesPath(dir.path);
      final checkout = await SqliteCheckoutStore.open(_scope);
      await checkout.db.insert('qr_checkout_attempts', {
        'id': _attempt,
        'scope': _scope,
        'state': attemptState,
        'payload': jsonEncode(_attemptJson(attemptState, order: attemptOrder)),
      });
    });
    final quick = (await tester.runAsync(
      () => SqliteQrQuickStore.open(_scope),
    ))!;
    final dio = Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
      ..httpClientAdapter = adapter;
    final api = PosApiService(tokenGetter: () => 'synthetic-device', dio: dio);
    Future<Database> db() async => (await SqliteCheckoutStore.open(_scope)).db;
    final gateway = ApiQrQuickGateway(
      api,
      () => _scope,
      cancellationGuard: (uuid) => assertWorkspaceVoidJournals(_scope, uuid),
      localPaymentOrders: () async =>
          ordersWithUnreviewedPayments(await db(), _scope),
      loadPaymentEvidence: (uuid) async =>
          loadPaymentReviewEvidence(await db(), _scope, uuid),
      recordPaymentReview: (uuid, evidence, requestId, result) async =>
          recordPaymentReview(
            await db(),
            _scope,
            uuid,
            evidence,
            requestId,
            result,
          ),
      currentGps: () async => {'lat': 23.5922, 'lng': 58.3773},
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
      () =>
          find.byKey(const ValueKey('quick-order-$_n')).evaluate().isNotEmpty &&
          find
              .byKey(const ValueKey('quick-payment-review-$_u'))
              .evaluate()
              .isNotEmpty,
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

  Future<void> until(
    WidgetTester tester,
    bool Function() condition,
    String reason,
  ) => pumpUntilRealCondition(
    tester,
    condition,
    reason: reason,
    timeout: const Duration(seconds: 20),
  );

  bool shown(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

  Future<void> openReview(WidgetTester tester, String uuid) async {
    // The local-evidence set loads from SQLite after the list.
    await until(
      tester,
      () => shown('quick-payment-review-$uuid'),
      'review button shown',
    );
    await tap(tester, 'quick-payment-review-$uuid');
    await until(
      tester,
      () =>
          shown('quick-payment-review-confirm') &&
          (shown('quick-payment-review-taken') ||
              shown('quick-payment-review-blocked')),
      'review loaded',
    );
  }

  Future<void> fill(WidgetTester tester, {String pin = '4321'}) async {
    await tester.enterText(
      find.byKey(const ValueKey('quick-payment-review-reference')),
      'Drawer count 29/09',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quick-payment-review-pin')),
      pin,
    );
  }

  Future<List<Map<String, Object?>>> reviews(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => (await SqliteCheckoutStore.open(
          _scope,
        )).db.query(paymentReviewTable),
      ))!;

  for (final arabic in [false, true]) {
    testWidgets(
      'no money taken frees the T3 order, then it can be cancelled ${arabic ? 'AR' : 'EN'}',
      (tester) async {
        final (adapter, controller) = await mount(tester, arabic: arabic);
        expect(shown('quick-payment-review-$_u'), isTrue);
        expect(shown('quick-payment-review-$_n'), isFalse);
        await openReview(tester, _b);
        expect(
          find.text(
            arabic
                ? '• تم استلام 0.840 OMR نقداً، الباقي 0.160 OMR · ${_local('2026-09-18T22:17:01.158802Z')}'
                : '• Cash 0.840 OMR taken, change 0.160 OMR · ${_local('2026-09-18T22:17:01.158802Z')}',
          ),
          findsOneWidget,
        );
        await tap(tester, 'quick-payment-review-not-taken');
        await fill(tester);
        await tap(tester, 'quick-payment-review-confirm');
        await until(
          tester,
          () => shown('quick-payment-review-done'),
          'review confirmed',
        );
        final post = adapter.reviewPosts.single;
        expect(post['decision'], 'not_paid');
        expect(post['reference'], 'Drawer count 29/09');
        expect(post['local_attempt_ids'], [_attempt]);
        expect(post['local_summary'], contains('cash 840 change 160'));
        expect(post.containsKey('method'), isFalse);
        expect(post.containsKey('amount_baisas'), isFalse);
        expect(post.containsKey('gps'), isFalse);
        final saved = await reviews(tester);
        expect(saved.single['attempt_id'], _attempt);
        expect(saved.single['decision'], 'not_paid');
        expect(saved.single['reference'], 'Drawer count 29/09');
        await tap(tester, 'quick-payment-review-close-done');
        await until(
          tester,
          () =>
              find.byType(AlertDialog).evaluate().isEmpty &&
              !shown('quick-payment-review-$_b'),
          'review button gone after the refresh',
        );
        // The checkout row itself is unchanged evidence.
        final row = (await tester.runAsync(
          () async => (await SqliteCheckoutStore.open(
            _scope,
          )).db.query('qr_checkout_attempts'),
        ))!.single;
        expect(row['state'], 'managed');
        expect(jsonDecode(row['payload'] as String), _attemptJson('managed'));

        await tap(tester, 'quick-cancel-$_b');
        await until(
          tester,
          () =>
              find.textContaining('1 orders · ').evaluate().isNotEmpty ||
              find.textContaining('1 طلبات · ').evaluate().isNotEmpty ||
              shown('quick-cancel-error'),
          'cancel review loaded',
        );
        expect(shown('quick-cancel-error'), isFalse);
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-reason')),
          'Synthetic cleanup',
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-pin')),
          '4321',
        );
        await tap(tester, 'quick-cancel-confirm');
        await until(
          tester,
          () =>
              find.byType(AlertDialog).evaluate().isEmpty &&
              controller.find(_b) == null,
          'order B cancelled',
        );
        expect(adapter.cancelled, [_b]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('money taken in cash records the payment with a location fix', (
    tester,
  ) async {
    final (adapter, controller) = await mount(tester);
    await openReview(tester, _b);
    await tap(tester, 'quick-payment-review-taken');
    await until(
      tester,
      () => shown('quick-payment-review-cash'),
      'method choice shown',
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('quick-payment-review-cash')),
          )
          .selected,
      isTrue,
      reason: 'the saved capture was cash',
    );
    await fill(tester);
    await tap(tester, 'quick-payment-review-confirm');
    await until(
      tester,
      () => shown('quick-payment-review-done'),
      'review confirmed',
    );
    expect(find.text('Recorded as paid. Receipt KLD-0200.'), findsOneWidget);
    final post = adapter.reviewPosts.single;
    expect(post['decision'], 'paid');
    expect(post['method'], 'cash');
    expect(post['amount_baisas'], 840);
    expect(post['gps'], {'lat': 23.5922, 'lng': 58.3773});
    expect((await reviews(tester)).single['decision'], 'paid');
    await tap(tester, 'quick-payment-review-close-done');
    await until(
      tester,
      () => controller.find(_b) == null,
      'paid order left the list',
    );
  });

  testWidgets(
    'a refused PIN and a lost answer retry the identical request once',
    (tester) async {
      final (adapter, _) = await mount(tester);
      await openReview(tester, _u);
      expect(find.textContaining('Saved on this till'), findsNothing);
      await tap(tester, 'quick-payment-review-taken');
      await tap(tester, 'quick-payment-review-card');
      await fill(tester, pin: '9999');
      await tap(tester, 'quick-payment-review-confirm');
      await until(
        tester,
        () => find
            .text('Manager PIN not accepted. Enter it again.')
            .evaluate()
            .isNotEmpty,
        'PIN refused',
      );
      // Decision, method and reference are fixed after the first submission.
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('quick-payment-review-reference')),
            )
            .enabled,
        isFalse,
      );
      adapter.loseNextAnswer = true;
      await tester.enterText(
        find.byKey(const ValueKey('quick-payment-review-pin')),
        '4321',
      );
      await tap(tester, 'quick-payment-review-confirm');
      await until(
        tester,
        () => find
            .textContaining('No answer from the server')
            .evaluate()
            .isNotEmpty,
        'answer lost',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick-payment-review-pin')),
        '4321',
      );
      await tap(tester, 'quick-payment-review-confirm');
      await until(
        tester,
        () => shown('quick-payment-review-done'),
        'review confirmed on replay',
      );
      expect(adapter.reviewPosts, hasLength(3));
      Map<String, dynamic> withoutPin(Map<String, dynamic> p) =>
          {...p}..remove('pin');
      expect(
        adapter.reviewPosts
            .map((p) => jsonEncode(withoutPin(p)))
            .toSet()
            .length,
        1,
        reason: 'the same request each time',
      );
      final post = adapter.reviewPosts.last;
      expect(post['method'], 'card');
      expect(post['amount_baisas'], 4750);
      expect(post.containsKey('local_attempt_ids'), isFalse);
      expect(adapter.results, hasLength(1), reason: 'recorded once');
      expect(await reviews(tester), isEmpty, reason: 'no local checkout');
    },
  );

  testWidgets('an open checkout on this till blocks the review', (
    tester,
  ) async {
    // A refused checkout the payment screen still owns (not handed over).
    final (adapter, _) = await mount(
      tester,
      attemptState: 'refused',
      attemptOrder: _u,
    );
    await openReview(tester, _u);
    expect(shown('quick-payment-review-blocked'), isTrue);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('quick-payment-review-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(adapter.reviewPosts, isEmpty);
  });

  testWidgets('choice, reference and PIN are required before sending', (
    tester,
  ) async {
    final (adapter, _) = await mount(tester);
    await openReview(tester, _b);
    await tester.enterText(
      find.byKey(const ValueKey('quick-payment-review-pin')),
      '4321',
    );
    await tap(tester, 'quick-payment-review-confirm');
    expect(find.byKey(const ValueKey('quick-payment-review-error')), findsOne);
    await tap(tester, 'quick-payment-review-not-taken');
    await tap(tester, 'quick-payment-review-confirm');
    expect(find.byKey(const ValueKey('quick-payment-review-error')), findsOne);
    expect(adapter.reviewPosts, isEmpty);
  });
}

String _local(String iso) {
  final l = DateTime.parse(iso).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
