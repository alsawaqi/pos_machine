import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fenced create and pay events gain fresh GPS without changing identity',
    () async {
      final geolocator = _FakeGeolocatorPlatform(
        positions: [_position(latitude: 23.588, longitude: 58.3829)],
      );
      final harness = await _harness(geolocator: geolocator, fenced: true);

      await _enqueue(
        harness.db,
        orderUuid: 'order-001',
        events: [
          {
            'client_event_id': 'create-event-001',
            'event_type': 'order.create',
            'client_timestamp': '2026-08-08T10:00:00.000Z',
            'payload': {
              'order': {
                'uuid': 'order-001',
                'gps': {'lat': 1.0},
              },
            },
          },
          {
            'client_event_id': 'pay-event-001',
            'event_type': 'order.pay',
            'client_timestamp': '2026-08-08T10:00:01.000Z',
            'payload': {'order_uuid': 'order-001'},
          },
        ],
      );

      expect(await harness.repository.flush(), 1);
      expect(geolocator.requestCount, 1);

      final sent = harness.adapter.requests.single;
      final create = sent[0];
      final createOrder = ((create['payload'] as Map)['order'] as Map)
          .cast<String, dynamic>();
      final pay = sent[1];
      final payPayload = (pay['payload'] as Map).cast<String, dynamic>();

      expect(createOrder['gps'], {'lat': 23.588, 'lng': 58.3829});
      expect(payPayload['gps'], {'lat': 23.588, 'lng': 58.3829});
      expect(create['client_event_id'], 'create-event-001');
      expect(create['client_timestamp'], '2026-08-08T10:00:00.000Z');
      expect(pay['client_event_id'], 'pay-event-001');
      expect(pay['client_timestamp'], '2026-08-08T10:00:01.000Z');
    },
  );

  test('no fresh fix holds only the affected fenced batch', () async {
    final geolocator = _FakeGeolocatorPlatform(error: StateError('no GPS'));
    final harness = await _harness(geolocator: geolocator, fenced: true);

    await _enqueue(
      harness.db,
      orderUuid: 'missing-gps',
      events: [_createEvent('missing-gps')],
      createdAt: DateTime.utc(2026, 8, 8, 9),
    );
    await _enqueue(
      harness.db,
      orderUuid: 'has-gps',
      events: [
        _createEvent('has-gps', gps: {'lat': 23.6, 'lng': 58.4}),
      ],
      createdAt: DateTime.utc(2026, 8, 8, 10),
    );

    expect(await harness.repository.flush(), 1);
    expect(geolocator.requestCount, 1);
    expect(
      harness.adapter.requests.single.single['client_event_id'],
      'create-has-gps',
    );

    final pending = await harness.db.pendingOutbox();
    expect(pending.single.orderUuid, 'missing-gps');
    expect(pending.single.attempts, 0);
    expect(pending.single.serverRejections, 0);
  });

  test('unfenced batches push unchanged without requesting location', () async {
    final geolocator = _FakeGeolocatorPlatform(error: StateError('unused'));
    final harness = await _harness(geolocator: geolocator, fenced: false);

    await _enqueue(
      harness.db,
      orderUuid: 'unfenced-order',
      events: [_createEvent('unfenced-order'), _payEvent('unfenced-order')],
    );

    expect(await harness.repository.flush(), 1);
    expect(geolocator.requestCount, 0);
    final sent = harness.adapter.requests.single;
    expect(_createOrder(sent[0]).containsKey('gps'), isFalse);
    expect(_payload(sent[1]).containsKey('gps'), isFalse);
  });

  test('complete GPS is preserved at a fenced branch', () async {
    final geolocator = _FakeGeolocatorPlatform(error: StateError('unused'));
    final harness = await _harness(geolocator: geolocator, fenced: true);
    final createGps = {'lat': 23.51, 'lng': 58.31};
    final payGps = {'lat': 23.52, 'lng': 58.32};

    await _enqueue(
      harness.db,
      orderUuid: 'located-order',
      events: [
        _createEvent('located-order', gps: createGps),
        _payEvent('located-order', gps: payGps),
      ],
    );

    expect(await harness.repository.flush(), 1);
    expect(geolocator.requestCount, 0);
    final sent = harness.adapter.requests.single;
    expect(_createOrder(sent[0])['gps'], createGps);
    expect(_payload(sent[1])['gps'], payGps);
  });

  test(
    'a transport retry re-enriches from durable events with a fresh fix',
    () async {
      final geolocator = _FakeGeolocatorPlatform(
        positions: [
          _position(latitude: 23.50, longitude: 58.30),
          _position(latitude: 23.60, longitude: 58.40),
        ],
      );
      final harness = await _harness(
        geolocator: geolocator,
        fenced: true,
        outcomes: [_SyncOutcome.networkFailure, _SyncOutcome.processed],
      );

      await _enqueue(
        harness.db,
        orderUuid: 'retry-order',
        events: [_createEvent('retry-order')],
      );

      expect(await harness.repository.flush(), 0);
      final durableAfterFailure =
          jsonDecode((await harness.db.pendingOutbox()).single.eventsJson)
              as List;
      expect(
        _createOrder(
          (durableAfterFailure.single as Map).cast(),
        ).containsKey('gps'),
        isFalse,
      );

      expect(await harness.repository.flush(), 1);
      expect(geolocator.requestCount, 2);
      expect(_createOrder(harness.adapter.requests[0].single)['gps'], {
        'lat': 23.50,
        'lng': 58.30,
      });
      expect(_createOrder(harness.adapter.requests[1].single)['gps'], {
        'lat': 23.60,
        'lng': 58.40,
      });
      expect(
        harness.adapter.requests.map(
          (request) => request.single['client_event_id'],
        ),
        everyElement('create-retry-order'),
      );
    },
  );
}

