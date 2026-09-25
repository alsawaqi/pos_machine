import 'package:flutter_test/flutter_test.dart';
import 't12_fix2_customer_harness.dart';

void main() {
  for (final id in [null, 999, 7, 5]) {
    test(
      'fix2 HTTP fixture preserves server refusal contract customer=$id',
      () async {
        final s = CustomerServer();
        if (id == 5) s.balances[5]![11] = [50, 3];
        final create = {
          'client_event_id': 'create',
          'event_type': 'order.create',
          'payload': {
            'order': {'uuid': 'order', 'customer_id': id},
          },
        };
        final pay = {
          'client_event_id': 'pay',
          'event_type': 'order.pay',
          'payload': {
            'order_uuid': 'order',
            'loyalty_redeem': {'rule_id': 11, 'points': 100, 'stamps': 5},
          },
        };
        final a = s.acknowledge(create), b = s.acknowledge(pay);
        expect(a['status'], id == 999 ? 'failed' : 'processed');
        if (id == 999) {
          expect(
            a['result']['error'],
            'order references a customer outside the device tenant',
          );
        }
        expect(b['status'], id == 5 ? 'processed' : 'failed');
        if (id == null) {
          expect(
            b['result']['error'],
            'cannot redeem loyalty without a customer on the order',
          );
        }
        if (id == 7) {
          expect(b['result']['error'], 'no loyalty account to redeem from');
        }
        if (id == 5) {
          expect(
            b['result']['loyalty_redeem_warning'],
            contains('REVIEW_REQUIRED'),
          );
          expect(s.balances[5]![11], [0, 0]);
        }
        expect(
          s.acknowledge(pay),
          b,
          reason: 'same id replays without a second debit',
        );
      },
    );
  }
  test('fix2 HTTP fixture uses exact-string customer POST identity', () async {
    final s = CustomerServer();
    final dio = s.dio();
    final a = await dio.post(
      '/device/customers',
      data: {'name': 'A', 'phone': '+968 9000 0001'},
    );
    final b = await dio.post(
      '/device/customers',
      data: {'name': 'digits', 'phone': '96890000001'},
    );
    expect(a.data['data']['customer']['id'], 5);
    expect(b.data['data']['customer']['id'], 902);
    expect(s.customers.length, 4);
  });
}
