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
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';

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
  bool shared = false;
  bool claimed = false;
  int manual = 0, comp = 0;
  Map<String, dynamic>? customer;
  @override
  Future<List<CustomerSearchResult>> searchCustomers(String query) async => [
    CustomerSearchResult(
      id: query == 'Second' ? 6 : 5,
      name: query,
      phone: '90000000',
    ),
  ];
  @override
  Future<List<Map<String, dynamic>>> checkoutPush(Map<String, dynamic> e) =>
      PosApiService(tokenGetter: () => 'fixture', dio: dio()).checkoutPush(e);
  int get total => 5400 - manual - comp;
  DateTime? claimedAt;
  final adjustments = <Map<String, dynamic>>[];
  Object? journalFault;
  Map<String, dynamic> get claim => {
    'order_uuid': uuid,
    'status': 'awaiting_payment',
    'charge_amount_baisas': total,
    'charge_claimed_at': claimedAt!.toUtc().toIso8601String(),
    'charge_deadline_at': claimedAt!
        .add(const Duration(minutes: 5))
        .toUtc()
        .toIso8601String(),
    'already_claimed_by_this_device': false,
  };
  @override
  Future<Map<String, dynamic>> checkoutClaim(
    Map<String, dynamic> payload,
  ) async {
    expect(payload['order_uuid'], uuid);
    final replay = claimed;
    claimed = true;
    claimedAt ??= DateTime.now();
    return {...claim, 'already_claimed_by_this_device': replay};
  }

  @override
  Future<Map<String, dynamic>> checkoutRead(String id) async => {
    'order': (await dineInDetail(1))['bill'],
    'claim': claim,
    'customer': customer,
  };
  @override
  Future<void> checkoutRelease(Map<String, dynamic> payload) async {
    claimed = false;
  }

  @override
  Future<void> cancelQuickReservation(Map<String, dynamic> payload) async {
    claimed = false;
  }

  @override
  Future<Map<String, dynamic>> dineInAdjust(
    String id,
    Map<String, dynamic> p,
  ) async {
    try {
      final journal = await SqliteDineInStore.open('inspection');
      final saved = (await journal.db.query('dine_in_requests')).single;
      expect(saved['request_id'], p['client_request_id']);
      expect(jsonDecode(saved['payload'] as String), p);
    } catch (e) {
      journalFault = e;
      rethrow;
    }
    adjustments.add(p);
    final a = Map<String, dynamic>.from(p['adjustment'] as Map);
    switch (a['kind']) {
      case 'discount':
        manual = a['mode'] == 'clear'
            ? 0
            : a['mode'] == 'fixed'
            ? a['amount_baisas'] as int
            : a['mode'] == 'rule'
            ? 270
            : (5400 * (a['percent_bp'] as int) / 10000).round();
      case 'comp':
        expect(a['mode'] == 'clear' || a['authorized_by'] == 'Manager', true);
        comp = a['mode'] == 'clear'
            ? 0
            : 2700 * ((a['target'] as Map)['qty'] as int);
      case 'customer':
        customer = a['mode'] == 'detach'
            ? null
            : {
                'id': a['customer_id'],
                'name': a['customer_id'] == 5 ? 'First' : 'Second',
                'phone': '90000000',
              };
    }
    return {
      'outcome': 'adjusted',
      'table_session_uuid': seat,
      'winner_table_session_uuid': null,
      'order_uuid': uuid,
      'table_id': 1,
      'seating_key': p['seating_key'],
      'client_request_id': p['client_request_id'],
      'kind': a['kind'],
      'mode': a['mode'],
      'grand_total_baisas': total,
    };
  }

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
                'table_session_uuid': seat,
                'temp_reference': 'T-FIX7-001',
                if (e['event_type'] == 'order.pay') ...{
                  'status': 'paid',
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
    'occupied': !paid && uuid != null,
    'orphaned': false,
    'seating': paid || uuid == null
        ? null
        : {
            'uuid': seat,
            'table_id': 1,
            'status': 'open',
            'joined_table_ids': [],
          },
    'bill': paid || uuid == null
        ? null
        : {
            'uuid': uuid,
            'id': 65,
            'temp_reference': 'T-T65-001',
            'status': claimed ? 'awaiting_payment' : 'open',
            'source': 'main_pos',
            'checkout_policy': 'staff_table_claim_v1',
            'charge': claimed ? 'claimed' : 'none',
            'subtotal_baisas': 5400,
            'discount_total_baisas': manual,
            'manual_discount_baisas': manual,
            'comp_total_baisas': comp,
            'tax_total_baisas': 0,
            'grand_total_baisas': total,
            'customer': customer,
            'adjustment_state': {
              'discount': {
                'mode': 'percent',
                'amount_baisas': manual,
                'basis_baisas': 5400,
                'stale': false,
              },
              'comp': comp == 0
                  ? null
                  : {'reason_name': 'Service', 'amount_baisas': comp},
            },
            'discounts': [
              if (manual > 0) {'name': '10%', 'amount_baisas': manual},
            ],
            'items': [
              {
                'id': 1,
                'product_id': 10,
                'product_name': 'Coffee',
                'qty': 2,
                'unit_price_baisas': 2700,
                'line_total_baisas': 5400,
                'line_discount_baisas': 0,
                'status': 'open',
                'addons': [],
              },
            ],
            'order_type': 'dine_in',
            'table_id': 1,
          },
    'rounds': <dynamic>[
      if (uuid != null && !paid)
        {
          'id': 1,
          'round_no': 1,
          'status': 'accepted',
          'entered_by': 'staff',
          'priced_lines': [],
        },
      if (shared && uuid != null && !paid)
        {
          'id': 2,
          'round_no': 2,
          'status': 'accepted',
          'entered_by': 'customer',
          'priced_lines': [],
        },
    ],
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

void main() => runPaymentRegression();

void runPaymentRegression({bool gps = false, bool parkedWaste = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final mode in [
    'staff',
    if (!parkedWaste) 'shared',
    if (!parkedWaste) 'already-stuck',
    if (gps) 'unadjusted',
  ]) {
    final restart = mode == 'already-stuck';
    testWidgets(
      'T65 real screen ${parkedWaste ? 'parked waste ' : ''}${gps ? 'GPS ' : ''}$mode payment journals canonical amount and retires own acknowledged copy',
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

        Future<void> settle([int frames = 18]) async {
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await drive(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
          }
        }

        Future<void> tap(Finder target) async {
          await pumpUntilRealCondition(tester, () {
            try {
              if (target.evaluate().isEmpty) return false;
              final widget = tester.widget(target);
              return widget is! TextButton || widget.onPressed != null;
            } on StateError {
              return false;
            }
          }, reason: 'requested control is visible and enabled');
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await pumpUntilRealCondition(tester, () {
            try {
              return target.hitTestable().evaluate().isNotEmpty;
            } on StateError {
              return false;
            }
          }, reason: 'requested control is ready for a real tap');
          await tester.tap(target);
          await settle(6);
          final control = find.byKey(const ValueKey('table-adjust-discount'));
          if (find.byType(Dialog).evaluate().isEmpty &&
              find.byType(BottomSheet).evaluate().isEmpty &&
              control.evaluate().isNotEmpty) {
            await pumpUntilRealCondition(
              tester,
              () =>
                  find.byType(Dialog).evaluate().isNotEmpty ||
                  find.byType(BottomSheet).evaluate().isNotEmpty ||
                  control.evaluate().isEmpty ||
                  tester.widget<TextButton>(control).onPressed != null,
              reason: 'adjustment journal and refresh completed',
            );
          }
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
        final server = AckServer()..shared = mode == 'shared';
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
        if (parkedWaste) {
          await drive(() async {
            await outbox.enqueueEvent('tbl:legacy-seat:waste:fixture', {
              'client_event_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'event_type': 'product.waste',
              'client_timestamp': DateTime.now().toUtc().toIso8601String(),
              'payload': {
                'lines': [
                  {'product_id': 10, 'qty': 1, 'reason': 'other'},
                ],
                'note': 'cancelled after preparation — table 1',
              },
            });
            for (var i = 1; i < OrderSyncRepository.maxServerRejections; i++) {
              await outbox.flush();
            }
            expect(await outbox.stuckBatches(), hasLength(1));
          });
        }
        debugOrderStorageOverride = storage;
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
            realTableHealth: parkedWaste,
            connectivityOnline: parkedWaste,
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
          () => !c.isLoadingStorage && c.diningTableSyncHooks != null,
          reason: 'real I/O condition before assertions',
        );
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
        c.compReasons = const [
          CompReasonRef(id: 1, code: 'service', name: 'Service', maxAmount: 3),
        ];
        c.printReceipts = false;
        c.printKitchenTickets = false;
        await drive(() async {
          await storage.refreshRecoveryGuard();
          expect(c.diningTableDefinitions, isNotEmpty);
          await c.openDiningTable('1');
          expect(c.activeDiningTableId, '1', reason: c.lastPaymentMessage);
          c.addProduct(product);
          c.addProduct(product);
        });
        if (parkedWaste) {
          await pumpUntilRealCondition(
            tester,
            () => find
                .byKey(const ValueKey('waste-sync-attention-banner'))
                .evaluate()
                .isNotEmpty,
            reason:
                'parked waste shown as stock waste with Stuck sales destination',
          );
          expect(
            find.textContaining('Stock waste could not sync.'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Stuck sales to review and retry'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('table-sync-attention-banner')),
            findsNothing,
          );
          expect(
            find.textContaining('Table synchronization is pending.'),
            findsNothing,
          );
          await drive(outbox.assertIdleForCombine);
        }

        await pumpUntilRealCondition(tester, () {
          final control = find.byKey(const ValueKey('table-send-to-kitchen'));
          return control.hitTestable().evaluate().isNotEmpty &&
              tester.widget<FilledButton>(control).onPressed != null;
        }, reason: 'real I/O condition before assertions');
        await tester.tap(find.byKey(const ValueKey('table-send-to-kitchen')));
        await pumpUntilRealCondition(
          tester,
          () => server.events.any(
            (e) => e['event_type'] == 'table.session.round',
          ),
          reason: 'real I/O condition before assertions',
        );
        await drive(() async {
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

        c.availableDiscounts = const [
          MerchantDiscount(
            id: 7,
            name: 'Automatic',
            scope: 'order',
            amountType: 'percent',
            percent: 5,
            autoApply: true,
          ),
        ];
        c.maybeAutoApplyOrderDiscount();
        expect(
          c.discount.isActive,
          false,
          reason: 'Live rounds already own automatic discounts',
        );
        c.availableDiscounts = [];
        if (mode == 'shared') {
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
                  billGrandTotalBaisas: 5400,
                ),
              },
            ),
          );
          await pumpUntilRealCondition(
            tester,
            () => find.byType(DineInScreen).evaluate().isNotEmpty,
            reason: 'shared bill screen opened',
          );
          expect(find.byType(DineInScreen), findsOneWidget);
        }
        await pumpUntilRealCondition(tester, () {
          final control = find.byKey(const ValueKey('table-adjust-discount'));
          return control.evaluate().isNotEmpty &&
              tester.widget<TextButton>(control).onPressed != null;
        }, reason: 'table detail and journal ready');
        if (mode != 'unadjusted') {
          final discount = find.byKey(const ValueKey('table-adjust-discount'));
          expect(discount, findsOneWidget);
          expect(
            tester.widget<TextButton>(discount).onPressed,
            isNotNull,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .join(' | '),
          );
          await tester.ensureVisible(discount);
          await tester.tap(discount);
          await pumpUntilRealCondition(
            tester,
            () => find.text('10%').evaluate().isNotEmpty,
            reason: 'real I/O condition before assertions',
          );
          expect(find.text('10%'), findsWidgets);
          await tester.tap(
            find
                .descendant(of: find.byType(Dialog), matching: find.text('10%'))
                .last,
          );
          await tester.pump();
          await tap(
            find.text(L10nEn().posDiscountDlgApply('10% Discount')).last,
          );
          await pumpUntilRealCondition(
            tester,
            () => server.adjustments.length == 1,
            reason: 'real I/O condition before assertions',
          );
          expect(
            server.adjustments,
            hasLength(1),
            reason: server.journalFault?.toString(),
          );
          expect(server.manual, 540);
          expect(
            c.discount.value,
            0,
            reason: 'No server adjustment may become local cart money',
          );

          // Both the ordinary live cart and adopted DineInScreen reuse these dialogs.
          await tap(discount);
          await tap(
            find
                .descendant(of: find.byType(Dialog), matching: find.text('5%'))
                .last,
          );
          await tap(
            find.text(L10nEn().posDiscountDlgApply('5% Discount')).last,
          );
          expect(server.manual, 270);
          await tap(discount);
          await tap(find.text(L10nEn().posDiscountDlgClear).last);
          expect(server.manual, 0);
          await tap(discount);
          await tap(
            find
                .descendant(of: find.byType(Dialog), matching: find.text('10%'))
                .last,
          );
          await tap(
            find.text(L10nEn().posDiscountDlgApply('10% Discount')).last,
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('manager_biometric_registered', true);
          var authorized = false, gateCalls = 0;
          const gate = MethodChannel('com.example.manager_biometrics');
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(gate, (call) async {
                gateCalls++;
                return authorized;
              });
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(gate, null),
          );
          final compButton = find.byKey(const ValueKey('table-adjust-comp'));
          final beforeDenied = server.adjustments.length;
          await tap(compButton);
          await tap(find.text(L10nEn().commonCancel).last);
          expect(server.adjustments, hasLength(beforeDenied));
          expect(
            await drive(
              () async => (await SqliteDineInStore.open(
                'inspection',
              )).db.query('dine_in_requests'),
            ),
            isEmpty,
          );
          // The warning uses the existing temporary feedback overlay; wait it out.
          await settle(45);
          authorized = true;
          await tap(compButton);
          await tap(find.byKey(const ValueKey('comp-target-dropdown')));
          await tap(find.text('Coffee ×2').last);
          if (find.text('2 / 2').evaluate().isNotEmpty) {
            await tap(find.byKey(const ValueKey('comp-qty-decrement')));
          }
          await tap(find.text('Service').last);
          await tap(find.text(L10nEn().posCompApplyButton).last);
          expect(server.comp, 2700);
          expect(c.appliedComp, null);
          await tap(compButton);
          await tap(find.text('Replace').last);
          await tap(find.byKey(const ValueKey('comp-target-dropdown')));
          await tap(find.text('Coffee ×2').last);
          if (find.text('2 / 2').evaluate().isNotEmpty) {
            await tap(find.byKey(const ValueKey('comp-qty-decrement')));
          }
          await tap(find.text('Service').last);
          await tap(find.text(L10nEn().posCompApplyButton).last);
          expect(server.comp, 2700);
          await tap(compButton);
          await tap(find.text(L10nEn().posCompRemoveButton).last);
          expect(server.comp, 0);
          expect(gateCalls, 3);
          c.availableDiscounts = const [
            MerchantDiscount(
              id: 8,
              name: 'Manager five',
              scope: 'order',
              amountType: 'percent',
              percent: 5,
              requiresManagerApproval: true,
            ),
          ];
          authorized = false;
          final beforeRule = server.adjustments.length;
          await tap(discount);
          await tap(find.text('Manager five').last);
          await tap(find.text(L10nEn().commonCancel).last);
          await settle(45);
          expect(server.adjustments, hasLength(beforeRule));
          expect(
            await drive(
              () async => (await SqliteDineInStore.open(
                'inspection',
              )).db.query('dine_in_requests'),
            ),
            isEmpty,
          );
          authorized = true;
          await tap(discount);
          await tap(find.text('Manager five').last);
          expect(server.manual, 270);
          expect(
            (server.adjustments.last['adjustment'] as Map)['authorized_by'],
            'Manager',
          );
          c.availableDiscounts = [];
          await tap(discount);
          // Wait for the fresh-read dialog, not a fixed number of frames.
          await pumpUntilRealCondition(
            tester,
            () => find
                .byKey(const ValueKey('discount-custom-percent'))
                .evaluate()
                .isNotEmpty,
            reason: 'manual discount dialog finished its fresh read',
          );
          await tester.pumpAndSettle();
          // Exercise free-entry as well as the presets used earlier.
          await tester.enterText(
            find.byKey(const ValueKey('discount-custom-percent')),
            '10',
          );
          await tester.enterText(
            find.byKey(const ValueKey('discount-reason')),
            'Synthetic test',
          );
          await tester.pump();
          await tap(
            find.text(L10nEn().posDiscountDlgApply('10% Discount')).last,
          );
          expect(server.manual, 540);
          expect(c.discount.isActive, false);
          final customerButton = find.byKey(
            const ValueKey('table-adjust-customer'),
          );
          Future<void> search(String name) async {
            final field = find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            );
            await pumpUntilRealCondition(
              tester,
              () => field.evaluate().length == 1,
              reason: 'customer search dialog opened after fresh bill read',
            );
            await tester.enterText(field, name);
            await tap(find.text(L10nEn().posCustomerSearchButton).last);
            await tap(find.text(name).last);
          }

          await tap(customerButton);
          await search('First');
          expect(server.customer?['id'], 5);
          expect(c.selectedCustomer, null);
          await tap(customerButton);
          await tap(find.text('Replace').last);
          await search('Second');
          expect(server.customer?['id'], 6);
          await tap(customerButton);
          await tap(find.text('Remove customer').last);
          expect(server.customer, null);
          expect(
            gateCalls,
            5,
            reason:
                'Manual discounts and customer changes have no manager gate',
          );
          // Leave all three adjustments on the paid bill: only the server
          // receipt carries them; the original local draft remains unadjusted.
          await tap(compButton);
          await tap(find.byKey(const ValueKey('comp-target-dropdown')));
          await tap(find.text('Coffee ×2').last);
          if (find.text('2 / 2').evaluate().isNotEmpty) {
            await tap(find.byKey(const ValueKey('comp-qty-decrement')));
          }
          await tap(find.text('Service').last);
          await tap(find.text(L10nEn().posCompApplyButton).last);
          await tap(customerButton);
          await search('First');
          expect(server.total, 2160);
          expect(server.customer?['id'], 5);
          expect(c.discount.isActive, false);
          expect(c.appliedComp, null);
          expect(c.selectedCustomer, null);
        }
        if (mode == 'shared') {
          final screen = tester.widget<DineInScreen>(find.byType(DineInScreen));
          unawaited(screen.onPay(server.uuid!));
          await pumpUntilRealCondition(
            tester,
            () =>
                find.byType(QrCheckoutBoundary).evaluate().isNotEmpty &&
                tester
                    .widget<QrCheckoutBoundary>(find.byType(QrCheckoutBoundary))
                    .controller
                    .ready,
            reason: 'checkout claim and snapshot ready',
          );
          final boundary = tester.widget<QrCheckoutBoundary>(
            find.byType(QrCheckoutBoundary),
          );
          final checkout = boundary.controller;
          expect(checkout.ready, true, reason: checkout.notice);
          expect(checkout.total, 2160);
          await drive(
            () => checkout.pay([CheckoutTender('cash', checkout.total)]),
          );
          await pumpUntilRealCondition(
            tester,
            () => checkout.phase == CheckoutPhase.paid,
            reason: 'paid journal completed',
          );
          expect(checkout.phase, CheckoutPhase.paid, reason: checkout.notice);
          boards.add(
            RemoteTableSnapshot(
              tables: {
                1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
              },
            ),
          );
          await tap(find.byKey(const ValueKey('qr-checkout-exit')));
          await pumpUntilRealCondition(
            tester,
            () async => (await localDb.query('dining_tables')).isEmpty,
            reason: 'closed copy archived',
          );
          expect(
            await drive(() => localDb.query('dining_tables')),
            isEmpty,
            reason:
                'active=${c.activeDiningTableId};cart=${c.cart.length};screen=${find.byType(DineInScreen).evaluate().length};text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join('|')}',
          );
          expect(
            await drive(() => localDb.query('draft_recovery_closed_archive')),
            hasLength(1),
          );
          final receipts = await drive(() => localDb.query('order_history'));
          expect(receipts, hasLength(1));
          expect(
            receipts!.single['snapshot_json'],
            contains('"serverReceiptConfirmed":true'),
          );
          expect(
            server.events.where((e) => e['event_type'] == 'order.pay'),
            hasLength(1),
          );
          expect(
            server.events.where(
              (e) => e['event_type'] == 'table.session.round',
            ),
            hasLength(1),
          );
          expect(
            server.events.where((e) => e['event_type'] == 'order.void'),
            isEmpty,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          return;
        }
        if (gps) {
          final realContext = coordinator.paymentContext!;
          coordinator.paymentContext = (snapshot) async {
            final context = await realContext(snapshot);
            return TablePaymentContext(
              lat: 23.588,
              lng: 58.3829,
              cardCharge: context.cardCharge,
              eventId: context.eventId,
              prepareEvent: context.prepareEvent,
            );
          };
        }
        c.selectPaymentMethod('Cash');
        var done = false;
        await drive(() async {
          unawaited(
            c.payAndPrint(cashTenderedAmount: 20).then((_) => done = true),
          );
        });
        await pumpUntilRealCondition(
          tester,
          () => done,
          reason: 'real payment completed',
        );
        expect(done, true);
        expect(c.cart, isEmpty, reason: c.lastPaymentMessage);
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
        expect(receiptRows.single['snapshot_json'], contains('TEST-T65-120'));
        final payRow = await drive(() => outbox.rowForKey(server.uuid!));
        expect(payRow!.syncedAt, isNotNull);
        if (gps) {
          final payload =
              server.events.singleWhere(
                    (e) => e['event_type'] == 'order.pay',
                  )['payload']
                  as Map;
          expect(payload['gps'], {'lat': 23.588, 'lng': 58.3829});
          expect(
            (payload['payments'] as List).single['amount_baisas'],
            mode == 'unadjusted' ? 5400 : 2160,
          );
          final rows = await drive(() async {
            final journal = await SqliteCheckoutStore.open('inspection');
            return journal.db.query('qr_checkout_attempts');
          });
          expect(rows!.single['state'], 'paid');
        }
        if (restart) {
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
        await pumpUntilRealCondition(
          tester,
          () async => (await localDb.query('dining_tables')).isEmpty,
          reason: 'real I/O condition before assertions',
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
        expect(await drive(() => localDb.query('order_history')), receiptRows);
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
        if (parkedWaste) {
          final rows = await drive(outbox.stuckBatches);
          expect(rows, hasLength(1));
          expect(rows!.single.eventsJson, contains('product.waste'));
        }
        expect(
          (currentHost.controller as PosController).diningSessionFor('1'),
          isNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
