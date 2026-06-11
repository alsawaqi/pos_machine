enum OrderType { quickOrder, toGo, delivery, dineIn }

enum ProductViewMode { grid, list }

enum DiscountKind { none, fixedAmount, percentage }

enum DiningTableStatus { available, occupied, paid }

double _roundStoredMoney(double value) =>
    double.parse(value.toStringAsFixed(3));

extension OrderTypeLabel on OrderType {
  String get label => switch (this) {
    OrderType.quickOrder => 'Quick Order',
    OrderType.toGo => 'To Go',
    OrderType.delivery => 'Delivery',
    OrderType.dineIn => 'Dine In',
  };

  String get storageValue => switch (this) {
    OrderType.quickOrder => 'quick_order',
    OrderType.toGo => 'to_go',
    OrderType.delivery => 'delivery',
    OrderType.dineIn => 'dine_in',
  };

  static OrderType fromStorage(String? value) {
    return switch (value) {
      'to_go' => OrderType.toGo,
      'delivery' => OrderType.delivery,
      'dine_in' => OrderType.dineIn,
      _ => OrderType.quickOrder,
    };
  }
}

extension ProductViewModeLabel on ProductViewMode {
  String get label => this == ProductViewMode.grid ? 'Grid' : 'List';
}

extension DiscountKindLabel on DiscountKind {
  String get storageValue => switch (this) {
    DiscountKind.none => 'none',
    DiscountKind.fixedAmount => 'fixed_amount',
    DiscountKind.percentage => 'percentage',
  };

  static DiscountKind fromStorage(String? value) {
    return switch (value) {
      'fixed_amount' => DiscountKind.fixedAmount,
      'percentage' => DiscountKind.percentage,
      _ => DiscountKind.none,
    };
  }
}

extension DiningTableStatusLabel on DiningTableStatus {
  String get label => switch (this) {
    DiningTableStatus.available => 'Available',
    DiningTableStatus.occupied => 'Occupied',
    DiningTableStatus.paid => 'Paid',
  };

  String get storageValue => switch (this) {
    DiningTableStatus.available => 'available',
    DiningTableStatus.occupied => 'occupied',
    DiningTableStatus.paid => 'paid',
  };

  static DiningTableStatus fromStorage(String? value) {
    return switch (value) {
      'occupied' => DiningTableStatus.occupied,
      'paid' => DiningTableStatus.paid,
      _ => DiningTableStatus.available,
    };
  }
}

class DiningFloor {
  final String id;
  final String label;

  const DiningFloor({required this.id, required this.label});
}

class DiningTableDefinition {
  final String id;
  final String floorId;
  final String name;
  final String sizeLabel;
  final int seats;
  final int sortOrder;
  // Floor-plan layout, mirrored from the merchant planner (px in a 1200x800
  // canvas). Defaults keep older call sites working.
  final String shape;
  final double positionX;
  final double positionY;
  final double width;
  final double height;

  const DiningTableDefinition({
    required this.id,
    required this.floorId,
    required this.name,
    required this.sizeLabel,
    required this.seats,
    required this.sortOrder,
    this.shape = 'square',
    this.positionX = 0,
    this.positionY = 0,
    this.width = 80,
    this.height = 80,
  });
}

/// A company tax fetched from the API config (name + percentage). Applied on
/// top of the order subtotal (exclusive).
class CompanyTax {
  const CompanyTax({required this.name, this.nameAr, required this.ratePercent});
  final String name;
  final String? nameAr;
  final double ratePercent; // 5.0 == 5%
}

/// A computed tax line for an order: the tax + the OMR amount it adds.
class TaxLineAmount {
  const TaxLineAmount({
    required this.name,
    required this.ratePercent,
    required this.amount,
  });
  final String name;
  final double ratePercent;
  final double amount;

  /// "5" for 5.0, "7.5" for 7.5 — used in the cart/receipt label, e.g. "VAT (5%)".
  String get rateLabel => ratePercent == ratePercent.roundToDouble()
      ? ratePercent.toStringAsFixed(0)
      : ratePercent.toString();
}

/// Company taxes currently in effect, set from the API config at staff login
/// (PosController.applyCatalog). A single shared source so the live cart and the
/// persisted / printed order totals agree. Empty => no tax (no implicit 5%).
List<CompanyTax> activeCompanyTaxes = const <CompanyTax>[];

double _roundTax(double v) => double.parse(v.toStringAsFixed(3));

/// Per-tax amounts for [subtotal] — each active company rate applied to the
/// subtotal (exclusive), rounded to 3 decimals (baisas precision).
List<TaxLineAmount> taxLinesFor(double subtotal) => activeCompanyTaxes
    .map((t) => TaxLineAmount(
          name: t.name,
          ratePercent: t.ratePercent,
          amount: _roundTax(subtotal * t.ratePercent / 100),
        ))
    .toList(growable: false);

/// Summed tax for [subtotal] across all active company taxes.
double taxTotalFor(double subtotal) =>
    _roundTax(taxLinesFor(subtotal).fold<double>(0, (s, l) => s + l.amount));

/// One selectable add-on within a group (e.g. "Oat milk", "Extra shot"), with
/// the price it adds to the line. Maps from the API `addons` (price in OMR,
/// converted from baisas at the catalog boundary).
class AddonOption {
  const AddonOption({
    required this.id,
    required this.label,
    this.labelAr,
    required this.priceDelta,
    this.isDefault = false,
  });
  final int id;
  final String label;
  final String? labelAr;
  final double priceDelta; // OMR added to the line when selected
  // Phase B — starts selected when the customize sheet opens.
  final bool isDefault;
}

/// A product's add-on group (e.g. "Size", "Milk", "Extras"), assigned per
/// product in the merchant portal and fetched in the device config. [multiSelect]
/// mirrors the API `selection_mode` ('multiple' vs 'single').
///
/// Phase B (Additions §1.2) — selection constraints: [minSelections] >= 1
/// makes the group REQUIRED (the customize sheet blocks Add until satisfied);
/// [maxSelections] caps how many options can be picked. Null = unbounded.
class AddonGroup {
  const AddonGroup({
    required this.id,
    required this.name,
    this.nameAr,
    required this.multiSelect,
    this.minSelections,
    this.maxSelections,
    required this.options,
  });
  final int id;
  final String name;
  final String? nameAr;
  final bool multiSelect;
  final int? minSelections;
  final int? maxSelections;
  final List<AddonOption> options;

  /// The effective minimum (a single-select group with min null is optional).
  int get effectiveMin => minSelections ?? 0;

  /// The effective maximum (single-select is implicitly capped at 1).
  int get effectiveMax =>
      maxSelections ?? (multiSelect ? options.length : 1);

  bool get isRequired => effectiveMin >= 1;
}

/// Phase B — a company void reason code (the cancel dialog requires one when
/// any exist; order.void sends [id] back so the server snapshots it and
/// decides whether inventory stays consumed).
class VoidReasonRef {
  const VoidReasonRef({
    required this.id,
    required this.code,
    required this.name,
    this.nameAr,
    this.affectsInventory = false,
    this.requiresManager = true,
  });
  final int id;
  final String code;
  final String name;
  final String? nameAr;
  final bool affectsInventory;
  final bool requiresManager;
}

/// Phase B — a comp reason (manager-approved write-off). [maxAmount] caps a
/// single comp in OMR; null = no cap.
class CompReasonRef {
  const CompReasonRef({
    required this.id,
    required this.code,
    required this.name,
    this.nameAr,
    this.maxAmount,
  });
  final int id;
  final String code;
  final String name;
  final String? nameAr;
  final double? maxAmount;
}

/// Phase B — the comp applied to the current order (one at a time on the
/// device; the wire format supports many). [lineIndex] null = whole-order
/// comp. The AMOUNT is always derived live from the cart (the comped line's
/// discounted total, or the whole discounted subtotal) so cart edits can
/// never leave a stale figure.
class AppliedComp {
  const AppliedComp({
    required this.reasonId,
    required this.reasonName,
    this.lineIndex,
    this.note,
  });
  final int reasonId;
  final String reasonName;
  final int? lineIndex;
  final String? note;

  Map<String, dynamic> toMap() => {
        'reasonId': reasonId,
        'reasonName': reasonName,
        'lineIndex': lineIndex,
        'note': note,
      };

  factory AppliedComp.fromMap(Map<String, dynamic> map) => AppliedComp(
        reasonId: (map['reasonId'] as num?)?.toInt() ?? 0,
        reasonName: map['reasonName']?.toString() ?? '',
        lineIndex: (map['lineIndex'] as num?)?.toInt(),
        note: map['note']?.toString(),
      );
}

