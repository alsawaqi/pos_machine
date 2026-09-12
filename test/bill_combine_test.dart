import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/bill_combine/combine_controller.dart';
import 'package:pos_machine/bill_combine/combine_models.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';

const sourceId = '11111111-1111-4111-8111-111111111111';
const targetId = '22222222-2222-4222-8222-222222222222';
const seatingId = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> line() => {
  'product_id': 7,
  'qty': 1,
  'name': 'Coffee',
  'notes': '',
  'unit_price_baisas': 1000,
  'line_total_baisas': 1000,
  'addons': <dynamic>[],
};
Map<String, dynamic> bill(String uuid) => {
  'uuid': uuid,
  'source': uuid == sourceId ? 'main_pos' : 'qr_web',
  'status': 'open',
  'temp_reference': uuid == sourceId ? 'OLD' : 'T-001',
  'receipt_number': null,
  'subtotal_baisas': 1000,
  'discount_total_baisas': 0,
  'comp_total_baisas': 0,
  'tax_total_baisas': 0,
  'grand_total_baisas': 1000,
  'items': [
    {...line(), 'id': 1, 'status': 'open', 'line_discount_baisas': 0},
  ],
};
Map<String, dynamic> previewJson() => {
  'combine_policy': 'local_owner_v1',
  'table_id': 1,
  'table_label': 'T1',
  'table_session_uuid': seatingId,
  'source': bill(sourceId),
  'target': bill(targetId),
  'combined_grand_total_baisas': 2000,
  'preview_token': '2000000000.${'a' * 64}',
  'requires_manager_pin': true,
  'kitchen_submission': false,
  'reason': 'same_party_duplicate_bill',
};
CombineLocal localSnapshot({String draft = 'original'}) => CombineLocal({
  'uuid': sourceId,
  'table_id': 1,
  'discount_baisas': 0,
  'lines': [line()],
  'rows': [
    {
      'table': 'held_orders',
      'pk': 'uuid',
      'value': sourceId,
      'row': {'uuid': sourceId, 'draft': draft},
    },
  ],
});
Map<String, dynamic> ack() => {
  'outcome': 'combined',
  'source_status': 'combined',
  'source_order_uuid': sourceId,
  'order_uuid': targetId,
  'table_session_uuid': seatingId,
  'grand_total_baisas': 2000,
  'temp_reference': 'T-001',
  'receipt_number': null,
  'event_id': 90,
  'round_id': 3,
  'approved_by_staff_id': 8,
};
Map<String, dynamic> success() => {
  'data': {'status': 'processed', 'result': ack()},
  'errors': [],
};

class Gateway implements CombineGateway {
  int previews = 0;
  final sent = <Map<String, dynamic>>[];
  Map<String, dynamic> remote = previewJson();
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? respond;
  @override
  Future<Map<String, dynamic>> preview(int tableId, String uuid) async {
    previews++;
    return remote;
  }

