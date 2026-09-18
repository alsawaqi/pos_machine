import 'dart:async';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'draft_recovery_test.dart' show RecoveryHarness, billId;
import 'workspace_machine_harness.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'qr_checkout_fakes.dart' show claimJson, snapshotJson;

class _Store extends LocalOrderStorageService {
  _Store(super.db) : super.forTesting();
  @override
  Future<int> fetchNextOrderNumber() async => 1450;
  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => [];
  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async =>
      List.of(receipts);
  final receipts = <OrderHistoryRecord>[];
  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {
    receipts.add(
      OrderHistoryRecord(
        id: snapshot.serverOrderUuid,
        orderNumber: snapshot.orderNumber,
        orderType: OrderTypeLabel.fromStorage(snapshot.orderType),
        createdAt: DateTime.now(),
        snapshot: snapshot,
      ),
    );
  }

  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {
    receipts[receipts.indexWhere((r) => r.id == record.id)] = record;
  }
}

class _Outbox implements OrderSyncRepository {
  _Outbox(this.h);
  final RecoveryHarness h;
  @override
  Future<int> flush() async => 0;
  @override
  Future<bool> hasUnresolvedStandaloneQrPay(String uuid) async => false;
  @override
  Stream<List<OrderOutboxRow>> watchPending() => Stream.value([]);
  @override
  Future<void> assertIdleForCombine() async {}
  @override
  Future<void> admitDraftRecovery(Future<void> Function() f) => f();
  @override
  Future<OrderOutboxRow?> rowForKey(String key) async => h.outbox[key];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected write: ${i.memberName}');
}

class _Coord extends WorkspaceTableCoordinator {
  _Coord(this.local);
  final _Store local;
  @override
  TableLedgerStore get store => local;
  @override
  Future<void> get settled async {}
  @override
  bool get live => true;
  DiningTableSession? saved;
  @override
  DiningTableSession? cachedSession(String id) => saved;
  @override
  Future<List<Map<String, dynamic>>> delta(DiningTableSession s) async => [];
  @override
  void onTableLeft(String id) {}
  @override
  void onTableDraftPersisted(DiningTableSession s) {}
  @override
  void onTableOccupied(DiningTableSession s) {}

  @override
  void forgetRecoveredSession({
    required String tableId,
    required String uuid,
    String? occupiedAt,
    String? seatingKey,
  }) {}
}

class _Api implements PosApiService {
  int reads = 0, payments = 0, claims = 0;
  bool paid = false;
  final issued = DateTime.now().toUtc();
  Map<String, dynamic> claim() => {
    ...claimJson(),
    'order_uuid': billId,
    'charge_claimed_at': issued.toIso8601String(),
    'charge_deadline_at': issued
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  };
  Map<String, dynamic> snapshot() {
    final result = snapshotJson();
    (result['order'] as Map).addAll(<String, dynamic>{
      'uuid': billId,
      'order_type': 'dine_in',
      'table_id': 1,
    });
    result['claim'] = claim();
    return result;
  }

  @override
  Future<Map<String, dynamic>> checkoutClaim(Map<String, dynamic> input) async {
    claims++;
    return {...claim(), 'already_claimed_by_this_device': claims > 1};
  }

  @override
  Future<Map<String, dynamic>> checkoutRead(String uuid) async => snapshot();
  @override
  Future<List<Map<String, dynamic>>> checkoutPush(
    Map<String, dynamic> event,
  ) async {
    payments++;
    paid = true;
    return [
      {
        'client_event_id': event['client_event_id'],
        'status': 'processed',
        'result': {
          'order_id': 12,
          'status': 'paid',
          'receipt_number': 'TEST-1',
        },
      },
    ];
  }

