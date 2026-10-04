import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/manager_auth.dart';
import '../core/training_mode.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/api_models.dart';

/// LAUNCH-P5 C6 — clock in before the first sale. Shown after login when
/// the login reply says this person is not clocked in. One tap queues
/// `staff.clock_in` through the outbox (works offline) and the till moves
/// on to the shift. Training mode needs no clock-in.
class ClockInScreen extends ConsumerStatefulWidget {
  const ClockInScreen({super.key});

  @override
  ConsumerState<ClockInScreen> createState() => _ClockInScreenState();
}

class _ClockInScreenState extends ConsumerState<ClockInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _clockIn() async {
    final staff = ref.read(sessionServiceProvider).staff;
    if (staff == null || _busy) return;
    final l10n = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await ref.read(attendanceServiceProvider).clockIn(staff.id);
      await ref
          .read(sessionControllerProvider.notifier)
          .updateAttendance(
            StaffAttendance(open: true, clockInAt: done.at, uuid: done.uuid),
          );
    } catch (_) {
      if (mounted) setState(() => _error = l10n.clockInFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _training() async {
    final gate = await authorizeAction(context, ref, action: 'training.use');
    gate?.grant?.forget();
    if (gate == null || !mounted) return;
    await ref.read(trainingModeProvider.notifier).enter();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final staff = ref.watch(sessionControllerProvider).staff;
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
                const Icon(
                  Icons.schedule_rounded,
                  color: Colors.white70,
                  size: 56,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.clockInTitle(staff?.name ?? ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.clockInSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
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
                SizedBox(
                  width: 260,
                  height: 56,
                  child: FilledButton.icon(
                    key: const ValueKey('clock-in-button'),
                    onPressed: _busy ? null : _clockIn,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(l10n.clockInButton),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  key: const ValueKey('clock-in-training'),
                  onPressed: _busy ? null : _training,
                  child: Text(l10n.trainingEnter),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => ref
                            .read(sessionControllerProvider.notifier)
                            .logoutStaff(),
                  child: Text(l10n.commonLogout),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
