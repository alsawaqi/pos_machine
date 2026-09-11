import 'package:flutter/material.dart';
import 'qr_checkout_controller.dart';
import 'qr_checkout_models.dart';

String checkoutText(BuildContext context, String key) {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  const copy = <String, (String, String)>{
    'title': ('Payment', 'الدفع'),
    'cash': ('Cash', 'نقداً'),
    'card': ('Card', 'بطاقة'),
    'bank': ('Bank POS', 'جهاز البنك'),
    'gift': ('Gift', 'هدية'),
    'tax': ('Tax', 'الضريبة'),
    'comp': ('Comp', 'إعفاء'),
    'cancel': ('Cancel payment', 'إلغاء الدفع'),
    'done': ('Done', 'تم'),
    'manager': ('Manager takeover', 'تسليم للمشرف'),
    'manager_denied': (
      'Manager approval is required.',
      'موافقة المشرف مطلوبة.',
    ),
    'empty': ('No unresolved QR payment.', 'لا توجد دفعة QR معلّقة.'),
    'loading': ('Reserving this bill…', 'جارٍ حجز الفاتورة للدفع…'),
    'busy': (
      'Payment in progress. Do not charge again.',
      'الدفع قيد التنفيذ. لا تأخذ دفعة أخرى.',
    ),
    'paid': ('Payment accepted', 'تم قبول الدفع'),
    'released': ('No new payment recorded', 'لم تُسجّل دفعة جديدة'),
    'pending': (
      'Waiting for the server. Do not take another payment.',
      'بانتظار تأكيد الخادم. لا تأخذ دفعة أخرى.',
    ),
    'retry': ('Check payment result', 'التحقق من نتيجة الدفع'),
    'recovery': (
      'STOP. A previous payment may have been taken. Do not retry the tender. A manager must check the terminal and the bill.',
      'توقف. ربما تم أخذ دفعة سابقة. لا تكرر الدفع. يجب أن يتحقق المشرف من الجهاز والفاتورة.',
    ),
    'release_failed': (
      'The reservation could not be safely released. Do not take payment. Call a manager.',
      'تعذّر تحرير حجز الدفع بأمان. لا تأخذ دفعة. اتصل بالمشرف.',
    ),
    'return_cash': (
      'Return any cash collected. Do not take another payment until this attempt is resolved.',
      'أعد أي نقد تم استلامه. لا تأخذ دفعة أخرى قبل تسوية هذه المحاولة.',
    ),
    'claim_changed': (
      'The reservation changed or expired. No further tender was started.',
      'تغيّر حجز الدفع أو انتهت صلاحيته. لم يبدأ دفع إضافي.',
    ),
    'cancelled': (
      'Payment cancelled. Refresh the order before another attempt.',
      'تم إلغاء الدفع. حدّث الطلب قبل المحاولة مجدداً.',
    ),
    'unavailable': (
      'Checkout is unavailable. No tender was started.',
      'الدفع غير متاح. لم يبدأ تحصيل دفعة.',
    ),
    'frozen': (
      'Server bill — prices and customer are read-only during payment.',
      'فاتورة الخادم — الأسعار والعميل للقراءة فقط أثناء الدفع.',
    ),
    'bank_instruction': (
      'Use the external bank terminal for this amount only. Record approval once. If its result is unclear, choose Unknown.',
      'استخدم جهاز البنك الخارجي لهذا المبلغ فقط. سجّل الموافقة مرة واحدة. إذا كانت النتيجة غير واضحة، اختر غير معروف.',
    ),
    'approved': ('Bank approved', 'وافق البنك'),
    'not_taken': ('No payment taken', 'لم تُؤخذ دفعة'),
    'unknown': ('Result unknown', 'النتيجة غير معروفة'),
    'recovery_link': ('Payment recovery', 'تسوية دفعة معلّقة'),
    'attention': ('Payment needs a manager', 'الدفع يحتاج إلى مشرف'),
    'receipt': ('Receipt', 'الإيصال'),
    'history_receipt': (
      'The receipt is stored with the server order.',
      'الإيصال محفوظ مع الطلب على الخادم.',
    ),
    'split': ('Split payment', 'تقسيم الدفع'),
    'cash_part': ('Cash portion (OMR)', 'الجزء النقدي (ر.ع.)'),
    'remainder': ('Remainder', 'المتبقي'),
    'confirm': ('Proceed', 'متابعة'),
    'amount_error': (
      'Enter a valid amount covering the bill.',
      'أدخل مبلغاً صحيحاً يغطي الفاتورة.',
    ),
  };
  final value = copy[key];
  return value == null
      ? (ar
            ? 'تعذّر حجز الفاتورة. حدّث الطلب أو اتصل بالمشرف.'
            : 'The bill could not be reserved. Refresh the order or call a manager.')
      : ar
      ? value.$2
      : value.$1;
}

