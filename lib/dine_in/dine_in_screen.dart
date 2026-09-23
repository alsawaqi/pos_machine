import 'table_loyalty.dart';
import '../table_cancellation/table_bill_cancellation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../order_workspace/current_order_workspace.dart';
import '../qr_quick/qr_quick_models.dart';
import '../qr_quick/qr_quick_screen.dart';
import 'dine_in_controller.dart';
import 'dine_in_models.dart';
import 'dine_in_store.dart';

String dineInText(bool ar, String key) {
  final loyaltyCode = key.startsWith('adjust_refused:')
      ? key.substring('adjust_refused:'.length)
      : key;
  if (loyaltyCode.startsWith('loyalty_') ||
      const {
        'loyalty',
        'approval_required',
        'validation_failed',
      }.contains(loyaltyCode)) {
    return loyaltyText(ar, loyaltyCode);
  }
  if (key.startsWith('cancel_refused:')) {
    return tableCancelText(key.substring('cancel_refused:'.length), ar);
  }
  if (key.startsWith('cancel_waste:')) {
    return ar
        ? 'تم تسجيل الهدر: ${key.substring(13)} ر.ع.'
        : 'Waste recorded: OMR ${key.substring(13)}';
  }
  const values = {
    'title': ['Dine-In', 'داخل المطعم'],
    'discount': ['Discount', 'خصم'],
    'comp': ['Complimentary', 'ضيافة'],
    'replace': ['Replace', 'استبدال'],
    'detach_customer': ['Remove customer', 'إزالة العميل'],
    'pending_adjustment': [
      'Resolve the saved request before adjusting this bill.',
      'تحقق من الطلب المحفوظ قبل تعديل الفاتورة.',
    ],
    'adjustment_review': [
      'Confirm or reject pending rounds before adjusting this bill.',
      'أكد أو ارفض الجولات المعلقة قبل تعديل الفاتورة.',
    ],
    'adjustment_unsent': [
      'Send or remove unsent items and finish sync before adjusting the bill.',
      'أرسل أو أزل الأصناف غير المرسلة وأكمل المزامنة قبل تعديل الفاتورة.',
    ],
    'bill_reserved': [
      'Reopen the bill and resolve its payment result before adjusting it.',
      'أعد فتح الفاتورة وتحقق من نتيجة الدفع قبل تعديلها.',
    ],
    'bill_missing': [
      'Open a table bill before adjusting it.',
      'افتح فاتورة الطاولة قبل تعديلها.',
    ],
    'adjustment_exceeds_bill': [
      'The adjustment must leave a positive amount to pay. Check the selected quantity.',
      'يجب أن يترك التعديل مبلغاً موجباً للدفع. تحقق من الكمية المحددة.',
    ],
    'full_comp_not_supported': [
      'Whole-bill complimentary payment is not supported. Leave an amount to pay.',
      'ضيافة الفاتورة كاملة غير متاحة. يجب إبقاء مبلغ للدفع.',
    ],
    'comp_cap_exceeded': [
      'Choose an active complimentary reason and stay within its limit.',
      'اختر سبب ضيافة نشطاً والتزم بحده.',
    ],
    'discount_rule_not_applicable': [
      'This discount is not available for this branch now.',
      'هذا الخصم غير متاح لهذا الفرع الآن.',
    ],
    'approval_required': [
      'Manager approval is required.',
      'موافقة المدير مطلوبة.',
    ],
    'customer_not_found': [
      'The customer was not found for this merchant.',
      'لم يتم العثور على العميل لدى هذا التاجر.',
    ],
    'discard_adjustment': [
      'Discard saved adjustment',
      'استبعاد التعديل المحفوظ',
    ],
    'discard_adjustment_explain': [
      'Retry first. If the server remains unreachable, a manager can archive this request locally. This does not undo a server adjustment or confirm its result. Refresh and check the bill before applying another adjustment.',
      'أعد المحاولة أولاً. إذا تعذر الوصول للخادم، يمكن للمدير أرشفة الطلب محلياً. هذا لا يلغي تعديل الخادم ولا يؤكد نتيجته. حدّث الفاتورة وتحقق منها قبل تعديل آخر.',
    ],
    'adjustment_discarded': [
      'Saved adjustment archived. Refresh and check the bill before another adjustment.',
      'تمت أرشفة التعديل المحفوظ. حدّث الفاتورة وتحقق منها قبل تعديل آخر.',
    ],
    'adjustment_replayed': [
      'The saved adjustment was already applied.',
      'تم تطبيق التعديل المحفوظ مسبقاً.',
    ],
    'retry_adjustment': [
      'Retry saved adjustment',
      'إعادة محاولة التعديل المحفوظ',
    ],
    'adjustment_stale': [
      'Calculated before the last change — re-apply to update.',
      'تم الحساب قبل آخر تغيير — أعد التطبيق للتحديث.',
    ],
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
    'clear': ['Clear empty session', 'إخلاء الجلسة الفارغة'],
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
  if (key.startsWith('adjust_refused:')) {
    final code = key.substring('adjust_refused:'.length);
    const adjustmentCodes = {
      'bill_missing',
      'bill_reserved',
      'adjustment_exceeds_bill',
      'full_comp_not_supported',
      'comp_cap_exceeded',
      'discount_rule_not_applicable',
      'approval_required',
      'customer_not_found',
    };
    // Unknown server codes must never resolve to unrelated UI captions.
    if (adjustmentCodes.contains(code)) {
      return values[code]![ar ? 1 : 0];
    }
    return (ar
        ? 'تعذر تنفيذ التعديل ($code). حدّث الفاتورة قبل المحاولة مجدداً.'
        : 'Adjustment refused ($code). Refresh the bill before trying again.');
  }
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
    this.onCorrectHeldRound,
    this.onEditLocalItems,
    this.hasHeldLocalRound,
    this.workspace,
    this.onVoid,
    this.approveCancellation,
    this.approveAdjustmentDiscard,
    this.pickAdjustment,
    this.onCombine,
    this.onRecover,
    this.localDraftBlockedNow,
  });
  final Future<Map<String, dynamic>?> Function(DineInDetail, String)?
  pickAdjustment;
  final Future<DineInController> Function() createController;
  final List<QuickProduct> Function() catalogue;
  final String label;
  final Future<void> Function(String) onPay;
  final Future<void> Function()? onCombine;
  final Future<void> Function()? onRecover;
  final Future<void> Function()? onCorrectHeldRound;
  final Future<void> Function()? onEditLocalItems;
  final bool Function()? hasHeldLocalRound;
  final bool Function()? localDraftBlockedNow;
  final bool arabic, writesAllowed, localDraftBlocked;
  final CurrentOrderWorkspace? workspace;
  final Future<bool> Function(String uuid)? onVoid;
  final Future<Map<String, dynamic>?> Function()? approveCancellation;
  final Future<bool> Function()? approveAdjustmentDiscard;
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
    widget.workspace?.attach(
      this,
      pick: (product) => _pick(product),
      leave: _leave,
      pay: _pay,
    );
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
      if (c.store case final DineInDraftStore store) {
        final saved = await store.loadDraft(c.tableId);
        if (!mounted) {
          c.dispose();
          return;
        }
        if (saved != null) {
          draftSeating = saved['seating_uuid'] as String?;
          draftBill = saved['bill_uuid'] as String?;
          drafts
            ..clear()
            ..addAll(
              (saved['lines'] as List).map((raw) {
                final row = tableMap(raw);
                return (
                  row['label'] as String,
                  QrQuickLine.fromJson(tableMap(row['line'])),
                );
              }),
            );
        }
      }
      c.addListener(_changed);
      c.setForeground(foreground);
      await c.start();
      if (mounted) _schedule();
    } catch (_) {
      if (mounted) setState(() => error = 'storage');
    }
  }

  Future<bool> _persistDrafts() async {
    final c = controller;
    if (c == null) return false;
    if (c.store case final DineInDraftStore store) {
      try {
        await store.saveDraft(
          c.tableId,
          drafts.isEmpty
              ? null
              : {
                  'seating_uuid': draftSeating,
                  'bill_uuid': draftBill,
                  'lines': [
                    for (final d in drafts)
                      {'label': d.$1, 'line': d.$2.toJson()},
                  ],
                },
        );
        if (error == 'storage') error = null;
      } catch (_) {
        if (mounted) setState(() => error = 'storage');
        _publish();
        return false;
      }
    }
    return true;
  }

  void _changed() {
    if (mounted) setState(() {});
    _publish();
  }

  @override
  void didUpdateWidget(covariant DineInScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.writesAllowed != widget.writesAllowed ||
        oldWidget.localDraftBlocked != widget.localDraftBlocked) {
      _publish();
    }
  }

  void _publish() {
    final c = controller;
    final blocked =
        widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked;
    widget.workspace?.publish(
      this,
      order: c?.detail?.bill,
      stale: c?.stale ?? true,
      canAdd:
          !blocked &&
          !childOpen &&
          widget.writesAllowed &&
          c?.canAdd == true &&
          drafts.length < 50,
      canPay:
          !blocked &&
          !childOpen &&
          (drafts.isEmpty
              ? c?.canPay == true
              : widget.workspace?.mainCart == true &&
                    _editDrafts &&
                    _validDrafts &&
                    c?.detail?.pendingReview != true),
      cartControls: _cartControls,
    );
  }

  void _schedule() {
    _publish();
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
      setState(drafts.clear);
      if (!await _persistDrafts() || !mounted) return;
    }
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.workspace != null) {
        widget.workspace!.onExit();
      } else {
        Navigator.pop(context);
      }
    });
  }

  bool get _canVoid =>
      widget.workspace != null &&
      widget.onVoid != null &&
      !childOpen &&
      !leaving &&
      drafts.isEmpty &&
      !widget.localDraftBlocked &&
      widget.localDraftBlockedNow?.call() != true &&
      widget.writesAllowed &&
      controller?.available == true &&
      controller?.detail?.billUuid != null &&
      const {
        'open',
        'held',
        'awaiting_payment',
      }.contains(controller?.detail?.bill?['status']);

  Future<void> _void() async {
    if (!_canVoid) return;
    final c = controller!;
    final uuid = c.detail!.billUuid!;
    childOpen = true;
    c.setForeground(false);
    _schedule();
    try {
      if (await widget.onVoid!(uuid) && mounted) widget.workspace!.onExit();
    } finally {
      if (mounted) {
        childOpen = false;
        c.setForeground(foreground);
        await c.refresh();
        if (mounted) _schedule();
      }
    }
  }

  Future<void> _pick([QuickProduct? product]) async {
    final c = controller!;
    if (!c.canAdd || childOpen) return;
    if (widget.workspace?.mainCart == true && product != null) {
      if (!product.available) return;
      await _addDraft(product, const [], null);
      return;
    }
    final seating = c.detail!.seatingUuid, bill = c.detail!.billUuid;
    childOpen = true;
    _schedule();
    final picked = product != null
        ? await pickStaffRoundProduct(context, product, arabic: widget.arabic)
        : await pickStaffRoundItem(
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
    await _persistDrafts();
    await c.refresh();
    _schedule();
  }

  Future<void> _combine() => _openLocalAction(widget.onCombine!);
  Future<void> _openLocalAction(Future<void> Function() action) async {
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
      await action();
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

  bool get _editDrafts =>
      controller?.canAdd == true &&
      (drafts.isEmpty ||
          (draftSeating == controller?.detail?.seatingUuid &&
              draftBill == controller?.detail?.billUuid)) &&
      !childOpen &&
      !leaving &&
      widget.writesAllowed &&
      !(widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked);
  QuickProduct? _product(int id) =>
      widget.catalogue().where((p) => p.id == id).firstOrNull;

  Future<void> _addDraft(
    QuickProduct product,
    List<int> addons,
    String? notes, {
    int qty = 1,
  }) async {
    if (!_editDrafts) return;
    final selected = [...addons]..sort();
    final index = drafts.indexWhere((d) {
      final existing = [...d.$2.addonIds]..sort();
      return d.$2.productId == product.id &&
          existing.join(',') == selected.join(',') &&
          (d.$2.notes ?? '') == (notes ?? '');
    });
    final quantity = qty + (index < 0 ? 0 : drafts[index].$2.quantity);
    if (quantity > 99 || (index < 0 && drafts.length >= 50)) return;
    if (drafts.isEmpty) {
      draftSeating = controller!.detail!.seatingUuid;
      draftBill = controller!.detail!.billUuid;
    }
    setState(() {
      final entry = (
        widget.arabic ? product.nameAr : product.name,
        QrQuickLine(product.id, quantity, selected, notes: notes),
      );
      if (index < 0) {
        drafts.add(entry);
      } else {
        drafts[index] = entry;
      }
    });
    await _persistDrafts();
    _publish();
  }

  Map<String, dynamic> _draftRow(int index) {
    final line = drafts[index].$2,
        product = _product(drafts[index].$2.productId);
    final addons = [
      for (final group in product?.groups ?? <QuickGroup>[])
        for (final choice in group.choices)
          if (line.addonIds.contains(choice.id)) choice,
    ];
    return {
      'id': 'draft-$index',
      'draft_index': index,
      'product_id': line.productId,
      'product_name': product?.name ?? drafts[index].$1,
      'product_name_ar': product?.nameAr ?? '',
      'qty': line.quantity,
      'line_total_baisas':
          ((product?.priceBaisas ?? 0) +
              addons.fold<int>(0, (n, a) => n + a.priceBaisas)) *
          line.quantity,
      'notes': line.notes,
      'addons': [
        for (final a in addons)
          {
            'add_on_id': a.id,
            'add_on_name': a.name,
            'add_on_name_ar': a.nameAr,
          },
      ],
    };
  }

  bool get _validDrafts => drafts.every((d) {
    final product = _product(d.$2.productId);
    return product?.available == true &&
        product!.groups.every((g) {
          final count = g.choices
              .where((a) => d.$2.addonIds.contains(a.id))
              .length;
          return count >= g.min && count <= g.max;
        });
  });

  Future<void> _quantity(Map<String, dynamic> row, int qty) async {
    if (row['pending_round_id'] != null) return;
    if (!_editDrafts || qty < 0 || qty > 99) return;
    if (row['draft_index'] case final int index) {
      if (index >= drafts.length) return;
      final old = drafts[index];
      setState(() {
        if (qty == 0) {
          drafts.removeAt(index);
        } else {
          drafts[index] = (
            old.$1,
            QrQuickLine(
              old.$2.productId,
              qty,
              old.$2.addonIds,
              notes: old.$2.notes,
            ),
          );
        }
      });
      await _persistDrafts();
      _publish();
    } else if (qty > (row['qty'] as num)) {
      final product = _product(row['product_id'] as int);
      if (product != null) {
        await _addDraft(
          product,
          [
            for (final a in row['addons'] as List? ?? [])
              if (qrMap(a)['add_on_id'] is int) qrMap(a)['add_on_id'] as int,
          ],
          row['notes'] as String?,
          qty: qty - (row['qty'] as num).toInt(),
        );
      }
    } else if (qty < (row['qty'] as num) &&
        widget.approveCancellation != null) {
      await controller!.cancelLine(
        row,
        (row['qty'] as num).toInt() - qty,
        approve: widget.approveCancellation!,
      );
    }
  }

  Future<void> _customize(Map<String, dynamic> row) async {
    if (row['pending_round_id'] != null) return;
    if (!_editDrafts || widget.workspace?.editOptions == null) {
      return;
    }
    final index = row['draft_index'] as int?;
    if (index == null && widget.approveCancellation == null) return;
    childOpen = true;
    _publish();
    try {
      final changed = await widget.workspace!.editOptions!(row);
      if (mounted &&
          changed != null &&
          index != null &&
          index < drafts.length) {
        setState(() => drafts[index] = (drafts[index].$1, changed));
        await _persistDrafts();
      } else if (mounted && changed != null && index == null) {
        final ok = await controller!.cancelLine(
          row,
          (row['qty'] as num).toInt(),
          approve: widget.approveCancellation!,
        );
        if (mounted && ok) {
          childOpen = false;
          final product = _product(changed.productId);
          if (product != null) {
            await _addDraft(
              product,
              changed.addonIds,
              changed.notes,
              qty: changed.quantity,
            );
          }
        }
      }
    } finally {
      childOpen = false;
      if (mounted) _publish();
    }
  }

  Future<void> _clearCart() async {
    if (!_editDrafts) return;
    final rows =
        widget.workspace?.bill?.groupedItems ?? <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      setState(drafts.clear);
      await _persistDrafts();
      _publish();
      return;
    }
    if (widget.approveCancellation == null) return;
    childOpen = true;
    _publish();
    try {
      final approval = await widget.approveCancellation!();
      if (!mounted || approval == null) return;
      setState(drafts.clear);
      await _persistDrafts();
      for (final row in rows) {
        if (!mounted ||
            !await controller!.cancelLine(
              row,
              (row['qty'] as num).toInt(),
              approve: () async => approval,
            )) {
          break;
        }
      }
    } finally {
      childOpen = false;
      if (mounted) _publish();
    }
  }

  String _heldDescription(Map<String, dynamic> line) {
    final reason = switch (line['held_reason']) {
      'out_of_stock' => widget.arabic ? 'نفد المخزون' : 'Out of stock',
      'addon_selection_invalid' =>
        widget.arabic ? 'اختيار الإضافة غير صالح' : 'Invalid add-on selection',
      'product_unavailable' =>
        widget.arabic ? 'الصنف غير متاح' : 'Item unavailable',
      _ => widget.arabic ? 'تحتاج للمراجعة' : 'Needs review',
    };
    return '${widget.arabic ? 'معلّق — لا يوجد سعر بعد' : 'Held — no price yet'} · $reason';
  }

  List<Widget> _adjustedSummary(Map<String, dynamic> value) {
    final bill = WorkspaceBill(value);
    if ((value['manual_discount_baisas'] as int? ?? 0) == 0 &&
        bill.comp == 0 &&
        bill.customer == null) {
      return [];
    }
    String label(String en, String ar) => widget.arabic ? ar : en;
    return [
      Text('${label('Subtotal', 'المجموع الفرعي')}: ${money(bill.subtotal)}'),
      if (bill.discount > 0)
        Text(
          '${label('Discount', 'الخصم')} ${bill.discountLabel}: −${money(bill.discount)}',
        ),
      if (bill.comp > 0)
        Text(
          '${label('Complimentary', 'الضيافة')} ${bill.compReason}: −${money(bill.comp)}',
        ),
      Text('${label('Tax', 'الضريبة')}: ${money(bill.tax)}'),
      if (bill.adjustmentStale) Text(text('adjustment_stale')),
      if (bill.customer case final customer?)
        Text('${customer['name'] ?? ''} · ${customer['phone'] ?? ''}'),
    ];
  }

  bool get _canAdjust =>
      widget.writesAllowed &&
      widget.pickAdjustment != null &&
      controller?.canAdjust == true &&
      drafts.isEmpty &&
      !childOpen &&
      !(widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked);
  Future<void> _adjust(String kind) async {
    if (!_canAdjust) return;
    await controller!.adjust((detail) => widget.pickAdjustment!(detail, kind));
    if (mounted) _publish();
  }

  WorkspaceCartControls get _cartControls {
    final c = controller, detail = c?.detail;
    final enabled =
        _editDrafts &&
        !(widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked);
    final canReview =
        c?.available == true &&
        !childOpen &&
        drafts.isEmpty &&
        !(widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked);
    return WorkspaceCartControls(
      adjustmentSupported: widget.pickAdjustment != null,
      discount: _canAdjust ? () => _adjust('discount') : null,
      comp: _canAdjust ? () => _adjust('comp') : null,
      customer: _canAdjust ? () => _adjust('customer') : null,
      loyalty: _canAdjust && detail?.bill?['customer'] is Map
          ? () => _adjust('loyalty')
          : null,
      adjustmentBlocked: drafts.isNotEmpty
          ? 'adjustment_unsent'
          : c?.adjustmentBlocked,
      busy: c?.busy == true || childOpen,
      pendingRows: [
        if (detail != null)
          for (final round in detail.rounds)
            if (round['status'] == 'pending_confirmation')
              for (final raw in round['priced_lines'] as List)
                if (!tableLineHeld(tableMap(raw)))
                  {
                    ...tableMap(raw),
                    'pending_round_id': round['id'],
                    'notes': [
                      '${text('pending_confirmation')} — ${round['round_no']}',
                      if (tableMap(raw)['notes'] != null)
                        tableMap(raw)['notes'],
                    ].join(' · '),
                  },
      ],
      pendingTax:
          detail?.rounds
              .where((r) => r['status'] == 'pending_confirmation')
              .fold<int>(0, (sum, r) => sum + (r['tax_baisas'] as int? ?? 0)) ??
          0,
      notices: [
        if (detail != null)
          for (final round in detail.rounds)
            if (round['status'] == 'pending_confirmation')
              for (final raw in round['priced_lines'] as List)
                if (tableLineHeld(tableMap(raw)))
                  '${tableMap(raw)['qty']} × ${(widget.arabic ? tableMap(raw)['product_name_ar'] : null) ?? tableMap(raw)['product_name']} · ${_heldDescription(tableMap(raw))}',
        if ((widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked) ||
            c?.hasLocalConflict == true)
          widget.arabic
              ? 'أكمل إرسال أو إزالة الأصناف المحلية ومزامنتها، ثم أعد فتح الفاتورة.'
              : 'Send or remove unsent local items and finish sync, then reopen the bill.',
        if (detail?.pendingReview == true)
          widget.arabic
              ? 'إجمالي تقديري — الجولة بانتظار التأكيد'
              : 'Estimated total — round awaiting confirmation',

        if (error != null) text(error!),
        if (drafts.isNotEmpty &&
            c?.stale == false &&
            (draftSeating != detail?.seatingUuid ||
                draftBill != detail?.billUuid))
          text('changed'),
        if (c?.stale == true) text('refresh'),
        if (c?.notice != null)
          (c?.pending?.isCancellation == true ||
                      c?.pending?.isAdjustment == true) &&
                  c?.notice == 'uncertain'
              ? (widget.arabic
                    ? 'التعديل محفوظ. أعد محاولة نفس التعديل.'
                    : 'The change is saved. Retry this same change.')
              : text(c!.notice!),
        if (drafts.isNotEmpty && !_validDrafts)
          widget.arabic
              ? 'راجع الإضافات المطلوبة أو الأصناف غير المتاحة'
              : 'Review required add-ons or unavailable items',
      ],
      drafts: [for (final d in drafts) '${d.$2.quantity} × ${d.$1}'],
      draftRows: [for (var i = 0; i < drafts.length; i++) _draftRow(i)],
      quantity: enabled ? _quantity : null,
      customize: enabled ? _customize : null,
      clear: enabled ? _clearCart : null,
      refresh: c?.busy == true
          ? null
          : () async {
              await c?.refresh();
            },
      submit: enabled && drafts.isNotEmpty && _validDrafts ? _send : null,
      retry: c?.pending != null && c?.busy != true
          ? () async {
              await c?.retry();
            }
          : null,
      voidBill: _canVoid ? _void : null,
      actions: [
        if (c?.canDiscardAdjustment == true &&
            widget.approveAdjustmentDiscard != null)
          WorkspaceAction(text('discard_adjustment'), _discardAdjustment),
        if (((widget.localDraftBlockedNow?.call() ??
                    widget.localDraftBlocked) ||
                c?.hasLocalConflict == true) &&
            widget.onEditLocalItems != null)
          WorkspaceAction(
            widget.arabic ? 'تعديل الأصناف المحلية' : 'Edit local items',
            c?.busy != true && c?.pending == null && !childOpen
                ? widget.onEditLocalItems
                : null,
          ),
        if (widget.onCorrectHeldRound != null &&
            controller?.detail?.canAppend == true &&
            (controller?.detail?.heldStaffReview == true ||
                widget.hasHeldLocalRound?.call() == true))
          WorkspaceAction(
            widget.arabic ? 'تصحيح الجولة المعلّقة' : 'Correct held round',
            widget.writesAllowed &&
                    c?.busy != true &&
                    c?.pending == null &&
                    !childOpen
                ? widget.onCorrectHeldRound
                : null,
          ),
        if (detail?.canClearEmpty == true)
          WorkspaceAction(
            text('clear'),
            canReview && widget.writesAllowed ? _clearEmptySession : null,
          ),
        if (detail != null)
          for (final round in detail.rounds)
            if (round['status'] == 'pending_confirmation') ...[
              WorkspaceAction(
                '${text('confirm')} ${round['round_no']}',
                canReview ? () => c!.review(round['id'] as int, true) : null,
              ),
              WorkspaceAction(
                '${text('reject')} ${round['round_no']}',
                canReview ? () => c!.review(round['id'] as int, false) : null,
              ),
            ],
        if (detail?.protectedCheckout == true && detail?.canAppend == false)
          WorkspaceAction(
            text('reopen'),
            c?.available == true && drafts.isEmpty ? c!.reopen : null,
          ),
        if (c?.notice == 'print_failed' && detail != null)
          for (final round in detail.rounds)
            if (round['status'] == 'accepted' &&
                round['kitchen_printed_at'] == null)
              WorkspaceAction(
                text('print'),
                c?.available == true
                    ? () => c!.retryPrint(round['id'] as int)
                    : null,
              ),
      ],
    );
  }

  Future<void> _discardAdjustment() async {
    final c = controller;
    final approve = widget.approveAdjustmentDiscard;
    if (c == null || approve == null || !c.canDiscardAdjustment) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(text('discard_adjustment')),
        content: Text(text('discard_adjustment_explain')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(widget.arabic ? 'رجوع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(text('discard_adjustment')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await c.discardPendingAdjustment(approve);
  }

  Future<void> _send() async {
    final c = controller!;
    if (!await _persistDrafts()) return;
    final ok = await c.add(
      drafts.map((d) => d.$2).toList(),
      expectedSeating: draftSeating,
      expectedBill: draftBill,
    );
    if (mounted && (ok || c.pending != null)) setState(drafts.clear);
    if (mounted) await _persistDrafts();
    if (mounted) _publish();
  }

  Future<void> _pay() async {
    final c = controller!;
    if (widget.workspace?.mainCart == true && drafts.isNotEmpty) {
      if (!_editDrafts || !_validDrafts) return;
      await _send();
      if (!mounted) return;
    }
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
        if (mounted &&
            !c.stale &&
            (c.detail?.occupied == false ||
                const {'paid', 'void'}.contains(c.detail?.bill?['status']))) {
          widget.workspace?.onExit();
        } else {
          _schedule();
        }
      }
    }
  }

  @override
  void dispose() {
    widget.workspace?.detach(this);
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
  Future<void> _clearEmptySession() async {
    final c = controller;
    if (c?.available != true ||
        c?.detail?.canClearEmpty != true ||
        drafts.isNotEmpty ||
        childOpen ||
        widget.localDraftBlocked) {
      return;
    }
    childOpen = true;
    _publish();
    try {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text(text('clear')),
              content: Text(
                widget.arabic
                    ? 'إغلاق الجلسة الفارغة وإتاحة الطاولة؟ لن يتم إلغاء أي طلب.'
                    : 'Close this empty session and free the table? No order will be cancelled.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: Text(text('cancel')),
                ),
                FilledButton(
                  key: const ValueKey('dine-clear-confirm'),
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(text('clear')),
                ),
              ],
            ),
          ) ??
          false;
      if (!mounted || !confirmed) return;
      await c!.clear();
      if (mounted && c.detail?.occupied == false && !c.stale) {
        if (widget.workspace != null) {
          widget.workspace!.onExit();
        } else {
          setState(() => leaving = true);
          Navigator.of(context).pop();
        }
      }
    } finally {
      childOpen = false;
      if (mounted) {
        setState(() {});
        _publish();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, detail = c?.detail;
    final localBlocked =
        widget.localDraftBlockedNow?.call() ?? widget.localDraftBlocked;
    final enabled = c?.available == true && !localBlocked && !childOpen;
    return PopScope(
      canPop: widget.workspace == null && leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Directionality(
        textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: widget.workspace?.mainCart == true
            ? const SizedBox.shrink(key: ValueKey('dine-in-cart-controller'))
            : Scaffold(
                key: const ValueKey('unified-dine-in'),
                appBar: AppBar(
                  leading: IconButton(
                    onPressed: _leave,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  title: Text('${text('title')} · ${widget.label}'),
                  actions: [
                    if (widget.workspace != null && widget.onVoid != null)
                      TextButton.icon(
                        key: const ValueKey('workspace-void'),
                        onPressed: _canVoid ? _void : null,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(
                          widget.arabic
                              ? 'إلغاء فاتورة الطاولة'
                              : 'Cancel table bill',
                        ),
                      ),
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
                    if (widget.onCorrectHeldRound != null &&
                        controller?.detail?.canAppend == true &&
                        (controller?.detail?.heldStaffReview == true ||
                            widget.hasHeldLocalRound?.call() == true))
                      OutlinedButton(
                        key: const ValueKey('dine-correct-held-round'),
                        onPressed:
                            widget.writesAllowed &&
                                c?.busy != true &&
                                c?.pending == null &&
                                !childOpen
                            ? widget.onCorrectHeldRound
                            : null,
                        child: Text(
                          widget.arabic
                              ? 'تصحيح الجولة المعلّقة'
                              : 'Correct held round',
                        ),
                      ),
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
                    if (widget.onRecover != null)
                      OutlinedButton(
                        key: const ValueKey('dine-recover-draft'),
                        onPressed:
                            c?.busy == true ||
                                c?.pending != null ||
                                drafts.isNotEmpty ||
                                childOpen
                            ? null
                            : () => _openLocalAction(widget.onRecover!),
                        child: Text(
                          widget.arabic
                              ? 'استعادة مسودة هذه الفاتورة'
                              : 'Recover this bill draft',
                        ),
                      ),
                    if ((localBlocked || c?.hasLocalConflict == true) &&
                        widget.onEditLocalItems != null)
                      OutlinedButton(
                        key: const ValueKey('dine-edit-local-items'),
                        onPressed:
                            c?.busy != true && c?.pending == null && !childOpen
                            ? widget.onEditLocalItems
                            : null,
                        child: Text(
                          widget.arabic
                              ? 'تعديل الأصناف المحلية'
                              : 'Edit local items',
                        ),
                      ),
                    if (localBlocked || c?.hasLocalConflict == true)
                      note(
                        widget.arabic
                            ? 'يوجد طلب محلي غير مرسل. عالجه أولاً دون إنشاء فاتورة ثانية.'
                            : 'A local draft is unresolved. Resolve it first without creating a second bill.',
                      ),
                    if (widget.pickAdjustment != null && detail?.bill != null)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final kind in [
                            'discount',
                            'comp',
                            'customer',
                            'loyalty',
                          ])
                            TextButton(
                              key: ValueKey('dine-adjust-$kind'),
                              onPressed:
                                  _canAdjust &&
                                      (kind != 'loyalty' ||
                                          detail?.bill?['customer'] is Map)
                                  ? () => _adjust(kind)
                                  : null,
                              child: Text(text(kind)),
                            ),
                        ],
                      ),
                    if (detail != null) ...[
                      Text(
                        '${widget.label} · ${text(detail.occupied ? 'occupied' : 'free')}',
                        key: const ValueKey('dine-occupancy'),
                      ),
                      Text(
                        detail.reference,
                        key: const ValueKey('dine-reference'),
                      ),
                      if (detail.orphaned) note('orphan'),
                      if (detail.bill != null) ...[
                        ..._adjustedSummary(detail.bill!),
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
                                for (final line
                                    in round['priced_lines'] as List)
                                  _line(tableMap(line)),
                                if (round['status'] == 'accepted' &&
                                    round['kitchen_printed_at'] == null &&
                                    c?.printAccepted != null)
                                  TextButton(
                                    key: ValueKey('dine-print-${round['id']}'),
                                    onPressed: enabled
                                        ? () =>
                                              c!.retryPrint(round['id'] as int)
                                        : null,
                                    child: Text(text('print')),
                                  ),
                                if (round['status'] == 'pending_confirmation')
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      FilledButton(
                                        key: ValueKey(
                                          'dine-confirm-${round['id']}',
                                        ),
                                        onPressed: enabled && drafts.isEmpty
                                            ? () => c!.review(
                                                round['id'] as int,
                                                true,
                                              )
                                            : null,
                                        child: Text(text('confirm')),
                                      ),
                                      OutlinedButton(
                                        key: ValueKey(
                                          'dine-reject-${round['id']}',
                                        ),
                                        onPressed: enabled && drafts.isEmpty
                                            ? () => c!.review(
                                                round['id'] as int,
                                                false,
                                              )
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
                      if (c?.canDiscardAdjustment == true &&
                          widget.approveAdjustmentDiscard != null)
                        TextButton(
                          key: const ValueKey('dine-discard-adjustment'),
                          onPressed: _discardAdjustment,
                          child: Text(text('discard_adjustment')),
                        ),
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
                          title: Text(
                            '${drafts[i].$2.quantity} × ${drafts[i].$1}',
                          ),
                          trailing: IconButton(
                            key: ValueKey('dine-remove-$i'),
                            onPressed: c?.busy == true
                                ? null
                                : () async {
                                    setState(() => drafts.removeAt(i));
                                    await _persistDrafts();
                                    _publish();
                                  },
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
                          if (detail.protectedCheckout && !detail.canAppend)
                            OutlinedButton(
                              key: const ValueKey('dine-reopen'),
                              onPressed: enabled && drafts.isEmpty
                                  ? c!.reopen
                                  : null,
                              child: Text(text('reopen')),
                            ),
                          if (detail.protectedCheckout)
                            FilledButton(
                              key: const ValueKey('dine-pay'),
                              onPressed: enabled && c!.canPay && drafts.isEmpty
                                  ? _pay
                                  : null,
                              child: Text(text('pay')),
                            ),
                          if (detail.canClearEmpty)
                            OutlinedButton(
                              key: const ValueKey('dine-clear'),
                              onPressed: enabled && drafts.isEmpty
                                  ? _clearEmptySession
                                  : null,
                              child: Text(text('clear')),
                            ),
                        ],
                      ),
                      if (detail.bill != null && !detail.protectedCheckout)
                        note('staff_pay'),
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
        if (tableLineHeld(line)) _heldDescription(line),
        if (line['cancelled_qty'] != null)
          '${widget.arabic ? 'ملغي' : 'Cancelled'}: ${line['cancelled_qty']}',
      ].whereType<String>().join(' · '),
    ),
    trailing: tableLineHeld(line)
        ? null
        : Text(money(line['line_total_baisas'])),
  );
}
