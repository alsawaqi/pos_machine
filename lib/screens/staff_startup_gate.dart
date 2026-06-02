import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'geofence_gate.dart';
import 'pairing_screen.dart';
import 'staff_pin_login_screen.dart';
import 'staff_pos_screen.dart';

/// Boot stages, decided from the persisted session:
///   not paired       → PairingScreen          (needs network)
///   paired, no staff → StaffPinLoginScreen     (first login needs network)
///   paired + staff   → GeofenceGate(StaffPosScreen)  (works offline from Drift)
///
/// A 401 anywhere clears the session (PosApiService.onUnauthorized →
/// SessionController.clearForRePair), which flips this gate back to pairing.
class StaffStartupGate extends ConsumerWidget {
  const StaffStartupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    if (!session.isPaired) {
      return const PairingScreen();
    }
    if (!session.hasStaff) {
      return const StaffPinLoginScreen();
    }
    return const GeofenceGate(child: StaffPosScreen());
  }
}
