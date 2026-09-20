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
    if (mode != 'live' || !state.hasWarning) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final at = state.since?.toLocal();
    final time = at == null
        ? '—'
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.degraded)
            _message(
              'table-degraded-banner',
              state.connectionUnavailable
                  ? l10n.tableOfflineBanner(time, state.queuedActions)
                  : l10n.tableSyncPendingBanner(state.queuedActions),
            ),
          if (state.parkedWaste > 0)
            _message(
              'waste-sync-attention-banner',
              Localizations.localeOf(context).languageCode == 'ar'
                  ? 'تعذرت مزامنة هدر المخزون. ${state.parkedWaste} عمليات محفوظة. افتح الإعدادات ← مبيعات عالقة للمراجعة وإعادة المحاولة.'
                  : 'Stock waste could not sync. ${state.parkedWaste} saved bookings. Open Settings → Stuck sales to review and retry.',
            ),
          if (state.parkedActions > 0)
            _message(
              'table-sync-attention-banner',
              l10n.tableParkedActionsBanner(state.parkedActions),
            ),
        ],
      ),
    );
  }

  Widget _message(String key, String text) => Container(
    key: ValueKey(key),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: const Color(0xFFFFE6A6),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF503600), fontSize: 16),
    ),
  );
}
