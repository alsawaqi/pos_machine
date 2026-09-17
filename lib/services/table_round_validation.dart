import '../models/pos_models.dart';

/// A known catalogue rule failed before any durable send or kitchen print.
class TableRoundSelectionException implements Exception {
  const TableRoundSelectionException(this.product, this.group);
  final String product;
  final String group;

  String message({required bool arabic}) => arabic
      ? '$product: راجع اختيار $group من زر الإضافات قبل الإرسال أو الدفع.'
      : '$product: choose valid $group options with Add On before sending or paying.';
}

/// Validate only new quantities, never reprice previously submitted rounds.
/// Use raw catalogue bounds: an impossible configuration must not be relaxed.
void validateTableRoundSelections(
  List<Map<String, dynamic>> lines, {
  required Product? Function(int id) productForId,
  required List<AddonGroup> Function(Product product) groupsForProduct,
}) {
  for (final line in lines) {
    if ((line['qty'] as num? ?? 0) <= 0) continue;
    final product = productForId(line['product_id'] as int);
    if (product == null) continue; // Server remains authoritative for drift.
    final selected = (line['addon_ids'] as List? ?? const [])
        .whereType<int>()
        .toSet();
    for (final group in groupsForProduct(product)) {
      final choices = group.options.map((o) => o.id).toSet();
      final count = selected.intersection(choices).length;
      final minimum = group.minSelections ?? 0;
      final maximum = group.maxSelections ?? (group.multiSelect ? null : 1);
      if (count < minimum || (maximum != null && count > maximum)) {
        throw TableRoundSelectionException(product.name, group.name);
      }
    }
  }
}

class TableRoundReviewRequired implements Exception {
  const TableRoundReviewRequired();
  String message({required bool arabic}) => arabic
      ? 'راجع الجولة المعلّقة قبل الإرسال أو الدفع.'
      : 'Review the held round before sending or paying.';
}
