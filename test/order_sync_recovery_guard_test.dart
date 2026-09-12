import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('admission waits for preparation and refuses its pending row', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    final preparing = Completer<void>();
    final releasePreparation = Completer<void>();
    var admitted = false;
    final event = _event('round', type: 'table.session.round.append');
    final enqueue = harness.repository.enqueueEvent(
      'tbl:seating:round:1',
      event,
      beforeFlush: () async {
        preparing.complete();
        await releasePreparation.future;
        return {...event, 'prepared': true};
      },
    );
    await preparing.future;

    final admission = expectLater(
      harness.repository.admitDraftRecovery(() async => admitted = true),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    expect(admitted, isFalse);
    expect(harness.adapter.requests, isEmpty);

    releasePreparation.complete();
    await admission;
    await enqueue;
    expect(admitted, isFalse);
    expect(harness.adapter.requests.single.single['prepared'], isTrue);
    expect(
      (await harness.repository.rowForKey('tbl:seating:round:1'))!.syncedAt,
      isNotNull,
    );
  });

  final enqueuers = <String, Future<void> Function(OrderSyncRepository)>{
    'event and following transfer event': (repository) =>
        repository.enqueueEvent(
          'tbl:seating:move:1',
          _event('move', type: 'table.session.move'),
          followingEvents: {
            'tbl:seating:join:1': _event('join', type: 'table.session.join'),
          },
        ),
    'snapshot': (repository) => repository.enqueue(_snapshot()),
    'void': (repository) => repository.enqueueVoid('bill'),
    'hold': (repository) => repository.enqueueHold(_draft()),
    'standalone payment': (repository) async {
      await repository.enqueueStandaloneQrPay(
        orderUuid: 'bill',
        frozenAmountBaisas: 2500,
        method: 'cash',
      );
    },
  };

  for (final entry in enqueuers.entries) {
    test(
      '${entry.key} waits for admission then rechecks durable guard',
      () async {
        final harness = _Harness();
        addTearDown(harness.close);
        final enteredAdmission = Completer<void>();
        final releaseAdmission = Completer<void>();
        final admission = harness.repository.admitDraftRecovery(() async {
          enteredAdmission.complete();
          await releaseAdmission.future;
          harness.recoveryPending = true;
        });
        await enteredAdmission.future;

        final mutation = expectLater(
          entry.value(harness.repository),
          throwsStateError,
        );
        await Future<void>.delayed(Duration.zero);
        expect(harness.guardChecks, 0);
        expect(await harness.rows(), isEmpty);
        expect(harness.adapter.requests, isEmpty);

        releaseAdmission.complete();
        await admission;
        await mutation;
        expect(harness.guardChecks, 1);
        expect(await harness.rows(), isEmpty);
        expect(harness.adapter.requests, isEmpty);
      },
    );
  }

  for (final pendingKind in ['queued', 'parked', 'missing GPS']) {
    test(
      'admission retains and refuses $pendingKind evidence without flushing',
      () async {
        final harness = _Harness();
        addTearDown(harness.close);
        if (pendingKind == 'missing GPS') {
          await harness.db
              .into(harness.db.branchCache)
              .insert(
                BranchCacheCompanion.insert(
                  latitude: const Value(23.59),
                  longitude: const Value(58.38),
                ),
              );
        }
        await harness.seed(
          'bill',
          _event(
            'create',
            type: 'order.create',
            payload: {
              'order': {'uuid': 'bill'},
            },
          ),
          serverRejections: pendingKind == 'parked'
              ? OrderSyncRepository.maxServerRejections
              : 0,
        );
        final before = await harness.rows();
        var admitted = false;

        await expectLater(
          harness.repository.admitDraftRecovery(() async => admitted = true),
          throwsStateError,
        );

        expect(admitted, isFalse);
        expect(await harness.rows(), before);
        expect(harness.adapter.requests, isEmpty);
        expect(harness.guardChecks, 0);
      },
    );
  }

  test(
    'admission preserves synced history and leaves startup reads usable',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.seed(
        'tbl:seating:move:3',
        _event('move', type: 'table.session.move'),
        synced: true,
      );
      final before = await harness.rows();

      await harness.repository.admitDraftRecovery(() async {
        harness.recoveryPending = true;
      });

      expect(await harness.repository.pendingRows(), isEmpty);
      expect(await harness.repository.stuckBatches(), isEmpty);
      expect(await harness.repository.watchPending().first, isEmpty);
      expect(await harness.repository.watchAttention().first, isEmpty);
      expect(
        await harness.repository.rowForKey('tbl:seating:move:3'),
        isNotNull,
      );
      expect(await harness.repository.resolveTableBillUuid('bill'), 'bill');
      expect(
        await harness.repository.nextTableOperationNumber('seating', 'move'),
        4,
      );
      expect(
        await harness.repository.hasUnresolvedStandaloneQrPay('bill'),
        isFalse,
      );
      await harness.repository.assertIdleForCombine();
      expect(harness.guardChecks, 0);
      expect(await harness.rows(), before);
      expect(harness.adapter.requests, isEmpty);
    },
  );

  test(
    'pending recovery prevents flush, retries, retirement and UUID rewriting',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.seed(
        'bill',
        _event('pay', type: 'order.pay', payload: {'order_uuid': 'old-bill'}),
        serverRejections: OrderSyncRepository.maxServerRejections,
      );
      await harness.seed(
        'bill:pay',
        _event('qr-pay', type: 'order.pay', payload: {'order_uuid': 'bill'}),
        serverRejections: OrderSyncRepository.maxServerRejections,
      );
      await harness.seed(
        'tbl:seating:round:1',
        _event('round', type: 'table.session.round.append'),
      );
      final before = await harness.rows();
      harness.recoveryPending = true;

      await expectLater(harness.repository.flush(), throwsStateError);
      await expectLater(harness.repository.retryAttention(), throwsStateError);
      await expectLater(harness.repository.retryStuck(), throwsStateError);
      await expectLater(
        harness.repository.retireStandaloneQrPay('bill', reason: 'released'),
        throwsStateError,
      );
      await expectLater(
        harness.repository.rewritePendingOrderUuid(
          'seating',
          'old-bill',
          'new-bill',
        ),
        throwsStateError,
      );

      expect(await harness.rows(), before);
      expect(harness.adapter.requests, isEmpty);
      expect(harness.guardChecks, 5);
    },
  );

  test(
    'admission waits for ACK rewrites without deadlocking the active flush',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await harness.seed(
        'tbl:seating:open',
        _event('open', type: 'table.session.open'),
      );
      await harness.seed(
        'local-bill',
        _event('pay', type: 'order.pay', payload: {'order_uuid': 'old-bill'}),
        createdAt: DateTime.utc(2026, 8, 8, 10, 1),
      );
      final ackEntered = Completer<void>();
      final releaseAck = Completer<void>();
      harness.repository.addAckListener((row, _, _) async {
        if (row.orderUuid != 'tbl:seating:open') return;
        ackEntered.complete();
        await releaseAck.future;
        await harness.repository.rewritePendingOrderUuid(
          'seating',
          'old-bill',
          'canonical-bill',
        );
      });
      final flush = harness.repository.flush();
      await ackEntered.future;
      var admitted = false;
      final admission = harness.repository.admitDraftRecovery(() async {
        admitted = true;
        harness.recoveryPending = true;
      });
      final externalRewrite = expectLater(
        harness.repository.rewritePendingOrderUuid(
          'seating',
          'canonical-bill',
          'unexpected-bill',
        ),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(admitted, isFalse);
      expect(harness.adapter.requests, hasLength(1));

      releaseAck.complete();
      expect(await flush.timeout(const Duration(seconds: 5)), 2);
      await admission;
      await externalRewrite;
      expect(admitted, isTrue);
      expect(harness.adapter.requests.last.single['payload'], {
        'order_uuid': 'canonical-bill',
      });
      final retained = await harness.repository.rowForKey('local-bill');
      expect(retained!.syncedAt, isNotNull);
      expect(
        (jsonDecode(retained.eventsJson) as List).single['client_event_id'],
        'pay',
      );
    },
  );

  test('a completed ACK scope cannot bypass a later recovery guard', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    await harness.seed('open', _event('open', type: 'table.session.open'));
    final releaseDetachedWork = Completer<void>();
    late Future<void> detachedWork;
    harness.repository.addAckListener((_, _, _) {
      detachedWork = () async {
        await releaseDetachedWork.future;
        await expectLater(
          harness.repository.rewritePendingOrderUuid('seating', 'old', 'new'),
          throwsStateError,
        );
      }();
    });
    expect(await harness.repository.flush(), 1);
    await harness.repository.admitDraftRecovery(() async {
      harness.recoveryPending = true;
    });

    releaseDetachedWork.complete();
    await detachedWork;
    expect(harness.guardChecks, 2);
  });

  test(
    'admission or guard failure does not poison subsequent queue work',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      await expectLater(
        harness.repository.admitDraftRecovery(() async {
          throw StateError('local journal creation failed');
        }),
        throwsStateError,
      );
      harness.recoveryPending = true;
      await expectLater(
        harness.repository.enqueueVoid('blocked'),
        throwsStateError,
      );
      harness.recoveryPending = false;

      await harness.repository.enqueueVoid('allowed');

      expect(await harness.repository.rowForKey('blocked:void'), isNull);
      expect(
        (await harness.repository.rowForKey('allowed:void'))!.syncedAt,
        isNotNull,
      );
      expect(harness.adapter.requests, hasLength(1));
    },
  );
}

