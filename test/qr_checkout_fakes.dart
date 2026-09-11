import 'dart:async';
import 'dart:convert';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';

final checkoutTime = DateTime.utc(2026, 9, 11, 10);
Map<String, dynamic> claimJson({bool replay = false, int amount = 4750}) => {
  'order_uuid': 'qr-bill',
  'status': 'awaiting_payment',
  'charge_amount_baisas': amount,
  'charge_claimed_at': checkoutTime.toIso8601String(),
  'charge_deadline_at': checkoutTime
      .add(const Duration(minutes: 5))
      .toIso8601String(),
  'already_claimed_by_this_device': replay,
};
Map<String, dynamic> snapshotJson() => {
  'order': {
    'id': 12,
    'uuid': 'qr-bill',
    'source': 'qr_web',
    'order_type': 'quick',
    'table_id': null,
    'status': 'awaiting_payment',
    'temp_reference': 'Q-007',
    'opened_at': checkoutTime.toIso8601String(),
    'customer_id': 5,
    'plate_number': null,
    'subtotal_baisas': 5000,
    'discount_total_baisas': 500,
    'comp_total_baisas': 0,
    'tax_total_baisas': 250,
    'grand_total_baisas': 4750,
    'items': [
      {
        'id': 1,
        'product_id': 8,
        'product_name': 'Test Coffee',
        'qty': 2.0,
        'unit_price_baisas': 2500,
        'line_total_baisas': 5000,
        'status': 'active',
        'notes': 'No sugar',
        'addons': [],
      },
    ],
  },
  'customer': {'id': 5, 'name': 'Test Customer', 'phone': '00000000'},
  'claim': claimJson(),
};

class MemoryCheckoutStore implements CheckoutStore {
  CheckoutAttempt? value;
  final history = <CheckoutAttempt>[];
  String? failState;
  @override
  Future<CheckoutAttempt?> active() async =>
      value?.terminal == true ? null : value;
  @override
  Future<void> create(CheckoutAttempt next) async {
    if (failState == next.state || await active() != null) {
      throw StateError('disk/conflict');
    }
    value = next;
    history.add(next);
  }

  @override
  Future<void> replace(CheckoutAttempt previous, CheckoutAttempt next) async {
    if (failState == next.state || value != previous || previous.terminal) {
      throw StateError('disk/conflict');
    }
    if (previous.event != null &&
        jsonEncode(previous.event) != jsonEncode(next.event)) {
      throw StateError('immutable');
    }
    value = next;
    history.add(next);
  }
}

class CheckoutFakeGateway implements CheckoutGateway {
  int claims = 0, snapshots = 0, preflights = 0, commits = 0;
  bool firstReplay = false,
      loseAck = false,
      failRelease = false,
      badSnapshot = false;
  bool failPreflight = false, failClaim = false;
  String ack = 'paid';
  int? refuseClaimAt, changedClaimAt;
  Completer<void>? claimWait;
  final releases = <Map<String, dynamic>>[];
  final pushes = <Map<String, dynamic>>[];
  final accepted = <String>{};
  @override
  Future<void> preflight(String uuid) async {
    preflights++;
    if (failPreflight) throw StateError('scope');
  }

  @override
  Future<CheckoutClaim> claim(String uuid) async {
    claims++;
    if (claimWait != null) await claimWait!.future;
    if (failClaim) throw TimeoutException('claim lost');
    if (claims == refuseClaimAt) {
      throw const CheckoutRefusal('charge_already_claimed');
    }
    return CheckoutClaim(
      claimJson(
        replay: firstReplay || claims > 1,
        amount: claims == changedClaimAt ? 5000 : 4750,
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> snapshot(String uuid) async {
    snapshots++;
    final data = snapshotJson();
    if (badSnapshot) (data['order'] as Map)['uuid'] = 'foreign';
    return data;
  }

  @override
  Future<void> release(
    String uuid,
    String outcome,
    List<Map<String, dynamic>> captures,
  ) async {
    releases.add({'uuid': uuid, 'outcome': outcome, 'captures': captures});
    if (failRelease) throw TimeoutException('release lost');
  }

  @override
  Future<List<Map<String, dynamic>>> push(Map<String, dynamic> event) async {
    pushes.add(checkoutMap(jsonDecode(jsonEncode(event))));
    if (ack == 'paid' && accepted.add(event['client_event_id'] as String)) {
      commits++;
    }
    if (loseAck) throw TimeoutException('ACK lost AFTER commit');
    return [
      {
        'client_event_id': ack == 'wrong-id'
            ? 'foreign'
            : event['client_event_id'],
        'status': ack == 'failed' ? 'failed' : 'processed',
        'result': {
          'order_id': ack == 'wrong-order' ? 99 : 12,
          'status': ack == 'wrong-status' ? 'held' : 'paid',
          'orphan_tender': ack == 'orphan',
          'receipt_number': 'R-009',
        },
      },
    ];
  }
}

class CheckoutFixture {
  final store = MemoryCheckoutStore();
  final api = CheckoutFakeGateway();
  int cards = 0, banks = 0, gifts = 0;
  bool giftAllowed = true;
  DateTime now = checkoutTime;
  CheckoutCaptureState cardState = CheckoutCaptureState.approved;
  CheckoutCaptureState bankState = CheckoutCaptureState.approved;
  Completer<void>? captureWait;
  QrCheckoutController controller() => QrCheckoutController(
    gateway: api,
    store: store,
    now: () => now,
    newId: () => 'payment-attempt-1',
    authorizeGift: () async {
      gifts++;
      return giftAllowed;
    },
    captureCard: (amount) async {
      cards++;
      if (captureWait != null) await captureWait!.future;
      return CheckoutCapture(
        cardState,
        evidence: {'softpos_reference': 'TEST-RRN'},
      );
    },
    captureBank: (amount) async {
      banks++;
      return CheckoutCapture(bankState);
    },
  );
}
