/// LAUNCH item kind (owner decision 2026-10-03): an ingredient is Weighed
/// (kept in g, or legacy kg), Liquid (kept in ml, or legacy l) or Counted.
/// A Weighed or Liquid ingredient can be counted in either unit of its kind;
/// the device converts the typed amount to the stored unit before sending,
/// so the `stock.count` event is unchanged.
library;

/// Units by kind, with their size in the kind's smallest metric unit: the
/// metric pair (largest first), then the built-in non-metric pair (owner
/// decision 2026-10-03: US gallon and fl oz for liquids, lb and oz for
/// weighed items; exact factors).
const Map<String, List<(String, double)>> _kinds = {
  'mass': [('kg', 1000), ('g', 1), ('lb', 453.59237), ('oz', 28.349523125)],
  'volume': [
    ('l', 1000),
    ('ml', 1),
    ('gal', 3785.411784),
    ('fl oz', 29.5735295625),
  ],
};

/// How a unit reads on screen: the non-metric ones say their size, so there
/// is no doubt which gallon or ounce is meant.
String countUnitLabel(String unit) => switch (unit) {
      'gal' => 'gal (3.785 l)',
      'fl oz' => 'fl oz (29.57 ml)',
      'lb' => 'lb (453.6 g)',
      'oz' => 'oz (28.35 g)',
      _ => unit,
    };

String? _kindOf(String? unit) => switch (unit?.trim().toLowerCase()) {
      'kg' || 'g' => 'mass',
      'l' || 'ml' => 'volume',
      _ => null,
    };

double _size(String unit) {
  final u = unit.trim().toLowerCase();
  for (final units in _kinds.values) {
    for (final (name, size) in units) {
      if (name == u) return size;
    }
  }
  throw ArgumentError.value(unit, 'unit', 'not a metric unit');
}

/// The units a count of an ingredient stored in [storedUnit] can be typed
/// in: `[kg, g, lb, oz]` or `[l, ml, gal, fl oz]`; empty for counted items
/// and custom units.
List<String> countUnitChoices(String? storedUnit) {
  final kind = _kindOf(storedUnit);
  if (kind == null) return const <String>[];
  return [for (final (name, _) in _kinds[kind]!) name];
}

/// [value] typed in [typedUnit], expressed in [storedUnit] (same kind),
/// rounded to the 4 decimals the stock ledger keeps.
double toStoredUnits(double value, String typedUnit, String storedUnit) {
  final converted = value * _size(typedUnit) / _size(storedUnit);
  return double.parse(converted.toStringAsFixed(4));
}

/// An amount kept in [storedUnit], shown in the friendlier unit of its kind:
/// 1000 g or ml and above reads in kg or l ("12 l", not "12000 ml"). Up to
/// 4 decimals, trailing zeros trimmed.
String friendlyQuantity(double value, String? storedUnit) {
  final u = storedUnit?.trim().toLowerCase() ?? '';
  var shown = value;
  var unit = storedUnit?.trim() ?? '';
  if ((u == 'g' || u == 'ml') && value.abs() >= 1000) {
    shown = value / 1000;
    unit = u == 'g' ? 'kg' : 'l';
  }
  var text = shown.toStringAsFixed(4);
  if (text.contains('.')) text = text.replaceAll(RegExp(r'\.?0+$'), '');
  if (text == '-0') text = '0';
  return unit.isEmpty ? text : '$text $unit';
}
