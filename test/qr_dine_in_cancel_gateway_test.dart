import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'qr_quick_gateway_test.dart' show QuickAdapter;
import 'qr_checkout_fakes.dart';

void main() {
  test(
    'Back on a dine-in bill atomically returns to editing with the exact reservation',
    () async {
      final adapter = QuickAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://qr-test.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final gateway = ApiCheckoutGateway(
        api: PosApiService(tokenGetter: () => 'test-token', dio: dio),
        currentScope: () => 'scope',
        location: () async => null,
        legacyGuard: (_) async {},
      );
      adapter.data = {'data': claimJson(), 'errors': []};
      final claim = await gateway.claim('qr-bill');
      final snapshot = snapshotJson();
      (snapshot['order'] as Map)['order_type'] = 'dine_in';
      (snapshot['order'] as Map)['source'] = 'qr_web';
      adapter.data = {'data': snapshot, 'errors': []};
      await gateway.snapshot('qr-bill');
      adapter.data = {'data': {}, 'errors': []};
      await gateway.release('qr-bill', 'cancelled', []);
      expect(adapter.requests.last.path, '/device/qr/cancel-settlement');
      expect(adapter.requests.last.data, {
        'order_uuid': 'qr-bill',
        'charge_claimed_at': claim.json['charge_claimed_at'],
        'charge_deadline_at': claim.json['charge_deadline_at'],
      });
      await gateway.release('qr-bill', 'uncertain', [
        {'method': 'card', 'softpos_reference': 'TEST-ONLY'},
      ]);
      expect(adapter.requests.last.path, '/device/qr/release-charge');
      expect((adapter.requests.last.data as Map)['outcome'], 'uncertain');
      expect(
        (adapter.requests.last.data as Map)['softpos_reference'],
        'TEST-ONLY',
      );
    },
  );
}
