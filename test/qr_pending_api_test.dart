import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_till_service.dart';
import 'support/qr_pending_fakes.dart';

void main() {
  test(
    'real pending facade uses A1 GET and A2 POST with no prices or offline queue',
    () async {
      final adapter = _Adapter();
      final dio = Dio(
        BaseOptions(baseUrl: 'https://pos.test', validateStatus: (_) => true),
      )..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final QrTillGateway gateway = QrTillService(
        PosApiService(tokenGetter: () => 'synthetic', dio: dio),
      );
      final orders = await gateway.fetchQrPendingOrders();
      expect(orders.single.active.uuid, 'quick-expired');
      expect(orders.single.active.tableId, isNull);
      expect(orders.single.active.items.single.name, 'Server-priced meal');
      expect(orders.single.active.items.single.quantity, 1);
      expect(orders.single.boardOrder.acceptedTotalBaisas, 4750);
      expect(orders.single.phoneTail, '5555');
      expect(orders.single.canSettle, isTrue);
      final moved = await gateway.moveQrPendingToCounter('quick-expired');
      expect(moved.active.status, 'held');
      expect(
        adapter.requests.map((request) => (request.method, request.path)),
        [
          ('GET', '/device/qr/pending-orders'),
          ('POST', '/device/qr/pending-orders/quick-expired/to-counter'),
        ],
      );
      expect(adapter.requests.last.data, isNull);
      expect(adapter.requests.last.queryParameters, isEmpty);
      adapter.refuse = true;
      await expectLater(
        gateway.moveQrPendingToCounter('quick-expired'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'charge_outcome_uncertain',
          ),
        ),
      );
      expect(adapter.requests.length, 3);
    },
  );
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool refuse = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'data': refuse
            ? null
            : options.method == 'GET'
            ? {
                'orders': [pendingOrder().json],
              }
            : pendingOrder().json,
        'meta': <String, dynamic>{},
        'errors': refuse
            ? [
                {'code': 'charge_outcome_uncertain', 'message': 'refused'},
              ]
            : [],
      }),
      refuse ? 409 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
