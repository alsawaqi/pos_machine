import '../models/pos_models.dart';

/// P-F9 — the OFFER ENGINE: evaluates the merchant's promotions against the
/// cart and returns the money each applied offer takes off, allocated to
/// lines (so the wire can carry per-line discounts[] entries with offer_id).
///
/// PURE and deterministic: cart + offers + clock + branch in, allocations
/// out — no side effects, heavily unit-tested. Money is OMR doubles rounded
/// to 3 decimals (baisas precision) at every allocation.
///
/// Semantics (the standard restaurant rules, written down):
/// - The cart expands into UNITS (a line of qty 3 = 3 units). Each unit's
///   value is its share of the line's net (unit price minus the per-unit
///   merchant line discount). GIFTED lines are excluded — they're already
///   free. A unit participates in at most ONE offer application.
/// - Offers evaluate in id order; each may apply up to max_per_order times
///   (null = unlimited).
/// - bogo: each application consumes buy.qty matching units, then discounts
///   the CHEAPEST get.qty eligible units by percent_off (customer-friendly,
///   the industry default). With same_as_buy the get pool is the buy pool.
/// - multi_buy ("3 for 1.000"): each application takes the qty most
///   expensive eligible units and charges price_baisas for the set (the
///   discount is the difference, never negative).
/// - cheapest_free ("buy 3, cheapest free"): each application consumes qty
///   eligible units and makes the cheapest free_count of them free.
/// - spend_get: when the eligible subtotal (all non-gifted line nets) meets
///   min_subtotal_baisas: percent_off/fixed_off → an ORDER-level amount;
///   free_product → the cheapest unit of that product in the cart goes
///   free (nothing happens if it isn't in the cart — the Offers sheet
///   hints the cashier to add it). Defaults to once per order.
/// - bundle: never auto. The cashier picks the items (tagged with a
///   bundleKey); every evaluation re-validates each instance still has its
///   full group composition and, when intact, discounts the set down to
///   price_baisas (largest-remainder allocation keeps the sum exact).
///   Broken bundles (an item removed) charge normally — no discount.
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

  /// Per cart-line discount taken by this offer (line index → OMR).
  final Map<int, double> lineAmounts;

  /// Order-level discount (spend_get percent/fixed).
  final double orderAmount;

  /// How many times the offer applied (e.g. two complete BOGO pairs).
  final int applications;

  double get total =>
      _round(lineAmounts.values.fold(0.0, (s, v) => s + v) + orderAmount);
}

double _round(double v) => double.parse(v.toStringAsFixed(3));

class _Unit {
  _Unit(this.lineIndex, this.productId, this.categoryId, this.value);
  final int lineIndex;
  final int? productId;
  final int? categoryId;
  final double value; // the unit's net share (after merchant line discounts)
  bool consumed = false;
}

class _Selector {
  _Selector(Map<String, dynamic>? json)
      : productIds = _intList(json?['product_ids']),
        categoryIds = _intList(json?['category_ids']);

  final Set<int> productIds;
  final Set<int> categoryIds;

  bool get isEmpty => productIds.isEmpty && categoryIds.isEmpty;

  bool matches(_Unit u) =>
      (u.productId != null && productIds.contains(u.productId)) ||
      (u.categoryId != null && categoryIds.contains(u.categoryId));
}

Set<int> _intList(dynamic v) => ((v as List?) ?? const [])
    .map((e) => (e as num?)?.toInt())
    .whereType<int>()
    .toSet();

int _intOf(dynamic v, [int fallback = 0]) =>
    (v as num?)?.toInt() ?? fallback;

double _omr(dynamic v) => (_intOf(v)) / 1000.0;

