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
class AckServer {
  bool paid = false;
  int reward = 0;
  bool pinAccepted = true;
  int pinCalls = 0;
  bool shared = false;
  bool claimed = false;
  int manual = 0, comp = 0;
  Map<String, dynamic>? customer;
  Future<List<CustomerSearchResult>> searchCustomers(String query) async => [
    CustomerSearchResult(
      id: query == 'Second' ? 6 : 5,
      name: query,
      phone: '90000000',
    ),
  ];
  Future<List<Map<String, dynamic>>> checkoutPush(Map<String, dynamic> e) =>
      PosApiService(tokenGetter: () => 'fixture', dio: dio()).checkoutPush(e);
  int get total => 5400 - manual - comp - reward;
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
  Future<Map<String, dynamic>> checkoutClaim(
    Map<String, dynamic> payload,
  ) async {
    expectSync(payload['order_uuid'], uuid);
    final replay = claimed;
    claimed = true;
    claimedAt ??= DateTime.now();
    return {...claim, 'already_claimed_by_this_device': replay};
  }

  Future<Map<String, dynamic>> checkoutRead(String id) async => {
    'order': (await dineInDetail(1))['bill'],
    'claim': claim,
    'customer': customer,
  };
  Future<void> checkoutRelease(Map<String, dynamic> payload) async {
    claimed = false;
  }

  Future<void> cancelQuickReservation(Map<String, dynamic> payload) async {
    claimed = false;
  }

  Future<Map<String, dynamic>> dineInAdjust(
    String id,
    Map<String, dynamic> p,
  ) async {
    try {
      final journal = await SqliteDineInStore.open('inspection');
      final saved = (await journal.db.query('dine_in_requests')).single;
      expectSync(saved['request_id'], p['client_request_id']);
      expectSync(jsonDecode(saved['payload'] as String), p);
    } catch (e) {
      journalFault = e;
      rethrow;
    }
    adjustments.add(p);
    final a = Map<String, dynamic>.from(p['adjustment'] as Map);
    switch (a['kind']) {
      case 'loyalty':
        reward = a['mode'] == 'clear' ? 0 : (a['blocks'] as int) * 500;
      case 'discount':
        manual = a['mode'] == 'clear'
            ? 0
            : a['mode'] == 'fixed'
            ? a['amount_baisas'] as int
            : a['mode'] == 'rule'
            ? 270
            : (5400 * (a['percent_bp'] as int) / 10000).round();
      case 'comp':
        expectSync(
          a['mode'] == 'clear' || a['authorized_by'] == 'Manager',
          true,
        );
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
        onRequest: (o, h) async {
          dynamic value;
          if (o.path.endsWith('/detail')) {
            value = await dineInDetail(1);
          } else if (o.path.endsWith('/customers/search')) {
            value = {
              'customers': [
                {
                  'id': 5,
                  'name': 'Customer',
                  'phone': '90000000',
                  'loyalty': [
                    {
                      'rule_id': 11,
                      'points': 200,
                      'stamps': 0,
                      'available_points': 200,
                      'available_stamps': 0,
                    },
                  ],
                },
              ],
            };
          } else if (o.path.endsWith('/customers/5')) {
            value = {
              'customer': {
                'id': 5,
                'name': 'Customer',
                'phone': '90000000',
                'loyalty': [
                  {
                    'rule_id': 11,
                    'points': 1000,
                    'stamps': 0,
                    'available_points': 200,
                    'available_stamps': 0,
                  },
                ],
              },
            };
          } else if (o.path.endsWith('/verify-manager-pin')) {
            pinCalls++;
            value = {
              'ok': pinAccepted,
              'staff': {'id': 19, 'name': 'Verified Approver'},
            };
          } else if (o.path.endsWith('/adjust')) {
            value = await dineInAdjust(
              seat,
              Map<String, dynamic>.from(o.data as Map),
            );
          } else if (o.path.endsWith('/claim-settlement')) {
            value = await checkoutClaim(
              Map<String, dynamic>.from(o.data as Map),
            );
          } else if (o.path.endsWith('/checkout')) {
            value = await checkoutRead(uuid!);
          } else if (o.path.endsWith('/orders/history')) {
            value = {
              'orders': paid ? [await closedTableBill(uuid!, 1)] : [],
            };
          } else if (o.path.endsWith('/incoming')) {
            value = {'transfers': []};
          }
          if (value != null) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {'data': value},
              ),
            );
            return;
          }

