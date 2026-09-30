import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';

import 'package:drift/drift.dart' show Value;
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 't65_real_screen_payment_test.dart' as original;

// Hardware boundary only: each reading differs, including journal and retry.
class MovingGps extends GeolocatorPlatform {
  int calls = 0;
  bool failTenderFix = false;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    calls++;
    if (failTenderFix && calls == 2) {
      throw StateError('initial tender fix unavailable');
    }
    return Position(
      latitude: 23.588 + (calls / 100000),
      longitude: 58.3829,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;
}

class RecoveryServer extends original.AckServer {
  bool answer = false;
  bool receiptProof = true;
  int activeTable = 1;
  @override
  Future<Map<String, dynamic>> dineInDetail(int id) async {
    final detail = await super.dineInDetail(id);
    (detail['table'] as Map)['id'] = activeTable;
    if (detail['seating'] is Map) {
      (detail['seating'] as Map)['table_id'] = activeTable;
    }
    if (detail['bill'] is Map) {
      (detail['bill'] as Map)['table_id'] = activeTable;
    }
    return detail;
  }

  final ids = <String>{};
  @override
  Dio dio() {
    final d = Dio();
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          final batch = ((o.data as Map)['events'] as List).cast<Map>();
          final results = <Map<String, dynamic>>[];
          for (final raw in batch) {
            final e = Map<String, dynamic>.from(raw);
            events.add(e);
            if (e['event_type'] == 'product.waste') {
              results.add({
                'client_event_id': e['client_event_id'],
                'status': 'failed',
                'result': {'error': 'Cannot waste: only -21 on the shelf.'},
              });
              continue;
            }
            uuid = (e['payload'] as Map)['order_uuid'] as String;
            if (e['event_type'] == 'order.pay') {
              expect(claimed, true);
              final payments = (e['payload'] as Map)['payments'] as List;
              expect(
                payments.fold<int>(
                  0,
                  (s, p) => s + (p['amount_baisas'] as int),
                ),
                total,
              );
              paid = true;
            }
            results.add({
              'client_event_id': e['client_event_id'],
              'status': 'processed',
              'result': {
                'order_uuid': uuid,
                'table_session_uuid': original.seat,
                'temp_reference': 'T-FIX7-001',
                if (e['event_type'] == 'order.pay') ...{
                  if (receiptProof) 'status': 'paid',
                  'order_id': 65,
                  'receipt_number': 'TEST-T65-120',
                } else
                  'outcome': e['event_type'] == 'table.session.open'
                      ? 'opened'
                      : 'appended',
                if (e['event_type'] == 'table.session.round') ...{
                  'round_id': 1,
                  'round_no': 1,
                },
              },
            });
          }
          if (batch.any((e) => e['event_type'] == 'order.pay')) {
            ids.addAll(
              batch
                  .where((e) => e['event_type'] == 'order.pay')
                  .map((e) => e['client_event_id'] as String),
            );
            if (!answer) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                  error: 'ACK lost after server commit',
                ),
              );
              return;
            }
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'data': {'results': results},
              },
            ),
          );
        },
      ),
    );
    return d;
  }
}

