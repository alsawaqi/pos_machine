import 'dart:convert';
import '../qr_checkout/qr_checkout_models.dart';
import 'package:crypto/crypto.dart';
import '../bill_combine/combine_models.dart';
import '../dine_in/dine_in_models.dart';
import '../qr_quick/qr_quick_models.dart';

Map<String, dynamic> recoveryMap(Object? value) => combineMap(value);
String recoveryJson(Object? value) => combineJson(value);
List<Map<String, dynamic>> recoveryMaps(Object? value) {
  if (value is! List) throw const FormatException('Missing recovery evidence');
  return value.map(recoveryMap).toList();
}

/// Exact identity: no case folding, whitespace rewriting or duplicate add-ons.
Map<String, dynamic> recoveryWire(Map<String, dynamic> line) {
  final ids = (line['addon_ids'] as List? ?? const []).toList();
  if (line['product_id'] is! int ||
      (line['product_id'] as int) < 1 ||
      line['qty'] is! int ||
      (line['qty'] as int) < 1 ||
      (line['qty'] as int) > 999 ||
      ids.any((id) => id is! int || id < 1) ||
      ids.toSet().length != ids.length ||
      (line['notes'] != null && line['notes'] is! String)) {
    throw const FormatException('Invalid original item identity');
  }
  ids.sort((a, b) => (a as int).compareTo(b as int));
  return {
    'product_id': line['product_id'],
    'qty': line['qty'],
    'notes': line['notes'] ?? '',
    'addon_ids': ids,
  };
}

Map<String, dynamic> recoveryPriced(Map<String, dynamic> line) {
  final addons = recoveryMaps(line['addons']);
  final wire = recoveryWire({
    ...line,
    'addon_ids': addons.map((a) => a['id']).toList(),
  });
  if (line['name'] is! String ||
      line['unit_price_baisas'] is! int ||
      (line['unit_price_baisas'] as int) < 0 ||
      line['line_total_baisas'] !=
          (line['unit_price_baisas'] as int) * (wire['qty'] as int) ||
      (line['line_discount_baisas'] ?? 0) != 0 ||
      addons.any(
        (a) =>
            a['name'] is! String ||
            a['price_delta_baisas'] is! int ||
            (a['price_delta_baisas'] as int) < 0,
      )) {
    throw const FormatException('Original stored prices cannot be proved');
  }
  addons.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  return {
    'product_id': wire['product_id'],
    'qty': wire['qty'],
    'name': line['name'],
    'notes': wire['notes'],
    'unit_price_baisas': line['unit_price_baisas'],
    'line_total_baisas': line['line_total_baisas'],
    'addons': addons
        .map(
          (a) => {
            'id': a['id'],
            'name': a['name'],
            'price_delta_baisas': a['price_delta_baisas'],
          },
        )
        .toList(),
  };
}

String recoveryPriceKey(Map<String, dynamic> line) => recoveryJson(
  {...line}
    ..remove('qty')
    ..remove('line_total_baisas'),
);

Map<String, dynamic> recoveryLocalLine(Map<String, dynamic> item) {
  if (item['gifted'] == true || (item['bundleKey'] ?? '') != '') {
    throw StateError('Gifted or bundled local items need separate review.');
  }
  final addons = recoveryMaps(item['modifiers'])
      .map(
        (a) => {
          'id': int.tryParse(a['id']?.toString() ?? ''),
          'name': a['label'],
          'price_delta_baisas': combineBaisas(a['price']),
        },
      )
      .toList();
  final unit = combineBaisas(item['unitPrice']);
  if (unit !=
      combineBaisas(item['basePrice']) +
          addons.fold<int>(0, (s, a) => s + (a['price_delta_baisas'] as int))) {
    throw StateError('Local stored prices are inconsistent.');
  }
  return recoveryPriced({
    'product_id': int.tryParse(item['id']?.toString() ?? ''),
    'qty': item['qty'],
    'name': item['name'],
    'notes': item['notes'] ?? '',
    'unit_price_baisas': unit,
    'line_total_baisas': combineBaisas(item['lineTotal']),
    'addons': addons,
  });
}

