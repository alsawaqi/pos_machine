import 'dart:convert';
import 'dart:math';

Map<String, dynamic> qrMap(Object? value) =>
    (value as Map).cast<String, dynamic>();

/// Server snapshots are display-only: never turn them into a cart/held order.
class QrQuickOrder {
  QrQuickOrder(Map<String, dynamic> value)
    : json = qrMap(jsonDecode(jsonEncode(value))) {
    if (uuid.isEmpty ||
        json['source'] != 'qr_web' ||
        json['order_type'] != 'quick' ||
        json['table_id'] != null ||
        json['grand_total_baisas'] is! int ||
        json['items'] is! List) {
      throw const FormatException('Invalid QR quick order');
    }
  }
  final Map<String, dynamic> json;
  String get uuid => json['uuid'] as String? ?? '';
  String get reference =>
      (json['receipt_number'] ?? json['temp_reference'] ?? uuid).toString();
  int get total => json['grand_total_baisas'] as int;
  String get status => json['status'] as String? ?? '';
  String get charge => json['charge'] as String? ?? 'uncertain';
  String get session => json['session'] as String? ?? 'missing';
  String? get refusal => json['refusal_code'] as String?;
  String get phoneTail => json['phone_tail'] as String? ?? '';
  int get ageSeconds => (json['age_seconds'] as num?)?.toInt() ?? 0;
  // Replaced/deleted rows remain in json for history, not the current bill.
  List<Map<String, dynamic>> get items => (json['items'] as List)
      .map(qrMap)
      .where((line) => line['status'] != 'void' && (line['qty'] as num) > 0)
      .toList();
  bool get canPay => (json['actions'] as Map?)?['settle'] == true;
  bool get canMove => (json['actions'] as Map?)?['to_counter'] == true;
  bool get canAdd =>
      status == 'held' &&
      charge == 'none' &&
      json['transferred_to_device_id'] == null;
}

/// The only outbound line shape. Intentionally has no price/discount/tax field.
class QrQuickLine {
  QrQuickLine(this.productId, this.quantity, List<int> addons, {this.notes})
    : addonIds = List.unmodifiable(addons) {
    if (productId < 1 ||
        quantity < 1 ||
        quantity > 99 ||
        addonIds.length > 30 ||
        addonIds.toSet().length != addonIds.length ||
        addonIds.any((id) => id < 1) ||
        (notes?.length ?? 0) > 500) {
      throw const FormatException('Invalid addition line');
    }
  }
  final int productId;
  final int quantity;
  final List<int> addonIds;
  final String? notes;
  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'qty': quantity,
    'addon_ids': addonIds,
    'notes': notes,
  };
  factory QrQuickLine.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
      (key) => !{'product_id', 'qty', 'addon_ids', 'notes'}.contains(key),
    )) {
      throw const FormatException('Unexpected addition field');
    }
    return QrQuickLine(
      json['product_id'] as int,
      json['qty'] as int,
      (json['addon_ids'] as List).cast<int>(),
      notes: json['notes'] as String?,
    );
  }
}

class QrQuickRequest {
  QrQuickRequest(
    this.orderUuid,
    this.id,
    List<QrQuickLine> lines, {
    Map<String, dynamic>? change,
  }) : change = change == null ? null : Map.unmodifiable(change),
       lines = List.unmodifiable(lines) {
    if (orderUuid.isEmpty ||
        id.isEmpty ||
        (lines.isEmpty && change == null) ||
        lines.length > 50) {
      throw const FormatException('Invalid addition request');
    }
  }
  final String orderUuid;
  final String id;
  final List<QrQuickLine> lines;
  final Map<String, dynamic>? change;
  Map<String, dynamic> get payload => {
    'client_request_id': id,
    ...?change,
    if (change == null || lines.isNotEmpty)
      'lines': lines.map((line) => line.toJson()).toList(),
  };
  static String newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class QrQuickFailure implements Exception {
  const QrQuickFailure(this.code, this.message, {this.refused = false});
  final String code;
  final String message;

  /// Only a structured, deliberate no-write 4xx response, never transport/5xx.
  final bool refused;
}

class QuickChoice {
  const QuickChoice(
    this.id,
    this.name, {
    this.nameAr = '',
    this.selected = false,
    this.priceBaisas = 0,
  });
  final int id;
  final String name;
  final String nameAr;
  final bool selected;
  final int priceBaisas;
}

class QuickGroup {
  const QuickGroup(
    this.name,
    this.choices, {
    this.nameAr = '',
    this.min = 0,
    required this.max,
  });
  final String name;
  final String nameAr;
  final List<QuickChoice> choices;
  final int min;
  final int max;
}

class QuickProduct {
  const QuickProduct(
    this.id,
    this.name, {
    this.nameAr = '',
    this.groups = const [],
    this.available = true,
    this.priceBaisas = 0,
  });
  final int id;
  final String name;
  final String nameAr;
  final List<QuickGroup> groups;
  final bool available;
  final int priceBaisas;
}
