import 'dart:async';
import 'dart:convert';
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
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';

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
                      : 'appended',
                if (e['event_type'] == 'table.session.round') ...{
                  'round_id': 1,
                  'round_no': 1,
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
          },
    'rounds': <dynamic>[],
  };
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
  for (final mode in [
    'same-session',
    'already-stuck',
    'other-close',
    'merged',
    'pending',
    'legacy',
    'unsent',
    'missing-pay',
  ]) {
    final restart = mode == 'already-stuck';
    final guarded = !['same-session', 'already-stuck'].contains(mode);
    testWidgets(
      'F12 real ACK SQLite $mode preserves evidence and retires only own paid sent copy',
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
          outbox.addAckListener(ServerReceiptHistory(storage).acknowledge);
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
        c.prepareDiningTableTender =
            null; // External claim is outside this existing regression.
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
        final before = await drive(() => localDb.query('dining_tables'));
        expect(before!.single['seating_state'], 'open');
        expect(before.single['seating_uuid'], seat);
        // Actual fresh-open path leaves controller identity behind the persisted
        // coordinator ACK. A bound pre-seeded fixture would hide the proof gate.
        expect(c.diningSessionFor('1')!.seatingUuid, isNull);
        c.selectPaymentMethod('Cash');
        var done = false;
        await drive(() async {
          unawaited(
            c.payAndPrint(cashTenderedAmount: 20).then((_) => done = true),
          );
        });
        for (var i = 0; i < 200 && !done; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await drive(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        expect(done, true);
        expect(c.cart, isEmpty);
        expect(c.activeDiningTableId, isNull);
        final closed = await drive(() => localDb.query('dining_tables'));
        expect(
          closed!.single['seating_state'],
          'closed',
          reason: 'Real coordinator pay ACK must persist the failing state',
        );
        expect(closed.single['server_order_uuid'], server.uuid);
        final receiptRows = await drive(() => localDb.query('order_history'));
        expect(receiptRows, hasLength(1));
        expect(
          receiptRows!.single['snapshot_json'],
          contains('"serverReceiptConfirmed":true'),
        );
        expect(receiptRows.single['snapshot_json'], contains('TEST-FIX7-120'));
        final payRow = await drive(() => outbox.rowForKey(server.uuid!));
        expect(payRow!.syncedAt, isNotNull);
        // Negative cases alter only disposable fixture evidence after the real
        // ACK. None substitute for coordinator processing or identity storage.
        await drive(() async {
          if (mode == 'other-close') {
            await localDb.update('dining_tables', {'last_verdict': 'closed'});
          }
          if (mode == 'merged') {
            await localDb.update('dining_tables', {
              'seating_state': 'merged',
              'winner_seating_uuid': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            });
          }
          if (mode == 'pending' || mode == 'legacy') {
            final snapshot =
                jsonDecode(receiptRows.single['snapshot_json'] as String)
                    as Map;
            if (mode == 'pending') snapshot['serverReceiptConfirmed'] = false;
            if (mode == 'legacy') snapshot['serverReceipt'] = false;
            await localDb.update('order_history', {
              'snapshot_json': jsonEncode(snapshot),
            });
          }
          if (mode == 'unsent') {
            final draft =
                jsonDecode(closed.single['draft_json'] as String) as Map;
            ((draft['items'] as List).single as Map)['qty'] = 3;
            await localDb.update('dining_tables', {
              'draft_json': jsonEncode(draft),
            });
          }
          if (mode == 'missing-pay') {
            await driftDb.customStatement(
              'DELETE FROM order_outbox WHERE order_uuid = ?',
              [server.uuid],
            );
          }
        });
        final preserved = await drive(() => localDb.query('dining_tables'));
        final preservedReceipts = await drive(
          () => localDb.query('order_history'),
        );
        if (restart) {
          bridge!.detach();
          bridge = null;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          await mount();
        }
        // Board is already free: this isolates missing in-memory identity from
        // board lag. Restart reads the real closed row created by the pay ACK.
        boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
            },
          ),
        );
        for (var i = 0; i < 160; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await drive(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        if (guarded) {
          expect(await drive(() => localDb.query('dining_tables')), preserved);
          expect(
            await drive(() => localDb.query('order_history')),
            preservedReceipts,
          );
          expect(
            await drive(() => localDb.query('draft_recovery_closed_archive')),
            isEmpty,
          );
        } else {
          await pumpUntilRealCondition(
            tester,
            () async => (await localDb.query('dining_tables')).isEmpty,
            reason: 'own paid bill retirement committed to real SQLite',
          );
          expect(
            await drive(() => localDb.query('dining_tables')),
            isEmpty,
            reason:
                'Own acknowledged staff-only pay must automatically free the table',
          );
          final archives = await drive(
            () => localDb.query('draft_recovery_closed_archive'),
          );
          expect(archives, hasLength(1));
          final archive =
              jsonDecode(archives!.single['local_json'] as String) as Map;
          expect((archive['rows'] as List).single['row'], closed.single);
          expect(
            await drive(() => localDb.query('order_history')),
            receiptRows,
          );
        }
        expect(
          server.events.where((e) => e['event_type'] == 'order.pay'),
          hasLength(1),
        );
        expect(
          server.events.where((e) => e['event_type'] == 'order.void'),
          isEmpty,
        );
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
        );
        final dynamic currentHost = tester.state(find.byType(StaffPosScreen));
        if (!guarded) {
          expect(
            (currentHost.controller as PosController).diningSessionFor('1'),
            isNull,
          );
        }
        bridge?.detach();
        bridge = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
