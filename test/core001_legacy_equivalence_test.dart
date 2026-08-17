import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/pricing_adapter.dart';

import 'legacy/offer_engine_legacy.dart' as legacy;

const _seed = 0xC0E001;
const _caseCount = 1200;
const _branchId = 7;
final _now = DateTime(2026, 6, 15, 12, 30);

void main() {
  test(
    'CORE-001 seeded whole-order equivalence classifies only divergences #1/#2',
    () {
      final originalTaxes = activeCompanyTaxes;
      addTearDown(() => activeCompanyTaxes = originalTaxes);

      final random = Random(_seed);
      final coverage = <String, int>{};
      var exact = 0;
      var divergence1 = 0;
      var divergence2Tax = 0;
      var divergence2OrderPercent = 0;

      for (var caseIndex = 0; caseIndex < _caseCount; caseIndex++) {
        final scenario = _scenario(random, caseIndex);
        _recordCoverage(coverage, scenario);

        activeCompanyTaxes = scenario.taxes;
        final actual = _viewOf(
          pricing.priceOrder(buildPricingInput(scenario, scenario.now)),
        );
        final old = _legacyPrice(scenario);
        if (actual == old) {
          exact++;
          continue;
        }

        final classified = switch (scenario.expectedDivergence) {
          _ExpectedDivergence.multiBuyConsumeThenBreak => _isOnlyDivergence1(
            scenario,
            actual,
            old,
          ),
          _ExpectedDivergence.taxHalfBaisa => _isOnlyTaxHalfBaisaDivergence(
            scenario,
            actual,
            old,
          ),
          _ExpectedDivergence.orderPercentHalfBaisa =>
            _isOnlyOrderPercentHalfBaisaDivergence(scenario, actual, old),
          _ExpectedDivergence.none => false,
        };

        if (!classified) {
          fail(
            'Unclassified CORE-001 legacy mismatch. '
            'seed=$_seed case=$caseIndex\n'
            'scenario=${scenario.diagnostic}\n'
            'legacy=${old.canonical}\n'
            'core=${actual.canonical}',
          );
        }

        switch (scenario.expectedDivergence) {
          case _ExpectedDivergence.multiBuyConsumeThenBreak:
            divergence1++;
            break;
          case _ExpectedDivergence.taxHalfBaisa:
            divergence2Tax++;
            break;
          case _ExpectedDivergence.orderPercentHalfBaisa:
            divergence2OrderPercent++;
            break;
          case _ExpectedDivergence.none:
            fail('An unlicensed case was classified as divergent.');
        }
      }

      for (final key in const <String>[
        'qty:1',
        'qty:2',
        'qty:3',
        'qty:4',
        'qty:5',
        'modifiers',
        'gifts',
        'bundles',
        'rule:product',
        'rule:category',
        'rule:order',
        'offer:bogo',
        'offer:multi_buy',
        'offer:cheapest_free',
        'offer:spend_get',
        'offer:bundle',
        'taxes:0',
        'taxes:1',
        'taxes:2',
        'delivery',
      ]) {
        expect(
          coverage[key] ?? 0,
          greaterThan(0),
          reason: 'The seeded corpus must cover $key.',
        );
      }
      expect(divergence1, greaterThan(0));
      expect(divergence2Tax, greaterThan(0));
      expect(divergence2OrderPercent, greaterThan(0));
      expect(
        exact + divergence1 + divergence2Tax + divergence2OrderPercent,
        _caseCount,
      );

      debugPrint(
        'CORE-001 equivalence seed=$_seed cases=$_caseCount exact=$exact '
        'divergence#1=$divergence1 divergence#2-tax=$divergence2Tax '
        'divergence#2-order-percent=$divergence2OrderPercent '
        'coverage=${jsonEncode(coverage)}',
      );
    },
  );
}

enum _ExpectedDivergence {
  none,
  multiBuyConsumeThenBreak,
  taxHalfBaisa,
  orderPercentHalfBaisa,
}

final class _Scenario implements MachinePricingState {
  const _Scenario({
    required this.cart,
    required this.availableDiscounts,
    required this.availableOffers,
    required this.discount,
    required this.appliedComp,
    required this.selectedOrderType,
    required this.pricingBranchId,
    required this.taxes,
    required this.now,
    this.expectedDivergence = _ExpectedDivergence.none,
    this.divergence1MultiBuyId,
    this.divergence1FollowingOfferId,
  });

