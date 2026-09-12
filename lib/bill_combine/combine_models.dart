import 'dart:convert';

Map<String, dynamic> combineMap(Object? value) {
  if (value is! Map) throw const FormatException('Invalid combine object');
  return Map<String, dynamic>.from(value);
}

String combineJson(Object? value) {
  Object? sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sorted(v[k])};
    }
    if (v is List) return v.map(sorted).toList();
    return v;
  }

  return jsonEncode(sorted(value));
}

int combineBaisas(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      (value * 1000 - (value * 1000).round()).abs() > 0.00001) {
    throw const FormatException('Cannot prove original local price');
  }
  return (value * 1000).round();
}

bool combineUuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);

/// Deep snapshots, not editable carts. Raw local rows remain in the journal
/// after completion; PIN is never a model field.
class CombineLocal {
  CombineLocal(Map<String, dynamic> value) : encoded = combineJson(value) {
    if (!combineUuid(json['uuid']) ||
        tableId < 1 ||
        rows.isEmpty ||
        lines.isEmpty ||
        json['discount_baisas'] is! int ||
        (json['discount_baisas'] as int) < 0) {
      throw const FormatException('Cannot prove original local bill');
    }
    final identities = <String>{};
    for (final r in rows) {
      final table = r['table'], pk = r['pk'];
      if (!((table == 'held_orders' && (pk == 'id' || pk == 'uuid')) ||
              (table == 'dining_tables' && pk == 'table_id')) ||
          r['value'] is! String ||
          combineMap(r['row'])[pk] != r['value'] ||
          !identities.add('$table:${r['value']}')) {
        throw const FormatException('Invalid local row identity');
      }
    }
  }
  final String encoded;
  Map<String, dynamic> get json => combineMap(jsonDecode(encoded));
  int get tableId => json['table_id'] as int;
  String get uuid => json['uuid'] as String;
  List<Map<String, dynamic>> get rows =>
      (json['rows'] as List).map(combineMap).toList();
  List<Map<String, dynamic>> get lines =>
      (json['lines'] as List).map(combineMap).toList();

  void matches(CombinePreview preview) {
    final source = preview.source;
    if (preview.tableId != tableId ||
        source['uuid'] != uuid ||
        source['discount_total_baisas'] != json['discount_baisas'] ||
        source['comp_total_baisas'] != 0) {
      throw StateError('Local bill differs from its server mirror');
    }
    final expected = (source['items'] as List).map((v) {
      final line = combineMap(v);
      if (line['line_discount_baisas'] != 0 ||
          line['qty'] is! num ||
          (line['qty'] as num) != (line['qty'] as num).toInt()) {
        throw StateError('This bill needs separate accounting review');
      }
      return combineJson({
        'product_id': line['product_id'],
        'qty': (line['qty'] as num).toInt(),
        'name': line['name'],
        'notes': line['notes'] ?? '',
        'unit_price_baisas': line['unit_price_baisas'],
        'line_total_baisas': line['line_total_baisas'],
        'addons': ((line['addons'] as List).map(combineJson).toList()..sort()),
      });
    }).toList()..sort();
    final actual =
        lines
            .map(
              (line) => combineJson({
                ...line,
                'addons': ((line['addons'] as List).map(combineJson).toList()
                  ..sort()),
              }),
            )
            .toList()
          ..sort();
    if (combineJson(actual) != combineJson(expected)) {
      throw StateError('Local items differ from the frozen server bill');
    }
  }
}

class CombinePreview {
  CombinePreview(Map<String, dynamic> value) : encoded = combineJson(value) {
    if (json['combine_policy'] != 'local_owner_v1' ||
        json['table_id'] is! int ||
        tableId < 1 ||
        json['table_label'] is! String ||
        !combineUuid(json['table_session_uuid']) ||
        !combineUuid(source['uuid']) ||
        !combineUuid(target['uuid']) ||
        source['uuid'] == target['uuid'] ||
        json['requires_manager_pin'] != true ||
        json['kitchen_submission'] != false ||
        json['reason'] != 'same_party_duplicate_bill' ||
        json['preview_token'] is! String ||
        !RegExp(
          r'^\d+\.[0-9a-f]{64}$',
        ).hasMatch(json['preview_token'] as String)) {
      throw const FormatException(
        'Server does not support safe local combining',
      );
    }
    for (final bill in [source, target]) {
      for (final k in [
        'subtotal_baisas',
        'discount_total_baisas',
        'comp_total_baisas',
        'tax_total_baisas',
        'grand_total_baisas',
      ]) {
        if (bill[k] is! int || (bill[k] as int) < 0) {
          throw const FormatException('Invalid frozen bill amount');
        }
      }
      if (bill['items'] is! List || (bill['items'] as List).isEmpty) {
        throw const FormatException('Missing frozen bill items');
      }
    }
    if (json['combined_grand_total_baisas'] !=
        (source['grand_total_baisas'] as int) +
            (target['grand_total_baisas'] as int)) {
      throw const FormatException('Invalid combined amount');
    }
  }
  final String encoded;
  Map<String, dynamic> get json => combineMap(jsonDecode(encoded));
  Map<String, dynamic> get source => combineMap(json['source']);
  Map<String, dynamic> get target => combineMap(json['target']);
  int get tableId => json['table_id'] as int;
}

class CombineAttempt {
  CombineAttempt(Map<String, dynamic> value) : encoded = combineJson(value) {
    if (!combineUuid(id) ||
        !const {
          'pending',
          'confirmed',
          'done',
          'not_applied',
        }.contains(state)) {
      throw const FormatException('Invalid combine journal');
    }
    local.matches(preview);
    if (state == 'confirmed' || state == 'done') {
      validateAck(combineMap(json['ack']));
    }
  }
  final String encoded;
  Map<String, dynamic> get json => combineMap(jsonDecode(encoded));
  String get id => json['id'] as String;
  String get state => json['state'] as String;
  CombineLocal get local => CombineLocal(combineMap(json['local']));
  CombinePreview get preview => CombinePreview(combineMap(json['preview']));
  bool get terminal => state == 'done' || state == 'not_applied';
  Map<String, dynamic> get payload => {
    'source_order_uuid': local.uuid,
    'target_order_uuid': preview.target['uuid'],
    'client_request_id': id,
    'preview_token': preview.json['preview_token'],
    'reason': 'same_party_duplicate_bill',
  };
  CombineAttempt withState(String next, {Map<String, dynamic>? ack}) =>
      CombineAttempt({...json, 'state': next, 'ack': ?ack});
  void validateAck(Map<String, dynamic> ack) {
    if (ack['outcome'] != 'combined' ||
        ack['source_status'] != 'combined' ||
        ack['source_order_uuid'] != local.uuid ||
        ack['order_uuid'] != preview.target['uuid'] ||
        ack['table_session_uuid'] != preview.json['table_session_uuid'] ||
        ack['grand_total_baisas'] !=
            preview.json['combined_grand_total_baisas'] ||
        ack['temp_reference'] != preview.target['temp_reference'] ||
        ack['receipt_number'] != preview.target['receipt_number']) {
      throw const FormatException(
        'Combine reply does not match the reviewed bills',
      );
    }
    for (final k in ['event_id', 'round_id', 'approved_by_staff_id']) {
      if (ack[k] is! int || (ack[k] as int) < 1) {
        throw const FormatException('Missing combine confirmation');
      }
    }
  }

  bool matchesRelease(Object? proof) =>
      proof is Map &&
      combineJson(proof) ==
          combineJson({...payload, 'table_id': local.tableId});
}
