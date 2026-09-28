import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import '../models/pos_models.dart';
import 'pricing_adapter.dart';

/// Display-only projection of the same integer allocations sent by sync.
/// It never reprices a bill or changes its total.
class DiscountDisplayRow {
  const DiscountDisplayRow(this.key, this.name, this.amountBaisas);
  final String key;
  final String name;
  final int amountBaisas;

  String label({bool arabic = false}) =>
      name.trim().isEmpty ? (arabic ? 'الخصم' : 'Discount') : name;
}

List<DiscountDisplayRow> priceDiscountDisplayRows(
  pricing.PriceResult price, {
  required String orderLabel,
  int? orderRuleId,
}) => groupDiscountDisplayRows([
  if (price.orderDiscountRowBaisas > 0)
    DiscountDisplayRow(
      'order:$orderRuleId',
      orderLabel,
      price.orderDiscountRowBaisas,
    ),
  for (final row in price.lineDiscounts)
    DiscountDisplayRow(
      'line:${row.ruleId}:${row.label}',
      row.label,
      row.amountBaisas,
    ),
  for (final row in price.appliedOffers)
    DiscountDisplayRow('offer:${row.offerId}', row.name, row.totalBaisas),
], price.discountTotalBaisas);

List<DiscountDisplayRow> snapshotDiscountDisplayRows(OrderSnapshot order) =>
    order.discountSources.isNotEmpty
    ? serverDiscountDisplayRows({
        'discount_sources': order.discountSources,
        'discount_total_baisas': pricing.omrToBaisas(order.discountAmount),
      })
    : priceDiscountDisplayRows(
        frozenPriceResultFromSnapshot(order),
        orderLabel: order.discountLabel,
        orderRuleId: order.discountId,
      );

List<DiscountDisplayRow> serverDiscountDisplayRows(Map<String, dynamic> bill) {
  final source =
      (bill['discount_sources'] ?? bill['discounts']) as List? ?? const [];
  final rows = <DiscountDisplayRow>[
    for (final row in source.whereType<Map>())
      DiscountDisplayRow(
        row['offer_id'] != null
            ? 'offer:${row['offer_id']}'
            : '${row['source'] ?? 'order'}:${row['discount_id']}:${row['name']}',
        row['name']?.toString() ?? '',
        (row['amount_baisas'] as num?)?.toInt() ?? 0,
      ),
  ];
  // Older servers expose the table redemption separately from manual rows.
  if (bill['discount_sources'] == null &&
      (bill['loyalty_discount_baisas'] as num? ?? 0) > 0) {
    rows.add(
      DiscountDisplayRow(
        'loyalty',
        ((bill['adjustment_state'] as Map?)?['loyalty'] as Map?)?['name']
                ?.toString() ??
            '',
        (bill['loyalty_discount_baisas'] as num).toInt(),
      ),
    );
  }
  return groupDiscountDisplayRows(
    rows,
    (bill['discount_total_baisas'] as num?)?.toInt() ?? 0,
  );
}

/// Coalesce repeated allocations and append-only reversals per source. Legacy
/// snapshots without source detail retain an unnamed remainder, never an
/// invented attribution to the first rule. The integer rows always sum to total.
List<DiscountDisplayRow> groupDiscountDisplayRows(
  Iterable<DiscountDisplayRow> rows,
  int total,
) {
  final grouped = <String, DiscountDisplayRow>{};
  for (final row in rows) {
    final previous = grouped[row.key];
    grouped[row.key] = DiscountDisplayRow(
      row.key,
      row.name,
      (previous?.amountBaisas ?? 0) + row.amountBaisas,
    );
  }
  var remaining = total;
  final result = <DiscountDisplayRow>[];
  for (final row in grouped.values) {
    if (remaining <= 0 || row.amountBaisas <= 0) continue;
    final amount = row.amountBaisas.clamp(0, remaining);
    result.add(DiscountDisplayRow(row.key, row.name, amount));
    remaining -= amount;
  }
  if (remaining > 0) {
    result.add(DiscountDisplayRow('unattributed', '', remaining));
  }
  return result;
}