Future<CheckoutCapture> confirmCheckoutBank(
  BuildContext context,
  int amount,
) async {
  final state = await showDialog<CheckoutCaptureState>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('qr-bank-confirmation'),
        title: Text(
          '${checkoutText(context, 'bank')} · ${(amount / 1000).toStringAsFixed(3)} OMR',
        ),
        content: Text(checkoutText(context, 'bank_instruction')),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialog, CheckoutCaptureState.cancelled),
            child: Text(checkoutText(context, 'not_taken')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialog, CheckoutCaptureState.uncertain),
            child: Text(checkoutText(context, 'unknown')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialog, CheckoutCaptureState.approved),
            child: Text(checkoutText(context, 'approved')),
          ),
        ],
      ),
    ),
  );
  return CheckoutCapture(state ?? CheckoutCaptureState.uncertain);
}

/// Recovery/route guard only. The ready state hosts the EXISTING payment page.
class QrCheckoutBoundary extends StatefulWidget {
  const QrCheckoutBoundary({
    super.key,
    required this.controller,
    required this.authorizeManager,
    required this.paymentPage,
  });
  final QrCheckoutController controller;
  final Future<bool> Function() authorizeManager;
  final Widget Function(BuildContext, VoidCallback) paymentPage;
  @override
  State<QrCheckoutBoundary> createState() => _QrCheckoutBoundaryState();
}

class _QrCheckoutBoundaryState extends State<QrCheckoutBoundary> {
  bool _exiting = false;
  bool _allowPop = false;
  QrCheckoutController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _exit() async {
    if (_exiting || controller.busy) return;
    _exiting = true;
    try {
      if (controller.phase == CheckoutPhase.ready ||
          controller.attempt?.state == 'releasing') {
        await controller.cancel();
      }
      var canLeave = controller.canLeave;
      if (!canLeave &&
          const [
            CheckoutPhase.attention,
            CheckoutPhase.pending,
          ].contains(controller.phase)) {
        canLeave = await controller.managerTakeover(widget.authorizeManager);
      }
      if (canLeave && mounted) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } finally {
      _exiting = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || controller.canLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _exit();
    },
    child: controller.phase == CheckoutPhase.ready
        ? widget.paymentPage(context, _exit)
        : Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(checkoutText(context, 'title')),
            ),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.busy) const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        controller.reference,
                        key: const ValueKey('qr-checkout-reference'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        checkoutText(context, controller.phase.name),
                        key: const ValueKey('qr-checkout-status'),
                        textAlign: TextAlign.center,
                      ),
                      if (controller.notice case final notice?)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            checkoutText(context, notice),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (controller.phase == CheckoutPhase.paid) ...[
                        const SizedBox(height: 16),
                        Text(
                          '${checkoutText(context, 'receipt')}: ${controller.attempt?.receiptNumber ?? controller.reference}',
                        ),
                        Text(checkoutText(context, 'history_receipt')),
                      ],
                      const SizedBox(height: 20),
                      if (controller.phase == CheckoutPhase.pending)
                        FilledButton(
                          key: const ValueKey('qr-checkout-retry'),
                          onPressed: controller.busy
                              ? null
                              : controller.retryAcknowledgement,
                          child: Text(checkoutText(context, 'retry')),
                        ),
                      if (!controller.busy)
                        TextButton(
                          key: const ValueKey('qr-checkout-exit'),
                          onPressed: _exit,
                          child: Text(
                            checkoutText(
                              context,
                              controller.canLeave ? 'done' : 'manager',
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

Future<List<CheckoutTender>?> checkoutMixedPlan(
  BuildContext context,
  int total,
) => showDialog<List<CheckoutTender>>(
  context: context,
  builder: (_) => _CheckoutSplitPlan(total: total),
);

class _CheckoutSplitPlan extends StatefulWidget {
  const _CheckoutSplitPlan({required this.total});
  final int total;
  @override
  State<_CheckoutSplitPlan> createState() => _CheckoutSplitPlanState();
}

class _CheckoutSplitPlanState extends State<_CheckoutSplitPlan> {
  final cash = TextEditingController();
  String method = 'card';
  String? error;
  @override
  void dispose() {
    cash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(checkoutText(context, 'split')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('qr-split-cash'),
          controller: cash,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: checkoutText(context, 'cash_part'),
          ),
        ),
        DropdownButton<String>(
          value: method,
          items: [
            DropdownMenuItem(
              value: 'card',
              child: Text(checkoutText(context, 'card')),
            ),
            DropdownMenuItem(
              value: 'bank_pos',
              child: Text(checkoutText(context, 'bank')),
            ),
          ],
          onChanged: (value) => setState(() => method = value!),
        ),
        if (error != null) Text(error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(checkoutText(context, 'cancel')),
      ),
      FilledButton(
        onPressed: () {
          final value = double.tryParse(cash.text);
          final baisas = value != null && value.isFinite
              ? (value * 1000).round()
              : 0;
          if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(cash.text) ||
              baisas <= 0 ||
              baisas >= widget.total) {
            setState(() => error = checkoutText(context, 'amount_error'));
            return;
          }
          Navigator.pop(context, [
            CheckoutTender('cash', baisas),
            CheckoutTender(method, widget.total - baisas),
          ]);
        },
        child: Text(checkoutText(context, 'confirm')),
      ),
    ],
  );
}