  @override
  final List<CartItem> cart;

  @override
  final List<MerchantDiscount> availableDiscounts;

  @override
  final List<Offer> availableOffers;

  @override
  final DiscountConfiguration discount;

  @override
  final AppliedComp? appliedComp;

  @override
  final OrderType selectedOrderType;

  @override
  final int? pricingBranchId;

  final List<CompanyTax> taxes;
  final DateTime now;
  final _ExpectedDivergence expectedDivergence;
  final int? divergence1MultiBuyId;
  final int? divergence1FollowingOfferId;

  @override
  int? get loyaltyRedeemRuleId => null;

  @override
  int get loyaltyRedeemPoints => 0;

  @override
  int get loyaltyRedeemStamps => 0;

  _Scenario withOffers(List<Offer> offers) => _Scenario(
    cart: cart,
    availableDiscounts: availableDiscounts,
    availableOffers: offers,
    discount: discount,
    appliedComp: appliedComp,
    selectedOrderType: selectedOrderType,
    pricingBranchId: pricingBranchId,
    taxes: taxes,
    now: now,
  );

  String get diagnostic => jsonEncode(<String, Object?>{
    'expectedDivergence': expectedDivergence.name,
    'branchId': pricingBranchId,
    'delivery': selectedOrderType == OrderType.delivery,
    'cart': [
      for (final item in cart)
        <String, Object?>{
          'productId': item.product.id,
          'categoryId': item.product.categoryId,
          'unitPriceBaisas': (item.unitPrice * 1000).round(),
          'qty': item.qty,
          'gifted': item.gifted,
          'bundleKey': item.bundleKey,
          'modifierCount': item.modifiers.length,
        },
    ],
    'discountRules': [
      for (final rule in availableDiscounts)
        <String, Object?>{
          'id': rule.id,
          'scope': rule.scope,
          'amountType': rule.amountType,
          'fixedAmount': rule.fixedAmount,
          'percent': rule.percent,
        },
    ],
    'offers': [
      for (final offer in availableOffers)
        <String, Object?>{
          'id': offer.id,
          'type': offer.type,
          'config': offer.config,
        },
    ],
    'orderDiscount': <String, Object?>{
      'kind': discount.kind.name,
      'value': discount.value,
    },
    'compLineIndex': appliedComp?.lineIndex,
    'taxRates': [for (final tax in taxes) tax.ratePercent],
  });
}

_Scenario _scenario(Random random, int caseIndex) {
  switch (caseIndex % 60) {
    case 0:
      return _divergence1Scenario(random);
    case 1:
      return _taxHalfBaisaScenario();
    case 2:
      return _orderPercentHalfBaisaScenario();
    default:
      return _randomCompatibleScenario(random, caseIndex);
  }
}

_Scenario _divergence1Scenario(Random random) {
  final unitBaisas = 200 + random.nextInt(1800);
  final product = Product(
    id: '101',
    name: 'D1 product',
    category: 'D1',
    categoryId: 10,
    price: unitBaisas / 1000,
  );
  const multiBuyId = 10;
  const bogoId = 20;
  return _Scenario(
    cart: <CartItem>[CartItem(product: product, qty: 3)],
    availableDiscounts: const <MerchantDiscount>[],
    availableOffers: <Offer>[
      Offer(
        id: multiBuyId,
        name: 'At-price multi-buy',
        type: 'multi_buy',
        config: <String, dynamic>{
          'product_ids': <int>[101],
          'qty': 2,
          'price_baisas': unitBaisas * 2,
        },
      ),
      const Offer(
        id: bogoId,
        name: 'Following BOGO',
        type: 'bogo',
        config: <String, dynamic>{
          'buy': <String, dynamic>{
            'product_ids': <int>[101],
            'qty': 2,
          },
          'get': <String, dynamic>{
            'same_as_buy': true,
            'qty': 1,
            'percent_off': 100,
          },
        },
      ),
    ],
    discount: const DiscountConfiguration(),
    appliedComp: null,
    selectedOrderType: OrderType.quickOrder,
    pricingBranchId: _branchId,
    taxes: const <CompanyTax>[],
    now: _now,
    expectedDivergence: _ExpectedDivergence.multiBuyConsumeThenBreak,
    divergence1MultiBuyId: multiBuyId,
    divergence1FollowingOfferId: bogoId,
  );
}

