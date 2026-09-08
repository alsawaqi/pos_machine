import 'dart:async';

import 'package:pos_machine/models/qr_pending_order.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/services/qr_till_service.dart';

QrPendingOrder pendingOrder({
  String uuid = 'quick-expired',
  String status = 'held',
  String session = 'expired',
  String charge = 'none',
  String? refusal,
}) => QrPendingOrder.fromJson({
  'uuid': uuid,
  'source': 'qr_web',
  'order_type': 'quick',
  'status': status,
  'receipt_number': null,
  'temp_reference': 'Q-0042',
  'table_id': null,
  'customer_id': 7,
  'plate_number': null,
  'subtotal_baisas': 4500,
  'discount_total_baisas': 0,
  'comp_total_baisas': 0,
  'tax_total_baisas': 250,
  'grand_total_baisas': 4750,
  'route': status == 'held' ? 'counter' : 'machine',
  'session': session,
  'charge': charge,
  'age_seconds': 7800,
  'phone_tail': '5555',
  'actions': {
    'settle': status == 'held' && charge == 'none',
    'to_counter':
        charge == 'declined' ||
        charge == 'cancelled' ||
        (status == 'awaiting_payment' && charge == 'none'),
  },
  'refusal_code': refusal,
  'items': [
    {
      'id': 1,
      'product_id': 11,
      'product_name': 'Server-priced meal',
      'qty': 1,
      'unit_price_baisas': 4500,
      'line_discount_baisas': 0,
      'line_total_baisas': 4500,
      'status': 'accepted',
      'addons': [],
    },
  ],
});

class PendingGateway implements QrTillGateway, QrPendingGateway {
  PendingGateway([List<QrPendingOrder>? initial])
    : orders = initial ?? [pendingOrder()];
  List<QrPendingOrder> orders;
  final calls = <String>[];
  Object? fetchError;
  Object? moveError;
  Completer<List<QrPendingOrder>>? fetchPending;

  @override
  Future<List<QrPendingOrder>> fetchQrPendingOrders() async {
    calls.add('fetch');
    if (fetchError != null) throw fetchError!;
    return fetchPending == null ? orders : fetchPending!.future;
  }

  @override
  Future<QrPendingOrder> moveQrPendingToCounter(String uuid) async {
    calls.add('move:$uuid');
    if (moveError != null) throw moveError!;
    orders = [pendingOrder(uuid: uuid)];
    return orders.single;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected gateway call: ${invocation.memberName}');
}

class PendingFlow implements QrSettlementFlow {
  final calls = <String>[];
  Completer<QrSettlementClaim>? claimPending;
  @override
  List<QrSettlementResult> get pendingManagerRecoveries => const [];

  @override
  Future<QrSettlementClaim> claim(String uuid) async {
    calls.add('claim:$uuid');
    return claimPending == null ? pendingClaim(uuid) : claimPending!.future;
  }

  @override
  Future<QrSettlementResult> settleClaim(
    QrSettlementClaim claim,
    QrTender tender,
  ) async {
    calls.add('settle:${tender.name}');
    return QrSettlementResult(kind: QrSettlementResultKind.paid, claim: claim);
  }

  @override
  Future<void> releaseClaim(
    QrSettlementClaim claim,
    QrReleaseOutcome outcome, {
    Object? terminalResult,
  }) async {
    calls.add('release:${outcome.name}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected flow call: ${invocation.memberName}');
}

QrSettlementClaim pendingClaim(
  String uuid, {
  bool replay = false,
  DateTime? now,
}) => QrSettlementClaim(
  orderUuid: uuid,
  frozenAmountBaisas: 4750,
  status: 'awaiting_payment',
  deadlineAt: (now ?? DateTime.now()).add(const Duration(minutes: 5)),
  alreadyClaimedByThisDevice: replay,
);
