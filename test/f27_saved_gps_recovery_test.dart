import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_receipt.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'qr_checkout_fakes.dart' show claimJson, snapshotJson, checkoutTime;
import 't65_real_screen_payment_test.dart' show realLocalDatabase;

CheckoutAttempt oldPending({Map<String, dynamic>? extra, bool gps = true}) {
  final tenders = [
    {'method': 'cash', 'amount_baisas': 4750, 'status': 'success'},
  ];
  return CheckoutAttempt(
    id: '11111111-1111-4111-8111-111111111111',
    orderUuid: 'qr-bill',
    state: 'pending',
    createdAt: checkoutTime,
    claim: claimJson(),
    orderId: 12,
    reference: 'T-F27-OLD',
    captures: tenders,
    tenderMayHaveStarted: true,
    event: {
      'client_event_id': '11111111-1111-4111-8111-111111111111',
      'event_type': 'order.pay',
      'client_timestamp': checkoutTime.toIso8601String(),
      'payload': {
        'order_uuid': 'qr-bill',
        'paid_at': checkoutTime.toIso8601String(),
        'payments': tenders,
        if (gps) 'gps': {'lat': 23.588, 'lng': 58.3829},
        ...?extra,
      },
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final lateGps in [false, true]) {
    test(
      'F27 ${lateGps ? 'late' : 'old'} GPS payment replays through real outbox ACK, journal and receipt storage',
      () async {
        databaseFactory = databaseFactoryFfi;
        final local = await realLocalDatabase();
        await SqliteCheckoutStore.createSchema(local);
        final store = SqliteCheckoutStore(local, 'scope');
        final storage = LocalOrderStorageService.forTesting(local);
        final history = ServerReceiptHistory(storage);
        final old = oldPending(gps: !lateGps);
        final wireEvent = oldPending().event;
        // Exact pre-update persisted shape: create deliberately does not decode.
        await store.create(old);
        await projectMachineCheckoutReceipt(
          history,
          CheckoutSnapshot(snapshotJson(), CheckoutClaim(claimJson())),
          old,
        );
        final drift = AppDatabase.forTesting(NativeDatabase.memory());
        await drift.enqueueOutbox(
          OrderOutboxCompanion(
            orderUuid: const Value('qr-bill'),
            orderNumber: const Value(0),
            createdAt: Value(checkoutTime),
            eventsJson: Value(jsonEncode([wireEvent])),
          ),
        );
        final received = <String>[];
        final dio = Dio(BaseOptions(baseUrl: 'http://fixture.invalid/api/v1'))
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) {
                expect(o.path, endsWith('/sync/push'));
                final e = ((o.data as Map)['events'] as List).single as Map;
                received.add(jsonEncode(e));
                h.resolve(
                  Response(
                    requestOptions: o,
                    statusCode: 200,
                    data: {
                      'data': {
                        'results': [
                          {
                            'client_event_id': old.id,
                            'status': 'processed',
                            'result': {
                              'order_id': 12,
                              'status': 'paid',
                              'receipt_number': 'KLD-F27-OLD',
                            },
                          },
                        ],
                      },
                    },
                  ),
                );
              },
            ),
          );
        final api = PosApiService(tokenGetter: () => 'fixture', dio: dio);
        final outbox = OrderSyncRepository(api, drift);
        final checkout = QrCheckoutController(
          gateway: ApiCheckoutGateway(
            api: api,
            currentScope: () => 'scope',
            location: () async => null,
            legacyGuard: (_) async {},
          ),
          store: store,
          captureCard: (_) async => throw StateError('No bank operation'),
          captureBank: (_) async => throw StateError('No bank operation'),
          authorizeGift: () async => false,
          projectReceipt: (s, a) =>
              projectMachineCheckoutReceipt(history, s, a),
        );
        final coordinator = TableSyncCoordinator(
          outbox: outbox,
          store: storage,
          loadSessions: storage.loadDiningTableSessions,
          mode: () => 'live',
          degraded: () => false,
          staffId: () => 7,
          markPrinted: (_) async {},
        );
        coordinator.paymentAcknowledged = checkout.acceptTablePayAck;
        addTearDown(() async {
          checkout.dispose();
          await coordinator.dispose();
          await outbox.dispose();
          await drift.close();
          await local.close();
        });
        await coordinator.hydrate();
        await outbox.flush();
        final row = await outbox.rowForKey('qr-bill');
        expect(row!.syncedAt, isNotNull, reason: row.lastError);
        expect(received, [jsonEncode(wireEvent)]);
        expect(
          (await local.query('qr_checkout_attempts')).single['state'],
          'paid',
        );
        expect(await store.active(), isNull);
        final receipt = (await storage.loadOrderHistory()).single.snapshot;
        expect(receipt.serverReceiptConfirmed, true);
        expect(receipt.receiptNumber, 'KLD-F27-OLD');
        expect(receipt.paymentStatus, 'Paid');
        await outbox.flush();
        expect(
          received,
          hasLength(1),
          reason: 'Completed outbox never sends a second tender',
        );
        expect(
          (await local.query('qr_checkout_attempts')).single['payload'],
          contains(jsonEncode(old.event)),
        );
      },
    );
  }
  test(
    'F27 shared checkout keeps GPS on claim and next table can be claimed',
    () async {
      databaseFactory = databaseFactoryFfi;
      final db = await realLocalDatabase();
      await SqliteCheckoutStore.createSchema(db);
      final store = SqliteCheckoutStore(db, 'shared');
      final history = ServerReceiptHistory(
        LocalOrderStorageService.forTesting(db),
      );
      var uuid = 'qr-bill';
      final claims = <Map>[], events = <Map>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://fixture.invalid/api/v1'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              Object data;
              final claim = {
                ...claimJson(
                  replay: claims.any((c) => c['order_uuid'] == uuid),
                ),
                'order_uuid': uuid,
              };
              if (o.path.endsWith('/claim-settlement')) {
                claims.add(Map.from(o.data as Map));
                data = claim;
              } else if (o.path.endsWith('/checkout')) {
                final snapshot = snapshotJson();
                (snapshot['order'] as Map).addAll(<String, dynamic>{
                  'uuid': uuid,
                  'order_type': 'dine_in',
                  'table_id': 1,
                });
                snapshot['claim'] = claim;
                data = snapshot;
              } else {
                expect(o.path, endsWith('/sync/push'));
                final e = ((o.data as Map)['events'] as List).single as Map;
                events.add(Map.from(e));
                data = {
                  'results': [
                    {
                      'client_event_id': e['client_event_id'],
                      'status': 'processed',
                      'result': {
                        'order_id': 12,
                        'status': 'paid',
                        'receipt_number': 'KLD-SHARED',
                      },
                    },
                  ],
                };
              }
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {'data': data},
                ),
              );
            },
          ),
        );
      final api = PosApiService(tokenGetter: () => 'fixture', dio: dio);
      QrCheckoutController create() => QrCheckoutController(
        gateway: ApiCheckoutGateway(
          api: api,
          currentScope: () => 'shared',
          location: () async => (lat: 23.588, lng: 58.3829),
          legacyGuard: (_) async {},
        ),
        store: store,
        now: () => checkoutTime,
        captureCard: (_) async => throw StateError('No bank'),
        captureBank: (_) async => throw StateError('No bank'),
        authorizeGift: () async => false,
        projectReceipt: (s, a) => projectMachineCheckoutReceipt(history, s, a),
      );
      final c = create();
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      await c.open(uuid);
      expect(c.ready, true, reason: c.notice);
      expect(claims.single['gps'], {'lat': 23.588, 'lng': 58.3829});
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(c.phase, CheckoutPhase.paid, reason: c.notice);
      // Shared checkout has always geofenced its claim, not modified its pay.
      expect((events.single['payload'] as Map).keys.toSet(), {
        'order_uuid',
        'paid_at',
        'payments',
      });
      expect(await store.active(), isNull);
      uuid = 'next-table-bill';
      final next = create();
      addTearDown(next.dispose);
      await next.open(uuid);
      expect(next.ready, true, reason: next.notice);
      expect(claims.last['order_uuid'], uuid);
      expect(events, hasLength(1));
    },
  );
  test(
    'F27 saved payment admits GPS but still fails closed on unknown or malformed fields',
    () {
      expect(
        CheckoutAttempt.decode(jsonEncode(oldPending().json)).event,
        oldPending().event,
      );
      for (final fields in <Map<String, dynamic>>[
        {'unrecognized': true},
        {'loyalty_redeem': {}},
        {'gps': null},
        {
          'gps': {'lat': 23.5},
        },
        {
          'gps': {'lat': '23.5', 'lng': 58},
        },
        {
          'gps': {'lat': 91, 'lng': 58},
        },
        {
          'gps': {'lat': 23, 'lng': 181},
        },
        {
          'gps': {'lat': 23, 'lng': 58, 'extra': 1},
        },
      ]) {
        expect(
          () => CheckoutAttempt.decode(
            jsonEncode(oldPending(extra: fields).json),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
