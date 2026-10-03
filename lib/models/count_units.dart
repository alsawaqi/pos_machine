/// LAUNCH item kind (owner decision 2026-10-03): an ingredient is Weighed
/// (kept in g, or legacy kg), Liquid (kept in ml, or legacy l) or Counted.
/// A Weighed or Liquid ingredient can be counted in either unit of its kind;
/// the device converts the typed amount to the stored unit before sending,
/// so the `stock.count` event is unchanged.
library;

/// Metric units by kind, largest first, with their size in the kind's
/// smallest unit.
const Map<String, List<(String, double)>> _kinds = {
  'mass': [('kg', 1000), ('g', 1)],
  'volume': [('l', 1000), ('ml', 1)],
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
/// in, largest first (`[kg, g]` or `[l, ml]`); empty for counted items and
/// custom units.
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
