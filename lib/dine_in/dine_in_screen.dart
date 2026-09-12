import 'dart:async';
import 'package:flutter/material.dart';
import '../qr_quick/qr_quick_models.dart';
import '../qr_quick/qr_quick_screen.dart';
import 'dine_in_controller.dart';
import 'dine_in_models.dart';

String dineInText(bool ar, String key) {
  const values = {
    'title': ['Dine-In', 'داخل المطعم'],
    'add': ['Add items', 'إضافة أصناف'],
    'send': ['Send round', 'إرسال الجولة'],
    'pay': ['Proceed to pay', 'المتابعة للدفع'],
    'refresh': [
      'Refresh the table before continuing.',
      'حدّث الطاولة قبل المتابعة.',
    ],
    'uncertain': [
      'The round is saved. Retry the same request; do not enter it again.',
      'الجولة محفوظة. أعد محاولة نفس الطلب ولا تدخله مجدداً.',
    ],
    'recovery': [
      'This seating changed. The saved request needs reconciliation before another send or payment.',
      'تغيرت الجلسة. يجب التحقق من الطلب المحفوظ قبل إرسال جديد أو دفع.',
    ],
    'storage': [
      'Cannot read the saved request. Do not clear app data.',
      'تعذرت قراءة الطلب المحفوظ. لا تمسح بيانات التطبيق.',
    ],
    'retry': ['Retry saved round', 'إعادة محاولة الجولة المحفوظة'],
    'added': [
      'Round received on this bill.',
      'تم استلام الجولة على هذه الفاتورة.',
    ],
    'held': [
      'Round needs review. Unavailable items are not charged.',
      'تحتاج الجولة للمراجعة. لا تُحتسب الأصناف غير المتاحة.',
    ],
    'changed': [
      'The bill changed. Review it before sending.',
      'تغيرت الفاتورة. راجعها قبل الإرسال.',
    ],
    'bill_unpaid': [
      'Reopen the bill before adding items.',
      'أعد فتح الفاتورة قبل إضافة أصناف.',
    ],
    'bill_terminal': [
      'This bill is already closed.',
      'هذه الفاتورة مغلقة بالفعل.',
    ],
    'confirm': ['Confirm round', 'تأكيد الجولة'],
    'reject': ['Reject round', 'رفض الجولة'],
    'reopen': ['Reopen for more rounds', 'إعادة الفتح لجولات إضافية'],
    'clear': ['Clear empty seating', 'إخلاء الجلسة الفارغة'],
    'occupied': ['Occupied', 'مشغولة'],
    'free': ['Free', 'متاحة'],
    'round': ['Round', 'الجولة'],
    'staff': ['Staff', 'الموظف'],
    'customer': ['Customer', 'العميل'],
    'accepted': ['Accepted', 'مقبولة'],
    'rejected': ['Not accepted', 'غير مقبولة'],
    'pending_confirmation': ['Awaiting confirmation', 'بانتظار التأكيد'],
    'pricing': [
      'New items only. The server sets prices; existing bill items stay unchanged.',
      'أصناف جديدة فقط. يحدد الخادم الأسعار وتبقى أصناف الفاتورة الحالية دون تغيير.',
    ],
    'discard': ['Discard unsent items?', 'تجاهل الأصناف غير المرسلة؟'],
    'cancel': ['Cancel', 'إلغاء'],
    'leave': ['Discard and leave', 'تجاهل ومغادرة'],
    'staff_pay': [
      'Staff-only bill: use its existing staff checkout. No QR payment claim is available.',
      'فاتورة موظف فقط: استخدم صفحة الدفع الأصلية لها. لا يتوفر حجز دفع QR.',
    ],
    'orphan': [
      'This bill needs staff reconciliation; do not open another bill for this table.',
      'تحتاج هذه الفاتورة للتحقق؛ لا تفتح فاتورة أخرى لهذه الطاولة.',
    ],
    'held_line': [
      'Unavailable — excluded when confirming',
      'غير متاح — يُستبعد عند التأكيد',
    ],
    'total': ['Bill total', 'إجمالي الفاتورة'],
    'print_failed': [
      'Round received; kitchen print needs attention. Retry its print, not the order.',
      'تم استلام الجولة؛ تحقق من طباعة المطبخ. أعد الطباعة وليس الطلب.',
    ],
    'print': ['Retry kitchen print', 'إعادة طباعة المطبخ'],
  };
  return values[key]?[ar ? 1 : 0] ?? key;
}

/// Canonical table/bill host. No PosController, cart conversion or tender logic.
class DineInScreen extends StatefulWidget {
  const DineInScreen({
    super.key,
    required this.createController,
    required this.catalogue,
    required this.label,
    required this.onPay,
    this.arabic = false,
    this.writesAllowed = true,
    this.localDraftBlocked = false,
    this.onCombine,
  });
  final Future<DineInController> Function() createController;
  final List<QuickProduct> Function() catalogue;
  final String label;
  final Future<void> Function(String) onPay;
  final Future<void> Function()? onCombine;
  final bool arabic, writesAllowed, localDraftBlocked;
  @override
  State<DineInScreen> createState() => _DineInScreenState();
}

