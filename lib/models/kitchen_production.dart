/// P-G1 — kitchen production models (GET /device/kitchen + the
/// /device/productions lifecycle). Pure data classes parsed from the
/// pos_api JSON; quantities are doubles (ingredient amounts / piece
/// counts), never money — so no baisas here.
library;

/// One cooked product the kitchen can produce.
class KitchenProduct {
  const KitchenProduct({
    required this.id,
    required this.uuid,
    required this.name,
    this.nameAr,
    this.categoryId,
    this.branchStockQty,
    this.maxProducible,
    this.recipe = const <KitchenRecipeLine>[],
  });

  factory KitchenProduct.fromJson(Map<String, dynamic> json) => KitchenProduct(
        id: (json['id'] as num?)?.toInt() ?? 0,
        uuid: json['uuid']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        nameAr: json['name_ar']?.toString(),
        categoryId: (json['category_id'] as num?)?.toInt(),
        branchStockQty: (json['branch_stock_qty'] as num?)?.toDouble(),
        maxProducible: (json['max_producible'] as num?)?.toInt(),
        recipe: (json['recipe'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => KitchenRecipeLine.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  final int id;
  final String uuid;
  final String name;
  final String? nameAr;
  final int? categoryId;

  /// Current shelf count at this branch; null = nothing produced yet.
  final double? branchStockQty;

  /// Server-computed "can make up to N" from live branch balances;
  /// null = the product has no recipe (unconstrained).
  final int? maxProducible;
  final List<KitchenRecipeLine> recipe;
}

/// One per-piece recipe line of a cooked product, with the live balance.
class KitchenRecipeLine {
  const KitchenRecipeLine({
    required this.ingredientId,
    required this.name,
    this.nameAr,
    required this.quantity,
    required this.unit,
    required this.branchBalance,
  });

  factory KitchenRecipeLine.fromJson(Map<String, dynamic> json) =>
      KitchenRecipeLine(
        ingredientId: (json['ingredient_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        nameAr: json['name_ar']?.toString(),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? '',
        branchBalance: (json['branch_balance'] as num?)?.toDouble() ?? 0,
      );

  final int ingredientId;
  final String name;
  final String? nameAr;

  /// Amount per ONE piece (the server locks total = quantity x batch size).
  final double quantity;
  final String unit;
  final double branchBalance;
}

/// A company ingredient + this branch's balance, for the extras picker.
class KitchenIngredient {
  const KitchenIngredient({
    required this.id,
    required this.name,
    this.nameAr,
    required this.unit,
    required this.branchBalance,
  });

  factory KitchenIngredient.fromJson(Map<String, dynamic> json) =>
      KitchenIngredient(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        nameAr: json['name_ar']?.toString(),
        unit: json['unit']?.toString() ?? '',
        branchBalance: (json['branch_balance'] as num?)?.toDouble() ?? 0,
      );

  final int id;
  final String name;
  final String? nameAr;
  final String unit;
  final double branchBalance;
}

/// One ingredient line of a batch (std locked or declared extra).
class ProductionBatchLine {
  const ProductionBatchLine({
    required this.ingredientId,
    required this.name,
    this.nameAr,
    required this.quantity,
    required this.unit,
    required this.isExtra,
  });

  factory ProductionBatchLine.fromJson(Map<String, dynamic> json) =>
      ProductionBatchLine(
        ingredientId: (json['ingredient_id'] as num?)?.toInt() ?? 0,
        name: json['name']?.toString() ?? '',
        nameAr: json['name_ar']?.toString(),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unit: json['unit']?.toString() ?? '',
        isExtra: json['is_extra'] == true,
      );

  final int ingredientId;
  final String name;
  final String? nameAr;

  /// Total for the WHOLE batch (the server already multiplied by qty).
  final double quantity;
  final String unit;
  final bool isExtra;
}

/// A production batch as the server tells it.
class ProductionBatch {
  const ProductionBatch({
    required this.uuid,
    required this.status,
    required this.productId,
    this.productName,
    this.productNameAr,
    required this.quantity,
    this.startedAt,
    this.finishedAt,
    this.durationSeconds,
    this.startedBy,
    this.lines = const <ProductionBatchLine>[],
  });

  factory ProductionBatch.fromJson(Map<String, dynamic> json) =>
      ProductionBatch(
        uuid: json['uuid']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        productId: (json['product_id'] as num?)?.toInt() ?? 0,
        productName: json['product_name']?.toString(),
        productNameAr: json['product_name_ar']?.toString(),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
        finishedAt: DateTime.tryParse(json['finished_at']?.toString() ?? ''),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        startedBy: json['started_by']?.toString(),
        lines: (json['lines'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => ProductionBatchLine.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  final String uuid;
  final String status;
  final int productId;
  final String? productName;
  final String? productNameAr;
  final double quantity;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? durationSeconds;
  final String? startedBy;
  final List<ProductionBatchLine> lines;
}

/// The whole GET /device/kitchen payload.
class KitchenData {
  const KitchenData({
    this.products = const <KitchenProduct>[],
    this.ingredients = const <KitchenIngredient>[],
    this.active = const <ProductionBatch>[],
  });

  factory KitchenData.fromJson(Map<String, dynamic> json) => KitchenData(
        products: (json['products'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => KitchenProduct.fromJson(m.cast<String, dynamic>()))
            .toList(),
        ingredients: (json['ingredients'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => KitchenIngredient.fromJson(m.cast<String, dynamic>()))
            .toList(),
        active: (json['active'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => ProductionBatch.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  final List<KitchenProduct> products;
  final List<KitchenIngredient> ingredients;
  final List<ProductionBatch> active;
}
