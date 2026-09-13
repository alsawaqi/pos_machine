import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'package:pos_machine/services/sunmi_receipt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'printer receives one customer slip and large reversal heading',
    () async {
      const channel = MethodChannel('sunmi_printer_plus');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final lines = buildReversalSlipLines(
        header: ['Merchant'],
        kind: 'refund',
        orderReference: 'O',
        originalReceiptNumber: 'R',
        originalMaskedCard: '433662XXXXXX5819',
        originalAuthCode: 'OLD',
        amountBaisas: 4750,
        currency: '0512',
        receipt: const SoftPosReceiptIdentifiers(
          transactionId: 'TX',
          rrn: 'RRN',
          authCode: 'AUTH',
        ),
        responseCode: '00',
        description: 'Approved',
        occurredAt: '2026-09-13',
        approverName: 'Manager',
      );
      expect(await SunmiReceiptService.printReversalSlip(lines), isTrue);
      final printed = calls.where((c) => c.method == 'printText').toList();
      expect(
        printed.map((c) => c.arguments['data']['text']).toList(),
        lines.map((r) => r.text).toList(),
      );
      expect(calls.where((c) => c.method == 'cutPaper'), hasLength(1));
    },
  );
}
