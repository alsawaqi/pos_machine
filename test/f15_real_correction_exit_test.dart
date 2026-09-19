import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';

const seat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const product = Product(
  id: '10',
  name: 'Coffee',
  category: 'Drinks',
  price: 2.7,
);

// Only the external server is simulated. Payment, outbox ACK processing,
// identity persistence, receipt history and retirement use production code.
class AckServer implements PosApiService {
  bool paid = false;
  String roundStatus = 'pending_confirmation';
  String? requestId;
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
            uuid = (e['payload'] as Map)['order_uuid'] as String;
            if (e['event_type'] == 'table.session.round') {
              requestId = (e['payload'] as Map)['client_request_id'] as String;
            }
            if (e['event_type'] == 'order.pay') paid = true;
            results.add({
              'client_event_id': e['client_event_id'],
              'status': 'processed',
              'result': {
                'order_uuid': uuid,
                'table_session_uuid': seat,
                'temp_reference': 'T-FIX7-001',
                if (e['event_type'] == 'order.pay') ...{
                  'status': 'paid',
                  'receipt_number': 'TEST-FIX7-120',
                } else
                  'outcome': e['event_type'] == 'table.session.open'
                      ? 'opened'
                      : 'held',
                if (e['event_type'] == 'table.session.round') ...{
                  'round_id': 1,
                  'round_no': 1,
                  'held_lines': [
                    {'line_index': 0, 'reason': 'out_of_stock'},
                  ],
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
    'rounds': [
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
  Future<Map<String, dynamic>?> closedTableBill(String id, int table) async => {
    'uuid': uuid,
    'table_id': 1,
    'order_type': 'dine_in',
    'status': 'paid',
  };
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
  for (final mode in ['reject-and-correct', 'edit-local-items']) {
    testWidgets(
      'F15 real host exit and SQLite ledger $mode never auto-resends and exposes editable cart',
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
          for (var i = 0; i < 500 && !done; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
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
        final server = AckServer();
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        late Directory auxiliary;
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          auxiliary = await Directory.systemTemp.createTemp('fix7-ack-');
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
          await tester.pump();
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
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await drive(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        c.applyCatalog(
          categories: const ['Drinks'],
          products: const [product],
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
        // External tender preflight/printing are outside the defect. Neither
        // callback replaces payAndPrint, coordinator ACKs or any storage method.
        c.verifyDiningTableTender = () async => null;
        c.onOrderCompleted = (_) {};
        coordinator.paymentContext = (_) async => const TablePaymentContext();
        final shell = await SharedPreferences.getInstance();
        await drive(() async {
          bridge = TableKitchenBridge(
            controller: c,
            coordinator: coordinator,
            preferences: shell,
            l10n: L10nEn.new,
            printer: (_) async => true,
            onPrintFailure: () {},
          )..attach();
        });
        await drive(() async {
          await storage.refreshRecoveryGuard();
          expect(c.diningTableDefinitions, isNotEmpty);
          await c.openDiningTable('1');
          expect(c.activeDiningTableId, '1', reason: c.lastPaymentMessage);
          c.addProduct(product);
          c.addProduct(product);
        });
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await drive(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        await drive(() async {
          expect(c.cart, hasLength(1), reason: c.lastPaymentMessage);
          expect(c.diningSessionFor('1'), isNotNull, reason: c.displayNote);
          await bridge!.send(bridge!.activeSession()!);
          await coordinator.settled;
          await outbox.flush();
        });
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
        );
        Future<void> settle() async {
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await drive(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
          }
        }

        await settle();
        // Close the real reconciliation notice if the held ACK surfaced it.
        if (find.text('Done').evaluate().isNotEmpty) {
          await tester.tap(find.text('Done').last);
          await settle();
        }
        final held = await drive(() => localDb.query('local_table_rounds'));
        expect(held!.single['status'], 'held');
        if (mode == 'edit-local-items') {
          await drive(
            () => coordinator.rejectHeldRounds(
              bridge!.activeSession()!,
              readDetail: () => server.dineInDetail(1),
              reject: (uuid, id) =>
                  server.dineInReview(uuid, id, staff: true, accept: false),
              isCurrent: () => true,
            ),
          );
        }
        boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(
                tableId: 1,
                fetchedAt: DateTime.now(),
                seatingUuid: seat,
                seatingStatus: 'open',
                billOrderUuid: server.uuid,
                billStatus: 'open',
                billSource: 'main_pos',
                billCustomerRounds: 1,
                billStaffRounds: 1,
                billGrandTotalBaisas: 840,
                needsReviewCount: 1,
              ),
            },
          ),
        );
        await settle();
        // Open through the actual till host; do not substitute workspace.onExit
        // or TableKitchenBridge.onTableLeft (the two components causing F15).
        if (find.byType(DineInScreen).evaluate().isEmpty) {
          expect(find.text('Customer bill'), findsWidgets);
          await tester.tap(find.text('Customer bill').first);
          await settle();
        }
        expect(find.byType(DineInScreen), findsOneWidget);
        if (mode == 'reject-and-correct') {
          expect(find.text('Correct held round'), findsOneWidget);
          await tester.tap(find.text('Correct held round'));
          await settle();
          expect(find.text('Reject and correct'), findsOneWidget);
          await tester.tap(find.text('Reject and correct'));
          await settle();
        } else {
          expect(find.text('Edit local items'), findsOneWidget);
          await tester.tap(find.text('Edit local items'));
          await settle();
        }
        await drive(() async {
          await coordinator.settled;
          await outbox.flush();
        });
        expect(server.rejects, 1);
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
          reason:
              'Correct/edit is not table leave and must not auto-send rejected items',
        );
        expect(
          (await drive(
            () => localDb.query('local_table_rounds'),
          ))!.single['status'],
          'rejected',
        );
        expect(find.byType(DineInScreen), findsNothing);
        expect(c.activeDiningTableId, '1');
        expect(c.cart.single.qty, 2);
        // The regular editable cart is live: changing quantity must work before
        // staff explicitly choose to send a newly corrected round.
        c.addProduct(product);
        await settle();
        expect(c.cart.single.qty, 3);
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
        );
        bridge?.detach();
        bridge = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
