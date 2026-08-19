import 'dart:math';

import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import '../models/pos_models.dart';
import 'pricing_adapter.dart';

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
  // Joined tables (v2) — the EXTRA tables this one shared order covered.
  List<int> joinedTableIds = const <int>[],
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
  final priced = frozenPriceResultFromSnapshot(snapshot);
  // Reuse the uuid stamped on the snapshot at completion (so a later full-cancel
  // can emit a matching order.void); otherwise mint a fresh one.
  final orderUuid = snapshot.serverOrderUuid.isNotEmpty
      ? snapshot.serverOrderUuid
      : gen();

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
  final wireLineIndexBySnapshotIndex = <int, int>{};
  for (
    var snapshotIndex = 0;
    snapshotIndex < snapshot.items.length;
    snapshotIndex++
  ) {
    final raw = snapshot.items[snapshotIndex];
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
        'price_delta_baisas': omrToBaisas(
          (m['price'] as num?)?.toDouble() ?? 0,
        ),
      });
    }

    final notes = (raw['notes'] as String?)?.trim();
    final lineIndex = lines.length;
    wireLineIndexBySnapshotIndex[snapshotIndex] = lineIndex;
    lines.add({
      'product_id': productId,
      'qty': qty,
      'unit_price_baisas': omrToBaisas(unitPrice),
      'line_total_baisas': omrToBaisas(lineTotal),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (addons.isNotEmpty) 'addons': addons,
    });
  }
  for (final result in priced.lineDiscounts) {
    final lineIndex = wireLineIndexBySnapshotIndex[result.lineIndex];
    if (lineIndex == null || result.amountBaisas <= 0) continue;
    lineDiscounts.add({
      'name': result.label.isEmpty ? 'Discount' : result.label,
      'amount_baisas': result.amountBaisas,
      if (result.ruleId != null) 'discount_id': result.ruleId,
      if (result.amountType != null) 'amount_type': result.amountType,
      'line_index': lineIndex,
    });
  }

  // ---- discounts (snapshot-authoritative) ----
  // snapshot.discountAmount is the COMBINED total (order-level + auto-applied
  // line discounts + applied OFFERS). Split it back out: the order-level
  // entry carries only its own portion; line discounts and offer allocations
  // are appended as their own rows (offers carry offer_id for the by-offer
  // report).
  final discounts = <Map<String, dynamic>>[];
  final offerEntries = <Map<String, dynamic>>[];
  for (final offer in priced.appliedOffers) {
    for (final entry in offer.lineAmountsBaisas.entries) {
      if (entry.value <= 0) continue;
      offerEntries.add({
        'name': offer.name,
        'amount_baisas': entry.value,
        'offer_id': offer.offerId,
        'line_index': entry.key,
      });
    }
    if (offer.orderAmountBaisas > 0) {
      offerEntries.add({
        'name': offer.name,
        'amount_baisas': offer.orderAmountBaisas,
        'offer_id': offer.offerId,
      });
    }
  }
  if (priced.orderDiscountRowBaisas > 0) {
    discounts.add({
      'name': snapshot.discountLabel.isEmpty
          ? 'Discount'
          : snapshot.discountLabel,
      'amount_baisas': priced.orderDiscountRowBaisas,
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
  discounts.addAll(offerEntries);

  // ---- Phase B + P-F5 — comps: the manager's reasoned comp + per-line GIFT
  // write-offs (is_gift rows, no reason, no cap). Rows must sum EXACTLY to
  // comp_total_baisas (server-enforced), so gift rows take their face value
  // capped against the remaining budget (an order-level discount can shrink
  // the total write-off below the gifted lines' face value) and the reasoned
  // comp takes whatever the gifts left. ----
  final compBaisas = priced.compTotalBaisas;
  final comps = <Map<String, dynamic>>[];
  if (compBaisas > 0) {
    final rows = pricing.compWireRowsFor(
      giftAmountsBaisas: priced.giftAmountsBaisas,
      compTotalBaisas: priced.compTotalBaisas,
      comp: frozenCompSelectionFromSnapshot(snapshot),
    );
    // The helper returns budget order (gifts first). The established wire is
    // reasoned row first, then gifts, so emit in that compatibility order.
    for (final row in rows.where((row) => !row.isGift)) {
      if (row.reasonId == null) continue;
      comps.add({
        'comp_reason_id': row.reasonId,
        'amount_baisas': row.amountBaisas,
        if (row.lineIndex != null) 'line_index': row.lineIndex,
        if (row.lineIndex != null && snapshot.compQty != null)
          'qty': snapshot.compQty,
        'staff_id': ?staffId,
        if (snapshot.compReasonName.isNotEmpty) 'note': snapshot.compReasonName,
      });
    }
    for (final row in rows.where((row) => row.isGift)) {
      comps.add({
        'is_gift': true,
        'amount_baisas': row.amountBaisas,
        'line_index': row.lineIndex,
        'staff_id': ?staffId,
      });
    }
  }

  final order = <String, dynamic>{
    'uuid': orderUuid,
    'order_type': mapOrderType(snapshot.orderType),
    'source': 'main_pos',
    // P-F8 — the merchant's sequential receipt number, when one was
    // allocated (offline orders go up without one).
    if (snapshot.receiptNumber.isNotEmpty)
      'receipt_number': snapshot.receiptNumber,
    'subtotal_baisas': priced.rawSubtotalBaisas,
    'discount_total_baisas': priced.discountTotalBaisas,
    if (comps.isNotEmpty) 'comp_total_baisas': compBaisas,
    'tax_total_baisas': priced.taxTotalBaisas,
    'grand_total_baisas': priced.grandTotalBaisas,
    'opened_at': ts,
    'lines': lines,
    if (discounts.isNotEmpty) 'discounts': discounts,
    if (comps.isNotEmpty) 'comps': comps,
    'gps': ?gps,
    'staff_id': ?staffId,
    'table_id': ?tableId,
    if (joinedTableIds.isNotEmpty) 'joined_table_ids': joinedTableIds,
    'customer_id': ?customerId,
    'plate_number': ?plate,
    'note': ?note,
  };

  // ---- tenders: split into one row each, else a single tender. Sum is forced
  // to equal grand_total exactly (the server tolerates ±1 baisa). A CARD tender
  // carries its Soft POS evidence (reference / auth code / raw bank response)
  // and its status (success, or pending_reconciliation when force-recorded). ----
  final grandBaisas = priced.grandTotalBaisas;
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

  // P-G7 — a NO-TENDER delivery-provider order (the Proceed popup set a
  // provider reference): the second event is order.deliver, never order.pay.
  // The server lands it pending_verification, consumes inventory, and the
  // merchant's Deliveries page settles the money later. No loyalty, no
  // round-up, no tenders by design. Deliberately NOT conditioned on the
  // provider id: a reference-bearing order with a somehow-missing provider
  // must FAIL server-side (provider_id required) rather than silently
  // become a phantom paid-cash sale via the pay branch.
  final isPendingDelivery =
      snapshot.orderType == 'delivery' && snapshot.deliveryReference.isNotEmpty;

  final deliverEvent = <String, dynamic>{
    'order_uuid': orderUuid,
    'delivered_at': ts,
    'delivery': <String, dynamic>{
      'provider_id': snapshot.deliveryProviderId,
      'reference': snapshot.deliveryReference,
      if (snapshot.customerReferenceNumber.trim().isNotEmpty)
        'customer_phone': snapshot.customerReferenceNumber.trim(),
      if (snapshot.deliveryDriverPhone.trim().isNotEmpty)
        'driver_phone': snapshot.deliveryDriverPhone.trim(),
    },
    'gps': ?gps,
  };

  final events = <Map<String, dynamic>>[
    {
      'client_event_id': gen(),
      'event_type': 'order.create',
      'client_timestamp': ts,
      'payload': {'order': order},
    },
    {
      'client_event_id': gen(),
      'event_type': isPendingDelivery ? 'order.deliver' : 'order.pay',
      'client_timestamp': ts,
      'payload': isPendingDelivery ? deliverEvent : payEvent,
    },
  ];

  // ---- round-up donations: each accepted round-up rides ITS OWN card leg.
  // One donation.record per rounding card leg, carrying payment_index — the
  // leg's position in payments[] (the server inserts payment rows in array
  // order, so the index maps to the exact pos_payments row). Every charity
  // transaction therefore traces to the guest who rounded, even when two
  // card guests in one split both round up. Non-card legs can never round
  // (canOfferCharityRoundUp is card-only); a stale flag on one is skipped
  // defensively — never transmit a donation with no card charge behind it. ----
  final donationLegs = <Map<String, int>>[];
  if (snapshot.splitPayments.isNotEmpty) {
    for (var i = 0; i < snapshot.splitPayments.length; i++) {
      final rec = snapshot.splitPayments[i];
      final legBaisas = omrToBaisas(rec.charityRoundUpAmount);
      if (rec.charityRoundUpAccepted &&
          legBaisas > 0 &&
          payments[i]['method'] == 'card') {
        donationLegs.add({'index': i, 'baisas': legBaisas});
      }
    }
  } else if (snapshot.charityRoundUpAccepted) {
    final singleBaisas = omrToBaisas(snapshot.charityRoundUpAmount);
    final cardIndex = payments.indexWhere((p) => p['method'] == 'card');
    if (singleBaisas > 0 && cardIndex >= 0) {
      donationLegs.add({'index': cardIndex, 'baisas': singleBaisas});
    }
  }
  for (final leg in donationLegs) {
    events.add({
      'client_event_id': gen(),
      'event_type': 'donation.record',
      'client_timestamp': ts,
      'payload': {
        'order_uuid': orderUuid,
        'amount_baisas': leg['baisas'],
        'payment_index': leg['index'],
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
  // Joined tables (v2) — the EXTRA tables this held order's party covered.
  List<int> joinedTableIds = const <int>[],
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
          'name': draft.discount.label.isEmpty
              ? 'Discount'
              : draft.discount.label,
          'amount_baisas': discountBaisas,
          if (draft.discount.discountId != null)
            'discount_id': draft.discount.discountId,
          if (draft.discount.amountType != null)
            'amount_type': draft.discount.amountType,
        },
      ],
    'staff_id': ?staffId,
    'table_id': ?tableId,
    if (joinedTableIds.isNotEmpty) 'joined_table_ids': joinedTableIds,
  };

  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'order.hold',
    'client_timestamp': ts,
    'payload': {'order': order},
  };
}

/// Build a single `order.transfer` event: the current cart parked as a held
/// mirror ADDRESSED to another device in the same branch (the send leg of
/// device↔device order transfer). The payload is exactly order.hold's `order`
/// block plus `target_device_id` — the server upserts it as held, stamps the
/// target, and the target device claims it from its inbox
/// (POST /device/transfers/{uuid}/claim). Pushed ONLINE with an inline ACK
/// (never the durable outbox — you transferred to a live colleague's
/// terminal). Returns null when the draft has no pushable lines. Pure.
Map<String, dynamic>? buildOrderTransferEvent(
  OrderSessionDraft draft, {
  required String orderUuid,
  required int targetDeviceId,
  int? staffId,
  int? tableId,
  List<int> joinedTableIds = const <int>[],
  DateTime? now,
  String Function()? newUuid,
}) {
  final hold = buildOrderHoldEvent(
    draft,
    orderUuid: orderUuid,
    staffId: staffId,
    tableId: tableId,
    joinedTableIds: joinedTableIds,
    now: now,
    newUuid: newUuid,
  );
  if (hold == null) return null;

  return <String, dynamic>{
    ...hold,
    'event_type': 'order.transfer',
    'payload': <String, dynamic>{
      'target_device_id': targetDeviceId,
      ...(hold['payload'] as Map<String, dynamic>),
    },
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