class RecoveryLocal {
  RecoveryLocal(Map<String, dynamic> value) : encoded = recoveryJson(value) {
    if (!combineUuid(uuid) ||
        tableId < 1 ||
        rows.isEmpty ||
        items.isEmpty ||
        !const {'legacy_hold', 'staff_rounds'}.contains(kind)) {
      throw const FormatException('Cannot identify the original local draft');
    }
    final identities = <String>{};
    final draft = recoveryMap(json['draft']);
    if (draft['serverOrderUuid'] != uuid ||
        draft['diningTableId'] != '$tableId' ||
        draft['orderType'] != 'dine_in' ||
        draft['splitCount'] != 1 ||
        recoveryMap(draft['discount'])['value'] != 0 ||
        recoveryMaps(json['cancellations']).isNotEmpty ||
        (kind == 'legacy_hold' && rounds.isNotEmpty) ||
        (kind == 'staff_rounds' &&
            (rounds.isEmpty ||
                rounds.length > 100 ||
                !combineUuid(seatingUuid)))) {
      throw const FormatException(
        'Original local recovery evidence is inconsistent',
      );
    }
    for (final row in rows) {
      if (!const {'held_orders', 'dining_tables'}.contains(row['table']) ||
          row['pk'] != (row['table'] == 'dining_tables' ? 'table_id' : 'id') ||
          row['value'] is! String ||
          recoveryMap(row['row'])[row['pk']] != row['value'] ||
          !identities.add('${row['table']}:${row['value']}')) {
        throw const FormatException('Invalid local archive identity');
      }
      final raw = recoveryMap(row['row']);
      if (recoveryJson(jsonDecode(raw['draft_json'] as String)) !=
              recoveryJson(draft) ||
          (row['table'] == 'held_orders' && raw['order_type'] != 'dine_in') ||
          (row['table'] == 'dining_tables' &&
              (raw['table_id'] != '$tableId' ||
                  raw['status'] != 'occupied' ||
                  raw['paid_at'] != null ||
                  raw['paid_snapshot_json'] != null ||
                  (raw['primary_table_id'] ?? '') != '' ||
                  (raw['linked_table_ids_json'] != null &&
                      raw['linked_table_ids_json'] != '[]') ||
                  raw['winner_seating_uuid'] != null ||
                  (raw['server_order_uuid'] != null &&
                      raw['server_order_uuid'] != uuid)))) {
        throw const FormatException(
          'Raw local copies disagree with the recovery snapshot',
        );
      }
    }
    final requests = <String>{}, serverRounds = <int>{};
    for (final round in rounds) {
      if (!combineUuid(round['client_request_id']) ||
          !requests.add(round['client_request_id'] as String) ||
          round['table_id'] != '$tableId' ||
          round['order_uuid'] != uuid ||
          (round['status'] != 'appended' &&
              !(json['generation_scoped'] == true &&
                  const {'held', 'rejected'}.contains(round['status']))) ||
          !combineUuid(round['seating_key']) ||
          round['server_round_id'] is! int ||
          (round['server_round_id'] as int) < 1 ||
          !serverRounds.add(round['server_round_id'] as int) ||
          round['server_round_no'] is! int ||
          (round['server_round_no'] as int) < 1 ||
          round['acked_at'] is! String ||
          DateTime.tryParse(round['acked_at'] as String) == null ||
          (round['status'] == 'appended' &&
              ((jsonDecode(round['held_lines_json'] as String? ?? '[]') as List)
                      .isNotEmpty ||
                  (jsonDecode(round['review_reasons_json'] as String? ?? '[]')
                          as List)
                      .isNotEmpty))) {
        throw const FormatException(
          'Unresolved staff round in recovery snapshot',
        );
      }
    }
    for (final item in items) {
      recoveryLocalLine(item);
    }
  }
  final String encoded;
  Map<String, dynamic> get json => recoveryMap(jsonDecode(encoded));
  String get hash => sha256.convert(utf8.encode(encoded)).toString();
  int get tableId => json['table_id'] as int;
  String get uuid => json['uuid'] as String;
  String get kind => json['kind'] as String;
  String? get seatingUuid => json['seating_uuid'] as String?;
  List<Map<String, dynamic>> get rows => recoveryMaps(json['rows']);
  List<Map<String, dynamic>> get rounds => recoveryMaps(json['rounds']);
  List<Map<String, dynamic>> get items =>
      recoveryMaps(recoveryMap(json['draft'])['items']);
  List<String> get eventIds =>
      rounds.map((r) => r['client_request_id'] as String).toList()..sort();
  Map<String, dynamic> get query => {
    'order_uuid': uuid,
    'kind': kind,
    if (kind == 'staff_rounds') 'event_ids': eventIds,
  };

