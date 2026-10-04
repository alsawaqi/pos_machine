import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/pos_api_service.dart';
import '../tenancy/business_identity.dart';
import 'approval_proof.dart';
import 'authorization.dart';
import 'approver_store.dart';
import 'permissions.dart';
import 'pin_lockout.dart';

export 'authorization.dart';

/// LAUNCH-P5 C2 — THE approval gate of the till (PHASE-1A D-8: extracted
/// from staff_pos_screen.dart so the login screen and every other screen can
/// reach it).
///
/// The approver types their PIN on this device:
///  1. it is checked locally against the branch's stored approvers
///     (PBKDF2 with each approver's salt until a `check` matches) — this
///     works offline;
///  2. no local match and the till is online → `verify-manager-pin`, whose
///     reply carries the approver's verifier so the device can still sign;
///  3. the result is `{approver_staff_id, name, approved_at, method, proof}`
///     ([ApprovalGrant] + [ActionAuthorization.block]).
///
/// Five wrong PINs lock the sheet for 60 s, doubling, capped at 15 minutes,
/// across restarts ([PinLockout]). The old "manager fingerprint" is gone
/// (LAUNCH-P5 H2): approval is a PIN with an identity, nothing else.

/// Finds the approver whose verifier matches [pin]; returns their index
/// and key, or null.
typedef ApproverMatcher =
    Future<({int index, Uint8List key})?> Function(
      String pin,
      List<StoredApprover> approvers,
    );

({int index, Uint8List key})? matchApproverSync(
  String pin,
  List<({String salt, int iterations, String check})> verifiers,
) {
  for (var i = 0; i < verifiers.length; i++) {
    final v = verifiers[i];
    final Uint8List key;
    try {
      key = approverKey(pin, v.salt, v.iterations);
    } catch (_) {
      continue;
    }
    if (sameHex(approverCheck(key), v.check)) return (index: i, key: key);
    key.fillRange(0, key.length, 0);
  }
  return null;
}

/// Runs the PBKDF2 work off the UI isolate, split over up to four
/// isolates (one PBKDF2 per approver; the T3 has several cores).
Future<({int index, Uint8List key})?> matchApproverInIsolate(
  String pin,
  List<StoredApprover> approvers,
) async {
  final verifiers = [
    for (final a in approvers)
      (salt: a.salt, iterations: a.iterations, check: a.check),
  ];
  if (verifiers.isEmpty) return null;
  final lanes = verifiers.length < 4 ? verifiers.length : 4;
  final results = await Future.wait([
    for (var lane = 0; lane < lanes; lane++)
      Isolate.run(() {
        final mine = [
          for (var i = lane; i < verifiers.length; i += lanes) verifiers[i],
        ];
        final hit = matchApproverSync(pin, mine);
        return hit == null
            ? null
            : (index: lane + hit.index * lanes, key: hit.key);
      }),
  ]);
  for (final hit in results) {
    if (hit != null) return hit;
  }
  return null;
}

sealed class ApprovalAttempt {
  const ApprovalAttempt();
}

class ApprovalApproved extends ApprovalAttempt {
  const ApprovalApproved(this.grant);
  final ApprovalGrant grant;
}

/// The PIN matched nobody. [offline]: the server could not be asked, so an
/// approver whose verifier is not on this till yet cannot approve now.
class ApprovalWrongPin extends ApprovalAttempt {
  const ApprovalWrongPin({this.offline = false, this.lockedUntil});
  final bool offline;
  final DateTime? lockedUntil;
}

class ApprovalLocked extends ApprovalAttempt {
  const ApprovalLocked(this.until);
  final DateTime until;
}

class ApprovalUnavailable extends ApprovalAttempt {
  const ApprovalUnavailable([this.message]);
  final String? message;
}

