import 'package:pos_machine/tenancy/business_identity.dart';
import '../tenancy/tenant_sqlite.dart';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'qr_checkout_models.dart';

/// Manager payment reviews of saved QR checkouts. The checkout rows stay
/// unchanged; a review row records the server-confirmed decision beside them.
const paymentReviewTable = 'qr_checkout_payment_reviews';

class LocalPaymentEvidence {
  LocalPaymentEvidence(this.row)
    : attempt = CheckoutAttempt.decode(row['payload'] as String) {
    if (attempt.id != row['id'] || attempt.state != row['state']) {
      throw StateError('Invalid checkout journal');
    }
  }
  final Map<String, Object?> row;
  final CheckoutAttempt attempt;
}

class PaymentReviewEvidence {
  const PaymentReviewEvidence({
    this.open = const [],
    this.saved = const [],
    this.sending = false,
  });

  /// Checkouts the payment screen still owns; they are finished there first.
  final List<LocalPaymentEvidence> open;

  /// Checkouts handed to a manager; the review settles these.
  final List<LocalPaymentEvidence> saved;

  /// A payment for this order is still waiting in the send queue.
  final bool sending;
  bool get blocked => open.isNotEmpty || sending;
  List<String> get attemptIds => [for (final e in saved) e.attempt.id];

  /// Plain audit text for the server (never a PIN or customer data).
  String get summary {
    final parts = [
      for (final e in saved)
        [
          e.attempt.id,
          'saved ${e.attempt.createdAt.toUtc().toIso8601String()}',
          for (final c in e.attempt.captures)
            '${c['method']} ${c['amount_baisas']}'
                '${c['change_given_baisas'] == null ? '' : ' change ${c['change_given_baisas']}'}',
          if (e.attempt.event != null) 'pay event sent',
          if (e.attempt.tenderMayHaveStarted == true) 'tender may have started',
        ].join('; '),
    ].join(' | ');
    return parts.length > 500 ? parts.substring(0, 500) : parts;
  }
}

Future<bool> _hasReviews(DatabaseExecutor db) async => (await db.query(
  'sqlite_master',
  where: 'type = ? AND name = ?',
  whereArgs: ['table', paymentReviewTable],
)).isNotEmpty;

/// attempt id -> decision ('paid' | 'not_paid'). Read-only.
Future<Map<String, String>> paymentReviewDecisions(DatabaseExecutor db) async {
  if (!await _hasReviews(db)) return {};
  return {
    for (final row in await db.query(
      paymentReviewTable,
      columns: ['attempt_id', 'decision'],
    ))
      row['attempt_id'] as String: row['decision'] as String,
  };
}

Future<PaymentReviewEvidence> loadPaymentReviewEvidence(
  DatabaseExecutor db,
  String scope,
  String uuid, {
  bool sending = false,
}) async {
  final reviewed = await paymentReviewDecisions(db);
  final open = <LocalPaymentEvidence>[];
  final saved = <LocalPaymentEvidence>[];
  for (final row in await db.query(
    'qr_checkout_attempts',
    where: 'scope = ?',
    whereArgs: [scope],
  )) {
    final evidence = LocalPaymentEvidence(row);
    if (evidence.attempt.orderUuid != uuid ||
        reviewed.containsKey(evidence.attempt.id)) {
      continue;
    }
    if (!evidence.attempt.terminal) {
      open.add(evidence);
    } else if (evidence.attempt.state == 'managed') {
      saved.add(evidence);
    }
  }
  return PaymentReviewEvidence(open: open, saved: saved, sending: sending);
}

/// Orders with a checkout handed to a manager and not yet reviewed.
Future<Set<String>> ordersWithUnreviewedPayments(
  DatabaseExecutor db,
  String scope,
) async {
  final reviewed = await paymentReviewDecisions(db);
  return {
    for (final row in await db.query(
      'qr_checkout_attempts',
      where: "scope = ? AND state = 'managed'",
      whereArgs: [scope],
    ))
      if (!reviewed.containsKey(row['id']))
        LocalPaymentEvidence(row).attempt.orderUuid,
  };
}

/// Records a server-confirmed review. Every reviewed checkout must be exactly
/// as the manager saw it; a replayed server answer records nothing twice.
Future<void> recordPaymentReview(
  Database db,
  String scope,
  String uuid,
  PaymentReviewEvidence evidence,
  String requestId,
  Map<String, dynamic> result,
) => db.transaction((txn) async {
  await txn.execute('''CREATE TABLE IF NOT EXISTS $paymentReviewTable (
      attempt_id TEXT PRIMARY KEY, order_uuid TEXT NOT NULL,
      scope TEXT NOT NULL, original_row TEXT NOT NULL,
      decision TEXT NOT NULL, reference TEXT NOT NULL,
      request_id TEXT NOT NULL, server_result TEXT NOT NULL,
      reviewed_at TEXT NOT NULL)''');
  if (BusinessBoundary.initialized)
    await ensureBusinessTable(txn, '$paymentReviewTable');
  for (final item in evidence.saved) {
    final found = await txn.query(
      'qr_checkout_attempts',
      where: 'id = ? AND scope = ?',
      whereArgs: [item.row['id'], scope],
    );
    if (found.length != 1 ||
        jsonEncode(found.single) != jsonEncode(item.row) ||
        item.attempt.orderUuid != uuid) {
      throw StateError('Saved checkout changed; review again');
    }
    await txn.insert(paymentReviewTable, {
      'attempt_id': item.attempt.id,
      'order_uuid': uuid,
      'scope': scope,
      'original_row': jsonEncode(item.row),
      'decision': result['decision'],
      'reference': result['reference'],
      'request_id': requestId,
      'server_result': jsonEncode(result),
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
});
