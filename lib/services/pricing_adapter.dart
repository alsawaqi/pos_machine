import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import '../models/pos_models.dart';

/// The controller state needed at the single machine -> core pricing boundary.
///
/// Keeping this as a small interface lets the adapter own every model mapping
/// without importing the controller (and gives tests a lightweight source).
abstract interface class MachinePricingState {
  List<CartItem> get cart;
  List<MerchantDiscount> get availableDiscounts;
  List<Offer> get availableOffers;
  DiscountConfiguration get discount;
  AppliedComp? get appliedComp;
  int? get loyaltyRedeemRuleId;
  int get loyaltyRedeemPoints;
  int get loyaltyRedeemStamps;
  OrderType get selectedOrderType;
  int? get pricingBranchId;
}

/// The OMR-shaped offer result retained by the machine UI and snapshots.
class AppliedOffer {
  const AppliedOffer({
    required this.offerId,
    required this.name,
    this.nameAr,
    this.lineAmounts = const <int, double>{},
    this.orderAmount = 0,
    this.applications = 1,
  });

  final int offerId;
  final String name;
  final String? nameAr;
  final Map<int, double> lineAmounts;
  final double orderAmount;
  final int applications;

  double get total => pricing.baisasToOmr(
    lineAmounts.values.fold<int>(
          0,
          (sum, amount) => sum + pricing.omrToBaisas(amount),
        ) +
        pricing.omrToBaisas(orderAmount),
  );
}

/// LAUNCH combo add-on — a meal line is invisible to product / category
/// discounts and offers (no product, no category), like the server; a combo
/// line is its combo product.
pricing.PricingLine pricingLineFromCartItem(CartItem item) =>
    pricing.PricingLine(
      productId: item.isMeal ? null : int.tryParse(item.product.id),
      categoryId: item.isMeal ? null : item.product.categoryId,
      unitPriceBaisas: (item.unitPrice * 1000).round(),
      qty: item.qty,
      gifted: item.gifted,
      bundleKey: item.bundleKey,
    );

pricing.DiscountRule pricingRuleFromMerchantDiscount(MerchantDiscount rule) =>
    pricing.DiscountRule(
      id: rule.id,
      name: rule.name,
      scope: rule.scope,
      amountType: rule.amountType,
      fixedBaisas: rule.fixedAmount == null
          ? null
          : (rule.fixedAmount! * 1000).round(),
      percent: rule.percent,
      validityStart: rule.validityStart,
      validityEnd: rule.validityEnd,
      dayOfWeekMask: rule.dayOfWeekMask,
      timeStart: rule.timeStart,
      timeEnd: rule.timeEnd,
      branchScope: List<int>.from(rule.branchScope),
      stackable: rule.stackable,
      requiresManagerApproval: rule.requiresManagerApproval,
      isActive: rule.isActive,
      autoApply: rule.autoApply,
      targets: [
        for (final target in rule.targets)
          pricing.DiscountTarget(
            targetType: target.targetType,
            targetId: target.targetId,
          ),
      ],
    );

pricing.OfferSpec pricingOfferFromOffer(Offer offer) => pricing.OfferSpec(
  id: offer.id,
  name: offer.name,
  nameAr: offer.nameAr,
  type: offer.type,
  config: offer.config,
  autoApply: offer.autoApply,
  validityStart: offer.validityStart,
  validityEnd: offer.validityEnd,
  dayOfWeekMask: offer.dayOfWeekMask,
  timeStart: offer.timeStart,
  timeEnd: offer.timeEnd,
  branchScope: List<int>.from(offer.branchScope),
  maxPerOrder: offer.maxPerOrder,
  isActive: offer.isActive,
);

/// The core's percentage convenience constructor predates the adapter contract's
/// requirement to retain loyalty metadata on every active selection. Keep that
/// metadata on the machine side without changing the pinned core package.
final class _PercentageOrderDiscountSelection
    extends pricing.OrderDiscountSelection {
  const _PercentageOrderDiscountSelection({
    required super.percent,
    required super.label,
    required super.discountId,
    required super.reason,
    required int? loyaltyRuleId,
    required int loyaltyPoints,
    required int loyaltyStamps,
  }) : _loyaltyRuleId = loyaltyRuleId,
       _loyaltyPoints = loyaltyPoints,
       _loyaltyStamps = loyaltyStamps,
       super.percentage();

  final int? _loyaltyRuleId;
  final int _loyaltyPoints;
  final int _loyaltyStamps;

  @override
  int? get loyaltyRuleId => _loyaltyRuleId;

  @override
  int get loyaltyPoints => _loyaltyPoints;

  @override
  int get loyaltyStamps => _loyaltyStamps;
}

