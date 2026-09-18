import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_receipt.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'support/fake_order_storage.dart';
import 'qr_checkout_fakes.dart';

class _NumberingOffGateway extends CheckoutFakeGateway {
  @override
  Future<List<Map<String, dynamic>>> push(Map<String, dynamic> event) async {
    final result = await super.push(event);
    return [
      for (final ack in result)
        {
          ...ack,
          'result': <String, dynamic>{
            ...checkoutMap(ack['result']),
            'receipt_number': null,
          },
        },
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'canonical receipt survives lost ACK and restart without retender or automatic print',
    () async {
      final storage = FakeOrderStorage();
      final history = ServerReceiptHistory(storage);
      await storage.saveCompletedOrder(
        OrderSnapshot.initial().copyWith(
          receiptNumber: 'KLD-0104',
          serverOrderUuid: 'old-bill',
        ),
      );
      final old = jsonEncode(storage.history.single.snapshot.toMap());
      final calls = <MethodCall>[];
      for (final channel in ['pos_handheld/printer', 'sunmi_printer_plus']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(channel), (call) async {
              calls.add(call);
              return true;
            });
      }
      final f = CheckoutFixture();
      QrCheckoutController create() => QrCheckoutController(
        gateway: f.api,
        store: f.store,
        now: () => f.now,
        newId: () => 'receipt-attempt',
        captureCard: (_) async => throw StateError('No bank operation'),
        captureBank: (_) async => throw StateError('No bank operation'),
        authorizeGift: () async => false,
        projectReceipt: (snapshot, attempt) =>
            projectMachineCheckoutReceipt(history, snapshot, attempt),
      );
      final c = create();
      await c.open('qr-bill');
      f.api.loseAck = true;
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(c.phase, CheckoutPhase.pending);
      final event = jsonEncode(f.store.value!.event);
      expect((await history.find('qr-bill'))!.displayOrderNumber, 'Q-007');
      c.dispose();
      final resumed = create();
      await resumed.open(null);
      expect(resumed.snapshot, isNull);
      f.api.loseAck = false;
      await resumed.retryAcknowledgement();
      expect(resumed.phase, CheckoutPhase.paid);
      expect(resumed.attempt!.receiptNumber, 'R-009');
      expect(f.api.commits, 1);
      expect(f.api.claims, 2);
      expect(jsonEncode(f.api.pushes.last), event);
      expect((await history.find('qr-bill'))!.receiptNumber, 'R-009');
      expect(storage.history, hasLength(2));
      expect(jsonEncode(storage.history.last.snapshot.toMap()), old);
      await projectMachineCheckoutReceipt(history, null, resumed.attempt!);
      expect(storage.history, hasLength(2));
      expect(
        calls,
        isEmpty,
        reason: 'An ACK must never print a second receipt.',
      );
      resumed.dispose();
    },
  );
  test(
    'confirmed payment with numbering disabled retains temporary identity without pending label',
    () async {
      final storage = FakeOrderStorage();
      final history = ServerReceiptHistory(storage);
      final api = _NumberingOffGateway();
      final store = MemoryCheckoutStore();
      final c = QrCheckoutController(
        gateway: api,
        store: store,
        now: () => checkoutTime,
        newId: () => 'disabled-numbering',
        captureCard: (_) async => throw StateError('No bank operation'),
        captureBank: (_) async => throw StateError('No bank operation'),
        authorizeGift: () async => false,
        projectReceipt: (snapshot, attempt) =>
            projectMachineCheckoutReceipt(history, snapshot, attempt),
      );
      await c.open('qr-bill');
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(c.phase, CheckoutPhase.paid);
      expect(c.attempt!.receiptNumber, isNull);
      final receipt = (await history.find('qr-bill'))!;
      expect(receipt.displayOrderNumber, 'Q-007');
      expect(receipt.receiptPending, false);
      expect(receipt.serverOrderUuid, 'qr-bill');
      expect(api.commits, 1);
      c.dispose();
    },
  );
}
