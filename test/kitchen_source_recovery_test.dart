import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mithqal_kitchen_core/mithqal_kitchen_core.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/kitchen/kitchen_domain_store.dart';
import 'package:pos_machine/tenancy/business_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late OrderSyncRepository repo;
  late TillKitchenDomainStore domain;
  final owner = BusinessIdentity(1, 2, 'synthetic-device');
  Future<void> open() async {
    db = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/orders.sqlite')),
    );
    repo = OrderSyncRepository(PosApiService(tokenGetter: () => null), db);
    domain = TillKitchenDomainStore(repo);
  }

  setUp(() async {
    BusinessBoundary.resetForTest();
    SharedPreferences.setMockInitialValues({
      BusinessBoundary.identityKey: owner.encoded,
    });
    await BusinessBoundary.initialize(await SharedPreferences.getInstance());
    directory = await Directory.systemTemp.createTemp('mithqal-k3-till-');
    await open();
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
    BusinessBoundary.resetForTest();
    if (!directory.path.startsWith(Directory.systemTemp.path))
      throw StateError('unsafe');
    await directory.delete(recursive: true);
  });
  String payload(String id) => jsonEncode({
    'client_event_id': id,
    'event_type': 'order.hold',
    'payload': {'order_uuid': 'synthetic', 'value': 1.25},
  });
  test(
    'domain row and proof survive process-store reopen before kitchen READY',
    () async {
      final id = uuid(), raw = payload('ignored');
      final actual = payload(id);
      expect(
        await domain.evidence(id, domainDigest(raw)),
        DomainEvidence.absent,
      );
      await domain.persist(id, actual);
      await repo.dispose();
      await db.close();
      await open();
      expect(
        await domain.evidence(id, domainDigest(actual)),
        DomainEvidence.matching,
      );
      await domain.persist(id, actual);
      expect(await repo.allRows(), hasLength(1));
      await expectLater(
        domain.persist(id, payload(id).replaceAll('1.25', '2.25')),
        throwsStateError,
      );
      expect(await repo.allRows(), hasLength(1));
    },
  );
  test(
    'failed proof insert rolls back the actual financial outbox transaction',
    () async {
      final first = uuid();
      await domain.persist(first, payload(first));
      await db.customStatement(
        "CREATE TRIGGER reject_kitchen_proof BEFORE INSERT ON kitchen_domain_proofs BEGIN SELECT RAISE(ABORT,'disk full'); END",
      );
      final id = uuid();
      await expectLater(domain.persist(id, payload(id)), throwsA(anything));
      expect(await repo.allRows(), hasLength(1));
      expect(
        await domain.evidence(id, domainDigest(payload(id))),
        DomainEvidence.absent,
      );
    },
  );
  test('old assignment evidence cannot authorize a new branch', () async {
    final id = uuid();
    await domain.persist(id, payload(id));
    await BusinessBoundary.accept(BusinessIdentity(1, 3, 'new-assignment'));
    expect(
      await domain.evidence(id, domainDigest(payload(id))),
      DomainEvidence.conflict,
    );
    expect(() => domain.persist(uuid(), payload(id)), throwsStateError);
  });
  test(
    'PREPARED intent recovers against this actual domain store after both handles reopen',
    () async {
      sqfliteFfiInit();
      final folder = await Directory.systemTemp.createTemp(
        'mithqal-k3-intent-',
      );
      var journal = await KitchenStore.open(
        databaseFactoryFfi,
        '${folder.path}/intent.sqlite',
      );
      final peer = RecoveryPeer();
      final id = uuid();
      final Json event = {
        'protocol_version': 1,
        'event_id': uuid(),
        'epoch': 1,
        'occurred_at': '2026-10-09T00:00:00Z',
        'action': 'submit',
        'domain_event_uuid': id,
      };
      var source = KitchenSource(journal, domain, peer, owner.toJson());
      try {
        await source.prepare(event, id, payload(id));
        await source.recover();
        expect((await journal.db.query('intents')).single['state'], 'prepared');
        expect(peer.sends, 0);
        await domain.persist(id, payload(id));
        await journal.close();
        await repo.dispose();
        await db.close();
        await open();
        journal = await KitchenStore.open(
          databaseFactoryFfi,
          '${folder.path}/intent.sqlite',
        );
        source = KitchenSource(journal, domain, peer, owner.toJson());
        await source.recover();
        expect((await journal.db.query('intents')).single['state'], 'ready');
        await source.send(event['event_id']);
        await source.send(event['event_id']);
        expect(peer.sends, 1);
      } finally {
        await journal.close();
        if (!folder.path.startsWith(Directory.systemTemp.path))
          throw StateError('unsafe');
        await folder.delete(recursive: true);
      }
    },
  );
}

class RecoveryPeer implements KitchenPeer {
  int sends = 0;
  @override
  Future<Json> send(Json event, Json origin) async {
    sends++;
    return {'event_id': event['event_id'], 'durable': true};
  }
}
