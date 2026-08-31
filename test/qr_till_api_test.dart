import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_till_service.dart';

const orderUuid = '11111111-1111-4111-8111-111111111111';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'claim sends nested GPS and parses the frozen integer contract',
    () async {
      final adapter = _Adapter(
        (options) => _json({
          'data': {
            'order_uuid': orderUuid,
            'status': 'awaiting_payment',
            'charge_amount_baisas': 4750,
            'charge_claimed_at': '2026-08-30T12:00:00Z',
            'charge_deadline_at': '2026-08-30T12:05:00Z',
            'already_claimed_by_this_device': false,
          },
          'meta': {'money_unit': 'baisas'},
          'errors': <Object>[],
        }),
      );
      final api = _api(adapter);
      addTearDown(api.close);

      final claim = await api.service.claimQrSettlement(
        orderUuid,
        lat: 23.588,
        lng: 58.383,
      );

      expect(adapter.requests.single.path, '/device/qr/claim-settlement');
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.data, {
        'order_uuid': orderUuid,
        'gps': {'lat': 23.588, 'lng': 58.383},
      });
      expect(claim.orderUuid, orderUuid);
      expect(claim.status, 'awaiting_payment');
      expect(claim.frozenAmountBaisas, 4750);
      expect(claim.deadlineAt, DateTime.utc(2026, 8, 30, 12, 5));
    },
  );

  test(
    'release sends the only two client outcomes plus terminal evidence',
    () async {
      final adapter = _Adapter(
        (options) => _json({
          'data': {'order_uuid': orderUuid, 'status': 'open'},
          'errors': <Object>[],
        }),
      );
      final api = _api(adapter);
      addTearDown(api.close);

      await api.service.releaseQrSettlement(
        orderUuid: orderUuid,
        outcome: QrReleaseOutcome.uncertain,
        softposReference: 'RRN-1',
        softposAuthCode: 'AUTH-1',
        bankResponse: {'status': 'unknown'},
      );

      expect(adapter.requests.single.path, '/device/qr/release-charge');
      expect(adapter.requests.single.data, {
        'order_uuid': orderUuid,
        'outcome': 'uncertain',
        'softpos_reference': 'RRN-1',
        'softpos_auth_code': 'AUTH-1',
        'bank_response': {'status': 'unknown'},
      });
    },
  );

  test('active-order boundary admits qr_web and rejects main_pos', () async {
    final adapter = _Adapter(
      (options) => _json({
        'data': {
          'orders': [
            _activeOrder(orderUuid, source: 'qr_web'),
            _activeOrder(
              '22222222-2222-4222-8222-222222222222',
              source: 'main_pos',
            ),
          ],
        },
        'errors': <Object>[],
      }),
    );
    final api = _api(adapter);
    addTearDown(api.close);

    final orders = await api.service.fetchActiveQrOrders();

    expect(orders.map((order) => order.uuid), [orderUuid]);
    expect(orders.single.grandTotalBaisas, 4750);
    expect(adapter.requests.single.path, '/device/orders/active');
  });

  test(
    'staff actions use the exact shipped QR endpoint paths and bodies',
    () async {
      final adapter = _Adapter((options) {
        switch (options.path) {
          case '/device/qr/reopen-payment':
            return _json({
              'data': {
                'order_uuid': orderUuid,
                'status': 'open',
                'session_status': 'active',
              },
              'errors': <Object>[],
            });
          case '/device/qr/fallback-to-counter':
            return _json({
              'data': {
                'order_uuid': orderUuid,
                'receipt_number': 'QR-0042',
                'status': 'held',
              },
              'errors': <Object>[],
            });
          case '/device/qr/clear-table':
            return _json({
              'data': {'table_id': 42, 'status': 'cleared'},
              'errors': <Object>[],
            });
          default:
            throw StateError('Unexpected path ${options.path}');
        }
      });
      final api = _api(adapter);
      addTearDown(api.close);

      final reopened = await api.service.reopenQrPayment(orderUuid);
      final moved = await api.service.fallbackQrToCounter(orderUuid);
      await api.service.clearQrTable(42);

      expect(reopened.status, 'open');
      expect(reopened.sessionStatus, 'active');
      expect(moved.status, 'held');
      expect(moved.receiptNumber, 'QR-0042');
      expect(adapter.requests.map((request) => request.path), [
        '/device/qr/reopen-payment',
        '/device/qr/fallback-to-counter',
        '/device/qr/clear-table',
      ]);
      expect(adapter.requests[0].data, {'order_uuid': orderUuid});
      expect(adapter.requests[1].data, {'order_uuid': orderUuid});
      expect(adapter.requests[2].data, {'table_id': 42});
    },
  );

  test(
    'round detail uses the nested read contract and parses display data',
    () async {
      final adapter = _Adapter(
        (options) => _json({
          'data': _roundEnvelope(status: 'pending_confirmation'),
          'meta': {'money_unit': 'baisas'},
          'errors': <Object>[],
        }),
      );
      final api = _api(adapter);
      addTearDown(api.close);

      final result = await api.service.fetchQrRound(42);

      expect(adapter.requests.single.path, '/device/qr/table-round/42');
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.data, isNull);
      _expectRoundEnvelope(result, status: 'pending_confirmation');
    },
  );

  test(
    'confirm and reject send only round_id and parse nested responses',
    () async {
      final adapter = _Adapter((options) {
        final status = switch (options.path) {
          '/device/qr/confirm-round' => 'accepted',
          '/device/qr/reject-round' => 'rejected',
          _ => throw StateError('Unexpected path ${options.path}'),
        };
        return _json({
          'data': _roundEnvelope(status: status),
          'meta': {'money_unit': 'baisas'},
          'errors': <Object>[],
        });
      });
      final api = _api(adapter);
      addTearDown(api.close);

      final confirmed = await api.service.confirmQrRound(42);
      final rejected = await api.service.rejectQrRound(43);

      expect(adapter.requests.map((request) => request.path), [
        '/device/qr/confirm-round',
        '/device/qr/reject-round',
      ]);
      expect(adapter.requests.map((request) => request.method), [
        'POST',
        'POST',
      ]);
      expect(adapter.requests[0].data, {'round_id': 42});
      expect(adapter.requests[1].data, {'round_id': 43});
      _expectRoundEnvelope(confirmed, status: 'accepted');
      _expectRoundEnvelope(rejected, status: 'rejected');
    },
  );

  test(
    'accepted-round feed sends cursor/limit and parses flat rows plus meta',
    () async {
      final adapter = _Adapter(
        (options) => _json({
          'data': {
            'rounds': [
              _flatFeedRound(),
              _flatFeedRound(
                id: 43,
                roundNo: 3,
                tableLabel: null,
                receiptNumber: null,
              ),
            ],
          },
          'meta': {
            'next_cursor': 'cursor-43',
            'latest_cursor': 'cursor-99',
            'skipped_expired_count': 2,
            'money_unit': 'baisas',
          },
          'errors': <Object>[],
        }),
      );
      final api = _api(adapter);
      addTearDown(api.close);

      final page = await api.service.fetchAcceptedQrRounds(
        after: 'cursor-41',
        limit: 17,
      );

      final request = adapter.requests.single;
      expect(request.path, '/device/qr/accepted-rounds');
      expect(request.method, 'GET');
      expect(request.queryParameters, {'after': 'cursor-41', 'limit': 17});
      expect(page.nextCursor, 'cursor-43');
      expect(page.latestCursor, 'cursor-99');
      expect(page.skippedExpiredCount, 2);
      expect(page.rounds, hasLength(2));
      _expectRoundEnvelope(page.rounds.first, status: 'accepted');
      expect(page.rounds.first.sessionUuid, 'session-42');
      expect(page.rounds[1].round.id, 43);
      expect(page.rounds[1].round.roundNo, 3);
      expect(page.rounds[1].tableLabel, isNull);
      expect(page.rounds[1].receiptNumber, isNull);
    },
  );

  test(
    'polling backoff retains Retry-After delta seconds from structured 429',
    () async {
      final adapter = _Adapter(
        (options) => _json(
          {
            'data': <String, dynamic>{},
            'errors': [
              {'code': 'rate_limited', 'message': 'Slow down.'},
            ],
          },
          status: 429,
          headers: {
            'retry-after': ['37'],
          },
        ),
      );
      final api = _api(adapter);
      addTearDown(api.close);

      late ApiException error;
      try {
        await api.service.fetchQrTableBoard();
        fail('Expected a rate-limit error.');
      } on ApiException catch (caught) {
        error = caught;
      }

      expect(error.code, 'rate_limited');
      expect(error.statusCode, 429);
      expect(error.retryAfter, const Duration(seconds: 37));
      expect(
        const QrPollingPolicy().delayAfter(error),
        const Duration(seconds: 37),
      );
    },
  );

  test('Retry-After HTTP-date is parsed and retained', () async {
    final adapter = _Adapter(
      (options) => _json(
        {
          'data': <String, dynamic>{},
          'errors': [
            {'code': 'rate_limited', 'message': 'Slow down.'},
          ],
        },
        status: 429,
        headers: {
          'retry-after': ['Wed, 30 Aug 2090 12:00:00 GMT'],
        },
      ),
    );
    final api = _api(adapter);
    addTearDown(api.close);

    late ApiException error;
    try {
      await api.service.fetchQrTableBoard();
      fail('Expected a rate-limit error.');
    } on ApiException catch (caught) {
      error = caught;
    }

    expect(error.retryAfter, isNotNull);
    expect(error.retryAfter, greaterThan(const Duration(days: 365)));
  });

  test(
    'poll budget uses the conservative inclusive rolling-minute boundary',
    () {
      expect(
        QrPollingPolicy.acceptedRoundsInterval,
        const Duration(seconds: 5),
      );
      expect(QrPollingPolicy.qrRequestsPerWorstRollingMinute, 14);
      expect(QrPollingPolicy.existingSteadyRequestsPerWorstRollingMinute, 7);
      expect(
        QrPollingPolicy.acceptedRoundFeedRequestsPerWorstRollingMinute,
        13,
      );
      expect(
        QrPollingPolicy.combinedWorstRollingMinute,
        QrPollingPolicy.qrRequestsPerWorstRollingMinute +
            QrPollingPolicy.existingSteadyRequestsPerWorstRollingMinute +
            QrPollingPolicy.acceptedRoundFeedRequestsPerWorstRollingMinute,
      );
      expect(QrPollingPolicy.combinedWorstRollingMinute, 34);
      expect(
        QrPollingPolicy.qrRequestsPerWorstRollingMinute ~/ 2,
        lessThan(60),
      );
    },
  );
}