_Scenario _taxHalfBaisaScenario() => _Scenario(
  cart: <CartItem>[
    CartItem(
      product: const Product(
        id: '201',
        name: 'Tax midpoint',
        category: 'D2',
        categoryId: 20,
        price: 0.090,
      ),
    ),
  ],
  availableDiscounts: const <MerchantDiscount>[],
  availableOffers: const <Offer>[],
  discount: const DiscountConfiguration(),
  appliedComp: null,
  selectedOrderType: OrderType.quickOrder,
  pricingBranchId: _branchId,
  taxes: const <CompanyTax>[CompanyTax(name: 'VAT', ratePercent: 5)],
  now: _now,
  expectedDivergence: _ExpectedDivergence.taxHalfBaisa,
);

_Scenario _orderPercentHalfBaisaScenario() => _Scenario(
  cart: <CartItem>[
    CartItem(
      product: const Product(
        id: '202',
        name: 'Order percent midpoint',
        category: 'D2',
        categoryId: 20,
        price: 0.090,
      ),
    ),
  ],
  availableDiscounts: const <MerchantDiscount>[],
  availableOffers: const <Offer>[],
  discount: const DiscountConfiguration(
    kind: DiscountKind.percentage,
    value: 5,
    label: 'Five percent',
  ),
  appliedComp: null,
  selectedOrderType: OrderType.quickOrder,
  pricingBranchId: _branchId,
  taxes: const <CompanyTax>[],
  now: _now,
  expectedDivergence: _ExpectedDivergence.orderPercentHalfBaisa,
);

