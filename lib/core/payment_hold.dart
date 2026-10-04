import 'dart:async';

import '../tenancy/business_identity.dart';

/// LAUNCH-P5 fix order 2 (T13) — "a payment is in progress".
///
/// A forced sign-out (the person was suspended — staff-status — or the
/// server refused their staff token) must not pull the till out from under
/// a payment: the card may already be charged, and the sale is recorded
/// only when the payment flow finishes. The sign-out waits for [idle] and
/// happens right after the payment completes or is abandoned.
///
/// In progress = any tender tracked by [BusinessBoundary.trackPayment] (the
/// till's cash / card / mixed / QR settlements), or an owner that says so
/// through [set] (the POS screen: a split under way, a QR checkout open).
abstract final class PaymentHold {
  static final Set<Object> _owners = Set.identity();
  static Completer<void>? _ownersIdle;

  /// Whether a payment is in progress now.
  static bool get active =>
      _owners.isNotEmpty || BusinessBoundary.paymentInFlight;

  /// [owner] has (or no longer has) a payment in progress.
  static void set(Object owner, bool busy) {
    if (busy) {
      _owners.add(owner);
      return;
    }
    if (!_owners.remove(owner) || _owners.isNotEmpty) return;
    final idle = _ownersIdle;
    _ownersIdle = null;
    idle?.complete();
  }

  /// Completes once no payment is in progress (at once when none is).
  static Future<void> idle() async {
    while (active) {
      final waits = <Future<void>>[
        if (BusinessBoundary.paymentInFlight) BusinessBoundary.paymentsSettled,
        if (_owners.isNotEmpty) (_ownersIdle ??= Completer<void>()).future,
      ];
      if (waits.isEmpty) break;
      await Future.any(waits);
    }
  }

  /// Tests only.
  static void reset() {
    _owners.clear();
    final idle = _ownersIdle;
    _ownersIdle = null;
    idle?.complete();
  }
}