pricing.OrderDiscountSelection pricingOrderDiscountFromMachine({
  required DiscountConfiguration discount,
  required int? loyaltyRuleId,
  required int loyaltyPoints,
  required int loyaltyStamps,
}) {
  if (!discount.isActive) return const pricing.OrderDiscountSelection.none();
  return switch (discount.kind) {
    DiscountKind.fixedAmount => pricing.OrderDiscountSelection.fixed(
      fixedBaisas: (discount.value * 1000).round(),
      label: discount.label,
      discountId: discount.discountId,
      reason: discount.reason,
      loyaltyRuleId: loyaltyRuleId,
      loyaltyPoints: loyaltyPoints,
      loyaltyStamps: loyaltyStamps,
    ),
    DiscountKind.percentage => _PercentageOrderDiscountSelection(
      percent: discount.value,
      label: discount.label,
      discountId: discount.discountId,
      reason: discount.reason,
      loyaltyRuleId: loyaltyRuleId,
      loyaltyPoints: loyaltyPoints,
      loyaltyStamps: loyaltyStamps,
    ),
    DiscountKind.none => const pricing.OrderDiscountSelection.none(),
  };
}

pricing.CompSelection? pricingCompFromAppliedComp(AppliedComp? comp) =>
    comp == null
    ? null
    : pricing.CompSelection(
        lineIndex: comp.lineIndex,
        qty: comp.qty,
        reasonId: comp.reasonId,
        reason: comp.reasonName,
      );

pricing.TaxSpec pricingTaxFromCompanyTax(CompanyTax tax) => pricing.TaxSpec(
  name: tax.name,
  nameAr: tax.nameAr,
  ratePercent: tax.ratePercent,
);

/// Builds the package input once from the controller's current machine state.
pricing.PricingInput buildPricingInput(
  MachinePricingState state,
  DateTime now,
) => pricing.PricingInput(
  lines: [for (final item in state.cart) pricingLineFromCartItem(item)],
  discountRules: [
    for (final rule in state.availableDiscounts)
      pricingRuleFromMerchantDiscount(rule),
  ],
  offers: [
    for (final offer in state.availableOffers) pricingOfferFromOffer(offer),
  ],
  orderDiscount: pricingOrderDiscountFromMachine(
    discount: state.discount,
    loyaltyRuleId: state.loyaltyRedeemRuleId,
    loyaltyPoints: state.loyaltyRedeemPoints,
    loyaltyStamps: state.loyaltyRedeemStamps,
  ),
  comp: pricingCompFromAppliedComp(state.appliedComp),
  taxes: [for (final tax in activeCompanyTaxes) pricingTaxFromCompanyTax(tax)],
  isDeliveryProvider: state.selectedOrderType == OrderType.delivery,
  // LAUNCH-P4 — the merchant's "menu prices include VAT" switch.
  pricesIncludeTax: activePricesIncludeTax,
  now: now,
  branchId: state.pricingBranchId,
);

AppliedOffer appliedOfferFromResult(pricing.AppliedOfferResult result) =>
    AppliedOffer(
      offerId: result.offerId,
      name: result.name,
      nameAr: result.nameAr,
      lineAmounts: {
        for (final entry in result.lineAmountsBaisas.entries)
          entry.key: pricing.baisasToOmr(entry.value),
      },
      orderAmount: pricing.baisasToOmr(result.orderAmountBaisas),
      applications: result.applications,
    );

List<AppliedOffer> appliedOffersFromResult(pricing.PriceResult result) => [
  for (final offer in result.appliedOffers) appliedOfferFromResult(offer),
];

TaxLineAmount taxLineFromResult(pricing.TaxLineResult result) => TaxLineAmount(
  name: result.name,
  nameAr: result.nameAr,
  ratePercent: result.ratePercent,
  amount: pricing.baisasToOmr(result.amountBaisas),
);

DiscountConfiguration discountConfigurationFromSelection(
  pricing.OrderDiscountSelection selection,
) => switch (selection.kind) {
  pricing.OrderDiscountKind.fixedAmount => DiscountConfiguration(
    kind: DiscountKind.fixedAmount,
    value: pricing.baisasToOmr(selection.fixedBaisas),
    label: selection.label,
    discountId: selection.discountId,
    reason: selection.reason,
  ),
  pricing.OrderDiscountKind.percentage => DiscountConfiguration(
    kind: DiscountKind.percentage,
    value: selection.percent,
    label: selection.label,
    discountId: selection.discountId,
    reason: selection.reason,
  ),
  pricing.OrderDiscountKind.none => const DiscountConfiguration(),
};