_Scenario _randomCompatibleScenario(Random random, int caseIndex) {
  final lineCount = 2 + random.nextInt(4);
  final cart = <CartItem>[];
  for (var lineIndex = 0; lineIndex < lineCount; lineIndex++) {
    final productId = 1000 + lineIndex;
    final baseBaisas = 250 + random.nextInt(4750);
    final modifierCount = (caseIndex + lineIndex) % 3;
    final modifiers = <CartItemModifier>[
      for (
        var modifierIndex = 0;
        modifierIndex < modifierCount;
        modifierIndex++
      )
        CartItemModifier(
          id: 'm$lineIndex-$modifierIndex',
          group: 'Group $modifierIndex',
          label: 'Modifier $modifierIndex',
          price: (25 + random.nextInt(376)) / 1000,
        ),
    ];
    cart.add(
      CartItem(
        product: Product(
          id: '$productId',
          name: 'Product $productId',
          category: 'Category ${lineIndex % 3}',
          categoryId: 30 + (lineIndex % 3),
          price: baseBaisas / 1000,
        ),
        qty: ((caseIndex + lineIndex) % 5) + 1,
        modifiers: modifiers,
        gifted: caseIndex % 11 == 0 && lineIndex == lineCount - 1,
      ),
    );
  }

  final offerId = 100 + (caseIndex % 7);
  final offerVariant = caseIndex % 7;
  final offers = <Offer>[];
  switch (offerVariant) {
    case 0:
      cart[0].qty = 1;
      cart[1].qty = 1;
      cart[0].gifted = false;
      cart[1].gifted = false;
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded BOGO',
          type: 'bogo',
          config: <String, dynamic>{
            'buy': <String, dynamic>{
              'product_ids': <int>[int.parse(cart[0].product.id)],
              'qty': 1,
            },
            'get': <String, dynamic>{
              'product_ids': <int>[int.parse(cart[1].product.id)],
              'qty': 1,
              'percent_off': 100,
            },
          },
          maxPerOrder: 2,
        ),
      );
      break;
    case 1:
      cart[0].qty = 2;
      cart[0].gifted = false;
      final setValue = (cart[0].unitPrice * 2000).round();
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded multi-buy',
          type: 'multi_buy',
          config: <String, dynamic>{
            'product_ids': <int>[int.parse(cart[0].product.id)],
            'qty': 2,
            'price_baisas': max(1, setValue - max(2, setValue ~/ 4)),
          },
          maxPerOrder: 2,
        ),
      );
      break;
    case 2:
      cart[0].qty = 2;
      cart[0].gifted = false;
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded cheapest-free',
          type: 'cheapest_free',
          config: <String, dynamic>{
            'product_ids': <int>[int.parse(cart[0].product.id)],
            'qty': 2,
            'free_count': 1,
          },
          maxPerOrder: 2,
        ),
      );
      break;
    case 3:
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded spend percent',
          type: 'spend_get',
          config: const <String, dynamic>{
            'min_subtotal_baisas': 1,
            'reward_type': 'percent_off',
            'reward_value': 8,
          },
        ),
      );
      break;
    case 4:
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded spend fixed',
          type: 'spend_get',
          config: <String, dynamic>{
            'min_subtotal_baisas': 1,
            'reward_type': 'fixed_off',
            'reward_value': 1 + random.nextInt(400),
          },
        ),
      );
      break;
    case 5:
      cart[1].qty = 1;
      cart[1].gifted = false;
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded free product',
          type: 'spend_get',
          config: <String, dynamic>{
            'min_subtotal_baisas': 1,
            'reward_type': 'free_product',
            'reward_product_id': int.parse(cart[1].product.id),
          },
        ),
      );
      break;
    case 6:
      cart[0]
        ..qty = 1
        ..gifted = false
        ..bundleKey = '$offerId:1';
      cart[1]
        ..qty = 1
        ..gifted = false
        ..bundleKey = '$offerId:1';
      final setValue = ((cart[0].unitPrice + cart[1].unitPrice) * 1000).round();
      offers.add(
        Offer(
          id: offerId,
          name: 'Seeded bundle',
          type: 'bundle',
          autoApply: false,
          config: <String, dynamic>{
            'price_baisas': max(1, setValue - max(2, setValue ~/ 5)),
            'groups': <Map<String, dynamic>>[
              <String, dynamic>{
                'product_ids': <int>[int.parse(cart[0].product.id)],
                'qty': 1,
              },
              <String, dynamic>{
                'product_ids': <int>[int.parse(cart[1].product.id)],
                'qty': 1,
              },
            ],
          },
        ),
      );
      break;
  }

  final firstLineDiscountBaisas = cart[0].qty * (5 + random.nextInt(46));
  final discounts = <MerchantDiscount>[
    MerchantDiscount(
      id: 1,
      name: 'Product fixed',
      scope: 'product',
      amountType: 'fixed',
      fixedAmount: firstLineDiscountBaisas / 1000,
      stackable: caseIndex.isEven,
      targets: <DiscountTarget>[
        DiscountTarget(
          targetType: 'product',
          targetId: int.parse(cart[0].product.id),
        ),
      ],
    ),
    MerchantDiscount(
      id: 2,
      name: 'Category percent',
      scope: 'category',
      amountType: 'percent',
      percent: caseIndex.isEven ? 4 : 8,
      targets: <DiscountTarget>[
        DiscountTarget(
          targetType: 'category',
          targetId: cart[1].product.categoryId!,
        ),
      ],
    ),
    MerchantDiscount(
      id: 3,
      name: 'Order rule',
      scope: 'order',
      amountType: caseIndex.isEven ? 'fixed' : 'percent',
      fixedAmount: caseIndex.isEven ? (20 + random.nextInt(180)) / 1000 : null,
      percent: caseIndex.isEven ? null : 8,
      autoApply: true,
    ),
  ];

  final discount = switch (caseIndex % 4) {
    0 => const DiscountConfiguration(),
    1 => discounts.last.toConfiguration(),
    2 => DiscountConfiguration(
      kind: DiscountKind.fixedAmount,
      value: (10 + random.nextInt(490)) / 1000,
      label: 'Manual fixed',
      reason: 'Seeded',
    ),
    _ => DiscountConfiguration(
      kind: DiscountKind.percentage,
      value: caseIndex.isEven ? 4 : 8,
      label: 'Manual percent',
      reason: 'Seeded',
    ),
  };

  final comp = switch (caseIndex % 5) {
    0 => null,
    1 => const AppliedComp(reasonId: 10, reasonName: 'Line', lineIndex: 0),
    2 => const AppliedComp(reasonId: 11, reasonName: 'Whole order'),
    3 => AppliedComp(
      reasonId: 12,
      reasonName: 'Last line',
      lineIndex: cart.length - 1,
    ),
    _ => const AppliedComp(reasonId: 13, reasonName: 'Invalid', lineIndex: 99),
  };

  final taxes = switch (caseIndex % 3) {
    0 => const <CompanyTax>[],
    1 => const <CompanyTax>[CompanyTax(name: 'VAT', ratePercent: 4)],
    _ => const <CompanyTax>[
      CompanyTax(name: 'VAT', ratePercent: 4),
      CompanyTax(name: 'Tourism', ratePercent: 8),
    ],
  };

  return _Scenario(
    cart: cart,
    availableDiscounts: discounts,
    availableOffers: offers,
    discount: discount,
    appliedComp: comp,
    selectedOrderType: caseIndex % 13 == 0
        ? OrderType.delivery
        : OrderType.quickOrder,
    pricingBranchId: caseIndex % 17 == 0 ? null : _branchId,
    taxes: taxes,
    now: _now,
  );
}