/// A company delivery provider (Talabat, Otlob, …) the cashier picks on a
/// delivery order. Per-product prices live on [Product.deliveryPriceByProvider].
class DeliveryProvider {
  const DeliveryProvider({
    required this.id,
    required this.name,
    this.color,
    this.sortOrder = 0,
  });
  final int id;
  final String name;
  final String? color; // optional #RRGGBB UI hint
  final int sortOrder;
}

/// Per-branch custom receipt template (merchant-authored, delivered via
/// /device/config). Drives the header + footer the POS device prints. Null
/// fields / an [isEmpty] instance fall back to the built-in default receipt.
class ReceiptTemplate {
  const ReceiptTemplate({
    this.businessName,
    this.businessNameAr,
    this.crNumber,
    this.vatNumber,
    this.address,
    this.phone,
    this.headerLines = const <String>[],
    this.footerLines = const <String>[],
    this.showQr = true,
    this.logoBase64,
  });

  final String? businessName;
  final String? businessNameAr;
  final String? crNumber;
  final String? vatNumber;
  final String? address;
  final String? phone;
  final List<String> headerLines;
  final List<String> footerLines;
  final bool showQr;
  // Base64-encoded PNG of the branch logo (already resized + greyscaled by the
  // merchant portal). Null = no logo. Printed at the top of the receipt.
  final String? logoBase64;

  /// True when there is nothing custom to print (so the caller uses the
  /// default "MITHQAL 2.0" header instead of a blank one). A logo alone counts
  /// as custom content.
  bool get isEmpty =>
      (businessName?.isEmpty ?? true) &&
      (businessNameAr?.isEmpty ?? true) &&
      (crNumber?.isEmpty ?? true) &&
      (vatNumber?.isEmpty ?? true) &&
      (address?.isEmpty ?? true) &&
      (phone?.isEmpty ?? true) &&
      headerLines.isEmpty &&
      footerLines.isEmpty &&
      (logoBase64?.isEmpty ?? true);

  /// Parse the `branch.receipt_template` config object. Returns null when the
  /// branch has no template configured.
  static ReceiptTemplate? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    String? str(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    List<String> lines(Object? v) => v is List
        ? v
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];

    return ReceiptTemplate(
      businessName: str(json['business_name']),
      businessNameAr: str(json['business_name_ar']),
      crNumber: str(json['cr_number']),
      vatNumber: str(json['vat_number']),
      address: str(json['address']),
      phone: str(json['phone']),
      headerLines: lines(json['header_lines']),
      footerLines: lines(json['footer_lines']),
      // Default to printing the QR unless the merchant explicitly turned it off.
      showQr: json['show_qr'] == null ? true : json['show_qr'] == true,
      logoBase64: str(json['logo_base64']),
    );
  }
}

/// One ingredient line of a product's recipe: how much of an ingredient one unit
/// of the product needs. Drives ingredient-based sold-out on the device.
class RecipeLine {
  const RecipeLine({required this.ingredientId, required this.quantity});
  final int ingredientId;
  final double quantity;
}

class Product {
  final String id;
  final String name;
  // Phase C4 — the merchant's Arabic product name (empty = none provided).
  // Cached in Drift from /device/config name_ar; display-only (the English
  // name stays the identity used in snapshots, payloads and receipts).
  final String nameAr;
  final String category;
  // Numeric category id — for matching category-scope discounts to a cart line.
  // Null when unknown (e.g. a product reconstructed from an older snapshot).
  final int? categoryId;
  final double price;
  final String? imageAsset;
  final bool lowStock;
  // Add-on group ids assigned to this product (from the API `addon_group_ids`),
  // resolved to AddonGroups for the modifier sheet. Empty = no add-ons.
  final List<int> addonGroupIds;
  // Delivery pricing (OMR). [deliveryPrice] = in-house delivery default (null =
  // use [price]); [deliveryPriceByProvider] = per-provider overrides keyed by
  // provider id. Resolution: override → deliveryPrice → base price.
  final double? deliveryPrice;
  final Map<int, double> deliveryPriceByProvider;
  // Stock (Phase 7). [stockMode] = unit | ingredient | untracked (null=untracked).
  // [recipe] = ingredient lines for ingredient-mode availability. [branchStockQty]
  // = this branch's unit count for unit-mode availability (null = not tracked).
  final String? stockMode;
  final List<RecipeLine> recipe;
  final double? branchStockQty;
  // Gap sweep G1 — daily availability window ('HH:MM:SS', the pos_discounts
  // convention): both null = always orderable; start > end wraps midnight
  // (22:00→02:00). Evaluated device-side in [isAvailableAt].
  final String? availableFrom;
  final String? availableUntil;

  const Product({
    required this.id,
    required this.name,
    this.nameAr = '',
    required this.category,
    this.categoryId,
    required this.price,
    this.imageAsset,
    this.lowStock = false,
    this.addonGroupIds = const <int>[],
    this.deliveryPrice,
    this.deliveryPriceByProvider = const <int, double>{},
    this.stockMode,
    this.recipe = const <RecipeLine>[],
    this.branchStockQty,
    this.availableFrom,
    this.availableUntil,
  });

  /// The name to SHOW for [arabic] UI — falls back to the English identity
  /// name when the merchant provided no Arabic.
  String displayName(bool arabic) =>
      arabic && nameAr.trim().isNotEmpty ? nameAr : name;

  /// Normalize 'HH:MM' (a raw API caller may omit seconds) to 'HH:MM:SS'.
  static String? _normTime(String? v) {
    if (v == null || v.isEmpty) return null;
    return v.length == 5 ? '$v:00' : v;
  }

  /// Gap sweep G1 — whether this product may be ordered at [now] under its
  /// daily window (clone of MerchantDiscount._matchesTime): both-null =
  /// always; boundaries inclusive; start > end wraps midnight.
  bool isAvailableAt(DateTime now) {
    final from = _normTime(availableFrom);
    final until = _normTime(availableUntil);
    if (from == null && until == null) return true;

    String pad(int v) => v.toString().padLeft(2, '0');
    final hhmmss = '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}';
    final start = from ?? '00:00:00';
    final end = until ?? '23:59:59';
    if (start.compareTo(end) <= 0) {
      return hhmmss.compareTo(start) >= 0 && hhmmss.compareTo(end) <= 0;
    }
    // Overnight window (e.g. 22:00 → 02:00).
    return hhmmss.compareTo(start) >= 0 || hhmmss.compareTo(end) <= 0;
  }

  /// True when a daily window is configured at all.
  bool get hasAvailabilityWindow =>
      (availableFrom != null && availableFrom!.isNotEmpty) ||
      (availableUntil != null && availableUntil!.isNotEmpty);

  /// The unit price to charge on a delivery order for [providerId], following
  /// the merchant's chain: provider override → in-house delivery price → base.
  double deliveryPriceFor(int providerId) =>
      deliveryPriceByProvider[providerId] ?? deliveryPrice ?? price;

  Product copyWith({double? price}) => Product(
        id: id,
        name: name,
        nameAr: nameAr,
        category: category,
        categoryId: categoryId,
        price: price ?? this.price,
        imageAsset: imageAsset,
        lowStock: lowStock,
        addonGroupIds: addonGroupIds,
        deliveryPrice: deliveryPrice,
        deliveryPriceByProvider: deliveryPriceByProvider,
        stockMode: stockMode,
        recipe: recipe,
        branchStockQty: branchStockQty,
        availableFrom: availableFrom,
        availableUntil: availableUntil,
      );

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      nameAr: map['nameAr']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      categoryId: (map['categoryId'] as num?)?.toInt(),
      price:
          (map['basePrice'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble() ??
          0,
      imageAsset: map['imageAsset']?.toString(),
      lowStock: map['lowStock'] == true,
      addonGroupIds: ((map['addonGroupIds'] as List?) ?? const [])
          .map((e) => (e as num?)?.toInt())
          .whereType<int>()
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      if (nameAr.isNotEmpty) 'nameAr': nameAr,
      'category': category,
      'price': price,
      'imageAsset': imageAsset,
      'lowStock': lowStock,
      'addonGroupIds': addonGroupIds,
    };
  }
}

class CartItemModifier {
  final String id;
  final String group;
  final String label;
  // Phase C4 — the add-on's Arabic label (display-only; empty = none).
  final String labelAr;
  final double price;

  const CartItemModifier({
    required this.id,
    required this.group,
    required this.label,
    this.labelAr = '',
    required this.price,
  });

  /// The label to SHOW for [arabic] UI (English stays the identity).
  String displayLabel(bool arabic) =>
      arabic && labelAr.trim().isNotEmpty ? labelAr : label;

