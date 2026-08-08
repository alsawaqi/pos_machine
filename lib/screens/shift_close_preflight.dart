import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'kitchen_production_screen.dart';

/// Runs the established day-end disposition step before any drawer close.
/// A network failure never blocks reconciliation; expired pieces remain for
/// the next online close, matching the existing POS close behavior.
Future<void> runShiftClosePreflight(BuildContext context, WidgetRef ref) async {
  try {
    final expired = await ref.read(apiServiceProvider).fetchDisposition();
    if (!context.mounted || expired.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayEndDispositionScreen(
          items: expired,
          staffId: ref.read(sessionServiceProvider).staff?.id,
        ),
      ),
    );
  } catch (_) {
    // Offline / server hiccup: never block closing the drawer on disposition.
  }
}
