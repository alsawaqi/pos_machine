import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart' show TableDegradedState;

/// Informational only: it owns neither gestures nor any connectivity policy.
class TableDegradedBanner extends StatelessWidget {
  const TableDegradedBanner({
    super.key,
    required this.mode,
    required this.state,
  });

  final String mode;
  final TableDegradedState state;

  @override
  Widget build(BuildContext context) {
    if (mode != 'live' || !state.degraded) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final at = state.since?.toLocal();
    final time = at == null
        ? '—'
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return IgnorePointer(
      child: Container(
        key: const ValueKey('table-degraded-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFE6A6),
        child: Text(
          l10n.tableOfflineBanner(time, state.queuedActions),
          style: const TextStyle(color: Color(0xFF503600), fontSize: 16),
        ),
      ),
    );
  }
}
