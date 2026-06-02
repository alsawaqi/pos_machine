import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'device_setup_screen.dart';
import 'geofence_gate.dart';
import 'staff_pin_login_screen.dart';
import 'staff_pos_screen.dart';

/// Boot stages, decided from the persisted session:
///   not configured   → DeviceSetupScreen       (one-time terminal-ID claim)
///   claimed, no staff → StaffPinLoginScreen      (staff enters their PIN)
///   claimed + staff   → GeofenceGate(StaffPosScreen)  (works offline from Drift)
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
    return const GeofenceGate(child: StaffPosScreen());
  }
}
