import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F9 regression — applyCatalog and the offers slice.
///
/// The staff screen's catalog bridge re-runs applyCatalog on EVERY catalog
/// emission, and every named slice it omits falls back to a const-[] default
/// that overwrites the controller's state (the P-F1 bug class: replaceConfig's
/// defaults wiped the reason tables). Offers were never bridged until the
/// P-G6 sweep fix, so availableOffers was reset to empty on each emission and
/// the Offers sheet / auto-apply engine saw nothing. These tests pin the
/// forwarding + wipe semantics so the hazard stays visible; the screen-side
/// guard is the `offers: catalog.offers` line in staff_pos_screen.dart's
/// listener.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const offers = <Offer>[
    Offer(id: 1, name: 'Combo Deal', type: 'bundle'),
    Offer(id: 2, name: 'Happy Hour', type: 'percent'),
  ];

  test('applyCatalog forwards offers into availableOffers', () {
    final c = PosController();
    c.applyCatalog(
      categories: const [],
      products: const [],
      floors: const [],
      tables: const [],
      offers: offers,
    );

    expect(c.availableOffers.map((o) => o.id), [1, 2]);
  });

  test('re-applying WITHOUT offers wipes availableOffers (P-F1 bug class)',
      () {
    final c = PosController();
    c.applyCatalog(
      categories: const [],
      products: const [],
      floors: const [],
      tables: const [],
      offers: offers,
    );
    expect(c.availableOffers, isNotEmpty);

    // A catalog emission that omits the slice — exactly what the screen
    // bridge did before the fix. The const-[] default wins.
    c.applyCatalog(
      categories: const [],
      products: const [],
      floors: const [],
      tables: const [],
    );

    expect(
      c.availableOffers,
      isEmpty,
      reason: 'applyCatalog defaults overwrite state, so every caller that '
          'feeds it from a CatalogSnapshot must pass offers explicitly',
    );
  });
}
