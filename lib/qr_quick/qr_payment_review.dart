import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../qr_checkout/payment_review_store.dart';
import '../services/pos_api_service.dart' show ApiException;
import 'qr_quick_copy.dart';
import 'qr_quick_models.dart';

abstract interface class QrQuickPaymentReviewGateway {
  /// Orders with a checkout on this device that a manager has not reviewed.
  Future<Set<String>> ordersWithLocalPaymentEvidence();
  Future<PaymentReviewEvidence> paymentEvidence(String uuid);

  /// Sends the review, then records it beside the reviewed checkouts.
  Future<Map<String, dynamic>> reviewPayment(
    String uuid,
    PaymentReviewEvidence evidence,
    Map<String, dynamic> payload,
  );
}

/// Local save failed after the server confirmed; the same request is replayed.
class PaymentReviewNotSaved implements Exception {
  const PaymentReviewNotSaved();
}

Future<bool> showQrPaymentReview(
  BuildContext context,
  QrQuickPaymentReviewGateway gateway,
  QrQuickOrder order, {
  required bool arabic,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
        child: _PaymentReview(gateway, order, arabic),
      ),
    ) ??
    false;

class _PaymentReview extends StatefulWidget {
  const _PaymentReview(this.gateway, this.order, this.arabic);
  final QrQuickPaymentReviewGateway gateway;
  final QrQuickOrder order;
  final bool arabic;
  @override
  State<_PaymentReview> createState() => _PaymentReviewState();
}

class _PaymentReviewState extends State<_PaymentReview> {
  final pin = TextEditingController();
  final reference = TextEditingController();
  final requestId = QrQuickRequest.newId();
  PaymentReviewEvidence? evidence;
  bool? taken;
  String method = 'cash';
  bool busy = true, sent = false;