          if (o.data is! Map || !(o.data as Map).containsKey('events')) {
            h.resolve(
              Response(requestOptions: o, statusCode: 200, data: {'data': {}}),
            );
            return;
          }
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
              expectSync(claimed, true);
              expectSync(
                (e['payload'] as Map).containsKey('loyalty_redeem'),
                false,
              );
              final payments = (e['payload'] as Map)['payments'] as List;
              expectSync(
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
                  'receipt_number': 'TEST-T12-120',
                  'loyalty_earned': {'points': 44, 'stamps': 1},
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

  String Function() get tokenGetter =>
      () => 'fixture';
  String get quickOrderBaseUrl => 'http://fixture.invalid/api/v1';
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];
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
            'discount_total_baisas': manual + reward,
            'manual_discount_baisas': manual,
            'comp_total_baisas': comp,
            'tax_total_baisas': 0,
            'grand_total_baisas': total,
            'customer': customer,
            'adjustment_state': {
              'loyalty': reward == 0
                  ? null
                  : {'rule_id': 11, 'amount_baisas': reward, 'name': 'Points'},
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
  final db = await databaseFactoryFfi.openDatabase(
    '${await databaseFactoryFfi.getDatabasesPath()}/t12-local.sqlite',
  );
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

void runPaymentRegression({
  bool gps = false,
  bool parkedWaste = false,
  bool staleCounter = false,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final mode in [
    'staff',
    if (!staleCounter) 'counter-points',
    if (!staleCounter) 'counter-stamps',
    if (!parkedWaste) 'shared',
    if (!parkedWaste && !staleCounter) 'already-stuck',
    if (gps) 'unadjusted',
  ]) {
    final restart = mode == 'already-stuck';
    testWidgets(
      'T12 real screen ${staleCounter ? 'stale counter ' : ''}${parkedWaste ? 'parked waste ' : ''}${gps ? 'GPS ' : ''}$mode payment ${staleCounter ? 'checks live debit suppression' : 'journals canonical amount and retires own acknowledged copy'}',
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
          if (!staleCounter &&
              find.byType(Dialog).evaluate().isEmpty &&
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
        final server = AckServer()
          ..shared = mode == 'shared'
          ..customer = {'id': 5, 'name': 'Customer', 'phone': '90000000'};
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        late Directory auxiliary;
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          auxiliary = await Directory.systemTemp.createTemp('fix7-ack-');
          await databaseFactory.setDatabasesPath(auxiliary.path);
          localDb = await realLocalDatabase();
          storage = LocalOrderStorageService.forTesting(localDb);
          await storage.refreshRecoveryGuard();
          driftDb = AppDatabase.forTesting(
            NativeDatabase(File('${auxiliary.path}/drift.sqlite')),
          );
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
            expectSync(await outbox.stuckBatches(), hasLength(1));
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
            api: PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
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
        c.loyaltyRules = const [
          LoyaltyRule(
            id: 11,
            name: 'Points',
            type: 'spend_based',
            config: {'redemption_points': 100, 'redemption_value': '0.500'},
          ),
        ];
        c.compReasons = const [
          CompReasonRef(id: 1, code: 'service', name: 'Service', maxAmount: 3),
        ];
        c.printReceipts = false;
        c.printKitchenTickets = false;
        if (mode.startsWith('counter-')) {
          await drive(() async {
            c.addProduct(product);
            c.addProduct(product);
          });
          c.attachCustomer(
            CustomerSearchResult.fromJson({
              'id': 5,
              'name': 'Customer',
              'phone': '90000000',
              'loyalty': [
                {
                  'rule_id': 11,
                  'points': 1000,
                  'stamps': 10,
                  'available_points': 200,
                  'available_stamps': 0,
                },
              ],
            }),
          );
          if (mode == 'counter-stamps') {
            c.loyaltyRules = const [
              LoyaltyRule(
                id: 11,
                name: 'Stamps',
                type: 'visit_based',
                config: {
                  'stamps_required': 1,
                  'reward_type': 'fixed',
                  'reward_value': 1,
                },
              ),
            ];
          }
          await settle(8);

          await tap(find.text('Process to Pay').first);

          await tap(find.text('Add Discount').first);

          if (mode == 'counter-stamps') {
            expectSync(find.text('Redeem stamp reward'), findsNothing);
            expectSync(find.text('Redeem loyalty points'), findsNothing);
          } else {
            await tap(find.text('Redeem loyalty points'));
            final plus = find.widgetWithIcon(
              IconButton,
              Icons.add_circle_outline,
            );
            await tap(plus);
            expectSync(tester.widget<IconButton>(plus).onPressed, isNull);
            expectSync(find.textContaining('200 points  →'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          return;
        }
        if (staleCounter) {
          // ignore: avoid_print
          print('GUARD $mode quick cart start');
          c.addProduct(product);
          c.addProduct(product);
          await tap(find.text('Process to Pay').first);
          await tap(find.byTooltip('Search customer'));
          await tester.enterText(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byType(TextField),
            ),
            '90000000',
          );
          await tap(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.widgetWithText(FilledButton, 'Search'),
            ),
          );
          await tap(find.text('Customer').last);
          // ignore: avoid_print
          print('GUARD $mode payment opened');
          await tap(find.text('Add Discount').first);
          await tap(find.text('Redeem loyalty points'));
          await tap(find.widgetWithText(FilledButton, 'Redeem'));
          expectSync(c.loyaltyRedeemRuleId, 11);
          expectSync(c.loyaltyRedeemPoints, 100);
          // ignore: avoid_print
          print('GUARD $mode counter reward applied');
          await tap(find.byIcon(Icons.arrow_back_rounded).first);
          await tap(find.text('Dine In').first);
          await tap(find.text('Table 1').first);
          await pumpUntilRealCondition(
            tester,
            () => c.activeDiningTableId == '1' && !c.tableTransitionInProgress,
            reason: 'selected table identity and transition are ready',
          );
          // ignore: avoid_print
          print('GUARD $mode table cart reused');
          expectSync(c.activeDiningTableId, '1');
          expectSync(
            c.loyaltyRedeemRuleId,
            11,
            reason: 'real quick-cart reward survives the UI table reuse',
          );
          expectSync(c.loyaltyRedeemPoints, 100);
        } else {
          await drive(() async {
            await storage.refreshRecoveryGuard();
            expectSync(c.diningTableDefinitions, isNotEmpty);
            await c.openDiningTable('1');
            expectSync(
              c.activeDiningTableId,
              '1',
              reason: c.lastPaymentMessage,
            );
            c.addProduct(product);
            c.addProduct(product);
          });
        }
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
          expectSync(
            find.textContaining('Stock waste could not sync.'),
            findsOneWidget,
          );
          expectSync(
            find.textContaining('Stuck sales to review and retry'),
            findsOneWidget,
          );
          expectSync(
            find.byKey(const ValueKey('table-sync-attention-banner')),
            findsNothing,
          );
          expectSync(
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
        expectSync(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
        );
        final before = await drive(() => localDb.query('dining_tables'));
        expectSync(before!.single['seating_state'], 'open');
        expectSync(before.single['seating_uuid'], seat);
        // Actual fresh-open path leaves controller identity behind the persisted
        // coordinator ACK. A bound pre-seeded fixture would hide the proof gate.
        expectSync(c.diningSessionFor('1')!.seatingUuid, isNull);

        if (!staleCounter) {
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
          expectSync(
            c.discount.isActive,
            false,
            reason: 'Live rounds already own automatic discounts',
          );
          c.availableDiscounts = [];
        }
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
          expectSync(find.byType(DineInScreen), findsOneWidget);
        }
        await pumpUntilRealCondition(tester, () {
          final control = find.byKey(const ValueKey('table-adjust-discount'));
          return control.evaluate().isNotEmpty &&
              tester.widget<TextButton>(control).onPressed != null;
        }, reason: 'table detail, sent-line proof and journal ready');
        if (!staleCounter && mode != 'unadjusted') {
          final redeem = find.byKey(const ValueKey('table-adjust-loyalty'));
          expectSync(redeem, findsOneWidget);
          await pumpUntilRealCondition(
            tester,
            () =>
                redeem.evaluate().isNotEmpty &&
                tester.widget<TextButton>(redeem).onPressed != null,
            reason: 'loyalty table entry',
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('manager_biometric_registered', true);
          Future<void> picker() async {
            await tap(redeem);
            await pumpUntilRealCondition(
              tester,
              () => find
                  .byKey(const ValueKey('table-loyalty-picker'))
                  .evaluate()
                  .isNotEmpty,
              reason: 'whole block picker',
            );
            await tap(find.byKey(const ValueKey('table-loyalty-plus')));
            expectSync(
              find.text('Redeem 200 points for OMR 1.000'),
              findsOneWidget,
            );
            expectSync(
              tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('table-loyalty-plus')),
                  )
                  .onPressed,
              isNull,
            );
            await tap(find.byKey(const ValueKey('table-loyalty-apply')));
            await pumpUntilRealCondition(
              tester,
              () =>
                  find.text(L10nEn().posManagerPinTitle).evaluate().isNotEmpty,
              reason: 'fingerprint without staff id falls through to real PIN',
            );
          }

          Future<void> pin() async {
            for (final digit in ['1', '2', '3', '4']) {
              await tap(
                find
                    .descendant(
                      of: find.byType(Dialog),
                      matching: find.text(digit),
                    )
                    .last,
              );
            }
            await tap(find.text(L10nEn().posManagerPinVerify).last);
          }

          await picker();
          await tap(find.text(L10nEn().commonCancel).last);
          expectSync(server.adjustments, isEmpty);
          final journalRows = await drive(
            () async => (await SqliteDineInStore.open(
              'inspection',
            )).db.query('dine_in_requests'),
          );
          expectSync(journalRows, isEmpty);
          await picker();
          server.pinAccepted = false;
          await pin();
          expectSync(server.adjustments, isEmpty);
          await tap(find.text(L10nEn().commonCancel).last);
          server.pinAccepted = true;
          await picker();
          await pin();
          await pumpUntilRealCondition(
            tester,
            () => server.reward == 1000,
            reason: 'real adjustment applied',
          );
          expectSync(server.adjustments.single['adjustment'], {
            'kind': 'loyalty',
            'mode': 'redeem',
            'rule_id': 11,
            'blocks': 2,
            'authorized_by': 'Verified Approver',
            'approved_by_staff_id': 19,
          });
          expectSync(c.loyaltyRedeemRuleId, isNull);
          await pumpUntilRealCondition(
            tester,
            () => find
                .byKey(const ValueKey('table-loyalty-line'))
                .evaluate()
                .isNotEmpty,
            reason: 'server redemption displayed',
          );
          await tap(redeem);
          await tap(find.byKey(const ValueKey('table-loyalty-clear')));
          await pumpUntilRealCondition(
            tester,
            () => server.reward == 0,
            reason: 'clear acknowledged',
          );
          expectSync(server.adjustments.last['adjustment'], {
            'kind': 'loyalty',
            'mode': 'clear',
          });
          await picker();
          await pin();
          await pumpUntilRealCondition(
            tester,
            () => server.adjustments.length == 3,
            reason: 'new redemption saved',
          );
          expectSync(server.reward, 1000);
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
          expectSync(checkout.ready, true, reason: checkout.notice);
          expectSync(checkout.total, staleCounter ? 5400 : 4400);
          await drive(
            () => checkout.pay([CheckoutTender('cash', checkout.total)]),
          );
          await pumpUntilRealCondition(
            tester,
            () => checkout.phase == CheckoutPhase.paid,
            reason: 'paid journal completed',
          );
          expectSync(
            checkout.phase,
            CheckoutPhase.paid,
            reason: checkout.notice,
          );
          if (staleCounter) {
            final rows = await drive(
              () async => (await SqliteCheckoutStore.open(
                'inspection',
              )).db.query('qr_checkout_attempts'),
            );
            expectSync(rows, hasLength(1));
            expectSync(jsonEncode(rows), isNot(contains('loyalty_redeem')));
            final driftRows = await drive(
              () => driftDb.select(driftDb.orderOutbox).get(),
            );
            expectSync(
              driftRows!.every(
                (row) => !row.eventsJson.contains('loyalty_redeem'),
              ),
              true,
            );
            // ignore: avoid_print
            print(
              'F36 LIVE shared: checkout journal and drift rows contain no device redemption; pushed pay=${jsonEncode(server.events.where((e) => e['event_type'] == 'order.pay').toList())}',
            );
          }

          await tester.pump();
          expectSync(
            find.text('You earned 44 points · You earned 1 stamps'),
            findsOneWidget,
          );
          if (staleCounter) {
            expectSync(
              server.events.where((e) => e['event_type'] == 'order.pay'),
              hasLength(1),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 1));
            return;
          }
          boards.add(
            RemoteTableSnapshot(
              tables: {
                1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
              },
            ),
          );
          await tap(find.byKey(const ValueKey('qr-checkout-exit')));
          await pumpUntilRealCondition(tester, () async {
            final rows = await localDb.query('dining_tables');
            if (find.byType(StaffPosScreen).evaluate().isEmpty) return false;
            final dynamic current = tester.state(find.byType(StaffPosScreen));
            return rows.isEmpty &&
                (current.controller as PosController).diningSessionFor('1') ==
                    null;
          }, reason: 'closed copy archived');
          expectSync(
            await drive(() => localDb.query('dining_tables')),
            isEmpty,
            reason:
                'active=${c.activeDiningTableId};cart=${c.cart.length};screen=${find.byType(DineInScreen).evaluate().length};text=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join('|')}',
          );
          expectSync(
            await drive(() => localDb.query('draft_recovery_closed_archive')),
            hasLength(1),
          );
          final receipts = await drive(() => localDb.query('order_history'));
          expectSync(receipts, hasLength(1));
          expectSync(
            receipts!.single['snapshot_json'],
            contains('"serverReceiptConfirmed":true'),
          );
          expectSync(
            server.events.where((e) => e['event_type'] == 'order.pay'),
            hasLength(1),
          );
          expectSync(
            server.events.where(
              (e) => e['event_type'] == 'table.session.round',
            ),
            hasLength(1),
          );
          expectSync(
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
            c.payAndPrint(cashTenderedAmount: 20).then((message) {
              // ignore: avoid_print
              print(
                'T12 PAYMENT $mode stale=$staleCounter message=$message status=${c.paymentStatus} events=${server.events.map((e) => e['event_type']).toList()}',
              );
              done = true;
            }),
          );
        });
        await pumpUntilRealCondition(
          tester,
          () =>
              done &&
              find
                  .text('You earned 44 points · You earned 1 stamps')
                  .evaluate()
                  .isNotEmpty,
          reason: 'real payment and earned notice completed',
        );
        expectSync(done, true);
        expectSync(
          find.text('You earned 44 points · You earned 1 stamps'),
          findsOneWidget,
        );
        expectSync(c.cart, isEmpty, reason: c.lastPaymentMessage);
        expectSync(c.activeDiningTableId, isNull);
        final closed = await drive(() => localDb.query('dining_tables'));
        expectSync(
          closed!.single['seating_state'],
          'closed',
          reason: 'Real coordinator pay ACK must persist the failing state',
        );
        expectSync(closed.single['server_order_uuid'], server.uuid);
        final receiptRows = await drive(() => localDb.query('order_history'));
        expectSync(receiptRows, hasLength(1));
        expectSync(
          receiptRows!.single['snapshot_json'],
          contains('"serverReceiptConfirmed":true'),
        );
        expectSync(
          receiptRows.single['snapshot_json'],
          contains('TEST-T12-120'),
        );
        final payRow = await drive(() => outbox.rowForKey(server.uuid!));
        expectSync(payRow!.syncedAt, isNotNull);
        if (staleCounter) {
          final events = (jsonDecode(payRow.eventsJson) as List).cast<Map>();
          final pay = events.singleWhere((e) => e['event_type'] == 'order.pay');
          expectSync(
            (pay['payload'] as Map).containsKey('loyalty_redeem'),
            false,
          );
          expectSync(
            server.events.where((e) => e['event_type'] == 'order.pay'),
            hasLength(1),
          );
          // ignore: avoid_print
          print(
            'F36 LIVE staff: durable=${jsonEncode(pay)} pushed=${jsonEncode(server.events.where((e) => e['event_type'] == 'order.pay').toList())}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          return;
        }

        if (gps) {
          final payload =
              server.events.singleWhere(
                    (e) => e['event_type'] == 'order.pay',
                  )['payload']
                  as Map;
          expectSync(payload['gps'], {'lat': 23.588, 'lng': 58.3829});
          expectSync(
            (payload['payments'] as List).single['amount_baisas'],
            mode == 'unadjusted' ? 5400 : 4400,
          );
          final rows = await drive(() async {
            final journal = await SqliteCheckoutStore.open('inspection');
            return journal.db.query('qr_checkout_attempts');
          });
          expectSync(rows!.single['state'], 'paid');
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
        await pumpUntilRealCondition(tester, () async {
          final rows = await localDb.query('dining_tables');
          if (find.byType(StaffPosScreen).evaluate().isEmpty) return false;
          final dynamic current = tester.state(find.byType(StaffPosScreen));
          return rows.isEmpty &&
              (current.controller as PosController).diningSessionFor('1') ==
                  null;
        }, reason: 'real I/O condition before assertions');
        expectSync(
          await drive(() => localDb.query('dining_tables')),
          isEmpty,
          reason:
              'Own acknowledged staff-only pay must automatically free the table',
        );
        final archives = await drive(
          () => localDb.query('draft_recovery_closed_archive'),
        );
        expectSync(archives, hasLength(1));
        final archive =
            jsonDecode(archives!.single['local_json'] as String) as Map;
        expectSync((archive['rows'] as List).single['row'], closed.single);
        expectSync(
          await drive(() => localDb.query('order_history')),
          receiptRows,
        );
        expectSync(
          server.events.where((e) => e['event_type'] == 'order.pay'),
          hasLength(1),
        );
        expectSync(
          server.events.where((e) => e['event_type'] == 'order.void'),
          isEmpty,
        );
        expectSync(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
        );
        final dynamic currentHost = tester.state(find.byType(StaffPosScreen));
        if (parkedWaste) {
          final rows = await drive(outbox.stuckBatches);
          expectSync(rows, hasLength(1));
          expectSync(rows!.single.eventsJson, contains('product.waste'));
        }
        expectSync(
          (currentHost.controller as PosController).diningSessionFor('1'),
          isNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
