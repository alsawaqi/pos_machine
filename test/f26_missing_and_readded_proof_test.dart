import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';
import 'package:pos_machine/draft_recovery/recovery_local.dart';

const seat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const product = Product(
  id: '10',
  name: 'Coffee',
  category: 'Drinks',
  price: 2.7,
);

// External server responses are fixtures. The host, bridge, coordinator,
// held ACK, ledger, detail controller and shared screen are production code.
class AckServer implements PosApiService {
  bool paid = false;
  String roundStatus = 'pending_confirmation';
  String? requestId;
  bool noProof = false;
  bool omitHeld = false;
  int closedReads = 0;
  final roundEvents = <Map<String, dynamic>>[];
  int rejects = 0;
  String? uuid;
  final events = <Map<String, dynamic>>[];
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
            uuid = (e['payload'] as Map)['order_uuid'] as String? ?? uuid;
            if (e['event_type'] == 'table.session.round') {
              requestId = (e['payload'] as Map)['client_request_id'] as String;
              roundEvents.add(e);
            }
            if (e['event_type'] == 'order.pay') paid = true;
            results.add({
              'client_event_id': e['client_event_id'],
              'status': 'processed',
              'result': {
                'order_uuid': uuid,
                'table_session_uuid': seat,
                'temp_reference': 'T-F26-001',
                if (e['event_type'] == 'table.session.cancel_line')
                  'cancelled_qty': 0,
                if (e['event_type'] == 'order.pay') ...{
                  'status': 'paid',
                  'receipt_number': 'TEST-FIX8-120',
                } else
                  'outcome': e['event_type'] == 'table.session.open'
                      ? 'opened'
                      : e['event_type'] == 'table.session.cancel_line'
                      ? 'bill_terminal'
                      : roundEvents.length == 1
                      ? 'appended'
                      : 'held',
                if (e['event_type'] == 'table.session.round') ...{
                  'round_id': roundEvents.length,
                  'round_no': roundEvents.length,
                  if (roundEvents.length == 2)
                    'held_lines': [
                      {'line_index': 0, 'reason': 'out_of_stock'},
                    ],
                  if (roundEvents.length == 2)
                    'review_reasons': ['out_of_stock'],
                },
              },
            });
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

  @override
  String Function() get tokenGetter =>
      () => 'fixture';
  @override
  String get quickOrderBaseUrl => 'http://fixture.invalid/api/v1';
  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];
  @override
  Future<Map<String, dynamic>> dineInDetail(int id) async => {
    'table': {'id': 1, 'label': 'Table 1'},
    'occupied': !paid,
    'orphaned': false,
    'seating': paid
        ? null
        : {
            'uuid': seat,
            'table_id': 1,
            'status': 'open',
            'joined_table_ids': [],
          },
    'bill': paid
        ? null
        : {
            'uuid': uuid,
            'status': 'open',
            'order_type': 'dine_in',
            'table_id': 1,
            'source': 'main_pos',
            'charge': 'none',
            'grand_total_baisas': 840,
            'items': [],
          },
    'rounds': paid
        ? []
        : [
            {
              'id': 1,
              'round_no': 1,
              'client_request_id': requestId,
              'entered_by': 'staff',
              'status': roundStatus,
              'needs_review': true,
              'priced_lines': [],
              'total_baisas': 0,
            },
            {
              'id': 2,
              'round_no': 2,
              'entered_by': 'customer',
              'status': 'pending_confirmation',
              'needs_review': false,
              'priced_lines': [],
              'total_baisas': 840,
            },
          ],
  };
  @override
  Future<void> dineInReview(
    String uuid,
    int id, {
    required bool staff,
    required bool accept,
  }) async {
    expect(uuid, seat);
    expect(id, 1);
    expect(staff, true);
    expect(accept, false);
    rejects++;
    roundStatus = 'rejected';
  }

  @override
  Future<Map<String, dynamic>?> closedTableBill(String id, int table) async {
    closedReads++;
    return {
      'uuid': uuid,
      'table_id': 1,
      'order_type': 'dine_in',
      'status': 'paid',
      'items': [
        {
          'id': 1,
          'status': 'paid',
          'product_id': 10,
          'qty': 2,
          'notes': null,
          'addons': [],
        },
      ],
      if (!noProof)
        'table_round_evidence': {
          'complete': true,
          'order_uuid': uuid,
          'table_id': 1,
          'table_session_uuid': seat,
          'seating_status': 'closed',
          'merged': false,
          'rounds': [
            for (var i = 0; i < (omitHeld ? 1 : roundEvents.length); i++)
              {
                'id': i + 1,
                'round_no': i + 1,
                'same_seating': true,
                'entered_by': 'staff',
                'client_request_id':
                    (roundEvents[i]['payload'] as Map)['client_request_id'],
                'status': i == 0 ? 'accepted' : 'rejected',
                'needs_review': false,
                'lines': [
                  for (final l
                      in (roundEvents[i]['payload'] as Map)['lines'] as List)
                    {...l as Map, if (i == 0) 'order_item_id': 1},
                ],
              },
          ],
        },
    };
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected API ${i.memberName}');
}

