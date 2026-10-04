import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'device_setup_screen.dart';
import 'geofence_gate.dart';
import 'shift_close_screen.dart';
import 'shift_open_screen.dart';
import 'staff_pin_login_screen.dart';
import 'staff_pos_screen.dart';
import 'card_reversal_sheet.dart';
import 'card_reversal_factory.dart';
import 'clock_in_screen.dart';
import '../core/staff_session_guard.dart';
import '../core/training_mode.dart';
import '../services/session_service.dart' show SessionState;

/// Boot stages, decided from the persisted session:
///   not configured      → DeviceSetupScreen     (one-time terminal-ID claim)
///   claimed, no staff    → StaffPinLoginScreen    (staff enters their PIN)
///   staff, no open shift → ShiftOpenScreen        (count the opening float)
///   staff + foreign shift → ShiftCloseScreen      (forced drawer handover)
///   staff + own shift    → GeofenceGate(StaffPosScreen)  (works offline from Drift)
///
/// A 401 anywhere clears the session (PosApiService.onUnauthorized →
/// SessionController.clearForRePair), which flips this gate back to device setup.
class StaffStartupGate extends ConsumerWidget {
  const StaffStartupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    if (!session.isConfigured) {
      return const DeviceSetupScreen();
    }
    if (!session.hasStaff) {
      return const StaffPinLoginScreen();
    }
    // LAUNCH-P5 — every logged-in screen runs inside the session guard
    // (staff-status poll, approver refresh, shift-end reminder, training
    // banner).
    return StaffSessionGuard(child: _loggedIn(ref, session));
  }

  Widget _loggedIn(WidgetRef ref, SessionState session) {
    // LAUNCH-P5 C7 — training needs no clock-in and no shift.
    if (ref.watch(trainingModeProvider)) {
      return CardReversalRecoveryGate(
        createController: () => createMachineReversalController(ref),
        operatorName: session.staff?.name ?? '',
        child: const GeofenceGate(child: StaffPosScreen()),
      );
    }
    // LAUNCH-P5 C6 — clock in before the first sale (when the server says
    // this person is not clocked in; an older server says nothing).
    final attendance = session.staff!.attendance;
    if (attendance != null && !attendance.open) {
      return const ClockInScreen();
    }

    // MC-003 — every staff session gets a staff-keyed server probe, even when
    // a local shift exists. While online this adopts their own cross-device
    // shared shift or discovers the device's foreign drawer. Offline, the
    // cached owner check below still fails closed for a foreign shift.
    final staffId = session.staff!.id;
    final reconciliation = ref.watch(shiftReconciliationProvider(staffId));
    if (reconciliation.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF102028),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!session.hasOpenShift) {
      return const ShiftOpenScreen();
    }
    if (session.openShift!.staffId != staffId) {
      return const ShiftCloseScreen(forcedHandover: true);
    }
    return CardReversalRecoveryGate(
      createController: () => createMachineReversalController(ref),
      operatorName: session.staff?.name ?? '',
      child: const GeofenceGate(child: StaffPosScreen()));
  }
}
