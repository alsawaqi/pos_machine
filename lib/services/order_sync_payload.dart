import 'dart:math';

import '../models/pos_models.dart';

/// Builds the pos_api `/device/sync/push` event batch for a completed order.
///
/// The wire contract (pos_api Sync handlers, money = integer BAISAS):
///   order.create → opens the pos_orders row + lines + add-ons
///   order.pay    → records the tender(s), flips it paid, deducts stock
///   donation.record (optional) → the card round-up → pos_roundup_donations
///
/// Pricing is snapshot-authoritative: the device's computed totals are trusted
/// (the server only validates the invariant subtotal − discount + tax == grand).
/// Events carry STABLE client_event_ids so a re-push (offline replay) settles
/// exactly once. This is a pure function — no I/O — so it is unit-testable.
class OrderSyncPayload {
  OrderSyncPayload({required this.orderUuid, required this.events});

  final String orderUuid;
  final List<Map<String, dynamic>> events;
}

/// OMR (double, 3 dp) → integer baisas (1 OMR = 1000 baisas).
int omrToBaisas(double omr) => (omr * 1000).round();

/// pos_machine order-type storage value → pos_api Order::TYPES.
String mapOrderType(String storageValue) {
  switch (storageValue) {
    case 'dine_in':
      return 'dine_in';
    case 'to_go':
      return 'to_go';
    case 'delivery':
      return 'delivery';
    case 'quick_order':
    default:
      return 'quick';
  }
}

/// pos_machine payment label → pos_api Payment::METHODS.
String mapPaymentMethod(String label) {
  final l = label.toLowerCase();
  // P-F5 — the bank's standalone terminal, checked BEFORE 'card' so a label
  // like "Bank Card POS" never silently records as our Soft POS card money
  // (bank_pos stays out of the bank-commission base server-side).
  if (l.contains('bank')) return 'bank_pos';
  if (l.contains('card')) return 'card';
  if (l.contains('gift')) return 'gift';
  if (l.contains('loyalty')) return 'loyalty';
  return 'cash';
}

/// Attach the Soft POS evidence to a CARD [tender] in place. No-op for cash /
/// other tenders, or when there is no charge result. Overwrites [tender]'s
/// status with the charge status (success | pending_reconciliation).
void _applyCardCharge(Map<String, dynamic> tender, CardCharge? charge) {
  if (tender['method'] != 'card' || charge == null) return;
  if (charge.softposReference != null) {
    tender['softpos_reference'] = charge.softposReference;
  }
  if (charge.softposAuthCode != null) {
    tender['softpos_auth_code'] = charge.softposAuthCode;
  }
  if (charge.bankResponse != null) {
    tender['bank_response'] = charge.bankResponse;
  }
  tender['status'] = charge.status;
}

