import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart';
import 'shift_reminder.dart';
import 'training_mode.dart';

/// LAUNCH-P5 — what runs around every logged-in screen of the till:
///
///  * C6: every 60 s while online, `GET /device/staff-status`; a logged-in
///    person missing from the active list is logged out at once (their open
///    shift stays open) and the PIN screen says why;
///  * C2: the branch's approver verifiers are refreshed at start, on resume
///    and every 5 minutes while online;
///  * C8: the shift-end reminder — a banner and a sound at
///    `settings.shift_end_reminder_at` (Muscat) while the person's own shift
///    is open, again every 15 minutes until it is closed;
///  * C7: the red TRAINING banner while training mode is on.
class StaffSessionGuard extends ConsumerStatefulWidget {
  const StaffSessionGuard({super.key, required this.child});

  final Widget child;

  /// Test seams.
  static Duration statusEvery = const Duration(seconds: 60);
  static Duration approversEvery = const Duration(minutes: 5);
  static Duration reminderTick = const Duration(seconds: 30);
  static DateTime Function() clock = DateTime.now;
  static void Function() playAlert = () =>
      unawaited(SystemSound.play(SystemSoundType.alert));

  @override
  ConsumerState<StaffSessionGuard> createState() => _StaffSessionGuardState();
}

class _StaffSessionGuardState extends ConsumerState<StaffSessionGuard>
    with WidgetsBindingObserver {
  Timer? _statusTimer;
  Timer? _approversTimer;
  Timer? _reminderTimer;
  DateTime? _lastAlert;
  bool _reminderVisible = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusTimer = Timer.periodic(
      StaffSessionGuard.statusEvery,
      (_) => unawaited(_checkStatus()),
    );
    _approversTimer = Timer.periodic(
      StaffSessionGuard.approversEvery,
      (_) => unawaited(_refreshApprovers()),
    );
    _reminderTimer = Timer.periodic(
      StaffSessionGuard.reminderTick,
      (_) => _tickReminder(),
    );
    scheduleMicrotask(() {
      if (!mounted) return;
      unawaited(_refreshApprovers());
      _tickReminder();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _approversTimer?.cancel();
    _reminderTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshApprovers());
      unawaited(_checkStatus());
    }
  }

  Future<void> _refreshApprovers() async {
    try {
      await ref
          .read(approverStoreProvider)
          .refresh(ref.read(apiServiceProvider));
    } catch (_) {
      // Offline or an older server: the stored list stays.
    }
  }

  Future<void> _checkStatus() async {
    if (_checking || !mounted) return;
    final staff = ref.read(sessionServiceProvider).staff;
    if (staff == null) return;
    _checking = true;
    try {
      final active = await ref.read(apiServiceProvider).fetchActiveStaffIds();
      if (!mounted) return;
      final current = ref.read(sessionServiceProvider).staff;
      if (current == null || current.id != staff.id) return;
      if (active.contains(staff.id)) return;
      // Suspended or terminated: out now. The open shift stays open.
      ref.read(signOutNoticeProvider.notifier).show(staff.name);
      if (ref.read(trainingModeProvider)) {
        await ref.read(trainingModeProvider.notifier).exit();
      }
      await ref.read(sessionControllerProvider.notifier).logoutStaff();
    } catch (_) {
      // Offline: nothing to decide.
    } finally {
      _checking = false;
    }
  }

  void _tickReminder() {
    if (!mounted) return;
    final session = ref.read(sessionServiceProvider);
    final staff = session.staff;
    final shift = ref.read(sessionControllerProvider).openShift;
    String? at;
    try {
      at = session.shiftEndReminderAt;
    } catch (_) {
      at = null;
    }
    final now = StaffSessionGuard.clock();
    final due = staff == null || shift == null || shift.staffId != staff.id
        ? null
        : ShiftEndReminder.dueSince(
            hhmm: at,
            openedAt: shift.openedAt,
            now: now,
          );
    if (due == null) {
      if (_reminderVisible || _lastAlert != null) {
        setState(() {
          _reminderVisible = false;
          _lastAlert = null;
        });
      }
      return;
    }
    if (ShiftEndReminder.shouldAlert(
      dueSince: due,
      lastAlert: _lastAlert,
      now: now,
    )) {
      StaffSessionGuard.playAlert();
      setState(() {
        _lastAlert = now;
        _reminderVisible = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final training = ref.watch(trainingModeProvider);
    // A shift closed elsewhere hides the reminder at once.
    ref.listen(
      sessionControllerProvider,
      (_, _) => scheduleMicrotask(_tickReminder),
    );
    return Column(
      children: [
        if (training)
          Material(
            key: const ValueKey('training-banner'),
            color: const Color(0xFFC62828),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                height: 30,
                child: Center(
                  child: Text(
                    l10n.trainingBanner,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_reminderVisible)
          Material(
            key: const ValueKey('shift-end-reminder'),
            color: const Color(0xFFE0A93B),
            child: SafeArea(
              bottom: false,
              top: !training,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.alarm_rounded, color: Color(0xFF102028)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.shiftEndReminderBanner,
                        style: const TextStyle(
                          color: Color(0xFF102028),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _reminderVisible = false),
                      child: Text(
                        l10n.shiftEndReminderDismiss,
                        style: const TextStyle(color: Color(0xFF102028)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
