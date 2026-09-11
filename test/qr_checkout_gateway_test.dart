import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'qr_quick_gateway_test.dart' show QuickAdapter;
import 'qr_checkout_fakes.dart';

void main() {
  late QuickAdapter adapter;
  late ApiCheckoutGateway gateway;
  String? token;
  String scope = '';
  int guards = 0;
  setUp(() {
    adapter = QuickAdapter();
    token = 'test-token';
    scope = 'scope';
    guards = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://qr-test.invalid/api/v1'))
      ..httpClientAdapter = adapter;
    gateway = ApiCheckoutGateway(
      api: PosApiService(tokenGetter: () => token, dio: dio),
      currentScope: () => scope,
      location: () async => (lat: 23.0, lng: 58.0),
      legacyGuard: (_) async {
        guards++;
      },
    );
  });
  test(
    'claim -> snapshot use authenticated existing claim and new read-only endpoint',
    () async {
      await gateway.preflight('qr-bill');
      expect(guards, 1);
      adapter.data = {'data': claimJson(), 'errors': []};
      expect((await gateway.claim('qr-bill')).amount, 4750);
      expect(adapter.requests.last.path, '/device/qr/claim-settlement');
      expect(adapter.requests.last.data, {
        'order_uuid': 'qr-bill',
        'gps': {'lat': 23.0, 'lng': 58.0},
      });
      adapter.data = {'data': snapshotJson(), 'errors': []};
      expect(await gateway.snapshot('qr-bill'), snapshotJson());
      expect(adapter.requests.last.path, '/device/qr/orders/qr-bill/checkout');
      expect(adapter.requests.last.method, 'GET');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer test-token',
      );
    },
  );
  test(
    'push preserves standalone event exactly and release preserves all evidence',
    () async {
      const event = {
        'client_event_id': 'id',
        'event_type': 'order.pay',
        'payload': {'order_uuid': 'qr-bill'},
      };
      adapter.data = {
        'data': {
          'results': [
            {'client_event_id': 'id', 'status': 'processed'},
          ],
        },
        'errors': [],
      };
      final result = await gateway.push(event);
      expect(result.single['client_event_id'], 'id');
      expect(adapter.requests.last.data, {
        'events': [event],
      });
      adapter.data = {'data': {}, 'errors': []};
      await gateway.release('qr-bill', 'uncertain', [
        {
          'method': 'card',
          'amount_baisas': 4750,
          'softpos_reference': 'TEST-RRN',
        },
      ]);
      expect(adapter.requests.last.path, '/device/qr/release-charge');
      expect(
        (adapter.requests.last.data as Map)['softpos_reference'],
        'TEST-RRN',
      );
      expect(
        ((adapter.requests.last.data as Map)['bank_response']
            as Map)['checkout_tenders'],
        hasLength(1),
      );
    },
  );
  test('token or scope change prevents snapshot/pay/release', () async {
    token = 'other';
    await expectLater(gateway.snapshot('qr-bill'), throwsStateError);
    token = 'test-token';
    scope = 'other';
    await expectLater(gateway.push({}), throwsStateError);
    await expectLater(
      gateway.release('qr-bill', 'cancelled', []),
      throwsStateError,
    );
    expect(adapter.requests, isEmpty);
  });
  for (final status in [409, 500]) {
    test('HTTP $status no-claim classification is strict', () async {
      adapter.status = status;
      adapter.data = {
        'data': null,
        'errors': [
          {'code': 'charge_already_claimed', 'message': 'Already claimed'},
        ],
      };
      await expectLater(
        gateway.claim('qr-bill'),
        throwsA(status == 409 ? isA<CheckoutRefusal>() : isA<ApiException>()),
      );
    });
  }
}
