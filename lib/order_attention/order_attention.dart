import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A device/server ledger survives staff logout; credentials never enter storage.
class AttentionIdentity {
  const AttentionIdentity(this.scope, this.authorization);
  final String scope;
  final String authorization;

  @override
  bool operator ==(Object other) =>
      other is AttentionIdentity &&
      scope == other.scope &&
      authorization == other.authorization;
  @override
  int get hashCode => Object.hash(scope, authorization);
}

class AttentionSnapshot {
  AttentionSnapshot(this.quick, this.rounds);
  final Set<String> quick;
  final Set<String> rounds;
  Set<String> get keys => {...quick, ...rounds};

  factory AttentionSnapshot.parse(Map<String, dynamic> data) {
    Set<String> read(String field, String prefix) {
      final value = data[field];
      if (value is! List ||
          value.any(
            (key) =>
                key is! String ||
                !key.startsWith(prefix) ||
                key.length <= prefix.length,
          )) {
        throw const FormatException('Invalid attention snapshot');
      }
      final keys = value.cast<String>().toSet();
      if (keys.length != value.length) {
        throw const FormatException('Duplicate attention identities');
      }
      return keys;
    }

    if (data['version'] != 1) {
      throw const FormatException('Unsupported attention snapshot');
    }
    return AttentionSnapshot(
      read('quick_order_keys', 'quick:'),
      read('table_round_keys', 'round:'),
    );
  }
}

abstract interface class AttentionLedger {
  /// Null means first use: baseline silently. Never treat corruption as first use.
  Future<Set<String>?> read(String scope);
  Future<void> write(String scope, Set<String> keys);
}

class PreferencesAttentionLedger implements AttentionLedger {
  String _key(String scope) =>
      'order_attention_v1_${sha256.convert(utf8.encode(scope))}';

  @override
  Future<Set<String>?> read(String scope) async {
    final prefs = await businessPreferences();
    await prefs.reload();
    final raw = prefs.getString(_key(scope));
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map || value['version'] != 1 || value['keys'] is! List) {
      throw const FormatException('Invalid attention ledger');
    }
    final keys = value['keys'] as List;
    if (keys.any(
          (key) =>
              key is! String ||
              !(key.startsWith('quick:') || key.startsWith('round:')),
        ) ||
        keys.toSet().length != keys.length) {
      throw const FormatException('Invalid attention ledger keys');
    }
    return keys.cast<String>().toSet();
  }

  @override
  Future<void> write(String scope, Set<String> keys) async {
    final prefs = await businessPreferences();
    final saved = await prefs.setString(
      _key(scope),
      jsonEncode({'version': 1, 'keys': keys.toList()..sort()}),
    );
    if (!saved) throw StateError('Attention ledger could not be saved');
  }
}

class OrderAttentionSound {
  static const channel = MethodChannel('mithqal/order_attention');
  static Future<bool> play() async {
    try {
      return await channel.invokeMethod<bool>('play') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {
      // An absent native bridge must never interrupt an order/payment.
    }
  }
}

/// One serial foreground consumer. Failure never modifies an order or outbox.
class OrderAttentionController extends ChangeNotifier {
  OrderAttentionController({
    required this.identity,
    required this.fetch,
    required this.ledger,
    this.play = OrderAttentionSound.play,
    this.stop = OrderAttentionSound.stop,
  });

  final AttentionIdentity? Function() identity;
  final Future<Map<String, dynamic>> Function() fetch;
  final AttentionLedger ledger;
  final Future<bool> Function() play;
  final Future<void> Function() stop;
  // Serialises ledger consumption even during overlapping root replacement.
  static Future<void>? _ledgerTail;
  static const maxRememberedArrivals = 50000;
  AttentionSnapshot? snapshot;
  AttentionIdentity? _identity;
  bool stale = false;
  bool storageFailed = false;
  bool soundUnavailable = false;
  bool active = true;
  bool _busy = false;
  bool _disposed = false;
  int _epoch = 0;
  int newArrivals = 0;

  bool _current(AttentionIdentity captured, int epoch) =>
      !_disposed && active && _epoch == epoch && identity() == captured;

  void contextChanged() {
    _epoch++;
    if (identity() != _identity) {
      _identity = null;
      snapshot = null;
      newArrivals = 0;
      stale = storageFailed = soundUnavailable = false;
      _notify();
    }
    unawaited(refresh());
  }

  void setActive(bool value) {
    if (active == value) return;
    active = value;
    _epoch++;
    if (!value) {
      unawaited(stop());
    } else {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (_disposed || !active || _busy) return;
    final captured = identity();
    if (captured == null) {
      if (_identity != null || snapshot != null || stale) contextChanged();
      return;
    }
    if (_identity != captured) {
      _identity = captured;
      snapshot = null;
      newArrivals = 0;
      stale = storageFailed = soundUnavailable = false;
      _notify();
    }
    final epoch = _epoch;
    _busy = true;
    try {
      final next = AttentionSnapshot.parse(await fetch());
      if (!_current(captured, epoch)) return;
      snapshot = next;
      stale = false;
      newArrivals = 0;
      // Reserve this consumer's place before awaiting any storage operation.
      final previous = _ledgerTail;
      final finished = Completer<void>();
      _ledgerTail = finished.future;
      try {
        if (previous != null) await previous;
        if (!_current(captured, epoch)) return;
        final seen = await ledger.read(captured.scope);
        if (!_current(captured, epoch)) return;
        final added = next.keys.difference(seen ?? {});
        final combined = {...?seen, ...next.keys};
        if (combined.length > maxRememberedArrivals) {
          throw StateError('Attention ledger capacity reached');
        }
        if (seen == null || added.isNotEmpty) {
          await ledger.write(captured.scope, combined);
        }
        if (!_current(captured, epoch)) return;
        storageFailed = false;
        if (seen != null && added.isNotEmpty) {
          newArrivals = added.length;
          _notify(); // Visible even when audio is muted, absent or fails.
          final requested = await play();
          if (_current(captured, epoch)) soundUnavailable = !requested;
        }
      } catch (_) {
        if (_current(captured, epoch)) storageFailed = true;
      } finally {
        if (identical(_ledgerTail, finished.future)) _ledgerTail = null;
        finished.complete();
      }
    } catch (_) {
      if (_current(captured, epoch)) stale = true;
    } finally {
      _busy = false;
      if (!_disposed) {
        if (identity() != _identity) {
          contextChanged();
        } else {
          _notify();
        }
      }
    }
  }

  Future<void> testSound() async {
    if (_disposed || !active || identity() == null) return;
    final requested = await play();
    if (!_disposed) {
      soundUnavailable = !requested;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    unawaited(stop());
    super.dispose();
  }
}

/// Only an actually mounted staff POS surface enables the app-wide listener.
/// A cached staff profile on the cold-start PIN screen is not sufficient.
final staffAttentionHosts = ValueNotifier<Set<Object>>({});
Object enterStaffAttention() {
  final lease = Object();
  staffAttentionHosts.value = {...staffAttentionHosts.value, lease};
  return lease;
}

void leaveStaffAttention(Object lease) {
  staffAttentionHosts.value = {...staffAttentionHosts.value}..remove(lease);
}
