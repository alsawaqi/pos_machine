import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/device_heartbeat.dart';
import 'package:pos_machine/tenancy/tenancy_interceptor.dart';

import 'support/fix2_release_storage.dart';

/// The server side of a real Dio round trip: everything that reaches it is
/// recorded, and status codes go through the client's own validateStatus.
class _Server implements HttpClientAdapter {
  _Server(this.companyId, this.branchId);
  final int companyId;
  final int branchId;
  bool suspended = false;
  bool identityMissing = false;
  final reached = <String>[];

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    reached.add(options.path);
    if (suspended) {
      return _json({
        'data': null,
        'errors': [
          {'code': 'company_suspended', 'message': 'Account suspended.'},
        ],
      }, 503);
    }
    if (options.path.endsWith('/identity')) {
      if (identityMissing) return _json({'message': 'Not Found'}, 404);
      return _json({
        'data': {
          'uuid': '6ed7d78c-1d2e-4b7a-9f3c-0a1b2c3d4e5f',
          'company_id': companyId,
          'branch_id': branchId,
        },
      }, 200);
    }
    return _json({'data': {}}, 200);
  }

  @override
  void close({bool force = false}) {}
}

Dio _client(_Server server) =>
    Dio(
        BaseOptions(
          baseUrl: 'http://pos.test/api/v1',
          validateStatus: (_) => true,
        ),
      )
      ..httpClientAdapter = server
      ..interceptors.add(
        TenancyInterceptor(tokenGetter: () => 'release-fixture-token'),
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(BusinessBoundary.resetForTest);

  test(
    'D1 upgraded release till suspended before its identity lookup recovers after unsuspension',
    () async {
      await loadFix2ReleaseStorage();
      final provisional = BusinessBoundary.current!;
      expect(provisional.isProvisional, isTrue);
      final server = _Server(provisional.companyId, provisional.branchId)
        ..suspended = true;
      final dio = _client(server);

      await DeviceHeartbeat.report(dio);
      expect(BusinessBoundary.blocked.value, 'company_suspended');
      expect(server.reached, contains('/device/heartbeat'));

      server
        ..suspended = false
        ..reached.clear();
      await DeviceHeartbeat.report(dio);

      // The blocked identity lookup is refused locally; the heartbeat still
      // goes out, lifts the block, and the lookup then completes at once.
      expect(server.reached, ['/device/heartbeat', '/device/identity']);
      expect(BusinessBoundary.blocked.value, isNull);
      expect(BusinessBoundary.canWork, isTrue);
      expect(BusinessBoundary.current!.isProvisional, isFalse);
      expect(BusinessBoundary.current!.companyId, provisional.companyId);
      expect(BusinessBoundary.current!.branchId, provisional.branchId);
    },
  );

  test('D1 a failed identity lookup never skips the heartbeat', () async {
    await loadFix2ReleaseStorage();
    final provisional = BusinessBoundary.current!;
    final server = _Server(provisional.companyId, provisional.branchId)
      ..identityMissing = true;

    await DeviceHeartbeat.report(_client(server));

    expect(server.reached, ['/device/identity', '/device/heartbeat']);
    expect(BusinessBoundary.canWork, isTrue);
    expect(BusinessBoundary.current!.isProvisional, isTrue);
  });
}