/// Evaluate every applicable offer against the cart.
///
/// [lineNet] = each line's total net of merchant line discounts (same length
/// as [cart]); [now]/[branchId] gate applicability. Bundle instances are
/// discovered from the lines' bundleKey tags.
List<AppliedOffer> evaluateOffers({
  required List<CartItem> cart,
  required List<double> lineNet,
  required List<Offer> offers,
  required DateTime now,
  required int branchId,
}) {
  // ---- expand the cart into units --------------------------------------
  final units = <_Unit>[];
  for (var i = 0; i < cart.length; i++) {
    final item = cart[i];
    if (item.gifted) continue; // already free
    if (item.bundleKey.isNotEmpty) continue; // owned by a bundle instance
    if (item.qty <= 0) continue;
    final perUnit = lineNet[i] / item.qty;
    final productId = int.tryParse(item.product.id);
    for (var u = 0; u < item.qty; u++) {
      units.add(_Unit(i, productId, item.product.categoryId, perUnit));
    }
  }

  final applied = <AppliedOffer>[];
  final sorted = [...offers]..sort((a, b) => a.id.compareTo(b.id));

  for (final offer in sorted) {
    if (!offer.appliesAt(now, branchId: branchId)) continue;
    final AppliedOffer? result = switch (offer.type) {
      'bogo' => _applyBogo(offer, units),
      'multi_buy' => _applyMultiBuy(offer, units),
      'cheapest_free' => _applyCheapestFree(offer, units),
      'spend_get' => _applySpendGet(offer, units, cart, lineNet),
      'bundle' => _applyBundles(offer, cart, lineNet),
      _ => null,
    };
    if (result != null && result.total > 0) applied.add(result);
  }
  return applied;
}

List<_Unit> _free(List<_Unit> units, _Selector sel) =>
    units.where((u) => !u.consumed && sel.matches(u)).toList();

Map<int, double> _take(Map<int, double> into, _Unit u, double amount) {
  into[u.lineIndex] = _round((into[u.lineIndex] ?? 0) + amount);
  return into;
}

AppliedOffer? _applyBogo(Offer offer, List<_Unit> units) {
  final buy = _Selector(
      (offer.config['buy'] as Map?)?.cast<String, dynamic>());
  final getCfg = (offer.config['get'] as Map?)?.cast<String, dynamic>();
  final sameAsBuy = getCfg?['same_as_buy'] == true;
  final get = sameAsBuy ? buy : _Selector(getCfg);
  if (buy.isEmpty || get.isEmpty) return null;
  final buyQty = _intOf(offer.config['buy']?['qty'], 1).clamp(1, 999);
  final getQty = _intOf(getCfg?['qty'], 1).clamp(1, 999);
  final percent = _intOf(getCfg?['percent_off'], 100).clamp(1, 100);

  final amounts = <int, double>{};
  var applications = 0;
  while (offer.maxPerOrder == null || applications < offer.maxPerOrder!) {
    // The buy set: the most expensive eligible units (they "pay"), so the
    // discount lands on the cheapest get units — the industry rule.
    final buyPool = _free(units, buy)
      ..sort((a, b) => b.value.compareTo(a.value));
    if (buyPool.length < buyQty) break;
    final buySet = buyPool.take(buyQty).toList();
    for (final u in buySet) {
      u.consumed = true;
    }

    final getPool = _free(units, get)
      ..sort((a, b) => a.value.compareTo(b.value));
    if (getPool.length < getQty) {
      // Not enough left to reward — undo this application's buys and stop.
      for (final u in buySet) {
        u.consumed = false;
      }
      break;
    }
    for (final u in getPool.take(getQty)) {
      u.consumed = true;
      _take(amounts, u, _round(u.value * percent / 100));
    }
    applications++;
  }
  if (applications == 0) return null;
  return AppliedOffer(
    offerId: offer.id,
    name: offer.name,
    nameAr: offer.nameAr,
    lineAmounts: amounts,
    applications: applications,
  );
}

