import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/geofence_service.dart';

/// Wraps the POS: shows [child] only when the device is inside the branch fence
/// (or the branch has no fence). Otherwise shows a full-screen lock. Fail-closed.
class GeofenceGate extends ConsumerWidget {
  const GeofenceGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(geofenceProvider);
    return status.when(
      data: (s) => s.allowsPos ? child : _Lock(status: s),
      loading: () => const _Lock(status: GeofenceStatus(FenceState.locating)),
      error: (_, _) => const _Lock(status: GeofenceStatus(FenceState.noPermission)),
    );
  }
}

class _Lock extends ConsumerWidget {
  const _Lock({required this.status});

  final GeofenceStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final (String title, String message, IconData icon) = switch (status.state) {
      FenceState.locating => (
          l10n.geofenceCheckingLocationTitle,
          l10n.geofenceCheckingLocationMessage,
          Icons.my_location,
        ),
      FenceState.noPermission => (
          l10n.geofenceLocationRequiredTitle,
          l10n.geofenceLocationRequiredMessage,
          Icons.location_disabled,
        ),
      FenceState.outside => (
          l10n.geofenceOutsideTitle,
          _distanceText(l10n, status),
          Icons.wrong_location,
        ),
      _ => (l10n.geofenceLockedTitle, '', Icons.lock_outline),
    };

    return Scaffold(
      backgroundColor: const Color(0xFF14252E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.white70),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 15),
              ),
            ),
            const SizedBox(height: 28),
            if (status.state == FenceState.locating)
              const CircularProgressIndicator()
            else
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(geofenceProvider),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.commonRetry),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  String _distanceText(L10n l10n, GeofenceStatus s) {
    if (s.distanceM == null) {
      return l10n.geofenceOutsideNoDistanceMessage;
    }
    return l10n.geofenceOutsideDistanceMessage(
      s.distanceM!.round(),
      s.radiusM.round(),
    );
  }
}
