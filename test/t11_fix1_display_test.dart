import 'package:pos_machine/widgets/table_reconciliation_sheet.dart';
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
import 'package:pos_machine/l10n/l10n_ar.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';

import 'package:pos_machine/dine_in/dine_in_screen.dart';

const seat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const product = Product(
  id: '10',
  name: 'Coffee',
  category: 'Drinks',
  price: 0.5,
);

class CancelServer {
  String uuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  bool cancelled = false,
      lose = false,
      deny = false,
      shelf = false,
      offline = false,
      lineReserved = false,
      failDetail = false;
  String? refusal;
  int approvals = 0;
  void Function()? onCancelled;
  final calls = <String>[],
      cancellations = <Map<String, dynamic>>[],
      events = <Map<String, dynamic>>[];
  final applied = <String>{};
  late LocalOrderStorageService storage;
  Map<String, dynamic> detail() => {
    'table': {'id': 1, 'label': 'Table 1'},
    'occupied': !cancelled,
    'orphaned': false,
    'seating': cancelled
        ? null
        : {
            'uuid': seat,
            'table_id': 1,
            'status': 'open',
            'joined_table_ids': [],
          },
    'bill': cancelled
        ? null
        : {
            'uuid': uuid,
            'status': 'open',
            'order_type': 'dine_in',
            'table_id': 1,
            'charge': 'none',
            'grand_total_baisas': 1000,
            'pending_rounds': 0,
            'items': [],
            'temp_reference': 'T-T11',
          },
    'rounds': cancelled
        ? []
        : [
            {
              'id': 1,
              'round_no': 1,
              'status': 'accepted',
              'entered_by': 'staff',
              'kitchen_printed_at': '2026-09-21T10:00:00Z',
              'priced_lines': [
                {
                  'product_id': 10,
                  'product_name': 'Coffee',
                  'qty': 2,
                  'cancelled_qty': 0,
                  'unit_price_baisas': 500,
                  'line_total_baisas': 1000,
                  'addons': [],
                  'notes': null,
                  'order_item_id': 1,
                  'line_index': 0,
                },
              ],
            },
          ],
  };
  Dio dio() {
    final d = Dio(BaseOptions(baseUrl: 'http://t11.invalid/api/v1'));
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          calls.add(o.path);
          if (offline || (failDetail && o.path.endsWith('/detail'))) {
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.connectionError,
              ),
            );
            return;
          }
          dynamic data;
          if (o.path.endsWith('/detail')) {
            data = detail();
          } else if (o.path.endsWith('/verify-manager-pin')) {
            approvals++;
            data = {
              'ok': !deny,
              'staff': {'name': 'Test Manager'},
            };
            h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
            return;
          } else if (o.path.endsWith('/cancel-bill')) {
            final p = Map<String, dynamic>.from(o.data as Map);
            cancellations.add(jsonDecode(jsonEncode(p)));
            final journal = await storage.readTableSyncVerdicts(limit: 1000000);
            expectSync(
              journal.any(
                (v) =>
                    v.eventKind == 'cancel_bill_intent' &&
                    jsonEncode(v.detail['event']['payload']) == jsonEncode(p),
              ),
              isTrue,
            );
            if (refusal != null) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: o,
                    statusCode: 409,
                    data: {
                      'errors': [
                        {'code': refusal, 'message': 'Synthetic refusal'},
                      ],
                    },
                  ),
                ),
              );
              return;
            }
            final replay = !applied.add(p['client_request_id']);
            cancelled = true;
            onCancelled?.call();
            data = {
              'outcome': replay ? 'replayed' : 'cancelled',
              'client_request_id': p['client_request_id'],
              'table_id': 1,
              'seating_key': p['seating_key'],
              'table_session_uuid': seat,
              'order_uuid': uuid,
              'needs_review': false,
              'status': 'void',
              'grand_total_baisas': 0,
              'lines': [
                for (final l in p['lines'])
                  {
                    'client_request_id': l['client_request_id'],
                    'cancelled_qty': l['qty'],
                    'unlinked_line_count': 0,
                    'waste': {
                      'booked': l['prepared'] == true && !shelf,
                      'cost_baisas': l['prepared'] ? 123 : 0,
                      'ingredients': [],
                    },
                  },
              ],
            };
            if (lose) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
          } else if (o.path.endsWith('/sync/push')) {
            final list = (o.data['events'] as List).cast<Map>();
            final results = <Map<String, dynamic>>[];
            for (final raw in list) {
              final e = Map<String, dynamic>.from(raw),
                  p = Map<String, dynamic>.from(raw['payload'] as Map);
              events.add(e);
              if (lineReserved &&
                  e['event_type'] == 'table.session.cancel_line') {
                results.add({
                  'client_event_id': e['client_event_id'],
                  'status': 'failed',
                  'result': {
                    'refusal_code': 'bill_reserved',
                    'error': 'Synthetic reservation',
                  },
                });
                continue;
              }
              if (p['order_uuid'] is String) uuid = p['order_uuid'];
              results.add({
                'client_event_id': e['client_event_id'],
                'status': 'processed',
                'result': {
                  'order_uuid': uuid,
                  'table_session_uuid': seat,
                  'temp_reference': 'T-T11',
                  'needs_review': false,
                  'table_id': 1,
                  'seating_key': p['seating_key'],
                  'outcome': e['event_type'] == 'table.session.open'
                      ? 'opened'
                      : 'appended',
                  if (e['event_type'] == 'table.session.round') ...{
                    'round_id': 1,
                    'round_no': 1,
                  },
                  if (e['event_type'] == 'product.waste') ...{
                    'wasted_lines': 1,
                    'total_qty': '${p['lines'][0]['qty']}.000',
                  },
                },
              });
            }
            data = {'results': results};
          } else if (o.path.endsWith('/orders/history')) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'data': {
                    'orders': [
                      {
                        'uuid': uuid,
                        'table_id': 1,
                        'order_type': 'dine_in',
                        'status': cancelled ? 'void' : 'open',
                      },
                    ],
                  },
                  'meta': {'current_page': 1, 'last_page': 1},
                },
              ),
            );
            return;
          } else if (o.path.endsWith('/board')) {
            data = {
              'tables': [
                {
                  'table_id': 1,
                  'table_label': 'Table 1',
                  'floor_id': 1,
                  'seating': detail()['seating'],
                  'bill': detail()['bill'],
                },
              ],
            };
          } else if (o.path.endsWith('/feed')) {
            data = {'events': [], 'latest_id': 0, 'has_more': false};
          } else if (o.path.contains('incoming')) {
            data = {'transfers': []};
          } else if (o.path.contains('attention')) {
            data = {'orders': [], 'table_rounds': []};
          } else {
            data = {'orders': [], 'tables': [], 'events': []};
          }
          h.resolve(
            Response(requestOptions: o, statusCode: 200, data: {'data': data}),
          );
        },
      ),
    );
    return d;
  }
}

