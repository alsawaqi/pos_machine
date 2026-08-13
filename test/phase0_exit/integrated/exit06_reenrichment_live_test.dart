// EXIT-06 (integrated live leg) — GPS re-enrichment of a fenced offline sale,
// driven end-to-end through the REAL client stack against the phase0exit
// harness API: real Drift outbox (in-memory NativeDatabase), a real
// buildOrderSyncPayload event batch (integer-baisa money, stable
// client_event_ids), the real OrderSyncRepository.flush() hold/enrich logic,
// a real Dio HTTP push to /device/sync/push, and the real per-event server
// ACK (fixture branch 900115 'P0 Fenced' fails closed without GPS).
//
// Deliberately NO TestWidgetsFlutterBinding.ensureInitialized(): the Flutter
// test binding installs HttpOverrides whose mock HttpClient answers every
// real network request with HTTP 400 (recon-verified), and this driver must
// reach the live harness server at PHASE0_BASE_URL.
//
// The ONE seam that is not real: GeolocatorPlatform.instance is a scripted
// fake. Unavoidable — a host test process has no GPS radio and the geolocator
// plugin needs a device platform channel; everything downstream of the fix
// (durable batch mutation, HTTP push, server-side geofence acceptance) is
// exercised for real. The in-fence fix returned matches the fixture fence
// centre exactly (lat 23.5880 lng 58.3829, radius 500 m).
//
// Environment (exported by tool/phase0_exit.ps1):
//   PHASE0_INTEGRATED=1   — gate; without it this whole file skips.
//   PHASE0_DEVICE_TOKEN   — plaintext device token; the fenced fixture device
//                           is 'phase0-mdev-machine-fenced' (id 900116).
//   PHASE0_BASE_URL       — default http://127.0.0.1:58000/api/v1
//   PHASE0_PRODUCT_ID     — default 900140 ('P0 Untracked', 2.500 OMR).

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pos_api_service.dart';

// Fixture fence centre for branch 900115 'P0 Fenced' (fixtures.json).
const double _fenceLat = 23.5880;
const double _fenceLng = 58.3829;