  /// Only proven own staff quantities are subtracted at their exact stored price.
  /// A slice retains every original local field; no server cart is constructed.
  List<Map<String, dynamic>> delta(RecoveryPreview preview) {
    final proof = preview.proof;
    if (proof['table_id'] != tableId ||
        proof['order_uuid'] != uuid ||
        proof['kind'] != kind ||
        (seatingUuid != null && proof['table_session_uuid'] != seatingUuid)) {
      throw StateError('This proof belongs to another bill or seating.');
    }
    final acknowledged = recoveryMaps(proof['acknowledged']);
    if (kind == 'staff_rounds') {
      final proofIds = acknowledged.map((a) => a['client_event_id']).toList()
        ..sort();
      if (recoveryJson(proofIds) != recoveryJson(eventIds)) {
        throw StateError(
          'The complete local staff-round set is not acknowledged.',
        );
      }
      for (final round in rounds) {
        final ack = acknowledged.singleWhere(
          (a) => a['client_event_id'] == round['client_request_id'],
        );
        if (ack['client_request_id'] != round['client_request_id'] ||
            ack['seating_key'] != round['seating_key'] ||
            ack['round_id'] != round['server_round_id'] ||
            ack['round_no'] != round['server_round_no']) {
          throw StateError('Stored staff-round acknowledgement differs.');
        }
        final expected = recoveryMaps(
          jsonDecode(round['lines_json'] as String),
        ).map(recoveryWire).toList();
        final actual = recoveryMaps(ack['lines'])
            .map(
              (l) => recoveryWire({
                ...l,
                'addon_ids': recoveryMaps(
                  l['addons'],
                ).map((a) => a['id']).toList(),
              }),
            )
            .toList();
        if (recoveryJson(expected) != recoveryJson(actual)) {
          throw StateError('Original staff round quantities or notes differ.');
        }
      }
    } else if (acknowledged.length != 1 ||
        !combineUuid(acknowledged.single['client_event_id'])) {
      throw StateError('Missing original held-bill acknowledgement.');
    }
    if (kind == 'legacy_hold') {
      final original =
          items.map((item) => recoveryJson(recoveryLocalLine(item))).toList()
            ..sort();
      final received = recoveryMaps(
        acknowledged.single['lines'],
      ).map((line) => recoveryJson(recoveryPriced(line))).toList()..sort();
      if (recoveryJson(original) != recoveryJson(received)) {
        throw StateError(
          'The original held-bill line multiset differs. Keep every local item.',
        );
      }
    }
    final quantities = <String, int>{};
    final itemIds = <int>{}, roundIds = <int>{};
    for (final ack in acknowledged) {
      if (kind == 'staff_rounds' &&
          (ack['round_id'] is! int || !roundIds.add(ack['round_id'] as int))) {
        throw StateError('Duplicate round evidence.');
      }
      for (final line in recoveryMaps(ack['lines'])) {
        if (line['order_item_id'] is! int ||
            (line['order_item_id'] as int) < 1 ||
            !itemIds.add(line['order_item_id'] as int)) {
          throw StateError('Duplicate item evidence.');
        }
        final priced = recoveryPriced(line),
            key = recoveryPriceKey(recoveryPriced(line));
        quantities[key] = (quantities[key] ?? 0) + (priced['qty'] as int);
      }
    }
    final delta = <Map<String, dynamic>>[];
    for (final raw in items) {
      final line = recoveryLocalLine(raw),
          key = recoveryPriceKey(recoveryLocalLine(raw));
      final qty = line['qty'] as int, received = quantities[key] ?? 0;
      final used = received < qty ? received : qty;
      quantities[key] = received - used;
      if (used < qty) delta.add({'original': raw, 'qty': qty - used});
    }
    if (quantities.values.any((q) => q != 0) ||
        (kind == 'legacy_hold' && delta.isNotEmpty)) {
      throw StateError(
        'Local items differ from their acknowledged baseline. Keep the original draft.',
      );
    }
    if (delta.length > 50) {
      throw StateError('Too many saved additions for one safe round.');
    }
    for (final slice in delta) {
      final line = recoveryLocalLine(recoveryMap(slice['original']));
      QrQuickLine.fromJson(
        recoveryWire({
          ...line,
          'qty': slice['qty'],
          'addon_ids': recoveryMaps(
            line['addons'],
          ).map((a) => a['id']).toList(),
        }),
      );
    }
    return delta;
  }
}

