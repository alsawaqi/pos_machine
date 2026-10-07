import '../models/pos_models.dart';

/// The cart lines of a claimed transfer (POST /device/transfers/{uuid}/claim
/// → `order.items`, the server's DeviceOrderItems shape).
///
/// LAUNCH combo add-on — a combo's or meal's children are never lines of
/// their own: each line carries them as `combo` (per ONE combo / meal:
/// line_id, kind, product_id, product_name, qty, extra_price_baisas, notes,
/// addons; pos_api handback §7.7). They become the line's
/// [ComboComponent]s, so the resumed cart, its edits and its payment
/// (order.create `combo[]`) keep the same items. A meal line's product is
/// its MAIN (`meal_id` set; the main's add-ons and notes are the line's);
/// [mealFor] names the meal and gives its price. The line's base price is
/// the server unit price minus its add-ons, its items (and a meal's price).
List<CartItem> transferClaimCartItems(
  Map<String, dynamic> order, {
  required Product? Function(String id) productForId,
  MealSetup? Function(int id)? mealFor,
}) {
  int baisas(Object? v) => (v as num?)?.toInt() ?? 0;
  final items = <CartItem>[];
  for (final raw in ((order['items'] as List?) ?? const []).whereType<Map>()) {
    final m = raw.cast<String, dynamic>();
    // A child row from an older shape never becomes a line.
    if (m['parent_order_item_id'] != null) continue;
    final productId = (m['product_id'] as num?)?.toInt();

    final modifiers = <CartItemModifier>[
      for (final a in ((m['addons'] as List?) ?? const []).whereType<Map>())
        CartItemModifier(
          id: '${(a['add_on_id'] as num?)?.toInt() ?? ''}',
          group: '',
          label: (a['add_on_name'] ?? '').toString(),
          price: baisas(a['price_delta_baisas']) / 1000.0,
        ),
    ];

    final components = <ComboComponent>[
      for (final c
          in ((m['combo'] ?? m['components']) as List? ?? const [])
              .whereType<Map>())
        if ((c['product_id'] as num?)?.toInt() case final int cid)
          if (c['kind'] != 'main')
            ComboComponent(
              lineId: (c['line_id'] as num?)?.toInt() ?? 0,
              kind: (c['kind'] ?? 'choice').toString(),
              productId: '$cid',
              name:
                  productForId('$cid')?.name ??
                  (c['product_name'] ?? c['name'] ?? '').toString(),
              nameAr: productForId('$cid')?.nameAr ?? '',
              qty: ((c['qty'] as num?) ?? 1).round(),
              extraPrice: baisas(c['extra_price_baisas']) / 1000.0,
              weightBaisas: ((productForId('$cid')?.price ?? 0) * 1000).round(),
              modifiers: [
                for (final a
                    in (c['addons'] as List? ?? const []).whereType<Map>())
                  CartItemModifier(
                    id: '${(a['add_on_id'] as num?)?.toInt() ?? ''}',
                    group: '',
                    label: (a['add_on_name'] ?? a['name'] ?? '').toString(),
                    price: baisas(a['price_delta_baisas']) / 1000.0,
                  ),
              ],
              notes: (c['notes'] ?? '').toString(),
            ),
    ];

    final mealId = (m['meal_id'] as num?)?.toInt();
    final setup = mealId == null ? null : mealFor?.call(mealId);
    final meal = mealId == null
        ? null
        : CartMeal(
            id: mealId,
            name: setup?.name ?? (m['meal_name'] ?? '').toString(),
            nameAr: setup?.nameAr ?? (m['meal_name_ar'] ?? '').toString(),
            price:
                (setup?.mealPriceBaisas ?? baisas(m['meal_price_baisas'])) /
                1000.0,
          );

    final unitPrice = baisas(m['unit_price_baisas']) / 1000.0;
    final addonTotal = modifiers.fold(0.0, (sum, mo) => sum + mo.price);
    final componentTotal = components.fold(0.0, (sum, c) => sum + c.comboDelta);
    final basePrice = double.parse(
      (unitPrice - addonTotal - componentTotal - (meal?.price ?? 0))
          .toStringAsFixed(3),
    );

    final catalog = productId != null ? productForId('$productId') : null;
    items.add(
      CartItem(
        product: Product(
          id: '${productId ?? ''}',
          name: catalog?.name ?? (m['product_name'] ?? '').toString(),
          nameAr: catalog?.nameAr ?? '',
          category: catalog?.category ?? '',
          categoryId: catalog?.categoryId,
          price: basePrice < 0 ? 0 : basePrice,
          imageAsset: catalog?.imageAsset,
          imageUrl: catalog?.imageUrl,
          addonGroupIds: catalog?.addonGroupIds ?? const <int>[],
          productType:
              catalog?.productType ??
              (components.isEmpty || meal != null ? 'standard' : 'combo'),
          comboLines: catalog?.comboLines ?? const [],
        ),
        qty: ((m['qty'] as num?) ?? 1).round(),
        modifiers: modifiers,
        notes: (m['notes'] ?? '').toString(),
        components: components,
        meal: meal,
        mainWeightBaisas: catalog == null
            ? null
            : (catalog.price * 1000).round(),
      ),
    );
  }
  return items;
}
