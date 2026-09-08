import 'qr_till_models.dart';

/// A read-only A1 snapshot. No cart, held-store or outbox representation.
class QrPendingOrder {
  QrPendingOrder.fromJson(Map<String, dynamic> json)
    : json = Map.unmodifiable(json),
      active = QrActiveOrder.fromJson(json);

  final Map<String, dynamic> json;
  final QrActiveOrder active;
  String get uuid => active.uuid;
  String get reference => active.receiptNumber ?? active.tempReference ?? uuid;
  String get route => json['route'] as String? ?? '';
  String get session => json['session'] as String? ?? 'missing';
  String get charge => json['charge'] as String? ?? 'uncertain';
  int get ageSeconds => (json['age_seconds'] as num?)?.toInt() ?? 0;
  String? get phoneTail => json['phone_tail'] as String?;
  String? get refusalCode => json['refusal_code'] as String?;
  bool get canSettle => (json['actions'] as Map?)?['settle'] == true;
  bool get canMove => (json['actions'] as Map?)?['to_counter'] == true;
  QrBoardOrder get boardOrder => QrBoardOrder(
    uuid: uuid,
    status: active.status,
    receiptNumber: active.receiptNumber,
    tempReference: active.tempReference,
    acceptedTotalBaisas: active.grandTotalBaisas,
  );
}
