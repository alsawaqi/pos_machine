import '../models/pos_models.dart';

/// The cart lines of a claimed transfer (POST /device/transfers/{uuid}/claim
/// → `order.items`, the server's DeviceOrderItems shape).
///
/// LAUNCH-P4 C7 — a combo's children are never lines of their own: each combo
/// line carries them as `combo` (per ONE combo: slot_id, product_id,
/// product_name, qty, extra_price_baisas, notes, addons). They become the
/// line's [ComboComponent]s, so the resumed cart, its edits and its payment
/// (order.create `combo[]`) keep the same choices. The line's base price is
/// the server unit price minus its add-ons and its components.
List<CartItem> transferClaimCartItems(
  Map<String, dynamic> order, {
  required Product? Function(String id) productForId,
}) {
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
          price: ((a['price_delta_baisas'] as num?)?.toInt() ?? 0) / 1000.0,
        ),
    ];

    final components = <ComboComponent>[
      for (final c
          in ((m['combo'] ?? m['components']) as List? ?? const [])
              .whereType<Map>())
        if ((c['product_id'] as num?)?.toInt() case final int cid)
          ComboComponent(
            slotId: (c['slot_id'] as num?)?.toInt() ?? 0,
            productId: '$cid',
            name:
                productForId('$cid')?.name ??
                (c['product_name'] ?? c['name'] ?? '').toString(),
            nameAr: productForId('$cid')?.nameAr ?? '',
            qty: ((c['qty'] as num?) ?? 1).round(),
            extraPrice:
                ((c['extra_price_baisas'] as num?)?.toInt() ?? 0) / 1000.0,
            modifiers: [
              for (final a
                  in (c['addons'] as List? ?? const []).whereType<Map>())
                CartItemModifier(
                  id: '${(a['add_on_id'] as num?)?.toInt() ?? ''}',
                  group: '',
                  label: (a['add_on_name'] ?? a['name'] ?? '').toString(),
                  price:
                      ((a['price_delta_baisas'] as num?)?.toInt() ?? 0) /
                      1000.0,
                ),
            ],
            notes: (c['notes'] ?? '').toString(),
          ),
    ];

    final unitPrice = ((m['unit_price_baisas'] as num?)?.toInt() ?? 0) / 1000.0;
    final addonTotal = modifiers.fold(0.0, (sum, mo) => sum + mo.price);
    final componentTotal = components.fold(0.0, (sum, c) => sum + c.comboDelta);
    final basePrice = double.parse(
      (unitPrice - addonTotal - componentTotal).toStringAsFixed(3),
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
          price: basePrice,
          imageAsset: catalog?.imageAsset,
          imageUrl: catalog?.imageUrl,
          addonGroupIds: catalog?.addonGroupIds ?? const <int>[],
          productType:
              catalog?.productType ??
              (components.isEmpty ? 'standard' : 'combo'),
        ),
        qty: ((m['qty'] as num?) ?? 1).round(),
        modifiers: modifiers,
        notes: (m['notes'] ?? '').toString(),
        components: components,
      ),
    );
  }
  return items;
}
