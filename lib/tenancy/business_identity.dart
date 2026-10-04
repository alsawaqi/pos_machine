import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class BusinessIdentity {
  const BusinessIdentity(this.companyId, this.branchId, this.deviceUuid);
  final int companyId;
  final int branchId;
  final String deviceUuid;
  bool get isProvisional => deviceUuid.isEmpty;
  Map<String, dynamic> toJson() => {
    'company_id': companyId,
    'branch_id': branchId,
    'device_uuid': deviceUuid,
  };
  String get encoded => jsonEncode(toJson());
  static BusinessIdentity? parse(Object? value) {
    try {
      final map = value is String ? jsonDecode(value) : value;
      if (map is! Map ||
          map['company_id'] is! num ||
          map['branch_id'] is! num ||
          (map['company_id'] as num) <= 0 ||
          (map['branch_id'] as num) <= 0 ||
          (map['device_uuid'] != null && map['device_uuid'] is! String))
        return null;
      return BusinessIdentity(
        (map['company_id'] as num).toInt(),
        (map['branch_id'] as num).toInt(),
        (map['device_uuid'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  bool matches(Object? value) {
    final other = parse(value);
    return other != null &&
        companyId == other.companyId &&
        branchId == other.branchId &&
        (isProvisional ||
            other.isProvisional ||
            deviceUuid == other.deviceUuid);
  }
}

/// The durable activation boundary, independent of staff login. A refusal never
/// clears business data. Only a successful activation can commit another owner.
class BusinessBoundary {
  static const identityKey = '_p0.business_identity';
  static const recordPrefix = '_p0.record.';
  static const legacyKey = '_p0.legacy_identity';
  static const legacyPreferencesKey = '_p0.legacy_preferences';
  // Keep local row ownership stable when the server fills the missing UUID.
  // Wire identity is independent: old events are never relabelled.
  static BusinessIdentity? get storageIdentity {
    final legacy = BusinessIdentity.parse(_prefs?.getString(legacyKey));
    return current?.matches(legacy?.toJson()) == true ? legacy : current;
  }

  static Map<String, dynamic>? get legacyPreferences {
    final value = _prefs?.getString(legacyPreferencesKey);
    if (value == null) return null;
    final record = jsonDecode(value) as Map<String, dynamic>;
    return owns(record['identity']) ? record : null;
  }

  static Object? legacyPreference(String key) =>
      (legacyPreferences?['values'] as Map?)?[key];
  static Future<void> removeLegacyPreference(String key) async {
    final record = legacyPreferences;
    if (record == null) return;
    final values = Map<String, dynamic>.from(record['values'] as Map)
      ..remove(key);
    if (!await _prefs!.setString(
      legacyPreferencesKey,
      jsonEncode({...record, 'values': values}),
    ))
      throw StateError('Legacy preference removal failed.');
  }

  static String recordKey(String key, BusinessIdentity owner) =>
      recordPrefix +
      base64Url.encode(
        utf8.encode(
          current?.matches(owner.toJson()) == true
              ? storageIdentity!.encoded
              : owner.encoded,
        ),
      ) +
      '.' +
      base64Url.encode(utf8.encode(key));
  static bool get adoptingLegacy =>
      current != null && current!.matches(_prefs?.getString(legacyKey));
  static Map<String, dynamic> preferenceRecord(
    String key,
    Object value,
    BusinessIdentity owner,
  ) => {'key': key, 'identity': owner.toJson(), 'value': value};
  static Map<String, dynamic>? decodePreference(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is Map &&
              decoded.containsKey('key') &&
              decoded.containsKey('identity') &&
              decoded.containsKey('value')
          ? decoded.cast<String, dynamic>()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Called by the real session loader after reading the secure legacy token.
  /// A server refusal remains durable; adoption never clears that refusal.
  static Future<bool> adoptLegacy(String? token) async {
    final prefs = _prefs;
    if (prefs == null ||
        current != null ||
        (token ?? '').trim().isEmpty ||
        prefs.containsKey(transitionKey))
      return false;
    final company = prefs.getInt('company_id'),
        branch = prefs.getInt('branch_id');
    if (company == null || company <= 0 || branch == null || branch <= 0)
      return false;
    final owner = BusinessIdentity(
      company,
      branch,
      prefs.getString('device_uuid') ?? '',
    );
    // One atomic preference value is both the snapshot and the crash marker.
    // Never remove an original key before this complete snapshot is durable.
    if (!prefs.containsKey(legacyPreferencesKey)) {
      final values = <String, Object>{};
      for (final key in prefs.getKeys()) {
        if (!privatePreference(key) &&
            !keepPreference(key) &&
            !identityPreference(key)) {
          final value = prefs.get(key);
          if (value != null) values[key] = value;
        }
      }
      if (!await prefs.setString(
        legacyPreferencesKey,
        jsonEncode({'identity': owner.toJson(), 'values': values}),
      ))
        throw StateError('Legacy snapshot could not be saved.');
    }
    if (!await prefs.setString(legacyKey, owner.encoded) ||
        !await prefs.setString(identityKey, owner.encoded))
      throw StateError('Legacy identity could not be saved.');
    current = owner;
    blocked.value = prefs.getString(blockedKey);
    final values = legacyPreferences?['values'] as Map? ?? {};
    for (final key in values.keys.cast<String>()) {
      await prefs.remove(key);
      await prefs.remove('_p0.tag.' + key);
    }
    return true;
  }

  static Future<void> completeIdentity(
    BusinessIdentity next,
    int expectedGeneration,
  ) async {
    if (generation.value != expectedGeneration ||
        current == null ||
        !current!.isProvisional ||
        next.isProvisional)
      return;
    if (!current!.matches(next.toJson())) {
      block('device_reactivation_required');
      return;
    }
    // A single durable identity commit. Store keys/owners remain stable.
    if (!await _prefs!.setString(identityKey, next.encoded))
      throw StateError('Device identity could not be completed.');
    current = next;
    await _prefs!.setString('device_uuid', next.deviceUuid);
  }

  static const blockedKey = '_p0.blocked';
  static const transitionKey = '_p0.transition';
  static SharedPreferences? _prefs;
  static BusinessIdentity? current;
  static final blocked = ValueNotifier<String?>(null);
  static final generation = ValueNotifier<int>(0);
  static final activationCompleted = ValueNotifier<int>(0);
  static final List<Future<void> Function()> _wipers = [];
  static final List<Future<void> Function()> _activators = [];
  static void registerActivator(Future<void> Function() action) {
    if (!_activators.contains(action)) _activators.add(action);
  }

  static void unregisterActivator(Future<void> Function() action) =>
      _activators.remove(action);
  static bool get initialized => _prefs != null;
  static bool get canWork =>
      !initialized || (current != null && blocked.value == null);
  static int get quarantinedCount =>
      _prefs
          ?.getKeys()
          .where((key) => key.startsWith('_p0.quarantine.'))
          .fold<int>(0, (sum, key) {
            final raw = _prefs!.getString(key);
            try {
              return sum + ((jsonDecode(raw!) as Map)['count'] as num).toInt();
            } catch (_) {
              return sum + 1;
            }
          }) ??
      0;

  static Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    current = BusinessIdentity.parse(prefs.getString(identityKey));
    blocked.value = prefs.containsKey(transitionKey)
        ? 'device_reactivation_required'
        : (prefs.getString(blockedKey) ??
              (current == null ? 'device_reactivation_required' : null));
  }

  static void registerWiper(Future<void> Function() wipe) {
    if (!_wipers.contains(wipe)) _wipers.add(wipe);
  }

  static void unregisterWiper(Future<void> Function() wipe) =>
      _wipers.remove(wipe);

  static void observeError(int? status, String? code) {
    final reason = switch ((status, code)) {
      (401, 'device_reactivation_required') => 'device_reactivation_required',
      (403 || 503, 'company_suspended') => 'company_suspended',
      (409, 'device_unassigned') => 'device_reactivation_required',
      _ => null,
    };
    if (reason != null) block(reason);
  }

  static void block(String reason) {
    blocked.value = reason;
    unawaited(_prefs?.setString(blockedKey, reason));
  }

  static Future<void> confirmHeartbeat(int expectedGeneration) async {
    if (generation.value != expectedGeneration ||
        blocked.value != 'company_suspended')
      return;
    await _prefs?.remove(blockedKey);
    blocked.value = null;
  }

  static int _payments = 0;
  static Completer<void>? _paymentsDone;
  static Future<void> get paymentsSettled =>
      _paymentsDone?.future ?? Future.value();

  /// LAUNCH-P5 fix order 2 (T13) — a tracked tender is under way.
  static bool get paymentInFlight => _payments > 0;
  static Future<T> trackPayment<T>(Future<T> Function() action) async {
    if (_payments++ == 0) _paymentsDone = Completer<void>();
    try {
      return await action();
    } finally {
      if (--_payments == 0) {
        _paymentsDone?.complete();
        _paymentsDone = null;
      }
    }
  }

  // Only the captured sale's original owner may bypass suspension for its
  // durable completion. This capability is never used to authorize a tender.
  static bool get _savingPaid =>
      Zone.current['p0.paid'] == true && owns(Zone.current['p0.paidOwner']);
  static Future<T> persistPaid<T>(
    Object? owner,
    Future<T> Function() save,
  ) async {
    if (!owns(owner))
      throw StateError('The paid sale belongs to another identity.');
    return runZoned(save, zoneValues: {'p0.paid': true, 'p0.paidOwner': owner});
  }

  static void assertWritable() {
    if (!canWork &&
        !_savingPaid &&
        !(Zone.current['p0.activation'] == true && current != null))
      throw StateError(
        'Business access is blocked: ' +
            (blocked.value ?? 'activation required'),
      );
  }

  static void assertGeneration(int expected) {
    if (generation.value != expected && !_savingPaid)
      throw StateError('The device identity changed during this operation.');
  }

  static Map<String, dynamic> stamp(Map<String, dynamic> record) {
    if (!initialized) return record;
    assertWritable();
    return {...record, 'identity': record['identity'] ?? current!.toJson()};
  }

  static Map<String, dynamic> stampEvent(Map<String, dynamic> event) {
    if (initialized && current?.isProvisional == true) {
      assertWritable();
      return event;
    }
    return stamp(event);
  }

  static bool ownsEvent(Object? identity) =>
      (identity == null && adoptingLegacy) || owns(identity);

  static bool owns(Object? identity) =>
      !initialized || (current?.matches(identity) ?? false);

  static Future<void> quarantine(
    String source,
    String key,
    Object? record, {
    int count = 1,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final id = base64Url.encode(utf8.encode('$source|$key'));
    final saved = await prefs.setString(
      '_p0.quarantine.$id',
      jsonEncode({
        'source': source,
        'key': key,
        'count': count,
        'quarantined_at': DateTime.now().toUtc().toIso8601String(),
        'record': record,
      }),
    );
    if (!saved) throw StateError('Financial quarantine could not be saved.');
  }

  static bool keepPreference(String key) => const {
    'server_base_url',
    'print_receipts',
    'print_kitchen_tickets',
    'print_qr_kitchen_rounds',
    'app_language',
    'language',
    'printer_address',
    'printer_name',
    'printer_mac',
    'kitchen_printer_address',
    'kitchen_printer_name',
    'kitchen_printer_mac',
  }.contains(key);
  static bool identityPreference(String key) => const {
    'device_uuid',
    'kiosk_id',
    'company_id',
    'branch_id',
    'device_name',
  }.contains(key);
  static bool privatePreference(String key) => key.startsWith('_p0.');
  static bool financialStore(String key) => RegExp(
    r'outbox|combine|recovery|journal|reversal|pending.*charge|local_table_events|checkout.*attempt',
  ).hasMatch(key);

  static Future<bool> accept(
    BusinessIdentity next, {
    Future<void> Function()? install,
  }) async {
    await paymentsSettled;
    final prefs = _prefs;
    if (prefs == null) {
      current = next;
      await install?.call();
      return false;
    }
    final changed = !(current?.matches(next.toJson()) ?? false);
    await prefs.setString(blockedKey, 'device_reactivation_required');
    blocked.value = 'device_reactivation_required';
    generation.value++;
    if (changed) {
      // Retryable crash marker. A partially completed wipe cannot open sales.
      await prefs.setString(transitionKey, next.encoded);
      blocked.value = 'device_reactivation_required';
      for (final wipe in List<Future<void> Function()>.of(_wipers)) {
        await wipe();
      }
      for (final key in prefs.getKeys().toList()) {
        if ((privatePreference(key) && !key.startsWith(recordPrefix)) ||
            keepPreference(key))
          continue;
        final value = prefs.get(key);
        final packed = decodePreference(value);
        final businessKey = packed?['key'] as String? ?? key;
        if (financialStore(businessKey)) {
          Object? record = packed?['value'] ?? value;
          try {
            if (record is String) record = jsonDecode(record);
          } catch (_) {}
          await quarantine('preferences', key, {
            'identity': packed?['identity'] ?? prefs.getString('_p0.tag.$key'),
            'value': record,
          }, count: record is List ? record.length : 1);
        }
        await prefs.remove(key);
        await prefs.remove('_p0.tag.$key');
      }
      final legacy = legacyPreferences;
      if (legacy != null) {
        for (final item in (legacy['values'] as Map).entries) {
          if (financialStore(item.key as String)) {
            await quarantine('legacy-preferences', item.key as String, {
              'identity': legacy['identity'],
              'value': item.value,
            });
          }
        }
      }
      await prefs.remove(legacyPreferencesKey);
      await prefs.remove(legacyKey);
      await prefs.setString(identityKey, next.encoded);
      current = next;
    }
    if (!changed && current?.isProvisional == true && !next.isProvisional) {
      await completeIdentity(next, generation.value);
    }
    if (install != null) {
      await runZoned(install, zoneValues: {'p0.activation': true});
    }
    for (final activate in List<Future<void> Function()>.of(_activators)) {
      await activate();
    }
    await prefs.remove(transitionKey);
    await prefs.remove(blockedKey);
    activationCompleted.value++;
    blocked.value = null;
    return changed;
  }

  @visibleForTesting
  static void resetForTest() {
    _payments = 0;
    _paymentsDone = null;
    _prefs = null;
    current = null;
    _wipers.clear();
    _activators.clear();
    blocked.value = null;
    generation.value = 0;
    activationCompleted.value = 0;
  }
}