Map<String, dynamic> _event(
  String eventId, {
  required String type,
  Map<String, dynamic> payload = const {},
}) => {'client_event_id': eventId, 'event_type': type, 'payload': payload};

OrderSnapshot _snapshot() => OrderSnapshot.initial().copyWith(
  orderType: 'quick_order',
  items: const [
    {'id': '10', 'name': 'Latte', 'qty': 1, 'unitPrice': 2.5, 'lineTotal': 2.5},
  ],
  rawSubtotal: 2.5,
  total: 2.5,
  paymentMethod: 'Cash',
);

OrderSessionDraft _draft() => OrderSessionDraft(
  orderReference: 'held-bill',
  orderType: OrderType.quickOrder,
  selectedCategory: 'Coffee',
  customerReferenceNumber: '',
  items: [
    CartItem(
      product: const Product(
        id: '10',
        name: 'Latte',
        category: 'Coffee',
        price: 2.5,
      ),
    ),
  ],
  discount: const DiscountConfiguration(),
  splitCount: 1,
  serverOrderUuid: 'bill',
);

class _Harness {
  _Harness() {
    dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
      ..httpClientAdapter = adapter;
    repository = OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
      mutationGuard: () async {
        guardChecks++;
        if (recoveryPending) throw StateError('Finish draft recovery first.');
      },
    );
  }

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final adapter = _SyncAdapter();
  late final Dio dio;
  late final OrderSyncRepository repository;
  bool recoveryPending = false;
  int guardChecks = 0;

  Future<List<Map<String, dynamic>>> rows() async => [
    for (final row in await db.select(db.orderOutbox).get()) row.toJson(),
  ];

  Future<void> seed(
    String key,
    Map<String, dynamic> event, {
    int serverRejections = 0,
    DateTime? createdAt,
    bool synced = false,
  }) => db.enqueueOutbox(
    OrderOutboxCompanion.insert(
      orderUuid: key,
      eventsJson: jsonEncode([event]),
      orderNumber: const Value(1001),
      createdAt: createdAt ?? DateTime.utc(2026, 8, 8, 10),
      attempts: Value(serverRejections),
      serverRejections: Value(serverRejections),
      lastError: Value(serverRejections > 0 ? 'retained refusal' : null),
      syncedAt: Value(synced ? DateTime.utc(2026, 8, 8, 12) : null),
    ),
  );

  Future<void> close() async {
    dio.close(force: true);
    await repository.dispose();
    await db.close();
  }
}

class _SyncAdapter implements HttpClientAdapter {
  final List<List<Map<String, dynamic>>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final events =
        (jsonDecode(jsonEncode((options.data as Map)['events'])) as List)
            .map((event) => (event as Map).cast<String, dynamic>())
            .toList();
    requests.add(events);
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': 'processed',
                'result': {'status': 'paid'},
              },
          ],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
