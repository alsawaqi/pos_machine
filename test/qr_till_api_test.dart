import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_till_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orderUuid = '11111111-1111-4111-8111-111111111111';

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
      expect(QrPollingPolicy.qrRequestsPerWorstRollingMinute, 14);
      expect(QrPollingPolicy.existingSteadyRequestsPerWorstRollingMinute, 7);
      expect(QrPollingPolicy.combinedWorstRollingMinute, 21);
      expect(
        QrPollingPolicy.qrRequestsPerWorstRollingMinute ~/ 2,
        lessThan(60),
      );
    },
  );
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