AppliedOffer? _applyMultiBuy(Offer offer, List<_Unit> units) {
  final sel = _Selector(offer.config.cast<String, dynamic>());
  if (sel.isEmpty) return null;
  final qty = _intOf(offer.config['qty'], 0);
  final price = _omr(offer.config['price_baisas']);
  if (qty < 2 || price <= 0) return null;

  final amounts = <int, double>{};
  var applications = 0;
  while (offer.maxPerOrder == null || applications < offer.maxPerOrder!) {
    // Most expensive set first = the biggest saving for the customer.
    final pool = _free(units, sel)..sort((a, b) => b.value.compareTo(a.value));
    if (pool.length < qty) break;
    final set = pool.take(qty).toList();
    final setValue = _round(set.fold(0.0, (s, u) => s + u.value));
    final discount = _round((setValue - price).clamp(0.0, setValue));
    for (final u in set) {
      u.consumed = true;
    }
    if (discount > 0) {
      // Allocate proportionally across the set's units, largest remainder
      // keeps the OMR sum exact at baisas precision.
      _allocateExactly(set, discount, amounts);
      applications++;
    } else {
      // The set is already cheaper than the bundle price — stop (later sets
      // are only cheaper still).
      break;
    }
  }
  if (applications == 0) return null;
  return AppliedOffer(
    offerId: offer.id,
    name: offer.name,
    nameAr: offer.nameAr,
    lineAmounts: amounts,
    applications: applications,
  );
}

AppliedOffer? _applyCheapestFree(Offer offer, List<_Unit> units) {
  final sel = _Selector(offer.config.cast<String, dynamic>());
  if (sel.isEmpty) return null;
  final qty = _intOf(offer.config['qty'], 0);
  final freeCount = _intOf(offer.config['free_count'], 1).clamp(1, 999);
  if (qty < 2 || freeCount >= qty) return null;

  final amounts = <int, double>{};
  var applications = 0;
  while (offer.maxPerOrder == null || applications < offer.maxPerOrder!) {
    final pool = _free(units, sel)..sort((a, b) => b.value.compareTo(a.value));
    if (pool.length < qty) break;
    final set = pool.take(qty).toList();
    for (final u in set) {
      u.consumed = true;
    }
    // The cheapest [freeCount] of the set go free.
    final cheapest = [...set]..sort((a, b) => a.value.compareTo(b.value));
    for (final u in cheapest.take(freeCount)) {
      _take(amounts, u, u.value);
    }
    applications++;
  }
  if (applications == 0) return null;
  return AppliedOffer(
    offerId: offer.id,
    name: offer.name,
    nameAr: offer.nameAr,
    lineAmounts: amounts,
    applications: applications,
  );
}

AppliedOffer? _applySpendGet(
  Offer offer,
  List<_Unit> units,
  List<CartItem> cart,
  List<double> lineNet,
) {
  final minSubtotal = _omr(offer.config['min_subtotal_baisas']);
  if (minSubtotal <= 0) return null;
  // The threshold counts everything sellable (incl. bundle lines, excl.
  // gifted) — the customer did spend that money.
  var eligible = 0.0;
  for (var i = 0; i < cart.length; i++) {
    if (cart[i].gifted) continue;
    eligible += lineNet[i];
  }
  if (_round(eligible) + 0.0005 < minSubtotal) return null;

  final rewardType = offer.config['reward_type']?.toString();
  switch (rewardType) {
    case 'percent_off':
      final percent =
          ((offer.config['reward_value'] as num?)?.toDouble() ?? 0)
              .clamp(0, 100);
      if (percent <= 0) return null;
      return AppliedOffer(
        offerId: offer.id,
        name: offer.name,
        nameAr: offer.nameAr,
        orderAmount: _round(eligible * percent / 100),
      );
    case 'fixed_off':
      final fixed = _omr(offer.config['reward_value']);
      if (fixed <= 0) return null;
      return AppliedOffer(
        offerId: offer.id,
        name: offer.name,
        nameAr: offer.nameAr,
        orderAmount: _round(fixed.clamp(0.0, eligible)),
      );
    case 'free_product':
      final productId = _intOf(offer.config['reward_product_id'], -1);
      if (productId < 0) return null;
      // The cheapest unconsumed unit of the reward product goes free.
      final pool = units
          .where((u) => !u.consumed && u.productId == productId)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      if (pool.isEmpty) return null;
      final unit = pool.first..consumed = true;
      return AppliedOffer(
        offerId: offer.id,
        name: offer.name,
        nameAr: offer.nameAr,
        lineAmounts: {unit.lineIndex: _round(unit.value)},
      );
  }
  return null;
}

