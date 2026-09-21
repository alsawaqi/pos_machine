import 'package:flutter/material.dart';
import 'table_bill_cancellation.dart';

class BillCancelChoice {
  const BillCancelChoice(this.reason, this.lines);
  final String reason;
  final List<Map<String, dynamic>> lines;
}

Future<BillCancelChoice?> showBillCancelDialog(
  BuildContext context,
  List<BillCancelGroup> groups,
  int total, {
  required bool arabic,
}) => showDialog<BillCancelChoice>(
  context: context,
  builder: (_) => _BillCancelDialog(groups, total, arabic),
);

class _BillCancelDialog extends StatefulWidget {
  const _BillCancelDialog(this.groups, this.total, this.arabic);
  final List<BillCancelGroup> groups;
  final int total;
  final bool arabic;
  @override
  State<_BillCancelDialog> createState() => _BillCancelDialogState();
}

class _BillCancelDialogState extends State<_BillCancelDialog> {
  final reason = TextEditingController();
  late final prepared = [for (final g in widget.groups) g.prepared];
  bool invalid = false;
  String text(String en, String ar) => widget.arabic ? ar : en;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
    child: AlertDialog(
      title: Text(text('Cancel table bill', 'إلغاء فاتورة الطاولة')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text(
                  'Cancels the whole bill of OMR ${(widget.total / 1000).toStringAsFixed(3)}. Nothing will be charged.',
                  'سيتم إلغاء الفاتورة كاملة بمبلغ ${(widget.total / 1000).toStringAsFixed(3)} ر.ع. لن يتم تحصيل أي مبلغ.',
                ),
              ),
              for (var i = 0; i < widget.groups.length; i++)
                SwitchListTile(
                  key: ValueKey('cancel-bill-prepared-$i'),
                  title: Text(
                    '${widget.groups[i].qty} × ${widget.groups[i].label}',
                  ),
                  subtitle: Text(text('Prepared?', 'تم التحضير؟')),
                  value: prepared[i],
                  onChanged: (v) => setState(() => prepared[i] = v),
                ),
              TextField(
                key: const ValueKey('cancel-bill-reason'),
                controller: reason,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: text('Reason (required)', 'السبب (مطلوب)'),
                  errorText: invalid
                      ? text('Enter a reason.', 'أدخل السبب.')
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(text('Keep bill', 'الاحتفاظ بالفاتورة')),
        ),
        FilledButton(
          key: const ValueKey('cancel-bill-approve'),
          onPressed: () {
            if (reason.text.trim().isEmpty || reason.text.trim().length > 200) {
              setState(() => invalid = true);
              return;
            }
            Navigator.pop(
              context,
              BillCancelChoice(reason.text.trim(), [
                for (var i = 0; i < widget.groups.length; i++)
                  {
                    ...widget.groups[i].selector,
                    'qty': widget.groups[i].qty,
                    'prepared': prepared[i],
                  },
              ]),
            );
          },
          child: Text(text('Request manager approval', 'طلب موافقة المدير')),
        ),
      ],
    ),
  );
}
