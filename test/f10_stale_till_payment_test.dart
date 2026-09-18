import 'dart:async';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

class _Api implements PosApiService {
  _Api(this.offline);
  final bool offline;
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];
  @override
  Future<Map<String, dynamic>> dineInDetail(int id) async {
    reads++;
    if (offline) throw StateError('Offline');
    return {
      'table': {'id': id, 'label': 'Table 3'},
      'occupied': false,
      'orphaned': false,
      'seating': null,
      'bill': null,
      'rounds': <Map<String, dynamic>>[],
    };
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected: ${i.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pos_machine/rear_display_host');
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secure,
          (call) async => call.method == 'read' ? 'test-token' : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => <Map<String, dynamic>>[],
        );
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secure, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final offline in [false, true]) {
    testWidgets(
      'F10 ${offline ? 'unreachable' : 'paid elsewhere'} bill refuses cash before receipt and history',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final storage = FakeOrderStorage();
        debugOrderStorageOverride = storage;
        final api = _Api(offline);
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        addTearDown(boards.close);
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          api: api,
          boards: boards.stream,
          wrapStaff: (child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
            child: child,
          ),
          catalog: const CatalogSnapshot(
            categories: [],
            products: [],
            floors: [],
            tables: [],
            taxes: [],
          ),
        );
        final dynamic state = tester.state(find.byType(StaffPosScreen));
        final PosController controller = state.controller;
        controller.printReceipts = false;
        controller.printKitchenTickets = false;
        controller.addProduct(
          const Product(
            id: '1',
            name: 'Coffee',
            category: 'Coffee',
            price: 0.630,
          ),
        );
        controller.selectedOrderType = OrderType.dineIn;
        controller.activeDiningTableId = '3';
        controller.selectPaymentMethod('Cash');
        // External kitchen/outbox adapters are inert; payment remains real.
        controller.onDiningTableFinalRound = (_) async => true;
        controller.diningTableSyncHooks = null;
        controller.onOrderCompleted = null;
        if (!offline) {
          final at = DateTime.utc(2026, 9, 18);
          controller.diningTableSessions = [
            DiningTableSession(
              tableId: '3',
              floorId: '1',
              status: DiningTableStatus.occupied,
              orderReference: controller.currentOrderReference,
              occupiedAt: at,
              updatedAt: at,
              seatingUuid: '22222222-2222-4222-8222-222222222222',
              serverOrderUuid: controller.activeDiningTableBillUuid,
              draft: controller.createDraft(),
            ),
          ];
          boards.add(
            RemoteTableSnapshot(
              tables: {
                3: RemoteTableState(tableId: 3, fetchedAt: DateTime.now()),
              },
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(
            find.text(
              'This bill was paid or closed. Any unsent local items remain saved. Use Clear Table to review the saved copy.',
            ),
            findsOneWidget,
          );
          final dynamic pay = tester.widget(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_PayButton',
            ),
          );
          expect(pay.enabled, isFalse);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('table-send-to-kitchen')),
                )
                .onPressed,
            isNull,
          );
        }
        final before = controller.cart.length;
        final payment = controller.payAndPrint(cashTenderedAmount: 1);
        for (var tick = 0; tick < 5; tick++) {
          await tester.pump(const Duration(seconds: 1));
        }
        final result = await payment;
        expect(
          api.reads,
          1,
          reason: 'A fresh server check must precede any tender',
        );
        expect(
          storage.history,
          isEmpty,
          reason: 'A rejected preflight cannot record a second sale',
        );
        expect(
          controller.cart.length,
          before,
          reason: 'Keep the saved evidence for safe recovery',
        );
        expect(controller.paymentStatus, isNot('Paid'));
        expect(
          result,
          contains(
            offline
                ? 'verify'
                : 'This bill was paid or closed. Any unsent local items remain saved. Use Clear Table to review the saved copy.',
          ),
        );
        await disposeWorkspaceMachine(tester);
      },
    );
  }
}