  @override
  String Function() get tokenGetter =>
      () => 'fixture';
  @override
  String get quickOrderBaseUrl => 'http://fixture.invalid/api/v1';
  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];
  @override
  Future<Map<String, dynamic>> dineInDetail(int id) async {
    reads++;
    return {
      'table': {'id': 1, 'label': 'Table 1'},
      'occupied': !paid,
      'orphaned': false,
      'seating': paid
          ? null
          : {
              'uuid': '22222222-2222-4222-8222-222222222222',
              'table_id': 1,
              'status': 'open',
              'joined_table_ids': [],
            },
      'bill': paid
          ? null
          : {
              ...(snapshot()['order'] as Map<String, dynamic>),
              'status': 'open',
              'charge': 'none',
            },
      'rounds': <dynamic>[],
    };
  }

  // This member is also valid as an extra fake method on the frozen interface.
  @override
  Future<Map<String, dynamic>?> closedTableBill(String uuid, int id) async => {
    'uuid': billId,
    'table_id': 1,
    'order_type': 'dine_in',
    'status': 'paid',
  };
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected API: ${i.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final unsent in [false]) {
    testWidgets(
      'F12 residual real adopted checkout Done retires copy without restart',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final channel in [
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          const MethodChannel('pos_machine/rear_display_host'),
        ]) {
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
        final h = RecoveryHarness();
        late _Store storage;
        late Directory temp;
        await tester.runAsync(() async {
          databaseFactory = databaseFactoryFfi;
          temp = await Directory.systemTemp.createTemp('f12-test-');
          await databaseFactory.setDatabasesPath(temp.path);
          await h.init(qty: unsent ? 3 : 2);
          await h.db.delete('held_orders');
          for (final column in [
            'floor_id TEXT',
            'order_reference TEXT',
            'order_number INTEGER',
            'paid_snapshot_json TEXT',
          ]) {
            if (!(await h.db.rawQuery(
              'PRAGMA table_info(dining_tables)',
            )).any((row) => row['name'] == column.split(' ').first)) {
              await h.db.execute(
                'ALTER TABLE dining_tables ADD COLUMN $column',
              );
            }
          }
          await h.db.execute(
            'ALTER TABLE dining_tables ADD COLUMN updated_at TEXT',
          );
          await h.db.execute(
            'ALTER TABLE dining_tables ADD COLUMN temp_reference TEXT',
          );
          await h.db.execute(
            'ALTER TABLE dining_tables ADD COLUMN last_verdict TEXT',
          );
          await h.db.execute(
            'ALTER TABLE dining_tables ADD COLUMN last_verdict_at TEXT',
          );
          await h.db.execute(
            'ALTER TABLE local_line_cancellations ADD COLUMN seating_key TEXT',
          );
          storage = _Store(h.db);
          await storage.refreshRecoveryGuard();
        });
        debugOrderStorageOverride = storage;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          debugOrderStorageOverride = null;
          await tester.runAsync(h.close);
        });
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        addTearDown(boards.close);
        final api = _Api();
        final coordinator = _Coord(storage);
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          wrapStaff: (child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
            child: child,
          ),
          api: api,
          outbox: _Outbox(h),
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
        await tester.runAsync(() async {
          await c.refreshDiningTables();
        });
        c.diningFloors = const [DiningFloor(id: '1', label: 'Ground')];
        c.diningTableDefinitions = const [
          DiningTableDefinition(
            id: '1',
            floorId: '1',
            name: 'Table 1',
            sizeLabel: '2 seats',
            seats: 2,
            sortOrder: 1,
          ),
        ];
        coordinator.saved = c.diningSessionFor('1');
        await tester.runAsync(() => c.openDiningTable('1'));
        expect(c.cart, hasLength(1));

        final before = await tester.runAsync(() => h.db.query('dining_tables'));
        boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(
                tableId: 1,
                fetchedAt: DateTime.now(),
                seatingUuid: '22222222-2222-4222-8222-222222222222',
                seatingStatus: 'open',
                billOrderUuid: billId,
                billStatus: 'open',
                billSource: 'qr_web',
                billCustomerRounds: 1,
                billStaffRounds: 1,
              ),
            },
          ),
        );
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        expect(find.byType(DineInScreen), findsOneWidget);
        final screen = tester.widget<DineInScreen>(find.byType(DineInScreen));
        var routeDone = false;
        unawaited(screen.onPay(billId).then((_) => routeDone = true));
        for (
          var i = 0;
          i < 200 && find.byType(QrCheckoutBoundary).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        expect(find.byType(QrCheckoutBoundary), findsOneWidget);
        final checkout = tester
            .widget<QrCheckoutBoundary>(find.byType(QrCheckoutBoundary))
            .controller;
        for (var i = 0; i < 200 && !checkout.ready; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        expect(checkout.ready, isTrue, reason: checkout.notice);
        await tester.runAsync(
          () => checkout.pay([const CheckoutTender('cash', 4750)]),
        );
        await tester.pumpAndSettle();
        expect(checkout.phase, CheckoutPhase.paid, reason: checkout.notice);
        boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
            },
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('qr-checkout-exit')));
        await tester.pumpAndSettle();

        expect(api.payments, 1);
        for (var i = 0; i < (unsent ? 30 : 150); i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        expect(routeDone, isTrue);
        final rows = await tester.runAsync(() => h.db.query('dining_tables'));
        if (unsent) {
          expect(rows, before);
          expect(c.diningSessionFor('1'), isNotNull);
        } else {
          expect(
            rows,
            isEmpty,
            reason:
                'Paid canonical bill must retire the local tile automatically',
          );
          expect(c.diningSessionFor('1'), isNull);
          final archives = await tester.runAsync(
            () => h.db.query('draft_recovery_closed_archive'),
          );
          expect(archives, hasLength(1));
          expect(archives!.single['order_uuid'], billId);
        }
        expect(
          await tester.runAsync(() => h.db.query('order_history')),
          isEmpty,
        );
        expect(
          h.outbox.length,
          1,
        ); // Original acknowledged round only; no void/pay.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        // Auxiliary journal files are isolated under temp; never device databases.
        expect(temp.path, contains('f12-test-'));
      },
    );
  }
}
