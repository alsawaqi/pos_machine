import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/row_parsing.dart';
import '../tablet_orders/tablet_order_models.dart';

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
  AttentionSnapshot(this.quick, this.rounds, [this.tablet = const {}]);
  final Set<String> quick;
  final Set<String> rounds;

  /// LAUNCH-P6 — `tablet:<uuid>` keys (Quick / To go unpaid orders and
  /// dine-in pending rounds), sent only to a `tablet-orders` build, until
  /// a staff member takes the order on any device.
  final Set<String> tablet;
  Set<String> get keys => {...quick, ...rounds, ...tablet};

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

    // LAUNCH-P6 — the tablet list is new: a bad or unknown key in it is
    // skipped and logged, and an absent list (older server) is empty, so
    // tablet data can never stop the QR alerts.
    Set<String> readTablet() {
      final value = data['tablet_order_keys'];
      if (value == null) return const {};
      return parseRowsSkippingBad<String>(
        value is List
            ? [
                for (final key in value) {'key': key},
              ]
            : value,
        (row) {
          final key = row['key'];
          if (key is! String ||
              !key.startsWith(tabletAttentionPrefix) ||
              key.length <= tabletAttentionPrefix.length) {
            throw const FormatException('Invalid tablet attention key');
          }
          return key;
        },
        list: 'order-attention/tablet',
      ).toSet();
    }

    if (data['version'] != 1) {
      throw const FormatException('Unsupported attention snapshot');
    }
    return AttentionSnapshot(
      read('quick_order_keys', 'quick:'),
      read('table_round_keys', 'round:'),
      readTablet(),
    );
  }
}

const tabletAttentionPrefix = 'tablet:';

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
              !(key.startsWith('quick:') ||
                  key.startsWith('round:') ||
                  key.startsWith(tabletAttentionPrefix)),
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
    this.fetchTablet,
    this.repeatEvery = const Duration(seconds: 10),
  });

  final AttentionIdentity? Function() identity;
  final Future<Map<String, dynamic>> Function() fetch;
  final AttentionLedger ledger;
  final Future<bool> Function() play;
  final Future<void> Function() stop;

  /// LAUNCH-P6 — reads the tablet orders (for the banner's "Table 5" /
  /// "#27"). Null: no labels, the banner still shows.
  final Future<List<TabletOrderRow>> Function()? fetchTablet;

  /// LAUNCH-P6 item 3 — a tablet order rings again this often until it is
  /// opened here or taken on any device (its key leaves the snapshot).
  final Duration repeatEvery;

  /// The tablet orders known from the last read (for labels).
  List<TabletOrderRow> tabletRows = const [];

  /// Tablet keys opened on this device: they stop ringing here.
  final Set<String> _opened = {};
  Timer? _repeat;

  /// Tablet keys still ringing: in the snapshot, not opened here.
  Set<String> get ringing =>
      (snapshot?.tablet ?? const <String>{}).difference(_opened);

  /// Staff opened this tablet order: it stops ringing on this device.
  void opened(String key) {
    if (!_opened.add(key)) return;
    _updateRing();
    _notify();
  }

  void _updateRing() {
    final ring = active && !_disposed && ringing.isNotEmpty;
    if (ring && _repeat == null) {
      _repeat = Timer.periodic(repeatEvery, (_) {
        if (_disposed || !active || ringing.isEmpty) {
          _updateRing();
          return;
        }
        unawaited(
          play().then((requested) {
            if (!_disposed) soundUnavailable = !requested;
          }),
        );
      });
    } else if (!ring && _repeat != null) {
      _repeat!.cancel();
      _repeat = null;
      unawaited(stop());
    }
  }

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
      tabletRows = const [];
      _opened.clear();
      _updateRing();
      _notify();
    }
    unawaited(refresh());
  }

  void setActive(bool value) {
    if (active == value) return;
    active = value;
    _epoch++;
    _updateRing();
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
      tabletRows = const [];
      _opened.clear();
      _updateRing();
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
      // Forget opened keys that left (taken, sent, paid or cancelled).
      _opened.retainAll(next.tablet);
      _updateRing();
      // Read the tablet list only for a ringing order without a label yet.
      final unlabelled = ringing.any(
        (key) => !tabletRows.any((row) => row.attentionKey == key),
      );
      if (unlabelled && fetchTablet != null) {
        try {
          final rows = await fetchTablet!();
          if (!_current(captured, epoch)) return;
          tabletRows = rows;
        } catch (_) {
          // Labels only: the banner shows without them.
        }
      } else if (next.tablet.isEmpty) {
        tabletRows = const [];
      }
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
    _repeat?.cancel();
    _repeat = null;
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

/// LAUNCH-P6 — the mounted staff POS registers how to open the tablet
/// orders (optionally at one order, by its attention key). The banner and
/// the bell use it; null hides their Open action.
final tabletOrdersOpener = ValueNotifier<void Function(String? key)?>(null);
