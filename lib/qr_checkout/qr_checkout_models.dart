import 'dart:convert';
import 'dart:math';

Map<String, dynamic> checkoutMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);

/// Explicit server capability; source alone cannot authorize staff recovery.
bool hasStaffTableCheckoutPolicy(Map<String, dynamic>? bill) =>
    bill != null &&
    const {'main_pos', 'handheld'}.contains(bill['source']) &&
    bill['checkout_policy'] == 'staff_table_claim_v1';

Object? _freeze(Object? value) => switch (value) {
  Map value => Map<String, dynamic>.unmodifiable(
    value.map((k, v) => MapEntry(k as String, _freeze(v))),
  ),
  List value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
Map<String, dynamic> frozenCheckoutMap(Map<String, dynamic> value) =>
    _freeze(value) as Map<String, dynamic>;

String checkoutUuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

int checkoutInt(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid server money');
  }
  return value;
}

class CheckoutClaim {
  CheckoutClaim(Map<String, dynamic> json)
    : uuid = json['order_uuid'] as String,
      amount = checkoutInt(json['charge_amount_baisas']),
      claimedAt = DateTime.parse(json['charge_claimed_at'] as String),
      deadline = DateTime.parse(json['charge_deadline_at'] as String),
      replay = json['already_claimed_by_this_device'] == true {
    if (uuid.isEmpty ||
        json['status'] != 'awaiting_payment' ||
        json['already_claimed_by_this_device'] is! bool ||
        !deadline.isAfter(claimedAt)) {
      throw const FormatException('Invalid settlement claim');
    }
  }
  final String uuid;
  final int amount;
  final DateTime claimedAt;
  final DateTime deadline;
  final bool replay;
  Map<String, dynamic> get json => {
    'order_uuid': uuid,
    'status': 'awaiting_payment',
    'charge_amount_baisas': amount,
    'charge_claimed_at': claimedAt.toUtc().toIso8601String(),
    'charge_deadline_at': deadline.toUtc().toIso8601String(),
    'already_claimed_by_this_device': replay,
  };
  bool sameReservation(CheckoutClaim other) =>
      uuid == other.uuid &&
      amount == other.amount &&
      claimedAt.isAtSameMomentAs(other.claimedAt) &&
      deadline.isAtSameMomentAs(other.deadline);
}

/// Immutable server display data, not a cart/pricing input. Never persisted.
class CheckoutSnapshot {
  CheckoutSnapshot(Map<String, dynamic> data, CheckoutClaim claim)
    : order = frozenCheckoutMap(checkoutMap(data['order'])),
      customer = data['customer'] == null
          ? null
          : frozenCheckoutMap(checkoutMap(data['customer'])) {
    final identity = checkoutMap(data['claim']);
    if (order['uuid'] != claim.uuid ||
        !(order['source'] == 'qr_web' ||
            (hasStaffTableCheckoutPolicy(order) &&
                order['order_type'] == 'dine_in' &&
                order['table_id'] is int &&
                (order['table_id'] as int) > 0)) ||
        order['status'] != 'awaiting_payment' ||
        !((order['order_type'] == 'quick' && order['table_id'] == null) ||
            (order['order_type'] == 'dine_in' && order['table_id'] is int)) ||
        identity['order_uuid'] != claim.uuid ||
        checkoutInt(identity['charge_amount_baisas']) != claim.amount ||
        !DateTime.parse(
          identity['charge_claimed_at'] as String,
        ).isAtSameMomentAs(claim.claimedAt) ||
        !DateTime.parse(
          identity['charge_deadline_at'] as String,
        ).isAtSameMomentAs(claim.deadline) ||
        checkoutInt(order['grand_total_baisas']) != claim.amount ||
        order['id'] is! int ||
        (order['id'] as int) < 1 ||
        order['items'] is! List) {
      throw const FormatException('Checkout does not match the reservation');
    }
    for (final key in [
      'subtotal_baisas',
      'discount_total_baisas',
      'comp_total_baisas',
      'tax_total_baisas',
    ]) {
      checkoutInt(order[key]);
    }
    for (final line in lines) {
      checkoutInt(line['unit_price_baisas']);
      checkoutInt(line['line_total_baisas']);
      if (line['qty'] is! num ||
          !(line['qty'] as num).isFinite ||
          (line['qty'] as num) < 0 ||
          line['product_name'] is! String) {
        throw const FormatException('Invalid server item');
      }
    }
  }
  final Map<String, dynamic> order;
  final Map<String, dynamic>? customer;
  String get uuid => order['uuid'] as String;
  int get id => order['id'] as int;
  int get total => order['grand_total_baisas'] as int;
  String get reference =>
      (order['temp_reference'] ?? order['receipt_number'] ?? uuid).toString();
  List<Map<String, dynamic>> get lines =>
      (order['items'] as List).map(checkoutMap).toList();
  String get customerLabel => [
    customer?['name'],
    customer?['phone'],
  ].whereType<String>().where((v) => v.isNotEmpty).join(' · ');
}