void runTablePaymentRecovery(String scenario) {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final mode in [scenario]) {
    testWidgets(
      'F28 real screen $mode payment uses changing GPS and recovers one immutable tender',
      (tester) async {
        Future<T?> drive<T>(Future<T> Function() action) async {
          var done = false;
          T? value;
          Object? error;
          StackTrace? trace;
          await tester.runAsync(() async {
            unawaited(
              action().then(
                (v) {
                  value = v;
                  done = true;
                },
                onError: (Object e, StackTrace st) {
                  error = e;
                  trace = st;
                  done = true;
                },
              ),
            );
          });
          await pumpUntilRealCondition(
            tester,
            () => done,
            reason: 'real SQLite/coordinator operation completed',
          );
          if (!done) throw StateError('Real component workflow did not finish');
          if (error != null) Error.throwWithStackTrace(error!, trace!);
          return value;
        }

        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final name in [
          'plugins.it_nomads.com/flutter_secure_storage',
          'pos_machine/rear_display_host',
        ]) {
          final channel = MethodChannel(name);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                channel,
                (call) async => call.method == 'read'
                    ? 'fixture'
                    : <Map<String, dynamic>>[],
              );
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
        }
        late Database localDb;
        late AppDatabase driftDb;
        late LocalOrderStorageService storage;
        late OrderSyncRepository outbox;
        late TableSyncCoordinator coordinator;
        final server = RecoveryServer();
        final gps = MovingGps()..failTenderFix = mode == 'new-lost';
        final oldGps = GeolocatorPlatform.instance;
        GeolocatorPlatform.instance = gps;
        addTearDown(() => GeolocatorPlatform.instance = oldGps);
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        late Directory auxiliary;
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          auxiliary = await Directory.systemTemp.createTemp('fix8-ack-');
          await databaseFactory.setDatabasesPath(auxiliary.path);
          localDb = await original.realLocalDatabase();
          storage = LocalOrderStorageService.forTesting(localDb);
          await storage.refreshRecoveryGuard();
          driftDb = AppDatabase.forTesting(NativeDatabase.memory());
          outbox = OrderSyncRepository(
            PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
            driftDb,
          );
          coordinator = TableSyncCoordinator(
            outbox: outbox,
            store: storage,
            loadSessions: storage.loadDiningTableSessions,
            mode: () => 'live',
            degraded: () => false,
            staffId: () => 7,
            markPrinted: (_) async {},
          );
        });
        debugOrderStorageOverride = storage;
        TableKitchenBridge? bridge;
        addTearDown(() async {
          bridge?.detach();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          debugOrderStorageOverride = null;
          await drive(() async {
            await coordinator.dispose();
            await outbox.dispose();
            await driftDb.close();
            await localDb.close();
            await boards.close();
          });
        });
        Future<void> mount() async {
          await pumpWorkspaceMachine(
            tester,
            mode: 'live',
            toggle: false,
            wrapStaff: (child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
              child: child,
            ),
            api: server,
            outbox: outbox,
            database: driftDb,
            coordinator: coordinator,
            boards: boards.stream,
            catalog: const CatalogSnapshot(
              categories: [],
              products: [],
              floors: [],
              tables: [],
              taxes: [],
            ),
          );
        }

        await mount();
        final dynamic host = tester.state(find.byType(StaffPosScreen));
        final PosController c = host.controller;
        await pumpUntilRealCondition(
          tester,
          () => c.diningTableSyncHooks != null,
          reason: 'real table bridge attached',
        );
        c.applyCatalog(
          categories: const ['Drinks'],
          products: const [
            original.product,
            Product(id: '11', name: 'Sweet', category: 'Drinks', price: 0.3),
            Product(id: '12', name: 'Unsent', category: 'Drinks', price: 1),
          ],
          floors: const [DiningFloor(id: '1', label: 'Main')],
          tables: const [
            DiningTableDefinition(
              id: '1',
              floorId: '1',
              name: 'Table 1',
              sizeLabel: 'square',
              seats: 4,
              sortOrder: 1,
            ),
          ],
        );
        c.printReceipts = false;
        c.printKitchenTickets = false;
        bridge = c.diningTableSyncHooks as TableKitchenBridge;
        await drive(() async {
          await storage.refreshRecoveryGuard();
          expect(c.diningTableDefinitions, isNotEmpty);
          await c.openDiningTable('1');
          expect(c.activeDiningTableId, '1', reason: c.lastPaymentMessage);
          c.addProduct(original.product);
          c.addProduct(original.product);
        });
        await drive(() async {
          await bridge!.send(bridge.activeSession()!);
          await coordinator.settled;
          await outbox.flush();
        });
        await pumpUntilRealCondition(
          tester,
          () =>
              server.events
                  .where((e) => e['event_type'] == 'table.session.round')
                  .length ==
              1,
          reason: 'first accepted staff round ACK',
        );

        await drive(() async {
          await driftDb
              .into(driftDb.branchCache)
              .insert(
                BranchCacheCompanion.insert(
                  id: const Value(1),
                  latitude: const Value(23.588),
                  longitude: const Value(58.3829),
                ),
              );
        });
        await pumpUntilRealCondition(
          tester,
          () {
            final button = find.byKey(const ValueKey('table-adjust-discount'));
            return button.evaluate().isNotEmpty &&
                tester.widget<TextButton>(button).onPressed != null;
          },
          reason: 'real canonical table editor finished loading before tender',
        );
        c.selectPaymentMethod('Cash');
        await drive(() => c.payAndPrint(cashTenderedAmount: 20));
        await drive(() => outbox.settled);
        final journal = (await drive(
          () => SqliteCheckoutStore.open('inspection'),
        ))!;
        expect(
          c.lastPaymentMessage.contains('before payment'),
          isNot(true),
          reason: c.lastPaymentMessage,
        );
        final before = (await drive(
          () => journal.db.query('qr_checkout_attempts'),
        ))!.single;
        expect(before['state'], 'pending');
        final saved = CheckoutAttempt.decode(before['payload'] as String);
        final row = (await drive(() => outbox.rowForKey(server.uuid!)))!;
        expect(row.syncedAt, isNull);
        expect(
          server.paid,
          true,
          reason: 'Server committed; only ACK was lost',
        );
        if (mode != 'new-lost') {
          // Literal eb583ac serializer field order/shape: no payment_contract.
          // Substitute only the synthetic identities; never serialize today's model.
          final a = await drive(() => gps.getCurrentPosition());
          final text =
              '{"id":"${saved.id}","order_uuid":"${saved.orderUuid}","state":"pending","created_at":"2026-09-20T10:00:00.000Z","claim":{"order_uuid":"${saved.orderUuid}","status":"awaiting_payment","charge_amount_baisas":5400,"charge_claimed_at":"2026-09-20T10:00:00.000Z","charge_deadline_at":"2026-09-20T10:05:00.000Z","already_claimed_by_this_device":false},"order_id":65,"reference":"T-F28-LEGACY","event":{"client_event_id":"${saved.id}","event_type":"order.pay","client_timestamp":"2026-09-20T10:00:00.000Z","payload":{"order_uuid":"${saved.orderUuid}","paid_at":"2026-09-20T10:00:00.000Z","payments":[{"method":"cash","amount_baisas":5400,"status":"success"}],"gps":{"lat":${a!.latitude},"lng":${a.longitude}}}},"captures":[{"method":"cash","amount_baisas":5400,"status":"success"}],"receipt_number":null,"tender_may_have_started":true}';
          await drive(() async {
            await journal.db.update(
              'qr_checkout_attempts',
              {'payload': text},
              where: 'id = ?',
              whereArgs: [saved.id],
            );
            expect(
              (await journal.db.query(
                'qr_checkout_attempts',
              )).single['payload'],
              text,
            );
            final event = (jsonDecode(text) as Map)['event'] as Map;
            (event['payload'] as Map).remove('gps');
            await (driftDb.update(
              driftDb.orderOutbox,
            )..where((t) => t.orderUuid.equals(saved.orderUuid))).write(
              OrderOutboxCompanion(
                eventsJson: Value(jsonEncode([event])),
                syncedAt: Value(
                  mode == 'synced' || mode == 'missing' ? DateTime.now() : null,
                ),
              ),
            );
          });
        }
        // Restart the real host; it must discover synced/pending too.
        bridge.detach();
        bridge = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        server.answer = mode != 'missing';
        server.receiptProof = mode != 'bad-ack';
        await mount();
        final dynamic restartedHost = tester.state(find.byType(StaffPosScreen));
        final PosController restarted = restartedHost.controller;
        boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
            },
          ),
        );
        if (mode == 'missing' || mode == 'bad-ack') {
          await pumpUntilRealCondition(
            tester,
            () => find
                .byKey(const ValueKey('table-check-payment-result'))
                .evaluate()
                .isNotEmpty,
            reason:
                'staff-only pending payment has reachable Check payment result',
          );
          expect(
            (await drive(
              () => journal.db.query('qr_checkout_attempts'),
            ))!.single['state'],
            'pending',
          );
          expect(
            await drive(() => localDb.query('draft_recovery_closed_archive')),
            isEmpty,
          );
          expect(
            find.textContaining('Do not take payment again.'),
            findsOneWidget,
          );
          final requestsBefore = server.events
              .where((e) => e['event_type'] == 'order.pay')
              .length;
          await pumpUntilRealCondition(
            tester,
            () =>
                tester
                    .widget<TextButton>(
                      find.byKey(const ValueKey('table-check-payment-result')),
                    )
                    .onPressed !=
                null,
            reason: 'saved payment check ready',
          );
          await tester.tap(
            find.byKey(const ValueKey('table-check-payment-result')),
          );
          await pumpUntilRealCondition(
            tester,
            () =>
                server.events
                    .where((e) => e['event_type'] == 'order.pay')
                    .length >
                requestsBefore,
            reason: 'real recovery control replays the same saved event',
          );
          expect(
            (await drive(
              () => journal.db.query('qr_checkout_attempts'),
            ))!.single['state'],
            'pending',
          );
          expect(
            await drive(() => localDb.query('draft_recovery_closed_archive')),
            isEmpty,
          );
          expect(
            (await drive(() => outbox.rowForKey(saved.orderUuid)))!.syncedAt,
            isNull,
            reason: 'No paid proof must not silently sync a pending journal',
          );
          server.answer = true;
          server.receiptProof = true;
          await pumpUntilRealCondition(
            tester,
            () =>
                tester
                    .widget<TextButton>(
                      find.byKey(const ValueKey('table-check-payment-result')),
                    )
                    .onPressed !=
                null,
            reason: 'saved payment check ready',
          );
          await tester.tap(
            find.byKey(const ValueKey('table-check-payment-result')),
          );
        }
        await pumpUntilRealCondition(
          tester,
          () async =>
              (await journal.db.query(
                'qr_checkout_attempts',
              )).single['state'] ==
              'paid',
          reason: 'matching paid ACK completes the durable journal',
        );
        await pumpUntilRealCondition(
          tester,
          () async => (await localDb.query('dining_tables')).isEmpty,
          reason:
              'own confirmed table payment automatically archives the old copy',
        );
        expect(
          (await drive(() => outbox.rowForKey(saved.orderUuid)))!.syncedAt,
          isNotNull,
        );
        expect(
          await drive(() => localDb.query('draft_recovery_closed_archive')),
          hasLength(1),
        );
        final receipt = (await drive(
          storage.loadOrderHistory,
        ))!.single.snapshot;
        expect(receipt.serverReceiptConfirmed, true);
        expect(receipt.receiptNumber, 'TEST-T65-120');
        expect(receipt.paymentStatus, 'Paid');
        expect(server.ids, {
          saved.id,
        }, reason: 'Never a new pay event or second tender');
        final fixes = server.events
            .where((e) => e['event_type'] == 'order.pay')
            .map((e) => jsonEncode((e['payload'] as Map)['gps']))
            .toSet();
        expect(
          fixes.length,
          greaterThan(1),
          reason:
              'calls=${gps.calls}, events=${server.events.where((e) => e["event_type"] == "order.pay").toList()} row=${row.eventsJson}',
        );
        expect(gps.calls, greaterThan(1));
        await pumpUntilRealCondition(
          tester,
          () => restarted.diningSessionFor('1') == null,
          reason: 'controller reconciled archived table',
        );
        expect(restarted.diningSessionFor('1'), isNull);
        expect(
          (await drive(
            () => journal.db.query('qr_checkout_attempts'),
          ))!.single['payload'],
          contains(saved.id),
        );
        // A second table uses the same real staff tender/journal path. The
        // recovered attempt cannot hold the global beginTableTender gate.
        server
          ..paid = false
          ..claimed = false
          ..claimedAt = null
          ..uuid = null
          ..activeTable = 2;
        restarted.applyCatalog(
          categories: const ['Drinks'],
          products: const [original.product],
          floors: const [DiningFloor(id: '1', label: 'Main')],
          tables: const [
            DiningTableDefinition(
              id: '2',
              floorId: '1',
              name: 'Table 2',
              sizeLabel: 'square',
              seats: 4,
              sortOrder: 2,
            ),
          ],
        );
        restarted.printReceipts = false;
        restarted.printKitchenTickets = false;
        await drive(() async {
          await restarted.openDiningTable('2');
          restarted.addProduct(original.product);
          restarted.addProduct(original.product);
          final nextBridge =
              restarted.diningTableSyncHooks as TableKitchenBridge;
          await nextBridge.send(nextBridge.activeSession()!);
          await coordinator.settled;
          await outbox.flush();
        });
        await pumpUntilRealCondition(tester, () {
          final button = find.byKey(const ValueKey('table-adjust-discount'));
          return button.evaluate().isNotEmpty &&
              tester.widget<TextButton>(button).onPressed != null;
        }, reason: 'next table canonical editor ready');
        restarted.selectPaymentMethod('Cash');
        await drive(() => restarted.payAndPrint(cashTenderedAmount: 20));
        await drive(() => outbox.settled);
        final attemptsAfterNext = (await drive(
          () => journal.db.query('qr_checkout_attempts'),
        ))!;
        expect(
          attemptsAfterNext,
          hasLength(2),
          reason: restarted.lastPaymentMessage,
        );
        expect(attemptsAfterNext.every((r) => r['state'] == 'paid'), true);
        expect(
          server.ids,
          hasLength(2),
          reason: 'Only deliberate second-table payment gets another id',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        // Drain SQLite work started by the final ACK before Flutter checks
        // pending timers; all money and next-sale assertions remain above.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await drive(() => localDb.rawQuery('SELECT 1'));
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
