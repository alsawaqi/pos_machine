import '../data/db/app_database.dart';
import '../models/pos_models.dart';
import 'local_order_storage_service.dart';

const pendingReceiptEn = 'PAYMENT PENDING — NOT A FINAL RECEIPT';
const pendingReceiptAr = 'الدفع قيد التحقق — ليس إيصالاً نهائياً';

/// Projects acknowledgements for NEW server-owned receipts only. No allocation,
/// payment request, or printer operation is permitted in this projection.
class ServerReceiptHistory {
  ServerReceiptHistory(this.storage);
  final OrderStorageService storage;
  static Future<void> _tail = Future<void>.value();
  Future<OrderSnapshot?> find(String uuid) async =>
      (await storage.loadOrderHistory())
          .where(
            (r) =>
                r.snapshot.serverReceipt && r.snapshot.serverOrderUuid == uuid,
          )
          .firstOrNull
          ?.snapshot;

  Future<void> record(OrderSnapshot snapshot) {
    final operation = _tail.then((_) async {
      if (!snapshot.serverReceipt || snapshot.serverOrderUuid.isEmpty) {
        throw StateError('Missing canonical receipt identity');
      }
      final existing = (await storage.loadOrderHistory())
          .where(
            (r) =>
                r.snapshot.serverReceipt &&
                r.snapshot.serverOrderUuid == snapshot.serverOrderUuid,
          )
          .firstOrNull;
      if (existing == null) {
        await storage.saveCompletedOrder(snapshot);
      } else {
        if (existing.snapshot.serverReceiptConfirmed &&
            !snapshot.serverReceiptConfirmed) {
          return;
        }
        if (existing.snapshot.receiptNumber.isNotEmpty &&
            snapshot.receiptNumber.isEmpty) {
          return;
        }
        if (existing.snapshot.receiptNumber.isNotEmpty &&
            existing.snapshot.receiptNumber != snapshot.receiptNumber) {
          throw StateError('Receipt identity changed');
        }
        await storage.updateCompletedOrder(
          OrderHistoryRecord(
            id: existing.id,
            orderNumber: snapshot.orderNumber,
            orderType: existing.orderType,
            createdAt: existing.createdAt,
            snapshot: snapshot,
          ),
        );
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> acknowledge(
    OrderOutboxRow row,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> results,
  ) async {
    for (final event in events) {
      if (event['event_type'] != 'order.pay') continue;
      final payload = event['payload'];
      if (payload is! Map || payload['order_uuid'] is! String) continue;
      final ack = results
          .where(
            (r) =>
                r['client_event_id'] == event['client_event_id'] &&
                r['status'] == 'processed',
          )
          .firstOrNull;
      final result = ack?['result'];
      if (result is! Map ||
          result['status'] != 'paid' ||
          result['orphan_tender'] == true) {
        continue;
      }
      final number = result['receipt_number'];
      if (number != null && number is! String) continue;
      final snapshot = await find(payload['order_uuid'] as String);
      if (snapshot == null) continue;
      await record(
        snapshot.copyWith(
          receiptNumber: number as String? ?? '',
          serverReceiptConfirmed: true,
        ),
      );
    }
  }
}
