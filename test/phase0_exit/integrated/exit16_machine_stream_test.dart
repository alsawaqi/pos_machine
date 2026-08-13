// EXIT-16 (integrated) — the machine-side sales stream: N real sales
// (order.create + order.pay per sale) minted by the REAL buildOrderSyncPayload
// (integer-baisa money, snapshot-authoritative totals) and pushed over REAL
// Dio HTTP to the phase0exit harness API via the real PosApiService.pushSync.
//
// Idempotency discipline: every client_event_id is minted EXACTLY ONCE, before
// the barrier, and the SAME events list object is reused verbatim on any
// transport retry — replay safety is carried by the stable ids, never by
// re-minting.
//
// Barrier (so the orchestrating ps1 can release the machine and handheld
// streams together): the driver writes PHASE0_READY_FILE, then polls for
// PHASE0_GO_FILE every 50 ms with a 30 s timeout, BEFORE the first push.
//
// Deliberately NO TestWidgetsFlutterBinding.ensureInitialized(): the Flutter
// test binding installs HttpOverrides whose mock HttpClient answers every real
// network request with HTTP 400 (recon-verified), and this driver must reach
// the live harness server.
//
// Environment (exported by tool/phase0_exit.ps1):
//   PHASE0_INTEGRATED=1   — gate; without it this whole file skips.
//   PHASE0_DEVICE_TOKEN   — plaintext device token; the unfenced machine
//                           fixture device is 'phase0-mdev-machine-a1'.
//   PHASE0_BASE_URL       — default http://127.0.0.1:58000/api/v1
//   PHASE0_SALES_N        — default 5
//   PHASE0_PRODUCT_ID     — default 900141 ('P0 Tracked')
//   PHASE0_STAFF_ID       — default 900120
//   PHASE0_CUSTOMER_ID    — default 900130
//   PHASE0_READY_FILE / PHASE0_GO_FILE — barrier files (set together).
//
// The pushed order uuids are printed as PHASE0_ORDER_UUID=<uuid> lines (plus a
// combined PHASE0_ORDER_UUIDS= line) for the ps1's psql assertions.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  final integrated = Platform.environment['PHASE0_INTEGRATED'] == '1';

  group(
    'EXIT-16 integrated: machine sales stream against the live harness',
    () {
      test(
        'N sales settle processed through the real builder and real HTTP push',
        () async {
          final n = int.parse(Platform.environment['PHASE0_SALES_N'] ?? '5');
          expect(n >= 1, isTrue, reason: 'PHASE0_SALES_N must be >= 1');
          final productId =
              int.parse(Platform.environment['PHASE0_PRODUCT_ID'] ?? '900141');
          final staffId =
              int.parse(Platform.environment['PHASE0_STAFF_ID'] ?? '900120');
          final customerId = int.parse(
              Platform.environment['PHASE0_CUSTOMER_ID'] ?? '900130');
          final token = Platform.environment['PHASE0_DEVICE_TOKEN'];
          if (token == null || token.isEmpty) {
            fail(
              'PHASE0_DEVICE_TOKEN is not set — export the machine fixture '
              "device token ('phase0-mdev-machine-a1') before running the "
              'integrated driver',
            );
          }

          final dio = Dio(BaseOptions(
            baseUrl: Platform.environment['PHASE0_BASE_URL'] ??
                'http://127.0.0.1:58000/api/v1',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Accept': 'application/json'},
          ));
          addTearDown(() => dio.close(force: true));
          final api = PosApiService(
            tokenGetter: () => Platform.environment['PHASE0_DEVICE_TOKEN'],
            dio: dio,
          );

          // ---- Mint every payload (and thus every client_event_id) ONCE,
          // before the barrier. Nothing after this point re-mints an id. ----
          final payloads = <OrderSyncPayload>[
            for (var i = 0; i < n; i++)
              buildOrderSyncPayload(
                _saleSnapshot(productId: productId),
                staffId: staffId,
                customerId: customerId,
              ),
          ];

          final allEventIds = <String>{};
          final allOrderUuids = <String>{};
          for (final payload in payloads) {
            expect(payload.events, hasLength(2),
                reason: 'a plain cash sale is exactly create + pay');
            expect(payload.events[0]['event_type'], 'order.create');
            expect(payload.events[1]['event_type'], 'order.pay');
            _assertMoneyInvariants(payload);
            expect(
              allOrderUuids.add(payload.orderUuid),
              isTrue,
              reason: 'order uuids must be unique across the stream',
            );
            for (final event in payload.events) {
              expect(
                allEventIds.add(event['client_event_id'] as String),
                isTrue,
                reason: 'client_event_ids must be unique across the stream',
              );
            }
          }

          // ---- Barrier: signal ready, then wait for the go file. ----
          await _barrier();

          // ---- Ring the stream: one push per sale, ids reused on retry. ----
          for (final payload in payloads) {
            final push = await _pushWithBoundedRetry(api, payload.events);
            // Printed BEFORE the ACK assertions so the ps1 can locate the
            // server rows even when an assertion below fails.
            stdout.writeln('PHASE0_ORDER_UUID=${payload.orderUuid}');

            final results = (((push.data['results']) as List?) ?? const [])
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();
            expect(
              results,
              hasLength(payload.events.length),
              reason: 'ACK must carry one result per event — got: '
                  '${jsonEncode(push.data)}',
            );
            final mintedIds = payload.events
                .map((e) => e['client_event_id'] as String)
                .toSet();
            for (final r in results) {
              expect(
                r['status'],
                'processed',
                reason: 'event ${r['client_event_id']} of order '
                    '${payload.orderUuid} did not settle processed — full '
                    'ACK: ${jsonEncode(r)}',
              );
              expect(
                mintedIds.contains(r['client_event_id']),
                isTrue,
                reason: 'ACK echoed an unknown client_event_id '
                    '${r['client_event_id']}',
              );
            }

            final summary = ((push.data['summary'] as Map?) ?? const {})
                .cast<String, dynamic>();
            expect(
              (summary['total'] as num?)?.toInt(),
              payload.events.length,
              reason: 'summary.total must count every pushed event',
            );
            final accepted = (summary['accepted'] as num?)?.toInt() ?? -1;
            final duplicates = (summary['duplicates'] as num?)?.toInt() ?? 0;
            expect(
              accepted + duplicates,
              payload.events.length,
              reason: 'summary accepted+duplicates must account for every '
                  'event — summary: ${jsonEncode(summary)}',
            );
            if (!push.retried) {
              // A clean single-attempt push must be all-new, no duplicates.
              expect(accepted, payload.events.length,
                  reason: 'first-attempt push must accept every event');
              expect(duplicates, 0,
                  reason: 'first-attempt push cannot produce duplicates');
              for (final r in results) {
                expect(r['duplicate'], false,
                    reason: 'first-attempt event flagged duplicate: '
                        '${jsonEncode(r)}');
              }
            }
          }

          stdout.writeln(
            'PHASE0_ORDER_UUIDS='
            '${payloads.map((p) => p.orderUuid).join(',')}',
          );
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    },
    skip: integrated
        ? false
        : 'PHASE0_INTEGRATED!=1 — live Phase 0 exit-gate driver. Bring up the '
            'harness (tool\\phase0_exit.ps1 -RunId <id> -Setup), then run '
            'with PHASE0_INTEGRATED=1, PHASE0_DEVICE_TOKEN=<machine device '
            'token>, PHASE0_BASE_URL=http://127.0.0.1:58000/api/v1 and the '
            'PHASE0_READY_FILE/PHASE0_GO_FILE barrier pair: flutter test '
            'test/phase0_exit/integrated/exit16_machine_stream_test.dart',
  );
}

// ---------------------------------------------------------------------------
// Snapshot / payload helpers (REAL builder shapes, integer-baisa money)
// ---------------------------------------------------------------------------

OrderSnapshot _saleSnapshot({required int productId}) =>
    OrderSnapshot.initial().copyWith(
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

void _assertMoneyInvariants(OrderSyncPayload payload) {
  final order = (((payload.events.first['payload'] as Map)['order']) as Map)
      .cast<String, dynamic>();
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

  final payPayload =
      (payload.events[1]['payload'] as Map).cast<String, dynamic>();
  final paid = ((payPayload['payments'] as List))
      .whereType<Map>()
      .fold<int>(0, (sum, tender) => sum + (tender['amount_baisas'] as int));
  expect(
    (paid - grand).abs() <= 1,
    isTrue,
    reason: 'tender invariant sum(amount_baisas)==grand (±1 baisa) violated: '
        'paid=$paid grand=$grand',
  );
}

// ---------------------------------------------------------------------------
// Barrier: write READY, poll for GO (50 ms interval, 30 s timeout)
// ---------------------------------------------------------------------------

Future<void> _barrier() async {
  final readyPath = Platform.environment['PHASE0_READY_FILE'];
  final goPath = Platform.environment['PHASE0_GO_FILE'];
  if ((readyPath == null || readyPath.isEmpty) !=
      (goPath == null || goPath.isEmpty)) {
    fail(
      'PHASE0_READY_FILE and PHASE0_GO_FILE must be set together — the '
      'harness barrier is misconfigured '
      '(ready=${readyPath ?? '(unset)'} go=${goPath ?? '(unset)'})',
    );
  }
  if (readyPath == null || readyPath.isEmpty) {
    // Solo debugging run without the orchestrator: no barrier to honor.
    return;
  }

  final readyFile = File(readyPath);
  readyFile.parent.createSync(recursive: true);
  readyFile.writeAsStringSync(
    'ready ${DateTime.now().toUtc().toIso8601String()}\n',
    flush: true,
  );

  final goFile = File(goPath!);
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!goFile.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'barrier timeout: $goPath did not appear within 30 s of writing '
        '$readyPath',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

// ---------------------------------------------------------------------------
// Push with bounded transport retry (SAME events list — ids reused verbatim)
// ---------------------------------------------------------------------------

class _PushOutcome {
  _PushOutcome({required this.data, required this.retried});

  final Map<String, dynamic> data;
  final bool retried;
}

Future<_PushOutcome> _pushWithBoundedRetry(
  PosApiService api,
  List<Map<String, dynamic>> events,
) async {
  const maxAttempts = 3;
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      final data = await api.pushSync(events);
      return _PushOutcome(data: data, retried: attempt > 1);
    } on ApiException catch (e) {
      // Only transport failures (no ACK at all) retry; an answered rejection
      // is a genuine failure the gate must see.
      if (!e.isNetwork || attempt >= maxAttempts) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