class CheckoutTender {
  const CheckoutTender(this.method, this.amount, {this.change = 0});
  final String method;
  final int amount;
  final int change;
  Map<String, dynamic> get json => {
    'method': method,
    'amount_baisas': amount,
    'status': 'success',
    if (method == 'cash' && change > 0) 'change_given_baisas': change,
  };
}

void validateCheckoutPlan(List<CheckoutTender> plan, int frozenAmount) {
  if (plan.isEmpty ||
      plan.length > 20 ||
      plan.any(
        (leg) =>
            !const ['cash', 'card', 'bank_pos', 'gift'].contains(leg.method) ||
            leg.amount < 0 ||
            (plan.length > 1 && leg.amount == 0) ||
            leg.change < 0 ||
            (leg.method != 'cash' && leg.change != 0),
      ) ||
      plan.fold(0, (sum, leg) => sum + leg.amount) != frozenAmount ||
      (plan.any((leg) => leg.method == 'gift') && plan.length != 1)) {
    throw const FormatException(
      'Tender plan must cover the frozen bill exactly',
    );
  }
}

enum CheckoutCaptureState { approved, cancelled, notDispatched, uncertain }

class CheckoutCapture {
  const CheckoutCapture(this.state, {this.evidence = const {}});
  final CheckoutCaptureState state;
  final Map<String, dynamic> evidence;
}

/// Contains payment evidence/identity only; never customer phone, cart or secrets.
class CheckoutAttempt {
  CheckoutAttempt({
    required this.id,
    required this.orderUuid,
    required this.state,
    required this.createdAt,
    Map<String, dynamic>? claim,
    this.orderId,
    this.reference,
    Map<String, dynamic>? event,
    List<Map<String, dynamic>> captures = const [],
    this.receiptNumber,
    this.tenderMayHaveStarted,
  }) : claim = claim == null ? null : frozenCheckoutMap(claim),
       event = event == null ? null : frozenCheckoutMap(event),
       captures = List.unmodifiable(captures.map(frozenCheckoutMap)) {
    if (tenderMayHaveStarted == false &&
        (event != null ||
            captures.isNotEmpty ||
            receiptNumber != null ||
            const [
              'capturing',
              'pending',
              'refused',
              'paid',
            ].contains(state))) {
      throw const FormatException('Contradictory checkout tender evidence');
    }
  }
  final String id;
  final String orderUuid;
  final String state;
  final DateTime createdAt;
  final Map<String, dynamic>? claim;
  final int? orderId;
  final String? reference;
  final Map<String, dynamic>? event;
  final List<Map<String, dynamic>> captures;
  final String? receiptNumber;

