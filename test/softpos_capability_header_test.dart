import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  test(
    'capability header covers GET POST PATCH DELETE and rotating device tokens',
    () async {
      final seen = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'));
      var token = 'device-a';
      PosApiService(tokenGetter: () => token, dio: dio);
      dio.httpClientAdapter = HeaderAdapter(seen);
      for (final method in ['GET', 'POST', 'PATCH', 'DELETE']) {
        await dio.request(
          '/device/contract-probe',
          options: Options(method: method),
        );
        token = 'device-b';
      }
      expect(seen, hasLength(4));
      expect(
        seen.map((r) => r.headers['X-Mithqal-SoftPos-Capable']),
        everyElement('1'),
      );
      expect(seen.first.headers['Authorization'], 'Bearer device-a');
      expect(seen.last.headers['Authorization'], 'Bearer device-b');
    },
  );
}

class HeaderAdapter implements HttpClientAdapter {
  HeaderAdapter(this.seen);
  final List<RequestOptions> seen;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    seen.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