Map<String, dynamic> _roundEnvelope({required String status}) => {
  'round': _round(status: status),
  'table_label': 'T-12',
  'receipt_number': 'QR-0042',
  'order_uuid': orderUuid,
  'order': {
    'subtotal_baisas': 5000,
    'discount_total_baisas': 250,
    'tax_total_baisas': 0,
    'grand_total_baisas': 4750,
  },
};

Map<String, dynamic> _flatFeedRound({
  int id = 42,
  int roundNo = 2,
  String? tableLabel = 'T-12',
  String? receiptNumber = 'QR-0042',
}) => {
  ..._round(status: 'accepted', id: id, roundNo: roundNo),
  'table_label': tableLabel,
  'receipt_number': receiptNumber,
  'order_uuid': orderUuid,
  'session_uuid': 'session-42',
  // A private field accidentally added server-side must never enter a model.
  'confirm_payload': {'private': true},
};

Map<String, dynamic> _round({
  required String status,
  int id = 42,
  int roundNo = 2,
}) => {
  'id': id,
  'round_no': roundNo,
  'status': status,
  'priced_lines': [
    {
      'product_id': 101,
      'product_name': 'Flat white',
      'product_name_ar': 'فلات وايت',
      'qty': 2,
      'unit_price_baisas': 2500,
      'line_discount_baisas': 250,
      'line_total_baisas': 5000,
      'notes': 'No sugar',
      'addons': [
        {
          'add_on_id': 7,
          'name': 'Extra shot',
          'name_ar': 'جرعة إضافية',
          'price_delta_baisas': 300,
        },
      ],
    },
  ],
  'subtotal_baisas': 5000,
  'tax_baisas': 0,
  'total_baisas': 4750,
  'submitted_at': '2026-08-31T12:00:00Z',
  'resolved_at': status == 'pending_confirmation'
      ? null
      : '2026-08-31T12:01:00Z',
};