  /// After the first submission the decision is fixed, so a retry (refused
  /// PIN, no answer, location off) sends the identical request.
  bool frozen = false;
  String? error;
  Map<String, dynamic>? done;
  String text(String en, String ar) => widget.arabic ? ar : en;
  String money(int baisas) => '${(baisas / 1000).toStringAsFixed(3)} OMR';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.gateway.paymentEvidence(widget.order.uuid);
      final methods = {
        for (final e in value.saved)
          for (final c in e.attempt.captures) c['method'],
      };
      if (mounted) {
        setState(() {
          evidence = value;
          if (methods.length == 1 && methods.single == 'card') method = 'card';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = text(
            'Cannot read the saved payments on this till. Keep app data and ask for help.',
            'تعذّرت قراءة المدفوعات المحفوظة على هذا الجهاز. احتفظ ببيانات التطبيق واطلب المساعدة.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _when(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  String _method(Object? m) => switch (m) {
    'cash' => text('Cash', 'نقداً'),
    'card' => text('Card', 'بطاقة'),
    _ => '$m',
  };

  List<String> _lines(LocalPaymentEvidence e) {
    final a = e.attempt;
    final at = _when(
      a.event?['client_timestamp'] is String
          ? DateTime.parse(a.event!['client_timestamp'] as String)
          : a.createdAt,
    );
    if (a.captures.isNotEmpty) {
      return [
        for (final c in a.captures)
          text(
            '${_method(c['method'])} ${money(c['amount_baisas'] as int)} taken'
                '${(c['change_given_baisas'] ?? 0) == 0 ? '' : ', change ${money(c['change_given_baisas'] as int)}'}'
                ' · $at',
            'تم استلام ${money(c['amount_baisas'] as int)} ${_method(c['method'])}'
                '${(c['change_given_baisas'] ?? 0) == 0 ? '' : '، الباقي ${money(c['change_given_baisas'] as int)}'}'
                ' · $at',
          ),
      ];
    }
    if (a.tenderMayHaveStarted == true || a.event != null) {
      return [
        text(
          'A payment was started · $at — result unknown',
          'بدأت عملية دفع · $at — النتيجة غير معروفة',
        ),
      ];
    }
    return [
      text(
        'Checkout handed to a manager · $at',
        'تم تسليم الدفع إلى المشرف · $at',
      ),
    ];
  }

  String _error(Object e) {
    if (e is PaymentReviewNotSaved) {
      return text(
        'The server recorded the review, but this till could not save it. Tap Confirm again (the same review is sent, never twice).',
        'سجّل الخادم المراجعة، لكن تعذّر حفظها على هذا الجهاز. اضغط تأكيد مرة أخرى (تُرسل نفس المراجعة، ولا تتكرر).',
      );
    }
    if (e is StateError && e.message.contains('Saved checkout changed')) {
      return text(
        'The saved payment on this till changed. Close and review again.',
        'تغيّر الدفع المحفوظ على هذا الجهاز. أغلق وراجع مرة أخرى.',
      );
    }
    if (e is! ApiException) {
      return text(
        'Review not confirmed. Close, refresh and check the order.',
        'لم يتم تأكيد المراجعة. أغلق وحدّث وتحقق من الطلب.',
      );
    }
    if (e.isNetwork || (e.statusCode ?? 0) >= 500) {
      return text(
        'No answer from the server; the result is not confirmed. Enter the PIN and tap Confirm again (the same review is sent, never twice).',
        'لا يوجد رد من الخادم؛ النتيجة غير مؤكدة. أدخل الرمز واضغط تأكيد مرة أخرى (تُرسل نفس المراجعة، ولا تتكرر).',
      );
    }
    return switch (e.code) {
      'invalid_pin' => text(
        'Manager PIN not accepted. Enter it again.',
        'لم يُقبل رمز المشرف. أدخله مرة أخرى.',
      ),
      'gps_required' => text(
        'Location is needed to record a payment here. Turn on location, then tap Confirm again.',
        'الموقع مطلوب لتسجيل الدفع هنا. شغّل الموقع ثم اضغط تأكيد مرة أخرى.',
      ),
      'payment_refused' => text(
        'The payment was refused: ${e.message}',
        'تم رفض الدفع: ${e.message}',
      ),
      'order_not_unpaid' => text(
        'This order is already paid or closed. Refresh the list.',
        'هذا الطلب مدفوع أو مغلق بالفعل. حدّث القائمة.',
      ),
      'amount_mismatch' => text(
        'The bill total changed. Close, refresh and review again.',
        'تغيّر إجمالي الفاتورة. أغلق وحدّث وراجع مرة أخرى.',
      ),
      'charge_already_claimed' => text(
        'A payment is in progress. Wait for its result.',
        'توجد عملية دفع جارية. انتظر نتيجتها.',
      ),
      'payment_already_recorded' => text(
        'A payment is already recorded for this order. Ask the admin to check the reconciliation queue.',
        'يوجد دفع مسجل لهذا الطلب. اطلب من المسؤول مراجعة قائمة التسوية.',
      ),
      'nothing_to_review' => text(
        'There is no payment to review for this order. Refresh the list.',
        'لا يوجد دفع لمراجعته لهذا الطلب. حدّث القائمة.',
      ),
      'idempotency_conflict' => text(
        'This review was already sent with different details. Close and review again.',
        'أُرسلت هذه المراجعة سابقاً بتفاصيل مختلفة. أغلق وراجع مرة أخرى.',
      ),
      _ => text(
        'This order cannot be reviewed now. Close and refresh the list.',
        'لا يمكن مراجعة هذا الطلب الآن. أغلق وحدّث القائمة.',
      ),
    };
  }

  bool _retryable(Object e) =>
      e is PaymentReviewNotSaved ||
      (e is ApiException &&
          (e.isNetwork ||
              (e.statusCode ?? 0) >= 500 ||
              e.code == 'invalid_pin' ||
              e.code == 'gps_required'));

  Future<void> _submit() async {
    final value = evidence;
    if (busy || sent || value == null || value.blocked) return;
    if (taken == null ||
        reference.text.trim().isEmpty ||
        !RegExp(r'^\d{4,8}$').hasMatch(pin.text)) {
      setState(
        () => error = text(
          'Choose what happened, enter the receipt or reference number and the manager PIN.',
          'اختر ما حدث، وأدخل رقم الإيصال أو المرجع ورمز المشرف.',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      sent = true;
      frozen = true;
      error = null;
    });
    try {
      final result = await widget.gateway
          .reviewPayment(widget.order.uuid, value, {
            'client_request_id': requestId,
            'decision': taken! ? 'paid' : 'not_paid',
            if (taken!) 'method': method,
            if (taken!) 'amount_baisas': widget.order.total,
            'reference': reference.text.trim(),
            'pin': pin.text,
            if (value.saved.isNotEmpty) 'local_attempt_ids': value.attemptIds,
            if (value.saved.isNotEmpty) 'local_summary': value.summary,
          });
      if (mounted) setState(() => done = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _error(e);
          if (_retryable(e)) sent = false;
        });
      }
    } finally {
      pin.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    pin.dispose();
    reference.dispose();
    super.dispose();
  }

  Widget _choice(bool value, String title, String detail, String key) =>
      ListTile(
        key: ValueKey(key),
        contentPadding: EdgeInsets.zero,
        selected: taken == value,
        enabled: !busy && !frozen,
        leading: Icon(
          taken == value ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        onTap: () => setState(() => taken = value),
        title: Text(title),
        subtitle: Text(detail),
      );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final value = evidence;
    final result = done;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          text(
            'Payment review · ${order.reference}',
            'مراجعة الدفع · ${order.reference}',
          ),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy) const LinearProgressIndicator(),
                if (result != null)
                  Text(
                    result['decision'] == 'paid'
                        ? text(
                            'Recorded as paid. Receipt ${result['receipt_number'] ?? result['temp_reference'] ?? order.reference}.',
                            'تم التسجيل كمدفوع. الإيصال ${result['receipt_number'] ?? result['temp_reference'] ?? order.reference}.',
                          )
                        : text(
                            'Recorded: no money taken. The order can now be paid again or cancelled.',
                            'تم التسجيل: لم يُستلم أي مبلغ. يمكن الآن دفع الطلب مرة أخرى أو إلغاؤه.',
                          ),
                    key: const ValueKey('quick-payment-review-done'),
                  )
                else if (value != null) ...[
                  Text(
                    '${text('Bill total', 'إجمالي الفاتورة')}: ${money(order.total)}',
                  ),
                  Text(
                    '${text('Server', 'الخادم')}: ${QuickCopy(widget.arabic).state(order.charge, order.session)}',
                  ),
                  if (value.saved.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(text('Saved on this till:', 'محفوظ على هذا الجهاز:')),
                    for (final e in value.saved)
                      for (final line in _lines(e))
                        Text(
                          '• $line',
                          key: const ValueKey('quick-payment-review-evidence'),
                        ),
                  ],
                  if (value.blocked)
                    Text(
                      text(
                        'A payment for this order is still open on this till. Use Check payment result first.',
                        'لا يزال دفع هذا الطلب مفتوحاً على هذا الجهاز. استخدم «التحقق من نتيجة الدفع» أولاً.',
                      ),
                      key: const ValueKey('quick-payment-review-blocked'),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    Text(
                      text(
                        'Check the cash drawer or the bank app, then choose:',
                        'تحقق من درج النقد أو تطبيق البنك، ثم اختر:',
                      ),
                    ),
                    _choice(
                      true,
                      text('Money was taken', 'تم استلام المبلغ'),
                      text(
                        'Record ${money(order.total)} as paid, like a normal payment.',
                        'تسجيل ${money(order.total)} كمدفوع، مثل الدفع العادي.',
                      ),
                      'quick-payment-review-taken',
                    ),
                    _choice(
                      false,
                      text('No money was taken', 'لم يتم استلام أي مبلغ'),
                      text(
                        'Clear the stuck payment. The order can be paid again or cancelled.',
                        'مسح الدفع العالق. يمكن دفع الطلب مرة أخرى أو إلغاؤه.',
                      ),
                      'quick-payment-review-not-taken',
                    ),
                    if (taken == true)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in const ['cash', 'card'])
                            ChoiceChip(
                              key: ValueKey('quick-payment-review-$m'),
                              label: Text(
                                m == 'cash'
                                    ? text('Cash', 'نقداً')
                                    : text(
                                        'Card (bank will confirm)',
                                        'بطاقة (يؤكدها البنك)',
                                      ),
                              ),
                              selected: method == m,
                              onSelected: busy || frozen
                                  ? null
                                  : (_) => setState(() => method = m),
                            ),
                        ],
                      ),
                    TextField(
                      key: const ValueKey('quick-payment-review-reference'),
                      controller: reference,
                      enabled: !busy && !frozen,
                      maxLength: 64,
                      decoration: InputDecoration(
                        labelText: text(
                          'Receipt or reference number (required)',
                          'رقم الإيصال أو المرجع (مطلوب)',
                        ),
                      ),
                    ),
                    TextField(
                      key: const ValueKey('quick-payment-review-pin'),
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
                ],
                if (error != null)
                  Text(
                    error!,
                    key: const ValueKey('quick-payment-review-error'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (result != null)
            FilledButton(
              key: const ValueKey('quick-payment-review-close-done'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(text('Done', 'تم')),
            )
          else ...[
            TextButton(
              key: const ValueKey('quick-payment-review-close'),
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: Text(text('Close', 'إغلاق')),
            ),
            FilledButton(
              key: const ValueKey('quick-payment-review-confirm'),
              onPressed: busy || sent || value == null || value.blocked
                  ? null
                  : _submit,
              child: Text(text('Confirm review', 'تأكيد المراجعة')),
            ),
          ],
        ],
      ),
    );
  }
}
