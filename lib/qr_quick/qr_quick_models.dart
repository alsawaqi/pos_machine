import 'dart:convert';
import 'dart:math';

import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

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

/// LAUNCH combo add-on — one served item of a combo / meal on a
/// server-priced line (quick QR, staff table rounds, tablet edits; §7.4):
/// identity only, per ONE combo / meal — never a price. A fixed line left
/// out is served as is.
class QrQuickComboPick {
  QrQuickComboPick(
    this.lineId,
    this.productId, {
    this.quantity = 1,
    List<int> addons = const [],
    this.notes,
  }) : addonIds = List.unmodifiable(addons) {
    if (lineId < 1 ||
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
  final int lineId;
  final int productId;
  final int quantity;
  final List<int> addonIds;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'line_id': lineId,
    'product_id': productId,
    'qty': quantity,
    'addon_ids': addonIds,
    if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
  };

  factory QrQuickComboPick.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
      (key) =>
          !{'line_id', 'product_id', 'qty', 'addon_ids', 'notes'}.contains(key),
    )) {
      throw const FormatException('Unexpected combo field');
    }
    return QrQuickComboPick(
      json['line_id'] as int,
      json['product_id'] as int,
      quantity: json['qty'] as int? ?? 1,
      addons: ((json['addon_ids'] as List?) ?? const []).cast<int>(),
      notes: json['notes'] as String?,
    );
  }

  String get signature {
    final ids = [...addonIds]..sort();
    return '$lineId:$productId:$quantity:${ids.join(',')}:'
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
    this.mealId,
  }) : addonIds = List.unmodifiable(addons),
       combo = List.unmodifiable(combo) {
    if (productId < 1 ||
        (mealId != null && mealId! < 1) ||
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
  // LAUNCH combo add-on — "Make it a meal?": [productId] is the MAIN.
  final int? mealId;

  /// The same items (combo picks compared as a set; a meal is never its
  /// main alone).
  String get comboSignature =>
      '${mealId ?? ''}|'
      '${(combo.map((c) => c.signature).toList()..sort()).join(';')}';

  /// The same line with another quantity (choices kept).
  QrQuickLine withQuantity(int quantity) => QrQuickLine(
    productId,
    quantity,
    addonIds,
    notes: notes,
    combo: combo,
    mealId: mealId,
  );

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'qty': quantity,
    'addon_ids': addonIds,
    'notes': notes,
    if (mealId != null) 'meal_id': mealId,
    if (combo.isNotEmpty) 'combo': [for (final c in combo) c.toJson()],
  };
  factory QrQuickLine.fromJson(Map<String, dynamic> json) {
    if (json.keys.any(
      (key) => !{
        'product_id',
        'qty',
        'addon_ids',
        'notes',
        'combo',
        'meal_id',
      }.contains(key),
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
      mealId: json['meal_id'] as int?,
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

/// LAUNCH combo add-on — the items of a server combo / meal line as request
/// picks, so an edit (more of the same, options changed) sends the same
/// items back. A fixed line the server filled (served as is) and a meal's
/// main (the line itself) are left out.
List<QrQuickComboPick> serverComboPicks(Map<dynamic, dynamic> line) => [
  for (final c in serverComboOf(line))
    if (c['filled'] != true && c['kind'] != 'main')
      if ((c['line_id'] as num?)?.toInt() case final int lineId when lineId > 0)
        if ((c['product_id'] as num?)?.toInt() case final int product
            when product > 0)
          QrQuickComboPick(
            lineId,
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
  // A meal's main is the line itself: listed first, with its add-ons.
  if (line['meal_id'] != null) {
    final main = pick(
      line.cast<String, dynamic>(),
      ['product_name', 'name'],
      ['product_name_ar', 'name_ar'],
    );
    if (main.isNotEmpty) labels.add('> $main');
    for (final a in (line['addons'] as List?) ?? const []) {
      if (a is! Map) continue;
      final label = pick(
        a.cast<String, dynamic>(),
        ['name', 'add_on_name'],
        ['name_ar', 'add_on_name_ar'],
      );
      if (label.isNotEmpty) labels.add('   + $label');
    }
  }
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

/// LAUNCH combo add-on — the lines a draft line's combo / meal is built
/// from: the meal's lines for a meal line, else the combo product's.
List<pricing.ComboLineDef> quickComboLines(
  QrQuickLine line,
  QuickProduct? product,
) => line.mealId != null && product?.meal?.id == line.mealId
    ? product!.meal!.lines
    : product?.comboLines ?? const [];

/// LAUNCH combo add-on — a draft combo / meal line's items in the server
/// bill shape (so the cart shows them like a saved bill), each with
/// `unit_delta_baisas` = qty × max(0, extra + add-ons) for the draft's
/// estimated total. The server prices the real line.
List<Map<String, dynamic>> quickComboRows(
  QrQuickLine line,
  QuickProduct? product,
  QuickProduct? Function(int id) lookup,
) {
  final lines = quickComboLines(line, product);
  final resolved = pricing.resolveComboPicks(lines, [
    for (final pick in line.combo)
      pricing.ComboPick(
        lineId: pick.lineId,
        productId: pick.productId,
        qty: pick.quantity,
      ),
  ]);
  return [
    for (final pick in line.combo)
      () {
        final item = lookup(pick.productId);
        final choices = [
          for (final group in item?.groups ?? const <QuickGroup>[])
            for (final choice in group.choices)
              if (pick.addonIds.contains(choice.id)) choice,
        ];
        final served = resolved.items
            .where(
              (i) => i.lineId == pick.lineId && i.productId == pick.productId,
            )
            .firstOrNull;
        final extra = served?.extraPriceBaisas ?? 0;
        return <String, dynamic>{
          'line_id': pick.lineId,
          'kind': served?.kind.wire ?? 'choice',
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
          'unit_delta_baisas': pricing.comboItemPriceBaisas(
            qty: pick.quantity,
            extraPriceBaisas: extra,
            addOnDeltasBaisas: [for (final c in choices) c.priceBaisas],
          ),
        };
      }(),
  ];
}

/// LAUNCH combo add-on — a draft line's estimated unit price (§7.5 with the
/// floors): a standard line max(0, price + add-ons); a combo its price +
/// its items; a meal its main (+ add-ons) + meal price + its items. Display
/// only — the server prices the real line.
int quickDraftUnitBaisas(
  QrQuickLine line,
  QuickProduct? product,
  List<Map<String, dynamic>> comboRows,
  List<int> addOnDeltasBaisas,
) {
  final items = [for (final c in comboRows) c['unit_delta_baisas'] as int];
  final price = product?.priceBaisas ?? 0;
  final meal = product?.meal;
  if (line.mealId != null && meal != null && meal.id == line.mealId) {
    return pricing.mealUnitPriceBaisas(
      mainPriceBaisas: price,
      mainAddOnDeltasBaisas: addOnDeltasBaisas,
      mealPriceBaisas: meal.mealPriceBaisas,
      itemPricesBaisas: items,
    );
  }
  if (product?.isCombo == true || comboRows.isNotEmpty) {
    return pricing.comboUnitPriceBaisas(
      comboPriceBaisas: price,
      itemPricesBaisas: items,
    );
  }
  return pricing.standardUnitPriceBaisas(
    basePriceBaisas: price,
    addOnDeltasBaisas: addOnDeltasBaisas,
  );
}

/// LAUNCH combo add-on — a draft meal line's keys in the server bill shape
/// (`meal_id`, `display_name` "Beef burger meal"); empty for anything else.
Map<String, dynamic> quickMealKeys(QrQuickLine line, QuickProduct? product) {
  final meal = product?.meal;
  if (line.mealId == null || meal == null || meal.id != line.mealId) {
    return const <String, dynamic>{};
  }
  return {
    'meal_id': meal.id,
    'display_name': '${product!.name} ${meal.name}',
    'display_name_ar':
        '${product.nameAr.isEmpty ? product.name : product.nameAr} '
        '${meal.nameAr.isEmpty ? meal.name : meal.nameAr}',
  };
}

/// LAUNCH combo add-on — whether a draft line's combo / meal picks fit its
/// lines (choice lines exactly pick N; nothing not offered).
bool quickComboValid(QrQuickLine line, QuickProduct? product) {
  final lines = quickComboLines(line, product);
  if (lines.isEmpty) return line.combo.isEmpty;
  return pricing.resolveComboPicks(lines, [
    for (final pick in line.combo)
      pricing.ComboPick(
        lineId: pick.lineId,
        productId: pick.productId,
        qty: pick.quantity,
      ),
  ]).isValid;
}

/// LAUNCH combo add-on — the "Make it a meal?" setup a main offers in the
/// server-priced picker.
class QuickMeal {
  const QuickMeal(
    this.id,
    this.name, {
    this.nameAr = '',
    this.mealPriceBaisas = 0,
    this.lines = const [],
    this.available = true,
  });
  final int id;
  final String name;
  final String nameAr;
  final int mealPriceBaisas; // display only; the server prices it
  final List<pricing.ComboLineDef> lines;
  // Fix order 1 (T-C4) — false when a fixed item or a whole choice line is
  // sold out: the main is then added alone, without asking.
  final bool available;
}

class QuickProduct {
  const QuickProduct(
    this.id,
    this.name, {
    this.nameAr = '',
    this.groups = const [],
    this.available = true,
    this.priceBaisas = 0,
    this.combo = false,
    this.comboLines = const [],
    this.meal,
  });
  final int id;
  final String name;
  final String nameAr;
  final List<QuickGroup> groups;
  final bool available;
  final int priceBaisas;
  // LAUNCH combo add-on — a combo product and its lines.
  final bool combo;
  final List<pricing.ComboLineDef> comboLines;
  // LAUNCH combo add-on — the meal this product is a main of.
  final QuickMeal? meal;
  bool get isCombo => combo;
}