final class _LineDiscountValue {
  const _LineDiscountValue({
    required this.amount,
    required this.id,
    required this.amountType,
    required this.label,
  });

  final double amount;
  final int? id;
  final String? amountType;
  final String label;
}

_LineDiscountValue _legacyLineDiscount(_Scenario scenario, CartItem item) {
  final branchId = scenario.pricingBranchId;
  if (branchId == null || scenario.selectedOrderType == OrderType.delivery) {
    return const _LineDiscountValue(
      amount: 0,
      id: null,
      amountType: null,
      label: '',
    );
  }

  final productId = int.tryParse(item.product.id);
  final categoryId = item.product.categoryId;
  MerchantDiscount? best;
  var bestAmount = 0.0;
  for (final rule in scenario.availableDiscounts) {
    if (rule.isOrderScope) continue;
    if (!rule.appliesAt(scenario.now, branchId: branchId)) continue;
    if (!rule.appliesToProduct(productId, categoryId)) continue;
    final amount = rule.amountFor(item.lineTotal);
    if (amount > bestAmount) {
      bestAmount = amount;
      best = rule;
    }
  }
  if (best == null || bestAmount <= 0) {
    return const _LineDiscountValue(
      amount: 0,
      id: null,
      amountType: null,
      label: '',
    );
  }
  return _LineDiscountValue(
    amount: bestAmount,
    id: best.id,
    amountType: best.amountType,
    label: best.name,
  );
}

