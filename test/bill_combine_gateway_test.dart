import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/bill_combine/combine_gateway.dart';
import 'qr_quick_gateway_test.dart' show QuickAdapter;
import 'bill_combine_test.dart' show previewJson, sourceId, success;

void main() {
  late QuickAdapter adapter;
  late ApiCombineGateway gateway;
  String? token;
  String scope = '';
  setUp(() {
    adapter = QuickAdapter();
    token = 'test-only';
    scope = 'scope-a';
    final dio = Dio(BaseOptions(baseUrl: 'http://qr-test.invalid/api/v1'))
      ..httpClientAdapter = adapter;
    gateway = ApiCombineGateway(
      PosApiService(tokenGetter: () => token, dio: dio),
      () => scope,
    );
  });
  test('preview is authenticated and never sends local prices', () async {
    adapter.data = {'data': previewJson(), 'errors': []};
    expect(await gateway.preview(1, sourceId), previewJson());
    final request = adapter.requests.single;
    expect(request.path, '/device/tables/1/combine-preview');
    expect(request.queryParameters, {'source_order_uuid': sourceId});
    expect(request.headers['Authorization'], 'Bearer test-only');
  });
  test('successful confirmation preserves exact response envelope', () async {
    adapter.data = success();
    final payload = {
      'source_order_uuid': sourceId,
      'client_request_id': 'request',
      'pin': '4321',
    };
    expect(await gateway.confirm(1, payload), success());
    expect(adapter.requests.single.path, '/device/tables/1/combine');
    expect(adapter.requests.single.data, payload);
  });
  test(
    '409 preserves exact no-write proof; 500 never becomes a success',
    () async {
      adapter.status = 409;
      adapter.data = {
        'errors': [
          {'code': 'combine_preview_stale'},
        ],
        'combine_final_no_write': {'client_request_id': 'request'},
      };
      expect(await gateway.confirm(1, {}), adapter.data);
      adapter.status = 500;
      await expectLater(gateway.confirm(1, {}), throwsA(anything));
    },
  );
  test('token or scope change prevents all network sends', () async {
    token = 'different';
    await expectLater(gateway.preview(1, sourceId), throwsStateError);
    token = 'test-only';
    scope = 'other';
    await expectLater(gateway.confirm(1, {}), throwsStateError);
    expect(adapter.requests, isEmpty);
  });
}