  factory CartItemModifier.fromMap(Map<String, dynamic> map) {
    return CartItemModifier(
      id: map['id']?.toString() ?? '',
      group: map['group']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      labelAr: map['labelAr']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group': group,
      'label': label,
      if (labelAr.isNotEmpty) 'labelAr': labelAr,
      'price': price,
    };
  }
}

class CartItem {
  final Product product;
  int qty;
  List<CartItemModifier> modifiers;
  String notes;
  // P-F5 — this line is GIFTED: given away whole (a 100% write-off riding
  // the comp plumbing with is_gift on the wire — no tax, inventory still
  // consumed). Manager-gated on the screen.
  bool gifted;
  // P-F9 — non-empty when this line belongs to a cashier-picked BUNDLE
  // application ('<offerId>:<instance>'). Bundle lines never merge with
  // regular lines; the offer engine re-validates the set on every change.
  String bundleKey;

  CartItem({
    required this.product,
    this.qty = 1,
    List<CartItemModifier>? modifiers,
    this.notes = '',
    this.gifted = false,
    this.bundleKey = '',
  }) : modifiers = List<CartItemModifier>.from(modifiers ?? const []);

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      product: Product.fromMap(map),
      qty: (map['qty'] as num?)?.toInt() ?? 1,
      modifiers: ((map['modifiers'] as List?) ?? const [])
          .map(
            (modifier) => CartItemModifier.fromMap(
              Map<String, dynamic>.from(modifier as Map),
            ),
          )
          .toList(),
      notes: map['notes']?.toString() ?? '',
      gifted: map['gifted'] == true,
      bundleKey: map['bundleKey']?.toString() ?? '',
    );
  }

  double get modifierTotal =>
      modifiers.fold(0, (sum, modifier) => sum + modifier.price);

  double get unitPrice => product.price + modifierTotal;

  double get lineTotal => unitPrice * qty;

  bool get hasCustomization => modifiers.isNotEmpty || notes.trim().isNotEmpty;

  String get normalizedNotes => notes.trim();

  String get mergeSignature {
    final modifierSignature = modifiers
        .map((modifier) => modifier.id)
        .join('|');
    // P-F5 — a gifted line never merges with a paid one (table merges);
    // P-F9 — bundle lines stay distinct per bundle instance.
    return '${product.id}|$modifierSignature|${normalizedNotes.toLowerCase()}'
        '${gifted ? '|gift' : ''}'
        '${bundleKey.isNotEmpty ? '|b:$bundleKey' : ''}';
  }

  List<CartItemModifier> modifiersForGroup(String group) {
    return modifiers.where((modifier) => modifier.group == group).toList();
  }

  String? firstModifierLabel(String group) {
    final groupItems = modifiersForGroup(group);
    if (groupItems.isEmpty) return null;
    return groupItems.first.label;
  }

  List<String> get detailLines => detailLinesFor(false);

  /// Phase C4 — the cart line's modifier/notes summary, with add-on labels in
  /// Arabic when [arabic] (group names + the 'Notes:' prefix stay as authored;
  /// the stored English remains the identity everywhere else).
  List<String> detailLinesFor(bool arabic) {
    final lines = <String>[];
    final grouped = <String, List<CartItemModifier>>{};

    for (final modifier in modifiers) {
      grouped
          .putIfAbsent(modifier.group, () => <CartItemModifier>[])
          .add(modifier);
    }

    for (final entry in grouped.entries) {
      final formattedValues = entry.value
          .map((modifier) {
            final extra = modifier.price <= 0
                ? ''
                : ' (+${modifier.price.toStringAsFixed(3)} OMR)';
            return '${modifier.displayLabel(arabic)}$extra';
          })
          .join(', ');
      lines.add('${entry.key}: $formattedValues');
    }

    if (normalizedNotes.isNotEmpty) {
      lines.add('Notes: $normalizedNotes');
    }

    return lines;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': product.id,
      'name': product.name,
      if (product.nameAr.isNotEmpty) 'nameAr': product.nameAr,
      'category': product.category,
      'qty': qty,
      'basePrice': product.price,
      'modifierTotal': modifierTotal,
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
      'imageAsset': product.imageAsset,
      'lowStock': product.lowStock,
      'modifiers': modifiers.map((modifier) => modifier.toMap()).toList(),
      'notes': normalizedNotes,
      if (gifted) 'gifted': true,
      if (bundleKey.isNotEmpty) 'bundleKey': bundleKey,
      'detailLines': detailLines,
    };
  }
}

class DiscountConfiguration {
  final DiscountKind kind;
  final double value;
  final String label;
  // The merchant rule id when this is a fetched discount (null = manual/ad-hoc).
  // Sent on order.create so the server snapshots the rule for the by-rule report.
  final int? discountId;
  // P-F4 — the cashier's reason for a manual/custom discount (required by the
  // dialog for free-entry values). Recorded on the order's discount row.
  final String reason;

  const DiscountConfiguration({
    this.kind = DiscountKind.none,
    this.value = 0,
    this.label = '',
    this.discountId,
    this.reason = '',
  });

  bool get isActive => kind != DiscountKind.none && value > 0;

  /// The server amount_type for this discount ('percent' | 'fixed' | null).
  String? get amountType => switch (kind) {
        DiscountKind.percentage => 'percent',
        DiscountKind.fixedAmount => 'fixed',
        DiscountKind.none => null,
      };

  factory DiscountConfiguration.fromMap(Map<String, dynamic> map) {
    return DiscountConfiguration(
      kind: DiscountKindLabel.fromStorage(map['kind']?.toString()),
      value: (map['value'] as num?)?.toDouble() ?? 0,
      label: map['label']?.toString() ?? '',
      discountId: (map['discountId'] as num?)?.toInt(),
      reason: map['reason']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'kind': kind.storageValue,
      'value': value,
      'label': label,
      if (discountId != null) 'discountId': discountId,
      if (reason.isNotEmpty) 'reason': reason,
    };
  }
}

/// One product- or category-scope target of a [MerchantDiscount] (which
/// products/categories a line-level rule applies to).
class DiscountTarget {
  final String targetType; // product | category
  final int targetId;

  const DiscountTarget({required this.targetType, required this.targetId});
}

/// A merchant discount rule from the API config bundle. The device offers the
/// currently-applicable ORDER-scope ones in the discount picker, and
/// AUTO-APPLIES product/category-scope ones to matching cart lines. Applicability
/// mirrors the server `Discount` model (validity window / day-of-week mask /
/// time-of-day window / branch scope / targets). Money is OMR (converted from
/// baisas at the cache boundary).
class MerchantDiscount {
  final int id;
  final String name;
  final String scope; // product | category | order
  final String amountType; // fixed | percent
  final double? fixedAmount; // OMR, when amountType == fixed
  final double? percent; // when amountType == percent
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final int? dayOfWeekMask; // 1<<dow (Sun=0); null = every day
  final String? timeStart; // 'HH:MM:SS'
  final String? timeEnd;
  final List<int> branchScope; // empty = all branches
  final bool stackable;
  final bool requiresManagerApproval;
  final bool isActive;
  // P-F4 — order-scope rules with autoApply self-apply to every qualifying
  // order (no cashier action). Product/category scopes auto-apply per line
  // regardless (the longstanding behavior; the merchant UI forces the flag).
  final bool autoApply;
  // product/category-scope targets (which products/categories this rule hits);
  // empty for order-scope rules.
  final List<DiscountTarget> targets;

  const MerchantDiscount({
    required this.id,
    required this.name,
    required this.scope,
    required this.amountType,
    this.fixedAmount,
    this.percent,
    this.validityStart,
    this.validityEnd,
    this.dayOfWeekMask,
    this.timeStart,
    this.timeEnd,
    this.branchScope = const [],
    this.stackable = false,
    this.requiresManagerApproval = false,
    this.isActive = true,
    this.autoApply = false,
    this.targets = const <DiscountTarget>[],
  });

  bool get isOrderScope => scope == 'order';

  /// True when this product/category-scope rule targets the given cart line.
  /// Order-scope rules return false (they apply to the whole order, not a line).
  bool appliesToProduct(int? productId, int? categoryId) {
    if (scope == 'product') {
      return productId != null &&
          targets.any((t) => t.targetType == 'product' && t.targetId == productId);
    }
    if (scope == 'category') {
      return categoryId != null &&
          targets.any((t) => t.targetType == 'category' && t.targetId == categoryId);
    }
    return false;
  }

