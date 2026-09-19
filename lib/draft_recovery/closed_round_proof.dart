import 'dart:convert';
import 'recovery_models.dart';

/// Complete server round ownership is required only for generations containing
/// unaccepted ledger rows. Never infer rejection from a product subtraction.
bool closedRoundProof(RecoveryLocal local, Map<String, dynamic> bill) {
  try {
    final proof = recoveryMap(bill['table_round_evidence']);
    if (local.json['generation_scoped'] != true ||
        proof['complete'] != true ||
        proof['order_uuid'] != local.uuid ||
        proof['table_id'] != local.tableId ||
        proof['table_session_uuid'] != local.seatingUuid ||
        proof['seating_status'] != 'closed' ||
        proof['merged'] != false) {
      return false;
    }
    final server = <int, Map<String, dynamic>>{};
    final owned = <int, Map<String, dynamic>>{};
    Map<String, dynamic> wire(Map<String, dynamic> line) {
      final qty = line['qty'];
      if (qty is! num || !qty.isFinite || qty != qty.toInt()) {
        throw const FormatException('Invalid quantity');
      }
      return recoveryWire({...line, 'qty': qty.toInt()});
    }

    String lines(Iterable<Map<String, dynamic>> values) {
      final all = values.map((v) => recoveryJson(wire(v))).toList()..sort();
      return recoveryJson(all);
    }

    for (final round in recoveryMaps(proof['rounds'])) {
      final id = round['id'];
      if (id is! int ||
          server.containsKey(id) ||
          round['same_seating'] != true ||
          !const {'accepted', 'rejected'}.contains(round['status'])) {
        return false;
      }
      server[id] = round;
      if (round['status'] == 'accepted') {
        if (round['needs_review'] != false) return false;
        for (final line in recoveryMaps(round['lines'])) {
          final itemId = line['order_item_id'];
          if (itemId is! int || owned.containsKey(itemId)) return false;
          owned[itemId] = wire(line);
        }
      }
    }
    // Every accepted server line must identify one canonical paid-bill item,
    // including customer/other-device rounds. No pending/unknown server round.
    final items = <int, Map<String, dynamic>>{};
    for (final item in recoveryMaps(bill['items'])) {
      final id = item['id'];
      if (id is! int ||
          items.containsKey(id) ||
          !const {'open', 'paid'}.contains(item['status'])) {
        return false;
      }
      items[id] = wire({
        ...item,
        'addon_ids': recoveryMaps(
          item['addons'],
        ).map((a) => a['add_on_id']).toList(),
      });
    }
    if (owned.length != items.length ||
        owned.isEmpty ||
        owned.entries.any(
          (e) => recoveryJson(items[e.key]) != recoveryJson(e.value),
        )) {
      return false;
    }
    for (final round in local.rounds) {
      final remote = server[round['server_round_id']];
      if (round['status'] == 'appended') {
        if (remote == null ||
            remote['status'] != 'accepted' ||
            remote['entered_by'] != 'staff' ||
            remote['client_request_id'] != round['client_request_id'] ||
            remote['round_no'] != round['server_round_no'] ||
            lines(recoveryMaps(remote['lines'])) !=
                lines(
                  recoveryMaps(jsonDecode(round['lines_json'] as String)),
                )) {
          return false;
        }
      } else {
        // A missing row is safe only in this complete closed-bill projection,
        // whose accepted ownership set has just been proved against its items.
        if (remote != null &&
            (remote['status'] != 'rejected' ||
                remote['entered_by'] != 'staff' ||
                remote['client_request_id'] != round['client_request_id'] ||
                remote['round_no'] != round['server_round_no'])) {
          return false;
        }
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}
