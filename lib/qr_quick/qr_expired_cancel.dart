import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../order_workspace/workspace_void.dart';
import 'qr_quick_models.dart';

abstract interface class QrQuickCancellationGateway {
  Future<Map<String, dynamic>> previewCancel(String? uuid);
  Future<Map<String, dynamic>> cancelExpired(Map<String, dynamic> payload);
}

Future<bool> showQrExpiredCancel(
  BuildContext context,
  QrQuickCancellationGateway gateway,
  String? uuid, {
  required bool arabic,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: _CancelExpired(gateway, uuid, arabic),
      ),
    ) ??
    false;

class _CancelExpired extends StatefulWidget {
  const _CancelExpired(this.gateway, this.uuid, this.arabic);
  final QrQuickCancellationGateway gateway;
  final String? uuid;
  final bool arabic;
  @override
  State<_CancelExpired> createState() => _CancelExpiredState();
}

class _CancelExpiredState extends State<_CancelExpired> {
  final pin = TextEditingController();
  final reason = TextEditingController();
  final requestId = QrQuickRequest.newId();
  Map<String, dynamic>? preview;
  final prepared = <String>{};
  bool busy = true, sent = false;
  String? error;
  String text(String en, String ar) => widget.arabic ? ar : en;
  List<Map<String, dynamic>> get rows =>
      (preview?['orders'] as List? ?? []).map(qrMap).toList();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.gateway.previewCancel(widget.uuid);
      final orders = (value['orders'] as List).map(qrMap).toList();
      if (value['count'] != orders.length ||
          value['total_baisas'] is! int ||
          value['preview_token'] is! String ||
          (widget.uuid != null &&
              (orders.length != 1 || orders.single['uuid'] != widget.uuid)) ||
          orders.any(
            (o) =>
                o['uuid'] is! String ||
                o['reference'] is! String ||
                o['total_baisas'] is! int ||
                o['prepared'] is! bool ||
                o['items'] is! List,
          ) ||
          orders.fold<int>(0, (sum, o) => sum + (o['total_baisas'] as int)) !=
              value['total_baisas']) {
        throw const FormatException('Invalid cancellation preview');
      }
      if (mounted) {
        setState(() {
          preview = value;
          prepared.addAll(
            orders
                .where((o) => o['prepared'] == true)
                .map((o) => o['uuid'] as String),
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = workspaceVoidError(e, widget.arabic));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    if (busy || sent || rows.isEmpty) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin.text) ||
        reason.text.trim().isEmpty) {
      setState(
        () => error = text(
          'Enter a reason and manager PIN.',
          'أدخل السبب ورمز المشرف.',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      sent = true;
      error = null;
    });
    try {
      final result = await widget.gateway.cancelExpired({
        'client_request_id': requestId,
        'preview_token': preview!['preview_token'],
        'pin': pin.text,
        'reason': reason.text.trim(),
        // A printed round already proves exactly which lines were prepared.
        // Do not turn that server evidence into an all-lines override.
        'prepared_order_uuids':
            prepared
                .where(
                  (id) => rows.any(
                    (row) => row['uuid'] == id && row['prepared'] != true,
                  ),
                )
                .toList()
              ..sort(),
      });
      final orders = (result['orders'] as List).map(qrMap).toList();
      final expected = rows.map((r) => r['uuid']).toSet();
      if (result['replayed'] is! bool ||
          result['count'] != expected.length ||
          orders.length != expected.length ||
          orders.any(
            (o) => o['status'] != 'void' || !expected.remove(o['order_uuid']),
          ) ||
          expected.isNotEmpty) {
        throw const FormatException('Cancellation acknowledgement mismatch');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = workspaceVoidError(e, widget.arabic));
    } finally {
      pin.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    pin.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        text('Cancel expired QR orders?', 'إلغاء طلبات QR المنتهية؟'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (preview != null) ...[
                Text(
                  text(
                    '${rows.length} orders · ${((preview!['total_baisas'] as int) / 1000).toStringAsFixed(3)} OMR',
                    '${rows.length} طلبات · ${((preview!['total_baisas'] as int) / 1000).toStringAsFixed(3)} OMR',
                  ),
                  key: const ValueKey('quick-cancel-summary'),
                ),
                Text(
                  text(
                    'Only the expired or closed phone sessions in this review will be cancelled. Kitchen-sent items are recorded as wastage. No payment or refund is made.',
                    'سيتم إلغاء الطلبات ذات جلسات الهاتف المنتهية أو المغلقة في هذه المراجعة فقط. تُسجل الأصناف المرسلة للمطبخ كهدر. لا يتم دفع أو رد أموال.',
                  ),
                ),
                for (final row in rows) ...[
                  Text(
                    '${row['reference']} · ${((row['total_baisas'] as int) / 1000).toStringAsFixed(3)} OMR',
                  ),
                  for (final item in (row['items'] as List).map(qrMap))
                    Text('${item['qty']} × ${item['name']}'),
                  CheckboxListTile(
                    key: ValueKey('quick-prepared-${row['uuid']}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      text(
                        'Food was prepared — record wastage',
                        'تم تحضير الطعام — تسجيل الهدر',
                      ),
                    ),
                    value: prepared.contains(row['uuid']),
                    onChanged: busy || sent || row['prepared'] == true
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              prepared.add(row['uuid'] as String);
                            } else {
                              prepared.remove(row['uuid']);
                            }
                          }),
                  ),
                ],
                TextField(
                  key: const ValueKey('quick-cancel-reason'),
                  controller: reason,
                  enabled: !busy && !sent,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: text('Cancellation reason', 'سبب الإلغاء'),
                  ),
                ),
                TextField(
                  key: const ValueKey('quick-cancel-pin'),
                  controller: pin,
                  enabled: !busy && !sent,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: text('Manager PIN', 'رمز المشرف'),
                  ),
                ),
              ],
              if (error != null)
                Text(error!, key: const ValueKey('quick-cancel-error')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('quick-cancel-close'),
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: Text(text('Keep orders', 'الاحتفاظ بالطلبات')),
        ),
        FilledButton(
          key: const ValueKey('quick-cancel-confirm'),
          onPressed: busy || sent || rows.isEmpty ? null : _submit,
          child: Text(text('Approve cancellation', 'الموافقة على الإلغاء')),
        ),
      ],
    ),
  );
}
