import 'package:flutter/material.dart';

/// Stable key for accessibility checks and host-screen integration tests.
const qrRoundPrintStatusIndicatorKey = ValueKey<String>(
  'qr-round-print-status-indicator',
);

String qrRoundPrintUnavailableMessage({required bool arabic}) => arabic
    ? 'تعذّر اتصال طباعة طلبات QR للمطبخ بالخادم. '
          'قد تتأخر طباعة الجولات الجديدة؛ '
          'ستتم إعادة المحاولة تلقائيًا.'
    : 'QR kitchen printing cannot reach the server. '
          'New round printing may be delayed; retrying automatically.';

/// Copy for the one-shot notice emitted after an invalid persisted cursor is
/// replaced with a fresh server cursor.
String qrRoundPrintPositionResetMessage({required bool arabic}) => arabic
    ? 'تمت إعادة ضبط موضع طباعة QR. '
          'قد لا تكون الجولات المقبولة قبل إعادة الضبط قد طُبعت.'
    : 'QR print position was reset. '
          'Rounds accepted before the reset may not have printed.';

/// A persistent, non-blocking status surface shown only after the accepted-
/// round feed reaches its repeated-failure threshold.
class QrRoundPrintStatusIndicator extends StatelessWidget {
  const QrRoundPrintStatusIndicator({
    super.key,
    required this.unavailable,
    required this.arabic,
  });

  final bool unavailable;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    if (!unavailable) return const SizedBox.shrink();

    final message = qrRoundPrintUnavailableMessage(arabic: arabic);
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      key: qrRoundPrintStatusIndicatorKey,
      container: true,
      liveRegion: true,
      label: message,
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: ExcludeSemantics(
        child: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.errorContainer,
              border: Border.all(color: colors.error.withValues(alpha: 0.45)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_problem_rounded,
                    size: 18,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
