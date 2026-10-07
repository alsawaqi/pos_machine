import 'dart:convert';

/// The local ledger is separate from the server's read-only shadow tables.
abstract interface class TableLedgerStore {
  Future<void> saveLocalTableRound(LocalTableRound round);
  Future<List<LocalTableRound>> readLocalTableRounds({
    String? tableId,
    String? seatingKey,
  });
  Future<void> saveLocalLineCancellation(LocalLineCancellation cancellation);
  Future<List<LocalLineCancellation>> readLocalLineCancellations({
    String? tableId,
    String? seatingKey,
  });
  Future<int> addTableSyncVerdict(TableSyncVerdict verdict);
  Future<List<TableSyncVerdict>> readTableSyncVerdicts({
    bool unseenOnly = false,
    int limit = 200,
  });
  Future<void> markTableSyncVerdictsSeen(List<int> ids);
  Future<void> updateTableSyncFields(
    String tableId,
    Map<String, Object?> fields,
  );
}

/// Stored JSON is immutable. Acknowledgements replace only named ledger fields.
class LocalTableRound {
  LocalTableRound({
    required String clientRequestId,
    required String tableId,
    required String seatingKey,
    required int localRoundNo,
    required List<Map<String, dynamic>> lines,
    required DateTime submittedAt,
    required String outboxKey,
    DateTime? printedAt,
    String status = 'queued',
    int? serverRoundId,
    int? serverRoundNo,
    String? orderUuid,
    int? totalBaisas,
    List<String>? reviewReasons,
    List<Map<String, dynamic>>? heldLines,
    DateTime? ackedAt,
  }) : this.fromRow({
         'client_request_id': clientRequestId,
         'table_id': tableId,
         'seating_key': seatingKey,
         'local_round_no': localRoundNo,
         'lines_json': jsonEncode(lines),
         'submitted_at': submittedAt.toIso8601String(),
         'printed_at': printedAt?.toIso8601String(),
         'outbox_key': outboxKey,
         'status': status,
         'server_round_id': serverRoundId,
         'server_round_no': serverRoundNo,
         'order_uuid': orderUuid,
         'total_baisas': totalBaisas,
         'review_reasons_json': reviewReasons == null
             ? null
             : jsonEncode(reviewReasons),
         'held_lines_json': heldLines == null ? null : jsonEncode(heldLines),
         'acked_at': ackedAt?.toIso8601String(),
       });

  LocalTableRound.fromRow(Map<String, Object?> row)
    : _row = Map.unmodifiable(row);
  final Map<String, Object?> _row;
  String get clientRequestId => _row['client_request_id'] as String;
  String get tableId => _row['table_id'] as String;
  String get seatingKey => _row['seating_key'] as String;
  int get localRoundNo => _row['local_round_no'] as int;
  List<Map<String, dynamic>> get lines => _maps(_row['lines_json']);
  DateTime get submittedAt => DateTime.parse(_row['submitted_at'] as String);
  DateTime? get printedAt => _date(_row['printed_at']);
  String get outboxKey => _row['outbox_key'] as String;
  String get status => _row['status'] as String;
  int? get serverRoundId => _row['server_round_id'] as int?;
  int? get serverRoundNo => _row['server_round_no'] as int?;
  String? get orderUuid => _row['order_uuid'] as String?;
  int? get totalBaisas => _row['total_baisas'] as int?;
  List<String> get reviewReasons =>
      (jsonDecode(_row['review_reasons_json'] as String? ?? '[]') as List)
          .cast<String>();
  List<Map<String, dynamic>> get heldLines => _maps(_row['held_lines_json']);
  DateTime? get ackedAt => _date(_row['acked_at']);
  Map<String, Object?> toRow() => Map.of(_row);
  LocalTableRound withChanges(Map<String, Object?> fields) =>
      LocalTableRound.fromRow({..._row, ...fields});
}