void main() {
  final integrated = Platform.environment['PHASE0_INTEGRATED'] == '1';

  group(
    'EXIT-06 integrated: fenced GPS re-enrichment against the live harness',
    () {
      test(
        'a fenced sale queued without GPS re-enriches at flush and settles '
        'processed',
        () async {
          final token = Platform.environment['PHASE0_DEVICE_TOKEN'];
          if (token == null || token.isEmpty) {
            fail(
              'PHASE0_DEVICE_TOKEN is not set — export the fenced fixture '
              "device token ('phase0-mdev-machine-fenced') before running "
              'the integrated driver',
            );
          }

          final locator = _ScriptedGeolocator(
            positions: [_position(latitude: _fenceLat, longitude: _fenceLng)],
          );
          final harness = await _liveHarness(locator: locator);

          final payload = _fixturePayload();
          _assertMoneyInvariant(payload);
          final createOrder = _createOrder(payload);
          expect(
            createOrder.containsKey('gps'),
            isFalse,
            reason: 'the payload must be built without lat/lng so flush-time '
                're-enrichment is genuinely exercised',
          );

          await harness.db.enqueueOutbox(OrderOutboxCompanion(
            orderUuid: Value(payload.orderUuid),
            eventsJson: Value(jsonEncode(payload.events)),
            orderNumber: const Value(1450),
            createdAt: Value(DateTime.now()),
          ));

          expect(
            await harness.repository.flush(),
            1,
            reason: 'the fenced sale must settle in one flush once the '
                'locator returns an in-fence fix (last row error: '
                '${await _lastError(harness.db)})',
          );
          expect(
            locator.requestCount,
            1,
            reason: 'exactly one fresh fix is acquired per flush pass',
          );

          // Row synced: durably marked, no longer pending.
          final rows = await harness.db.select(harness.db.orderOutbox).get();
          expect(rows, hasLength(1));
          expect(rows.single.orderUuid, payload.orderUuid);
          expect(
            rows.single.syncedAt,
            isNotNull,
            reason: 'a processed ACK must mark the outbox row synced',
          );
          expect(await harness.db.pendingOutbox(), isEmpty);

          // Per-event ACK: every event of the batch settled 'processed'.
          expect(
            harness.ackBodies,
            hasLength(1),
            reason: 'exactly one HTTP push is expected for one outbox row',
          );
          final results = _ackResults(harness.ackBodies.single);
          expect(results, hasLength(payload.events.length));
          final mintedIds = payload.events
              .map((e) => e['client_event_id'] as String)
              .toSet();
          for (final r in results) {
            expect(
              r['status'],
              'processed',
              reason: 'event ${r['client_event_id']} did not settle '
                  'processed — full ACK: ${jsonEncode(r)}',
            );
            expect(
              mintedIds.contains(r['client_event_id']),
              isTrue,
              reason: 'ACK echoed an unknown client_event_id '
                  '${r['client_event_id']}',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'no fresh fix: the fenced sale stays held — flush()==0, row pending, '
        'attempts untouched',
        () async {
          final locator = _ScriptedGeolocator(error: StateError('no GPS fix'));
          final harness = await _liveHarness(locator: locator);

          final payload = _fixturePayload();
          expect(_createOrder(payload).containsKey('gps'), isFalse);

          await harness.db.enqueueOutbox(OrderOutboxCompanion(
            orderUuid: Value(payload.orderUuid),
            eventsJson: Value(jsonEncode(payload.events)),
            orderNumber: const Value(1450),
            createdAt: Value(DateTime.now()),
          ));

          expect(
            await harness.repository.flush(),
            0,
            reason: 'without a fix a fenced sale must not settle',
          );
          expect(locator.requestCount, 1);

          final pending = await harness.db.pendingOutbox();
          expect(
            pending,
            hasLength(1),
            reason: 'the held sale must remain durably queued',
          );
          expect(pending.single.orderUuid, payload.orderUuid);
          expect(
            pending.single.attempts,
            0,
            reason: 'a GPS hold must not consume a transport attempt',
          );
          expect(pending.single.serverRejections, 0);
          expect(
            harness.ackBodies,
            isEmpty,
            reason: 'no HTTP push may leave the device without a fix at a '
                'fenced branch',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: integrated
        ? false
        : 'PHASE0_INTEGRATED!=1 — live Phase 0 exit-gate driver. Bring up the '
            'harness (tool\\phase0_exit.ps1 -RunId <id> -Setup), then run '
            'with PHASE0_INTEGRATED=1, PHASE0_DEVICE_TOKEN=<fenced device '
            'token> and PHASE0_BASE_URL=http://127.0.0.1:58000/api/v1: '
            'flutter test test/phase0_exit/integrated/'
            'exit06_reenrichment_live_test.dart',
  );
}

// ---------------------------------------------------------------------------
// Harness plumbing
// ---------------------------------------------------------------------------

class _LiveHarness {
  _LiveHarness({
    required this.db,
    required this.repository,
    required this.ackBodies,
  });

  final AppDatabase db;
  final OrderSyncRepository repository;
  final List<Map<String, dynamic>> ackBodies;
}

Future<_LiveHarness> _liveHarness({
  required _ScriptedGeolocator locator,
}) async {
  final originalLocator = GeolocatorPlatform.instance;
  GeolocatorPlatform.instance = locator;
  addTearDown(() => GeolocatorPlatform.instance = originalLocator);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  // Fenced branch cache row mirroring fixture branch 900115 'P0 Fenced',
  // awaited so every later flush() sees a fenced branch.
  await db.into(db.branchCache).insert(
        BranchCacheCompanion.insert(
          id: const Value(900115),
          latitude: const Value(_fenceLat),
          longitude: const Value(_fenceLng),
          geofenceRadiusM: const Value(500),
        ),
      );

  final ackBodies = <Map<String, dynamic>>[];
  final dio = Dio(BaseOptions(
    baseUrl: Platform.environment['PHASE0_BASE_URL'] ??
        'http://127.0.0.1:58000/api/v1',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
  ));
  dio.interceptors.add(InterceptorsWrapper(
    onResponse: (response, handler) {
      final data = response.data;
      if (data is Map) ackBodies.add(data.cast<String, dynamic>());
      handler.next(response);
    },
  ));
  addTearDown(() => dio.close(force: true));

  final api = PosApiService(
    tokenGetter: () => Platform.environment['PHASE0_DEVICE_TOKEN'],
    dio: dio,
  );
  final repository = OrderSyncRepository(api, db);

  return _LiveHarness(db: db, repository: repository, ackBodies: ackBodies);
}

// ---------------------------------------------------------------------------
// Fixture payload (REAL builder, no lat/lng → gps genuinely absent)
// ---------------------------------------------------------------------------

OrderSyncPayload _fixturePayload() {
  final productId =
      int.parse(Platform.environment['PHASE0_PRODUCT_ID'] ?? '900140');
  final snapshot = OrderSnapshot.initial().copyWith(
    orderType: 'quick_order',
    items: [
      {
        'id': '$productId',
        'name': 'P0 fixture product',
        'qty': 1,
        'unitPrice': 2.500,
        'lineTotal': 2.500,
      },
    ],
    rawSubtotal: 2.500,
    discountAmount: 0,
    tax: 0,
    total: 2.500,
    paymentMethod: 'Cash',
  );
  // No lat/lng on purpose: the durable batch must genuinely lack GPS.
  return buildOrderSyncPayload(snapshot);
}

Map<String, dynamic> _createOrder(OrderSyncPayload payload) =>
    (((payload.events.first['payload'] as Map)['order']) as Map)
        .cast<String, dynamic>();

void _assertMoneyInvariant(OrderSyncPayload payload) {
  final order = _createOrder(payload);
  final subtotal = order['subtotal_baisas'] as int;
  final discount = order['discount_total_baisas'] as int;
  final comp = (order['comp_total_baisas'] as int?) ?? 0;
  final tax = order['tax_total_baisas'] as int;
  final grand = order['grand_total_baisas'] as int;
  expect(
    (subtotal - discount - comp + tax - grand).abs() <= 1,
    isTrue,
    reason: 'money invariant subtotal-discount-comp+tax==grand (±1 baisa) '
        'violated: ${jsonEncode(order)}',
  );
}

List<Map<String, dynamic>> _ackResults(Map<String, dynamic> body) =>
    (((body['data'] as Map?)?['results'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();

Future<String> _lastError(AppDatabase db) async {
  final rows = await db.select(db.orderOutbox).get();
  if (rows.isEmpty) return '(no outbox rows)';
  return rows.single.lastError ?? '(none)';
}

// ---------------------------------------------------------------------------
// Scripted geolocator — the single unavoidable seam (see header comment).
// ---------------------------------------------------------------------------

Position _position({required double latitude, required double longitude}) =>
    Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime.now().toUtc(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _ScriptedGeolocator extends GeolocatorPlatform {
  _ScriptedGeolocator({List<Position> positions = const [], this.error})
      : _positions = List.of(positions);

  final List<Position> _positions;
  final Object? error;
  int requestCount = 0;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    requestCount++;
    if (error != null) return Future.error(error!);
    if (_positions.isEmpty) {
      return Future.error(StateError('No scripted position left'));
    }
    return Future.value(_positions.removeAt(0));
  }
}
