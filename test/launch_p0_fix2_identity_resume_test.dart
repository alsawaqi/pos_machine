import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'package:pos_machine/tenancy/device_heartbeat.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'support/fix2_release_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(BusinessBoundary.resetForTest);
  test(
    'F1 release adoption resumes from saved marker and token resolves UUID atomically',
    () async {
      await loadFix2ReleaseStorage();
      final prefs = await SharedPreferences.getInstance();
      final owner = BusinessBoundary.current!;
      expect(owner.isProvisional, true);
      expect(prefs.getString(BusinessBoundary.legacyPreferencesKey), isNotNull);
      // Reboot at the identity-commit boundary, retaining the snapshot written
      // by the real adopter. No UUID or release business preference is invented.
      await prefs.remove(BusinessBoundary.identityKey);
      BusinessBoundary.resetForTest();
      await BusinessBoundary.initialize(prefs);
      final session = SessionService(
        const FlutterSecureStorage(),
        TenantPreferences(prefs),
      );
      await session.load();
      expect(session.deviceToken, 'release-fixture-token');
      expect(BusinessBoundary.canWork, true);
      final dio = Dio(
        BaseOptions(
          headers: {'Authorization': 'Bearer ' + session.deviceToken!},
        ),
      );
      final requests = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request.path);
            expect(
              request.headers['Authorization'],
              'Bearer release-fixture-token',
            );
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'data': request.path.endsWith('/identity')
                      ? {
                          'uuid': 'from-authenticated-server',
                          'company_id': owner.companyId,
                          'branch_id': owner.branchId,
                        }
                      : {},
                },
              ),
            );
          },
        ),
      );
      await DeviceHeartbeat.report(dio);
      expect(requests, ['/device/identity', '/device/heartbeat']);
      expect(BusinessBoundary.current!.deviceUuid, 'from-authenticated-server');
      BusinessBoundary.resetForTest();
      await BusinessBoundary.initialize(prefs);
      expect(BusinessBoundary.current!.deviceUuid, 'from-authenticated-server');
      final held = await LocalOrderStorageService.instance.loadHeldOrders();
      expect(
        held.any((h) => h.draft.orderReference == 'FIX2-RELEASE-HELD'),
        true,
      );
      expect(BusinessBoundary.quarantinedCount, 0);
    },
  );
}
