import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';

/// Phase C1 — the kitchen ticket layout contract (blueprint §6.10): items,
/// quantities, add-ons and notes only — never a price.
void main() {
  KitchenTicketData ticket({
    List<Map<String, dynamic>>? items,
    String tableLabel = '',
    String deliveryProvider = '',
    bool isReprint = false,
    bool isHold = false,
  }) {
    return KitchenTicketData(
      orderLabel: 'Order #1450',
      orderTypeLabel: 'Quick Order',
      time: DateTime(2026, 6, 10, 14, 5),
      tableLabel: tableLabel,
      deliveryProvider: deliveryProvider,
      isReprint: isReprint,
      isHold: isHold,
      items: items ??
          [
            {
              'name': 'Flat White',
              'qty': 2,
              'lineTotal': 2.4,
              'unitPrice': 1.2,
              'modifiers': [
                {'id': 'm1', 'group': 'Size', 'label': 'Large', 'price': 0.3},
                {'id': 'm2', 'group': '', 'label': 'Oat Milk', 'price': 0.2},
              ],
              'notes': 'No sugar',
            },
            {
              'name': 'Cheesecake',
              'qty': 1,
              'lineTotal': 1.8,
              'modifiers': const [],
              'notes': '',
            },
          ],
    );
  }

  List<String> textsOf(KitchenTicketData data) =>
      buildKitchenTicketLines(data).map((line) => line.text).toList();

  test('prints header, order label, type + time, items with qty', () {
    final texts = textsOf(ticket());

    expect(texts.first, 'KITCHEN');
    expect(texts, contains('Order #1450'));
    expect(texts, contains('Quick Order  10/06 14:05'));
    expect(texts, contains('2 x Flat White'));
    expect(texts, contains('1 x Cheesecake'));
  });

  test('never prints a price or money value', () {
    final joined = textsOf(ticket()).join('\n');

    expect(joined, isNot(contains('OMR')));
    expect(joined, isNot(contains('1.2')));
    expect(joined, isNot(contains('2.4')));
    expect(joined, isNot(contains('1.8')));
    expect(joined, isNot(contains('0.3')));
  });

  test('prints add-ons as indented lines (group-prefixed when present)', () {
    final texts = textsOf(ticket());

    expect(texts, contains('  + Size: Large'));
    expect(texts, contains('  + Oat Milk'));
  });

  test('prints line prep notes with the ** marker', () {
    final texts = textsOf(ticket());

    expect(texts, contains('  ** No sugar'));
  });

  test('omits empty modifiers, blank labels, and empty notes', () {
    final texts = textsOf(
      ticket(
        items: [
          {
            'name': 'Espresso',
            'qty': 1,
            'modifiers': [
              {'id': 'x', 'group': 'Size', 'label': '', 'price': 0},
            ],
            'notes': '   ',
          },
        ],
      ),
    );

    expect(texts.where((t) => t.startsWith('  +')), isEmpty);
    expect(texts.where((t) => t.startsWith('  **')), isEmpty);
  });

  test('reprint and hold banners', () {
    expect(textsOf(ticket(isReprint: true)), contains('*** REPRINT ***'));
    expect(textsOf(ticket(isHold: true)), contains('*** ON HOLD ***'));
    final plain = textsOf(ticket());
    expect(plain, isNot(contains('*** REPRINT ***')));
    expect(plain, isNot(contains('*** ON HOLD ***')));
  });

  test('table and delivery context lines render only when present', () {
    final dineIn = textsOf(ticket(tableLabel: 'Table 4 | Main Hall'));
    expect(dineIn, contains('Table 4 | Main Hall'));

    final delivery = textsOf(ticket(deliveryProvider: 'Talabat'));
    expect(delivery, contains('Delivery via Talabat'));

    final plain = textsOf(ticket());
    expect(plain.where((t) => t.startsWith('Table ')), isEmpty);
    expect(plain.where((t) => t.startsWith('Delivery via')), isEmpty);
  });

  test('fractional quantities print as-is, whole ones as integers', () {
    final texts = textsOf(
      ticket(
        items: [
          {'name': 'Juice', 'qty': 1.5, 'modifiers': const [], 'notes': ''},
          {'name': 'Cake', 'qty': 3.0, 'modifiers': const [], 'notes': ''},
        ],
      ),
    );

    expect(texts, contains('1.5 x Juice'));
    expect(texts, contains('3 x Cake'));
  });

  test('item lines are large + bold; add-on lines are not', () {
    final lines = buildKitchenTicketLines(ticket());

    final itemLine = lines.firstWhere((l) => l.text == '2 x Flat White');
    expect(itemLine.bold, isTrue);
    expect(itemLine.fontSize, 30);

    final addonLine = lines.firstWhere((l) => l.text == '  + Oat Milk');
    expect(addonLine.bold, isFalse);
    expect(addonLine.fontSize, isNull);
  });
}
