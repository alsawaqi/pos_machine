import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/pricing_adapter.dart';

// Preservation coverage for P-1: the production controller passes its local
// DateTime.now() to the pricing adapter. These checks supply the same local
// wall-clock fields an Oman-configured device supplies, without depending on
// the test runner's timezone or replacing the real pricing/applicability code.
// This fixture is not evidence that the app converts a non-Oman device clock:
// production still requires the device's local timezone to be Asia/Muscat.
DateTime _omanLocal(String utc) {
  final wall = DateTime.parse(utc).add(const Duration(hours: 4));
  return DateTime(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  );
}

MerchantDiscount _discount({
  String? start = '17:00:00',
  String? end = '18:00:00',
  DateTime? validityStart,
  DateTime? validityEnd,
}) => MerchantDiscount(
  id: 8,
  name: 'Oman daily discount',
  scope: 'product',
  amountType: 'percent',
  percent: 10,
  timeStart: start,
  timeEnd: end,
  validityStart: validityStart,
  validityEnd: validityEnd,
  targets: const [DiscountTarget(targetType: 'product', targetId: 17)],
);

Offer _offer({String? start = '17:00:00', String? end = '18:00:00'}) => Offer(
  id: 9,
  name: 'Oman daily offer',
  type: 'spend_get',
  timeStart: start,
  timeEnd: end,
  config: const {
    'min_subtotal_baisas': 3000,
    'reward_type': 'percent_off',
    'reward_value': 10,
  },
);

pricing.PriceResult _price(
  DateTime local, {
  MerchantDiscount? discount,
  Offer? offer,
}) => pricing.priceOrder(
  pricing.PricingInput(
    now: local,
    branchId: 1,
    lines: [
      pricingLineFromCartItem(
        CartItem(
          product: const Product(
            id: '17',
            name: 'Coffee',
            category: 'Drinks',
            price: 3,
          ),
          qty: 1,
        ),
      ),
    ],
    discountRules: [
      if (discount != null) pricingRuleFromMerchantDiscount(discount),
    ],
    offers: [if (offer != null) pricingOfferFromOffer(offer)],
  ),
);

void main() {
  for (final useOffer in [false, true]) {
    final kind = useOffer ? 'offer' : 'product discount';
    test('P-1 $kind daily hours use the Oman local clock at both edges', () {
      // 13:00 UTC is 17:00 Oman. The old wrong 17:00 UTC interpretation is
      // 21:00 Oman and must not apply this daily 17:00-18:00 window.
      final rows = <(String, int, int)>[
        ('2026-09-27T12:59:59Z', 16, 3000),
        ('2026-09-27T13:00:00Z', 17, 2700),
        ('2026-09-27T14:00:00Z', 18, 2700),
        ('2026-09-27T14:00:01Z', 18, 3000),
        ('2026-09-27T17:00:00Z', 21, 3000),
      ];
      for (final (instant, expectedHour, expectedTotal) in rows) {
        final local = _omanLocal(instant);
        expect(local.hour, expectedHour);
        final result = _price(
          local,
          discount: useOffer ? null : _discount(),
          offer: useOffer ? _offer() : null,
        );
        expect(result.rawSubtotalBaisas, 3000);
        expect(result.grandTotalBaisas, expectedTotal, reason: instant);
        expect(result.discountTotalBaisas, 3000 - expectedTotal);
      }
    });

    test('P-1 $kind overnight daily hours wrap at Oman midnight', () {
      final rows = <(String, int, int)>[
        ('2026-09-27T17:59:59Z', 27, 3000),
        ('2026-09-27T18:00:00Z', 27, 2700),
        ('2026-09-27T20:00:00Z', 28, 2700),
        ('2026-09-27T22:00:00Z', 28, 2700),
        ('2026-09-27T22:00:01Z', 28, 3000),
      ];
      for (final (instant, expectedDay, expectedTotal) in rows) {
        final local = _omanLocal(instant);
        expect(local.day, expectedDay);
        final result = _price(
          local,
          discount: useOffer
              ? null
              : _discount(start: '22:00:00', end: '02:00:00'),
          offer: useOffer ? _offer(start: '22:00:00', end: '02:00:00') : null,
        );
        expect(result.grandTotalBaisas, expectedTotal, reason: instant);
      }
    });
  }

  test('P-1 ISO validity remains instant-based through the real adapter', () {
    final rule = _discount(
      start: null,
      end: null,
      validityStart: DateTime.parse('2026-09-27T13:15:00+00:00'),
      validityEnd: DateTime.parse('2026-09-27T13:45:00+00:00'),
    );
    final rows = <(String, int)>[
      ('2026-09-27T13:14:59Z', 3000),
      ('2026-09-27T13:15:00Z', 2700),
      ('2026-09-27T13:45:00Z', 2700),
      ('2026-09-27T13:45:01Z', 3000),
      ('2026-09-28T13:30:00Z', 3000),
    ];
    for (final (instant, expectedTotal) in rows) {
      // Unlike the daily-hours fixture, this case preserves the absolute
      // instant so that validity is checked independently of runner timezone.
      final local = DateTime.parse(instant).toLocal();
      expect(local.isAtSameMomentAs(DateTime.parse(instant)), isTrue);
      expect(
        _price(local, discount: rule).grandTotalBaisas,
        expectedTotal,
        reason: instant,
      );
    }
  });

  test('P-1 empty daily hours leave the discount and offer active all day', () {
    for (final instant in [
      '2026-09-26T20:00:00Z',
      '2026-09-27T08:00:00Z',
      '2026-09-27T19:59:59Z',
    ]) {
      final local = _omanLocal(instant);
      expect(
        _price(
          local,
          discount: _discount(start: null, end: null),
        ).grandTotalBaisas,
        2700,
      );
      expect(
        _price(local, offer: _offer(start: null, end: null)).grandTotalBaisas,
        2700,
      );
    }
  });
}
