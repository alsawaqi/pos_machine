import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

/// The charity round-up may only be OFFERED on a CARD leg.
///
/// The round-up must ride the card charge — the bank collects sale + round-up
/// in one lump and the platform forwards the round-up to charity. A round-up
/// accepted on a CASH leg (previously allowed inside a split) put the money in
/// the till instead: the sync payload only transmits donations when a card
/// tender exists, so a cash-only split silently kept untracked charity cash,
/// and even in a mixed split the cash-leg round-up never reached the bank
/// lump. Plain cash sales never offered round-up; the gate now makes split
/// legs consistent with that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PosController seeded() {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Coffee'],
      products: const [
        Product(id: '10', name: 'Latte', nameAr: '', category: 'Coffee', price: 1.5),
      ],
      floors: const [],
      tables: const [],
      discounts: const [],
      offers: const [],
      branchId: 6,
    );
    c.addProduct(c.allProducts.first);
    return c;
  }

  group('canOfferCharityRoundUp — card legs only', () {
    test('offered on a single card payment', () {
      final c = seeded();
      c.selectPaymentMethod('Credit Card');
      expect(c.canOfferCharityRoundUp, isTrue);
    });

    test('never offered on a plain cash payment', () {
      final c = seeded();
      c.selectPaymentMethod('Cash');
      expect(c.canOfferCharityRoundUp, isFalse);
    });

    test('REGRESSION: never offered on a CASH leg of a split (the till leak)', () {
      final c = seeded();
      c.setSplitCount(2);
      c.selectPaymentMethod('Cash');
      // Collecting a round-up here would put untracked charity money in the
      // till — the donation event only rides card tenders.
      expect(c.canOfferCharityRoundUp, isFalse);
    });

    test('still offered on a CARD leg of a split', () {
      final c = seeded();
      c.setSplitCount(2);
      c.selectPaymentMethod('Credit Card');
      expect(c.canOfferCharityRoundUp, isTrue);
    });

    test('never offered on bank POS (bank-terminal money is merchant-held)', () {
      final c = seeded();
      c.selectPaymentMethod('Bank POS');
      expect(c.canOfferCharityRoundUp, isFalse);
    });
  });
}