/// Rehydrates the core result that was frozen into an [OrderSnapshot].
///
/// Completed snapshots persist across restarts, so the payload cannot depend
/// on an in-memory PriceResult. Every value below is an integer conversion of
/// data sourced from the controller's PriceResult at freeze time; no pricing
/// rule is evaluated again here.
pricing.PriceResult frozenPriceResultFromSnapshot(OrderSnapshot snapshot) {
  final lineDiscounts = <pricing.LineDiscountResult>[];
  final gifts = <int, int>{};
  for (var i = 0; i < snapshot.items.length; i++) {
    final item = snapshot.items[i];
    final lineAmount = pricing.omrToBaisas(
      (item['lineDiscount'] as num?)?.toDouble() ?? 0,
    );
    if (lineAmount > 0) {
      lineDiscounts.add(
        pricing.LineDiscountResult(
          lineIndex: i,
          amountBaisas: lineAmount,
          ruleId: (item['lineDiscountId'] as num?)?.toInt(),
          amountType: item['lineDiscountAmountType']?.toString(),
          label: item['lineDiscountLabel']?.toString() ?? '',
        ),
      );
    }
    final giftAmount = pricing.omrToBaisas(
      (item['giftAmount'] as num?)?.toDouble() ?? 0,
    );
    if (giftAmount > 0) gifts[i] = giftAmount;
  }

  final offerBuilders = <int, _FrozenOfferBuilder>{};
  for (final row in snapshot.offers) {
    final offerId = (row['offer_id'] as num?)?.toInt();
    if (offerId == null) continue;
    final builder = offerBuilders.putIfAbsent(
      offerId,
      () => _FrozenOfferBuilder(
        offerId: offerId,
        name: row['name']?.toString() ?? 'Offer',
      ),
    );
    final amount = pricing.omrToBaisas(
      (row['amount'] as num?)?.toDouble() ?? 0,
    );
    if (amount <= 0) continue;
    final lineIndex = (row['line_index'] as num?)?.toInt();
    if (lineIndex == null) {
      builder.orderAmountBaisas += amount;
    } else {
      builder.lineAmountsBaisas[lineIndex] =
          (builder.lineAmountsBaisas[lineIndex] ?? 0) + amount;
    }
  }
  final offers = [for (final builder in offerBuilders.values) builder.build()];

  final raw = pricing.omrToBaisas(snapshot.rawSubtotal);
  final discountTotal = pricing.omrToBaisas(snapshot.discountAmount);
  final lineDiscountTotal = lineDiscounts.fold<int>(
    0,
    (sum, row) => sum + row.amountBaisas,
  );
  final offerDiscountTotal = offers.fold<int>(
    0,
    (sum, row) => sum + row.totalBaisas,
  );
  final subtotal = pricing.omrToBaisas(snapshot.subtotal);
  final giftedTotal = gifts.values.fold<int>(0, (sum, amount) => sum + amount);
  final compTotal = pricing.omrToBaisas(snapshot.compAmount);
  final managerComp = pricing.managerCompBaisasFor(
    compTotalBaisas: compTotal,
    giftedTotalBaisas: giftedTotal,
    subtotalBaisas: subtotal,
  );
  final taxedBase = (subtotal - compTotal).clamp(0, subtotal).toInt();
  final taxTotal = pricing.omrToBaisas(snapshot.tax);
  final grandTotal = pricing.omrToBaisas(snapshot.total);
  final orderDiscountRow =
      (discountTotal - lineDiscountTotal - offerDiscountTotal)
          .clamp(0, raw)
          .toInt();

  return pricing.PriceResult(
    rawSubtotalBaisas: raw,
    lineDiscounts: lineDiscounts,
    lineDiscountTotalBaisas: lineDiscountTotal,
    appliedOffers: offers,
    offerDiscountTotalBaisas: offerDiscountTotal,
    orderDiscountBaisas: orderDiscountRow,
    discountTotalBaisas: discountTotal,
    subtotalBaisas: subtotal,
    giftAmountsBaisas: gifts,
    giftedTotalBaisas: giftedTotal,
    managerCompBaisas: managerComp,
    compTotalBaisas: compTotal,
    taxedBaseBaisas: taxedBase,
    taxLines: [
      for (final line in snapshot.taxLines)
        pricing.TaxLineResult(
          name: line['name']?.toString() ?? '',
          nameAr: line['nameAr']?.toString(),
          ratePercent: (line['ratePercent'] as num?)?.toDouble() ?? 0,
          amountBaisas: pricing.omrToBaisas(
            (line['amount'] as num?)?.toDouble() ?? 0,
          ),
        ),
    ],
    taxTotalBaisas: taxTotal,
    grandTotalBaisas: grandTotal,
    pricesIncludeTax: snapshot.pricesIncludeTax,
  );
}

pricing.CompSelection? frozenCompSelectionFromSnapshot(
  OrderSnapshot snapshot,
) => snapshot.compReasonId == null
    ? null
    : pricing.CompSelection(
        lineIndex: snapshot.compLineIndex,
        qty: snapshot.compQty,
        reasonId: snapshot.compReasonId,
        reason: snapshot.compReasonName,
      );

final class _FrozenOfferBuilder {
  _FrozenOfferBuilder({required this.offerId, required this.name});

  final int offerId;
  final String name;
  final Map<int, int> lineAmountsBaisas = <int, int>{};
  int orderAmountBaisas = 0;

  pricing.AppliedOfferResult build() => pricing.AppliedOfferResult(
    offerId: offerId,
    name: name,
    lineAmountsBaisas: lineAmountsBaisas,
    orderAmountBaisas: orderAmountBaisas,
  );
}
