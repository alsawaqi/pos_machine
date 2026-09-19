import '../models/pos_models.dart';
import '../services/server_receipt_history.dart';
import 'qr_checkout_models.dart';

Future<void> projectMachineCheckoutReceipt(
  ServerReceiptHistory history,
  CheckoutSnapshot? snapshot,
  CheckoutAttempt attempt,
) async {
  if (const {'refused', 'released', 'managed'}.contains(attempt.state)) {
    await history.removeProvisional(attempt.orderUuid);
    return;
  }
  final existing = await history.find(attempt.orderUuid);
  if (snapshot == null && existing == null) {
    throw StateError('Receipt details unavailable; keep the saved checkout');
  }
  final record = snapshot == null
      ? existing!
      : OrderHistoryRecord.fromServerJson({
          ...snapshot.order,
          'items': snapshot.lines
              .where(
                (line) => line['status'] != 'void' && (line['qty'] as num) > 0,
              )
              .toList(),
          'status': attempt.state == 'paid' ? 'paid' : 'pending',
          'receipt_number': attempt.state == 'paid'
              ? attempt.receiptNumber
              : null,
        }).snapshot.copyWith(
          serverReceipt: true,
          serverReceiptConfirmed: attempt.state == 'paid',
          tempReference: attempt.reference ?? snapshot.reference,
          paymentMethod: attempt.captures.map((c) => c['method']).join(' + '),
        );
  await history.record(
    record.copyWith(
      receiptNumber: attempt.state == 'paid' ? attempt.receiptNumber ?? '' : '',
      serverReceipt: true,
      serverReceiptConfirmed: attempt.state == 'paid',
    ),
  );
}
