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
  });
  final int id;
  final String label;
  final String? labelAr;
  final double priceDelta; // OMR added to the line when selected
}

/// A product's add-on group (e.g. "Size", "Milk", "Extras"), assigned per
/// product in the merchant portal and fetched in the device config. [multiSelect]
/// mirrors the API `selection_mode` ('multiple' vs 'single').
class AddonGroup {
  const AddonGroup({
    required this.id,
    required this.name,
    this.nameAr,
    required this.multiSelect,
    required this.options,
  });
  final int id;
  final String name;
  final String? nameAr;
  final bool multiSelect;
  final List<AddonOption> options;
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
  final String category;
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

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageAsset,
    this.lowStock = false,
    this.addonGroupIds = const <int>[],
    this.deliveryPrice,
    this.deliveryPriceByProvider = const <int, double>{},
    this.stockMode,
    this.recipe = const <RecipeLine>[],
    this.branchStockQty,
  });

  /// The unit price to charge on a delivery order for [providerId], following
  /// the merchant's chain: provider override → in-house delivery price → base.
  double deliveryPriceFor(int providerId) =>
      deliveryPriceByProvider[providerId] ?? deliveryPrice ?? price;

  Product copyWith({double? price}) => Product(
        id: id,
        name: name,
        category: category,
        price: price ?? this.price,
        imageAsset: imageAsset,
        lowStock: lowStock,
        addonGroupIds: addonGroupIds,
        deliveryPrice: deliveryPrice,
        deliveryPriceByProvider: deliveryPriceByProvider,
        stockMode: stockMode,
        recipe: recipe,
        branchStockQty: branchStockQty,
      );

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
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
  final double price;

  const CartItemModifier({
    required this.id,
    required this.group,
    required this.label,
    required this.price,
  });

  factory CartItemModifier.fromMap(Map<String, dynamic> map) {
    return CartItemModifier(
      id: map['id']?.toString() ?? '',
      group: map['group']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'group': group, 'label': label, 'price': price};
  }
}

class CartItem {
  final Product product;
  int qty;
  List<CartItemModifier> modifiers;
  String notes;

  CartItem({
    required this.product,
    this.qty = 1,
    List<CartItemModifier>? modifiers,
    this.notes = '',
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
    return '${product.id}|$modifierSignature|${normalizedNotes.toLowerCase()}';
  }

  List<CartItemModifier> modifiersForGroup(String group) {
    return modifiers.where((modifier) => modifier.group == group).toList();
  }

  String? firstModifierLabel(String group) {
    final groupItems = modifiersForGroup(group);
    if (groupItems.isEmpty) return null;
    return groupItems.first.label;
  }

  List<String> get detailLines {
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
            return '${modifier.label}$extra';
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
      'detailLines': detailLines,
    };
  }
}

class DiscountConfiguration {
  final DiscountKind kind;
  final double value;
  final String label;

  const DiscountConfiguration({
    this.kind = DiscountKind.none,
    this.value = 0,
    this.label = '',
  });

  bool get isActive => kind != DiscountKind.none && value > 0;

  factory DiscountConfiguration.fromMap(Map<String, dynamic> map) {
    return DiscountConfiguration(
      kind: DiscountKindLabel.fromStorage(map['kind']?.toString()),
      value: (map['value'] as num?)?.toDouble() ?? 0,
      label: map['label']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'kind': kind.storageValue, 'value': value, 'label': label};
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

  const SplitPaymentRecord({
    required this.splitIndex,
    required this.splitCount,
    required this.paymentMethod,
    required this.baseAmount,
    required this.charityRoundUpAccepted,
    required this.charityRoundUpAmount,
    required this.paidAmount,
    required this.paidAt,
  });

  factory SplitPaymentRecord.fromMap(Map<String, dynamic> map) {
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

  double get tax => taxTotalFor(subtotal);

  /// Per-tax breakdown for the cart / receipt (one line per active company tax).
  List<TaxLineAmount> get taxLines => taxLinesFor(subtotal);

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
    required this.charityRoundUpPromptId,
    required this.recentProductId,
    required this.orderUpdateNonce,
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
    };
  }

  OrderSnapshot copyWith({
    int? orderNumber,
    String? orderType,
    List<Map<String, dynamic>>? items,
    double? rawSubtotal,
    double? discountAmount,
    String? discountLabel,
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
  }) {
    return OrderSnapshot(
      orderNumber: orderNumber ?? this.orderNumber,
      orderType: orderType ?? this.orderType,
      items: items ?? this.items,
      rawSubtotal: rawSubtotal ?? this.rawSubtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      discountLabel: discountLabel ?? this.discountLabel,
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

  const OrderHistoryRecord({
    required this.id,
    required this.orderNumber,
    required this.orderType,
    required this.createdAt,
    required this.snapshot,
  });
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