Future<_Harness> _harness({
  required _FakeGeolocatorPlatform geolocator,
  required bool fenced,
  List<_SyncOutcome> outcomes = const [_SyncOutcome.processed],
}) async {
  final originalGeolocator = GeolocatorPlatform.instance;
  GeolocatorPlatform.instance = geolocator;
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final adapter = _SyncAdapter(outcomes);
  final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
    ..httpClientAdapter = adapter;
  final harness = _Harness(
    originalGeolocator: originalGeolocator,
    db: db,
    adapter: adapter,
    dio: dio,
    repository: OrderSyncRepository(
      PosApiService(tokenGetter: () => 'device-token', dio: dio),
      db,
    ),
  );
  addTearDown(harness.close);
  await _cacheBranch(db, fenced: fenced);
  return harness;
}

Map<String, dynamic> _createEvent(
  String orderUuid, {
  Map<String, dynamic>? gps,
}) => {
  'client_event_id': 'create-$orderUuid',
  'event_type': 'order.create',
  'client_timestamp': '2026-08-08T10:00:00.000Z',
  'payload': {
    'order': {'uuid': orderUuid, 'gps': ?gps},
  },
};

Map<String, dynamic> _payEvent(String orderUuid, {Map<String, dynamic>? gps}) =>
    {
      'client_event_id': 'pay-$orderUuid',
      'event_type': 'order.pay',
      'client_timestamp': '2026-08-08T10:00:01.000Z',
      'payload': {'order_uuid': orderUuid, 'gps': ?gps},
    };

Map<String, dynamic> _payload(Map<String, dynamic> event) =>
    (event['payload'] as Map).cast<String, dynamic>();

Map<String, dynamic> _createOrder(Map<String, dynamic> event) =>
    (_payload(event)['order'] as Map).cast<String, dynamic>();

Future<void> _cacheBranch(AppDatabase db, {required bool fenced}) => db
    .into(db.branchCache)
    .insert(
      BranchCacheCompanion.insert(
        id: const Value(1),
        latitude: Value(fenced ? 23.59 : null),
        longitude: Value(fenced ? 58.38 : null),
      ),
    );

Future<void> _enqueue(
  AppDatabase db, {
  required String orderUuid,
  required List<Map<String, dynamic>> events,
  DateTime? createdAt,
}) => db.enqueueOutbox(
  OrderOutboxCompanion.insert(
    orderUuid: orderUuid,
    eventsJson: jsonEncode(events),
    orderNumber: const Value(1001),
    createdAt: createdAt ?? DateTime.utc(2026, 8, 8, 10),
  ),
);

Position _position({required double latitude, required double longitude}) =>
    Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.utc(2026, 8, 8, 10, 1),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({List<Position> positions = const [], this.error})
    : _positions = List.of(positions);

  final List<Position> _positions;
  final Object? error;
  int requestCount = 0;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    requestCount++;
    if (error != null) return Future.error(error!);
    if (_positions.isEmpty) {
      return Future.error(StateError('No fake position configured'));
    }
    return Future.value(_positions.removeAt(0));
  }
}

class _SyncAdapter implements HttpClientAdapter {
  _SyncAdapter(List<_SyncOutcome> outcomes) : _outcomes = List.of(outcomes);

  final List<_SyncOutcome> _outcomes;
  final List<List<Map<String, dynamic>>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = (options.data as Map).cast<String, dynamic>();
    final events = (jsonDecode(jsonEncode(body['events'])) as List)
        .whereType<Map>()
        .map((event) => event.cast<String, dynamic>())
        .toList();
    requests.add(events);
    final outcome = _outcomes.isEmpty
        ? _SyncOutcome.processed
        : _outcomes.removeAt(0);
    if (outcome == _SyncOutcome.networkFailure) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'results': [
            for (final event in events)
              {
                'client_event_id': event['client_event_id'],
                'status': 'processed',
                'duplicate': false,
                'result': <String, dynamic>{},
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

enum _SyncOutcome { processed, networkFailure }

class _Harness {
  _Harness({
    required this.originalGeolocator,
    required this.db,
    required this.adapter,
    required this.dio,
    required this.repository,
  });

  final GeolocatorPlatform originalGeolocator;
  final AppDatabase db;
  final _SyncAdapter adapter;
  final Dio dio;
  final OrderSyncRepository repository;

  Future<void> close() async {
    GeolocatorPlatform.instance = originalGeolocator;
    dio.close(force: true);
    await db.close();
  }
}
