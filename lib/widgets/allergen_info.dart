/// LAUNCH costs & allergens add-on — the till's allergen lines, so staff can
/// answer customers: "Contains: Gluten, Milk" and "May contain: Sesame",
/// with the names from the config's allergen catalogue (English / Arabic).
/// Display only: nothing here touches orders, prices, receipts or tickets.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/pos_models.dart';

class AllergenInfoBlock extends StatelessWidget {
  const AllergenInfoBlock({
    super.key,
    required this.allergens,
    required this.catalog,
    this.showNone = false,
    this.fontSize = 13,
  });

  final AllergenSet allergens;
  final List<AllergenInfo> catalog;

  /// True in the item details: an item with none says so.
  final bool showNone;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String names(List<String> codes) => allergenNames(
      codes,
      catalog,
      arabic: arabic,
    ).join(arabic ? '، ' : ', ');
    if (allergens.isEmpty) {
      if (!showNone) return const SizedBox.shrink();
      return Text(
        l10n.posAllergensNone,
        key: const ValueKey('allergens-none'),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF5B6B73),
        ),
      );
    }
    return Column(
      key: const ValueKey('allergens'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (allergens.contains.isNotEmpty)
          Text(
            l10n.posAllergensContains(names(allergens.contains)),
            key: const ValueKey('allergens-contains'),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFB54708),
            ),
          ),
        if (allergens.mayContain.isNotEmpty)
          Text(
            l10n.posAllergensMayContain(names(allergens.mayContain)),
            key: const ValueKey('allergens-may-contain'),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8A5A00),
            ),
          ),
      ],
    );
  }
}

/// "Adds: Milk" under an option that adds allergens (empty = nothing).
String optionAllergenText(
  BuildContext context,
  List<String> codes,
  List<AllergenInfo> catalog,
) {
  if (codes.isEmpty) return '';
  final arabic = Localizations.localeOf(context).languageCode == 'ar';
  return L10n.of(context).posAllergensAdds(
    allergenNames(codes, catalog, arabic: arabic).join(arabic ? '، ' : ', '),
  );
}
