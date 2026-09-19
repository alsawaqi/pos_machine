import 'real_io_wait.dart';
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

const seat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const product = Product(
  id: '10',
  name: 'Coffee',
  category: 'Drinks',
  price: 2.7,
  addonGroupIds: [1],
);

// External HTTP responses and board polling are simulated. The screen, bridge,
// coordinator, outbox ACKs, delta calculation and both databases are real.
class AckServer implements PosApiService {
  bool paid = false;
  bool holdRound = false;
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
                'temp_reference': 'T-FIX8-001',
                if (e['event_type'] == 'order.pay') ...{
                  'status': 'paid',
                  'receipt_number': 'TEST-FIX8-120',
                } else
                  'outcome': e['event_type'] == 'table.session.open'
                      ? 'opened'
                      : holdRound
                      ? 'held'
                      : 'appended',
                if (e['event_type'] == 'table.session.round') ...{
                  if (holdRound) ...{
                    'held_lines': [
                      {'line_index': 0, 'reason': 'out_of_stock'},
                    ],
                    'review_reasons': ['out_of_stock'],
                  },
                  'round_id': events
                      .where((e) => e['event_type'] == 'table.session.round')
                      .length,
                  'round_no': events
                      .where((e) => e['event_type'] == 'table.session.round')
                      .length,
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
            'grand_total_baisas': 2900,
            'items': [],
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
  for (final scenario in ['fresh', 'prior', 'held']) {
    final priorRound = scenario == 'prior';
    final heldRound = scenario == 'held';
    testWidgets(
      heldRound
          ? 'R2 held ACK on open seating outranks older free board but not newer closure'
          : 'F16 real Apply enables first send immediately with prior round = $priorRound',
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
          auxiliary = await Directory.systemTemp.createTemp('fix8-apply-');
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
        c.addonGroups = const [
          AddonGroup(
            id: 1,
            name: 'Size',
            multiSelect: false,
            minSelections: 1,
            options: [AddonOption(id: 11, label: 'Large', priceDelta: 0.2)],
          ),
        ];
        c.printReceipts = false;
        c.printKitchenTickets = false;
        // Last floor-plan read was free before this till opened the seating.
        // Real devices keep that snapshot until the next board poll.
        final freeAt = DateTime.now().subtract(const Duration(seconds: 1));
        boards.add(
          RemoteTableSnapshot(
            tables: {1: RemoteTableState(tableId: 1, fetchedAt: freeAt)},
            meta: RemoteSyncMeta(boardFetchedAt: freeAt),
          ),
        );
        await tester.pump();
        await drive(() async {
          await storage.refreshRecoveryGuard();
          expect(c.diningTableDefinitions, isNotEmpty);
          await c.openDiningTable('1');
          expect(c.activeDiningTableId, '1', reason: c.lastPaymentMessage);
          expect(await localDb.query('local_table_rounds'), isEmpty);
          c.addProduct(product);
        });
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await drive(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        bridge = c.diningTableSyncHooks as TableKitchenBridge;
        expect(bridge.coordinator, same(coordinator));
        await drive(() => coordinator.settled);
        await pumpUntilRealCondition(
          tester,
          () =>
              server.events.any((e) => e['event_type'] == 'table.session.open'),
          reason: 'real table open persisted and reached transport',
        );
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.open'),
          hasLength(1),
        );
        await pumpUntilRealCondition(tester, () async {
          final rows = await localDb.query('dining_tables');
          return rows.length == 1 && rows.single['seating_uuid'] == seat;
        }, reason: 'real table-open ACK identity committed to SQLite');
        expect(
          (await drive(
            () => localDb.query('dining_tables'),
          ))!.single['seating_uuid'],
          seat,
        );
        if (priorRound) {
          c.updateCartItemCustomization(
            c.cart.single,
            modifiers: const [
              CartItemModifier(
                id: '11',
                group: 'Size',
                label: 'Large',
                price: .2,
              ),
            ],
            notes: '',
          );
          await drive(() => bridge!.send(bridge.activeSession()!));
          await drive(() => coordinator.settled);
          final occupiedAt = DateTime.now();
          boards.add(
            RemoteTableSnapshot(
              tables: {
                1: RemoteTableState(
                  tableId: 1,
                  fetchedAt: occupiedAt,
                  seatingUuid: seat,
                  seatingStatus: 'open',
                  billOrderUuid: server.uuid,
                  billStatus: 'open',
                  billSource: 'main_pos',
                  billCustomerRounds: 0,
                  billStaffRounds: 1,
                ),
              },
              meta: RemoteSyncMeta(boardFetchedAt: occupiedAt),
            ),
          );
          c.addProduct(product);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add On').first);
        }
        await tester.pump();
        await tester.tap(find.text('Add On').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Large'));
        await tester.pump();
        final before = server.events
            .where((e) => e['event_type'] == 'table.session.round')
            .length;
        expect(before, priorRound ? 1 : 0);
        await tester.tap(find.byKey(const ValueKey('customize-confirm')));
        // Advance only the dialog completion/I/O, not the periodic refresh that
        // hid the fresh-table bug on the device. Observe the first closed frame.
        var closed = false;
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          if (find
              .byKey(const ValueKey('customize-confirm'))
              .evaluate()
              .isEmpty) {
            closed = true;
            break;
          }
        }
        expect(closed, true);
        final send = find.byKey(const ValueKey('table-send-to-kitchen'));
        expect(
          tester.widget<FilledButton>(send).onPressed,
          isNotNull,
          reason:
              'Send must be enabled on the first frame after real Apply closes',
        );
        server.holdRound = heldRound;
        await tester.tap(send);
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await drive(() => coordinator.settled);
        await drive(() => outbox.flush());
        final rounds = server.events
            .where((e) => e['event_type'] == 'table.session.round')
            .toList();
        expect(rounds, hasLength(before + 1));
        expect((rounds.last['payload'] as Map)['lines'], [
          {
            'product_id': 10,
            'qty': 1,
            'addon_ids': [11],
          },
        ]);
        expect(
          await drive(() => localDb.query('local_table_rounds')),
          hasLength(before + 1),
        );
        if (heldRound) {
          final held = (await drive(
            () => localDb.query('local_table_rounds'),
          ))!.single;
          expect(held['status'], 'held');
          expect(coordinator.cachedSession('1')!.seatingState, 'open');
          expect(coordinator.cachedSession('1')!.lastVerdict, 'held');
          // Only the older free board exists: no board poll rescues this screen.
          if (find.text('Done').evaluate().isNotEmpty) {
            await tester.tap(find.text('Done').last);
            await tester.pumpAndSettle();
          }
          expect(
            find.textContaining('This bill was paid or closed'),
            findsNothing,
          );
          expect(find.text('Correct held round'), findsOneWidget);
          // Held lines need correction, not a duplicate send of the same delta.
          expect(tester.widget<FilledButton>(send).onPressed, isNull);
        }
        // A later authoritative free board still blocks this old generation.
        final closedAt = coordinator
            .cachedSession('1')!
            .lastVerdictAt!
            .add(const Duration(seconds: 1));
        boards.add(
          RemoteTableSnapshot(
            tables: {1: RemoteTableState(tableId: 1, fetchedAt: closedAt)},
            meta: RemoteSyncMeta(boardFetchedAt: closedAt),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.widget<FilledButton>(send).onPressed, isNull);
        if (heldRound) expect(find.text('Correct held round'), findsNothing);
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(before + 1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