  @override
  Future<Map<String, dynamic>> confirm(
    int tableId,
    Map<String, dynamic> input,
  ) async {
    sent.add(Map.of(input));
    return respond == null ? success() : await respond!(input);
  }
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late CombineStore store;
  late Gateway gateway;
  late CombineController controller;
  Future<void> idle() async {}
  CombineController create({
    Future<void> Function()? guard,
    Future<CombineLocal> Function(int)? load,
  }) => CombineController(
    store: store,
    gateway: gateway,
    tableId: 1,
    loadLocal: load ?? (_) async => localSnapshot(),
    checkIdle: guard ?? idle,
  );
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE held_orders (uuid TEXT PRIMARY KEY, draft TEXT NOT NULL)',
    );
    await db.insert('held_orders', {'uuid': sourceId, 'draft': 'original'});
    await CombineStore.createSchema(db);
    await RecoveryStore.createSchema(db);
    store = CombineStore(db, 'device-scope');
    gateway = Gateway();
    controller = create();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  test(
    'review reads frozen bills without creating intent or changing local rows',
    () async {
      await controller.start();
      expect(controller.error, null);
      expect(controller.canLeave, true);
      expect(await store.active(), null);
      expect(gateway.sent, isEmpty);
      expect(await db.query('held_orders'), [
        {'uuid': sourceId, 'draft': 'original'},
      ]);
    },
  );
  test(
    'saves exact intent before POST; double tap is one request; archives only on ACK',
    () async {
      final response = Completer<Map<String, dynamic>>();
      gateway.respond = (input) async {
        expect((await store.active())!.payload, {...input}..remove('pin'));
        expect(await db.query('held_orders'), hasLength(1));
        return response.future;
      };
      await controller.start();
      final run = controller.confirm('4321');
      while (gateway.sent.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.confirm('4321');
      expect(gateway.sent, hasLength(1));
      expect(controller.canLeave, false);
      response.complete(success());
      await run;
      expect(controller.attempt!.state, 'done');
      expect(await db.query('held_orders'), isEmpty);
      final saved = (await db.query('bill_combine_journal')).single;
      expect(saved['state'], 'done');
      expect(saved['payload'], contains('original'));
      expect(saved['payload'], contains('"event_id":90'));
      expect(saved['payload'], isNot(contains('4321')));
      expect(saved['payload'], isNot(contains('"pin"')));
      expect(await store.active(), null);
    },
  );
  test(
    'lost reply survives restart and retries identical intent, no second preview',
    () async {
      gateway.respond = (_) async =>
          throw StateError('reply lost after server commit');
      await controller.start();
      await controller.confirm('4321');
      final first = Map.of(gateway.sent.single);
      expect(await db.query('held_orders'), hasLength(1));
      expect(controller.canLeave, false);
      controller.dispose();
      controller = create();
      await controller.start();
      gateway.respond = (_) async => success();
      await controller.confirm('4321');
      expect(gateway.sent, [first, first]);
      expect(gateway.previews, 1);
      expect(controller.attempt!.state, 'done');
      expect(await db.query('held_orders'), isEmpty);
    },
  );
  for (final change in <String, dynamic>{
    'source_order_uuid': targetId,
    'order_uuid': sourceId,
    'table_session_uuid': sourceId,
    'grand_total_baisas': 1999,
    'event_id': null,
    'round_id': 0,
    'approved_by_staff_id': null,
    'temp_reference': 'OTHER',
    'receipt_number': 'wrong',
    'source_status': 'void',
    'outcome': 'replayed',
  }.entries) {
    test(
      'mismatched ${change.key} ACK retains pending intent and original local bill',
      () async {
        gateway.respond = (_) async => {
          'data': {
            'status': 'processed',
            'result': {...ack(), change.key: change.value},
          },
          'errors': [],
        };
        await controller.start();
        await controller.confirm('4321');
        expect(controller.error, isNotNull);
        expect((await store.active())!.state, 'pending');
        expect(await db.query('held_orders'), [
          {'uuid': sourceId, 'draft': 'original'},
        ]);
      },
    );
  }
  test(
    'pending work refuses before preview and no request is created',
    () async {
      controller.dispose();
      controller = create(
        guard: () async => throw StateError('outbox pending'),
      );
      await controller.start();
      expect(gateway.previews, 0);
      expect(gateway.sent, isEmpty);
      expect(await store.active(), null);
      expect(await db.query('held_orders'), hasLength(1));
    },
  );
  test(
    'local snapshot changes before approval: no POST and no retirement',
    () async {
      var original = true;
      controller.dispose();
      controller = create(
        load: (_) async =>
            localSnapshot(draft: original ? 'original' : 'changed'),
      );
      await controller.start();
      original = false;
      await controller.confirm('4321');
      expect(gateway.sent, isEmpty);
      expect(await store.active(), null);
    },
  );
  test('local CAS failure after ACK retains confirmed recovery copy', () async {
    gateway.respond = (_) async {
      await db.update('held_orders', {'draft': 'new local change'});
      return success();
    };
    await controller.start();
    await controller.confirm('4321');
    expect((await store.active())!.state, 'confirmed');
    expect(await db.query('held_orders'), [
      {'uuid': sourceId, 'draft': 'new local change'},
    ]);
    expect((await store.active())!.local.rows.single['row'], {
      'uuid': sourceId,
      'draft': 'original',
    });
  });
  test(
    'archive transaction rollback survives restart and does not resend or need PIN',
    () async {
      await db.execute(
        "CREATE TRIGGER fail_retire BEFORE DELETE ON held_orders BEGIN SELECT RAISE(ABORT, 'disk fault'); END",
      );
      await controller.start();
      await controller.confirm('4321');
      expect((await store.active())!.state, 'confirmed');
      expect(await db.query('held_orders'), hasLength(1));
      await db.execute('DROP TRIGGER fail_retire');
      controller.dispose();
      controller = create();
      await controller.start();
      await controller.confirm('');
      expect(controller.attempt!.state, 'done');
      expect(gateway.sent, hasLength(1));
    },
  );
  test(
    'expired not-applied proof releases intent without removing the local draft',
    () async {
      gateway.respond = (input) async => {
        'errors': [
          {'code': 'combine_preview_stale'},
        ],
        'combine_final_no_write': {...input, 'table_id': 1}..remove('pin'),
      };
      await controller.start();
      await controller.confirm('4321');
      expect(controller.attempt!.state, 'not_applied');
      expect(controller.canLeave, true);
      expect(await store.active(), null);
      expect(await db.query('held_orders'), hasLength(1));
    },
  );
  test(
    'generic refusal or mismatched release proof cannot unlock source',
    () async {
      gateway.respond = (input) async => {
        'errors': [
          {'code': 'combine_preview_stale'},
        ],
        'combine_final_no_write': {...input, 'table_id': 2}..remove('pin'),
      };
      await controller.start();
      await controller.confirm('4321');
      expect((await store.active())!.state, 'pending');
      gateway.respond = (_) async => {
        'errors': [
          {'message': 'refused'},
        ],
      };
      await controller.confirm('4321');
      expect((await store.active())!.state, 'pending');
    },
  );
  test(
    'background after server ACK persists confirmation but defers local retirement',
    () async {
      gateway.respond = (_) async {
        controller.setForeground(false);
        return success();
      };
      await controller.start();
      await controller.confirm('4321');
      expect((await store.active())!.state, 'confirmed');
      expect(await db.query('held_orders'), hasLength(1));
      controller.setForeground(true);
      await controller.confirm('');
      expect(controller.attempt!.state, 'done');
      expect(gateway.sent, hasLength(1));
    },
  );
  test('old server without the owner policy never enables combining', () async {
    gateway.remote.remove('combine_policy');
    await controller.start();
    expect(controller.preview, null);
    expect(controller.error, isNotNull);
    expect(gateway.sent, isEmpty);
  });
  test('PIN syntax failure never persists or sends', () async {
    await controller.start();
    await controller.confirm('12');
    expect(gateway.sent, isEmpty);
    expect(await store.active(), null);
  });
  test(
    'new copy inserted after ACK blocks atomic retirement of every copy',
    () async {
      await db.execute('ALTER TABLE held_orders ADD COLUMN table_json TEXT');
      controller.dispose();
      controller = create(
        load: (_) async {
          final raw = (await db.query(
            'held_orders',
            where: 'uuid = ?',
            whereArgs: [sourceId],
          )).single;
          return CombineLocal({
            ...localSnapshot().json,
            'rows': [
              {
                'table': 'held_orders',
                'pk': 'uuid',
                'value': sourceId,
                'row': raw,
              },
            ],
          });
        },
      );
      gateway.respond = (_) async {
        await db.insert('held_orders', {
          'uuid': targetId,
          'draft': 'new copy',
          'table_json': '{"table_id":1}',
        });
        return success();
      };
      await controller.start();
      await controller.confirm('4321');
      expect((await store.active())!.state, 'confirmed');
      expect(await db.query('held_orders'), hasLength(2));
      expect(controller.error, contains('copies changed'));
    },
  );
  test('missing original row after ACK never marks the journal done', () async {
    gateway.respond = (_) async {
      await db.delete('held_orders');
      return success();
    };
    await controller.start();
    await controller.confirm('4321');
    expect((await store.active())!.state, 'confirmed');
    expect(controller.canLeave, false);
    expect((await store.active())!.local.rows.single['row'], {
      'uuid': sourceId,
      'draft': 'original',
    });
  });
  test('journal insertion failure cannot send a request', () async {
    await db.execute(
      "CREATE TRIGGER fail_save BEFORE INSERT ON bill_combine_journal BEGIN SELECT RAISE(ABORT, 'disk fault'); END",
    );
    await controller.start();
    await controller.confirm('4321');
    expect(gateway.sent, isEmpty);
    expect(await store.active(), null);
    expect(await db.query('held_orders'), hasLength(1));
  });
  test(
    'pending journal blocks legacy mutation even in another scope',
    () async {
      final attempt = CombineAttempt({
        'id': seatingId,
        'state': 'pending',
        'local': localSnapshot().json,
        'preview': previewJson(),
      });
      await store.create(attempt);
      await expectLater(CombineStore.assertNonePending(db), throwsStateError);
      await expectLater(
        CombineStore(db, 'other').create(attempt),
        throwsStateError,
      );
      expect(await db.query('held_orders'), hasLength(1));
    },
  );
}
