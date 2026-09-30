import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/device_heartbeat.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner = BusinessIdentity(11, 21, 'device');
  setUp(() {
    BusinessBoundary.resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '8.7.6',
      buildNumber: '54',
      buildSignature: 'test',
    );
  });
  tearDown(() {
    DeviceHeartbeat.stop();
    DeviceHeartbeat.pendingCount = null;
    DeviceHeartbeat.printerStatus = null;
    BusinessBoundary.resetForTest();
  });
  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
  }

  test(
    'B12f same-generation heartbeat using the pre-activation token is discarded',
    () async {
      var token = 'old';
      final adapter = _Adapter();
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://local.invalid',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = adapter;
      PosApiService(tokenGetter: () => token, dio: dio);
      await initialize();
      late Future<Response<dynamic>> request;
      await BusinessBoundary.accept(
        owner,
        install: () async {
          request = dio.post<dynamic>('/device/heartbeat');
          await adapter.entered.future;
          token = 'fresh';
        },
      );
      adapter.answer.complete(
        ResponseBody.fromString(
          '{"message":"Unauthenticated."}',
          401,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
      await expectLater(
        request,
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'obsolete credential',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(BusinessBoundary.canWork, true);
      dio.close();
    },
  );
  test(
    'B12c unreadable counts still heartbeat with unknown; B12h uses real build and printer metadata',
    () async {
      await initialize();
      DeviceHeartbeat.pendingCount = () async =>
          throw StateError('unreadable store');
      DeviceHeartbeat.printerStatus = () => 'paper_out';
      final adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://local.invalid'))
        ..httpClientAdapter = adapter;
      try {
        Function.apply(DeviceHeartbeat.start, [dio]);
      } on NoSuchMethodError {
        Function.apply(DeviceHeartbeat.start, [
          dio,
          'obsolete-hardcoded-build',
        ]);
      }
      await adapter.entered.future.timeout(const Duration(seconds: 3));
      final data = adapter.request!.data as Map;
      expect(data.containsKey('pending_outbox_count'), false);
      expect(data['app_version'], '8.7.6+54');
      expect(data['printer_status'], 'paper_out');
      adapter.answer.complete(
        ResponseBody.fromString(
          '{}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      dio.close();
    },
  );
}

class _Adapter implements HttpClientAdapter {
  final entered = Completer<void>();
  final answer = Completer<ResponseBody>();
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) {
    request = options;
    if (!entered.isCompleted) entered.complete();
    return answer.future;
  }

  @override
  void close({bool force = false}) {}
}