class _DineInScreenState extends State<DineInScreen>
    with WidgetsBindingObserver {
  DineInController? controller;
  Timer? timer;
  bool foreground = true, childOpen = false, leaving = false;
  String? error;
  String? draftSeating, draftBill;
  final drafts = <(String, QrQuickLine)>[];
  String text(String key) => dineInText(widget.arabic, key);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    foreground = state == null || state == AppLifecycleState.resumed;
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final c = await widget.createController();
      if (!mounted) {
        c.dispose();
        return;
      }
      controller = c;
      c.addListener(_changed);
      c.setForeground(foreground);
      await c.start();
      if (mounted) _schedule();
    } catch (_) {
      if (mounted) setState(() => error = 'storage');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _schedule() {
    timer?.cancel();
    if (!foreground || childOpen || !mounted) return;
    timer = Timer(const Duration(seconds: 10), () async {
      await controller?.refresh();
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    controller?.setForeground(foreground && !childOpen);
    if (foreground && !childOpen) unawaited(controller?.refresh());
    _schedule();
  }

  Future<void> _leave() async {
    if (controller?.busy == true || childOpen) return;
    if (drafts.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(text('discard')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(text('leave')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _pick() async {
    final c = controller!;
    if (!c.canAdd || childOpen) return;
    final seating = c.detail!.seatingUuid, bill = c.detail!.billUuid;
    childOpen = true;
    _schedule();
    final picked = await pickStaffRoundItem(
      context,
      widget.catalogue(),
      arabic: widget.arabic,
    );
    if (!mounted) return;
    childOpen = false;
    if (picked != null) {
      setState(() {
        if (drafts.isEmpty) {
          draftSeating = seating;
          draftBill = bill;
        }
        drafts.add(picked);
      });
    }
    await c.refresh();
    _schedule();
  }

  Future<void> _combine() async {
    if (childOpen ||
        drafts.isNotEmpty ||
        controller?.busy == true ||
        controller?.pending != null) {
      return;
    }
    childOpen = true;
    controller?.setForeground(false);
    _schedule();
    try {
      await widget.onCombine!();
    } finally {
      childOpen = false;
      if (mounted) {
        controller?.removeListener(_changed);
        controller?.dispose();
        controller = null;
        await _start();
      }
    }
  }

  Future<void> _send() async {
    final c = controller!;
    final ok = await c.add(
      drafts.map((d) => d.$2).toList(),
      expectedSeating: draftSeating,
      expectedBill: draftBill,
    );
    if (mounted && (ok || c.pending != null)) setState(drafts.clear);
  }

  Future<void> _pay() async {
    final c = controller!;
    if (!c.canPay || drafts.isNotEmpty || childOpen) return;
    final uuid = c.detail!.billUuid!;
    childOpen = true;
    c.setForeground(false);
    _schedule();
    try {
      await widget.onPay(uuid);
    } finally {
      childOpen = false;
      if (mounted) {
        c.setForeground(foreground);
        await c.refresh();
        _schedule();
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller?.removeListener(_changed);
    controller?.dispose();
    super.dispose();
  }

  String money(Object? amount) =>
      amount is int ? 'OMR ${(amount / 1000).toStringAsFixed(3)}' : '—';
  Widget note(String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text(key)),
  );
  @override
  Widget build(BuildContext context) {
    final c = controller, detail = c?.detail;
    final enabled =
        c?.available == true && !widget.localDraftBlocked && !childOpen;
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Directionality(
        textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          key: const ValueKey('unified-dine-in'),
          appBar: AppBar(
            leading: IconButton(
              onPressed: _leave,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text('${text('title')} · ${widget.label}'),
            actions: [
              IconButton(
                key: const ValueKey('dine-refresh'),
                onPressed: c?.busy == true ? null : () => c?.refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (c == null || c.busy) const LinearProgressIndicator(),
              if (error != null) note(error!),
              if (c?.stale == true) note('refresh'),
              if (c?.notice != null) note(c!.notice!),
              if (widget.onCombine != null)
                OutlinedButton(
                  key: const ValueKey('dine-combine'),
                  onPressed:
                      c?.busy == true ||
                          c?.pending != null ||
                          drafts.isNotEmpty ||
                          childOpen
                      ? null
                      : _combine,
                  child: Text(
                    widget.arabic
                        ? 'مراجعة دمج فاتورة محلية / استعادة'
                        : 'Review local bill combine / recovery',
                  ),
                ),
              if (widget.localDraftBlocked || c?.hasLocalConflict == true)
                note(
                  widget.arabic
                      ? 'يوجد طلب محلي غير مرسل. عالجه أولاً دون إنشاء فاتورة ثانية.'
                      : 'A local draft is unresolved. Resolve it first without creating a second bill.',
                ),
              if (detail != null) ...[
                Text(
                  '${widget.label} · ${text(detail.occupied ? 'occupied' : 'free')}',
                  key: const ValueKey('dine-occupancy'),
                ),
                Text(detail.reference, key: const ValueKey('dine-reference')),
                if (detail.orphaned) note('orphan'),
                if (detail.bill != null) ...[
                  Text(
                    '${text('total')}: ${money(detail.bill!['grand_total_baisas'])}',
                    key: const ValueKey('dine-total'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  for (final raw in detail.bill!['items'] as List)
                    _line(tableMap(raw)),
                ],
                for (final round in detail.rounds)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${text('round')} ${round['round_no']} · ${text(round['entered_by'] as String)} · ${text(round['status'] as String)}',
                            key: ValueKey('dine-round-${round['id']}'),
                          ),
                          for (final line in round['priced_lines'] as List)
                            _line(tableMap(line)),
                          if (round['status'] == 'accepted' &&
                              round['kitchen_printed_at'] == null &&
                              c?.printAccepted != null)
                            TextButton(
                              key: ValueKey('dine-print-${round['id']}'),
                              onPressed: enabled
                                  ? () => c!.retryPrint(round['id'] as int)
                                  : null,
                              child: Text(text('print')),
                            ),
                          if (round['status'] == 'pending_confirmation')
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton(
                                  key: ValueKey('dine-confirm-${round['id']}'),
                                  onPressed: enabled && drafts.isEmpty
                                      ? () =>
                                            c!.review(round['id'] as int, true)
                                      : null,
                                  child: Text(text('confirm')),
                                ),
                                OutlinedButton(
                                  key: ValueKey('dine-reject-${round['id']}'),
                                  onPressed: enabled && drafts.isEmpty
                                      ? () =>
                                            c!.review(round['id'] as int, false)
                                      : null,
                                  child: Text(text('reject')),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (c?.pending != null) ...[
                note('uncertain'),
                Text('Table #${c!.pending!.tableId}'),
                FilledButton(
                  key: const ValueKey('dine-retry'),
                  onPressed: c.busy ? null : c.retry,
                  child: Text(text('retry')),
                ),
              ] else if (detail != null) ...[
                note('pricing'),
                for (var i = 0; i < drafts.length; i++)
                  ListTile(
                    title: Text('${drafts[i].$2.quantity} × ${drafts[i].$1}'),
                    trailing: IconButton(
                      key: ValueKey('dine-remove-$i'),
                      onPressed: c?.busy == true
                          ? null
                          : () => setState(() => drafts.removeAt(i)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('dine-add'),
                      onPressed:
                          enabled &&
                              widget.writesAllowed &&
                              c!.canAdd &&
                              drafts.length < 50
                          ? _pick
                          : null,
                      child: Text(text('add')),
                    ),
                    FilledButton(
                      key: const ValueKey('dine-send'),
                      onPressed:
                          enabled &&
                              widget.writesAllowed &&
                              c!.canAdd &&
                              drafts.isNotEmpty
                          ? _send
                          : null,
                      child: Text(text('send')),
                    ),
                    if (detail.qrBill && !detail.canAppend)
                      OutlinedButton(
                        key: const ValueKey('dine-reopen'),
                        onPressed: enabled && drafts.isEmpty ? c!.reopen : null,
                        child: Text(text('reopen')),
                      ),
                    if (detail.qrBill)
                      FilledButton(
                        key: const ValueKey('dine-pay'),
                        onPressed: enabled && c!.canPay && drafts.isEmpty
                            ? _pay
                            : null,
                        child: Text(text('pay')),
                      ),
                    if (detail.occupied && detail.bill == null)
                      OutlinedButton(
                        key: const ValueKey('dine-clear'),
                        onPressed: enabled && drafts.isEmpty ? c!.clear : null,
                        child: Text(text('clear')),
                      ),
                  ],
                ),
                if (detail.bill != null && !detail.qrBill) note('staff_pay'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(Map<String, dynamic> line) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      '${line['qty']} × ${(widget.arabic ? line['product_name_ar'] : null) ?? line['product_name'] ?? '#${line['product_id']}'}',
    ),
    subtitle: Text(
      [
        if (line['notes'] != null && line['notes'] != '') line['notes'],
        for (final raw in (line['addons'] as List? ?? const []))
          tableMap(raw)['name'] ?? tableMap(raw)['add_on_name'],
        if (line['held_reason'] != null) text('held_line'),
        if (line['cancelled_qty'] != null)
          '${widget.arabic ? 'ملغي' : 'Cancelled'}: ${line['cancelled_qty']}',
      ].whereType<String>().join(' · '),
    ),
    trailing: Text(money(line['line_total_baisas'])),
  );
}
