import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';

// Fix 10 (F-60): the real repository and a real Drift database. Only the HTTP
// boundary is supplied (it records pushes and refuses the connection) and the
// archive reader is a fixed map, as LocalOrderStorageService would return.
Map<String, dynamic> _event(String id, String type, Map<String, dynamic> p) => {
  'client_event_id': id,
  'event_type': type,
  'client_timestamp': '2026-09-28T10:00:00Z',
  'payload': p,
};

void main() {
  late AppDatabase db;
  late OrderSyncRepository repository;
  late List<Map<String, dynamic>> pushed;
  late String archivedJson;

  const archivedKey = 'tbl:seat-a:open';
  const parkedKey = 'tbl:seat-b:round:r1';
  const liveKey = 'tbl:seat-c:open';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    pushed = [];
    final dio = Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            final body = o.data;
            if (body is Map && body['events'] is List) {
              pushed.addAll(
                (body['events'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
            }
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );
    repository = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'fixture', dio: dio),
      db,
    );
    final old = DateTime.now().subtract(const Duration(minutes: 5));
    archivedJson = jsonEncode([
      _event('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'table.session.open', {
        'table_id': 3,
        'seating_key': 'seat-a',
        'order_uuid': 'archived-bill',
      }),
    ]);
    for (final (key, json) in [
      (archivedKey, archivedJson),
      (
        parkedKey,
        jsonEncode([
          _event(
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            'table.session.round',
            {
              'table_id': 4,
              'seating_key': 'seat-b',
              'order_uuid': 'parked-bill',
            },
          ),
        ]),
      ),
      (
        liveKey,
        jsonEncode([
          _event('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'table.session.open', {
            'table_id': 5,
            'seating_key': 'seat-c',
            'order_uuid': 'live-bill',
          }),
        ]),
      ),
    ]) {
      await db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: Value(key),
          eventsJson: Value(json),
          orderNumber: const Value(0),
          createdAt: Value(old),
        ),
      );
    }
    // The archived row and one live row are parked (deterministic refusals).
    await (db.update(
      db.orderOutbox,
    )..where((t) => t.orderUuid.isIn([archivedKey, parkedKey]))).write(
      const OrderOutboxCompanion(
        serverRejections: Value(OrderSyncRepository.maxServerRejections),
      ),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await db.close();
  });

  List<String> keys(Iterable<OrderOutboxRow> rows) =>
      rows.map((r) => r.orderUuid).toList()..sort();

  test(
    'F60 archived table-copy request is not pending, stuck or sent',
    () async {
      // Without the archive every row is pending (the pre-discard state).
      expect(
        keys(await repository.watchPending().first),
        [liveKey, archivedKey, parkedKey]..sort(),
      );
      repository.archivedTableCopies = () async => {archivedKey: archivedJson};

      expect(
        keys(await repository.pendingRows()),
        [liveKey, parkedKey]..sort(),
      );
      expect(
        keys(await repository.watchPending().first),
        [liveKey, parkedKey]..sort(),
      );
      expect(keys(await repository.watchStuck().first), [parkedKey]);
      expect(
        (await repository.watchAttention().first).map((a) => a.row.orderUuid),
        [parkedKey],
      );
      expect(keys(await repository.stuckBatches()), [parkedKey]);

      await repository.retryAttention();
      await repository.flush();
      expect(
        pushed.map((e) => e['client_event_id']),
        isNot(contains('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')),
        reason: 'an archived request is never sent, even after "retry"',
      );
      expect(
        pushed.map((e) => e['client_event_id']),
        contains('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
        reason: 'real pending work is still sent',
      );
      final archived = (await repository.allRows()).singleWhere(
        (r) => r.orderUuid == archivedKey,
      );
      expect(
        archived.syncedAt,
        isNull,
        reason: 'no fabricated acknowledgement',
      );
      expect(archived.eventsJson, archivedJson, reason: 'the row is immutable');
    },
  );

  test(
    'F60 a changed archived request blocks sending but stays visible',
    () async {
      repository.archivedTableCopies = () async => {archivedKey: '[]'};
      await expectLater(repository.pendingRows(), throwsStateError);
      expect(
        keys(await repository.watchPending().first),
        [liveKey, archivedKey, parkedKey]..sort(),
      );
    },
  );

  test('F60 the per-row archive check alone gives the same result', () async {
    repository.tableCopyArchived = (key, json) async {
      if (key != archivedKey) return false;
      if (json != archivedJson) throw StateError('Archived request changed');
      return true;
    };
    expect(keys(await repository.pendingRows()), [liveKey, parkedKey]..sort());
    expect(
      keys(await repository.watchPending().first),
      [liveKey, parkedKey]..sort(),
    );
    expect(keys(await repository.watchStuck().first), [parkedKey]);
  });
}
