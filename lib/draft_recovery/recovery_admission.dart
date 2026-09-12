import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../qr_checkout/qr_checkout_models.dart';

/// Read-only, device-wide admission across every retained journal scope.
/// Callers must also exclude concurrent payment/request preparation while this
/// check and recovery journal creation run. No database is opened or repaired.
Future<void> assertRecoveryJournalsIdle({
  required Database checkout,
  required Database dineIn,
  required Database quick,
}) async {
  // Explicit columns also reject an empty but incomplete/missing schema. Do
  // not use the checkout store's scope/state filter: terminal-looking rows
  // still have to decode, and an older device scope may own an uncertain pay.
  final attempts = await checkout.query(
    'qr_checkout_attempts',
    columns: ['id', 'scope', 'state', 'payload'],
  );
  for (final row in attempts) {
    final attempt = _checkoutAttempt(row);
    if (!attempt.terminal) {
      throw StateError(
        'Resolve all saved checkouts before recovering a draft.',
      );
    }
  }

  // These journals contain unresolved requests only; malformed rows are also
  // blockers. No row from any scope may be ignored or deleted for admission.
  final rounds = await dineIn.query(
    'dine_in_requests',
    columns: [
      'scope',
      'table_id',
      'seating_uuid',
      'bill_uuid',
      'request_id',
      'payload',
    ],
    limit: 1,
  );
  if (rounds.isNotEmpty) {
    throw StateError(
      'Resolve all saved Dine-In requests before recovering a draft.',
    );
  }
  final additions = await quick.query(
    'qr_quick_requests',
    columns: ['scope', 'order_uuid', 'request_id', 'payload'],
    limit: 1,
  );
  if (additions.isNotEmpty) {
    throw StateError(
      'Resolve all saved quick-order requests before recovering a draft.',
    );
  }
}

CheckoutAttempt _checkoutAttempt(Map<String, Object?> row) {
  try {
    final attempt = CheckoutAttempt.decode(row['payload'] as String);
    if (attempt.id != row['id'] ||
        attempt.state != row['state'] ||
        row['scope'] is! String ||
        (row['scope'] as String).trim().isEmpty ||
        attempt.id.trim().isEmpty ||
        attempt.orderUuid.trim().isEmpty ||
        (attempt.orderId != null && attempt.orderId! < 1)) {
      throw const FormatException('Checkout journal columns disagree');
    }
    if (attempt.terminal) {
      // The normal decoder applies full payment validation to pending state.
      // Retained terminal events must satisfy those same immutable identities,
      // money and capture checks; changing the state must not hide corruption.
      if (attempt.event != null || attempt.state == 'paid') {
        CheckoutAttempt.decode(
          jsonEncode({...attempt.json, 'state': 'pending'}),
        );
      } else if (attempt.captures.isNotEmpty) {
        // Released/managed attempts may retain only partial physical tender
        // evidence. A released initial claim or managed uncertain claim may
        // have neither a reservation nor captures, which remains valid.
        final claim = CheckoutClaim(attempt.claim!);
        final plan = [
          for (final capture in attempt.captures)
            CheckoutTender(
              capture['method'] as String,
              checkoutInt(capture['amount_baisas']),
              change: checkoutInt(capture['change_given_baisas'] ?? 0),
            ),
        ];
        final captured = plan.fold(0, (sum, tender) => sum + tender.amount);
        if (attempt.orderId == null ||
            captured > claim.amount ||
            attempt.captures.any((capture) => capture['status'] != 'success')) {
          throw const FormatException('Invalid retained checkout captures');
        }
        validateCheckoutPlan(plan, captured);
      }
    }
    return attempt;
  } catch (_) {
    throw const FormatException(
      'Cannot verify the saved checkout journal. Keep app data.',
    );
  }
}