class LocalLineCancellation {
  LocalLineCancellation({
    required String clientRequestId,
    required String tableId,
    required String seatingKey,
    required int productId,
    required List<int> addonIds,
    required int qty,
    required bool prepared,
    required DateTime cancelledAt,
    required String outboxKey,
    String? notes,
    String? reason,
    String? authorizedBy,
    String status = 'queued',
    int? cancelledQty,
    DateTime? ackedAt,
    Map<String, dynamic>? line,
  }) : this.fromRow({
         'client_request_id': clientRequestId,
         'table_id': tableId,
         'seating_key': seatingKey,
         'product_id': productId,
         'addon_ids_json': jsonEncode(addonIds),
         'notes': notes,
         'qty': qty,
         'prepared': prepared ? 1 : 0,
         'reason': reason,
         'authorized_by': authorizedBy,
         'cancelled_at': cancelledAt.toIso8601String(),
         'outbox_key': outboxKey,
         'status': status,
         'cancelled_qty': cancelledQty,
         'acked_at': ackedAt?.toIso8601String(),
         // LAUNCH combo add-on — only a meal / combo line stores its identity
         // (a standard cancellation keeps its exact historical row).
         if (line != null &&
             (line['meal_id'] != null ||
                 (line['combo'] is List && (line['combo'] as List).isNotEmpty)))
           'line_json': jsonEncode({
             if (line['meal_id'] != null) 'meal_id': line['meal_id'],
             if (line['combo'] is List && (line['combo'] as List).isNotEmpty)
               'combo': line['combo'],
           }),
       });

  LocalLineCancellation.fromRow(Map<String, Object?> row)
    : _row = Map.unmodifiable(row);
  final Map<String, Object?> _row;
  String get clientRequestId => _row['client_request_id'] as String;
  String get tableId => _row['table_id'] as String;
  String get seatingKey => _row['seating_key'] as String;
  int get productId => _row['product_id'] as int;
  List<int> get addonIds =>
      (jsonDecode(_row['addon_ids_json'] as String) as List).cast<int>();
  String? get notes => _row['notes'] as String?;
  int get qty => _row['qty'] as int;
  bool get prepared => _row['prepared'] == 1;
  String? get reason => _row['reason'] as String?;
  String? get authorizedBy => _row['authorized_by'] as String?;
  DateTime get cancelledAt => DateTime.parse(_row['cancelled_at'] as String);
  String get outboxKey => _row['outbox_key'] as String;
  String get status => _row['status'] as String;
  int? get cancelledQty => _row['cancelled_qty'] as int?;

  /// LAUNCH combo add-on — the cancelled line's meal id and served items
  /// (`{meal_id?, combo?}`), so the cancellation offsets exactly that line in
  /// the round delta (a meal is never its main alone). Empty for a standard
  /// line.
  Map<String, dynamic> get lineIdentity {
    final raw = _row['line_json'];
    if (raw is! String || raw.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : const {};
  }

  DateTime? get ackedAt => _date(_row['acked_at']);
  Map<String, Object?> toRow() => Map.of(_row);
  LocalLineCancellation withChanges(Map<String, Object?> fields) =>
      LocalLineCancellation.fromRow({..._row, ...fields});
}

class TableSyncVerdict {
  TableSyncVerdict({
    int? id,
    required DateTime observedAt,
    required String tableId,
    String? seatingKey,
    required String eventKind,
    required String outcome,
    Map<String, dynamic>? detail,
    bool seen = false,
  }) : this.fromRow({
         'id': ?id,
         'observed_at': observedAt.toIso8601String(),
         'table_id': tableId,
         'seating_key': seatingKey,
         'event_kind': eventKind,
         'outcome': outcome,
         'detail_json': detail == null ? null : jsonEncode(detail),
         'seen': seen ? 1 : 0,
       });

  TableSyncVerdict.fromRow(Map<String, Object?> row)
    : _row = Map.unmodifiable(row);
  final Map<String, Object?> _row;
  int? get id => _row['id'] as int?;
  DateTime get observedAt => DateTime.parse(_row['observed_at'] as String);
  String get tableId => _row['table_id'] as String;
  String? get seatingKey => _row['seating_key'] as String?;
  String get eventKind => _row['event_kind'] as String;
  String get outcome => _row['outcome'] as String;
  Map<String, dynamic> get detail =>
      (jsonDecode(_row['detail_json'] as String? ?? '{}') as Map)
          .cast<String, dynamic>();
  bool get seen => _row['seen'] == 1;
  Map<String, Object?> toRow() => Map.of(_row);
}

List<Map<String, dynamic>> _maps(Object? value) => [
  for (final row in jsonDecode(value as String? ?? '[]') as List)
    Map<String, dynamic>.from(row as Map),
];
DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
