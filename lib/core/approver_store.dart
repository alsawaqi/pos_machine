import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/pos_api_service.dart';
import '../tenancy/business_identity.dart';
import 'sentry.dart';

/// LAUNCH-P5 C2 — one approver of this device's branch, as
/// `GET /device/approvers` sends it. The device holds only the verifier
/// (`salt`, `iterations`, `check`), never the key or the PIN.
class StoredApprover {
  const StoredApprover({
    required this.staffId,
    required this.name,
    required this.salt,
    required this.iterations,
    required this.check,
    this.uuid,
    this.position,
    this.learnedAt,
  });

  final int staffId;
  final String name;
  final String? uuid;
  final String? position;
  final String salt;
  final int iterations;
  final String check;

  /// LAUNCH-P5 fix order 2b (T14) — when this till learned the verifier
  /// from an online approval (null = from the server's approver list).
  final DateTime? learnedAt;

  StoredApprover learned(DateTime at) => StoredApprover(
    staffId: staffId,
    name: name,
    uuid: uuid,
    position: position,
    salt: salt,
    iterations: iterations,
    check: check,
    learnedAt: at,
  );

  static StoredApprover? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['staff_id'] ?? raw['id'];
    final salt = raw['salt'], iterations = raw['iterations'];
    final check = raw['check'];
    if (id is! num ||
        id <= 0 ||
        salt is! String ||
        salt.isEmpty ||
        iterations is! num ||
        iterations <= 0 ||
        check is! String ||
        check.isEmpty) {
      return null;
    }
    return StoredApprover(
      staffId: id.toInt(),
      name: (raw['name'] ?? '').toString(),
      uuid: raw['uuid']?.toString(),
      position: raw['position']?.toString(),
      salt: salt,
      iterations: iterations.toInt(),
      check: check,
      learnedAt: raw['learned_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (raw['learned_at'] as num).toInt(),
              isUtc: true,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'staff_id': staffId,
    'uuid': ?uuid,
    'name': name,
    'position': ?position,
    'salt': salt,
    'iterations': iterations,
    'check': check,
    if (learnedAt != null) 'learned_at': learnedAt!.millisecondsSinceEpoch,
  };
}

/// LAUNCH-P5 fix order 2b (T14) — why the stored approver list read as it
/// did (for the breadcrumb when an offline check matches nobody).
enum ApproverListState { ok, empty, unreadable, otherIdentity }

/// Keeps the branch's approver verifiers in `flutter_secure_storage`
/// (Keystore-backed on Android). Replaced on each fetch; wiped on a device
/// reset or un-pairing. Stamped with the device identity, so a till moved to
/// another merchant never offers the old branch's approvers.
class ApproverStore {
  ApproverStore(this._secure, {DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  final FlutterSecureStorage _secure;
  final DateTime Function() _clock;

  static const storageKey = 'p5_approvers_v1';

  /// LAUNCH-P5 fix order 2b (T14) — every read-modify-write of the list
  /// runs one at a time (one secure-storage key, any store instance), so a
  /// refresh never writes over a verifier learned while it was saving.
  static Future<void> _tail = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Tests only: what the breadcrumbs would carry (never a PIN, key,
  /// salt or check).
  static void Function(String message, Map<String, dynamic> data)?
  debugBreadcrumb;

  /// A breadcrumb about the approver verifiers (never a secret).
  static void note(String message, Map<String, dynamic> data) =>
      _breadcrumb(message, data);

  static void _breadcrumb(String message, Map<String, dynamic> data) {
    debugBreadcrumb?.call(message, data);
    sentryBreadcrumb('approvers', message, data: data);
  }

  Future<List<StoredApprover>> load() async => (await loadState()).approvers;

  /// The stored list and why it reads as it does.
  Future<({List<StoredApprover> approvers, ApproverListState state})>
  loadState() async {
    const none = <StoredApprover>[];
    String? raw;
    try {
      raw = await _secure.read(key: storageKey);
    } catch (_) {
      return (approvers: none, state: ApproverListState.unreadable);
    }
    if (raw == null || raw.isEmpty) {
      return (approvers: none, state: ApproverListState.empty);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return (approvers: none, state: ApproverListState.unreadable);
      }
      if (BusinessBoundary.initialized &&
          decoded['identity'] != BusinessBoundary.current?.encoded) {
        return (approvers: none, state: ApproverListState.otherIdentity);
      }
      final approvers = [
        for (final row in decoded['approvers'] as List? ?? const [])
          ?StoredApprover.fromJson(row),
      ];
      return (
        approvers: approvers,
        state: approvers.isEmpty
            ? ApproverListState.empty
            : ApproverListState.ok,
      );
    } catch (_) {
      return (approvers: none, state: ApproverListState.unreadable);
    }
  }

  Future<void> save(List<StoredApprover> approvers, {String? asOf}) =>
      _serial(() => _write(approvers, asOf: asOf, source: 'save'));

  Future<void> _write(
    List<StoredApprover> approvers, {
    String? asOf,
    required String source,
  }) async {
    await _secure.write(
      key: storageKey,
      value: jsonEncode({
        'identity': BusinessBoundary.current?.encoded,
        'as_of': asOf,
        'approvers': [for (final a in approvers) a.toJson()],
      }),
    );
    _breadcrumb('approver verifiers saved', {
      'source': source,
      'count': approvers.length,
      'learned': approvers.where((a) => a.learnedAt != null).length,
      'as_of': asOf,
    });
  }

  Future<String?> _storedAsOf() async {
    try {
      final raw = await _secure.read(key: storageKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      return decoded is Map ? decoded['as_of']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  /// Add or replace one approver (after an online approval taught the device
  /// a verifier it did not have yet). Marked as learned now, so a refresh
  /// that was already under way keeps it.
  Future<void> remember(StoredApprover approver) => _serial(() async {
    final current = await load();
    await _write(
      [
        for (final a in current)
          if (a.staffId != approver.staffId) a,
        approver.learned(_clock()),
      ],
      asOf: await _storedAsOf(),
      source: 'learned',
    );
  });

  /// Take the server's list. A failed fetch keeps the previous list (offline
  /// approvals keep working).
  ///
  /// LAUNCH-P5 fix order 2b (T14) — merged by `staff_id`, never blindly
  /// replaced: a verifier this till learned from an online approval is kept
  /// when the server's reply predates that approval (learned after this
  /// refresh started), or when the server still lists the person but sends
  /// no verifier for them. A person the server no longer lists is dropped
  /// (unless learned after the reply was asked for).
  Future<int> refresh(PosApiService api) async {
    final started = _clock();
    final reply = await api.fetchApprovers();
    final listed = <int>{};
    final fromServer = <int, StoredApprover>{};
    for (final row in reply.approvers) {
      final id = row['staff_id'] ?? row['id'];
      if (id is num && id > 0) listed.add(id.toInt());
      final approver = StoredApprover.fromJson(row);
      if (approver != null) fromServer[approver.staffId] = approver;
    }
    return _serial(() async {
      final current = await load();
      bool learnedSince(StoredApprover a) =>
          a.learnedAt != null && !a.learnedAt!.isBefore(started);
      final merged = <StoredApprover>[];
      final kept = <int>{};
      for (final server in fromServer.values) {
        final local = current
            .where((a) => a.staffId == server.staffId)
            .firstOrNull;
        merged.add(local != null && learnedSince(local) ? local : server);
        kept.add(server.staffId);
      }
      for (final local in current) {
        if (kept.contains(local.staffId) || local.learnedAt == null) continue;
        if (learnedSince(local) || listed.contains(local.staffId)) {
          merged.add(local);
          kept.add(local.staffId);
        }
      }
      await _write(merged, asOf: reply.asOf, source: 'refresh');
      return merged.length;
    });
  }

  /// Breadcrumb for an offline check that matched nobody (no secrets: a
  /// reason, the stored count and the list's as_of). [online]: the server
  /// then verified the PIN (true) or could not be asked (false).
  Future<void> reportNoMatch({required bool online}) async {
    final read = await loadState();
    _breadcrumb('approver PIN matched no stored verifier', {
      'reason': read.state == ApproverListState.ok
          ? 'no_match'
          : read.state.name,
      'count': read.approvers.length,
      'learned': read.approvers.where((a) => a.learnedAt != null).length,
      'as_of': await _storedAsOf(),
      'verified_online': online,
    });
  }

  Future<void> wipe() => _serial(() async {
    try {
      await _secure.delete(key: storageKey);
    } catch (_) {
      // Best effort: a reset that cannot reach the keystore leaves nothing
      // readable for another identity anyway (identity stamp above).
    }
  });
}
