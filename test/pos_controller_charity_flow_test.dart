import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

const _frontChannelName = 'pos_machine/front_display_channel';
const _codec = StandardMethodCodec();
const _androidOnly = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
});

class _FakeOrderStorageService implements OrderStorageService {
  int _nextOrderNumber = 1450;
  int saveDiningTableSessionCalls = 0;
  final List<OrderHistoryRecord> _history = <OrderHistoryRecord>[];
  final List<HeldOrderRecord> _held = <HeldOrderRecord>[];
  final List<DiningTableSession> _dining = <DiningTableSession>[];

  @override
  Future<void> clearAllData() async {
    _nextOrderNumber = 1450;
    saveDiningTableSessionCalls = 0;
    _history.clear();
    _held.clear();
    _dining.clear();
  }

  @override
  Future<void> clearHeldOrders() async {
    _held.clear();
  }

  @override
  Future<void> clearDiningTable(String tableId) async {
    _dining.removeWhere((record) => record.tableId == tableId);
  }

  @override
  Future<void> deleteHeldOrder(String id) async {
    _held.removeWhere((record) => record.id == id);
  }

  @override
  Future<int> fetchNextOrderNumber() async => _nextOrderNumber;

  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => List.of(_held);

  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async =>
      List.of(_dining);

  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async =>
      List.of(_history);

  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {
    _history.insert(
      0,
      OrderHistoryRecord(
        id: 'history_${snapshot.orderNumber}',
        orderNumber: snapshot.orderNumber,
        orderType: OrderTypeLabel.fromStorage(snapshot.orderType),
        createdAt: DateTime.now(),
        snapshot: snapshot,
      ),
    );
    _nextOrderNumber = snapshot.orderNumber + 1;
  }

  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {
    final index = _history.indexWhere((entry) => entry.id == record.id);
    if (index == -1) {
      _history.insert(0, record);
      return;
    }
    _history[index] = record;
  }

  @override
  Future<void> saveHeldOrder(OrderSessionDraft draft) async {
    _held.insert(
      0,
      HeldOrderRecord(
        id: 'held_${draft.orderReference}',
        orderNumber: draft.orderNumber,
        orderReference: draft.orderReference,
        orderType: draft.orderType,
        heldAt: DateTime.now(),
        draft: draft,
      ),
    );
  }

  @override
  Future<void> saveDiningTableSession(DiningTableSession session) async {
    saveDiningTableSessionCalls++;
    _dining.removeWhere((record) => record.tableId == session.tableId);
    _dining.insert(0, session);
    if (session.orderNumber != null &&
        session.orderNumber! >= _nextOrderNumber) {
      _nextOrderNumber = session.orderNumber! + 1;
    }
  }
}

Future<void> _sendCustomerDecision({required bool accepted}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _frontChannelName,
        _codec.encodeMethodCall(
          MethodCall('customerEvent', {
            'type': 'charity_round_up_response',
            'accepted': accepted,
          }),
        ),
        (_) {},
      );
}

Future<void> _sendPaymentLaunchState({
  required String stage,
  required String surface,
}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _paymentChannel.name,
        _codec.encodeMethodCall(
          MethodCall('paymentLaunchState', {
            'stage': stage,
            'surface': surface,
          }),
        ),
        (_) {},
      );
}