  /// True when usable right now at [branchId]: active, within the validity
  /// window, on an allowed weekday, within the time window, and in branch scope.
  /// Mirrors pos_merchant Discount::appliesAt.
  bool appliesAt(DateTime now, {required int branchId}) {
    if (!isActive) return false;
    if (validityStart != null && now.isBefore(validityStart!)) return false;
    if (validityEnd != null && now.isAfter(validityEnd!)) return false;
    if (!_matchesDay(now)) return false;
    if (!_matchesTime(now)) return false;
    if (!_matchesBranch(branchId)) return false;
    return true;
  }

  bool _matchesDay(DateTime now) {
    final mask = dayOfWeekMask ?? 127;
    // Dart weekday is 1=Mon..7=Sun; the server mask is 0=Sun..6=Sat → % 7.
    final bit = 1 << (now.weekday % 7);
    return (mask & bit) != 0;
  }

  bool _matchesTime(DateTime now) {
    if (timeStart == null && timeEnd == null) return true;
    final hhmmss =
        '${_pad2(now.hour)}:${_pad2(now.minute)}:${_pad2(now.second)}';
    final start = timeStart ?? '00:00:00';
    final end = timeEnd ?? '23:59:59';
    if (start.compareTo(end) <= 0) {
      return hhmmss.compareTo(start) >= 0 && hhmmss.compareTo(end) <= 0;
    }
    // Midnight wrap (e.g. 22:00 → 02:00).
    return hhmmss.compareTo(start) >= 0 || hhmmss.compareTo(end) <= 0;
  }

  bool _matchesBranch(int branchId) =>
      branchScope.isEmpty || branchScope.contains(branchId);

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// The discount amount in OMR for an order [subtotal] (clamped to it).
  double amountFor(double subtotal) {
    final raw = amountType == 'percent'
        ? subtotal * ((percent ?? 0) / 100)
        : (fixedAmount ?? 0);
    final clamped = raw.clamp(0.0, subtotal).toDouble();
    return double.parse(clamped.toStringAsFixed(3));
  }

  /// The DiscountConfiguration this rule applies as (carries the rule id +
  /// amount_type so order.pay can snapshot it for the by-rule report).
  DiscountConfiguration toConfiguration() => DiscountConfiguration(
        kind: amountType == 'percent'
            ? DiscountKind.percentage
            : DiscountKind.fixedAmount,
        value: amountType == 'percent' ? (percent ?? 0) : (fixedAmount ?? 0),
        label: name,
        discountId: id,
      );
}

/// P-F9 — a merchant OFFER (promotion) from the config bundle. `type` is one
/// of bogo | bundle | multi_buy | cheapest_free | spend_get; [config] holds
/// the type-specific shape (see the offer engine). Shared applicability
/// (validity window / weekday mask / time window / branch scope) mirrors
/// [MerchantDiscount]. Auto types self-apply on the device; bundles are
/// cashier-picked. Money inside config is integer baisas.
class Offer {
  final int id;
  final String name;
  final String? nameAr;
  final String type;
  final Map<String, dynamic> config;
  final bool autoApply;
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final int? dayOfWeekMask;
  final String? timeStart; // 'HH:MM:SS'
  final String? timeEnd;
  final List<int> branchScope; // empty = all branches
  final int? maxPerOrder; // null = unlimited applications per order
  final bool isActive;

  const Offer({
    required this.id,
    required this.name,
    this.nameAr,
    required this.type,
    this.config = const {},
    this.autoApply = true,
    this.validityStart,
    this.validityEnd,
    this.dayOfWeekMask,
    this.timeStart,
    this.timeEnd,
    this.branchScope = const [],
    this.maxPerOrder,
    this.isActive = true,
  });

  bool get isBundle => type == 'bundle';

  /// The name to SHOW for [arabic] UI (identity stays English).
  String displayName(bool arabic) =>
      arabic && (nameAr?.trim().isNotEmpty ?? false) ? nameAr! : name;

  /// Usable right now at [branchId] — mirrors MerchantDiscount.appliesAt.
  bool appliesAt(DateTime now, {required int branchId}) {
    if (!isActive) return false;
    if (validityStart != null && now.isBefore(validityStart!)) return false;
    if (validityEnd != null && now.isAfter(validityEnd!)) return false;
    final mask = dayOfWeekMask ?? 127;
    if ((mask & (1 << (now.weekday % 7))) == 0) return false;
    if (timeStart != null || timeEnd != null) {
      String pad(int v) => v.toString().padLeft(2, '0');
      final hhmmss = '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}';
      final start = timeStart ?? '00:00:00';
      final end = timeEnd ?? '23:59:59';
      final inWindow = start.compareTo(end) <= 0
          ? hhmmss.compareTo(start) >= 0 && hhmmss.compareTo(end) <= 0
          : hhmmss.compareTo(start) >= 0 || hhmmss.compareTo(end) <= 0;
      if (!inWindow) return false;
    }
    if (branchScope.isNotEmpty && !branchScope.contains(branchId)) {
      return false;
    }
    return true;
  }
}

/// P-F8 — the merchant's order-numbering config (settings.order_numbering).
/// When [enabled], the device asks pos_api for the next sequential number at
/// PAYMENT time (per-branch or company-wide, optionally daily-reset); the
/// server-formatted value (e.g. "KLD-0042") becomes the order's receipt
/// number. Offline orders fall back to the device-local counter.
class OrderNumberingConfig {
  final bool enabled;
  final String prefix;
  final int pad;
  final String scope; // branch | company
  final bool dailyReset;

  const OrderNumberingConfig({
    this.enabled = false,
    this.prefix = '',
    this.pad = 4,
    this.scope = 'branch',
    this.dailyReset = false,
  });

  static const OrderNumberingConfig disabled = OrderNumberingConfig();

  factory OrderNumberingConfig.fromJson(Map<String, dynamic> j) =>
      OrderNumberingConfig(
        enabled: j['enabled'] == true,
        prefix: j['prefix']?.toString() ?? '',
        pad: (j['pad'] as num?)?.toInt() ?? 4,
        scope: j['scope']?.toString() ?? 'branch',
        dailyReset: j['daily_reset'] == true,
      );
}

/// A merchant loyalty rule from the config bundle. `type` is visit_based (a
/// stamp card) or spend_based (points). [config] holds the type-specific
/// settings; the typed getters parse it (values may arrive as strings).
class LoyaltyRule {
  final int id;
  final String name;
  final String type; // visit_based | spend_based
  final Map<String, dynamic> config;
  final bool isActive;

  const LoyaltyRule({
    required this.id,
    required this.name,
    required this.type,
    this.config = const {},
    this.isActive = true,
  });

  bool get isVisitBased => type == 'visit_based';
  bool get isSpendBased => type == 'spend_based';

  // spend_based config
  double get pointsPerOmr => _num(config['points_per_omr']);
  int get minRedemptionPoints => _num(config['min_redemption_points']).round();
  int get redemptionPoints => _num(config['redemption_points']).round();
  double get redemptionValue => _num(config['redemption_value']); // OMR / block
  // visit_based config
  int get stampsRequired => _num(config['stamps_required']).round();
  double get minOrderValue => _num(config['min_order_value']); // OMR
  // Stamp reward: 'percent_off' (rewardValue = % off) or 'free_product'
  // (rewardProductId names the product; its catalog price is the value).
  String? get rewardType => config['reward_type'] as String?;
  double get rewardValue => _num(config['reward_value']);
  int? get rewardProductId {
    final v = config['reward_product_id'];
    if (v == null) return null;
    final n = _num(v).round();
    return n > 0 ? n : null;
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}

/// A customer's loyalty balance under one rule (from a live customer lookup).
class LoyaltyBalance {
  final int ruleId;
  final int points;
  final int stamps;

  const LoyaltyBalance({
    required this.ruleId,
    required this.points,
    required this.stamps,
  });

  factory LoyaltyBalance.fromJson(Map<String, dynamic> j) => LoyaltyBalance(
        ruleId: (j['rule_id'] as num?)?.toInt() ?? 0,
        points: (j['points'] as num?)?.toInt() ?? 0,
        stamps: (j['stamps'] as num?)?.toInt() ?? 0,
      );
}

/// A live customer search result (from /device/customers/search) — includes the
/// loyalty balances the device shows + redeems against.
class CustomerSearchResult {
  final int id;
  final String name;
  final String phone;
  final double walletBalance;
  final List<LoyaltyBalance> loyalty;
  // P-F2 — the customer's registered vehicle plates (uppercased). A plate can
  // be linked to several customers (family car) and vice versa.
  final List<String> plates;

