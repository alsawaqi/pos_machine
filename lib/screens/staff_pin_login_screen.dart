import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/manager_auth.dart' show formatLockCountdown;
import '../core/pin_lockout.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/api_models.dart';
import '../services/pos_api_service.dart';
import 'kitchen_production_screen.dart' show PinPromptDialog;

/// Staff PIN login. On success it fetches + caches the branch config (first
/// login needs network) and then completes the session. The startup gate
/// reconciles this cashier's shift before it permits entry to the POS.
///
/// LAUNCH-P5 C4 (PHASE-1A D-9) — after 5 wrong PINs the server answers 423
/// `pin_locked` (or 429 `too_many_attempts`) with `retry_after_seconds`:
/// the keypad and the button are disabled under a live countdown, nothing
/// retries by itself, and the lock is persisted so a restart keeps it
/// (honest limit: clearing the app's data clears it, which also deletes the
/// device token and un-pairs the till). "Manager unlock" sends a manager PIN
/// to `POST /device/auth/unlock-pin-lock`, which clears the SERVER lock
/// (D-7); only then is the keypad enabled again.
///
/// LAUNCH-P5 C6 — "Clock in / out" lets people who do not sell (kitchen)
/// clock without logging in, and the screen says when the till signed
/// someone out because they are no longer active.
class StaffPinLoginScreen extends ConsumerStatefulWidget {
  const StaffPinLoginScreen({super.key});

  @override
  ConsumerState<StaffPinLoginScreen> createState() =>
      _StaffPinLoginScreenState();
}

class _StaffPinLoginScreenState extends ConsumerState<StaffPinLoginScreen> {
  static const int _minLen = 4;
  static const int _maxLen = 6;

  String _pin = '';
  bool _busy = false;
  String? _error;
  String? _notice;
  DateTime? _lockedUntil;
  Timer? _ticker;

  PinLockout get _lockout => ref.read(loginLockoutProvider);

