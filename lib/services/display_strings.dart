/// Phase C4 — display mapping for SEMANTIC state values.
///
/// PosController state strings (paymentStatus, selectedPaymentMethod) and
/// OrderType.label are identity values: they are compared, persisted in
/// snapshots, pushed to the server, and printed on receipts — so they STAY
/// English in state. The UI localizes them at render time through these
/// mappers (unknown values fall through verbatim, e.g. server-authored
/// statuses from a newer API).
library;

import '../l10n/l10n.dart';
import '../models/pos_models.dart';

String localizedOrderType(L10n l10n, OrderType type) => switch (type) {
      OrderType.quickOrder => l10n.displayOrderTypeQuickOrder,
      OrderType.toGo => l10n.displayOrderTypeToGo,
      OrderType.delivery => l10n.displayOrderTypeDelivery,
      OrderType.dineIn => l10n.displayOrderTypeDineIn,
    };

/// Localize a stored payment-status value ('Waiting', 'Paid', …) for display.
String localizedPaymentStatus(L10n l10n, String value) => switch (value) {
      'Waiting' => l10n.displayStatusWaiting,
      'Paid' => l10n.displayStatusPaid,
      'Paid (pending reconciliation)' => l10n.displayStatusPaidPendingRecon,
      'Awaiting confirmation' => l10n.displayStatusAwaitingConfirmation,
      'Card charge not confirmed' => l10n.displayStatusCardNotConfirmed,
      'Payment canceled' => l10n.displayStatusPaymentCanceled,
      'Preparing payment' => l10n.displayStatusPreparingPayment,
      'Processing payment' => l10n.displayStatusProcessingPayment,
      'Split payment pending' => l10n.displayStatusSplitPending,
      'Canceled' => l10n.displayStatusCanceled,
      'Partially Canceled' => l10n.displayStatusPartiallyCanceled,
      'Void' => l10n.displayStatusVoid,
      'Refunded' => l10n.displayStatusRefunded,
      _ => value,
    };

/// Localize a stored payment-method value ('Cash', 'Credit Card', …).
String localizedPaymentMethod(L10n l10n, String value) => switch (value) {
      'Cash' => l10n.displayMethodCash,
      'Credit Card' => l10n.displayMethodCard,
      'Split Payment' => l10n.displayMethodSplit,
      'Gift' => l10n.displayMethodGift,
      'Bank POS' => l10n.displayMethodBankPos, // P-F5
      _ => value,
    };