const _paymentChannel = MethodChannel('com.example.mosambee');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hostChannel = MethodChannel('pos_machine/rear_display_host');
  const paymentChannel = _paymentChannel;
  const printerChannel = MethodChannel('sunmi_printer_plus');

  late _FakeOrderStorageService fakeStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'terminal_id': 'TERM-1001'});
    fakeStorage = _FakeOrderStorageService();
    await fakeStorage.clearAllData();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, (call) async {
          switch (call.method) {
            case 'getPresentationDisplays':
              return <Map<String, dynamic>>[];
            case 'openRearDisplay':
              return true;
            case 'hideRearDisplay':
              return true;
            case 'transferDataToRear':
              return true;
            default:
              return null;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printerChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hostChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paymentChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(printerChannel, null);
  });

  testWidgets(
    'manager cancellation can mark a completed order fully canceled',
    (tester) async {
      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.selectPaymentMethod('Cash');

      final paymentFuture = controller.payAndPrint(cashTenderedAmount: 2.000);
      await tester.pump(const Duration(milliseconds: 800));
      final paymentMessage = await paymentFuture;

      expect(paymentMessage, contains('Cash payment recorded successfully.'));
      expect(fakeStorage._history, hasLength(1));

      final cancelMessage = await controller.cancelCompletedOrder(
        fakeStorage._history.single,
        cancelFullOrder: true,
        itemIndexes: const <int>{},
      );

      expect(cancelMessage, contains('fully canceled'));
      expect(fakeStorage._history.single.snapshot.paymentStatus, 'Canceled');
      expect(fakeStorage._history.single.snapshot.cancellations, hasLength(1));
      expect(fakeStorage._history.single.snapshot.isFullyCanceled, isTrue);
      expect(
        fakeStorage._history.single.snapshot.canceledAmount,
        closeTo(1.575, 0.001),
      );
    },
  );

  testWidgets(
    'manager cancellation can cancel selected completed order items',
    (tester) async {
      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts[0]);
      controller.addProduct(controller.allProducts[1]);
      controller.selectPaymentMethod('Cash');

      final paymentFuture = controller.payAndPrint(cashTenderedAmount: 4.000);
      await tester.pump(const Duration(milliseconds: 800));
      final paymentMessage = await paymentFuture;

      expect(paymentMessage, contains('Cash payment recorded successfully.'));
      expect(fakeStorage._history, hasLength(1));

      final cancelMessage = await controller.cancelCompletedOrder(
        fakeStorage._history.single,
        cancelFullOrder: false,
        itemIndexes: const <int>{0},
      );

      final updatedSnapshot = fakeStorage._history.single.snapshot;
      expect(cancelMessage, contains('1 item'));
      expect(updatedSnapshot.paymentStatus, 'Partially Canceled');
      expect(updatedSnapshot.cancellations, hasLength(1));
      expect(updatedSnapshot.isFullyCanceled, isFalse);
      expect(updatedSnapshot.isItemCanceled(0), isTrue);
      expect(updatedSnapshot.isItemCanceled(1), isFalse);
      expect(updatedSnapshot.cancellations.single.itemName, 'Cappuccino');
    },
  );

  testWidgets('newly added cart items appear at the top of the order', (
    tester,
  ) async {
    final controller = PosController(orderStorage: fakeStorage);
    addTearDown(controller.dispose);

    await controller.init();
    controller.addProduct(controller.allProducts[0]);
    controller.addProduct(controller.allProducts[1]);

    expect(controller.cart.first.product.id, controller.allProducts[1].id);
    expect(controller.cart.last.product.id, controller.allProducts[0].id);
  });

  testWidgets(
    'held orders use a temporary reference instead of an order number',
    (tester) async {
      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);

      final message = await controller.holdCurrentOrder();

      expect(message, isNot(contains('Order #')));
      expect(fakeStorage._held, hasLength(1));
      final held = fakeStorage._held.single;
      expect(held.orderNumber, isNull);
      expect(held.draft.toMap(), contains('orderReference'));
      expect(
        held.draft.toMap()['orderReference'].toString(),
        startsWith('REF-'),
      );
    },
  );

  testWidgets(
    'dining table drafts get a reference and only receive an order number after payment',
    (tester) async {
      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      await controller.openDiningTable('main_t1');
      controller.addProduct(controller.allProducts.first);
      await controller.returnToDiningFloorPlan();

      expect(fakeStorage._dining, hasLength(1));
      final occupiedSession = fakeStorage._dining.single;
      expect(occupiedSession.status, DiningTableStatus.occupied);
      expect(occupiedSession.orderNumber, isNull);
      expect(occupiedSession.draft!.toMap(), contains('orderReference'));
      expect(
        occupiedSession.draft!.toMap()['orderReference'].toString(),
        startsWith('REF-'),
      );

      await controller.openDiningTable('main_t1');
      controller.selectPaymentMethod('Cash');
      final paymentFuture = controller.payAndPrint(cashTenderedAmount: 2.000);
      await tester.pump(const Duration(milliseconds: 800));
      final message = await paymentFuture;

      expect(message, contains('Cash payment recorded successfully.'));
      expect(fakeStorage._history, hasLength(1));
      expect(fakeStorage._history.single.orderNumber, 1450);
      expect(fakeStorage._dining.single.status, DiningTableStatus.paid);
      expect(fakeStorage._dining.single.orderNumber, 1450);
    },
    variant: _androidOnly,
  );

  testWidgets('rapid dine-in product taps coalesce table draft persistence', (
    tester,
  ) async {
    final controller = PosController(orderStorage: fakeStorage);
    addTearDown(controller.dispose);

    await controller.init();
    await controller.openDiningTable('main_t1');

    for (var index = 0; index < 20; index++) {
      controller.addProduct(controller.allProducts.first);
    }

    expect(controller.cart.single.qty, 20);
    expect(fakeStorage.saveDiningTableSessionCalls, 0);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(fakeStorage.saveDiningTableSessionCalls, 1);
    expect(fakeStorage._dining.single.draft!.items.single.qty, 20);
  });

  testWidgets(
    'rear display syncs never overlap when product taps are rapid',
    (tester) async {
      final firstTransferCompleter = Completer<void>();
      var transferCalls = 0;
      var inFlightTransfers = 0;
      var maxInFlightTransfers = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hostChannel, (call) async {
            if (call.method != 'transferDataToRear') return true;

            transferCalls++;
            inFlightTransfers++;
            if (inFlightTransfers > maxInFlightTransfers) {
              maxInFlightTransfers = inFlightTransfers;
            }

            if (transferCalls == 1) {
              await firstTransferCompleter.future;
            }

            inFlightTransfers--;
            return true;
          });

      final controller = PosController(orderStorage: fakeStorage);
      controller.rearDisplayOpened = true;
      addTearDown(controller.dispose);

      controller.addProduct(controller.allProducts[0]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(transferCalls, 1);

      for (var index = 1; index < 12; index++) {
        controller.addProduct(
          controller.allProducts[index % controller.allProducts.length],
        );
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(maxInFlightTransfers, 1);

      firstTransferCompleter.complete();
      await tester.pump(const Duration(milliseconds: 600));

      expect(maxInFlightTransfers, 1);
      expect(transferCalls, 2);
    },
    variant: _androidOnly,
  );

  testWidgets(
    'accepting the charity round-up launches payment with the rounded total',
    (tester) async {
      String? sentAmount;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              sentAmount = arguments['amount']?.toString();
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.selectPaymentMethod('Credit Card');

      final paymentFuture = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);
      expect(controller.charityRoundUpAmount, closeTo(0.425, 0.0001));

      await _sendCustomerDecision(accepted: true);
      await tester.pump(const Duration(milliseconds: 800));

      final message = await paymentFuture;
      expect(sentAmount, '2000');
      expect(message, contains('Payment approved.'));
    },
    variant: _androidOnly,
  );

  testWidgets(
    'declining the charity round-up still launches payment with the original total',
    (tester) async {
      String? sentAmount;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              sentAmount = arguments['amount']?.toString();
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.selectPaymentMethod('Credit Card');

      final paymentFuture = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);

      await _sendCustomerDecision(accepted: false);
      await tester.pump(const Duration(milliseconds: 800));

      final message = await paymentFuture;
      expect(sentAmount, '1575');
      expect(message, contains('Payment approved.'));
    },
    variant: _androidOnly,
  );

  testWidgets(
    'staff fallback can confirm the charity round-up and continue payment',
    (tester) async {
      String? sentAmount;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              sentAmount = arguments['amount']?.toString();
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.selectPaymentMethod('Credit Card');

      final paymentFuture = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);

      controller.confirmCharityRoundUp(true);
      await tester.pump(const Duration(milliseconds: 800));

      final message = await paymentFuture;
      expect(sentAmount, '2000');
      expect(message, contains('Payment approved.'));
      expect(
        controller.lastCustomerEvent,
        'Staff confirmed the customer accepted the charity round-up.',
      );
    },
    variant: _androidOnly,
  );

  testWidgets(
    'credit card payment temporarily hands the rear display to Mosambee',
    (tester) async {
      var openRearDisplayCalls = 0;
      var hideRearDisplayCalls = 0;
      final paymentCompleter = Completer<String>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hostChannel, (call) async {
            switch (call.method) {
              case 'getPresentationDisplays':
                return <Map<String, dynamic>>[
                  <String, dynamic>{
                    'displayId': 2,
                    'name': 'Sunmi-USBDisplay-Test',
                    'isDefaultDisplay': false,
                    'isSunmiUsbDisplay': true,
                    'isPresentationCategory': true,
                    'serial': 'TEST123',
                  },
                ];
              case 'prepareRearDisplay':
                return <String, dynamic>{
                  'prepared': true,
                  'displayId': 2,
                  'serial': 'TEST123',
                  'isSunmiUsbDisplay': true,
                };
              case 'openRearDisplay':
                openRearDisplayCalls++;
                return true;
              case 'hideRearDisplay':
                hideRearDisplayCalls++;
                return true;
              case 'transferDataToRear':
                return true;
              default:
                return null;
            }
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              await _sendPaymentLaunchState(
                stage: 'login_started',
                surface: 'rear',
              );
              return paymentCompleter.future;
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      final initialOpenFuture = controller.openRearDisplay();
      await tester.pump(const Duration(milliseconds: 600));
      await initialOpenFuture;
      controller.addProduct(controller.allProducts.first);
      controller.selectPaymentMethod('Credit Card');

      expect(controller.rearDisplayOpened, isTrue);
      expect(openRearDisplayCalls, 1);

      final paymentFuture = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);

      controller.confirmCharityRoundUp(true);
      await tester.pump(const Duration(milliseconds: 800));

      expect(controller.rearDisplayOpened, isFalse);
      expect(hideRearDisplayCalls, 0);
      expect(openRearDisplayCalls, 1);

      paymentCompleter.complete(
        '{"status":"success","message":"Payment approved."}',
      );
      await tester.pump(const Duration(milliseconds: 1800));

      final message = await paymentFuture;
      expect(message, contains('Payment approved.'));
      expect(hideRearDisplayCalls, 0);
      expect(openRearDisplayCalls, 2);
      expect(controller.rearDisplayOpened, isTrue);
    },
    variant: _androidOnly,
  );

  testWidgets(
    'staff can cancel the charity round-up prompt before card payment launches',
    (tester) async {
      var loginAndPayCalls = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              loginAndPayCalls++;
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.selectPaymentMethod('Credit Card');

      final paymentFuture = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);

      controller.cancelCharityRoundUpPrompt();
      await tester.pump(const Duration(milliseconds: 50));

      final message = await paymentFuture;
      expect(message, 'Card payment canceled.');
      expect(loginAndPayCalls, 0);
      expect(controller.showCharityRoundUpPrompt, isFalse);
    },
    variant: _androidOnly,
  );

  testWidgets(
    'split cash payments keep the order open until every share is paid',
    (tester) async {
      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.setSplitCount(2);
      controller.selectPaymentMethod('Cash');

      final firstPayment = controller.payAndPrint(cashTenderedAmount: 1.000);
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);
      controller.confirmCharityRoundUp(true);
      await tester.pump(const Duration(milliseconds: 800));
      final firstMessage = await firstPayment;

      expect(firstMessage, contains('Split payment 1 of 2 recorded'));
      expect(controller.cart, isNotEmpty);
      expect(controller.paymentStatus, 'Split payment pending');
      expect(fakeStorage._history, isEmpty);

      controller.selectPaymentMethod('Cash');
      final secondPayment = controller.payAndPrint(cashTenderedAmount: 1.000);
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);
      controller.confirmCharityRoundUp(false);
      await tester.pump(const Duration(milliseconds: 800));
      final secondMessage = await secondPayment;

      expect(secondMessage, contains('Split payment completed'));
      expect(controller.cart, isEmpty);
      expect(fakeStorage._history, hasLength(1));

      final completedSnapshot = fakeStorage._history.single.snapshot;
      final splitPayments =
          completedSnapshot.toMap()['splitPayments'] as List<dynamic>;
      expect(completedSnapshot.paymentMethod, 'Split Payment');
      expect(completedSnapshot.splitCount, 2);
      expect(splitPayments, hasLength(2));
      expect(splitPayments.first, containsPair('charityRoundUpAccepted', true));
      expect(splitPayments.first, containsPair('paidAmount', 1.000));
      expect(splitPayments.last, containsPair('charityRoundUpAccepted', false));
      expect(splitPayments.last, containsPair('paidAmount', 0.788));
      expect(
        splitPayments
            .map((payment) => (payment as Map)['baseAmount'] as double)
            .fold<double>(0, (sum, amount) => sum + amount),
        closeTo(completedSnapshot.total, 0.001),
      );
      expect(completedSnapshot.payableTotal, closeTo(1.788, 0.001));
    },
    variant: _androidOnly,
  );

  testWidgets(
    'each split card payment can make its own charity round-up decision',
    (tester) async {
      final sentAmounts = <String>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              sentAmounts.add(arguments['amount']?.toString() ?? '');
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);
      controller.setSplitCount(2);
      controller.selectPaymentMethod('Credit Card');

      final firstPayment = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);
      controller.confirmCharityRoundUp(true);
      await tester.pump(const Duration(milliseconds: 800));

      final firstMessage = await firstPayment;
      expect(firstMessage, contains('Split payment 1 of 2 recorded'));
      expect(controller.cart, isNotEmpty);
      expect(sentAmounts, <String>['1000']);

      controller.selectPaymentMethod('Credit Card');
      final secondPayment = controller.payAndPrint();
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);
      controller.confirmCharityRoundUp(false);
      await tester.pump(const Duration(milliseconds: 800));

      final secondMessage = await secondPayment;
      expect(secondMessage, contains('Split payment completed'));
      expect(sentAmounts, <String>['1000', '788']);

      final completedSnapshot = fakeStorage._history.single.snapshot;
      final splitPayments = completedSnapshot.toMap()['splitPayments'] as List;
      expect(splitPayments, hasLength(2));
      expect(splitPayments.first, containsPair('charityRoundUpAccepted', true));
      expect(splitPayments.first, containsPair('paidAmount', 1.000));
      expect(splitPayments.last, containsPair('charityRoundUpAccepted', false));
      expect(splitPayments.last, containsPair('paidAmount', 0.788));
      expect(completedSnapshot.payableTotal, closeTo(1.788, 0.001));
    },
    variant: _androidOnly,
  );

  testWidgets(
    'mixed cash and card payment charges the remaining card balance with round-up',
    (tester) async {
      String? sentAmount;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paymentChannel, (call) async {
            if (call.method == 'loginAndPay') {
              final arguments = Map<String, dynamic>.from(
                call.arguments as Map,
              );
              sentAmount = arguments['amount']?.toString();
              return '{"status":"success","message":"Payment approved."}';
            }
            return null;
          });

      final controller = PosController(orderStorage: fakeStorage);
      addTearDown(controller.dispose);

      await controller.init();
      controller.addProduct(controller.allProducts.first);

      final paymentFuture = controller.payMixedCashAndCard(cashAmount: 1.000);
      await tester.pump();

      expect(controller.showCharityRoundUpPrompt, isTrue);
      expect(controller.charityRoundUpAmount, closeTo(0.425, 0.0001));

      controller.confirmCharityRoundUp(true);
      await tester.pump(const Duration(milliseconds: 800));

      final message = await paymentFuture;
      expect(sentAmount, '1000');
      expect(message, contains('Split payment completed'));
      expect(fakeStorage._history, hasLength(1));

      final completedSnapshot = fakeStorage._history.single.snapshot;
      final splitPayments = completedSnapshot.toMap()['splitPayments'] as List;
      expect(completedSnapshot.paymentMethod, 'Split Payment');
      expect(completedSnapshot.splitCount, 2);
      expect(splitPayments, hasLength(2));
      expect(splitPayments.first, containsPair('paymentMethod', 'Cash'));
      expect(splitPayments.first, containsPair('baseAmount', 1.000));
      expect(splitPayments.first, containsPair('paidAmount', 1.000));
      expect(splitPayments.last, containsPair('paymentMethod', 'Credit Card'));
      expect(splitPayments.last, containsPair('baseAmount', 0.575));
      expect(splitPayments.last, containsPair('charityRoundUpAmount', 0.425));
      expect(splitPayments.last, containsPair('paidAmount', 1.000));
      expect(completedSnapshot.payableTotal, closeTo(2.000, 0.001));
    },
    variant: _androidOnly,
  );
}