Future<Database> realLocalDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(
    'CREATE TABLE order_history (id TEXT PRIMARY KEY, order_number INTEGER NOT NULL, order_type TEXT NOT NULL, created_at TEXT NOT NULL, snapshot_json TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE held_orders (id TEXT PRIMARY KEY, order_number INTEGER, order_reference TEXT NOT NULL, order_type TEXT NOT NULL, held_at TEXT NOT NULL, draft_json TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE dining_tables (table_id TEXT PRIMARY KEY, floor_id TEXT NOT NULL, status TEXT NOT NULL, order_number INTEGER, order_reference TEXT, updated_at TEXT NOT NULL, occupied_at TEXT, paid_at TEXT, draft_json TEXT, paid_snapshot_json TEXT, primary_table_id TEXT, linked_table_ids_json TEXT)',
  );
  await LocalOrderStorageService.createRemoteTables(db);
  await LocalOrderStorageService.createTableLedger(db);
  await LocalOrderStorageService.createRemoteBillIdentity(db);
  await CombineStore.createSchema(db);
  await RecoveryStore.createSchema(db);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final mode in ['absent-server-round', 'removed-readded']) {
    testWidgets(
      'F26 fix5 real closed $mode copy has proof-bound automatic retirement',
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
        final server = AckServer()..omitHeld = mode == 'absent-server-round';
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        late Directory auxiliary;
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          auxiliary = await Directory.systemTemp.createTemp('fix8-ack-');
          await databaseFactory.setDatabasesPath(auxiliary.path);
          localDb = await realLocalDatabase();
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
            product,
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
          c.addProduct(product);
          c.addProduct(product);
        });
        await drive(() async {
          await bridge!.send(bridge.activeSession()!);
          await coordinator.settled;
          await outbox.flush();
        });
        await pumpUntilRealCondition(
          tester,
          () => server.roundEvents.length == 1,
          reason: 'first accepted staff round ACK',
        );
        c.addProduct(c.allProducts.singleWhere((p) => p.id == '11'));
        await drive(() async {
          await bridge!.send(bridge.activeSession()!);
          await coordinator.settled;
          await outbox.flush();
        });
        final ledger = await drive(
          () => localDb.query('local_table_rounds', orderBy: 'local_round_no'),
        );
        expect(ledger!.map((r) => r['status']).toList(), ['appended', 'held']);
        server.paid = true;
        if (mode == 'removed-readded') {
          await drive(() async {
            await coordinator.cancelLine(
              bridge!.activeSession()!,
              line: {'product_id': 11, 'addon_ids': <int>[], 'notes': null},
              qty: 1,
              prepared: false,
              authorizedBy: 'Manager',
            );
            c.removeCartItem(c.cart.singleWhere((i) => i.product.id == '11'));
          });
          final cancellations = await drive(
            () => localDb.query('local_line_cancellations'),
          );
          expect(cancellations!.single['status'], 'bill_terminal');
          expect(cancellations.single['cancelled_qty'], 0);
          c.addProduct(c.allProducts.singleWhere((p) => p.id == '11'));
        }
        if (mode == 'unsent') {
          c.addProduct(c.allProducts.singleWhere((p) => p.id == '12'));
        }
        await drive(() async {
          // Persist real edited cart through its actual exit path before proving it.
          await c.returnToDiningFloorPlan();
          await bridge!.settled;
          await coordinator.settled;
          final local = await loadRecoveryLocal(
            localDb,
            1,
            outboxRow: outbox.rowForKey,
            currentGenerationOnly: true,
          );
          final proof = (await server.closedTableBill(server.uuid!, 1))!;
          final detail = await server.dineInDetail(1);
          expect(
            RecoveryStore.closedSentProof(local, proof, detail),
            false,
            reason: mode == 'removed-readded'
                ? 'Cancellation consumes the rejected allowance; re-added quantity is unsent'
                : 'Missing held round is not evidence of rejection',
          );
          expect(
            await RecoveryStore(localDb, 'fixture').retireClosed(
              local,
              bill: proof,
              table: detail,
              reconcileRejectedRounds: true,
            ),
            false,
          );
          expect(await localDb.query('draft_recovery_closed_archive'), isEmpty);
          expect(await localDb.query('dining_tables'), hasLength(1));
        });
        expect(server.roundEvents, hasLength(2));
        bridge.detach();
        bridge = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
