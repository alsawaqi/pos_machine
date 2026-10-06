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

  /// LAUNCH-P6 — a customer tablet's Quick / To go order shown in the
  /// existing manager payment review (F-13): display data only, never a
  /// cart, and never listed with the QR quick orders.
  QrQuickOrder.review({
    required String uuid,
    required String reference,
    required int total,
    String charge = 'uncertain',
  }) : json = Map<String, dynamic>.unmodifiable({
         'uuid': uuid,
         'source': 'customer_tablet',
         'temp_reference': reference,
         'grand_total_baisas': total,
         'charge': charge,
         'session': 'none',
         'items': const <Object>[],
       });

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

/// LAUNCH-P4 C7 — one chosen item of a combo on a server-priced line (quick
/// QR, staff table rounds): identity only, per ONE combo — never a price.
class QrQuickComboPick {
  QrQuickComboPick(
    this.slotId,
    this.productId, {
    this.quantity = 1,
    List<int> addons = const [],
    this.notes,
  }) : addonIds = List.unmodifiable(addons) {
    if (slotId < 1 ||
        productId < 1 ||
        quantity < 1 ||
        quantity > 99 ||
        addonIds.length > 30 ||
        addonIds.toSet().length != addonIds.length ||
        addonIds.any((id) => id < 1) ||
        (notes?.length ?? 0) > 500) {
      throw const FormatException('Invalid combo choice');
    }
  }
  final int slotId;
  final int productId;
  final int quantity;
  final List<int> addonIds;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'slot_id': slotId,
    'product_id': productId,
    'qty': quantity,
    'addon_ids': addonIds,
    if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
  };

  factory QrQuickComboPick.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
      (key) =>
          !{'slot_id', 'product_id', 'qty', 'addon_ids', 'notes'}.contains(key),
    )) {
      throw const FormatException('Unexpected combo field');
    }
    return QrQuickComboPick(
      json['slot_id'] as int,
      json['product_id'] as int,
      quantity: json['qty'] as int? ?? 1,
      addons: ((json['addon_ids'] as List?) ?? const []).cast<int>(),
      notes: json['notes'] as String?,
    );
  }

  String get signature {
    final ids = [...addonIds]..sort();
    return '$slotId:$productId:$quantity:${ids.join(',')}:'
        '${(notes ?? '').trim().toLowerCase()}';
  }
}

/// The only outbound line shape. Intentionally has no price/discount/tax field.
/// LAUNCH-P4 C7 — a combo line also carries its [combo] choices (identity
/// only: the server prices them and refuses client prices).
class QrQuickLine {
  QrQuickLine(
    this.productId,
    this.quantity,
    List<int> addons, {
    this.notes,
    List<QrQuickComboPick> combo = const [],
  }) : addonIds = List.unmodifiable(addons),
       combo = List.unmodifiable(combo) {
    if (productId < 1 ||
        quantity < 1 ||
        quantity > 99 ||
        addonIds.length > 30 ||
        addonIds.toSet().length != addonIds.length ||
        addonIds.any((id) => id < 1) ||
        (notes?.length ?? 0) > 500 ||
        this.combo.length > 30) {
      throw const FormatException('Invalid addition line');
    }
  }
  final int productId;
  final int quantity;
  final List<int> addonIds;
  final String? notes;
  final List<QrQuickComboPick> combo;

  /// The same choices (combo picks compared as a set).
  String get comboSignature =>
      (combo.map((c) => c.signature).toList()..sort()).join(';');

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'qty': quantity,
    'addon_ids': addonIds,
    'notes': notes,
    if (combo.isNotEmpty) 'combo': [for (final c in combo) c.toJson()],
  };
  factory QrQuickLine.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
      (key) =>
          !{'product_id', 'qty', 'addon_ids', 'notes', 'combo'}.contains(key),
    )) {
      throw const FormatException('Unexpected addition field');
    }
    return QrQuickLine(
      json['product_id'] as int,
      json['qty'] as int,
      (json['addon_ids'] as List).cast<int>(),
      notes: json['notes'] as String?,
      combo: [
        for (final c in (json['combo'] as List?) ?? const [])
          QrQuickComboPick.fromJson(qrMap(c)),
      ],
    );
  }
}

/// LAUNCH-P4 C7 — a server bill line's nested combo items, per ONE combo.
/// Bills, transfers, pending and active orders call them `combo`; frozen
/// QR / table rounds call them `components`. Empty for a standard line.
List<Map<String, dynamic>> serverComboOf(Map<dynamic, dynamic> line) => [
  for (final c in ((line['combo'] ?? line['components']) as List?) ?? const [])
    if (c is Map) c.cast<String, dynamic>(),
];

