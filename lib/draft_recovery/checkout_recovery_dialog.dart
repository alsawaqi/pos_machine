import 'dart:convert';
import 'package:flutter/material.dart';
import 'checkout_recovery.dart';
import 'recovery_admission.dart';

class CheckoutRecoveryDialog extends StatefulWidget {
  const CheckoutRecoveryDialog({
    super.key,
    required this.recovery,
    required this.staffId,
    required this.authorize,
    this.arabic = false,
  });
  final CheckoutRecovery recovery;
  final int staffId;
  final Future<bool> Function() authorize;
  final bool arabic;
  @override
  State<CheckoutRecoveryDialog> createState() => _CheckoutRecoveryDialogState();
}

class _CheckoutRecoveryDialogState extends State<CheckoutRecoveryDialog> {
  List<Map<String, Object?>>? rows;
  bool busy = false;
  String? error;
  String t(String en, String ar) => widget.arabic ? ar : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await widget.recovery.rows();
      if (mounted) setState(() => rows = next);
    } catch (e) {
      if (mounted) {
        setState(() => error = recoveryMessage(e, arabic: widget.arabic));
      }
    }
  }

  Future<void> retire(Map<String, Object?> row) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t('Archive old reservation?', 'أرشفة الحجز السابق؟')),
          content: Text(
            t(
              'Confirm that this old server is retired and no payment was taken. The original record will be archived. This does not release a server reservation or record a payment.',
              'أكد أن الخادم السابق لم يعد مستخدماً وأنه لم يتم أخذ أي دفعة. سيُحفظ السجل الأصلي في الأرشيف. هذا لا يحرر حجزاً على الخادم ولا يسجل دفعة.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('Confirm', 'تأكيد')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.recovery.retire(
        row,
        staffId: widget.staffId,
        authorize: widget.authorize,
      );
      await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = recoveryMessage(e, arabic: widget.arabic));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String identity(Map<String, Object?> row) {
    try {
      final parts = jsonDecode(row['scope'] as String) as List;
      final uri = Uri.parse(parts[0] as String);
      return '${uri.scheme}://${uri.host}:${uri.port} · ${parts[1]}/${parts[2]} · ${parts[3]}';
    } catch (_) {
      return t('Previous device scope', 'نطاق جهاز سابق');
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
    child: AlertDialog(
      title: Text(
        t('Saved checkout recovery', 'استعادة عمليات الدفع المحفوظة'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) Text(error!),
              if (rows == null && error == null)
                const LinearProgressIndicator(),
              if (rows?.isEmpty == true)
                Text(
                  t(
                    'No unresolved saved checkouts.',
                    'لا توجد عمليات دفع محفوظة معلّقة.',
                  ),
                ),
              for (final row in rows ?? <Map<String, Object?>>[]) ...[
                Text(identity(row)),
                Text(
                  '${recoveryCheckoutAttempt(row).createdAt.toLocal()} · ${row['state']}',
                ),
                if (foreignReleaseCanRetire(
                  row,
                  widget.recovery.currentScope(),
                ))
                  FilledButton(
                    onPressed: busy ? null : () => retire(row),
                    child: Text(
                      t('Archive old reservation', 'أرشفة الحجز السابق'),
                    ),
                  )
                else
                  Text(
                    t(
                      'Open this order in its original device scope and retry release or choose Check payment result. Do not take payment again. Ask a manager if that server cannot be reached.',
                      'افتح هذا الطلب ضمن نطاق الجهاز الأصلي وأعد تحرير الحجز أو اختر «التحقق من نتيجة الدفع». لا تأخذ دفعة أخرى. اطلب مساعدة المشرف إذا تعذر الاتصال بالخادم.',
                    ),
                  ),
                const Divider(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(t('Done', 'تم')),
        ),
      ],
    ),
  );
}