AppliedOffer? _applyBundles(
  Offer offer,
  List<CartItem> cart,
  List<double> lineNet,
) {
  final price = _omr(offer.config['price_baisas']);
  final groups = ((offer.config['groups'] as List?) ?? const [])
      .whereType<Map>()
      .map((g) => g.cast<String, dynamic>())
      .toList();
  if (price <= 0 || groups.isEmpty) return null;

  // Collect this offer's bundle instances from the lines' bundleKey tags.
  final instances = <String, List<int>>{};
  for (var i = 0; i < cart.length; i++) {
    final key = cart[i].bundleKey;
    if (key.startsWith('${offer.id}:')) {
      (instances[key] ??= <int>[]).add(i);
    }
  }
  if (instances.isEmpty) return null;

  final amounts = <int, double>{};
  var applications = 0;
  instances.forEach((key, lineIndexes) {
    if (offer.maxPerOrder != null && applications >= offer.maxPerOrder!) {
      return;
    }
    // Validate the instance still satisfies EVERY group's composition.
    var intact = true;
    final remaining = <int>[...lineIndexes];
    for (final group in groups) {
      final ids = _intList(group['product_ids']);
      var requireQty = _intOf(group['qty'], 1).clamp(1, 99);
      for (final i in [...remaining]) {
        if (requireQty == 0) break;
        final pid = int.tryParse(cart[i].product.id);
        if (pid != null && ids.contains(pid)) {
          final take = cart[i].qty.clamp(0, requireQty);
          requireQty -= take;
          remaining.remove(i);
        }
      }
      if (requireQty > 0) {
        intact = false;
        break;
      }
    }
    if (!intact) return;

    final setValue = _round(
        lineIndexes.fold(0.0, (s, i) => s + lineNet[i]));
    final discount = _round((setValue - price).clamp(0.0, setValue));
    if (discount <= 0) return;
    final lineUnits = [
      for (final i in lineIndexes)
        _Unit(i, null, null, lineNet[i]),
    ];
    _allocateExactly(lineUnits, discount, amounts);
    applications++;
  });

  if (applications == 0) return null;
  return AppliedOffer(
    offerId: offer.id,
    name: offer.name,
    nameAr: offer.nameAr,
    lineAmounts: amounts,
    applications: applications,
  );
}

/// Distribute [discount] across [set] proportionally to each unit's value,
/// in BAISAS with largest-remainder so the allocations sum EXACTLY.
void _allocateExactly(
  List<_Unit> set,
  double discount,
  Map<int, double> into,
) {
  final totalValue = set.fold(0.0, (s, u) => s + u.value);
  if (totalValue <= 0) return;
  final discountBaisas = (discount * 1000).round();
  var allocated = 0;
  final shares = <({_Unit unit, int floor, double remainder})>[];
  for (final u in set) {
    final exact = discountBaisas * (u.value / totalValue);
    final floor = exact.floor();
    allocated += floor;
    shares.add((unit: u, floor: floor, remainder: exact - floor));
  }
  var leftover = discountBaisas - allocated;
  shares.sort((a, b) => b.remainder.compareTo(a.remainder));
  for (final s in shares) {
    var baisas = s.floor;
    if (leftover > 0) {
      baisas += 1;
      leftover -= 1;
    }
    if (baisas > 0) _take(into, s.unit, baisas / 1000.0);
  }
}
