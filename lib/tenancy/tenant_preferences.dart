import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'business_identity.dart';

Future<SharedPreferences> businessPreferences() async {
  final raw = await SharedPreferences.getInstance();
  if (!BusinessBoundary.initialized) return raw;
  final prefs = TenantPreferences(raw);
  if (BusinessBoundary.canWork) await prefs.archiveForeignRecords();
  return prefs;
}

/// One native preference write persists both value and owner. Physical keys
/// include the owner, so a late platform write cannot replace a new owner's data.
class TenantPreferences implements SharedPreferences {
  TenantPreferences(this.raw);
  final SharedPreferences raw;
  bool _unscoped(String key) =>
      !BusinessBoundary.initialized ||
      BusinessBoundary.keepPreference(key) ||
      BusinessBoundary.identityPreference(key) ||
      BusinessBoundary.privatePreference(key);
  String? _key(String key) => BusinessBoundary.current == null
      ? null
      : BusinessBoundary.recordKey(key, BusinessBoundary.current!);

  Future<void> archiveForeignRecords() async {
    for (final key in raw.getKeys().toList()) {
      if (!key.startsWith(BusinessBoundary.recordPrefix) && _unscoped(key))
        continue;
      final value = raw.get(key);
      final packed = BusinessBoundary.decodePreference(value);
      final owner = packed?['identity'] ?? raw.getString('_p0.tag.$key');
      if (BusinessBoundary.owns(owner)) continue;
      final businessKey = packed?['key'] as String? ?? key;
      Object? record = packed?['value'] ?? value;
      if (BusinessBoundary.financialStore(businessKey)) {
        try {
          if (record is String) record = jsonDecode(record);
        } catch (_) {}
        await BusinessBoundary.quarantine('foreign-preference', key, {
          'identity': owner,
          'value': record,
        }, count: record is List ? record.length : 1);
      }
      // No await between comparison and remove's synchronous cache mutation.
      // A concurrently replaced value is reconsidered on the next load.
      if (raw.get(key) == value) await raw.remove(key);
    }
  }

  @override
  Object? get(String key) {
    if (_unscoped(key)) return raw.get(key);
    final physical = _key(key);
    final packed = physical == null
        ? null
        : BusinessBoundary.decodePreference(raw.get(physical));
    if (packed != null && BusinessBoundary.owns(packed['identity']))
      return packed['value'];
    // Read compatibility with the first P0 candidate's two-field format.
    return BusinessBoundary.owns(raw.getString('_p0.tag.$key'))
        ? raw.get(key)
        : null;
  }

  Future<bool> _write(
    String key,
    Object value,
    Future<bool> Function() legacy,
  ) async {
    if (_unscoped(key)) return legacy();
    BusinessBoundary.assertWritable();
    final owner = BusinessBoundary.current!;
    final generation = BusinessBoundary.generation.value;
    final physical = BusinessBoundary.recordKey(key, owner);
    final saved = await raw.setString(
      physical,
      jsonEncode(BusinessBoundary.preferenceRecord(key, value, owner)),
    );
    if (BusinessBoundary.generation.value != generation) {
      if (!BusinessBoundary.owns(owner.toJson()) &&
          BusinessBoundary.financialStore(key)) {
        await BusinessBoundary.quarantine(
          'late-preference',
          physical,
          BusinessBoundary.preferenceRecord(key, value, owner),
        );
      }
      BusinessBoundary.assertGeneration(generation);
    }
    return saved;
  }

  @override
  String? getString(String key) => get(key) as String?;
  @override
  bool? getBool(String key) => get(key) as bool?;
  @override
  int? getInt(String key) => get(key) as int?;
  @override
  double? getDouble(String key) => (get(key) as num?)?.toDouble();
  @override
  List<String>? getStringList(String key) =>
      (get(key) as List?)?.cast<String>();
  @override
  bool containsKey(String key) => get(key) != null;
  @override
  Set<String> getKeys() {
    final keys = <String>{};
    for (final key in raw.getKeys()) {
      if (key.startsWith(BusinessBoundary.recordPrefix)) {
        final packed = BusinessBoundary.decodePreference(raw.get(key));
        if (packed != null && BusinessBoundary.owns(packed['identity']))
          keys.add(packed['key'] as String);
      } else if (get(key) != null) {
        keys.add(key);
      }
    }
    return keys;
  }

  @override
  Future<bool> setString(String key, String value) =>
      _write(key, value, () => raw.setString(key, value));
  @override
  Future<bool> setBool(String key, bool value) =>
      _write(key, value, () => raw.setBool(key, value));
  @override
  Future<bool> setInt(String key, int value) =>
      _write(key, value, () => raw.setInt(key, value));
  @override
  Future<bool> setDouble(String key, double value) =>
      _write(key, value, () => raw.setDouble(key, value));
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, value, () => raw.setStringList(key, value));
  @override
  Future<bool> remove(String key) async {
    if (_unscoped(key)) return raw.remove(key);
    final physical = _key(key);
    final owner = BusinessBoundary.current;
    if (physical != null && !await raw.remove(physical)) return false;
    if (owner?.matches(raw.getString('_p0.tag.$key')) == true) {
      await raw.remove(key);
      await raw.remove('_p0.tag.$key');
    }
    return true;
  }

  @override
  Future<bool> clear() async {
    for (final key in getKeys()) {
      if (!BusinessBoundary.privatePreference(key)) await remove(key);
    }
    return true;
  }

  @override
  Future<void> reload() => raw.reload();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unsupported preferences operation');
}