class RecoveryPreview {
  RecoveryPreview(Map<String, dynamic> value) : encoded = recoveryJson(value) {
    if (json['recovery_policy'] != 'same_bill_recovery_v1' ||
        json['preview_token'] is! String ||
        !RegExp(r'^\d+\.[0-9a-f]{64}$').hasMatch(token) ||
        json['expires_at'] is! String ||
        DateTime.tryParse(json['expires_at'] as String) == null ||
        proof['proof_policy'] != 'same_bill_draft_v1' ||
        proof['read_only'] != true ||
        proof['archive_authorized'] != false ||
        proof['delta_policy'] != 'proven_local_rounds_only' ||
        !combineUuid(proof['order_uuid']) ||
        !combineUuid(proof['table_session_uuid']) ||
        proof['table_id'] is! int ||
        proof['device_id'] is! int ||
        proof['table_label'] is! String ||
        recoveryMap(proof['bill'])['uuid'] != proof['order_uuid'] ||
        recoveryMap(proof['bill'])['status'] != 'open') {
      throw const FormatException(
        'Server cannot authorize safe draft recovery',
      );
    }
    final bill = recoveryMap(proof['bill']);
    if (bill['source'] != 'qr_web' && !hasStaffTableCheckoutPolicy(bill)) {
      throw StateError(
        'Shared staff-only checkout needs separate review. Keep the original local draft.',
      );
    }
    for (final key in [
      'subtotal_baisas',
      'tax_total_baisas',
      'grand_total_baisas',
    ]) {
      if (bill[key] is! int || (bill[key] as int) < 0) {
        throw const FormatException('Invalid frozen bill');
      }
    }
    if (bill['discount_total_baisas'] != 0 ||
        bill['comp_total_baisas'] != 0 ||
        bill['grand_total_baisas'] !=
            (bill['subtotal_baisas'] as int) +
                (bill['tax_total_baisas'] as int) ||
        recoveryMaps(proof['acknowledged']).isEmpty) {
      throw const FormatException('Incomplete recovery evidence');
    }
    final items = <int, Map<String, dynamic>>{};
    var subtotal = 0;
    for (final raw in recoveryMaps(bill['items'])) {
      final id = raw['id'];
      if (id is! int ||
          id < 1 ||
          items.containsKey(id) ||
          raw['status'] != 'open') {
        throw const FormatException('Invalid frozen bill item ownership');
      }
      final item = recoveryPriced(raw);
      subtotal += item['line_total_baisas'] as int;
      items[id] = item;
    }
    if (items.isEmpty || subtotal != bill['subtotal_baisas']) {
      throw const FormatException('Frozen bill does not balance');
    }
    final owned = <int>{};
    for (final ack in recoveryMaps(proof['acknowledged'])) {
      if (!combineUuid(ack['client_event_id'])) {
        throw const FormatException('Missing acknowledged event identity');
      }
      for (final line in recoveryMaps(ack['lines'])) {
        final id = line['order_item_id'];
        if (id is! int ||
            !owned.add(id) ||
            !items.containsKey(id) ||
            recoveryJson(recoveryPriced(line)) != recoveryJson(items[id])) {
          throw const FormatException(
            'Acknowledged items differ from the frozen bill',
          );
        }
      }
    }
  }
  final String encoded;
  Map<String, dynamic> get json => recoveryMap(jsonDecode(encoded));
  Map<String, dynamic> get proof => recoveryMap(json['proof']);
  String get token => json['preview_token'] as String;
}