  /// Local evidence only, never authorization to clear a server reservation.
  /// null: older journal, unknown. false: this attempt has not reached tender.
  /// true: tender may have started; written BEFORE capture and never reset.
  final bool? tenderMayHaveStarted;
  bool get terminal => const ['paid', 'released', 'managed'].contains(state);
  CheckoutAttempt copy({
    String? state,
    Map<String, dynamic>? claim,
    int? orderId,
    String? reference,
    Map<String, dynamic>? event,
    List<Map<String, dynamic>>? captures,
    String? receiptNumber,
    bool? tenderMayHaveStarted,
  }) => CheckoutAttempt(
    id: id,
    orderUuid: orderUuid,
    state: state ?? this.state,
    createdAt: createdAt,
    claim: claim ?? this.claim,
    orderId: orderId ?? this.orderId,
    reference: reference ?? this.reference,
    event: event ?? this.event,
    captures: captures ?? this.captures,
    receiptNumber: receiptNumber ?? this.receiptNumber,
    tenderMayHaveStarted:
        tenderMayHaveStarted ??
        (state == 'capturing' ? true : this.tenderMayHaveStarted),
  );
  Map<String, dynamic> get json => {
    'id': id,
    'order_uuid': orderUuid,
    'state': state,
    'created_at': createdAt.toUtc().toIso8601String(),
    'claim': claim,
    'order_id': orderId,
    'reference': reference,
    'event': event,
    'captures': captures,
    'receipt_number': receiptNumber,
    if (tenderMayHaveStarted != null)
      'tender_may_have_started': tenderMayHaveStarted,
  };
  factory CheckoutAttempt.decode(String text) {
    final json = checkoutMap(jsonDecode(text));
    if (json.containsKey('tender_may_have_started') &&
        json['tender_may_have_started'] is! bool) {
      throw const FormatException('Invalid checkout tender evidence');
    }
    final state = json['state'] as String;
    if (!const [
      'claiming',
      'reserved',
      'capturing',
      'pending',
      'refused',
      'uncertain',
      'releasing',
      'paid',
      'released',
      'managed',
    ].contains(state)) {
      throw const FormatException('Unknown checkout journal state');
    }
    final attempt = CheckoutAttempt(
      id: json['id'] as String,
      orderUuid: json['order_uuid'] as String,
      state: state,
      createdAt: DateTime.parse(json['created_at'] as String),
      claim: json['claim'] == null ? null : checkoutMap(json['claim']),
      orderId: json['order_id'] as int?,
      reference: json['reference'] as String?,
      event: json['event'] == null ? null : checkoutMap(json['event']),
      captures: (json['captures'] as List).map(checkoutMap).toList(),
      receiptNumber: json['receipt_number'] as String?,
      tenderMayHaveStarted: json['tender_may_have_started'] as bool?,
    );
    if (attempt.id.isEmpty ||
        attempt.orderUuid.isEmpty ||
        (attempt.claim != null &&
            CheckoutClaim(attempt.claim!).uuid != attempt.orderUuid) ||
        (const ['reserved', 'capturing', 'pending'].contains(state) &&
            attempt.claim == null) ||
        (state == 'pending' &&
            (attempt.event?['client_event_id'] != attempt.id ||
                attempt.event?['event_type'] != 'order.pay' ||
                checkoutMap(attempt.event?['payload'])['order_uuid'] !=
                    attempt.orderUuid))) {
      throw const FormatException('Checkout journal identity mismatch');
    }
    if (state == 'pending') {
      final payload = checkoutMap(attempt.event!['payload']);
      final payments = (payload['payments'] as List).map(checkoutMap).toList();
      if (attempt.orderId == null ||
          attempt.orderId! < 1 ||
          payload.keys.toSet().difference({
            'order_uuid',
            'paid_at',
            'payments',
            'gps',
          }).isNotEmpty ||
          (payload.containsKey('gps') && !_validSavedGps(payload['gps'])) ||
          payments.any((p) => p['status'] != 'success') ||
          jsonEncode(payments) != jsonEncode(attempt.captures)) {
        throw const FormatException('Invalid saved QR payment');
      }
      DateTime.parse(payload['paid_at'] as String);
      DateTime.parse(attempt.event!['client_timestamp'] as String);
      validateCheckoutPlan([
        for (final p in payments)
          CheckoutTender(
            p['method'] as String,
            checkoutInt(p['amount_baisas']),
            change: checkoutInt(p['change_given_baisas'] ?? 0),
          ),
      ], CheckoutClaim(attempt.claim!).amount);
    }
    return attempt;
  }
}

// The table pay producer may freeze a geofence fix into the immutable event.
// Accept exactly that shape, never arbitrary metadata or a partial fix.
bool _validSavedGps(Object? value) {
  if (value is! Map ||
      value.length != 2 ||
      !value.containsKey('lat') ||
      !value.containsKey('lng'))
    return false;
  final lat = value['lat'], lng = value['lng'];
  return lat is num &&
      lng is num &&
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;
}
