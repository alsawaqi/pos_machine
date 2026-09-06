import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

class SentLineCancellationApproval {
  const SentLineCancellationApproval({required this.prepared, this.reason});
  final bool prepared;
  final String? reason;
}

/// Reuses the caller's existing fingerprint/PIN gate. No cancellation intent
/// exists until both manager approval and the preparation choice succeed.
Future<SentLineCancellationApproval?> requestSentLineCancellation(
  BuildContext context, {
  required Future<bool> Function() authorizeManager,
}) async {
  if (!await authorizeManager() || !context.mounted) return null;
  return showDialog<SentLineCancellationApproval>(
    context: context,
    builder: (_) => const SentLineCancelDialog(),
  );
}

class SentLineCancelDialog extends StatefulWidget {
  const SentLineCancelDialog({super.key});

  @override
  State<SentLineCancelDialog> createState() => _SentLineCancelDialogState();
}

class _SentLineCancelDialogState extends State<SentLineCancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _choose(bool prepared) {
    final reason = _reason.text.trim();
    Navigator.of(context).pop(
      SentLineCancellationApproval(
        prepared: prepared,
        reason: reason.isEmpty ? null : reason,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.tableCancelSentTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tableWasPrepared),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 200,
            decoration: InputDecoration(labelText: l10n.tableCancelSentReason),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => _choose(false),
          child: Text(l10n.tablePreparedNo),
        ),
        FilledButton(
          onPressed: () => _choose(true),
          child: Text(l10n.tablePreparedYes),
        ),
      ],
    );
  }
}