Future<Database> realLocalDatabase(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
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
  const codes = {
    'bill_changed': [
      'The bill changed. Reload the items and request approval again.',
      'تغيرت الفاتورة. حدّث الأصناف واطلب الموافقة مجدداً.',
    ],
    'bill_reserved': [
      'Resolve the payment result and reopen the bill before cancelling.',
      'تحقق من نتيجة الدفع وأعد فتح الفاتورة قبل الإلغاء.',
    ],
    'bill_has_payment': [
      'This bill has a payment and cannot be cancelled here.',
      'تحتوي الفاتورة على دفعة ولا يمكن إلغاؤها هنا.',
    ],
    'nothing_to_cancel': [
      'There are no accepted items to cancel. Use Clear Table for an empty session.',
      'لا توجد أصناف مقبولة للإلغاء. استخدم إخلاء الطاولة للجلسة الفارغة.',
    ],
    'bill_terminal': [
      'This bill is already closed. Refresh the tables.',
      'هذه الفاتورة مغلقة بالفعل. حدّث الطاولات.',
    ],
    'cancel_request_conflict': [
      'This saved cancellation conflicts with the server record. Ask a manager to review it.',
      'يتعارض الإلغاء المحفوظ مع سجل الخادم. اطلب من المدير مراجعته.',
    ],
  };
  for (final scenario in [
    'normal-empty',
    'normal-unsent',
    'normal-card',
    'normal-card-AR',
    'neutral-label',
    'neutral-label-AR',
  ]) {
    final ar = scenario.endsWith('-AR'), code = scenario.replaceAll('-AR', '');
    testWidgets('T11 fix1 O4 O5 real normal screen $scenario', (tester) async {
      Future<void> Function()? disposeFixture;
      try {
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
            timeout: const Duration(seconds: 20),
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
        final server = CancelServer()
          ..lose = scenario == 'lost'
          ..deny = scenario == 'denied'
          ..shelf = scenario == 'shelf'
          ..refusal = scenario == 'changed-loop'
              ? 'bill_changed'
              : codes.containsKey(code)
              ? code
              : null;
        final product = Product(
          id: '10',
          name: 'Coffee',
          category: 'Drinks',
          price: 0.5,
          stockMode: const {'shelf', 'offline-line'}.contains(scenario)
              ? 'unit'
              : 'ingredient',
        );
        late PosApiService api;
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        server.onCancelled = () => boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
            },
          ),
        );
        late Directory auxiliary;
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          auxiliary = await Directory.systemTemp.createTemp('fix7-ack-');
          await databaseFactory.setDatabasesPath(auxiliary.path);
          localDb = await realLocalDatabase('${auxiliary.path}/orders.db');
          storage = LocalOrderStorageService.forTesting(localDb);
          await storage.refreshRecoveryGuard();
          driftDb = AppDatabase.forTesting(
            NativeDatabase(File('${auxiliary.path}/outbox.db')),
          );
          server.storage = storage;
          api = PosApiService(tokenGetter: () => 'fixture', dio: server.dio());
          outbox = OrderSyncRepository(api, driftDb);
          coordinator = TableSyncCoordinator(
            outbox: outbox,
            store: storage,
            loadSessions: storage.loadDiningTableSessions,
            mode: () => 'live',
            degraded: () => server.offline,
            staffId: () => 7,
            markPrinted: (_) async {},
          );
        });
        debugOrderStorageOverride = storage;
        TableKitchenBridge? bridge;
        var disposed = false;
        disposeFixture = () async {
          if (disposed) return;
          disposed = true;
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
        };
        addTearDown(disposeFixture);
        Future<void> mount() async {
          await pumpWorkspaceMachine(
            tester,
            mode: 'live',
            toggle: false,
            wrapStaff: (child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
              child: child,
            ),
            api: api,
            realServices: true,
            arabic: ar,
            database: driftDb,
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
        debugPrint('T11 mounted');
        final dynamic host = tester.state(find.byType(StaffPosScreen));
        final PosController c = host.controller;
        await pumpUntilRealCondition(
          tester,
          () => c.diningTableSyncHooks is TableKitchenBridge,
          timeout: const Duration(seconds: 20),
          reason: 'real screen table startup hydration completed',
        );
        c.applyCatalog(
          categories: const ['Drinks'],
          products: [product],
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
        debugPrint('T11 ready to create local');
        await drive(() async {
          await storage.refreshRecoveryGuard();
          expect(c.diningTableDefinitions, isNotEmpty);
          await c.openDiningTable('1');
          expect(c.activeDiningTableId, '1', reason: c.lastPaymentMessage);
          if (scenario != 'normal-empty') {
            c.addProduct(product);
            c.addProduct(product);
          }
        });
        if (scenario == 'normal-empty') {
          await pumpUntilRealCondition(
            tester,
            () => find
                .text(L10nEn().posOrderPanelClearTable)
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'empty table keeps clear action',
          );
          expect(find.text('Cancel table bill'), findsNothing);
          expect(server.cancellations, isEmpty);
          return;
        }
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

        if (code == 'line-reserved-sync') {
          server.lineReserved = true;
          await drive(
            () => coordinator.cancelLine(
              c.diningSessionFor('1')!,
              line: {'product_id': 10, 'addon_ids': <int>[], 'notes': null},
              qty: 1,
              prepared: false,
              authorizedBy: 'Test Manager',
              reason: 'Synthetic reserved',
            ),
          );
          await pumpUntilRealCondition(
            tester,
            () => find
                .text(codes['bill_reserved']![ar ? 1 : 0])
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'sync refusal shown in real reconciliation sheet',
          );
          expect(await drive(outbox.pendingRows), isEmpty);
          final rows = (await drive(
            () => storage.readLocalLineCancellations(),
          ))!;
          expect(rows.single.cancelledQty, 0);
          expect(rows.single.status, 'bill_reserved');
          await drive(outbox.flush);
          expect(
            server.events.where(
              (e) => e['event_type'] == 'table.session.cancel_line',
            ),
            hasLength(1),
          );
          expect(await drive(() => localDb.query('order_history')), isEmpty);
          return;
        }
        if (scenario == 'offline-line') {
          server.offline = true;
          await drive(
            () => coordinator.cancelLine(
              c.diningSessionFor('1')!,
              line: {'product_id': 10, 'addon_ids': <int>[], 'notes': null},
              qty: 1,
              prepared: true,
              authorizedBy: 'Test Manager',
              reason: 'Synthetic offline',
            ),
          );
          final pending = (await drive(outbox.pendingRows))!;
          final rows = pending
              .expand((r) => (jsonDecode(r.eventsJson) as List).cast<Map>())
              .toList();
          final cancel = rows.singleWhere(
            (e) => e['event_type'] == 'table.session.cancel_line',
          );
          final waste = rows.singleWhere(
            (e) => e['event_type'] == 'product.waste',
          );
          expect(cancel['payload']['queued_offline'], true);
          expect(
            waste['payload']['table_cancellation_request_id'],
            cancel['payload']['client_request_id'],
          );
          expect(await drive(() => localDb.query('order_history')), isEmpty);
          return;
        }
        if (code == 'normal-card' || code == 'normal-unsent') {
          await pumpUntilRealCondition(
            tester,
            () => find
                .text(ar ? 'إلغاء فاتورة الطاولة' : 'Cancel table bill')
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'normal staff table offers cancellation',
          );
          expect(
            find.text(
              ar
                  ? L10nAr().posOrderPanelClearTable
                  : L10nEn().posOrderPanelClearTable,
            ),
            findsNothing,
          );
        } else {
          debugPrint('T11 accepted staff round');
          boards.add(
            RemoteTableSnapshot(
              tables: {
                1: RemoteTableState.fromBoard({
                  'table_id': 1,
                  'seating': server.detail()['seating'],
                  'bill': {
                    ...(server.detail()['bill'] as Map),
                    'order_uuid': server.uuid,
                    'source': 'main_pos',
                    'customer_rounds': 1,
                  },
                }, DateTime.now()),
              },
            ),
          );
          await pumpUntilRealCondition(
            tester,
            () => find.byType(DineInScreen).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'real staff screen adopted canonical shared bill',
          );
          await pumpUntilRealCondition(
            tester,
            () =>
                (tester.state(find.byType(DineInScreen)) as dynamic)
                    .controller
                    ?.ready ==
                true,
            timeout: const Duration(seconds: 20),
            reason: 'real controller loaded',
          );
          final dynamic sc = tester.state(find.byType(DineInScreen));
          final sw = tester.widget<DineInScreen>(find.byType(DineInScreen));
          debugPrint(
            'T11 controller available=${sc.controller.available} stale=${sc.controller.stale} notice=${sc.controller.notice} detail=${sc.controller.detail?.bill} local=${sw.localDraftBlocked} now=${sw.localDraftBlockedNow?.call()}',
          );
          await pumpUntilRealCondition(
            tester,
            () =>
                tester
                    .widget<DineInScreen>(find.byType(DineInScreen))
                    .workspace
                    ?.cartControls
                    ?.voidBill !=
                null,
            timeout: const Duration(seconds: 20),
            reason: 'cancel button published',
          );
        }
        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await pumpUntilRealCondition(
            tester,
            () => f.hitTestable().evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'control visible',
          );
          await tester.tap(f);
          await tester.pump();
        }

        debugPrint('T11 void enabled');
        if (scenario == 'normal-unsent') c.addProduct(product);
        if (scenario == 'offline-bill') server.offline = true;
        if (scenario == 'offline-read') server.failDetail = true;
        await tap(
          find.text(ar ? 'إلغاء فاتورة الطاولة' : 'Cancel table bill').first,
        );
        if (scenario == 'normal-unsent') {
          await pumpUntilRealCondition(
            tester,
            () => find
                .text(
                  'Resolve saved actions and send or remove unsent items before cancelling.',
                )
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'unsent draft prevents cancellation',
          );
          expect(server.cancellations, isEmpty);
          expect(server.approvals, 0);
          expect(
            (await drive(
              () => storage.readTableSyncVerdicts(limit: 1000000),
            ))!.where((v) => v.eventKind == 'cancel_bill_intent'),
            isEmpty,
          );
          return;
        }
        if (scenario == 'offline-bill' || scenario == 'offline-read') {
          await pumpUntilRealCondition(
            tester,
            () => find
                .text('Connect to the server before cancelling a table bill.')
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'offline refusal',
          );
          expect(server.cancellations, isEmpty);
          expect(
            (await drive(
              () => storage.readTableSyncVerdicts(limit: 1000000),
            ))!.where((v) => v.eventKind == 'cancel_bill_intent'),
            isEmpty,
          );
          return;
        }
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('cancel-bill-reason'))
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 20),
          reason: 'prepared confirmation',
        );
        expect(find.textContaining('1.000'), findsWidgets);
        expect(
          find.text(ar ? 'جارٍ مراجعة الإلغاء' : 'Reviewing cancellation'),
          findsOneWidget,
        );
        expect(
          find.text(ar ? 'بانتظار قرار الموظف' : 'Waiting for staff decision'),
          findsOneWidget,
        );
        expect(
          find.text(
            ar ? L10nAr().posPayBtnProcessing : L10nEn().posPayBtnProcessing,
          ),
          findsNothing,
        );
        expect(
          find.text(
            ar
                ? L10nAr().posPayBtnCompletingOrder
                : L10nEn().posPayBtnCompletingOrder,
          ),
          findsNothing,
        );

        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('cancel-bill-prepared-0')),
              )
              .value,
          isTrue,
        );
        if (scenario == 'unprepared') {
          await tap(find.byKey(const ValueKey('cancel-bill-prepared-0')));
        }
        await tester.enterText(
          find.byKey(const ValueKey('cancel-bill-reason')),
          'Synthetic T11',
        );
        await tap(find.byKey(const ValueKey('cancel-bill-approve')));
        await pumpUntilRealCondition(
          tester,
          () => find
              .text(
                ar ? L10nAr().posManagerPinTitle : L10nEn().posManagerPinTitle,
              )
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 20),
          reason: 'existing manager gate',
        );
        if (scenario == 'dismiss') {
          Navigator.of(tester.element(find.byType(AlertDialog).last)).pop();
          await pumpUntilRealCondition(
            tester,
            () => find.byType(AlertDialog).evaluate().isEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'gate dismissed',
          );
          expect(server.cancellations, isEmpty);
          expect(
            (await drive(
              () => storage.readTableSyncVerdicts(limit: 1000000),
            ))!.where((v) => v.eventKind == 'cancel_bill_intent'),
            isEmpty,
          );
          return;
        }
        for (final digit in ['1', '2', '3', '4']) {
          await tap(find.text(digit).last);
        }
        await tap(
          find
              .text(
                ar
                    ? L10nAr().posManagerPinVerify
                    : L10nEn().posManagerPinVerify,
              )
              .last,
        );
        if (scenario == 'denied') {
          await pumpUntilRealCondition(
            tester,
            () =>
                find.text(L10nEn().posManagerPinInvalid).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'gate refused',
          );
          expect(server.cancellations, isEmpty);
          expect(
            (await drive(
              () => storage.readTableSyncVerdicts(limit: 1000000),
            ))!.where((v) => v.eventKind == 'cancel_bill_intent'),
            isEmpty,
          );
          return;
        }
        await pumpUntilRealCondition(
          tester,
          () => server.cancellations.isNotEmpty,
          timeout: const Duration(seconds: 20),
          reason: 'approved intent sent',
        );
        if (codes.containsKey(code)) {
          await pumpUntilRealCondition(
            tester,
            () => find.text(codes[code]![ar ? 1 : 0]).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'readable final refusal',
          );
          expect(server.cancellations, hasLength(1));
          expect(server.applied, isEmpty);
          expect(await drive(() => outbox.pendingRows()), isEmpty);
          expect(
            await drive(() => localDb.query('dining_tables')),
            hasLength(1),
          );
          expect(await drive(() => localDb.query('order_history')), isEmpty);
          expect(
            (await drive(() => storage.readTableSyncVerdicts(limit: 1000000)))!
                .where((v) => v.eventKind == 'cancel_bill')
                .single
                .detail['refusal_code'],
            code,
          );
          return;
        }
        if (scenario == 'changed-loop') {
          await pumpUntilRealCondition(
            tester,
            () => find.text(codes['bill_changed']![0]).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'first changed-bill refusal visible',
          );
          expect(await drive(() => outbox.pendingRows()), isEmpty);
          expect(server.approvals, 1);
          final first = server.cancellations.single;
          if (find
              .byKey(const ValueKey('table-reconciliation-dismiss'))
              .evaluate()
              .isNotEmpty) {
            await tap(
              find.byKey(const ValueKey('table-reconciliation-dismiss')),
            );
          }
          server.refusal = null;
          await tap(find.text('Cancel table bill').first);
          await pumpUntilRealCondition(
            tester,
            () => find
                .byKey(const ValueKey('cancel-bill-reason'))
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'fresh confirmation after refusal',
          );
          await tester.enterText(
            find.byKey(const ValueKey('cancel-bill-reason')),
            'T11 fresh approval',
          );
          await tap(find.byKey(const ValueKey('cancel-bill-approve')));
          await pumpUntilRealCondition(
            tester,
            () => find.text(L10nEn().posManagerPinTitle).evaluate().isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'fresh manager gate',
          );
          for (final digit in ['1', '2', '3', '4']) {
            await tap(find.text(digit).last);
          }
          await tap(find.text(L10nEn().posManagerPinVerify).last);
          await pumpUntilRealCondition(
            tester,
            () => server.cancellations.length == 2,
            timeout: const Duration(seconds: 20),
            reason: 'second separately approved request',
          );
          expect(
            server.cancellations.last['client_request_id'],
            isNot(first['client_request_id']),
          );
          expect(
            server.cancellations.last['lines'][0]['client_request_id'],
            isNot(first['lines'][0]['client_request_id']),
          );
        }
        if (scenario == 'lost') {
          await pumpUntilRealCondition(
            tester,
            () => find
                .textContaining('The cancellation is saved.')
                .evaluate()
                .isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'lost response returned uncertain',
          );
          await pumpUntilRealCondition(
            tester,
            () async => (await outbox.pendingRows()).isNotEmpty,
            timeout: const Duration(seconds: 20),
            reason: 'lost response preserved',
          );
          final original = jsonEncode(server.cancellations.first);
          server.lose = false;
          await drive(outbox.flush);
          for (final p in server.cancellations) {
            expect(jsonEncode(p), original);
          }
          boards.add(
            RemoteTableSnapshot(
              tables: {
                1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
              },
            ),
          );
        }
        await pumpUntilRealCondition(
          tester,
          () async => (await localDb.query('dining_tables')).isEmpty,
          timeout: const Duration(seconds: 20),
          reason: 'cancelled local copy archived',
        );
        if (scenario == 'lost') {
          expect(server.cancellations.length, greaterThanOrEqualTo(2));
        } else {
          expect(
            server.cancellations,
            hasLength(scenario == 'changed-loop' ? 2 : 1),
          );
        }
        expect(server.applied, hasLength(1));
        expect(server.approvals, scenario == 'changed-loop' ? 2 : 1);
        final payload = server.cancellations.first;
        expect(payload['lines'][0]['qty'], 2);
        expect(payload['lines'][0]['prepared'], scenario != 'unprepared');
        expect(
          payload['lines'][0]['client_request_id'],
          isNot(payload['client_request_id']),
        );
        expect(payload['queued_offline'], false);
        expect(payload.containsKey('total'), false);
        expect(await drive(() => localDb.query('order_history')), isEmpty);
        expect(
          await drive(() => localDb.query('draft_recovery_closed_archive')),
          hasLength(1),
        );
        expect(
          server.events.any(
            (e) =>
                e['event_type'] == 'order.pay' ||
                e['event_type'] == 'order.void',
          ),
          false,
        );
        expect(server.calls.any((p) => p.contains('/void')), false);
        if (scenario == 'unprepared' || scenario == 'shelf') {
          expect(find.textContaining('Waste recorded:'), findsNothing);
        } else if (scenario == 'happy') {
          expect(
            find.textContaining('Waste recorded: OMR 0.123'),
            findsWidgets,
          );
        }
        if (scenario == 'shelf') {
          await drive(outbox.flush);
          final waste = server.events
              .where((e) => e['event_type'] == 'product.waste')
              .toList();
          expect(waste, hasLength(1));
          expect(
            waste.single['payload']['table_cancellation_request_id'],
            payload['lines'][0]['client_request_id'],
          );
          expect(waste.single['payload']['lines'][0]['qty'], 2);
          final shelfNotice = (await drive(
            () => storage.readTableSyncVerdicts(limit: 1000000),
          ))!.singleWhere((v) => v.eventKind == 'cancel_shelf_waste');
          expect(
            shelfNotice.detail['table_cancellation_request_id'],
            payload['lines'][0]['client_request_id'],
          );
          expect(
            tableReconciliationCopy(L10nEn(), shelfNotice),
            'Prepared-item waste recorded.',
          );
          expect(
            tableReconciliationCopy(L10nAr(), shelfNotice),
            'تم تسجيل هدر الأصناف المحضّرة.',
          );
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await disposeFixture?.call();
        await tester.pump(const Duration(milliseconds: 1));
      }
    });
  }
}
