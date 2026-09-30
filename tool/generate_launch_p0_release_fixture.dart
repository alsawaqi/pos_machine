import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'generate actual release storage and wire payloads from the T3 copy',
    () async {
      final root = Directory(Platform.environment['P0_RELEASE_OUTPUT']!);
      final source = Directory(root.path + '/t3');
      final out = Directory(root.path + '/generated')
        ..createSync(recursive: true);
      for (final f in source.listSync().whereType<File>()) {
        await f.copy(out.path + '/' + f.uri.pathSegments.last);
      }
      final prefs = Map<String, Object>.from(
        jsonDecode(File(root.path + '/prefs.json').readAsStringSync()),
      );
      expect(prefs.containsKey('device_uuid'), false);
      SharedPreferences.setMockInitialValues(prefs);
      // The captured files intentionally exclude secure storage. This test-only
      // credential substitutes the secure channel, not the release preference format.
      FlutterSecureStorage.setMockInitialValues({
        'device_token': 'release-fixture-token',
      });
      final session = SessionService(
        const FlutterSecureStorage(),
        await SharedPreferences.getInstance(),
      );
      await session.load();
      expect(session.deviceToken, 'release-fixture-token');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(out.path);
      final orders = await openDatabase(out.path + '/mithqal_orders.db');
      final storage = LocalOrderStorageService.forTesting(orders);
      final drift = AppDatabase.forTesting(
        NativeDatabase(File(out.path + '/pos_machine_cache.sqlite')),
      );
      final sync = OrderSyncRepository(_Offline(), drift);
      final inputs = <Map<String, dynamic>>[];
      for (final kind in ['comp', 'gift']) {
        final snapshot = OrderSnapshot.initial().copyWith(
          orderNumber: kind == 'comp' ? 920001 : 920002,
          orderType: 'quick_order',
          paymentMethod: 'Cash',
          items: [
            {
              'id': '1',
              'name': 'Release fixture item',
              'qty': 2,
              'unitPrice': 1.5,
              'lineTotal': 3.0,
              if (kind == 'gift') ...{'gifted': true, 'giftAmount': 3.0},
            },
          ],
          rawSubtotal: 3,
          compAmount: kind == 'comp' ? 1.5 : 3,
          compReasonId: kind == 'comp' ? 2 : null,
          total: kind == 'comp' ? 1.5 : 0,
        );
        await storage.saveCompletedOrder(snapshot);
        await sync.enqueue(snapshot, staffId: 7, lat: 23.5, lng: 58.5);
        inputs.add(snapshot.toMap());
      }
      final held = OrderSessionDraft(
        orderReference: 'FIX2-RELEASE-HELD',
        orderType: OrderType.quickOrder,
        selectedCategory: 'Coffee',
        customerReferenceNumber: '',
        items: [
          CartItem(
            product: const Product(
              id: '1',
              name: 'Release fixture item',
              category: 'Coffee',
              price: 1.5,
            ),
          ),
        ],
        discount: const DiscountConfiguration(),
        splitCount: 1,
      );
      await storage.saveHeldOrder(held);
      final event = buildTableSessionEvent(
        'open',
        seatingKey: '22222222-2222-4222-8222-222222222222',
        tableId: '1',
        staffId: 7,
        queuedOffline: true,
        payload: {
          'opened_at': DateTime.now().toUtc().toIso8601String(),
          'order_uuid': '44444444-4444-4444-8444-444444444444',
        },
        newUuid: () => '33333333-3333-4333-8333-333333333333',
      );
      await sync.enqueueEvent('fix2-release-table', event);
      final pending = await drift.pendingOutbox();
      final generated = pending
          .where(
            (r) =>
                r.orderNumber == 920001 ||
                r.orderNumber == 920002 ||
                r.orderUuid == 'fix2-release-table',
          )
          .toList();
      expect(generated, hasLength(3));
      final payloads = [
        for (final r in generated)
          ...List<Map<String, dynamic>>.from(jsonDecode(r.eventsJson)),
      ];
      expect(payloads.every((e) => !e.containsKey('identity')), true);
      File(root.path + '/card-pay.json').writeAsStringSync(
        jsonEncode(
          buildStandaloneQrPayEvent(
            orderUuid: payloads.first['payload']['order']['uuid'],
            frozenAmountBaisas: 1500,
            method: 'card',
          ),
        ),
      );
      File(
        root.path + '/payloads.json',
      ).writeAsStringSync(jsonEncode(payloads));
      File(root.path + '/snapshots.json').writeAsStringSync(jsonEncode(inputs));
      File(
        root.path + '/held.json',
      ).writeAsStringSync(jsonEncode(held.toMap()));
      File(root.path + '/expected.json').writeAsStringSync(
        jsonEncode({
          'company_id': session.companyId,
          'branch_id': session.branchId,
          'generated_event_ids': [
            for (final e in payloads) e['client_event_id'],
          ],
          'held_reference': held.orderReference,
          'secure_token': 'release-fixture-token',
          'release': '01d17de',
        }),
      );
      await sync.dispose();
      await drift.close();
      await orders.close();
    },
  );
}

class _Offline extends PosApiService {
  _Offline() : super(tokenGetter: () => null);
  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async => throw const SocketException('fixture is offline');
}