_PriceView _legacyPrice(_Scenario scenario) {
  final lineDiscounts = <_LineDiscountValue>[
    for (final item in scenario.cart) _legacyLineDiscount(scenario, item),
  ];
  final rawSubtotal = scenario.cart.fold<double>(
    0,
    (sum, item) => sum + item.lineTotal,
  );
  final lineDiscountTotal = lineDiscounts.fold<double>(
    0,
    (sum, result) => sum + result.amount,
  );

  final branchId = scenario.pricingBranchId;
  final appliedOffers =
      scenario.selectedOrderType == OrderType.delivery ||
          branchId == null ||
          scenario.availableOffers.isEmpty ||
          scenario.cart.isEmpty
      ? const <legacy.AppliedOffer>[]
      : legacy.evaluateOffers(
          cart: scenario.cart,
          lineNet: <double>[
            for (var i = 0; i < scenario.cart.length; i++)
              (scenario.cart[i].lineTotal - lineDiscounts[i].amount)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
          ],
          offers: <Offer>[
            for (final offer in scenario.availableOffers)
              if (offer.autoApply || offer.isBundle) offer,
          ],
          now: scenario.now,
          branchId: branchId,
        );
  final offerDiscountTotal = _round(
    appliedOffers.fold<double>(0, (sum, offer) => sum + offer.total),
  );

  final orderDiscount = scenario.discount.isActive
      ? switch (scenario.discount.kind) {
          DiscountKind.fixedAmount => scenario.discount.value,
          DiscountKind.percentage =>
            rawSubtotal * (scenario.discount.value / 100),
          DiscountKind.none => 0.0,
        }
      : 0.0;
  final discountTotal = _round(
    (orderDiscount + lineDiscountTotal + offerDiscountTotal)
        .clamp(0.0, rawSubtotal)
        .toDouble(),
  );
  final subtotal = _round(
    (rawSubtotal - discountTotal).clamp(0.0, double.infinity).toDouble(),
  );

  final giftAmounts = <int, double>{};
  for (var i = 0; i < scenario.cart.length; i++) {
    final item = scenario.cart[i];
    if (!item.gifted) continue;
    final amount = _round(
      (item.lineTotal - lineDiscounts[i].amount)
          .clamp(0.0, double.infinity)
          .toDouble(),
    );
    if (amount > 0) giftAmounts[i] = amount;
  }
  final giftedTotal = _round(
    giftAmounts.values.fold<double>(0, (sum, amount) => sum + amount),
  );

  final comp = scenario.appliedComp;
  double managerPart;
  if (comp == null) {
    managerPart = 0;
  } else if (comp.lineIndex == null) {
    managerPart = (subtotal - giftedTotal)
        .clamp(0.0, double.infinity)
        .toDouble();
  } else if (comp.lineIndex! < 0 || comp.lineIndex! >= scenario.cart.length) {
    managerPart = 0;
  } else {
    final lineIndex = comp.lineIndex!;
    final item = scenario.cart[lineIndex];
    managerPart = item.gifted
        ? 0
        : (item.lineTotal - lineDiscounts[lineIndex].amount)
              .clamp(0.0, double.infinity)
              .toDouble();
  }
  final compTotal = _round(
    (managerPart + giftedTotal).clamp(0.0, subtotal).toDouble(),
  );
  final managerComp = _round(
    (compTotal - giftedTotal).clamp(0.0, subtotal).toDouble(),
  );
  final taxedBase = _round(
    (subtotal - compTotal).clamp(0.0, double.infinity).toDouble(),
  );
  final taxLines = scenario.selectedOrderType == OrderType.delivery
      ? const <TaxLineAmount>[]
      : <TaxLineAmount>[
          for (final tax in scenario.taxes)
            TaxLineAmount(
              name: tax.name,
              ratePercent: tax.ratePercent,
              amount: _round(taxedBase * tax.ratePercent / 100),
            ),
        ];
  final taxTotal = scenario.selectedOrderType == OrderType.delivery
      ? 0.0
      : _round(taxLines.fold<double>(0, (sum, line) => sum + line.amount));
  final grandTotal = _round(taxedBase + taxTotal);

  final discountTotalBaisas = _baisas(discountTotal);
  final lineDiscountTotalBaisas = _baisas(lineDiscountTotal);
  final offerDiscountTotalBaisas = _baisas(offerDiscountTotal);
  final orderDiscountRowBaisas =
      (discountTotalBaisas - lineDiscountTotalBaisas - offerDiscountTotalBaisas)
          .clamp(0, _baisas(rawSubtotal));

  return _PriceView(<String, Object?>{
    'rawSubtotalBaisas': _baisas(rawSubtotal),
    'lineDiscounts': <Map<String, Object?>>[
      for (var i = 0; i < lineDiscounts.length; i++)
        if (lineDiscounts[i].amount > 0)
          <String, Object?>{
            'lineIndex': i,
            'amountBaisas': _baisas(lineDiscounts[i].amount),
            'ruleId': lineDiscounts[i].id,
            'amountType': lineDiscounts[i].amountType,
            'label': lineDiscounts[i].label,
          },
    ],
    'lineDiscountTotalBaisas': lineDiscountTotalBaisas,
    'appliedOffers': <Map<String, Object?>>[
      for (final offer in appliedOffers)
        <String, Object?>{
          'offerId': offer.offerId,
          'name': offer.name,
          'nameAr': offer.nameAr,
          'lineAmountsBaisas': _canonicalLineAmounts(<int, int>{
            for (final entry in offer.lineAmounts.entries)
              entry.key: _baisas(entry.value),
          }),
          'orderAmountBaisas': _baisas(offer.orderAmount),
          'applications': offer.applications,
        },
    ],
    'offerDiscountTotalBaisas': offerDiscountTotalBaisas,
    'orderDiscountBaisas': _baisas(orderDiscount),
    'orderDiscountRowBaisas': orderDiscountRowBaisas,
    'discountTotalBaisas': discountTotalBaisas,
    'subtotalBaisas': _baisas(subtotal),
    'giftAmountsBaisas': <String, int>{
      for (final entry in giftAmounts.entries)
        '${entry.key}': _baisas(entry.value),
    },
    'giftedTotalBaisas': _baisas(giftedTotal),
    'managerCompBaisas': _baisas(managerComp),
    'compTotalBaisas': _baisas(compTotal),
    'taxedBaseBaisas': _baisas(taxedBase),
    'taxLines': <Map<String, Object?>>[
      for (final line in taxLines)
        <String, Object?>{
          'name': line.name,
          'ratePercent': line.ratePercent,
          'amountBaisas': _baisas(line.amount),
        },
    ],
    'taxTotalBaisas': _baisas(taxTotal),
    'grandTotalBaisas': _baisas(grandTotal),
  });
}

