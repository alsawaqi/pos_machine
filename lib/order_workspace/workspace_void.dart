import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pos_api_service.dart';
import '../qr_checkout/qr_checkout_models.dart';
import '../qr_checkout/qr_checkout_store.dart';
import '../qr_quick/qr_quick_store.dart';
import '../dine_in/dine_in_store.dart';

/// Read existing journals only. In particular, managed is not released: old
/// unknown attempts still block their bill after a manager leaves checkout.
Future<void> assertWorkspaceVoidJournals(String scope, String uuid) async {
  final checkout = await SqliteCheckoutStore.open(scope);
  final rows = await checkout.db.query(
    'qr_checkout_attempts',
    where: 'scope = ?',
    whereArgs: [scope],
  );
  assertWorkspaceVoidAttempts(rows, uuid);
  if ((await (await SqliteQrQuickStore.open(
        scope,
      )).load()).any((request) => request.orderUuid == uuid) ||
      await (await SqliteDineInStore.open(scope)).load() != null) {
    throw StateError('Resolve saved additions before cancellation');
  }
}

void assertWorkspaceVoidAttempts(List<Map<String, Object?>> rows, String uuid) {
  for (final row in rows) {
    final attempt = CheckoutAttempt.decode(row['payload'] as String);
    if (attempt.id != row['id'] || attempt.state != row['state']) {
      throw StateError('Invalid checkout journal');
    }
    if ((!const {'paid', 'released', 'managed'}.contains(attempt.state)) ||
        (attempt.orderUuid == uuid && attempt.state != 'released')) {
      throw StateError('Payment evidence requires reconciliation');
    }
  }
}

class WorkspaceVoidPreview {
  WorkspaceVoidPreview(String uuid, Map<String, dynamic> data)
    : order = frozenCheckoutMap(checkoutMap(data['order'])),
      token = data['preview_token'] as String,
      pendingRounds = data['pending_rounds'] as int {
    if (order['uuid'] != uuid ||
        token.isEmpty ||
        pendingRounds < 0 ||
        !const {'open', 'held', 'awaiting_payment'}.contains(order['status']) ||
        order['grand_total_baisas'] is! int ||
        (order['grand_total_baisas'] as int) < 0 ||
        order['items'] is! List) {
      throw const FormatException('Invalid void preview');
    }
    for (final line in items) {
      if (line['name'] is! String ||
          line['qty'] is! num ||
          !(line['qty'] as num).isFinite ||
          (line['qty'] as num) < 0 ||
          line['line_total_baisas'] is! int) {
        throw const FormatException('Invalid void preview item');
      }
    }
  }
  final Map<String, dynamic> order;
  final String token;
  final int pendingRounds;
  String get uuid => order['uuid'] as String;
  String get reference =>
      (order['receipt_number'] ?? order['temp_reference'] ?? uuid).toString();
  int get total => order['grand_total_baisas'] as int;
  List<Map<String, dynamic>> get items =>
      (order['items'] as List).map(checkoutMap).toList();
}

abstract interface class WorkspaceVoidGateway {
  Future<WorkspaceVoidPreview> preview(String uuid);
  Future<void> cancel(WorkspaceVoidPreview preview, String pin, String reason);
}

class ApiWorkspaceVoidGateway implements WorkspaceVoidGateway {
  ApiWorkspaceVoidGateway(this.api, this.currentScope, this.guard)
    : scope = currentScope(),
      token = api.tokenGetter();
  final PosApiService api;
  final String Function() currentScope;
  final Future<void> Function(String uuid) guard;
  final String scope;
  final String? token;
  void _check() {
    if (scope != currentScope() ||
        token == null ||
        token!.isEmpty ||
        api.tokenGetter() != token) {
      throw StateError('Device identity changed');
    }
  }

  Future<void> _admit(String uuid) async {
    _check();
    await guard(uuid);
    _check();
  }

  @override
  Future<WorkspaceVoidPreview> preview(String uuid) async {
    await _admit(uuid);
    final data = await api.workspaceVoidPreview(uuid);
    _check();
    return WorkspaceVoidPreview(uuid, data);
  }

  @override
  Future<void> cancel(
    WorkspaceVoidPreview preview,
    String pin,
    String reason,
  ) async {
    await _admit(preview.uuid);
    final result = await api.workspaceVoid(preview.uuid, {
      'preview_token': preview.token,
      'pin': pin,
      'reason': reason,
    });
    _check();
    if (result['order_uuid'] != preview.uuid ||
        result['status'] != 'void' ||
        result['already_void'] is! bool) {
      throw const FormatException('Cancellation acknowledgement mismatch');
    }
  }
}

