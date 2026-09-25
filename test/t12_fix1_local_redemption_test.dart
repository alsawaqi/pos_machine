import 'dart:async';
import 'dart:convert';
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
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';

// Digits-only fixture phone avoids the separate, deferred P-1 identity defect.
const product = Product(
  id: '10',
  name: 'Coffee',
  category: 'Drinks',
  price: 2.7,
);

class TesterServer {
  final requests = <String>[];
  final events = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> searchResult = const [];
  int createdCustomerId = 902;

  Dio dio() {
    final d = Dio();
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          requests.add(
            '${o.method} ${o.path} ${o.queryParameters.isEmpty ? '' : jsonEncode(o.queryParameters)} '
            '${o.data is Map && !(o.data as Map).containsKey('events') ? jsonEncode(o.data) : ''}',
          );
          dynamic value;
          if (o.path.endsWith('/device/customers/search')) {
            value = {'customers': searchResult};
          } else if (o.method == 'POST' &&
              o.path.endsWith('/device/customers')) {
            value = {
              'customer': {
                'id': createdCustomerId,
                'name': (o.data as Map)['name'],
                'phone': (o.data as Map)['phone'],
              },
            };
          } else if (o.path.contains('/tables')) {
            value = {'tables': [], 'sessions': []};
          } else if (o.path.endsWith('/incoming')) {
            value = {'transfers': []};
          }
          if (value == null &&
              o.data is Map &&
              (o.data as Map).containsKey('events')) {
            final results = <Map<String, dynamic>>[];
            for (final raw in ((o.data as Map)['events'] as List).cast<Map>()) {
              final e = Map<String, dynamic>.from(raw);
              events.add(e);
              final uuid = (e['payload'] as Map)['order_uuid'];
              results.add({
                'client_event_id': e['client_event_id'],
                'status': 'processed',
                'result': {
                  'order_uuid': uuid,
                  if (e['event_type'] == 'order.pay') ...{
                    'status': 'paid',
                    'order_id': 65,
                    'receipt_number': 'TESTER-F36-1',
                  },
                },
              });
            }
            value = {'results': results};
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {'data': value ?? {}},
            ),
          );
        },
      ),
    );
    return d;
  }
}

