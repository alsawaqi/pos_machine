import 'package:flutter/material.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'send_to_kitchen_test.dart' show B3Memory, b3Product;
import 'workspace_machine_harness.dart';

const _bill = '11111111-1111-4111-8111-111111111111';
const _seat = '22222222-2222-4222-8222-222222222222';

class _Coordinator extends WorkspaceTableCoordinator {
  _Coordinator(this.memory);
  final B3Memory memory;
  @override
  B3Memory get store => memory;
  @override
  bool get live => true;
  @override
  Future<void> get settled async {}
  @override
  DiningTableSession? cachedSession(String id) => store.tables[id];
  @override
  Future<List<Map<String, dynamic>>> delta(DiningTableSession session) async =>
      (session.draft?.items.single.qty ?? 0) > 1
      ? [
          {'product_id': 10, 'qty': 1, 'addon_ids': <int>[], 'notes': ''},
        ]
      : [];
  @override
  void onTableDraftPersisted(DiningTableSession session) {}
  @override
  void onTableOccupied(DiningTableSession session) {}
}

class _ReviewGateway extends TableFake {
  @override
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  ) async {
    await super.review(detail, round, accept);
    (value['rounds'] as List).last['status'] = accept ? 'accepted' : 'rejected';
    if (accept) {
      (value['bill'] as Map)['grand_total_baisas'] = 5250;
      (value['bill'] as Map)['items'].add({
        'id': 100,
        'product_name': 'Water',
        'qty': 1,
        'line_total_baisas': 500,
      });
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channels = [
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    MethodChannel('pos_machine/rear_display_host'),
  ];
  setUp(() {
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async =>
                call.method == 'read' ? 'mock-token' : <Map<String, dynamic>>[],
          );
    }
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    for (final channel in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
  for (final unsent in [false, true]) {
    testWidgets(
      'F09 opening till ${unsent ? 'explains an unsent draft' : 'adopts arriving customer round with sent cart'}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = B3Memory();
        debugOrderStorageOverride = store;
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        addTearDown(boards.close);
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          coordinator: _Coordinator(store),
          boards: boards.stream,
          catalog: const CatalogSnapshot(
            categories: ['Drinks'],
            products: [b3Product],
            floors: [],
            tables: [],
            taxes: [],
          ),
        );
        final dynamic state = tester.state(find.byType(StaffPosScreen));
        final PosController controller = state.controller;
        controller.addProduct(b3Product);
        if (unsent) controller.addProduct(b3Product);
        controller.selectedOrderType = OrderType.dineIn;
        controller.activeDiningTableId = '3';
        final at = DateTime.utc(2026, 9, 18);
        final local = DiningTableSession(
          tableId: '3',
          floorId: '1',
          status: DiningTableStatus.occupied,
          orderReference: controller.currentOrderReference,
          occupiedAt: at,
          updatedAt: at,
          seatingKey: _seat,
          seatingUuid: _seat,
          serverOrderUuid: _bill,
          draft: controller.createDraft(serverOrderUuid: _bill),
        );
        controller.diningTableSessions = [local];
        store.tables['3'] = local;
        store.rounds['round1'] = LocalTableRound(
          clientRequestId: 'round1',
          tableId: '3',
          seatingKey: _seat,
          localRoundNo: 1,
          lines: [
            {'product_id': 10, 'qty': 1, 'addon_ids': <int>[], 'notes': ''},
          ],
          submittedAt: at,
          outboxKey: 'round1',
          status: 'appended',
          serverRoundId: 1,
          serverRoundNo: 1,
          orderUuid: _bill,
          ackedAt: at,
        );
        boards.add(
          RemoteTableSnapshot(
            tables: {
              3: RemoteTableState(
                tableId: 3,
                fetchedAt: DateTime.now(),
                seatingUuid: _seat,
                seatingStatus: 'open',
                billOrderUuid: _bill,
                billStatus: 'open',
                billSource: 'main_pos',
                billCustomerRounds: 1,
                billStaffRounds: 1,
                needsReviewCount: 1,
              ),
            },
          ),
        );
        // Board polling arrives while the till's original cart is still open.
        for (var tick = 0; tick < 8; tick++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (unsent) {
          expect(find.byType(DineInScreen), findsNothing);
          expect(
            find.textContaining('Send or remove unsent local items'),
            findsOneWidget,
          );
        } else {
          expect(find.byType(DineInScreen), findsOneWidget);
          final screen = tester.widget<DineInScreen>(find.byType(DineInScreen));
          expect(screen.localDraftBlocked, isFalse);
          expect(screen.localDraftBlockedNow!(), isFalse);
          // Exercise the editor with exactly the admission flags produced by
          // the real opening-till host. Only HTTP/storage are memory adapters.
          final gateway = _ReviewGateway()
            ..value = tableFixture(selected: 3, pending: true);
          final shared = DineInController(gateway, TableMemory(), 3);
          final paid = <String>[];
          unawaited(
            Navigator.of(
              tester.element(find.byType(StaffPosScreen)),
            ).push<void>(
              MaterialPageRoute(
                builder: (_) => DineInScreen(
                  createController: () async => shared,
                  catalogue: () => [],
                  label: 'Table 3',
                  localDraftBlocked: screen.localDraftBlocked,
                  localDraftBlockedNow: screen.localDraftBlockedNow,
                  onPay: (uuid) async => paid.add(uuid),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final confirm = find.byKey(const ValueKey('dine-confirm-8'));
          expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
          expect(shared.canPay, isFalse);
          await tester.ensureVisible(confirm);
          await tester.tap(confirm);
          await tester.pumpAndSettle();
          expect(gateway.calls, contains('review:customer:8:true'));
          expect(shared.canPay, isTrue);
          expect(find.textContaining('5.250'), findsWidgets);
          final pay = find.byKey(const ValueKey('dine-pay'));
          expect(tester.widget<FilledButton>(pay).onPressed, isNotNull);
          await tester.ensureVisible(pay);
          await tester.tap(pay);
          await tester.pumpAndSettle();
          expect(paid, ['bill-1']);
        }
        // The server workspace is a projection: never discard the local evidence.
        expect(controller.cart.single.qty, unsent ? 2 : 1);
        expect(store.tables['3']?.serverOrderUuid, _bill);
        await disposeWorkspaceMachine(tester);
      },
    );
  }
}
