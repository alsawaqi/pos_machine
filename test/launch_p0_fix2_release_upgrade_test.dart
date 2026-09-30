import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'package:pos_machine/tenancy/tenant_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final offlineFirst in [false, true]) {
    test(
      'F1 real T3 release storage survives upgrade; offline first=' +
          offlineFirst.toString(),
      () async {
        BusinessBoundary.resetForTest();
        addTearDown(BusinessBoundary.resetForTest);
        const root = 'test/fixtures/release_01d17de';
        final prefsMap = Map<String, Object>.from(
          jsonDecode(File(root + '/prefs.json').readAsStringSync()),
        );
        expect(prefsMap.containsKey('device_uuid'), false);
        final expected =
            jsonDecode(File(root + '/expected.json').readAsStringSync()) as Map;
        final dir = await Directory.systemTemp.createTemp('fix2-t3-');
        for (final f in Directory(
          root + '/generated',
        ).listSync().whereType<File>()) {
          await f.copy(dir.path + '/' + f.uri.pathSegments.last);
        }
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        await databaseFactory.setDatabasesPath(dir.path);
        SharedPreferences.setMockInitialValues(prefsMap);
        FlutterSecureStorage.setMockInitialValues({
          'device_token': expected['secure_token'],
        });
        final raw = await SharedPreferences.getInstance();
        await BusinessBoundary.initialize(raw);
        final session = SessionService(
          const FlutterSecureStorage(),
          TenantPreferences(raw),
        );
        await session.load();
        expect(session.isConfigured, true);
        expect(
          BusinessBoundary.canWork,
          true,
          reason: 'No activation screen on the real release state',
        );
        final local = await openBusinessDatabase(
          dir.path + '/mithqal_orders.db',
        );
        final storage = LocalOrderStorageService.forTesting(local);
        final db = AppDatabase.forTesting(
          NativeDatabase(File(dir.path + '/pos_machine_cache.sqlite')),
        );
        final api = ReleaseAckApi()..offline = offlineFirst;
        final sync = OrderSyncRepository(api, db);
        BusinessBoundary.registerWiper(db.wipeTenantData);
        BusinessBoundary.registerWiper(wipeBusinessDatabases);
        final held = await storage.loadHeldOrders();
        expect(
          held.any((h) => h.draft.orderReference == expected['held_reference']),
          true,
        );
        final rows = await db.pendingOutbox();
        expect(
          rows.where((r) => r.orderNumber == 920001 || r.orderNumber == 920002),
          hasLength(2),
        );
        await sync.flush();
        if (offlineFirst) {
          expect(api.sent, isEmpty);
          expect(BusinessBoundary.canWork, true);
          api.offline = false;
          await sync.flush();
        }
        expect(
          api.sent.map((e) => e['client_event_id']),
          containsAll(expected['generated_event_ids']),
        );
        expect(
          api.sent.every((e) => !e.containsKey('identity')),
          true,
          reason:
              'Release backlog must be judged by the server cutoff, never relabelled',
        );
        expect(BusinessBoundary.quarantinedCount, 0);
        await session.saveActivation(
          PairResult(
            deviceToken: 'same-identity-new-token',
            companyId: session.companyId,
            branchId: session.branchId,
            deviceUuid: 'server-resolved-uuid',
          ),
        );
        expect(
          (await LocalOrderStorageService.forTesting(local).loadHeldOrders())
              .any((h) => h.draft.orderReference == expected['held_reference']),
          true,
        );
        expect(BusinessBoundary.quarantinedCount, 0);
        expect(BusinessBoundary.canWork, true);
        await sync.dispose();
        await db.close();
        await local.close();
      },
    );
  }
}

class ReleaseAckApi extends PosApiService {
  ReleaseAckApi() : super(tokenGetter: () => null);
  bool offline = false;
  final sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    if (offline) throw const SocketException('offline first boot');
    sent.addAll(events);
    return {
      'results': [
        for (final e in events)
          {
            'client_event_id': e['client_event_id'],
            'status': 'processed',
            'result': {'status': 'paid'},
          },
      ],
    };
  }
}
