import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final acknowledged in [false, true]) {
    test(
      'shared table prints exactly once; server acknowledged=$acknowledged',
      () async {
        final storage = FakeOrderStorage();
        final c = PosController(orderStorage: storage);
        addTearDown(c.dispose);
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('sunmi_printer_plus'),
              (call) async {
                calls.add(call);
                return null;
              },
            );
        c.printReceipts = true;
        c.printKitchenTickets = false;
        c.isLiveSharedTable = () => true;
        c.verifyDiningTableTender = () async => null;
        c.prepareDiningTableTender =
            null; // External claim is outside this existing regression.
        c.onDiningTableFinalRound = (_) async => true;
        c.canonicalDiningBillUuid = () => 'canonical-bill';
        c.refreshServerReceipt = (snapshot) async {
          expect(calls.where((call) => call.method == 'cutPaper'), isEmpty);
          if (!acknowledged) return snapshot;
          final confirmed = snapshot.copyWith(receiptNumber: 'KLD-0106');
          await ServerReceiptHistory(storage).record(confirmed);
          return confirmed;
        };
        c.addProduct(
          const Product(id: '7', name: 'Coffee', category: 'Coffee', price: 1),
        );
        c.selectedOrderType = OrderType.dineIn;
        c.activeDiningTableId = '1';
        c.selectPaymentMethod('Cash');
        await c.payAndPrint(cashTenderedAmount: 1);
        expect(calls.where((call) => call.method == 'cutPaper'), hasLength(1));
        final printed = calls
            .where((call) => call.method == 'printText')
            .map((call) => call.arguments.toString())
            .join('\n');
        expect(printed.contains(pendingReceiptEn), !acknowledged);
        expect(printed.contains(pendingReceiptAr), !acknowledged);
        expect(printed.contains('KLD-0106'), acknowledged);
        expect(
          storage.history.single.snapshot.serverOrderUuid,
          'canonical-bill',
        );
      },
    );
  }
}