_PriceView _viewOf(pricing.PriceResult result) => _PriceView(<String, Object?>{
  'rawSubtotalBaisas': result.rawSubtotalBaisas,
  'lineDiscounts': <Map<String, Object?>>[
    for (final discount in result.lineDiscounts)
      <String, Object?>{
        'lineIndex': discount.lineIndex,
        'amountBaisas': discount.amountBaisas,
        'ruleId': discount.ruleId,
        'amountType': discount.amountType,
        'label': discount.label,
      },
  ],
  'lineDiscountTotalBaisas': result.lineDiscountTotalBaisas,
  'appliedOffers': <Map<String, Object?>>[
    for (final offer in result.appliedOffers)
      <String, Object?>{
        'offerId': offer.offerId,
        'name': offer.name,
        'nameAr': offer.nameAr,
        'lineAmountsBaisas': _canonicalLineAmounts(offer.lineAmountsBaisas),
        'orderAmountBaisas': offer.orderAmountBaisas,
        'applications': offer.applications,
      },
  ],
  'offerDiscountTotalBaisas': result.offerDiscountTotalBaisas,
  'orderDiscountBaisas': result.orderDiscountBaisas,
  'orderDiscountRowBaisas': result.orderDiscountRowBaisas,
  'discountTotalBaisas': result.discountTotalBaisas,
  'subtotalBaisas': result.subtotalBaisas,
  'giftAmountsBaisas': <String, int>{
    for (final entry in result.giftAmountsBaisas.entries)
      '${entry.key}': entry.value,
  },
  'giftedTotalBaisas': result.giftedTotalBaisas,
  'managerCompBaisas': result.managerCompBaisas,
  'compTotalBaisas': result.compTotalBaisas,
  'taxedBaseBaisas': result.taxedBaseBaisas,
  'taxLines': <Map<String, Object?>>[
    for (final line in result.taxLines)
      <String, Object?>{
        'name': line.name,
        'ratePercent': line.ratePercent,
        'amountBaisas': line.amountBaisas,
      },
  ],
  'taxTotalBaisas': result.taxTotalBaisas,
  'grandTotalBaisas': result.grandTotalBaisas,
});

final class _PriceView {
  _PriceView(this.values) : canonical = jsonEncode(values);

  final Map<String, Object?> values;
  final String canonical;

  int intValue(String key) => values[key]! as int;

  List<Map<String, Object?>> listValue(String key) =>
      (values[key]! as List).cast<Map<String, Object?>>();

  @override
  bool operator ==(Object other) =>
      other is _PriceView && canonical == other.canonical;

  @override
  int get hashCode => canonical.hashCode;
}

bool _isOnlyDivergence1(_Scenario scenario, _PriceView actual, _PriceView old) {
  final multiBuyId = scenario.divergence1MultiBuyId;
  final followingOfferId = scenario.divergence1FollowingOfferId;
  if (multiBuyId == null || followingOfferId == null) return false;

  final withoutAtPriceMultiBuy = scenario.withOffers(<Offer>[
    for (final offer in scenario.availableOffers)
      if (offer.id != multiBuyId) offer,
  ]);
  final oldWithoutStarvation = _legacyPrice(withoutAtPriceMultiBuy);
  final actualOffers = actual.listValue('appliedOffers');
  final oldOffers = old.listValue('appliedOffers');

  // Divergence #1: deleting only the legacy consume-then-break offer makes
  // the legacy whole-order result byte-identical to core. The later offer
  // must be present only in core, proving that no unrelated mismatch passed.
  return actual == oldWithoutStarvation &&
      old != oldWithoutStarvation &&
      actualOffers.any((row) => row['offerId'] == followingOfferId) &&
      !oldOffers.any((row) => row['offerId'] == followingOfferId);
}

