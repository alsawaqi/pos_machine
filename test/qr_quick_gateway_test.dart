import 'dart:typed_data';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/qr_quick/qr_quick_gateway.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'qr_quick_controller_test.dart' show quickJson;

class QuickAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object data = {
    'data': {
      'orders': [quickJson()],
    },
    'errors': [],
  };
  int status = 200;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late QuickAdapter adapter;
  late PosApiService api;
  late ApiQrQuickGateway gateway;
  String? token;
  String scope = '';
  setUp(() {
    adapter = QuickAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://qr-test.invalid/api/v1'))
      ..httpClientAdapter = adapter;
    token = 'test-device';
    scope = quickDeviceScope('http://qr-test.invalid/api/v1', 1, 2, 'device-a');
    api = PosApiService(tokenGetter: () => token, dio: dio);
    gateway = ApiQrQuickGateway(api, () => scope);
  });
  test('GET uses existing device auth and parses exact quick list', () async {
    expect((await gateway.fetch()).single.reference, 'Q-007');
    expect(adapter.requests.single.path, '/device/qr/pending-orders');
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer test-device',
    );
  });
  test(
    'POST sends only request id and unpriced lines, with same bill URL',
    () async {
      adapter.data = {
        'data': {
          'order': quickJson(),
          'addition': {'id': 1, 'priced_lines': []},
          'replayed': false,
        },
        'errors': [],
      };
      final request = QrQuickRequest('bill-1', 'request-1', [
        QrQuickLine(7, 1, []),
      ]);
      await gateway.append(request);
      expect(adapter.requests.single.method, 'POST');
      expect(
        adapter.requests.single.path,
        '/device/qr/pending-orders/bill-1/items',
      );
      expect(adapter.requests.single.data, request.payload);
    },
  );
  test('to-counter never emits a sync event', () async {
    adapter.data = {'data': quickJson(), 'errors': []};
    await gateway.move('bill-1');
    expect(
      adapter.requests.single.path,
      '/device/qr/pending-orders/bill-1/to-counter',
    );
  });
  for (final status in [422, 500]) {
    test(
      'HTTP $status only definite catalogue refusal may release a fresh request',
      () async {
        adapter.status = status;
        adapter.data = {
          'errors': [
            {'code': 'product_unavailable', 'message': 'Sold out'},
          ],
          'data': null,
        };
        await expectLater(
          gateway.append(
            QrQuickRequest('bill-1', 'req', [QrQuickLine(7, 1, [])]),
          ),
          throwsA(
            isA<QrQuickFailure>().having(
              (e) => e.refused,
              'definite no write',
              status == 422,
            ),
          ),
        );
      },
    );
  }
  test('different device token or scope prevents sends', () async {
    token = 'another-device';
    await expectLater(gateway.fetch(), throwsA(isA<QrQuickFailure>()));
    token = 'test-device';
    scope = 'another-server';
    await expectLater(gateway.move('bill-1'), throwsA(isA<QrQuickFailure>()));
    expect(adapter.requests, isEmpty);
  });
  test(
    'scope includes server, company, branch and device; no credentials persisted',
    () {
      expect(jsonDecode(scope), [
        'http://qr-test.invalid/api/v1',
        1,
        2,
        'device-a',
      ]);
      expect(
        () => quickDeviceScope('http://test', 1, null, 'd'),
        throwsA(isA<QrQuickFailure>()),
      );
      expect(scope, isNot(contains('test-device')));
    },
  );
}
