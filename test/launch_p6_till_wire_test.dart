import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_quick/qr_quick_gateway.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';

/// LAUNCH-P6 Part C items 1 and 2 (till) — the capability header on every
/// call, and one unknown or bad row skipped (and logged) in every QR and
/// tablet list instead of breaking the whole list.
class RouteAdapter implements HttpClientAdapter {
  RouteAdapter(this.routes);
  final Map<String, Object> routes;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final data = routes[options.path] ?? <String, dynamic>{};
    return ResponseBody.fromString(
      jsonEncode({'data': data, 'meta': <String, dynamic>{}, 'errors': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> qrQuick(String uuid) => {
  'uuid': uuid,
  'source': 'qr_web',
  'order_type': 'quick',
  'table_id': null,
  'status': 'held',
  'grand_total_baisas': 1500,
  'items': <Object>[],
};

Map<String, dynamic> tabletRow(String uuid, {Map<String, dynamic>? extra}) => {
  'tablet_order_uuid': uuid,
  'order_uuid': 'order-$uuid',
  'order_type': 'quick',
  'source': 'customer_tablet',
  'order_status': 'held',
  'state': 'pending',
  'paid': false,
  'unpaid': true,
  'order_number': '27',
  'temp_reference': 'T-1006-27',
  'table': null,
  'lines': [
    {'product_id': 4, 'product_name': 'Burger', 'qty': 1},
  ],
  'total_baisas': 2000,
  'grand_total_baisas': 2000,
  'payment': 'cash',
  'redeem': null,
  'taken_by': null,
  'sent_to_kitchen': null,
  'charge': {
    'state': 'none',
    'device_id': null,
    'deadline_at': null,
    'held_by_this_device': false,
  },
  'recovery_needed': false,
  ...?extra,
};

void main() {
  late List<String> skipped;
  setUp(() {
    skipped = [];
    skippedRowLogger = (list, index, error) => skipped.add('$list#$index');
  });

  (PosApiService, RouteAdapter) api(Map<String, Object> routes) {
    final adapter = RouteAdapter(routes);
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://till.invalid/api/v1',
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;
    return (PosApiService(tokenGetter: () => 'device-tok', dio: dio), adapter);
  }

  test('every call carries X-Pos-Capabilities: tablet-orders', () async {
    final (service, adapter) = api({
      '/device/tablet-orders': {'orders': <Object>[]},
    });
    await service.fetchOrderAttention();
    await service.fetchTabletOrders();
    await service.takeTabletOrder('t-1').catchError((_) => <String, dynamic>{});
    await service
        .editTabletOrderLines('t-1', clientRequestId: 'r', lines: const [])
        .catchError((_) => <String, dynamic>{});
    await service.pushSync(const []).catchError((_) => <String, dynamic>{});
    expect(adapter.seen.length, 5);
    expect(
      adapter.seen.map((r) => r.headers['X-Pos-Capabilities']),
      everyElement('tablet-orders'),
    );
    expect(adapter.seen.map((r) => r.method).toSet(), {'GET', 'POST', 'PUT'});
  });

  test('a mixed tablet list keeps the good rows and logs the bad ones', () {
    final rows = parseTabletOrderRows([
      tabletRow('a'),
      'not an object',
      tabletRow('b', extra: {'order_type': 'delivery'}),
      tabletRow('c', extra: {'lines': 'none'}),
      tabletRow(
        'd',
        extra: {
          'redeem': {'status': 'mystery'},
        },
      ),
      tabletRow(
        'e',
        extra: {
          'charge': {'state': 'from_the_future'},
        },
      ),
    ]);
    expect(rows.map((r) => r.uuid), ['a', 'e']);
    // An unknown charge state is never "nothing to do".
    expect(rows.last.charge.state, 'unknown');
    expect(skipped, [
      'tablet-orders#1',
      'tablet-orders#2',
      'tablet-orders#3',
      'tablet-orders#4',
    ]);
  });

  test('QR lists skip one bad row instead of failing the whole list', () async {
    final (service, _) = api({
      '/device/qr/pending-orders': {
        'orders': [qrQuick('p-1'), 'garbage', qrQuick('p-2')],
      },
      '/device/qr/accepted-rounds': {
        'rounds': [
          {'id': 1, 'round_no': 1, 'order_uuid': 'o-1', 'priced_lines': []},
          42,
          {'id': 2, 'round_no': 1, 'order_uuid': 'o-2', 'priced_lines': []},
        ],
      },
      '/device/tables/board': {
        'tables': [
          {'table_id': 1},
          'broken',
        ],
      },
      '/device/qr/table-board': {
        'tables': [
          {'table_id': 1, 'label': 'T1'},
          7,
        ],
      },
      '/device/orders/active': {
        'orders': [qrQuick('a-1'), null],
      },
    });
    expect((await service.fetchQrPendingOrders()).map((o) => o.uuid), [
      'p-1',
      'p-2',
    ]);
    expect(
      (await service.fetchAcceptedQrRounds()).rounds.map((r) => r.round.id),
      [1, 2],
    );
    expect(await service.fetchTableBoard(), hasLength(1));
    expect(await service.fetchQrTableBoard(), hasLength(1));
    expect(await service.fetchActiveQrOrders(), hasLength(1));
    expect(skipped, [
      'qr/pending-orders#1',
      'qr/accepted-rounds#1',
      'tables/board#1',
      'qr/board#1',
      'orders/active#1',
    ]);
  });

  test(
    'the QR quick inbox skips a customer_tablet row and keeps QR orders',
    () async {
      final (service, _) = api({
        '/device/qr/pending-orders': {
          'orders': [
            qrQuick('q-1'),
            {...qrQuick('t-1'), 'source': 'customer_tablet'},
            qrQuick('q-2'),
          ],
        },
      });
      final gateway = ApiQrQuickGateway(service, () => 'scope');
      final orders = await gateway.fetch();
      expect(orders.map((o) => o.uuid), ['q-1', 'q-2']);
      expect(skipped, ['qr/quick-inbox#1']);
    },
  );
}
