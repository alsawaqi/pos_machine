import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'support/fake_order_storage.dart';

void main() {
  test(
    'table ACK preserves historical receipt and idempotently updates only canonical pending copy',
    () async {
      final storage = FakeOrderStorage();
      final history = ServerReceiptHistory(storage);
      await storage.saveCompletedOrder(
        OrderSnapshot.initial().copyWith(
          orderNumber: 104,
          receiptNumber: 'KLD-0104',
          serverOrderUuid: 'historical',
        ),
      );
      final old = jsonEncode(storage.history.single.snapshot.toMap());
      await history.record(
        OrderSnapshot.initial().copyWith(
          orderNumber: 1450,
          serverReceipt: true,
          serverOrderUuid: 'canonical',
          tempReference: 'T-009',
        ),
      );
      final row = OrderOutboxRow(
        orderUuid: 'canonical:pay',
        eventsJson: '[]',
        createdAt: DateTime.now(),
        attempts: 0,
        serverRejections: 0,
      );
      final events = <Map<String, dynamic>>[
        {
          'event_type': 'order.pay',
          'client_event_id': 'pay-1',
          'payload': {'order_uuid': 'canonical'},
        },
      ];
      final results = <Map<String, dynamic>>[
        {
          'client_event_id': 'pay-1',
          'status': 'processed',
          'result': {'status': 'paid', 'receipt_number': 'KLD-0106'},
        },
      ];
      await history.acknowledge(row, events, [
        {
          'client_event_id': 'foreign',
          'status': 'processed',
          'result': {'status': 'paid', 'receipt_number': 'WRONG'},
        },
      ]);
      expect((await history.find('canonical'))!.receiptNumber, isEmpty);
      await history.acknowledge(row, events, results);
      await history.acknowledge(row, events, results);
      expect(storage.history, hasLength(2));
      expect((await history.find('canonical'))!.receiptNumber, 'KLD-0106');
      expect(jsonEncode(storage.history.last.snapshot.toMap()), old);
      expect(
        storage.history.any((r) => r.snapshot.receiptNumber == 'KLD-0105'),
        false,
      );
      await expectLater(
        history.record(
          (await history.find(
            'canonical',
          ))!.copyWith(receiptNumber: 'KLD-0107'),
        ),
        throwsStateError,
      );
      expect((await history.find('canonical'))!.receiptNumber, 'KLD-0106');
    },
  );
}