/// The non-UI half of the sheet (unit-testable).
class ApprovalEngine {
  ApprovalEngine({
    required this.api,
    required this.store,
    required this.lockout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PosApiService api;
  final ApproverStore store;
  final PinLockout lockout;
  final DateTime Function() _clock;

  /// Tests replace this with a synchronous matcher.
  static ApproverMatcher matcher = matchApproverInIsolate;

  Future<void> _reportNoMatch({required bool online}) async {
    try {
      await store.reportNoMatch(online: online);
    } catch (_) {
      // A breadcrumb never blocks an approval.
    }
  }

  Future<ApprovalAttempt> verify(String pin) async {
    final locked = lockout.lockedUntil;
    if (locked != null) return ApprovalLocked(locked);

    final approvers = await store.load();
    if (approvers.isNotEmpty) {
      final match = await matcher(pin, approvers);
      if (match != null) {
        final approver = approvers[match.index];
        await lockout.clear();
        return ApprovalApproved(
          ApprovalGrant(
            approverStaffId: approver.staffId,
            name: approver.name,
            position: approver.position,
            approvedAt: _clock(),
            method: 'offline',
            key: match.key,
          ),
        );
      }
    }

    ApproverVerification? online;
    try {
      online = await api.verifyApprover(pin);
    } on ApiException catch (e) {
      if (e.isPinLock) {
        return ApprovalLocked(
          await lockout.lockFor(e.lockDuration ?? PinLockout.baseLock),
        );
      }
      if (e.isNetwork) {
        // LAUNCH-P5 fix order 2b (T14) — the offline check found no match
        // and the server cannot be asked: say why in the breadcrumb.
        await _reportNoMatch(online: false);
        return ApprovalWrongPin(
          offline: true,
          lockedUntil: await lockout.recordFailure(),
        );
      }
      return ApprovalUnavailable(e.message);
    } catch (_) {
      return const ApprovalUnavailable();
    }
    if (online == null) {
      return ApprovalWrongPin(lockedUntil: await lockout.recordFailure());
    }

    // LAUNCH-P5 fix order 2b (T14) — a real approver this till could not
    // check offline: why (it is learned below for next time).
    await _reportNoMatch(online: true);
    Uint8List? key;
    if (online.hasVerifier) {
      final learned = StoredApprover(
        staffId: online.staffId,
        name: online.name,
        position: online.position,
        salt: online.salt!,
        iterations: online.iterations!,
        check: online.check!,
      );
      final match = await matcher(pin, [learned]);
      if (match != null) {
        key = match.key;
        // Next time this approver can approve offline.
        try {
          await store.remember(learned);
        } catch (error) {
          ApproverStore.note('learned approver verifier not stored', {
            'error': error.runtimeType.toString(),
          });
        }
      } else {
        ApproverStore.note('online approver verifier did not match', {
          'iterations': online.iterations,
        });
      }
    } else {
      ApproverStore.note('online approval without a verifier', {});
    }
    await lockout.clear();
    return ApprovalApproved(
      ApprovalGrant(
        approverStaffId: online.staffId,
        name: online.name,
        position: online.position,
        approvedAt: _clock(),
        method: 'online',
        key: key,
      ),
    );
  }
}

/// The device's uuid for the canonical string.
String currentDeviceUuid(SharedPreferences prefs) {
  final fromIdentity = BusinessBoundary.current?.deviceUuid ?? '';
  if (fromIdentity.isNotEmpty) return fromIdentity;
  try {
    return prefs.getString('device_uuid') ?? '';
  } catch (_) {
    return '';
  }
}

/// Open the approval sheet. Returns the grant, or null when nobody approved.
Future<ApprovalGrant?> requestManagerApproval(
  BuildContext context,
  WidgetRef ref, {
  String? subtitle,
  String? description,
}) async {
  if (!context.mounted) return null;
  return showDialog<ApprovalGrant>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ManagerApprovalSheet(
      engine: ref.read(approvalEngineProvider),
      subtitle: subtitle,
      description: description,
    ),
  );
}

/// C1 + C2 — the one gate for an action on the tick list: allowed by the
/// person's own tick, or by an approver's PIN. [alwaysApproval] forces the
/// sheet (a void reason or discount rule marked "needs manager").
Future<ActionAuthorization?> authorizeAction(
  BuildContext context,
  WidgetRef ref, {
  required String action,
  double? amountPercent,
  bool alwaysApproval = false,
  String? subtitle,
  String? description,
}) async {
  final staff = ref.read(sessionServiceProvider).staff;
  final deviceUuid = currentDeviceUuid(ref.read(sharedPreferencesProvider));
  if (!alwaysApproval &&
      currentStaffPermissions(ref).can(action, amountPercent: amountPercent)) {
    return ActionAuthorization.position(
      action: action,
      actorStaffId: staff?.id,
      actorName: staff?.name ?? '',
      deviceUuid: deviceUuid,
    );
  }
  if (!context.mounted) return null;
  final grant = await requestManagerApproval(
    context,
    ref,
    subtitle: subtitle,
    description: description,
  );
  if (grant == null) return null;
  return ActionAuthorization.approval(
    action: action,
    actorStaffId: staff?.id,
    actorName: staff?.name ?? '',
    grant: grant,
    deviceUuid: deviceUuid,
  );
}

/// C1 — the logged-in person's tick list, read fresh at the gate.
StaffPermissions currentStaffPermissions(WidgetRef ref) => StaffPermissions(
  ref.read(positionPermissionsProvider),
  ref.read(sessionServiceProvider).staff?.position,
);

/// mm:ss for a lock countdown.
String formatLockCountdown(Duration remaining) {
  final total = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
  final m = total ~/ 60, s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The approval sheet: a masked PIN keypad. Pops an [ApprovalGrant] on
/// approval, null otherwise.
class ManagerApprovalSheet extends StatefulWidget {
  const ManagerApprovalSheet({
    super.key,
    required this.engine,
    this.subtitle,
    this.description,
  });

  final ApprovalEngine engine;
  final String? subtitle;
  final String? description;

  @override
  State<ManagerApprovalSheet> createState() => _ManagerApprovalSheetState();
}

class _ManagerApprovalSheetState extends State<ManagerApprovalSheet> {
  String _pin = '';
  bool _busy = false;
  String? _error;
  DateTime? _lockedUntil;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final until = widget.engine.lockout.lockedUntil;
    if (until != null) _startLock(until);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _locked =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  void _startLock(DateTime until) {
    _lockedUntil = until;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_locked) {
        _ticker?.cancel();
        setState(() {
          _lockedUntil = null;
          _error = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  void _append(String digit) {
    if (_busy || _locked || _pin.length >= 8) return;
    setState(() {
      _pin = '$_pin$digit';
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    if (_busy || _locked || _pin.length < 4) return;
    final l10n = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final pin = _pin;
    final attempt = await widget.engine.verify(pin);
    if (!mounted) return;
    switch (attempt) {
      case ApprovalApproved(:final grant):
        Navigator.of(context).pop(grant);
        return;
      case ApprovalLocked(:final until):
        setState(() {
          _busy = false;
          _pin = '';
          _startLock(until);
        });
      case ApprovalWrongPin(:final offline, :final lockedUntil):
        setState(() {
          _busy = false;
          _pin = '';
          _error = offline
              ? l10n.posManagerPinOffline
              : l10n.posManagerPinInvalid;
          if (lockedUntil != null) _startLock(lockedUntil);
        });
      case ApprovalUnavailable(:final message):
        setState(() {
          _busy = false;
          _pin = '';
          _error = message ?? l10n.approvalCheckFailed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locked = _locked;
    final dots = List<Widget>.generate(
      _pin.length,
      (_) => Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: const BoxDecoration(
          color: Color(0xFF1E8D54),
          shape: BoxShape.circle,
        ),
      ),
    );

    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: const Color(0xFFF2F7FA),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy || locked ? null : (onTap ?? () => _append(label)),
            child: SizedBox(
              height: 52,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 20, color: const Color(0xFF39505B))
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF20323C),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    final message = locked
        ? l10n.approvalLockedCountdown(
            formatLockCountdown(_lockedUntil!.difference(DateTime.now())),
          )
        : _error;
    return AlertDialog(
      key: const ValueKey('manager-approval-sheet'),
      title: Text(l10n.posManagerPinTitle),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.subtitle ?? l10n.posManagerPinSubtitle,
                style: const TextStyle(fontSize: 13.5, height: 1.35),
              ),
              if (widget.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.description!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Color(0xFF5B6E78),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _pin.isEmpty
                    ? const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: Color(0xFF8B9DA8),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: dots,
                      ),
              ),
              if (message != null) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  key: const ValueKey('manager-approval-message'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB84524),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Keypad stays LTR in Arabic (digit order never mirrors).
              Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  children: [
                    Row(children: [key('1'), key('2'), key('3')]),
                    Row(children: [key('4'), key('5'), key('6')]),
                    Row(children: [key('7'), key('8'), key('9')]),
                    Row(
                      children: [
                        key(
                          '',
                          icon: Icons.backspace_outlined,
                          onTap: _backspace,
                        ),
                        key('0'),
                        key('', icon: Icons.check_rounded, onTap: _verify),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('manager-approval-verify'),
          onPressed: _busy || locked || _pin.length < 4 ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.posManagerPinVerify),
        ),
      ],
    );
  }
}
