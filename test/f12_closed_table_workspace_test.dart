import 'real_io_wait.dart';
import 'dart:async';
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

class _Store extends LocalOrderStorageService {
  _Store(super.db) : super.forTesting();
  @override
  Future<int> fetchNextOrderNumber() async => 1450;
  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => [];
  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async => [];
}

class _Outbox implements OrderSyncRepository {
  _Outbox(this.h);
  final RecoveryHarness h;
  @override
  Future<int> flush() async => 0;
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
  @override
  void forgetRecoveredSession({
    required String tableId,
    required String uuid,
    String? occupiedAt,
    String? seatingKey,
  }) {}
}

class _Api implements PosApiService {
  int reads = 0;
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
      'occupied': false,
      'orphaned': false,
      'seating': null,
      'bill': null,
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
  for (final unsent in [false, true]) {
    testWidgets(
      'F12 opening till ${unsent ? "retains unsent local additions" : "retires sent-only paid shared copy"}',
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
          debugOrderStorageOverride = null;
          await h.close();
        });
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        addTearDown(boards.close);
        final api = _Api();
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
          coordinator: _Coord(storage),
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
        c.selectedOrderType = OrderType.dineIn;
        final before = await tester.runAsync(() => h.db.query('dining_tables'));
        boards.add(
          RemoteTableSnapshot(
            tables: {
              1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now()),
            },
          ),
        );
        for (var i = 0; i < (unsent ? 30 : 150); i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        if (!unsent) {
          await pumpUntilRealCondition(
            tester,
            () async =>
                (await h.db.query('dining_tables')).isEmpty &&
                c.diningSessionFor('1') == null,
            reason: 'retirement committed and controller refresh completed',
          );
        }
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
