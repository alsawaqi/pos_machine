import 'dart:convert';
import '../qr_quick/qr_quick_models.dart';

Map<String, dynamic> tableMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected table object');
  return Map<String, dynamic>.from(value);
}

/// A display snapshot, never a cart, local table record or payment authority.
class DineInDetail {
  DineInDetail(Map<String, dynamic> value)
    : json = tableMap(jsonDecode(jsonEncode(value))) {
    if (table['id'] is! int ||
        table['label'] is! String ||
        json['occupied'] is! bool ||
        json['orphaned'] is! bool ||
        json['rounds'] is! List) {
      throw const FormatException('Invalid table snapshot');
    }
    if (seating != null &&
        (seating!['uuid'] is! String || seating!['table_id'] is! int)) {
      throw const FormatException('Invalid canonical seating');
    }
    if (bill != null &&
        (bill!['uuid'] is! String ||
            bill!['grand_total_baisas'] is! int ||
            bill!['items'] is! List)) {
      throw const FormatException('Invalid table bill');
    }
    for (final round in rounds) {
      if (round['id'] is! int ||
          round['round_no'] is! int ||
          round['priced_lines'] is! List ||
          !const {'staff', 'customer'}.contains(round['entered_by'])) {
        throw const FormatException('Invalid round');
      }
    }
  }
  final Map<String, dynamic> json;
  Map<String, dynamic> get table => tableMap(json['table']);
  Map<String, dynamic>? get seating =>
      json['seating'] == null ? null : tableMap(json['seating']);
  Map<String, dynamic>? get bill =>
      json['bill'] == null ? null : tableMap(json['bill']);
  List<Map<String, dynamic>> get rounds =>
      (json['rounds'] as List).map(tableMap).toList()..sort((a, b) {
        final number = (a['round_no'] as int).compareTo(b['round_no'] as int);
        return number == 0
            ? (a['id'] as int).compareTo(b['id'] as int)
            : number;
      });
  int get tableId => table['id'] as int;
  Set<int> get coveredTableIds => {
    tableId,
    ?primaryTableId,
    ...((seating?['joined_table_ids'] as List?) ?? const []).whereType<int>(),
  };
  String? get seatingUuid => seating?['uuid'] as String?;
  int? get primaryTableId => seating?['table_id'] as int?;
  String? get billUuid => bill?['uuid'] as String?;
  String get reference =>
      (bill?['receipt_number'] ??
              bill?['temp_reference'] ??
              seating?['temp_reference'] ??
              '')
          .toString();
  bool get occupied => json['occupied'] == true;
  bool get orphaned => json['orphaned'] == true;
  bool get pendingReview =>
      rounds.any((r) => r['status'] == 'pending_confirmation');
  bool get canAppend =>
      !orphaned &&
      seating?['status'] == 'open' &&
      (bill == null || bill?['status'] == 'open') &&
      (bill == null || bill?['charge'] == 'none');
  // Staff-only bills still use their existing staff checkout, not a QR claim.
  bool get qrBill => bill?['source'] == 'qr_web';
}

/// Immutable, price-free round intent. The selected table can be a joined member;
/// the URL and payload always address the canonical primary seating.
class DineInRequest {
  DineInRequest({
    required this.tableId,
    required this.seatingUuid,
    required this.billUuid,
    required Map<String, dynamic> payload,
  }) : encoded = jsonEncode(payload) {
    final p = this.payload;
    if (tableId < 1 ||
        seatingUuid.isEmpty ||
        p['table_id'] is! int ||
        p['client_request_id'] is! String ||
        p['seating_key'] is! String ||
        p['submitted_at'] is! String ||
        p['queued_offline'] != false ||
        p.keys.any(
          (k) => !const {
            'table_id',
            'client_request_id',
            'seating_key',
            'submitted_at',
            'queued_offline',
            'staff_id',
            'lines',
          }.contains(k),
        )) {
      throw const FormatException('Invalid round intent');
    }
    final lines = p['lines'] as List;
    if (lines.isEmpty || lines.length > 50) {
      throw const FormatException('Invalid lines');
    }
    for (final raw in lines) {
      final line = tableMap(raw);
      if (line.keys.any(
        (k) => !const {'product_id', 'qty', 'addon_ids', 'notes'}.contains(k),
      )) {
        throw const FormatException('Client price or ownership field');
      }
      QrQuickLine.fromJson(line);
    }
  }
  factory DineInRequest.create(
    DineInDetail detail,
    List<QrQuickLine> lines,
    int? staffId,
  ) => DineInRequest(
    tableId: detail.tableId,
    seatingUuid: detail.seatingUuid!,
    billUuid: detail.billUuid,
    payload: {
      'table_id': detail.primaryTableId!,
      'seating_key': QrQuickRequest.newId(),
      'client_request_id': QrQuickRequest.newId(),
      'queued_offline': false,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'staff_id': ?staffId,
      'lines': lines.map((line) => line.toJson()).toList(),
    },
  );
  final int tableId;
  final String seatingUuid;
  final String? billUuid;
  final String encoded;
  Map<String, dynamic> get payload => tableMap(jsonDecode(encoded));
  String get id => payload['client_request_id'] as String;
}