/// RFC-4122 v4 UUID. [rng] is injectable so tests can be deterministic.
String uuidV4([Random? rng]) {
  final r = rng ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC-4122 variant
  String h(int x) => x.toRadixString(16).padLeft(2, '0');
  final s = b.map(h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

/// Build the order.create / order.pay (/ donation.record) events for [snapshot].
///
/// [lat]/[lng] = the device GPS at completion (required at a geofenced branch —
/// the server fails closed without it). [staffId]/[tableId] are sent when known.
OrderSyncPayload buildOrderSyncPayload(
  OrderSnapshot snapshot, {
  double? lat,
  double? lng,
  int? staffId,
  int? tableId,
  int? customerId,
  String? plateNumber,
  String? deliveryProviderName,
  CardCharge? cardCharge,
  List<int> loyaltyRuleIds = const <int>[],
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  // Reuse the uuid stamped on the snapshot at completion (so a later full-cancel
  // can emit a matching order.void); otherwise mint a fresh one.
  final orderUuid =
      snapshot.serverOrderUuid.isNotEmpty ? snapshot.serverOrderUuid : gen();

  Map<String, double>? gps;
  if (lat != null && lng != null) {
    gps = {'lat': lat, 'lng': lng};
  }

  final plate = (plateNumber != null && plateNumber.trim().isNotEmpty)
      ? plateNumber.trim()
      : null;

  // The order note carries the cashier note + the delivery provider (we record
  // the provider in the note since pos_orders has no provider column yet).
  final noteParts = <String>[];
  if (snapshot.note.trim().isNotEmpty) noteParts.add(snapshot.note.trim());
  if (deliveryProviderName != null && deliveryProviderName.trim().isNotEmpty) {
    noteParts.add('Delivery via ${deliveryProviderName.trim()}');
  }
  final note = noteParts.isEmpty ? null : noteParts.join(' | ');

  // ---- lines (+ add-ons) ----
  final lines = <Map<String, dynamic>>[];
  // Auto-applied per-line (product/category) discounts, emitted with a
  // line_index pointing at the line's position in [lines] (the server maps
  // line_index -> order_item).
  final lineDiscounts = <Map<String, dynamic>>[];
  var lineDiscountSum = 0.0;
  for (final raw in snapshot.items) {
    final productId = int.tryParse('${raw['id']}');
    if (productId == null) continue; // non-catalog (demo) product — cannot ref
    final qty = (raw['qty'] as num?)?.toInt() ?? 1;
    final unitPrice = (raw['unitPrice'] as num?)?.toDouble() ?? 0;
    final lineTotal = (raw['lineTotal'] as num?)?.toDouble() ?? 0;

    final addons = <Map<String, dynamic>>[];
    for (final m in (raw['modifiers'] as List? ?? const [])) {
      if (m is! Map) continue;
      final addOnId = int.tryParse('${m['id']}');
      if (addOnId == null) continue; // sample/demo modifier — not a real add-on
      addons.add({
        'add_on_id': addOnId,
        'price_delta_baisas': omrToBaisas((m['price'] as num?)?.toDouble() ?? 0),
      });
    }

    final notes = (raw['notes'] as String?)?.trim();
    final lineIndex = lines.length;
    lines.add({
      'product_id': productId,
      'qty': qty,
      'unit_price_baisas': omrToBaisas(unitPrice),
      'line_total_baisas': omrToBaisas(lineTotal),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (addons.isNotEmpty) 'addons': addons,
    });

    final lineDiscount = (raw['lineDiscount'] as num?)?.toDouble() ?? 0;
    if (lineDiscount > 0) {
      lineDiscountSum += lineDiscount;
      final label = (raw['lineDiscountLabel'] as String?) ?? '';
      lineDiscounts.add({
        'name': label.isEmpty ? 'Discount' : label,
        'amount_baisas': omrToBaisas(lineDiscount),
        if (raw['lineDiscountId'] != null) 'discount_id': raw['lineDiscountId'],
        if (raw['lineDiscountAmountType'] != null)
          'amount_type': raw['lineDiscountAmountType'],
        'line_index': lineIndex,
      });
    }
  }

  // ---- discounts (snapshot-authoritative) ----
  // snapshot.discountAmount is the COMBINED total (order-level + auto-applied
  // line discounts). Split it back out: the order-level entry carries only its
  // own portion, then each per-line discount is appended with its line_index.
  final discounts = <Map<String, dynamic>>[];
  final orderLevelDiscount = (snapshot.discountAmount - lineDiscountSum)
      .clamp(0.0, double.infinity)
      .toDouble();
  if (orderLevelDiscount > 0) {
    discounts.add({
      'name': snapshot.discountLabel.isEmpty ? 'Discount' : snapshot.discountLabel,
      'amount_baisas': omrToBaisas(orderLevelDiscount),
      // A merchant rule carries its id + amount_type so the server snapshots it
      // (by-rule report); a manual discount omits them.
      if (snapshot.discountId != null) 'discount_id': snapshot.discountId,
      if (snapshot.discountAmountType != null)
        'amount_type': snapshot.discountAmountType,
      // P-F4 — the cashier's reason for a manual/custom discount.
      if (snapshot.discountReason.isNotEmpty) 'reason': snapshot.discountReason,
    });
  }
  discounts.addAll(lineDiscounts);

  // ---- Phase B + P-F5 — comps: the manager's reasoned comp + per-line GIFT
  // write-offs (is_gift rows, no reason, no cap). Rows must sum EXACTLY to
  // comp_total_baisas (server-enforced), so gift rows take their face value
  // capped against the remaining budget (an order-level discount can shrink
  // the total write-off below the gifted lines' face value) and the reasoned
  // comp takes whatever the gifts left. ----
  final compBaisas = omrToBaisas(snapshot.compAmount);
  final comps = <Map<String, dynamic>>[];
  if (compBaisas > 0) {
    var remaining = compBaisas;
    final giftRows = <Map<String, dynamic>>[];
    for (var i = 0; i < snapshot.items.length; i++) {
      final giftAmount =
          (snapshot.items[i]['giftAmount'] as num?)?.toDouble() ?? 0;
      if (giftAmount <= 0) continue;
      final amount = omrToBaisas(giftAmount).clamp(0, remaining);
      if (amount <= 0) continue;
      remaining -= amount;
      giftRows.add({
        'is_gift': true,
        'amount_baisas': amount,
        'line_index': i,
        'staff_id': ?staffId,
      });
    }
    if (remaining > 0 && snapshot.compReasonId != null) {
      comps.add({
        'comp_reason_id': snapshot.compReasonId,
        'amount_baisas': remaining,
        if (snapshot.compLineIndex != null)
          'line_index': snapshot.compLineIndex,
        'staff_id': ?staffId,
      });
    }
    comps.addAll(giftRows);
  }

  final order = <String, dynamic>{
    'uuid': orderUuid,
    'order_type': mapOrderType(snapshot.orderType),
    'source': 'main_pos',
    'subtotal_baisas': omrToBaisas(snapshot.rawSubtotal),
    'discount_total_baisas': omrToBaisas(snapshot.discountAmount),
    if (comps.isNotEmpty) 'comp_total_baisas': compBaisas,
    'tax_total_baisas': omrToBaisas(snapshot.tax),
    'grand_total_baisas': omrToBaisas(snapshot.total),
    'opened_at': ts,
    'lines': lines,
    if (discounts.isNotEmpty) 'discounts': discounts,
    if (comps.isNotEmpty) 'comps': comps,
    'gps': ?gps,
    'staff_id': ?staffId,
    'table_id': ?tableId,
    'customer_id': ?customerId,
    'plate_number': ?plate,
    'note': ?note,
  };

  // ---- tenders: split into one row each, else a single tender. Sum is forced
  // to equal grand_total exactly (the server tolerates ±1 baisa). A CARD tender
  // carries its Soft POS evidence (reference / auth code / raw bank response)
  // and its status (success, or pending_reconciliation when force-recorded). ----
  final grandBaisas = omrToBaisas(snapshot.total);
  final payments = <Map<String, dynamic>>[];
  if (snapshot.splitPayments.isNotEmpty) {
    var acc = 0;
    for (var i = 0; i < snapshot.splitPayments.length; i++) {
      final rec = snapshot.splitPayments[i];
      final isLast = i == snapshot.splitPayments.length - 1;
      final amt = isLast ? (grandBaisas - acc) : omrToBaisas(rec.baseAmount);
      acc += amt;
      final tender = <String, dynamic>{
        'method': mapPaymentMethod(rec.paymentMethod),
        'amount_baisas': amt,
        'status': 'success',
      };
      _applyCardCharge(tender, rec.cardCharge);
      payments.add(tender);
    }
  } else {
    final tender = <String, dynamic>{
      'method': mapPaymentMethod(snapshot.paymentMethod),
      'amount_baisas': grandBaisas,
      'status': 'success',
    };
    _applyCardCharge(tender, cardCharge);
    payments.add(tender);
  }

  final payEvent = <String, dynamic>{
    'order_uuid': orderUuid,
    'paid_at': ts,
    'payments': payments,
    'gps': ?gps,
    // Loyalty EARN (v2 #3): naming the rules makes the server accrue points/
    // stamps for the order's customer under EACH (server-authoritative). Only
    // sent when a customer is attached and the company has active earn rules.
    if (loyaltyRuleIds.isNotEmpty) 'loyalty_rule_ids': loyaltyRuleIds,
  };

  // Loyalty REDEEM: the points OR stamps spent (their value is already on the
  // order as the discount). The server decrements the balance (strict —
  // over-balance fails). spend_based sends points; visit_based sends stamps.
  if (snapshot.loyaltyRedeemRuleId != null &&
      (snapshot.loyaltyRedeemPoints > 0 || snapshot.loyaltyRedeemStamps > 0)) {
    payEvent['loyalty_redeem'] = <String, dynamic>{
      'rule_id': snapshot.loyaltyRedeemRuleId,
      'points': snapshot.loyaltyRedeemPoints,
      'stamps': snapshot.loyaltyRedeemStamps,
    };
  }

  final events = <Map<String, dynamic>>[
    {
      'client_event_id': gen(),
      'event_type': 'order.create',
      'client_timestamp': ts,
      'payload': {'order': order},
    },
    {
      'client_event_id': gen(),
      'event_type': 'order.pay',
      'client_timestamp': ts,
      'payload': payEvent,
    },
  ];

  // ---- round-up donation: rides a CARD tender (the server attaches it to the
  // latest card payment). Sum split round-ups, else the single round-up. ----
  final hasCard = payments.any((p) => p['method'] == 'card');
  var roundUp = 0.0;
  if (snapshot.splitPayments.isNotEmpty) {
    for (final rec in snapshot.splitPayments) {
      if (rec.charityRoundUpAccepted) roundUp += rec.charityRoundUpAmount;
    }
  } else if (snapshot.charityRoundUpAccepted) {
    roundUp = snapshot.charityRoundUpAmount;
  }
  final roundUpBaisas = omrToBaisas(roundUp);
  if (hasCard && roundUpBaisas > 0) {
    events.add({
      'client_event_id': gen(),
      'event_type': 'donation.record',
      'client_timestamp': ts,
      'payload': {
        'order_uuid': orderUuid,
        'amount_baisas': roundUpBaisas,
        'occurred_at': ts,
      },
    });
  }

  return OrderSyncPayload(orderUuid: orderUuid, events: events);
}

/// Phase C2 — build the single `order.hold` event that mirrors a held cart
/// server-side (blueprint §6.7). The payload is order.create's `order` shape;
/// pos_api upserts by uuid: status=held, a re-hold replaces the mirror, the
/// final order.create (same uuid) flips it open, order.void discards it. No
/// GPS is sent — the server deliberately skips the geofence on holds (no money
/// or stock moves). Returns null when the draft has no pushable lines (a
/// demo-only cart cannot reference server products). Pure — unit-testable.
Map<String, dynamic>? buildOrderHoldEvent(
  OrderSessionDraft draft, {
  required String orderUuid,
  int? staffId,
  int? tableId,
  DateTime? now,
  String Function()? newUuid,
}) {
  if (orderUuid.isEmpty) return null;
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();

  final lines = <Map<String, dynamic>>[];
  for (final item in draft.items) {
    final productId = int.tryParse(item.product.id);
    if (productId == null) continue; // non-catalog (demo) product — cannot ref

    final addons = <Map<String, dynamic>>[];
    for (final m in item.modifiers) {
      final addOnId = int.tryParse(m.id);
      if (addOnId == null) continue; // sample/demo modifier — not a real add-on
      addons.add({
        'add_on_id': addOnId,
        'price_delta_baisas': omrToBaisas(m.price),
      });
    }

    final notes = item.normalizedNotes;
    lines.add({
      'product_id': productId,
      'qty': item.qty,
      'unit_price_baisas': omrToBaisas(item.unitPrice),
      'line_total_baisas': omrToBaisas(item.lineTotal),
      if (notes.isNotEmpty) 'notes': notes,
      if (addons.isNotEmpty) 'addons': addons,
    });
  }
  if (lines.isEmpty) return null;

  // The draft's order-level discount (auto line discounts are derived at
  // completion, not held). Invariant: raw − discount + tax == total, matching
  // the draft's own getters.
  final discountBaisas = omrToBaisas(draft.discountAmount);

  final order = <String, dynamic>{
    'uuid': orderUuid,
    'order_type': mapOrderType(draft.orderType.storageValue),
    'source': 'main_pos',
    'subtotal_baisas': omrToBaisas(draft.rawSubtotal),
    'discount_total_baisas': discountBaisas,
    'tax_total_baisas': omrToBaisas(draft.tax),
    'grand_total_baisas': omrToBaisas(draft.total),
    'opened_at': ts,
    'lines': lines,
    if (discountBaisas > 0)
      'discounts': [
        {
          'name':
              draft.discount.label.isEmpty ? 'Discount' : draft.discount.label,
          'amount_baisas': discountBaisas,
          if (draft.discount.discountId != null)
            'discount_id': draft.discount.discountId,
          if (draft.discount.amountType != null)
            'amount_type': draft.discount.amountType,
        }
      ],
    'staff_id': ?staffId,
    'table_id': ?tableId,
  };

  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'order.hold',
    'client_timestamp': ts,
    'payload': {'order': order},
  };
}

/// Build a single `order.void` event for [orderUuid] (the server matches by the
/// order_uuid that order.create used). The server voids the WHOLE order and
/// unwinds its inventory / loyalty / round-up / commission, idempotently. The
/// client_event_id is stable per build so a re-push (offline replay) is deduped.
///
/// [staffId]/[authorizedBy] ride along for the audit trail (the server ignores
/// keys it doesn't read). Pure + injectable for unit tests.
Map<String, dynamic> buildOrderVoidEvent({
  required String orderUuid,
  String? reason,
  // Phase B — the picked void reason code's id. The server snapshots it and
  // KEEPS inventory consumed when the reason says the food was made.
  int? voidReasonId,
  int? staffId,
  String? authorizedBy,
  DateTime? voidedAt,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (voidedAt ?? DateTime.now()).toUtc().toIso8601String();
  final cleanReason = reason?.trim();
  final cleanBy = authorizedBy?.trim();

  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'order.void',
    'client_timestamp': ts,
    'payload': <String, dynamic>{
      'order_uuid': orderUuid,
      'voided_at': ts,
      if (cleanReason != null && cleanReason.isNotEmpty) 'reason': cleanReason,
      'void_reason_id': ?voidReasonId,
      'staff_id': ?staffId,
      if (cleanBy != null && cleanBy.isNotEmpty) 'authorized_by': cleanBy,
    },
  };
}
