import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';

/// Phase C4e — Arabic catalog display: the English name stays the IDENTITY
/// (payloads, comparisons, receipts); Arabic is display-only with an English
/// fallback when the merchant provided none.
void main() {
  const latte = Product(
    id: '10',
    name: 'Latte',
    nameAr: 'لاتيه',
    category: 'Coffee',
    price: 2.0,
  );
  const cake = Product(id: '11', name: 'Cake', category: 'Dessert', price: 3.0);

  test('Product.displayName: Arabic when present, English fallback', () {
    expect(latte.displayName(true), 'لاتيه');
    expect(latte.displayName(false), 'Latte');
    expect(cake.displayName(true), 'Cake'); // no Arabic provided
  });

  test('nameAr round-trips through Product.toMap/fromMap and CartItem.toMap', () {
    final restored = Product.fromMap(latte.toMap());
    expect(restored.nameAr, 'لاتيه');

    final cartMap = CartItem(product: latte, qty: 2).toMap();
    expect(cartMap['nameAr'], 'لاتيه');
    expect(cartMap['name'], 'Latte'); // identity untouched
    expect(CartItem.fromMap(cartMap).product.displayName(true), 'لاتيه');
    // No Arabic → key omitted (schema stays lean for legacy drafts).
    expect(CartItem(product: cake).toMap().containsKey('nameAr'), isFalse);
  });

  test('CartItemModifier.displayLabel + detailLinesFor use Arabic labels', () {
    final item = CartItem(
      product: latte,
      modifiers: const [
        CartItemModifier(
          id: '100',
          group: 'Size',
          label: 'Large',
          labelAr: 'كبير',
          price: 0.5,
        ),
        CartItemModifier(id: '101', group: 'Size', label: 'Hot', price: 0),
      ],
    );

    expect(item.modifiers.first.displayLabel(true), 'كبير');
    expect(item.modifiers.last.displayLabel(true), 'Hot'); // fallback

    final ar = item.detailLinesFor(true).join('\n');
    expect(ar, contains('كبير'));
    expect(ar, contains('Hot'));
    // The English summary (and anything persisted before C4) is unchanged.
    expect(item.detailLines.join('\n'), contains('Large'));
    // labelAr round-trips through the cart-line map (held drafts/snapshots).
    final restored = CartItem.fromMap(item.toMap());
    expect(restored.modifiers.first.displayLabel(true), 'كبير');
  });
}
