import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import '../models/pos_models.dart';
import 'pricing_adapter.dart';

export 'pricing_adapter.dart' show AppliedOffer;

/// Compatibility wrapper for the machine's established offer-engine API.
/// The live implementation is the pinned shared pricing core.
List<AppliedOffer> evaluateOffers({
  required List<CartItem> cart,
  required List<double> lineNet,
  required List<Offer> offers,
  required DateTime now,
  required int branchId,
}) {
  final results = pricing.evaluateOffers(
    lines: [for (final item in cart) pricingLineFromCartItem(item)],
    lineNetBaisas: [for (final amount in lineNet) pricing.omrToBaisas(amount)],
    offers: [for (final offer in offers) pricingOfferFromOffer(offer)],
    now: now,
    branchId: branchId,
  );
  return [for (final result in results) appliedOfferFromResult(result)];
}
