import 'package:sqflite/sqflite.dart';

import 'qr_checkout_controller.dart';
import 'qr_checkout_models.dart';

/// LAUNCH-P5 fix order 2 (T4) — QR and table-workspace payments taken at
/// this till hold the shift close like local sales.
///
/// They are kept in the checkout journal (`qr_checkout_attempts`), never in
/// the order outbox, so the close reads them here:
///  * an attempt since the shift opened that may have money but no server
///    acknowledgement ([holdingStates]) is "still sending" and blocks the
///    close;
///  * those and the acknowledged (`paid`) ones go into the close's
///    `order_uuids`, so the server checks it has every one.
class CheckoutCloseHold {
  CheckoutCloseHold({required this.db, required this.scope, this.resume});

  final Database db;
  final String scope;

  /// Builds a headless checkout controller over this journal, used to push
  /// a `pending` attempt's saved order.pay again (the same event; never a
  /// new tender). Null = no pushing (a test, or no server identity).
  final QrCheckoutController Function()? resume;

  /// Money may have been taken, the server has not acknowledged it:
  /// `capturing` (tender running or interrupted), `pending` (order.pay
  /// saved, no ACK), `uncertain` (the capture result is unknown), `refused`
  /// (the server refused the pay; a manager must resolve it).
  static const holdingStates = {'capturing', 'pending', 'uncertain', 'refused'};

  /// The attempts of this device since [openedAt] (one minute of clock
  /// slack, like the outbox check).
  Future<({List<CheckoutAttempt> unsent, List<String> orderUuids})> since(
    DateTime openedAt,
  ) async {
    final from = openedAt.subtract(const Duration(minutes: 1));
    final rows = await db.query(
      'qr_checkout_attempts',
      where: 'scope = ?',
      whereArgs: [scope],
    );
    final unsent = <CheckoutAttempt>[];
    final uuids = <String>[];
    for (final row in rows) {
      CheckoutAttempt attempt;
      try {
        attempt = CheckoutAttempt.decode(row['payload'] as String);
      } catch (_) {
        continue;
      }
      if (attempt.createdAt.isBefore(from)) continue;
      final holding = holdingStates.contains(attempt.state);
      if (holding) unsent.add(attempt);
      if ((holding || attempt.state == 'paid') &&
          attempt.orderUuid.isNotEmpty &&
          !uuids.contains(attempt.orderUuid)) {
        uuids.add(attempt.orderUuid);
      }
    }
    return (unsent: unsent, orderUuids: uuids);
  }

  /// Push this device's `pending` attempt again (its saved event, through
  /// the checkout controller's own acknowledgement path). Never throws.
  Future<void> flush() async {
    final build = resume;
    if (build == null) return;
    QrCheckoutController? checkout;
    try {
      checkout = build();
      await checkout.open(null);
      if (checkout.phase == CheckoutPhase.pending) {
        await checkout.retryAcknowledgement();
      }
    } catch (_) {
      // Still listed as sending below.
    } finally {
      checkout?.dispose();
    }
  }
}

/// A capture or tender that never runs from the close screen.
Future<CheckoutCapture> refuseCheckoutCapture(int _) async =>
    throw StateError('No tender from the shift close');