String workspaceVoidError(Object error, bool ar) {
  final code = error is ApiException ? error.code : null;
  const messages = {
    'invalid_pin': ['Manager PIN not accepted.', 'لم يتم قبول رمز المشرف.'],
    'qr_session_active': [
      'The phone session is active. Refresh the list; this order was not cancelled.',
      'جلسة الهاتف نشطة. حدّث القائمة؛ لم يُلغَ هذا الطلب.',
    ],
    'qr_waste_review_required': [
      'Prepared stock needs review. No orders were cancelled. Review wastage and try again.',
      'المخزون المحضر يحتاج إلى مراجعة. لم تُلغَ أي طلبات. راجع الهدر وحاول مجدداً.',
    ],
    'void_preview_changed': [
      'The bill changed. Close this review and refresh before cancelling.',
      'تغيرت الفاتورة. أغلق المراجعة وحدّثها قبل الإلغاء.',
    ],
    'qr_charge_recovery_required': [
      'Payment evidence requires reconciliation. Do not cancel or take another payment.',
      'توجد بيانات دفع تحتاج إلى تسوية. لا تُلغِ الفاتورة ولا تأخذ دفعة أخرى.',
    ],
    'void_bill_not_unpaid': [
      'This bill is no longer unpaid. Refresh its status.',
      'هذه الفاتورة لم تعد غير مدفوعة. حدّث حالتها.',
    ],
    'order_not_found': [
      'This bill is no longer available here. Refresh the list.',
      'هذه الفاتورة لم تعد متاحة هنا. حدّث القائمة.',
    ],
    'device_not_attended': [
      'An active assigned till or handheld is required.',
      'يلزم جهاز كاشير أو جهاز محمول نشط ومخصص.',
    ],
  };
  if (messages[code] case final text?) return text[ar ? 1 : 0];
  if (error is StateError) {
    return ar
        ? 'لم يتم تأكيد الإلغاء. راجع بيانات الجهاز والطلبات المحفوظة ثم حدّث الفاتورة قبل أي إجراء آخر.'
        : 'Cancellation is not confirmed. Review device identity and saved requests, then refresh the bill before another action.';
  }
  return ar
      ? 'لم يتم تأكيد الإلغاء. حدّث حالة الفاتورة قبل أي إجراء آخر. لا تكرر الدفع.'
      : 'Cancellation is not confirmed. Refresh the bill before another action. Do not repeat payment.';
}

Future<bool> showWorkspaceVoid(
  BuildContext context,
  WorkspaceVoidGateway gateway,
  String uuid, {
  required bool arabic,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: _VoidDialog(gateway, uuid, arabic),
      ),
    ) ??
    false;

class _VoidDialog extends StatefulWidget {
  const _VoidDialog(this.gateway, this.uuid, this.arabic);
  final WorkspaceVoidGateway gateway;
  final String uuid;
  final bool arabic;
  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final pin = TextEditingController(), reason = TextEditingController();
  WorkspaceVoidPreview? preview;
  String? error;
  bool busy = true, sent = false;
  String text(String en, String ar) => widget.arabic ? ar : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.gateway.preview(widget.uuid);
      if (value.uuid != widget.uuid) throw const FormatException('Wrong bill');
      if (mounted) setState(() => preview = value);
    } catch (e) {
      if (mounted) setState(() => error = workspaceVoidError(e, widget.arabic));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    if (busy || sent || preview == null) return;
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
      error = null;
      sent = true;
    });
    try {
      await widget.gateway.cancel(preview!, pin.text, reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // No automatic retry, no offline queue, and no claimed success on a
      // lost/invalid reply. A fresh review is required for another operation.
      if (mounted) setState(() => error = workspaceVoidError(e, widget.arabic));
    } finally {
      if (mounted) {
        pin.clear();
        setState(() => busy = false);
      }
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
      title: Text(text('Void this bill?', 'إلغاء هذه الفاتورة؟')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (preview case final p?) ...[
                Text(
                  '${p.reference} · ${(p.total / 1000).toStringAsFixed(3)} OMR',
                  key: const ValueKey('void-reference'),
                ),
                for (final item in p.items)
                  Text('${item['qty']} × ${item['name']}'),
                Text(
                  text(
                    'This cancels the whole unpaid bill and rejects ${p.pendingRounds} pending rounds. It does not refund or clear payment evidence.',
                    'سيتم إلغاء الفاتورة غير المدفوعة بالكامل ورفض ${p.pendingRounds} جولات معلقة. لا يتم رد أموال أو مسح بيانات الدفع.',
                  ),
                ),
                TextField(
                  controller: reason,
                  key: const ValueKey('void-reason'),
                  enabled: !busy && !sent,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: text('Cancellation reason', 'سبب الإلغاء'),
                  ),
                ),
                TextField(
                  controller: pin,
                  key: const ValueKey('void-pin'),
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
                Text(error!, key: const ValueKey('void-error')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('void-keep'),
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: Text(
            text('Close without another action', 'إغلاق دون إجراء آخر'),
          ),
        ),
        FilledButton(
          key: const ValueKey('void-confirm'),
          onPressed: busy || sent || preview == null ? null : _submit,
          child: Text(text('Approve cancellation', 'الموافقة على الإلغاء')),
        ),
      ],
    ),
  );
}