  @override
  void initState() {
    super.initState();
    // A lock from before a restart: recompute what is left; a stored time
    // in the past is not a lock.
    final until = _lockout.lockedUntil;
    if (until != null) _startLock(until);
    final signedOut = ref.read(signOutNoticeProvider);
    if (signedOut != null) {
      scheduleMicrotask(() {
        if (!mounted) return;
        setState(() => _notice = L10n.of(context).signedOutInactive(signedOut));
        ref.read(signOutNoticeProvider.notifier).clear();
      });
    } else if (ref.read(staffReverifyNoticeProvider) ||
        ref.read(sessionServiceProvider).reloginRequired) {
      // LAUNCH-P5 F1 — the staff token was refused (or an upgraded till
      // restored a session without one): ask for the PIN again.
      scheduleMicrotask(() {
        if (!mounted) return;
        setState(() => _notice = L10n.of(context).staffReverifyNotice);
        ref.read(staffReverifyNoticeProvider.notifier).clear();
      });
    }
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
        // Re-enable only; never retry the login by itself.
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

  Future<void> _applyLock(ApiException e) async {
    final until = await _lockout.lockFor(e.lockDuration ?? PinLockout.baseLock);
    if (!mounted) return;
    setState(() {
      _pin = '';
      _error = null;
      _startLock(until);
    });
  }

  void _tap(String digit) {
    if (_busy || _locked || _pin.length >= _maxLen) return;
    setState(() {
      _pin += digit;
      _error = null;
      _notice = null;
    });
  }

  void _backspace() {
    if (_busy || _locked || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<({double? lat, double? lng})> _gpsIfFenced() async {
    final branch = await ref.read(configRepositoryProvider).getBranch();
    final fenced = branch?.latitude != null && branch?.longitude != null;
    return fenced ? await _currentGps() : (lat: null, lng: null);
  }

  Future<void> _submit() async {
    // Captured before the first await so the catch blocks below never touch
    // the context across an async gap.
    final l10n = L10n.of(context);
    if (_locked) return;
    if (_pin.length < _minLen) {
      setState(() => _error = l10n.pinLoginPinLengthError(_minLen, _maxLen));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      // Geofence at sign-in (blueprint §9.4): if this device's branch has a
      // fence, capture the live GPS and send it with the PIN — the server
      // rejects the login when the device is outside the branch area
      // (fail-closed). An unfenced branch needs no location.
      final gps = await _gpsIfFenced();

      final staff = await ref
          .read(apiServiceProvider)
          .staffLogin(pin: _pin, lat: gps.lat, lng: gps.lng);
      await _lockout.clear();
      // First login needs the network: pull the branch config before completing.
      await ref.read(configRepositoryProvider).fetchAndCache();
      // LAUNCH-P5 C2 — the approvers come with the config.
      unawaited(
        ref
            .read(approverStoreProvider)
            .refresh(ref.read(apiServiceProvider))
            .then((_) {}, onError: (Object _) {}),
      );
      await ref.read(sessionControllerProvider.notifier).saveStaff(staff);
      // Gate rebuilds into the POS (behind the geofence gate).
    } on ApiException catch (e) {
      if (e.isPinLock) {
        await _applyLock(e);
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _pin = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = l10n.pinLoginFailedError;
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// PHASE-1A D-7 — a manager PIN clears the server lock, then the pad.
  Future<void> _managerUnlock() async {
    final l10n = L10n.of(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => PinPromptDialog(
        title: l10n.pinLoginManagerUnlock,
        hint: l10n.pinLoginManagerUnlockHint,
        confirmLabel: l10n.pinLoginManagerUnlock,
        confirmColor: const Color(0xFF35C28B),
      ),
    );
    if (pin == null || pin.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final name = await ref.read(apiServiceProvider).unlockPinLock(pin);
      if (!mounted) return;
      if (name == null) {
        setState(() => _error = l10n.posManagerPinInvalid);
        return;
      }
      await _lockout.clear();
      _ticker?.cancel();
      if (!mounted) return;
      setState(() {
        _lockedUntil = null;
        _error = null;
        _notice = l10n.pinLoginUnlockedBy(name);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.isNetwork
            ? l10n.pinLoginUnlockOffline
            : e.isPinLock
            ? l10n.approvalLockedCountdown(
                formatLockCountdown(e.lockDuration ?? PinLockout.baseLock),
              )
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// LAUNCH-P5 C6 — clock in or out without logging in: the PIN identifies
  /// the person (the login check, online), the event goes through the
  /// outbox, and nobody is signed in on the till.
  Future<void> _clockInOut() async {
    final l10n = L10n.of(context);
    if (_locked) return;
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => PinPromptDialog(
        title: l10n.clockInOutTitle,
        hint: l10n.clockInOutHint,
        confirmLabel: l10n.clockInOutConfirm,
        confirmColor: const Color(0xFF35C28B),
      ),
    );
    if (pin == null || pin.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final gps = await _gpsIfFenced();
      final staff = await ref
          .read(apiServiceProvider)
          .staffLogin(pin: pin, lat: gps.lat, lng: gps.lng);
      await _lockout.clear();
      final attendance = ref.read(attendanceServiceProvider);
      final StaffAttendance? state = staff.attendance;
      // LAUNCH-P5 F1 — the event carries the clocking person's token.
      if (state?.open == true) {
        await attendance.clockOut(
          staff.id,
          attendanceUuid: state?.uuid,
          staffToken: staff.staffToken,
        );
        if (mounted) {
          setState(() => _notice = l10n.clockedOutMessage(staff.name));
        }
      } else {
        await attendance.clockIn(staff.id, staffToken: staff.staffToken);
        if (mounted) {
          setState(() => _notice = l10n.clockedInMessage(staff.name));
        }
      }
    } on ApiException catch (e) {
      if (e.isPinLock) {
        await _applyLock(e);
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.clockInFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Best-effort current GPS for the login-time geofence check. Returns nulls
  /// if location is off / denied / times out; the server then fail-closes for a
  /// fenced branch, prompting the operator to enable location and retry.
  Future<({double? lat, double? lng})> _currentGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (lat: null, lng: null);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (lat: null, lng: null);
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locked = _locked;
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.pinLoginTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.pinLoginSubtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 24),
                _dots(),
                if (_notice != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _notice!,
                    key: const ValueKey('pin-login-notice'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF35C28B),
                      fontSize: 14,
                    ),
                  ),
                ],
                if (locked) ...[
                  const SizedBox(height: 14),
                  Text(
                    l10n.approvalLockedCountdown(
                      formatLockCountdown(
                        _lockedUntil!.difference(DateTime.now()),
                      ),
                    ),
                    key: const ValueKey('pin-login-locked'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFE0A93B),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B),
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _keypad(locked),
                const SizedBox(height: 20),
                SizedBox(
                  width: 240,
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('pin-login-submit'),
                    onPressed: _busy || locked ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.pinLoginButton),
                  ),
                ),
                const SizedBox(height: 12),
                if (locked)
                  TextButton.icon(
                    key: const ValueKey('pin-login-manager-unlock'),
                    onPressed: _busy ? null : _managerUnlock,
                    icon: const Icon(
                      Icons.lock_open_rounded,
                      color: Colors.white70,
                    ),
                    label: Text(
                      l10n.pinLoginManagerUnlock,
                      style: const TextStyle(color: Colors.white),
                    ),
                  )
                else
                  TextButton.icon(
                    key: const ValueKey('pin-login-clock'),
                    onPressed: _busy ? null : _clockInOut,
                    icon: const Icon(
                      Icons.schedule_rounded,
                      color: Colors.white70,
                    ),
                    label: Text(
                      l10n.clockInOutButton,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_maxLen, (i) {
        final filled = i < _pin.length;
        return Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? Colors.white : Colors.white24,
          ),
        );
      }),
    );
  }

  Widget _keypad(bool locked) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    // Numeric keypads keep the 1-2-3 order in every locale: pin the grid to
    // LTR so it does not mirror when the app runs RTL (Arabic).
    return SizedBox(
      width: 300,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          physics: const NeverScrollableScrollPhysics(),
          children: keys.map((k) {
            if (k.isEmpty) return const SizedBox.shrink();
            return Opacity(
              opacity: locked ? 0.4 : 1,
              child: Material(
                color: const Color(0xFF1B3540),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: locked
                      ? null
                      : () => k == '<' ? _backspace() : _tap(k),
                  child: Center(
                    child: k == '<'
                        ? const Icon(
                            Icons.backspace_outlined,
                            color: Colors.white70,
                          )
                        : Text(
                            k,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
