import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'B12e activation rebuilds all four retained providers without restart',
    () async {
      BusinessBoundary.resetForTest();
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        BusinessBoundary.identityKey: const BusinessIdentity(1, 2, 'd').encoded,
      });
      final prefs = await SharedPreferences.getInstance();
      await BusinessBoundary.initialize(prefs);
      final builds = [0, 0, 0, 0];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(TenantPreferences(prefs)),
          sessionServiceProvider.overrideWithValue(
            SessionService(
              const FlutterSecureStorage(),
              TenantPreferences(prefs),
            ),
          ),
          qrSettlementOutboxProvider.overrideWith((ref) {
            builds[0]++;
            return _Outbox();
          }),
          stuckOrderSyncProvider.overrideWith((ref) {
            builds[1]++;
            return const Stream.empty();
          }),
          orderSyncAttentionProvider.overrideWith((ref) {
            builds[2]++;
            return const Stream.empty();
          }),
          geofenceProvider.overrideWith((ref) {
            builds[3]++;
            return const Stream.empty();
          }),
        ],
      );
      addTearDown(() {
        container.dispose();
        BusinessBoundary.resetForTest();
      });
      container.listen(qrSettlementOutboxProvider, (_, __) {});
      container.listen(stuckOrderSyncProvider, (_, __) {});
      container.listen(orderSyncAttentionProvider, (_, __) {});
      container.listen(geofenceProvider, (_, __) {});
      expect(builds, [1, 1, 1, 1]);
      await container
          .read(sessionControllerProvider.notifier)
          .saveActivation(
            const PairResult(
              deviceToken: 'new',
              deviceUuid: 'd',
              companyId: 1,
              branchId: 3,
            ),
          );
      await container.pump();
      expect(builds, [2, 2, 2, 2]);
    },
  );
}

class _Outbox implements QrSettlementOutbox {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