bool _isOnlyTaxHalfBaisaDivergence(
  _Scenario scenario,
  _PriceView actual,
  _PriceView old,
) {
  if (scenario.taxes.length != 1 ||
      scenario.taxes.single.ratePercent != 5 ||
      actual.intValue('taxedBaseBaisas') != 90 ||
      old.intValue('taxedBaseBaisas') != 90) {
    return false;
  }
  final actualExceptTax = Map<String, Object?>.from(actual.values)
    ..remove('taxLines')
    ..remove('taxTotalBaisas')
    ..remove('grandTotalBaisas');
  final oldExceptTax = Map<String, Object?>.from(old.values)
    ..remove('taxLines')
    ..remove('taxTotalBaisas')
    ..remove('grandTotalBaisas');

  // Divergence #2: 5% of 90 baisas is exactly 4.5 baisas. Core's decimal
  // law resolves it half-away-from-zero (5); the old double path produced 4.
  return jsonEncode(actualExceptTax) == jsonEncode(oldExceptTax) &&
      actual.intValue('taxTotalBaisas') == 5 &&
      old.intValue('taxTotalBaisas') == 4 &&
      actual.intValue('grandTotalBaisas') == 95 &&
      old.intValue('grandTotalBaisas') == 94;
}

bool _isOnlyOrderPercentHalfBaisaDivergence(
  _Scenario scenario,
  _PriceView actual,
  _PriceView old,
) {
  if (scenario.discount.kind != DiscountKind.percentage ||
      scenario.discount.value != 5 ||
      scenario.taxes.isNotEmpty ||
      scenario.appliedComp != null ||
      scenario.availableOffers.isNotEmpty ||
      scenario.availableDiscounts.isNotEmpty ||
      actual.intValue('rawSubtotalBaisas') != 90 ||
      old.intValue('rawSubtotalBaisas') != 90) {
    return false;
  }

  // Divergence #2: 5% of 90 baisas is exactly 4.5 baisas. Every changed
  // downstream quantity is pinned here; no additional mismatch is accepted.
  return actual.intValue('discountTotalBaisas') == 5 &&
      old.intValue('discountTotalBaisas') == 4 &&
      actual.intValue('orderDiscountBaisas') == 5 &&
      // The legacy isolated order amount rounds to 5; its noisy combined
      // discount-total path is what falls to 4 at this exact midpoint.
      old.intValue('orderDiscountBaisas') == 5 &&
      actual.intValue('orderDiscountRowBaisas') == 5 &&
      old.intValue('orderDiscountRowBaisas') == 4 &&
      actual.intValue('subtotalBaisas') == 85 &&
      old.intValue('subtotalBaisas') == 86 &&
      actual.intValue('giftedTotalBaisas') == 0 &&
      old.intValue('giftedTotalBaisas') == 0 &&
      actual.intValue('compTotalBaisas') == 0 &&
      old.intValue('compTotalBaisas') == 0 &&
      actual.intValue('taxTotalBaisas') == 0 &&
      old.intValue('taxTotalBaisas') == 0 &&
      actual.intValue('grandTotalBaisas') == 85 &&
      old.intValue('grandTotalBaisas') == 86;
}

void _recordCoverage(Map<String, int> coverage, _Scenario scenario) {
  void hit(String key) => coverage[key] = (coverage[key] ?? 0) + 1;

  for (final item in scenario.cart) {
    if (item.qty >= 1 && item.qty <= 5) hit('qty:${item.qty}');
    if (item.modifiers.isNotEmpty) hit('modifiers');
    if (item.gifted) hit('gifts');
    if (item.bundleKey.isNotEmpty) hit('bundles');
  }
  for (final rule in scenario.availableDiscounts) {
    hit('rule:${rule.scope}');
  }
  for (final offer in scenario.availableOffers) {
    hit('offer:${offer.type}');
  }
  hit('taxes:${scenario.taxes.length}');
  if (scenario.selectedOrderType == OrderType.delivery) hit('delivery');
}

double _round(double value) => double.parse(value.toStringAsFixed(3));

int _baisas(double value) => (value * 1000).round();

Map<String, int> _canonicalLineAmounts(Map<int, int> amounts) {
  // The contract here is exact money per line. Map insertion order is not an
  // amount; offer-list order and every wire-relevant list remain unnormalized.
  final indexes = amounts.keys.toList()..sort();
  return <String, int>{for (final index in indexes) '$index': amounts[index]!};
}
