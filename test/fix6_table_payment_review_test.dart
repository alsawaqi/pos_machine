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
import 'f27_saved_gps_recovery_test.dart' show oldPending;
import 't65_real_screen_payment_test.dart' show realLocalDatabase;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final scenario in [
    'numbering-disabled',
    'orphan',
    'rebound',
    'refused-parked',
    'standalone',
    'missing-ack',
  ]) {
    test('Fix6 real table coordinator/outbox/journal $scenario', () async {
      databaseFactory = databaseFactoryFfi;
      final local = await realLocalDatabase();
      await SqliteCheckoutStore.createSchema(local);
      final store = SqliteCheckoutStore(local, 'scope');
      final storage = LocalOrderStorageService.forTesting(local);
      final history = ServerReceiptHistory(storage);
      final old = oldPending().copy(
        paymentContract: scenario == 'standalone' ? 'qr' : 'table',
      );
      // Standalone contract intentionally has no GPS; table allows it.
      final event = Map<String, dynamic>.from(old.event!);
      if (scenario == 'standalone') {
        event['payload'] = Map<String, dynamic>.from(event['payload'] as Map)
          ..remove('gps');
      }
      final saved = old.copy(event: event);
      await store.create(saved);
      await projectMachineCheckoutReceipt(
        history,
        CheckoutSnapshot(snapshotJson(), CheckoutClaim(claimJson())),
        saved,
      );
      final drift = AppDatabase.forTesting(NativeDatabase.memory());
      final key = scenario == 'rebound'
          ? 'saved-snapshot-local-uuid'
          : 'qr-bill';
      await drift.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: Value(key),
          orderNumber: const Value(0),
          createdAt: Value(checkoutTime),
          eventsJson: Value(jsonEncode([event])),
          serverRejections: Value(scenario == 'refused-parked' ? 5 : 0),
          lastError: Value(
            scenario == 'refused-parked' ? 'Bill refused' : null,
          ),
        ),
      );
      final requests = <Map>[];
      var releases = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://fixture.invalid/api/v1'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              if (o.path.endsWith('/release-charge')) {
                releases++;
                h.resolve(
                  Response(
                    requestOptions: o,
                    statusCode: 200,
                    data: {'data': {}},
                  ),
                );
                return;
              }
              expect(o.path, endsWith('/sync/push'));
              final e = ((o.data as Map)['events'] as List).single as Map;
              requests.add(e);
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'data': {
                      'results': [
                        if (scenario != 'missing-ack')
                          {
                            'client_event_id': saved.id,
                            'status': scenario == 'refused-parked'
                                ? 'failed'
                                : 'processed',
                            'result': scenario == 'refused-parked'
                                ? {'error': 'bill is closed'}
                                : {
                                    'order_id': 12,
                                    'status': scenario == 'orphan'
                                        ? 'void'
                                        : 'paid',
                                    if (scenario != 'numbering-disabled')
                                      'receipt_number': 'FIX6-1',
                                    if (scenario == 'orphan')
                                      'orphan_tender': true,
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
        captureCard: (_) async => throw StateError('No bank'),
        captureBank: (_) async => throw StateError('No bank'),
        authorizeGift: () async => false,
        projectReceipt: (s, a) => projectMachineCheckoutReceipt(history, s, a),
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
      if (scenario == 'rebound' || scenario == 'refused-parked') {
        await outbox.recoverTablePayment(saved.orderUuid, saved.id);
      } else {
        await outbox.flush();
      }
      final row = (await outbox.rowForKey(key))!;
      final active = await store.active();
      if (scenario == 'missing-ack') {
        expect(active!.state, 'pending');
        expect(OrderSyncRepository.isStuck(row), false);
        expect(
          row.serverRejections,
          1,
          reason: 'Missing ACK keeps pre-existing retry classification',
        );
        expect(
          (await history.find(saved.orderUuid))!.serverReceiptConfirmed,
          false,
        );
      } else if (scenario == 'standalone') {
        expect(
          active!.state,
          'pending',
          reason: 'table listener must never resolve a standalone QR attempt',
        );
        expect(
          (await history.find(saved.orderUuid))!.serverReceiptConfirmed,
          false,
        );
      } else if (scenario == 'orphan' || scenario == 'refused-parked') {
        expect(active!.state, scenario == 'orphan' ? 'uncertain' : 'refused');
        expect(checkout.phase, CheckoutPhase.attention);
        expect(
          checkout.notice,
          scenario == 'orphan' ? 'recovery' : 'return_cash',
        );
        expect(await checkout.managerTakeover(() async => false), false);
        expect((await store.active())!.state, active.state);
        expect(await checkout.managerTakeover(() async => true), true);
        expect(await store.active(), isNull);
        expect(
          (await local.query('qr_checkout_attempts')).single['state'],
          'managed',
        );
        expect(await history.find(saved.orderUuid), isNull);
        if (scenario == 'refused-parked') {
          expect(OrderSyncRepository.isStuck(row), true);
          expect(releases, 1);
        }
      } else {
        expect(active, isNull, reason: row.lastError);
        expect(
          (await local.query('qr_checkout_attempts')).single['state'],
          'paid',
        );
        expect(row.syncedAt, isNotNull);
        final receipt = (await history.find(saved.orderUuid))!;
        expect(receipt.paymentStatus, 'Paid');
        expect(
          receipt.receiptNumber,
          scenario == 'numbering-disabled' ? '' : 'FIX6-1',
        );
        expect(
          receipt.displayOrderNumber,
          scenario == 'numbering-disabled' ? 'T-F27-OLD' : 'FIX6-1',
        );
      }
      expect(requests, hasLength(1));
      expect(requests.single['client_event_id'], saved.id);
      expect(
        jsonEncode(requests.single['payload']),
        jsonEncode(event['payload']),
      );
      expect(
        (await local.query('qr_checkout_attempts')).single['payload'],
        contains(jsonEncode(event)),
      );
      await outbox.flush();
      expect(
        requests,
        hasLength(scenario == 'missing-ack' ? 2 : 1),
        reason: 'only unresolved no-ACK payment can replay',
      );
    });
  }
}