/// LAUNCH-P4 C7 — the choices of a server combo line as request picks, so an
/// edit (more of the same, options changed) sends the same combo back.
List<QrQuickComboPick> serverComboPicks(Map<dynamic, dynamic> line) => [
  for (final c in serverComboOf(line))
    if ((c['slot_id'] as num?)?.toInt() case final int slot when slot > 0)
      if ((c['product_id'] as num?)?.toInt() case final int product
          when product > 0)
        QrQuickComboPick(
          slot,
          product,
          quantity: ((c['qty'] as num?) ?? 1).round().clamp(1, 99),
          addons: [
            for (final a in (c['addons'] as List?) ?? const [])
              if (a is Map && (a['add_on_id'] as num?)?.toInt() != null)
                (a['add_on_id'] as num).toInt(),
            for (final id in (c['addon_ids'] as List?) ?? const [])
              if (id is num) id.toInt(),
          ].toSet().toList(),
          notes: (c['notes'] as String?)?.trim().isEmpty ?? true
              ? null
              : c['notes'] as String,
        ),
];

/// LAUNCH-P4 C7 — display text for a server combo line's items: each chosen
/// item ("> 2 x Fries (+0.300)") followed by its add-ons ("   + Large").
List<String> serverComboLabels(
  Map<dynamic, dynamic> line, {
  required bool arabic,
}) {
  String pick(Map<String, dynamic> m, List<String> en, List<String> ar) {
    if (arabic) {
      for (final key in ar) {
        final v = m[key]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    for (final key in en) {
      final v = m[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return m['product_id'] == null ? '' : '#${m['product_id']}';
  }

  final labels = <String>[];
  for (final c in serverComboOf(line)) {
    final qty = (c['qty'] as num?) ?? 1;
    final extra = (c['extra_price_baisas'] as num?)?.toInt() ?? 0;
    final name = pick(
      c,
      ['name', 'product_name'],
      ['name_ar', 'product_name_ar'],
    );
    labels.add(
      '> ${qty == 1 ? '' : '${qty == qty.roundToDouble() ? qty.toInt() : qty} x '}'
      '$name${extra > 0 ? ' (+${(extra / 1000).toStringAsFixed(3)})' : ''}',
    );
    for (final a in (c['addons'] as List?) ?? const []) {
      if (a is! Map) continue;
      final label = pick(
        a.cast<String, dynamic>(),
        ['name', 'add_on_name'],
        ['name_ar', 'add_on_name_ar'],
      );
      if (label.isNotEmpty) labels.add('   + $label');
    }
    final notes = c['notes']?.toString().trim() ?? '';
    if (notes.isNotEmpty) labels.add('   $notes');
  }
  return labels;
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

/// LAUNCH-P4 C7 — a draft combo line's items in the server bill shape (so the
/// cart shows them like a saved bill), each with `unit_delta_baisas` = qty ×
/// (extra + add-ons) for the draft's estimated total. The server prices the
/// real line.
List<Map<String, dynamic>> quickComboRows(
  QrQuickLine line,
  QuickProduct? product,
  QuickProduct? Function(int id) lookup,
) => [
  for (final pick in line.combo)
    () {
      final slot = product?.comboSlots
          .where((s) => s.id == pick.slotId)
          .firstOrNull;
      final option = slot?.options
          .where((o) => o.productId == pick.productId)
          .firstOrNull;
      final item = lookup(pick.productId);
      final choices = [
        for (final group in item?.groups ?? const <QuickGroup>[])
          for (final choice in group.choices)
            if (pick.addonIds.contains(choice.id)) choice,
      ];
      final extra = option?.extraPriceBaisas ?? 0;
      return <String, dynamic>{
        'slot_id': pick.slotId,
        'product_id': pick.productId,
        'product_name': item?.name ?? '#${pick.productId}',
        'product_name_ar': item?.nameAr ?? '',
        'qty': pick.quantity,
        'extra_price_baisas': extra,
        if ((pick.notes ?? '').trim().isNotEmpty) 'notes': pick.notes,
        'addons': [
          for (final c in choices)
            {
              'add_on_id': c.id,
              'add_on_name': c.name,
              'add_on_name_ar': c.nameAr,
              'price_delta_baisas': c.priceBaisas,
            },
        ],
        'unit_delta_baisas':
            pick.quantity *
            (extra + choices.fold<int>(0, (n, c) => n + c.priceBaisas)),
      };
    }(),
];

/// LAUNCH-P4 C7 — one option of a combo slot in the server-priced picker.
class QuickComboOption {
  const QuickComboOption(
    this.productId, {
    this.extraPriceBaisas = 0,
    this.isDefault = false,
  });
  final int productId;
  final int extraPriceBaisas; // display only; the server prices it
  final bool isDefault;
}

/// LAUNCH-P4 C7 — one choice slot of a combo in the server-priced picker.
class QuickComboSlot {
  const QuickComboSlot(
    this.id,
    this.name, {
    this.nameAr = '',
    this.min = 1,
    this.max = 1,
    this.options = const [],
  });
  final int id;
  final String name;
  final String nameAr;
  final int min;
  final int max;
  final List<QuickComboOption> options;
}

class QuickProduct {
  const QuickProduct(
    this.id,
    this.name, {
    this.nameAr = '',
    this.groups = const [],
    this.available = true,
    this.priceBaisas = 0,
    this.comboSlots = const [],
  });
  final int id;
  final String name;
  final String nameAr;
  final List<QuickGroup> groups;
  final bool available;
  final int priceBaisas;
  // LAUNCH-P4 C7 — a combo's slots (empty for a standard product).
  final List<QuickComboSlot> comboSlots;
  bool get isCombo => comboSlots.isNotEmpty;
}