  const CustomerSearchResult({
    required this.id,
    required this.name,
    this.phone = '',
    this.walletBalance = 0,
    this.loyalty = const [],
    this.plates = const [],
  });

  factory CustomerSearchResult.fromJson(Map<String, dynamic> j) =>
      CustomerSearchResult(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        walletBalance: ((j['wallet_balance_baisas'] as num?)?.toDouble() ?? 0) /
            1000.0,
        loyalty: ((j['loyalty'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => LoyaltyBalance.fromJson(m.cast<String, dynamic>()))
            .toList(),
        plates: ((j['plates'] as List?) ?? const [])
            .map((p) => p.toString())
            .where((p) => p.isNotEmpty)
            .toList(),
      );

  int pointsForRule(int ruleId) =>
      loyalty.where((b) => b.ruleId == ruleId).fold(0, (s, b) => s + b.points);

  int stampsForRule(int ruleId) =>
      loyalty.where((b) => b.ruleId == ruleId).fold(0, (s, b) => s + b.stamps);
}

/// A cached customer slice for offline lookup / attaching to an order. Money OMR.
class CustomerRef {
  final int id;
  final String name;
  final String phone;
  final double walletBalance;
  // Cached loyalty balances per rule (offline points view + redeem).
  final List<LoyaltyBalance> loyalty;
  // P-F2 — cached plate links for offline plate lookup / the details dialog.
  final List<String> plates;

  const CustomerRef({
    required this.id,
    required this.name,
    this.phone = '',
    this.walletBalance = 0,
    this.loyalty = const [],
    this.plates = const [],
  });

  /// Convert to the [CustomerSearchResult] shape the attach/redeem flow uses, so
  /// an offline cache hit reuses the same selectedCustomer / _redeemable path.
  CustomerSearchResult toSearchResult() => CustomerSearchResult(
        id: id,
        name: name,
        phone: phone,
        walletBalance: walletBalance,
        loyalty: loyalty,
        plates: plates,
      );
}

/// A company ingredient (id + name + unit) for the device restock-request
/// picker and the Phase A day-end count screen. The pickers show [name]/[unit]
/// but send [id] (the integer ingredient_id the sync handlers resolve).
///
/// Phase A (Additions §2.3) piece model: when [pieceUnitLabel] +
/// [unitsPerPiece] are set, staff count this ingredient in physical PIECES
/// ("5 bottles") and the server converts via the ratio. A base unit of
/// 'piece' is implicitly piece-countable with ratio 1.
class IngredientRef {
  final int id;
  final String name;
  final String? nameAr;
  final String? unit;
  final String? pieceUnitLabel;
  final String? pieceUnitLabelAr;
  final double? unitsPerPiece;
  final bool allowFractionalPieces;

  const IngredientRef({
    required this.id,
    required this.name,
    this.nameAr,
    this.unit,
    this.pieceUnitLabel,
    this.pieceUnitLabelAr,
    this.unitsPerPiece,
    this.allowFractionalPieces = true,
  });

  /// The label staff physically count in, or null when this ingredient is
  /// counted directly in its base [unit].
  String? get countableLabel {
    if (pieceUnitLabel != null && unitsPerPiece != null) return pieceUnitLabel;
    return unit == 'piece' ? 'piece' : null;
  }

  /// Whether the day-end count for this ingredient is entered in pieces.
  bool get isPieceCounted => countableLabel != null;
}

/// The Soft POS (Mosambee) outcome for a single card tender, carried onto the
/// order.pay tender so pos_api can persist the acquirer evidence. [status] is
/// the pos_api Payment status — 'success' or 'pending_reconciliation' (the
/// latter when the cashier force-records an unconfirmed/NFC-timeout charge).
class CardCharge {
  final String? softposReference;
  final String? softposAuthCode;
  final Map<String, dynamic>? bankResponse;
  final String status;

  const CardCharge({
    this.softposReference,
    this.softposAuthCode,
    this.bankResponse,
    this.status = 'success',
  });

  bool get isPendingReconciliation => status == 'pending_reconciliation';

  factory CardCharge.fromMap(Map<String, dynamic> map) {
    final raw = map['bankResponse'];
    return CardCharge(
      softposReference: map['softposReference']?.toString(),
      softposAuthCode: map['softposAuthCode']?.toString(),
      bankResponse: raw is Map ? Map<String, dynamic>.from(raw) : null,
      status: map['status']?.toString() ?? 'success',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (softposReference != null) 'softposReference': softposReference,
      if (softposAuthCode != null) 'softposAuthCode': softposAuthCode,
      if (bankResponse != null) 'bankResponse': bankResponse,
      'status': status,
    };
  }
}

class SplitPaymentRecord {
  final int splitIndex;
  final int splitCount;
  final String paymentMethod;
  final double baseAmount;
  final bool charityRoundUpAccepted;
  final double charityRoundUpAmount;
  final double paidAmount;
  final DateTime paidAt;

  /// Soft POS evidence for a CARD tender (null for cash/other tenders).
  final CardCharge? cardCharge;

  const SplitPaymentRecord({
    required this.splitIndex,
    required this.splitCount,
    required this.paymentMethod,
    required this.baseAmount,
    required this.charityRoundUpAccepted,
    required this.charityRoundUpAmount,
    required this.paidAmount,
    required this.paidAt,
    this.cardCharge,
  });

  factory SplitPaymentRecord.fromMap(Map<String, dynamic> map) {
    final charge = map['cardCharge'];
    return SplitPaymentRecord(
      splitIndex: (map['splitIndex'] as num?)?.toInt() ?? 1,
      splitCount: (map['splitCount'] as num?)?.toInt() ?? 1,
      paymentMethod: map['paymentMethod']?.toString() ?? 'Cash',
      baseAmount: (map['baseAmount'] as num?)?.toDouble() ?? 0,
      charityRoundUpAccepted: map['charityRoundUpAccepted'] == true,
      charityRoundUpAmount:
          (map['charityRoundUpAmount'] as num?)?.toDouble() ?? 0,
      paidAmount: (map['paidAmount'] as num?)?.toDouble() ?? 0,
      paidAt:
          DateTime.tryParse(map['paidAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      cardCharge: charge is Map
          ? CardCharge.fromMap(Map<String, dynamic>.from(charge))
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'splitIndex': splitIndex,
      'splitCount': splitCount,
      'paymentMethod': paymentMethod,
      'baseAmount': _roundStoredMoney(baseAmount),
      'charityRoundUpAccepted': charityRoundUpAccepted,
      'charityRoundUpAmount': _roundStoredMoney(charityRoundUpAmount),
      'paidAmount': _roundStoredMoney(paidAmount),
      'paidAt': paidAt.toIso8601String(),
      if (cardCharge != null) 'cardCharge': cardCharge!.toMap(),
    };
  }
}

class OrderCancellationRecord {
  final String id;
  final bool fullOrder;
  final int? itemIndex;
  final String itemName;
  final int quantity;
  final double amount;
  final DateTime canceledAt;
  final String authorizedBy;

  const OrderCancellationRecord({
    required this.id,
    required this.fullOrder,
    this.itemIndex,
    required this.itemName,
    required this.quantity,
    required this.amount,
    required this.canceledAt,
    required this.authorizedBy,
  });

  factory OrderCancellationRecord.fromMap(Map<String, dynamic> map) {
    return OrderCancellationRecord(
      id: map['id']?.toString() ?? '',
      fullOrder: map['fullOrder'] == true,
      itemIndex: (map['itemIndex'] as num?)?.toInt(),
      itemName: map['itemName']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      canceledAt:
          DateTime.tryParse(map['canceledAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      authorizedBy: map['authorizedBy']?.toString() ?? 'Manager',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullOrder': fullOrder,
      'itemIndex': itemIndex,
      'itemName': itemName,
      'quantity': quantity,
      'amount': _roundStoredMoney(amount),
      'canceledAt': canceledAt.toIso8601String(),
      'authorizedBy': authorizedBy,
    };
  }
}

class OrderSessionDraft {
  final int? orderNumber;
  final String orderReference;
  final OrderType orderType;
  final String selectedCategory;
  final String customerReferenceNumber;
  final String diningFloorId;
  final String diningFloorLabel;
  final String diningTableId;
  final String diningTableName;
  final List<CartItem> items;
  final DiscountConfiguration discount;
  final int splitCount;
  final String note;
  // Phase C2 — the server order uuid minted at HOLD time, so the hold mirror
  // (order.hold), any re-hold, the final order.create, and a discard's
  // order.void all converge on ONE pos_orders row. Empty = never mirrored
  // (legacy hold, or a demo-only cart).
  final String serverOrderUuid;

  const OrderSessionDraft({
    this.orderNumber,
    required this.orderReference,
    required this.orderType,
    required this.selectedCategory,
    required this.customerReferenceNumber,
    this.diningFloorId = '',
    this.diningFloorLabel = '',
    this.diningTableId = '',
    this.diningTableName = '',
    required this.items,
    required this.discount,
    required this.splitCount,
    this.note = '',
    this.serverOrderUuid = '',
  });

  factory OrderSessionDraft.fromMap(Map<String, dynamic> map) {
    final legacyOrderNumber = (map['orderNumber'] as num?)?.toInt();
    return OrderSessionDraft(
      orderNumber: legacyOrderNumber,
      orderReference:
          map['orderReference']?.toString() ??
          map['draftReference']?.toString() ??
          (legacyOrderNumber == null ? '' : 'REF-$legacyOrderNumber'),
      orderType: OrderTypeLabel.fromStorage(map['orderType']?.toString()),
      selectedCategory: map['selectedCategory']?.toString() ?? 'Coffee',
      customerReferenceNumber: map['customerReferenceNumber']?.toString() ?? '',
      diningFloorId: map['diningFloorId']?.toString() ?? '',
      diningFloorLabel: map['diningFloorLabel']?.toString() ?? '',
      diningTableId: map['diningTableId']?.toString() ?? '',
      diningTableName: map['diningTableName']?.toString() ?? '',
      items: ((map['items'] as List?) ?? const [])
          .map(
            (item) => CartItem.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      discount: DiscountConfiguration.fromMap(
        Map<String, dynamic>.from(
          (map['discount'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      splitCount: (map['splitCount'] as num?)?.toInt() ?? 1,
      note: map['note']?.toString() ?? '',
      serverOrderUuid: map['serverOrderUuid']?.toString() ?? '',
    );
  }

  /// Gap sweep G2 — rebuild the draft with overrides (table transfer/merge
  /// re-point the table binding; merge swaps the item list). Mirrors
  /// OrderSnapshot.copyWith: every field listed by hand, so new fields MUST
  /// be added here too.
  OrderSessionDraft copyWith({
    int? orderNumber,
    String? orderReference,
    OrderType? orderType,
    String? selectedCategory,
    String? customerReferenceNumber,
    String? diningFloorId,
    String? diningFloorLabel,
    String? diningTableId,
    String? diningTableName,
    List<CartItem>? items,
    DiscountConfiguration? discount,
    int? splitCount,
    String? note,
    String? serverOrderUuid,
  }) {
    return OrderSessionDraft(
      orderNumber: orderNumber ?? this.orderNumber,
      orderReference: orderReference ?? this.orderReference,
      orderType: orderType ?? this.orderType,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      customerReferenceNumber:
          customerReferenceNumber ?? this.customerReferenceNumber,
      diningFloorId: diningFloorId ?? this.diningFloorId,
      diningFloorLabel: diningFloorLabel ?? this.diningFloorLabel,
      diningTableId: diningTableId ?? this.diningTableId,
      diningTableName: diningTableName ?? this.diningTableName,
      items: items ?? this.items,
      discount: discount ?? this.discount,
      splitCount: splitCount ?? this.splitCount,
      note: note ?? this.note,
      serverOrderUuid: serverOrderUuid ?? this.serverOrderUuid,
    );
  }

  double get rawSubtotal => items.fold(0, (sum, item) => sum + item.lineTotal);

  double get discountAmount {
    if (!discount.isActive) return 0;

    final calculated = switch (discount.kind) {
      DiscountKind.fixedAmount => discount.value,
      DiscountKind.percentage => rawSubtotal * (discount.value / 100),
      DiscountKind.none => 0,
    };

    return _roundStoredMoney(calculated.clamp(0.0, rawSubtotal).toDouble());
  }

  double get subtotal => _roundStoredMoney(
    (rawSubtotal - discountAmount).clamp(0.0, double.infinity).toDouble(),
  );

  // P-F1 — delivery-provider orders are tax-exempt (the provider's listed
  // price is final); mirrors PosController._isTaxExempt for held drafts.
  bool get _isTaxExempt => orderType == OrderType.delivery;

  double get tax => _isTaxExempt ? 0 : taxTotalFor(subtotal);

  /// Per-tax breakdown for the cart / receipt (one line per active company tax).
  List<TaxLineAmount> get taxLines =>
      _isTaxExempt ? const <TaxLineAmount>[] : taxLinesFor(subtotal);

  double get total => _roundStoredMoney(subtotal + tax);

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'orderReference': orderReference,
      'orderType': orderType.storageValue,
      'selectedCategory': selectedCategory,
      'customerReferenceNumber': customerReferenceNumber,
      'diningFloorId': diningFloorId,
      'diningFloorLabel': diningFloorLabel,
      'diningTableId': diningTableId,
      'diningTableName': diningTableName,
      'items': items.map((item) => item.toMap()).toList(),
      'discount': discount.toMap(),
      'splitCount': splitCount,
      'note': note,
      if (serverOrderUuid.isNotEmpty) 'serverOrderUuid': serverOrderUuid,
    };
    if (orderNumber != null) {
      map['orderNumber'] = orderNumber;
    }
    return map;
  }
}

class OrderSnapshot {
  final int orderNumber;
  final String orderType;
  final List<Map<String, dynamic>> items;
  final double rawSubtotal;
  final double discountAmount;
  final String discountLabel;
  // When the applied discount is a merchant rule: its id + amount_type, sent on
  // order.create so the server snapshots the rule (by-rule report). Null = manual.
  final int? discountId;
  final String? discountAmountType;
  // P-F4 — the cashier's reason for a manual/custom discount ('' = none);
  // rides order.create's discounts[] entry and lands in the audit row.
  final String discountReason;
  // P-F8 — the merchant's formatted sequential order number (e.g. "KLD-0042")
  // allocated server-side at payment time. '' = none (numbering disabled or
  // the device was offline → the local [orderNumber] stands alone).
  final String receiptNumber;
  // P-F9 — the applied offers frozen at snapshot time: flattened entries
  // {offer_id, name, amount (OMR), line_index?} — per-line allocations plus
  // any order-level (spend_get) amount. Pushed as discounts[] rows carrying
  // offer_id.
  final List<Map<String, dynamic>> offers;
  // Loyalty redemption applied to this order (points spent under a rule); sent
  // as loyalty_redeem on order.pay. Null/0 = no redemption.
  final int? loyaltyRedeemRuleId;
  final int loyaltyRedeemPoints;
  // Stamps spent on a visit_based (stamp-card) redemption. Null/0 = none.
  final int loyaltyRedeemStamps;
  // Phase B — the manager comp applied (one per order on the device) + its
  // frozen amount. 0/null = no comp. Emitted as comps[] + comp_total_baisas.
  final double compAmount;
  final int? compReasonId;
  final String compReasonName;
  final int? compLineIndex;
  final double subtotal;
  final double tax;
  final double total;
  final double activePaymentBaseTotal;
  final int splitCount;
  final double payableTotal;
  final String paymentStatus;
  final String paymentMethod;
  final String customerReferenceNumber;
  final String diningFloorId;
  final String diningFloorLabel;
  final String diningTableId;
  final String diningTableName;
  final String note;
  final bool showCharityRoundUpPrompt;
  final bool showPaymentLaunchOverlay;
  final String paymentOverlayTitle;
  final bool charityRoundUpAccepted;
  final double charityRoundUpAmount;
  final double charityRoundUpTotal;
  final List<SplitPaymentRecord> splitPayments;
  final List<OrderCancellationRecord> cancellations;
  final int charityRoundUpPromptId;
  final String recentProductId;
  final int orderUpdateNonce;
  // The server order_uuid sent in order.create when this order was pushed
  // (stamped at completion). Lets a later full-cancel emit a matching
  // order.void to pos_api. Empty for orders never pushed (e.g. demo-only) or
  // records loaded from the server's history.
  final String serverOrderUuid;

  const OrderSnapshot({
    required this.orderNumber,
    required this.orderType,
    required this.items,
    required this.rawSubtotal,
    required this.discountAmount,
    required this.discountLabel,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.activePaymentBaseTotal,
    required this.splitCount,
    required this.payableTotal,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.customerReferenceNumber,
    required this.diningFloorId,
    required this.diningFloorLabel,
    required this.diningTableId,
    required this.diningTableName,
    required this.note,
    required this.showCharityRoundUpPrompt,
    required this.showPaymentLaunchOverlay,
    required this.paymentOverlayTitle,
    required this.charityRoundUpAccepted,
    required this.charityRoundUpAmount,
    required this.charityRoundUpTotal,
    this.splitPayments = const [],
    this.cancellations = const [],
    this.discountId,
    this.discountAmountType,
    this.discountReason = '',
    this.receiptNumber = '',
    this.offers = const <Map<String, dynamic>>[],
    this.loyaltyRedeemRuleId,
    this.loyaltyRedeemPoints = 0,
    this.loyaltyRedeemStamps = 0,
    this.compAmount = 0,
    this.compReasonId,
    this.compReasonName = '',
    this.compLineIndex,
    required this.charityRoundUpPromptId,
    required this.recentProductId,
    required this.orderUpdateNonce,
    this.serverOrderUuid = '',
  });

  factory OrderSnapshot.initial() {
    return const OrderSnapshot(
      orderNumber: 1450,
      orderType: 'quick_order',
      items: [],
      rawSubtotal: 0,
      discountAmount: 0,
      discountLabel: '',
      subtotal: 0,
      tax: 0,
      total: 0,
      activePaymentBaseTotal: 0,
      splitCount: 1,
      payableTotal: 0,
      paymentStatus: 'Waiting',
      paymentMethod: 'Cash',
      customerReferenceNumber: '',
      diningFloorId: '',
      diningFloorLabel: '',
      diningTableId: '',
      diningTableName: '',
      note: '',
      showCharityRoundUpPrompt: false,
      showPaymentLaunchOverlay: false,
      paymentOverlayTitle: '',
      charityRoundUpAccepted: false,
      charityRoundUpAmount: 0,
      charityRoundUpTotal: 0,
      splitPayments: [],
      cancellations: [],
      charityRoundUpPromptId: 0,
      recentProductId: '',
      orderUpdateNonce: 0,
    );
  }

  factory OrderSnapshot.fromMap(Map<String, dynamic> map) {
    return OrderSnapshot(
      orderNumber: (map['orderNumber'] as num?)?.toInt() ?? 1450,
      orderType: map['orderType']?.toString() ?? 'quick_order',
      items: ((map['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      rawSubtotal:
          (map['rawSubtotal'] as num?)?.toDouble() ??
          (map['subtotal'] as num?)?.toDouble() ??
          0,
      discountAmount: (map['discountAmount'] as num?)?.toDouble() ?? 0,
      discountLabel: map['discountLabel']?.toString() ?? '',
      discountReason: map['discountReason']?.toString() ?? '',
      receiptNumber: map['receiptNumber']?.toString() ?? '',
      offers: ((map['offers'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(),
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      tax: (map['tax'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      activePaymentBaseTotal:
          (map['activePaymentBaseTotal'] as num?)?.toDouble() ??
          (map['total'] as num?)?.toDouble() ??
          0,
      splitCount: (map['splitCount'] as num?)?.toInt() ?? 1,
      payableTotal:
          (map['payableTotal'] as num?)?.toDouble() ??
          (map['total'] as num?)?.toDouble() ??
          0,
      paymentStatus: map['paymentStatus']?.toString() ?? 'Waiting',
      paymentMethod: map['paymentMethod']?.toString() ?? 'Cash',
      customerReferenceNumber: map['customerReferenceNumber']?.toString() ?? '',
      diningFloorId: map['diningFloorId']?.toString() ?? '',
      diningFloorLabel: map['diningFloorLabel']?.toString() ?? '',
      diningTableId: map['diningTableId']?.toString() ?? '',
      diningTableName: map['diningTableName']?.toString() ?? '',
      note: map['note']?.toString() ?? '',
      showCharityRoundUpPrompt: map['showCharityRoundUpPrompt'] == true,
      showPaymentLaunchOverlay: map['showPaymentLaunchOverlay'] == true,
      paymentOverlayTitle: map['paymentOverlayTitle']?.toString() ?? '',
      charityRoundUpAccepted: map['charityRoundUpAccepted'] == true,
      charityRoundUpAmount:
          (map['charityRoundUpAmount'] as num?)?.toDouble() ?? 0,
      charityRoundUpTotal:
          (map['charityRoundUpTotal'] as num?)?.toDouble() ?? 0,
      splitPayments: ((map['splitPayments'] as List?) ?? const [])
          .map(
            (payment) => SplitPaymentRecord.fromMap(
              Map<String, dynamic>.from(payment as Map),
            ),
          )
          .toList(),
      cancellations: ((map['cancellations'] as List?) ?? const [])
          .map(
            (entry) => OrderCancellationRecord.fromMap(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(),
      charityRoundUpPromptId:
          (map['charityRoundUpPromptId'] as num?)?.toInt() ?? 0,
      recentProductId: map['recentProductId']?.toString() ?? '',
      orderUpdateNonce: (map['orderUpdateNonce'] as num?)?.toInt() ?? 0,
      serverOrderUuid: map['serverOrderUuid']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderNumber': orderNumber,
      'orderType': orderType,
      'items': items,
      'rawSubtotal': rawSubtotal,
      'discountAmount': discountAmount,
      'discountLabel': discountLabel,
      if (discountReason.isNotEmpty) 'discountReason': discountReason,
      if (receiptNumber.isNotEmpty) 'receiptNumber': receiptNumber,
      if (offers.isNotEmpty) 'offers': offers,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'activePaymentBaseTotal': activePaymentBaseTotal,
      'splitCount': splitCount,
      'payableTotal': payableTotal,
      'paymentStatus': paymentStatus,
      'paymentMethod': paymentMethod,
      'customerReferenceNumber': customerReferenceNumber,
      'diningFloorId': diningFloorId,
      'diningFloorLabel': diningFloorLabel,
      'diningTableId': diningTableId,
      'diningTableName': diningTableName,
      'note': note,
      'showCharityRoundUpPrompt': showCharityRoundUpPrompt,
      'showPaymentLaunchOverlay': showPaymentLaunchOverlay,
      'paymentOverlayTitle': paymentOverlayTitle,
      'charityRoundUpAccepted': charityRoundUpAccepted,
      'charityRoundUpAmount': charityRoundUpAmount,
      'charityRoundUpTotal': charityRoundUpTotal,
      'splitPayments': splitPayments.map((payment) => payment.toMap()).toList(),
      'cancellations': cancellations
          .map((cancellation) => cancellation.toMap())
          .toList(),
      'charityRoundUpPromptId': charityRoundUpPromptId,
      'recentProductId': recentProductId,
      'orderUpdateNonce': orderUpdateNonce,
      'serverOrderUuid': serverOrderUuid,
    };
  }

  OrderSnapshot copyWith({
    int? orderNumber,
    String? orderType,
    List<Map<String, dynamic>>? items,
    double? rawSubtotal,
    double? discountAmount,
    String? discountLabel,
    int? discountId,
    String? discountAmountType,
    String? discountReason,
    String? receiptNumber,
    List<Map<String, dynamic>>? offers,
    int? loyaltyRedeemRuleId,
    int? loyaltyRedeemPoints,
    int? loyaltyRedeemStamps,
    double? compAmount,
    int? compReasonId,
    String? compReasonName,
    int? compLineIndex,
    double? subtotal,
    double? tax,
    double? total,
    double? activePaymentBaseTotal,
    int? splitCount,
    double? payableTotal,
    String? paymentStatus,
    String? paymentMethod,
    String? customerReferenceNumber,
    String? diningFloorId,
    String? diningFloorLabel,
    String? diningTableId,
    String? diningTableName,
    String? note,
    bool? showCharityRoundUpPrompt,
    bool? showPaymentLaunchOverlay,
    String? paymentOverlayTitle,
    bool? charityRoundUpAccepted,
    double? charityRoundUpAmount,
    double? charityRoundUpTotal,
    List<SplitPaymentRecord>? splitPayments,
    List<OrderCancellationRecord>? cancellations,
    int? charityRoundUpPromptId,
    String? recentProductId,
    int? orderUpdateNonce,
    String? serverOrderUuid,
  }) {
    return OrderSnapshot(
      orderNumber: orderNumber ?? this.orderNumber,
      orderType: orderType ?? this.orderType,
      items: items ?? this.items,
      rawSubtotal: rawSubtotal ?? this.rawSubtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      discountLabel: discountLabel ?? this.discountLabel,
      discountId: discountId ?? this.discountId,
      discountAmountType: discountAmountType ?? this.discountAmountType,
      discountReason: discountReason ?? this.discountReason,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      offers: offers ?? this.offers,
      loyaltyRedeemRuleId: loyaltyRedeemRuleId ?? this.loyaltyRedeemRuleId,
      loyaltyRedeemPoints: loyaltyRedeemPoints ?? this.loyaltyRedeemPoints,
      loyaltyRedeemStamps: loyaltyRedeemStamps ?? this.loyaltyRedeemStamps,
      compAmount: compAmount ?? this.compAmount,
      compReasonId: compReasonId ?? this.compReasonId,
      compReasonName: compReasonName ?? this.compReasonName,
      compLineIndex: compLineIndex ?? this.compLineIndex,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      activePaymentBaseTotal:
          activePaymentBaseTotal ?? this.activePaymentBaseTotal,
      splitCount: splitCount ?? this.splitCount,
      payableTotal: payableTotal ?? this.payableTotal,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      customerReferenceNumber:
          customerReferenceNumber ?? this.customerReferenceNumber,
      diningFloorId: diningFloorId ?? this.diningFloorId,
      diningFloorLabel: diningFloorLabel ?? this.diningFloorLabel,
      diningTableId: diningTableId ?? this.diningTableId,
      diningTableName: diningTableName ?? this.diningTableName,
      note: note ?? this.note,
      showCharityRoundUpPrompt:
          showCharityRoundUpPrompt ?? this.showCharityRoundUpPrompt,
      showPaymentLaunchOverlay:
          showPaymentLaunchOverlay ?? this.showPaymentLaunchOverlay,
      paymentOverlayTitle: paymentOverlayTitle ?? this.paymentOverlayTitle,
      charityRoundUpAccepted:
          charityRoundUpAccepted ?? this.charityRoundUpAccepted,
      charityRoundUpAmount: charityRoundUpAmount ?? this.charityRoundUpAmount,
      charityRoundUpTotal: charityRoundUpTotal ?? this.charityRoundUpTotal,
      splitPayments: splitPayments ?? this.splitPayments,
      cancellations: cancellations ?? this.cancellations,
      charityRoundUpPromptId:
          charityRoundUpPromptId ?? this.charityRoundUpPromptId,
      recentProductId: recentProductId ?? this.recentProductId,
      orderUpdateNonce: orderUpdateNonce ?? this.orderUpdateNonce,
      serverOrderUuid: serverOrderUuid ?? this.serverOrderUuid,
    );
  }

  double get splitPaymentsBaseTotal => _roundStoredMoney(
    splitPayments.fold<double>(0, (sum, payment) => sum + payment.baseAmount),
  );

  double get splitPaymentsPaidTotal => _roundStoredMoney(
    splitPayments.fold<double>(0, (sum, payment) => sum + payment.paidAmount),
  );

  double get canceledAmount => _roundStoredMoney(
    cancellations.fold<double>(0, (sum, entry) => sum + entry.amount),
  );

  /// P-F8 — what receipts/tickets/history show: the merchant's sequential
  /// number when one was allocated, else the device-local '#N'.
  String get displayOrderNumber =>
      receiptNumber.isNotEmpty ? receiptNumber : '#$orderNumber';

  bool get isFullyCanceled => cancellations.any((entry) => entry.fullOrder);

  Set<int> get canceledItemIndexes => cancellations
      .where((entry) => !entry.fullOrder && entry.itemIndex != null)
      .map((entry) => entry.itemIndex!)
      .toSet();

  bool isItemCanceled(int itemIndex) =>
      isFullyCanceled || canceledItemIndexes.contains(itemIndex);
}

class DiningTableSession {
  final String tableId;
  final String floorId;
  final DiningTableStatus status;
  final int? orderNumber;
  final String orderReference;
  final DateTime updatedAt;
  final DateTime? occupiedAt;
  final DateTime? paidAt;
  final OrderSessionDraft? draft;
  final OrderSnapshot? paidSnapshot;

  const DiningTableSession({
    required this.tableId,
    required this.floorId,
    required this.status,
    required this.updatedAt,
    this.orderNumber,
    this.orderReference = '',
    this.occupiedAt,
    this.paidAt,
    this.draft,
    this.paidSnapshot,
  });

  double get total => switch (status) {
    DiningTableStatus.occupied => draft?.total ?? 0,
    DiningTableStatus.paid =>
      paidSnapshot?.payableTotal ?? paidSnapshot?.total ?? 0,
    DiningTableStatus.available => 0,
  };
}

class OrderHistoryRecord {
  final String id;
  final int orderNumber;
  final OrderType orderType;
  final DateTime createdAt;
  final OrderSnapshot snapshot;
  // True when this record came from the server's branch history (cross-device)
  // rather than the device's local store. A paid server record CAN be canceled
  // (full-order only — the cancel mirrors an order.void to pos_api); see
  // [isServerTerminal] for the states that stay locked.
  final bool fromServer;

  const OrderHistoryRecord({
    required this.id,
    required this.orderNumber,
    required this.orderType,
    required this.createdAt,
    required this.snapshot,
    this.fromServer = false,
  });

  /// P-F1 — a server-history record whose status is already terminal beyond
  /// paid (void / refunded): nothing further can be done to it from the
  /// device, so the cancel action stays disabled.
  bool get isServerTerminal {
    if (!fromServer) return false;
    final status = snapshot.paymentStatus.toLowerCase();
    return status == 'void' ||
        status == 'voided' ||
        status == 'refunded' ||
        status == 'canceled';
  }

  /// Build a history record from the pos_api `/device/orders/history` shape
  /// (money is integer baisas). Only the fields the history view shows are
  /// mapped; the rest of [OrderSnapshot] defaults (UI-only state). Marked
  /// [fromServer]: cancellable in full while paid, locked once void/refunded.
  factory OrderHistoryRecord.fromServerJson(Map<String, dynamic> json) {
    double omr(String key) => ((json[key] as num?)?.toDouble() ?? 0) / 1000.0;
    final status = json['status']?.toString() ?? '';
    final statusLabel =
        status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);
    final orderTypeStr = json['order_type']?.toString() ?? 'quick_order';
    final serverId = (json['id'] as num?)?.toInt() ?? 0;
    final total = omr('grand_total_baisas');

    final items = ((json['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => <String, dynamic>{
              'name': raw['product_name']?.toString() ?? 'Item',
              'qty': (raw['qty'] as num?)?.toDouble() ?? 0,
              'lineTotal':
                  ((raw['line_total_baisas'] as num?)?.toDouble() ?? 0) / 1000.0,
              'notes': raw['notes']?.toString() ?? '',
              // Phase C1 — the server's add-ons, mapped to the CartItem
              // modifier shape so kitchen-ticket reprints of cross-device
              // orders show them (the server sends no group label).
              'modifiers': ((raw['addons'] as List?) ?? const [])
                  .whereType<Map>()
                  .map((addon) => <String, dynamic>{
                        'id': 'addon_${addon['add_on_id']}',
                        'group': '',
                        'label': addon['add_on_name']?.toString() ?? '',
                        'price':
                            ((addon['price_delta_baisas'] as num?)?.toDouble() ??
                                    0) /
                                1000.0,
                      })
                  .toList(),
            })
        .toList();

    final snapshot = OrderSnapshot.fromMap(<String, dynamic>{
      'orderNumber': serverId,
      'orderType': orderTypeStr,
      'items': items,
      'rawSubtotal': omr('subtotal_baisas'),
      'subtotal': omr('subtotal_baisas'),
      'discountAmount': omr('discount_total_baisas'),
      'tax': omr('tax_total_baisas'),
      'total': total,
      'payableTotal': total,
      'activePaymentBaseTotal': total,
      'paymentStatus': statusLabel,
      'paymentMethod': '',
      'note': json['note']?.toString() ?? '',
      // P-F1 — carry the server uuid so a cross-device cancel can mirror an
      // order.void back to pos_api (the handler is branch-scoped, not
      // creating-device-scoped).
      'serverOrderUuid': json['uuid']?.toString() ?? '',
      // P-F8 — the merchant's sequential number, when the order has one.
      'receiptNumber': json['receipt_number']?.toString() ?? '',
    });

    return OrderHistoryRecord(
      id: json['uuid']?.toString() ?? 'srv_$serverId',
      orderNumber: serverId,
      orderType: OrderTypeLabel.fromStorage(orderTypeStr),
      createdAt:
          DateTime.tryParse(json['opened_at']?.toString() ?? '') ?? DateTime.now(),
      snapshot: snapshot,
      fromServer: true,
    );
  }
}

class HeldOrderRecord {
  final String id;
  final int? orderNumber;
  final String orderReference;
  final OrderType orderType;
  final DateTime heldAt;
  final OrderSessionDraft draft;

  const HeldOrderRecord({
    required this.id,
    this.orderNumber,
    required this.orderReference,
    required this.orderType,
    required this.heldAt,
    required this.draft,
  });
}