class RecoveryAttempt {
  RecoveryAttempt(Map<String, dynamic> value) : encoded = recoveryJson(value) {
    if (!combineUuid(id) ||
        !const {
          'pending',
          'confirmed',
          'delta_ready',
          'delta_pending',
          'done',
          'not_applied',
        }.contains(state)) {
      throw const FormatException('Invalid recovery journal');
    }
    final computed = local.delta(preview);
    if (recoveryJson(computed) != recoveryJson(json['delta'])) {
      throw const FormatException('Saved additions changed');
    }
    if (state != 'pending' && state != 'not_applied') {
      validateAck(recoveryMap(json['ack']));
    }
    if (state == 'not_applied' && !matchesRelease(json['release'])) {
      throw const FormatException('Missing exact final no-write release');
    }
    if (state == 'delta_pending' || json['delta_request'] != null) {
      request;
    }
    if (state == 'done' && computed.isNotEmpty) {
      validateDeltaAck(recoveryMap(json['delta_ack']));
      validateDeltaRound(
        recoveryMap(json['delta_round']),
        recoveryMap(json['delta_ack']),
      );
    }
  }
  final String encoded;
  Map<String, dynamic> get json => recoveryMap(jsonDecode(encoded));
  String get id => json['id'] as String;
  String get state => json['state'] as String;
  RecoveryLocal get local => RecoveryLocal(recoveryMap(json['local']));
  RecoveryPreview get preview => RecoveryPreview(recoveryMap(json['preview']));
  bool get terminal => state == 'done' || state == 'not_applied';
  List<Map<String, dynamic>> get delta => recoveryMaps(json['delta']);
  Map<String, dynamic> get payload => {
    ...local.query,
    'client_request_id': id,
    'preview_token': preview.token,
    'local_snapshot_hash': local.hash,
  };
  RecoveryAttempt change(
    String state, [
    Map<String, dynamic> fields = const {},
  ]) => RecoveryAttempt({...json, ...fields, 'state': state});
  DineInRequest get request {
    final r = recoveryMap(json['delta_request']);
    final request = DineInRequest(
      tableId: local.tableId,
      seatingUuid: preview.proof['table_session_uuid'] as String,
      billUuid: local.uuid,
      payload: recoveryMap(r['payload']),
    );
    if (r['seating_uuid'] != request.seatingUuid ||
        r['bill_uuid'] != request.billUuid ||
        r['table_id'] != request.tableId) {
      throw const FormatException('Saved round identity changed');
    }
    final lines = delta.map((slice) {
      final l = recoveryLocalLine(recoveryMap(slice['original']));
      return recoveryWire({
        ...l,
        'qty': slice['qty'],
        'addon_ids': recoveryMaps(l['addons']).map((a) => a['id']).toList(),
      });
    }).toList();
    if (recoveryJson(lines) !=
        recoveryJson(
          recoveryMaps(request.payload['lines']).map(recoveryWire).toList(),
        )) {
      throw const FormatException(
        'Saved round differs from the preserved additions',
      );
    }
    return request;
  }

  void validateAck(Map<String, dynamic> ack) {
    for (final entry in {
      'outcome': 'draft_recovered',
      'recovery_policy': 'same_bill_recovery_v1',
      'client_request_id': id,
      'local_snapshot_hash': local.hash,
      'order_uuid': local.uuid,
      'table_id': local.tableId,
      'table_session_uuid': preview.proof['table_session_uuid'],
      'preview_token': preview.token,
      'archive_authorized': true,
    }.entries) {
      if (ack[entry.key] != entry.value) {
        throw const FormatException(
          'Recovery reply does not match the saved request',
        );
      }
    }
    if (ack['event_id'] is! int || (ack['event_id'] as int) < 1) {
      throw const FormatException('Missing recovery acknowledgement');
    }
  }

  void validateDeltaAck(Map<String, dynamic> ack) {
    final r = request;
    if (!const {
          'appended',
          'seating_created',
          'replayed',
          'held',
        }.contains(ack['outcome']) ||
        !const {
          'accepted',
          'pending_confirmation',
          'rejected',
        }.contains(ack['round_status']) ||
        ack['order_uuid'] != local.uuid ||
        ack['table_session_uuid'] != r.seatingUuid ||
        ack['winner_table_session_uuid'] != null ||
        ack['table_id'] != r.payload['table_id'] ||
        ack['seating_key'] != r.payload['seating_key'] ||
        ack['round_id'] is! int ||
        (ack['round_id'] as int) < 1 ||
        ack['round_no'] is! int ||
        (ack['round_no'] as int) < 1 ||
        ack['total_baisas'] is! int ||
        (ack['total_baisas'] as int) < 0) {
      throw const FormatException(
        'Saved additions have not been safely acknowledged',
      );
    }
  }

  void validateDeltaRound(
    Map<String, dynamic> round,
    Map<String, dynamic> ack,
  ) {
    if (round['id'] != ack['round_id'] ||
        round['round_no'] != ack['round_no'] ||
        !const {
          'accepted',
          'pending_confirmation',
          'rejected',
        }.contains(round['status']) ||
        round['entered_by'] != 'staff' ||
        round['client_request_id'] != request.id) {
      throw const FormatException(
        'The received round does not identify the saved additions',
      );
    }
  }

  bool matchesRelease(Object? value) =>
      value is Map &&
      recoveryJson(value) ==
          recoveryJson({...payload, 'table_id': local.tableId});
}
