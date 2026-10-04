import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/pos_api_service.dart';
import '../tenancy/business_identity.dart';

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
  });

  final int staffId;
  final String name;
  final String? uuid;
  final String? position;
  final String salt;
  final int iterations;
  final String check;

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
  };
}

/// Keeps the branch's approver verifiers in `flutter_secure_storage`
/// (Keystore-backed on Android). Replaced on each fetch; wiped on a device
/// reset or un-pairing. Stamped with the device identity, so a till moved to
/// another merchant never offers the old branch's approvers.
class ApproverStore {
  ApproverStore(this._secure);

  final FlutterSecureStorage _secure;

  static const storageKey = 'p5_approvers_v1';

  Future<List<StoredApprover>> load() async {
    String? raw;
    try {
      raw = await _secure.read(key: storageKey);
    } catch (_) {
      return const [];
    }
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      if (BusinessBoundary.initialized &&
          decoded['identity'] != BusinessBoundary.current?.encoded) {
        return const [];
      }
      return [
        for (final row in decoded['approvers'] as List? ?? const [])
          ?StoredApprover.fromJson(row),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<StoredApprover> approvers, {String? asOf}) async {
    await _secure.write(
      key: storageKey,
      value: jsonEncode({
        'identity': BusinessBoundary.current?.encoded,
        'as_of': asOf,
        'approvers': [for (final a in approvers) a.toJson()],
      }),
    );
  }

  /// Add or replace one approver (after an online approval taught the device
  /// a verifier it did not have yet).
  Future<void> remember(StoredApprover approver) async {
    final current = await load();
    await save([
      for (final a in current)
        if (a.staffId != approver.staffId) a,
      approver,
    ]);
  }

  /// Replace the stored list with the server's. A failed fetch keeps the
  /// previous list (offline approvals keep working).
  Future<int> refresh(PosApiService api) async {
    final reply = await api.fetchApprovers();
    final approvers = [
      for (final row in reply.approvers) ?StoredApprover.fromJson(row),
    ];
    await save(approvers, asOf: reply.asOf);
    return approvers.length;
  }

  Future<void> wipe() async {
    try {
      await _secure.delete(key: storageKey);
    } catch (_) {
      // Best effort: a reset that cannot reach the keystore leaves nothing
      // readable for another identity anyway (identity stamp above).
    }
  }
}
