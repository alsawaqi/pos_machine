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
  if (l.contains('card')) return 'card';
  if (l.contains('gift')) return 'gift';
  if (l.contains('loyalty')) return 'loyalty';
  return 'cash';
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
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  final orderUuid = gen();

  Map<String, double>? gps;
  if (lat != null && lng != null) {
    gps = {'lat': lat, 'lng': lng};
  }

  // ---- lines (+ add-ons) ----
  final lines = <Map<String, dynamic>>[];
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
    lines.add({
      'product_id': productId,
      'qty': qty,
      'unit_price_baisas': omrToBaisas(unitPrice),
      'line_total_baisas': omrToBaisas(lineTotal),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (addons.isNotEmpty) 'addons': addons,
    });
  }

  // ---- order-level discount (snapshot-authoritative) ----
  final discounts = <Map<String, dynamic>>[];
  if (snapshot.discountAmount > 0) {
    discounts.add({
      'name': snapshot.discountLabel.isEmpty ? 'Discount' : snapshot.discountLabel,
      'amount_baisas': omrToBaisas(snapshot.discountAmount),
    });
  }

  final order = <String, dynamic>{
    'uuid': orderUuid,
    'order_type': mapOrderType(snapshot.orderType),
    'source': 'main_pos',
    'subtotal_baisas': omrToBaisas(snapshot.rawSubtotal),
    'discount_total_baisas': omrToBaisas(snapshot.discountAmount),
    'tax_total_baisas': omrToBaisas(snapshot.tax),
    'grand_total_baisas': omrToBaisas(snapshot.total),
    'opened_at': ts,
    'lines': lines,
    if (discounts.isNotEmpty) 'discounts': discounts,
    'gps': ?gps,
    'staff_id': ?staffId,
    'table_id': ?tableId,
    if (snapshot.note.trim().isNotEmpty) 'note': snapshot.note.trim(),
  };

  // ---- tenders: split into one row each, else a single tender. Sum is forced
  // to equal grand_total exactly (the server tolerates ±1 baisa). ----
  final grandBaisas = omrToBaisas(snapshot.total);
  final payments = <Map<String, dynamic>>[];
  if (snapshot.splitPayments.isNotEmpty) {
    var acc = 0;
    for (var i = 0; i < snapshot.splitPayments.length; i++) {
      final rec = snapshot.splitPayments[i];
      final isLast = i == snapshot.splitPayments.length - 1;
      final amt = isLast ? (grandBaisas - acc) : omrToBaisas(rec.baseAmount);
      acc += amt;
      payments.add({
        'method': mapPaymentMethod(rec.paymentMethod),
        'amount_baisas': amt,
        'status': 'success',
      });
    }
  } else {
    payments.add({
      'method': mapPaymentMethod(snapshot.paymentMethod),
      'amount_baisas': grandBaisas,
      'status': 'success',
    });
  }

  final payEvent = <String, dynamic>{
    'order_uuid': orderUuid,
    'paid_at': ts,
    'payments': payments,
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
