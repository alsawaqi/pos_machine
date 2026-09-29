import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'business_identity.dart';

Future<SharedPreferences> businessPreferences() {
  if (!BusinessBoundary.initialized) return SharedPreferences.getInstance();
  return _loadBusinessPreferences();
}

Future<SharedPreferences> _loadBusinessPreferences() async {
  final raw = await SharedPreferences.getInstance();
  if (BusinessBoundary.initialized && BusinessBoundary.canWork) {
    for (final key in raw.getKeys().toList()) {
      if (BusinessBoundary.privatePreference(key) ||
          BusinessBoundary.keepPreference(key) ||
          BusinessBoundary.identityPreference(key) ||
          BusinessBoundary.owns(raw.getString('_p0.tag.$key')))
        continue;
      final value = raw.get(key);
      if (BusinessBoundary.financialStore(key)) {
        Object? record = value;
        try {
          if (value is String) record = jsonDecode(value);
        } catch (_) {}
        await BusinessBoundary.quarantine('foreign-preference', key, {
          'identity': raw.getString('_p0.tag.$key'),
          'value': record,
        }, count: record is List ? record.length : 1);
      }
      await raw.remove(key);
      await raw.remove('_p0.tag.$key');
    }
  }
  return TenantPreferences(raw);
}

/// Every business preference has an adjacent identity stamp. Device settings
/// and the activation identity are the only unscoped values.
class TenantPreferences implements SharedPreferences {
  TenantPreferences(this.raw);
  final SharedPreferences raw;
  bool _unscoped(String key) =>
      BusinessBoundary.keepPreference(key) ||
      BusinessBoundary.identityPreference(key) ||
      BusinessBoundary.privatePreference(key);
  bool _readable(String key) =>
      !BusinessBoundary.initialized ||
      _unscoped(key) ||
      BusinessBoundary.owns(raw.getString('_p0.tag.$key'));
  Future<bool> _write(String key, Future<bool> Function() action) async {
    if (BusinessBoundary.initialized && !_unscoped(key)) {
      BusinessBoundary.assertWritable();
      final identity = BusinessBoundary.current!.encoded;
      final generation = BusinessBoundary.generation.value;
      // Remove the previous stamp before replacing its value. A crash between
      // writes cannot relabel an old value as belonging to another merchant.
      await raw.remove('_p0.tag.$key');
      // Activation or suspension may finish while the stamp removal awaits I/O.
      // Never overwrite a new owner's value beneath its newly installed stamp.
      BusinessBoundary.assertGeneration(generation);
      BusinessBoundary.assertWritable();
      if (!await action()) return false;
      BusinessBoundary.assertGeneration(generation);
      return raw.setString('_p0.tag.$key', identity);
    }
    return action();
  }

  @override
  Object? get(String key) => _readable(key) ? raw.get(key) : null;
  @override
  String? getString(String key) => get(key) as String?;
  @override
  bool? getBool(String key) => get(key) as bool?;
  @override
  int? getInt(String key) => get(key) as int?;
  @override
  double? getDouble(String key) => get(key) as double?;
  @override
  List<String>? getStringList(String key) =>
      (get(key) as List?)?.cast<String>();
  @override
  bool containsKey(String key) => _readable(key) && raw.containsKey(key);
  @override
  Set<String> getKeys() => raw.getKeys().where(_readable).toSet();
  @override
  Future<bool> setString(String key, String value) =>
      _write(key, () => raw.setString(key, value));
  @override
  Future<bool> setBool(String key, bool value) =>
      _write(key, () => raw.setBool(key, value));
  @override
  Future<bool> setInt(String key, int value) =>
      _write(key, () => raw.setInt(key, value));
  @override
  Future<bool> setDouble(String key, double value) =>
      _write(key, () => raw.setDouble(key, value));
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, () => raw.setStringList(key, value));
  @override
  Future<bool> remove(String key) async {
    await raw.remove('_p0.tag.$key');
    return raw.remove(key);
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
