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
  String? currentScope,
}) async {
  // Explicit columns also reject an empty but incomplete/missing schema. Do
  // not use the checkout store's scope/state filter: terminal-looking rows
  // still have to decode, and an older device scope may own an uncertain pay.
  final attempts = await checkout.query(
    'qr_checkout_attempts',
    columns: ['id', 'scope', 'state', 'payload'],
  );
  for (final row in attempts) {
    final attempt = recoveryCheckoutAttempt(row);
    if (checkoutMoneyUncertain(attempt)) {
      throw StateError(
        'Check payment result for the saved checkout before recovering a draft. Do not take payment again.',
      );
    }
    if (!attempt.terminal && !foreignReleaseCanRetire(row, currentScope)) {
      throw StateError(
        'Open the saved order and retry its release or use Check payment result before recovering this draft.',
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

CheckoutAttempt recoveryCheckoutAttempt(Map<String, Object?> row) {
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

// Unknown older tender evidence is allowed ONLY on the pre-tender release path,
// never on capturing/uncertain/payment-event paths.
bool checkoutMoneyUncertain(CheckoutAttempt attempt) =>
    const {
      'capturing',
      'pending',
      'refused',
      'uncertain',
    }.contains(attempt.state) ||
    (!attempt.terminal &&
        (attempt.event != null ||
            attempt.captures.isNotEmpty ||
            attempt.tenderMayHaveStarted == true ||
            attempt.receiptNumber != null)) ||
    (attempt.state == 'managed' &&
        (attempt.captures.any((c) => c['capture_uncertain'] == true) ||
            (attempt.tenderMayHaveStarted == true && attempt.event == null)));

bool foreignReleaseCanRetire(Map<String, Object?> row, String? currentScope) {
  bool validScope(Object? scope) {
    try {
      final parts = jsonDecode(scope as String);
      return parts is List &&
          parts.length == 4 &&
          parts[0] is String &&
          Uri.parse(parts[0] as String).hasAuthority &&
          parts[1] is int &&
          parts[2] is int &&
          parts[3] is String &&
          (parts[3] as String).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final attempt = recoveryCheckoutAttempt(row);
  return validScope(currentScope) &&
      validScope(row['scope']) &&
      row['scope'] != currentScope &&
      attempt.state == 'releasing' &&
      attempt.event == null &&
      attempt.captures.isEmpty &&
      attempt.receiptNumber == null &&
      attempt.tenderMayHaveStarted != true;
}

String recoveryMessage(Object? error, {required bool arabic}) {
  final raw = error.toString();
  if (raw.contains('Check payment result') || raw.contains('saved checkouts')) {
    return arabic
        ? 'افتح الطلب المحفوظ وأعد محاولة تحرير الحجز أو اختر «التحقق من نتيجة الدفع». لا تأخذ دفعة أخرى. للحجز من خادم سابق، افتح «استعادة عمليات الدفع المحفوظة» في الإعدادات.'
        : 'Open the saved order and retry its release or choose Check payment result. Do not take payment again. For an old server reservation, open Saved checkout recovery in Settings.';
  }
  if (raw.contains('Dine-In requests') ||
      raw.contains('quick-order requests')) {
    return arabic
        ? 'أكمل الطلبات المحفوظة في طلبات QR أو داخل المطعم ثم أعد فتح الاستعادة. احتفظ ببيانات التطبيق.'
        : 'Finish the saved requests in QR Orders or Dine In, then reopen recovery. Keep app data.';
  }
  return arabic
      ? 'تعذر التحقق من السجلات المحفوظة. احتفظ بكل النسخ الأصلية وبيانات التطبيق. أكمل أي دفع أو مزامنة معلّقة، ثم أعد فتح الاستعادة أو اطلب مساعدة المشرف.'
      : 'Could not verify the saved records. Keep every original copy and app data. Finish pending payment or sync work, then reopen recovery or ask a manager for help.';
}