Future<Database> realLocalDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(
    '${await databaseFactoryFfi.getDatabasesPath()}/tester-local.sqlite',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final scenario in [
    'off-points',
    'shadow-points',
    'off-stamps',
    'hold',
    'reopen',
    'legacy-held',
    'legacy-table',
  ]) {
    final mode = scenario.startsWith('shadow') ? 'shadow' : 'off';
    final held = scenario == 'hold' || scenario == 'legacy-held';
    final legacy = scenario.startsWith('legacy');
    final stamps = scenario == 'off-stamps' || scenario == 'legacy-table';
    testWidgets(
      'T12 fix1 F36 P2 $scenario real screen cash carries debit or clears unsafe legacy discount',
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
            reason: 'real operation completed',
          );
          if (error != null) Error.throwWithStackTrace(error!, trace!);
          return value;
        }

        Future<void> settle([int frames = 10]) async {
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await drive(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
          }
        }

        Future<void> tap(Finder target, String what) async {
          await pumpUntilRealCondition(tester, () {
            try {
              return target.hitTestable().evaluate().isNotEmpty;
            } on StateError {
              return false;
            }
          }, reason: 'control "$what" visible and hit-testable');
          await tester.tap(target.hitTestable().first);
          await settle(6);
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

        final server = TesterServer()
          ..searchResult = [
            {
              'id': 5,
              'name': 'Loyal Customer',
              'phone': '90000000',
              'loyalty': [
                {
                  'rule_id': 11,
                  'points': 200,
                  'stamps': 5,
                  'available_points': 200,
                  'available_stamps': 5,
                },
              ],
            },
          ]
          ..createdCustomerId =
              5; // digits-only phone: find-or-create would match the same customer
        late Database localDb;
        late AppDatabase driftDb;
        late LocalOrderStorageService storage;
        late OrderSyncRepository outbox;
        late TableSyncCoordinator coordinator;
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          final aux = await Directory.systemTemp.createTemp('tester-f36-');
          await databaseFactory.setDatabasesPath(aux.path);
          localDb = await realLocalDatabase();
          storage = LocalOrderStorageService.forTesting(localDb);
          await storage.refreshRecoveryGuard();
          driftDb = AppDatabase.forTesting(
            NativeDatabase(File('${aux.path}/drift.sqlite')),
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
            mode: () => mode,
            degraded: () => false,
            staffId: () => 7,
            markPrinted: (_) async {},
          );
        });
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

        await pumpWorkspaceMachine(
          tester,
          mode: mode,
          toggle: false,
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
        final dynamic host = tester.state(find.byType(StaffPosScreen));
        final PosController c = host.controller;
        await pumpUntilRealCondition(
          tester,
          () => !c.isLoadingStorage,
          reason: 'storage loaded',
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
        c.loyaltyRules = [
          if (stamps)
            const LoyaltyRule(
              id: 11,
              name: 'Stamps',
              type: 'visit_based',
              config: {
                'stamps_required': 5,
                'reward_type': 'fixed',
                'reward_value': '0.500',
              },
            )
          else
            const LoyaltyRule(
              id: 11,
              name: 'Points',
              type: 'spend_based',
              config: {'redemption_points': 100, 'redemption_value': '0.500'},
            ),
        ];
        c.printReceipts = false;
        c.printKitchenTickets = false;
        if (!held) {
          await tap(find.text('Dine In').first, 'Dine In');
          await tap(find.text('Table 1').first, 'Table 1');
        }
        await drive(() async {
          c.addProduct(product);
          c.addProduct(product);
        });
        await settle(8);
        // ignore: avoid_print
        print(
          'TESTER_STATE before pay page: orderType=${c.selectedOrderType.storageValue} '
          'activeTable=${c.activeDiningTableId} cart=${c.cart.length} lastMsg="${c.lastPaymentMessage}"',
        );
        expect(
          c.selectedOrderType,
          held ? OrderType.quickOrder : OrderType.dineIn,
        );
        expect(c.activeDiningTableId, held ? null : '1');

        await tap(find.text('Process to Pay'), 'Process to Pay');
        // Real customer search dialog on the payment page.
        await tap(find.byTooltip('Search customer'), 'Search customer');
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
          'Search',
        );
        await tap(find.text('Loyal Customer'), 'customer result');
        // ignore: avoid_print
        print(
          'TESTER_STATE after attach: selectedCustomer=${c.selectedCustomer?.id} ref=${c.customerReferenceNumber}',
        );

        await tap(find.text('Add Discount'), 'Add Discount');
        expect(
          find.text(stamps ? 'Redeem stamp reward' : 'Redeem loyalty points'),
          findsOneWidget,
          reason:
              'the discount sheet offers redemption on an off-mode dine-in table',
        );
        await tap(
          find.text(stamps ? 'Redeem stamp reward' : 'Redeem loyalty points'),
          'Redeem loyalty points',
        );
        await tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.widgetWithText(FilledButton, 'Redeem'),
          ),
          'Redeem',
        );
        // ignore: avoid_print
        print(
          'TESTER_STATE after redeem: discount=${c.discountAmount} redeemRule=${c.loyaltyRedeemRuleId} '
          'redeemPoints=${c.loyaltyRedeemPoints} total=${c.activePaymentBaseTotal}',
        );
        expect(c.loyaltyRedeemRuleId, 11);

        if (held || scenario == 'reopen' || legacy) {
          await tap(
            find.byIcon(Icons.arrow_back_rounded).first,
            'Back to current order',
          );
          if (held) {
            await tap(find.text('Hold').first, 'Hold');
            await pumpUntilRealCondition(
              tester,
              () => c.heldOrders.length == 1,
              reason: 'held draft saved',
            );
          } else {
            await tap(find.text('Back To Floor').first, 'Back To Floor');
            await pumpUntilRealCondition(
              tester,
              () => c.activeDiningTableId == null,
              reason: 'floor plan restored',
            );
          }
          if (legacy) {
            await drive(() async {
              final table = held ? 'held_orders' : 'dining_tables';
              final rows = await localDb.query(table);
              final raw =
                  jsonDecode(rows.single['draft_json'] as String)
                      as Map<String, dynamic>;
              raw.remove('loyaltyRedeemRuleId');
              raw.remove('loyaltyRedeemPoints');
              raw.remove('loyaltyRedeemStamps');
              await localDb.update(table, {'draft_json': jsonEncode(raw)});
              if (held) {
                await c.refreshHeldOrders();
              } else {
                await c.refreshDiningTables();
              }
            });
          }
          if (held) {
            // The hold popup dismisses using its real close control.
            final close = find.byIcon(Icons.close_rounded).hitTestable();
            if (close.evaluate().isNotEmpty) {
              await tap(close.first, 'Close hold notice');
            }
            await tap(find.text('Held Orders').first, 'Held Orders');
            await tap(find.text('Continue Order').first, 'Continue Order');
            await pumpUntilRealCondition(
              tester,
              () =>
                  c.cart.isNotEmpty &&
                  c.heldOrders.isEmpty &&
                  find.text('Continue Order').evaluate().isEmpty,
              reason: 'real held resume and overlay dismissal completed',
            );
          } else {
            await tap(find.text('Table 1').first, 'Reopen Table 1');
          }
          if (legacy) {
            await pumpUntilRealCondition(
              tester,
              () => find
                  .text(
                    'Saved loyalty discount removed because its redemption details are missing. Please redeem the reward again.',
                  )
                  .evaluate()
                  .isNotEmpty,
              reason: 'legacy missing-debit notice is visible',
            );
            expect(c.discountAmount, 0);
            expect(c.loyaltyRedeemRuleId, isNull);
          } else {
            expect(c.discountAmount, 0.5);
            expect(c.loyaltyRedeemRuleId, 11);
          }
          final close = find.byIcon(Icons.close_rounded).hitTestable();
          if (close.evaluate().isNotEmpty) {
            await tap(close.first, 'Close resume notice');
          }
          await tap(
            find.text('Process to Pay'),
            'Process to Pay restored order',
          );
        }
        await tap(find.text('10 OMR'), 'quick cash 10 OMR');
        final cashButton = find.ancestor(
          of: find.text('Cash'),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PaymentMethodActionButton',
          ),
        );
        await tap(cashButton, 'Cash');

        await pumpUntilRealCondition(
          tester,
          () async =>
              (await driftDb.select(driftDb.orderOutbox).get()).isNotEmpty,
          reason: 'order enqueued in the durable outbox',
        );
        await pumpUntilRealCondition(
          tester,
          () =>
              server.events
                  .where((e) => e['event_type'] == 'order.pay')
                  .length ==
              1,
          reason: 'one order.pay pushed through real outbox',
        );
        await pumpUntilRealCondition(
          tester,
          () => !c.isProcessingPayment && c.cart.isEmpty,
          reason: 'cash completion and local table writes finished',
        );
        await drive(() async {
          await coordinator.settled;
          await outbox.flush();
        });
        final rows = await drive(
          () => driftDb.select(driftDb.orderOutbox).get(),
        );
        final paidRows = rows!
            .where(
              (row) => (jsonDecode(row.eventsJson) as List).any(
                (e) => e['event_type'] == 'order.pay',
              ),
            )
            .toList();
        expect(paidRows, hasLength(1));
        final events = (jsonDecode(paidRows.single.eventsJson) as List)
            .cast<Map<String, dynamic>>();
        final create =
            events.firstWhere(
                  (e) => e['event_type'] == 'order.create',
                )['payload']
                as Map;
        final pay =
            events.firstWhere((e) => e['event_type'] == 'order.pay')['payload']
                as Map;
        final order = (create['order'] ?? create) as Map;
        // ignore: avoid_print
        print(
          'TESTER_F36 outbox events=${events.map((e) => e['event_type']).toList()} '
          'order_type=${order['order_type']} table_id=${order['table_id'] ?? create['table_id']} '
          'customer_id=${order['customer_id'] ?? create['customer_id']} '
          'discount=${order['discount_total_baisas'] ?? order['discount_baisas']} '
          'payments=${jsonEncode(pay['payments'])} loyalty_redeem=${pay['loyalty_redeem']} '
          'loyalty_rule_ids=${pay['loyalty_rule_ids']}',
        );
        // ignore: avoid_print
        print(
          'TESTER_F36 http=${server.requests.where((r) => r.contains('customers') || r.contains('sync') || r.contains('events')).toList()}',
        );
        final expected = legacy
            ? null
            : {
                'rule_id': 11,
                'points': stamps ? 0 : 100,
                'stamps': stamps ? 5 : 0,
              };
        expect(
          events.where((e) => e['event_type'] == 'order.pay'),
          hasLength(1),
        );
        if (scenario == 'hold' || scenario == 'reopen') {
          expect(order['customer_id'], 5);
        }
        expect(pay['loyalty_redeem'], expected);
        expect(order['discount_total_baisas'], legacy ? 0 : 500);
        final pushed = server.events
            .where((e) => e['event_type'] == 'order.pay')
            .toList();
        expect(pushed, hasLength(1));
        expect((pushed.single['payload'] as Map)['loyalty_redeem'], expected);
        final pushedCreate =
            server.events.singleWhere(
                  (e) => e['event_type'] == 'order.create',
                )['payload']
                as Map;
        expect(
          (pushedCreate['order'] as Map)['discount_total_baisas'],
          legacy ? 0 : 500,
        );
        // ignore: avoid_print
        print(
          'T12 FIX1 MEASURED $scenario durable=${jsonEncode(pay)} pushed=${jsonEncode(pushed.single['payload'])} discount=${order['discount_total_baisas']}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
