import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/screens/dining_table_qr_sheet.dart';
import 'package:pos_machine/services/session_service.dart';
import 'dining_table_qr_sheet_test.dart' show T7SheetGateway, T7SheetFlow,
    T7SpyController, t7SheetRow, t7SheetActiveOrder, disposeT7Sheet;

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _v6RemoteColumns = [
  'table_id',
  'seating_uuid',
  'seating_status',
  'origin',
  'temp_reference',
  'opened_at',
  'expires_at',
  'needs_review_count',
  'joined_table_ids_json',
  'bill_order_uuid',
  'bill_status',
  'bill_grand_total_baisas',
  'bill_receipt_number',
  'bill_temp_reference',
  'charge_claim_live',
  'fetched_at',
  'source',
];
const _v7IdentityColumns = [
  'bill_source',
  'bill_customer_rounds',
  'bill_staff_rounds',
  'credential_status',
];
const _v6ColumnCounts = {
  'dining_tables': 20,
  'held_orders': 6,
  'order_history': 5,
  'remote_table_states': 17,
  'remote_sync_meta': 7,
  'remote_table_disagreements': 9,
  'local_table_rounds': 16,
  'local_line_cancellations': 15,
  'table_sync_verdicts': 8,
};

Future<void> _createV6(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE order_history (
      id TEXT PRIMARY KEY, order_number INTEGER NOT NULL,
      order_type TEXT NOT NULL, created_at TEXT NOT NULL,
      snapshot_json TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE held_orders (
      id TEXT PRIMARY KEY, order_number INTEGER,
      order_reference TEXT NOT NULL, order_type TEXT NOT NULL,
      held_at TEXT NOT NULL, draft_json TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE dining_tables (
      table_id TEXT PRIMARY KEY, floor_id TEXT NOT NULL, status TEXT NOT NULL,
      order_number INTEGER, order_reference TEXT, updated_at TEXT NOT NULL,
      occupied_at TEXT, paid_at TEXT, draft_json TEXT, paid_snapshot_json TEXT,
      primary_table_id TEXT, linked_table_ids_json TEXT
    )
  ''');
  await LocalOrderStorageService.createRemoteTables(db);
  await LocalOrderStorageService.createTableLedger(db);
}

Map<String, List<Map<String, Object?>>> _v6Rows(DateTime at) {
  final stamp = at.toIso8601String();
  return {
    'dining_tables': [
      for (final id in ['1', '2', '999'])
        {
          'table_id': id,
          'floor_id': '7',
          'status': id == '2' ? 'paid' : 'occupied',
          'order_number': 1449,
          'order_reference': 'REF-$id',
          'updated_at': stamp,
          'occupied_at': stamp,
          'paid_at': id == '2' ? stamp : null,
          'draft_json': '{ "exact" : [1,2] }',
          'paid_snapshot_json': '{"money":4750}',
          'primary_table_id': id == '2' ? '1' : null,
          'linked_table_ids_json': id == '1' ? '["2"]' : null,
          'seating_key': 'key-$id',
          'seating_uuid': 'seat-$id',
          'seating_state': 'open',
          'server_order_uuid': 'bill-$id',
          'temp_reference': 'T-0906-$id',
          'winner_seating_uuid': id == '2' ? 'seat-1' : null,
          'last_verdict': 'attached',
          'last_verdict_at': stamp,
        },
    ],
    'held_orders': [
      {
        'id': 'held',
        'order_number': null,
        'order_reference': 'REF-held',
        'order_type': 'dine_in',
        'held_at': stamp,
        'draft_json': '{ "keep-held" : true }',
      },
    ],
    'order_history': [
      {
        'id': 'paid',
        'order_number': 1450,
        'order_type': 'dine_in',
        'created_at': stamp,
        'snapshot_json': '{ "paid" : 4750 }',
      },
    ],
    'remote_table_states': [
      {
        'table_id': 1,
        'seating_uuid': 'seat-1',
        'seating_status': 'billing',
        'origin': 'station',
        'temp_reference': 'T-0906-001',
        'opened_at': stamp,
        'expires_at': null,
        'needs_review_count': 2,
        'joined_table_ids_json': '[ 2 ]',
        'bill_order_uuid': 'bill-1',
        'bill_status': 'awaiting_payment',
        'bill_grand_total_baisas': 4750,
        'bill_receipt_number': null,
        'bill_temp_reference': 'T-0906-001',
        'charge_claim_live': 1,
        'fetched_at': stamp,
        'source': 'board',
      },
    ],
    'remote_sync_meta': [
      {
        'id': 1,
        'feed_cursor': 48,
        'board_fetched_at': stamp,
        'last_feed_ok_at': stamp,
        'last_error': 'old-error',
        'consecutive_failures': 2,
        'last_notified_event_id': 47,
      },
    ],
    'remote_table_disagreements': [
      {
        'id': 1,
        'observed_at': stamp,
        'table_id': '1',
        'local_status': 'occupied',
        'server_status': 'billing',
        'server_origin': 'station',
        'server_reference': 'T-0906-001',
        'local_reference': 'REF-1',
        'kind': 'status',
      },
    ],
    'local_table_rounds': [
      {
        'client_request_id': 'round-request',
        'table_id': '1',
        'seating_key': 'key-1',
        'local_round_no': 2,
        'lines_json': '[ { "product_id" : 8, "qty" : 2 } ]',
        'submitted_at': stamp,
        'printed_at': stamp,
        'outbox_key': 'tbl:key-1:round:round-request',
        'status': 'appended',
        'server_round_id': 12,
        'server_round_no': 3,
        'order_uuid': 'bill-1',
        'total_baisas': 2000,
        'review_reasons_json': null,
        'held_lines_json': '[]',
        'acked_at': stamp,
      },
    ],
    'local_line_cancellations': [
      {
        'client_request_id': 'cancel-request',
        'table_id': '1',
        'seating_key': 'key-1',
        'product_id': 8,
        'addon_ids_json': '[ 3 ]',
        'notes': 'No sugar',
        'qty': 1,
        'prepared': 1,
        'reason': 'Correction',
        'authorized_by': 'Manager',
        'cancelled_at': stamp,
        'outbox_key': 'tbl:key-1:cancel:cancel-request',
        'status': 'cancelled',
        'cancelled_qty': 1,
        'acked_at': stamp,
      },
    ],
    'table_sync_verdicts': [
      {
        'id': 1,
        'observed_at': stamp,
        'table_id': '1',
        'seating_key': 'key-1',
        'event_kind': 'open',
        'outcome': 'attached',
        'detail_json': '{ "winner" : "primary" }',
        'seen': 1,
      },
    ],
  };
}

Future<Map<String, String>> _snapshotV6(DatabaseExecutor db) async => {
  for (final table in _v6ColumnCounts.keys)
    table: jsonEncode(
      await db.query(
        table,
        columns: table == 'remote_table_states' ? _v6RemoteColumns : null,
        orderBy: 'rowid',
      ),
    ),
};

Future<Database> _freshV7() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 7,
      onCreate: (db, _) async {
        await _createV6(db);
        await LocalOrderStorageService.createRemoteBillIdentity(db);
      },
    ),
  );
  addTearDown(db.close);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  _registerSchemaTests();
  _registerFloorUiTests();
}

const _floorTable = DiningTableDefinition(
  id: '3', floorId: '1', name: 'Table 3', sizeLabel: 'square',
  seats: 4, sortOrder: 3,
);
final _floorNow = DateTime.utc(2026, 9, 6, 12);

DiningTableSession _floorSession(DiningTableStatus status) => DiningTableSession(
  tableId: '3', floorId: '1', status: status, updatedAt: _floorNow,
  occupiedAt: _floorNow.subtract(const Duration(minutes: 12)),
  orderReference: 'LOCAL-3', orderNumber: 33,
);

RemoteTableState _floorRemote({
  String status = 'open', String origin = 'station', String source = 'qr_web',
  bool bill = true,
}) => RemoteTableState(
  tableId: 3, fetchedAt: _floorNow, seatingUuid: 'seat-3',
  seatingStatus: status, origin: origin, tempReference: 'T-0906-012',
  billOrderUuid: bill ? 'order-3' : null,
  billSource: bill ? source : null,
);

Future<void> _pumpFloor(
  WidgetTester tester, {
  required Widget Function(BuildContext) builder,
  required T7SheetGateway service,
  String mode = 'live',
}) async {
  SharedPreferences.setMockInitialValues(const {'print_kitchen_tickets': false});
  final preferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      tableSessionsModeProvider.overrideWithValue(mode),
      qrTillServiceProvider.overrideWithValue(service),
      qrRoundGatewayProvider.overrideWithValue(service),
      qrSettlementCoordinatorProvider.overrideWithValue(T7SheetFlow()),
      sessionServiceProvider.overrideWithValue(
        SessionService(const FlutterSecureStorage(), preferences),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Builder(builder: (context) => Scaffold(body: Center(
        child: SizedBox(width: 580, height: 340, child: builder(context)),
      ))),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpT7FloorNotice(
  WidgetTester tester, {
  required Widget Function(BuildContext) builder,
  required T7SheetGateway service,
}) => _pumpFloor(tester, builder: builder, service: service);

void _registerFloorUiTests() {
  final rows = [
    (name: 'none / none stays free', session: null, remote: null,
      path: 'local', customer: false, shared: false),
    (name: 'none / live opens customer sheet', session: null, remote: _floorRemote(),
      path: 'sheet', customer: true, shared: false),
    (name: 'occupied / none keeps local cart', session: _floorSession(DiningTableStatus.occupied), remote: null,
      path: 'local', customer: false, shared: false),
    (name: 'occupied / live opens shared bill without importing a cart', session: _floorSession(DiningTableStatus.occupied), remote: _floorRemote(),
      path: 'sheet', customer: true, shared: true),
    (name: 'old local paid / new live QR bill opens current bill', session: _floorSession(DiningTableStatus.paid), remote: _floorRemote(),
      path: 'sheet', customer: true, shared: false),
  ];
  for (final mode in ['live', 'shadow']) {
    for (final row in rows) {
      testWidgets('occupancy matrix $mode: ${row.name}', (tester) async {
        final controller = T7SpyController();
        final service = T7SheetGateway(
          board: [t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open')],
          active: [t7SheetActiveOrder()],
        );
        final clock = ValueNotifier(_floorNow);
        addTearDown(clock.dispose);
        var paid = 0;
        var localOpened = 0;
        final before = jsonEncode(row.session?.toMap());
        final customer = customerOccupiesDiningTable(
          mode: mode, session: row.session, remote: row.remote,
        );
        expect(customer, row.customer);
        await _pumpFloor(tester, service: service, mode: mode,
          builder: (context) => buildDiningTableCardForTest(
            table: _floorTable, session: row.session,
            status: row.session?.status ?? DiningTableStatus.available,
            clock: clock, remote: row.remote, live: mode == 'live',
            customerOccupied: customer,
            customerReference: row.remote?.tempReference,
            pendingRounds: row.remote == null ? 0 : 2,
            onTap: () => routeDiningTableTap(
              tableId: '3', mode: mode, session: row.session, remote: row.remote,
              controller: controller,
              openCustomerBill: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => DiningTableQrSheet(
                  controller: controller, tableId: 3,
                  tableLabel: 'Table 3', floorLabel: 'Main floor',
                )),
              ),
              openPaidDialog: () async { paid++; },
              localOpened: () => localOpened++,
            ),
          ),
        );
        expect(controller.calls, isEmpty);
        expect(service.calls, isEmpty);
        expect(find.text('shared'), row.shared ? findsOneWidget : findsNothing);
        if (row.customer) {
          expect(find.text('Occupied by customer'), findsOneWidget);
          expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);
          expect(find.text('T-0906-012'), findsOneWidget);
          expect(find.textContaining('2 pending rounds'), findsOneWidget);
          final color = tester.widget<Text>(find.text('Table 3')).style?.color;
          expect(color, const Color(0xFFC9470F));
          final decoration = tester.widget<AnimatedContainer>(
            find.byType(AnimatedContainer)).decoration as ShapeDecoration;
          expect((decoration.gradient as LinearGradient).colors,
            const [Color(0xFFF7FFF6), Color(0xFFF7FCF4)]);
        }
        await tester.tap(find.text('Table 3'));
        await tester.pumpAndSettle();
        expect(controller.calls, row.path == 'local' ? ['open:3'] : []);
        expect(localOpened, row.path == 'local' ? 1 : 0);
        expect(paid, row.path == 'paid' ? 1 : 0);
        expect(find.byType(DiningTableQrSheet),
          row.path == 'sheet' ? findsOneWidget : findsNothing);
        expect(controller.cart, isEmpty);
        expect(jsonEncode(row.session?.toMap()), before);
        if (row.path == 'sheet') {
          expect(find.text('Long server-priced product name'), findsOneWidget);
        }
        debugPrint('T7_OCCUPANCY=mode:$mode case:${row.name} path:${row.path} local_calls:${controller.calls} local_row_unchanged:true');
        expect(tester.takeException(), isNull);
        await disposeT7Sheet(tester);
      });
    }
  }

  for (final origin in ['station', 'staff_till', 'handheld']) {
    for (final status in ['open', 'billing']) {
      test('customer occupancy accepts $origin / $status even with an older local session', () {
        final remote = _floorRemote(origin: origin, status: status);
        expect(customerOccupiesDiningTable(mode: 'live', session: null, remote: remote), true);
        expect(customerOccupiesDiningTable(mode: 'shadow', session: null, remote: remote), true);
        expect(customerOccupiesDiningTable(mode: 'off', session: null, remote: remote), false);
        expect(customerOccupiesDiningTable(mode: 'live',
          session: _floorSession(DiningTableStatus.occupied), remote: remote), true);
      });
    }
  }
  test('closed seating never renders customer occupancy', () {
    expect(customerOccupiesDiningTable(
      mode: 'live', session: null, remote: _floorRemote(status: 'closed'),
    ), false);
  });

  for (final status in DiningTableStatus.values) {
    testWidgets('Off preserves T6 card keys text colors and gestures: ${status.name}', (tester) async {
      final service = T7SheetGateway(board: const []);
      final clock = ValueNotifier(_floorNow);
      addTearDown(clock.dispose);
      final session = status == DiningTableStatus.available ? null : _floorSession(status);
      var taps = 0;
      Widget card({bool explicitOff = false}) => buildDiningTableCardForTest(
        table: _floorTable, status: status, session: session, clock: clock,
        onTap: () => taps++,
        customerOccupied: explicitOff && customerOccupiesDiningTable(
          mode: 'off', session: session, remote: _floorRemote(),
        ),
      );
      List<String> signature() => [
        for (final widget in tester.allWidgets)
          '${widget.runtimeType}|${widget.key is ValueKey ? widget.key : ''}|${widget is Text ? widget.data : ''}',
      ];
      await _pumpFloor(tester, service: service, mode: 'off', builder: (_) => card());
      final before = signature();
      final decoration = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer)).decoration;
      await _pumpFloor(tester, service: service, mode: 'off',
        builder: (_) => card(explicitOff: true));
      expect(signature(), before);
      expect(tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer)).decoration, decoration);
      expect(find.byType(DiningTableQrSheet), findsNothing);
      expect(find.byType(DiningServerBadge), findsNothing);
      expect(find.byIcon(Icons.phone_android_rounded), findsNothing);
      expect(service.calls, isEmpty);
      await tester.tap(find.text('Table 3'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      debugPrint('T7_OFF_CARD=${status.name} keys_text_colors_gestures_identical:true requests:0');
      await disposeT7Sheet(tester);
    });
  }

  for (final mode in ['live', 'shadow']) {
    for (final hasBill in [false, true]) {
      testWidgets('long press $mode customer bill visible=$hasBill', (tester) async {
        final controller = T7SpyController();
        final service = T7SheetGateway(board: const []);
        final clock = ValueNotifier(_floorNow);
        addTearDown(clock.dispose);
        String? action;
        await _pumpFloor(tester, service: service, mode: mode,
          builder: (context) => buildDiningTableCardForTest(
            table: _floorTable, status: DiningTableStatus.available,
            clock: clock, customerOccupied: true,
            customerReference: 'T-0906-012', onTap: () {},
            onLongPress: () async {
              action = await showCustomerDiningTableActions(
                context, mode: mode, hasBill: hasBill,
              );
            },
          ),
        );
        await tester.longPress(find.text('Table 3'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('table-action-customer-bill')),
          hasBill ? findsOneWidget : findsNothing);
        expect(find.text(mode == 'live' ? 'Add items' : 'Open a separate local table'),
          findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('table-action-add-items')));
        await tester.pumpAndSettle();
        expect(action, 'add_items');
        expect(controller.calls, isEmpty);
        expect(service.calls, isEmpty);
        await disposeT7Sheet(tester);
      });
    }
  }

  test('customer bill entry honors every local checkout lock', () {
    bool blocked(int index) => customerBillEntryBlocked(
      localCheckoutOpen: index == 0, processingPayment: index == 1,
      charityPrompt: index == 2, paymentLaunchOverlay: index == 3,
      recordedSplitWithCart: index == 4,
    );
    expect(blocked(-1), false);
    for (var index = 0; index < 5; index++) {
      expect(blocked(index), true, reason: 'checkout lock $index');
    }
  });
}

void _registerSchemaTests() {
  final at = DateTime.utc(2026, 9, 6, 12);

  group('T7 board identity storage', () {
    test('v6 to v7 preserves all old rows and the separate Drift outbox byte-identically', () async {
      final outbox = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(outbox.close);
      for (final key in ['pending', 'synced']) {
        await outbox.enqueueOutbox(
          OrderOutboxCompanion.insert(
            orderUuid: key,
            eventsJson: '[ { "client_event_id" : "$key:pay" } ]',
            orderNumber: const drift.Value(1450),
            createdAt: at,
            attempts: const drift.Value(3),
            serverRejections: const drift.Value(2),
            lastError: const drift.Value('Keep exact failure'),
            syncedAt: drift.Value(key == 'synced' ? at : null),
          ),
        );
      }
      Future<String> outboxRows() async => jsonEncode([
        for (final row
            in await outbox
                .customSelect('SELECT * FROM order_outbox ORDER BY order_uuid')
                .get())
          row.data,
      ]);
      final beforeOutbox = await outboxRows();
      late Map<String, String> before;
      late List<Map<String, Object?>> beforeSchema;
      var upgrades = 0;
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 7,
          onConfigure: (db) async {
            await _createV6(db);
            for (final entry in _v6Rows(at).entries) {
              for (final row in entry.value) {
                await db.insert(entry.key, row);
              }
            }
            for (final entry in _v6ColumnCounts.entries) {
              expect(
                (await db.rawQuery('PRAGMA table_info(${entry.key})')).length,
                entry.value,
                reason: '${entry.key} historical v6 column count',
              );
            }
            before = await _snapshotV6(db);
            beforeSchema = await db.rawQuery(
              "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name != 'remote_table_states' ORDER BY name",
            );
            await db.setVersion(6);
          },
          onCreate: (_, _) async => fail('The v6 fixture must upgrade'),
          onUpgrade: (db, old, next) async {
            expect(old, 6);
            expect(next, 7);
            upgrades++;
            await LocalOrderStorageService.createRemoteBillIdentity(db);
          },
        ),
      );
      addTearDown(db.close);
      expect(upgrades, 1);
      expect(await db.getVersion(), 7);
      expect(await _snapshotV6(db), before);
      expect(
        await db.rawQuery(
          "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name != 'remote_table_states' ORDER BY name",
        ),
        beforeSchema,
      );
      final identityInfo = (await db.rawQuery(
        'PRAGMA table_info(remote_table_states)',
      )).where((row) => _v7IdentityColumns.contains(row['name'])).toList();
      expect(identityInfo.map((row) => row['name']), _v7IdentityColumns);
      expect(identityInfo.map((row) => row['type']), [
        'TEXT',
        'INTEGER',
        'INTEGER',
        'TEXT',
      ]);
      for (final column in identityInfo) {
        expect(column['notnull'], 0);
        expect(column['dflt_value'], isNull);
        expect(column['pk'], 0);
      }
      expect(
        await db.query('remote_table_states', columns: _v7IdentityColumns),
        [
          {for (final column in _v7IdentityColumns) column: null},
        ],
      );
      // LAUNCH-P4 moved the Drift head to 30.
      expect(outbox.schemaVersion, 30);
      expect(await outboxRows(), beforeOutbox);
      expect((await outbox.pendingOutbox()).single.orderUuid, 'pending');
      expect((await outbox.getOutbox('synced'))!.syncedAt!.toUtc(), at);
      // ignore: avoid_print
      print(
        'T7_V6_V7_UPGRADE=version:7 upgrades:1 dining_tables:3 held:1 history:1 remote_states:1 remote_meta:1 disagreements:1 rounds:1 cancellations:1 verdicts:1 all_old_columns_byte_identical:true new_nullable_columns:4 drift_version:30 outbox:2 byte_identical:true',
      );
    });

    test('fresh v7 has exactly the ordered 21 remote columns', () async {
      final db = await _freshV7();
      final columns = await db.rawQuery(
        'PRAGMA table_info(remote_table_states)',
      );
      expect(columns.map((row) => row['name']).toList(), [
        ..._v6RemoteColumns,
        ..._v7IdentityColumns,
      ]);
      expect(await db.getVersion(), 7);
      expect(await db.query('remote_table_states'), isEmpty);
      final ddl = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name = 'remote_table_states'",
      );
      // ignore: avoid_print
      print('T7_V7_REMOTE_DDL=${jsonEncode(ddl)}');
    });

    test('board identity round trips an adopted customer bill and a staff bill with zero customer rounds', () async {
      final db = await _freshV7();
      final store = LocalOrderStorageService.forTesting(db);
      for (final customer in [true, false]) {
        final row = RemoteTableState.fromBoard({
          'table_id': 1,
          'seating': {
            'uuid': 'seating',
            'status': 'open',
            'origin': 'staff_till',
            'temp_reference': 'T-0906-001',
            'credential_status': customer ? 'ordered' : null,
          },
          'bill': {
            'order_uuid': 'bill',
            'status': 'open',
            'grand_total_baisas': 4750,
            'source': customer ? 'qr_web' : 'main_pos',
            'customer_rounds': customer ? 1 : 0,
            'staff_rounds': 1,
          },
        }, at);
        expect(row.billSource, customer ? 'qr_web' : 'main_pos');
        expect(row.billCustomerRounds, customer ? 1 : 0);
        expect(row.billStaffRounds, 1);
        expect(row.credentialStatus, customer ? 'ordered' : null);
        await store.replaceRemoteBoard([row], at);
        final restored = (await store.readRemoteTables()).single;
        expect(restored.toRow(), row.toRow());
        expect(restored.billSource, row.billSource);
        expect(restored.billCustomerRounds, row.billCustomerRounds);
        expect(restored.billStaffRounds, row.billStaffRounds);
        expect(restored.credentialStatus, row.credentialStatus);
        expect(
          (await db.query('remote_table_states'))
              .single['bill_customer_rounds'],
          customer ? 1 : 0,
        );
      }
    });

    test(
      'old server and old storage rows tolerate all four absent keys',
      () async {
        final row = RemoteTableState.fromBoard({
          'table_id': 1,
          'seating': {
            'uuid': 'seating',
            'status': 'open',
            'origin': 'station',
            'temp_reference': 'T-0906-001',
          },
          'bill': {
            'order_uuid': 'bill',
            'status': 'open',
            'grand_total_baisas': 4750,
          },
        }, at);
        expect(row.billSource, isNull);
        expect(row.billCustomerRounds, isNull);
        expect(row.billStaffRounds, isNull);
        expect(row.credentialStatus, isNull);
        for (final column in _v7IdentityColumns) {
          expect(row.toRow().containsKey(column), isFalse);
        }
        final restored = RemoteTableState.fromRow(row.toRow());
        expect(restored.toRow(), row.toRow());
        expect(restored.billSource, isNull);
        expect(restored.billCustomerRounds, isNull);
        expect(restored.billStaffRounds, isNull);
        expect(restored.credentialStatus, isNull);
        final db = await _freshV7();
        final store = LocalOrderStorageService.forTesting(db);
        await store.replaceRemoteBoard([row], at);
        expect((await store.readRemoteTables()).single.toRow(), row.toRow());
      },
    );

    test('board replacement never writes local sessions history held orders or the ledger', () async {
      final db = await _freshV7();
      for (final entry in _v6Rows(at).entries) {
        for (final row in entry.value) {
          await db.insert(entry.key, row);
        }
      }
      final before = await _snapshotV6(db);
      final store = LocalOrderStorageService.forTesting(db);
      await store.replaceRemoteBoard([
        RemoteTableState(
          tableId: 999,
          fetchedAt: at.add(const Duration(seconds: 10)),
          seatingUuid: 'remote-only',
          seatingStatus: 'open',
          billOrderUuid: 'remote-bill',
          billSource: 'qr_web',
          billCustomerRounds: 2,
          billStaffRounds: 0,
          credentialStatus: 'ordered',
        ),
      ], at.add(const Duration(seconds: 10)));
      final after = await _snapshotV6(db);
      for (final table in _v6ColumnCounts.keys) {
        if (table == 'remote_table_states' || table == 'remote_sync_meta') {
          continue;
        }
        expect(
          after[table],
          before[table],
          reason: '$table is not server-owned',
        );
      }
      expect((await store.readRemoteTables()).single.tableId, 999);
      expect((await store.readRemoteMeta()).lastNotifiedEventId, 47);
    });
  });
}