void _expectRoundEnvelope(QrRoundEnvelope envelope, {required String status}) {
  expect(envelope.orderUuid, orderUuid);
  expect(envelope.tableLabel, 'T-12');
  expect(envelope.receiptNumber, 'QR-0042');
  expect(envelope.round.id, 42);
  expect(envelope.round.roundNo, 2);
  expect(envelope.round.status, status);
  expect(envelope.round.subtotalBaisas, 5000);
  expect(envelope.round.taxBaisas, 0);
  expect(envelope.round.totalBaisas, 4750);
  expect(envelope.round.submittedAt, DateTime.utc(2026, 8, 31, 12));
  expect(
    envelope.round.resolvedAt,
    status == 'pending_confirmation'
        ? isNull
        : DateTime.utc(2026, 8, 31, 12, 1),
  );
  expect(envelope.round.lines, hasLength(1));
  final line = envelope.round.lines.single;
  expect(line.name, 'Flat white');
  expect(line.nameAr, 'فلات وايت');
  expect(line.quantity, 2);
  expect(line.unitPriceBaisas, 2500);
  expect(line.lineDiscountBaisas, 250);
  expect(line.lineTotalBaisas, 5000);
  expect(line.notes, 'No sugar');
  expect(line.addons.single.addOnId, 7);
  expect(line.addons.single.name, 'Extra shot');
  expect(line.addons.single.nameAr, 'جرعة إضافية');
  expect(line.addons.single.priceDeltaBaisas, 300);
}

Map<String, dynamic> _activeOrder(String uuid, {required String source}) => {
  'uuid': uuid,
  'status': 'open',
  'source': source,
  'subtotal_baisas': 4500,
  'discount_total_baisas': 0,
  'comp_total_baisas': 0,
  'tax_total_baisas': 250,
  'grand_total_baisas': 4750,
  'items': <Object>[],
};

_ApiHarness _api(_Adapter adapter) {
  final dio = Dio(
    BaseOptions(baseUrl: 'https://pos.test', validateStatus: (_) => true),
  )..httpClientAdapter = adapter;
  return _ApiHarness(
    dio,
    PosApiService(tokenGetter: () => 'device-token', dio: dio),
  );
}

class _ApiHarness {
  const _ApiHarness(this.dio, this.service);

  final Dio dio;
  final PosApiService service;

  void close() => dio.close(force: true);
}

typedef _Responder = ResponseBody Function(RequestOptions options);

class _Adapter implements HttpClientAdapter {
  _Adapter(this._responder);

  final _Responder _responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  Map<String, dynamic> body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...headers,
  },
);
