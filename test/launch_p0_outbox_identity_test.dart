import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/device_heartbeat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _Api api;
  late OrderSyncRepository repository;
  const owner = BusinessIdentity(1, 2, 'uuid');
  setUp(() async {
    BusinessBoundary.resetForTest();
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    db = AppDatabase.forTesting(NativeDatabase.memory());
    BusinessBoundary.registerWiper(db.wipeTenantData);
    api = _Api();
    repository = OrderSyncRepository(api, db);
  });
  tearDown(() async {
    DeviceHeartbeat.stop();
    await repository.dispose();
    await db.close();
    BusinessBoundary.resetForTest();
  });

  test(
    'W2 till outbox never sends a foreign identity and preserves financial evidence',
    () async {
      await db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: const Value('foreign'),
          createdAt: Value(DateTime.now()),
          eventsJson: Value(
            jsonEncode([
              {
                'client_event_id': 'evt',
                'event_type': 'expense.log',
                'payload': {'amount': 1200},
                'identity': const BusinessIdentity(99, 22, 'uuid').toJson(),
              },
            ]),
          ),
        ),
      );
      expect(await repository.flush(), 0);
      expect(api.sent, isEmpty);
      expect(await db.pendingOutbox(), isEmpty);
      expect(BusinessBoundary.quarantinedCount, 1);
    },
  );

  test(
    'W2 current event is tagged on durable enqueue and sent with the original tag',
    () async {
      await repository.enqueueEvent('expense', {
        'client_event_id': 'expense',
        'event_type': 'expense.log',
        'payload': {'amount': 1200},
      });
      expect(api.sent, hasLength(1));
      expect(api.sent.single['identity'], owner.toJson());
      expect(await db.pendingOutbox(), isEmpty);
    },
  );

  test(
    'W2 activation wipes every Drift cache table and archives unsent events',
    () async {
      await db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: const Value('pending'),
          createdAt: Value(DateTime.now()),
          eventsJson: Value(
            jsonEncode([
              {'event_type': 'expense.log', 'client_event_id': 'pending'},
            ]),
          ),
        ),
      );
      await BusinessBoundary.accept(const BusinessIdentity(1, 3, 'uuid'));
      for (final table in db.allTables) {
        expect(
          await db
              .customSelect('SELECT * FROM "' + table.actualTableName + '"')
              .get(),
          isEmpty,
        );
      }
      expect(BusinessBoundary.quarantinedCount, 1);
    },
  );

  test(
    'W2 an old repository cannot enqueue after even same-identity activation',
    () async {
      await BusinessBoundary.accept(owner);
      await expectLater(
        repository.enqueueEvent('late', {
          'client_event_id': 'late',
          'event_type': 'expense.log',
          'payload': {},
        }),
        throwsStateError,
      );
      expect(api.sent, isEmpty);
    },
  );

  test('W2 release till starts with no demo products or tables', () {
    final controller = PosController(releaseBuild: true);
    addTearDown(controller.dispose);
    expect(controller.allProducts, isEmpty);
    expect(controller.diningTableDefinitions, isEmpty);
  });
}

class _Api extends PosApiService {
  _Api() : super(tokenGetter: () => null);
  final sent = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    sent.addAll(events);
    return {
      'results': [
        for (final event in events)
          {
            'client_event_id': event['client_event_id'],
            'status': 'processed',
            'duplicate': false,
            'result': {},
          },
      ],
    };
  }
}
