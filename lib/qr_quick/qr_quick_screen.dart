import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import '../combo/combo_sheet.dart';
import '../models/pos_models.dart' show CartItemModifier, ComboSelection;
import '../order_workspace/current_order_workspace.dart';
import 'qr_quick_controller.dart';
import 'qr_expired_cancel.dart';
import 'qr_payment_review.dart';
import 'qr_quick_copy.dart';
import 'qr_quick_models.dart';

/// Shared price-free catalogue picker. It never reads or modifies a cart.
Future<(String, QrQuickLine)?> pickStaffRoundItem(
  BuildContext context,
  List<QuickProduct> products, {
  required bool arabic,
}) async {
  final copy = QuickCopy(arabic);
  final product = await showDialog<QuickProduct>(
    context: context,
    builder: (_) => Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: _ProductPicker(products, copy),
    ),
  );
  if (product == null || !context.mounted) return null;
  final line = await quickPickLine(context, product, copy, catalogue: products);
  return line == null ? null : (copy.name(product.name, product.nameAr), line);
}

/// LAUNCH-P4 C7 — [catalogue] resolves a combo's option products (names,
/// add-on groups); [initial] edits an existing server or draft line.
Future<(String, QrQuickLine)?> pickStaffRoundProduct(
  BuildContext context,
  QuickProduct product, {
  required bool arabic,
  List<QuickProduct> catalogue = const [],
  Map<String, dynamic>? initial,
}) async {
  if (!product.available) return null;
  final copy = QuickCopy(arabic);
  final line = await quickPickLine(
    context,
    product,
    copy,
    catalogue: catalogue,
    initial: initial,
  );
  return line == null ? null : (copy.name(product.name, product.nameAr), line);
}

class QrQuickScreen extends StatefulWidget {
  const QrQuickScreen({
    super.key,
    required this.createController,
    required this.catalogue,
    this.onPay,
    this.onRecoverPayment,
    this.arabic = false,
    this.onOpen,
    this.workspace,
    this.workspaceUuid,
    this.onVoid,
  });
  final Future<QrQuickController> Function() createController;
  final List<QuickProduct> Function() catalogue;
  final Future<void> Function(BuildContext, QrQuickOrder)? onPay;
  final Future<void> Function()? onRecoverPayment;
  final bool arabic;
  final Future<void> Function(String uuid)? onOpen;
  final CurrentOrderWorkspace? workspace;
  final String? workspaceUuid;
  final Future<bool> Function(String uuid)? onVoid;
  @override
  State<QrQuickScreen> createState() => _QrQuickScreenState();
}

class _QrQuickScreenState extends State<QrQuickScreen>
    with WidgetsBindingObserver {
  QrQuickController? controller;
  Timer? timer;
  bool failed = false;
  bool foreground = true;
  int covered = 0;
  bool paying = false;
  String search = '';
  bool cancelling = false;
  bool reviewing = false;

  /// Orders with a payment saved on this till that a manager has not reviewed.
  Set<String> localPayments = {};
  late bool arabic = widget.arabic;
  QuickCopy get copy => QuickCopy(arabic);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await widget.createController();
      if (!mounted) {
        value.dispose();
        return;
      }
      controller = value;
      await value.start();
      if (!mounted) return;
      setState(() {});
      _schedule();
      unawaited(_refreshLocalPayments());
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  void _schedule() {
    timer?.cancel();
    if (!foreground || covered > 0 || !mounted) return;
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(controller?.refresh());
      unawaited(_refreshLocalPayments());
    });
  }

  Future<void> _refreshLocalPayments() async {
    final gateway = controller?.gateway;
    if (gateway is! QrQuickPaymentReviewGateway) return;
    try {
      final value = await (gateway as QrQuickPaymentReviewGateway)
          .ordersWithLocalPaymentEvidence();
      if (mounted &&
          (value.length != localPayments.length ||
              !value.containsAll(localPayments))) {
        setState(() => localPayments = value);
      }
    } catch (_) {
      // Unreadable journals keep the last known set; the review dialog and
      // the cancellation guard both re-read and fail closed.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) controller?.invalidate();
    _schedule();
    if (foreground && covered == 0) unawaited(controller?.refresh());
  }

  Future<void> _child(Future<void> Function() action) async {
    covered++;
    _schedule();
    try {
      await action();
    } finally {
      covered--;
      if (mounted) {
        await controller?.refresh();
        await _refreshLocalPayments();
        _schedule();
      }
    }
  }

  Future<void> _cancel(String? uuid) async {
    final c = controller;
    if (c == null ||
        c.busy ||
        c.stale ||
        cancelling ||
        c.gateway is! QrQuickCancellationGateway) {
      return;
    }
    setState(() => cancelling = true);
    try {
      await _child(() async {
        await showQrExpiredCancel(
          context,
          c.gateway as QrQuickCancellationGateway,
          uuid,
          arabic: arabic,
        );
      });
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  Future<void> _review(QrQuickOrder order) async {
    final c = controller;
    if (c == null ||
        c.busy ||
        c.stale ||
        reviewing ||
        c.gateway is! QrQuickPaymentReviewGateway) {
      return;
    }
    setState(() => reviewing = true);
    try {
      await _child(
        () => showQrPaymentReview(
          context,
          c.gateway as QrQuickPaymentReviewGateway,
          order,
          arabic: arabic,
        ),
      );
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
  }

  Future<void> _pay(String uuid) async {
    if (paying) return;
    paying = true;
    final c = controller!;
    try {
      if (c.stale) await c.refresh();
      if (!mounted || !c.canPay(uuid) || widget.onPay == null) return;
      await _child(() => widget.onPay!(context, c.find(uuid)!));
    } finally {
      paying = false;
    }
  }

  Future<void> _open(String uuid) => widget.onOpen != null
      ? _child(() => widget.onOpen!(uuid))
      : _child(
          () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => _QuickEditor(
                controller: controller!,
                uuid: uuid,
                catalogue: widget.catalogue,
                copy: copy,
                onPay: widget.onPay == null ? null : () => _pay(uuid),
              ),
            ),
          ),
        );
  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workspace?.mainCart == true && controller == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: failed
            ? Text(copy.message('storage'))
            : const LinearProgressIndicator(),
      );
    }
    if (widget.workspace != null) {
      return controller == null
          ? Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  onPressed: widget.workspace!.requestClose,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: Text(copy.pair('Current Order', 'الطلب الحالي')),
              ),
              body: Center(
                child: failed
                    ? Text(copy.message('storage'))
                    : const CircularProgressIndicator(),
              ),
            )
          : _QuickEditor(
              controller: controller!,
              uuid: widget.workspaceUuid!,
              catalogue: widget.catalogue,
              copy: copy,
              onPay: widget.onPay == null
                  ? null
                  : () => _pay(widget.workspaceUuid!),
              workspace: widget.workspace,
              onVoid: widget.onVoid,
            );
    }
    return Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(copy.title),
          actions: [
            if (widget.onRecoverPayment != null)
              IconButton(
                key: const ValueKey('quick-payment-recovery'),
                tooltip: arabic
                    ? 'تحقق من نتيجة الدفع'
                    : 'Check payment result',
                onPressed: () => _child(widget.onRecoverPayment!),
                icon: const Icon(Icons.receipt_long),
              ),
            TextButton(
              onPressed: () => setState(() => arabic = !arabic),
              child: Text(arabic ? 'English' : 'العربية'),
            ),
            IconButton(
              key: const ValueKey('quick-refresh'),
              tooltip: copy.refresh,
              onPressed: () => controller?.refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: failed
            ? Center(child: Text(copy.message('storage')))
            : controller == null
            ? const Center(child: CircularProgressIndicator())
            : AnimatedBuilder(
                animation: controller!,
                builder: (context, _) {
                  final c = controller!;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        key: const ValueKey('quick-order-search'),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: copy.pair(
                            'Search order number or last 4 phone digits',
                            'البحث برقم الطلب أو آخر 4 أرقام للهاتف',
                          ),
                        ),
                        onChanged: (value) =>
                            setState(() => search = value.trim().toLowerCase()),
                      ),
                      if (c.gateway is QrQuickCancellationGateway)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            key: const ValueKey('quick-clear-expired'),
                            onPressed: c.busy || c.stale || cancelling
                                ? null
                                : () => _cancel(null),
                            child: Text(
                              copy.pair(
                                'Clear all expired',
                                'إلغاء جميع الطلبات المنتهية',
                              ),
                            ),
                          ),
                        ),
                      if (c.busy) const LinearProgressIndicator(),
                      if (c.stale) _notice(copy.stale),
                      if (c.notice != null) _notice(copy.message(c.notice!)),
                      if (c.orders.isEmpty && c.pending.isEmpty && !c.stale)
                        _notice(copy.empty),
                      for (final request in c.pending.values.where(
                        (r) => c.find(r.orderUuid) == null,
                      ))
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(request.orderUuid),
                                Text(copy.uncertain),
                                TextButton(
                                  onPressed: c.busy
                                      ? null
                                      : () => c.retry(request.orderUuid),
                                  child: Text(copy.retry),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (final order in c.orders.where(
                        (o) =>
                            search.isEmpty ||
                            o.reference.toLowerCase().contains(search) ||
                            (search.length == 4 && o.phoneTail == search),
                      ))
                        Card(
                          key: ValueKey('quick-order-${order.uuid}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.reference,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text('${copy.total}: ${_money(order.total)}'),
                                Text(
                                  '${order.ageSeconds ~/ 60} ${copy.pair('min', 'دقيقة')}${order.phoneTail.isEmpty ? '' : ' · •••• ${order.phoneTail}'}',
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    Chip(
                                      label: Text(
                                        copy.state(order.charge, order.session),
                                      ),
                                    ),
                                  ],
                                ),
                                if (order.refusal != null)
                                  Text(copy.message(order.refusal!)),
                                if (localPayments.contains(order.uuid))
                                  Text(
                                    copy.pair(
                                      'A payment for this order is saved on this till. A manager must review it.',
                                      'يوجد دفع محفوظ لهذا الطلب على هذا الجهاز. يجب أن يراجعه المشرف.',
                                    ),
                                  ),
                                if (c.pending.containsKey(order.uuid))
                                  Text(copy.uncertain),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (c.gateway
                                            is QrQuickPaymentReviewGateway &&
                                        (order.charge == 'uncertain' ||
                                            localPayments.contains(order.uuid)))
                                      FilledButton(
                                        key: ValueKey(
                                          'quick-payment-review-${order.uuid}',
                                        ),
                                        onPressed:
                                            c.busy ||
                                                c.stale ||
                                                reviewing ||
                                                c.pending.containsKey(
                                                  order.uuid,
                                                )
                                            ? null
                                            : () => _review(order),
                                        child: Text(
                                          copy.pair(
                                            'Review payment',
                                            'مراجعة الدفع',
                                          ),
                                        ),
                                      ),
                                    if (c.gateway
                                            is QrQuickCancellationGateway &&
                                        const {
                                          'closed',
                                          'expired',
                                        }.contains(order.session))
                                      TextButton(
                                        key: ValueKey(
                                          'quick-cancel-${order.uuid}',
                                        ),
                                        onPressed:
                                            c.busy ||
                                                c.stale ||
                                                cancelling ||
                                                c.pending.containsKey(
                                                  order.uuid,
                                                )
                                            ? null
                                            : () => _cancel(order.uuid),
                                        child: Text(
                                          copy.pair('Cancel', 'إلغاء'),
                                        ),
                                      ),
                                    FilledButton.tonal(
                                      key: ValueKey(
                                        'quick-review-${order.uuid}',
                                      ),
                                      onPressed: () => _open(order.uuid),
                                      child: Text(
                                        copy.pair('Open order', 'فتح الطلب'),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: c.canAdd(order.uuid)
                                          ? () => _open(order.uuid)
                                          : null,
                                      child: Text(copy.add),
                                    ),
                                    TextButton(
                                      onPressed:
                                          c.canPay(order.uuid) &&
                                              widget.onPay != null
                                          ? () => _pay(order.uuid)
                                          : null,
                                      child: Text(copy.pay),
                                    ),
                                  ],
                                ),
                                if (widget.onPay == null) Text(copy.noPayment),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

String _money(int baisas) => '${(baisas / 1000).toStringAsFixed(3)} OMR';
Widget _notice(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(text),
);

class _QuickEditor extends StatefulWidget {
  const _QuickEditor({
    required this.controller,
    required this.uuid,
    required this.catalogue,
    required this.copy,
    this.onPay,
    this.workspace,
    this.onVoid,
  });
  final QrQuickController controller;
  final String uuid;
  final List<QuickProduct> Function() catalogue;
  final QuickCopy copy;
  final Future<void> Function()? onPay;
  final CurrentOrderWorkspace? workspace;
  final Future<bool> Function(String uuid)? onVoid;
  @override
  State<_QuickEditor> createState() => _QuickEditorState();
}

class _QuickEditorState extends State<_QuickEditor> {
  final drafts = <(String, QrQuickLine)>[];
  final _pickedProducts = <int, QuickProduct>{};
  QuickProduct? _product(int id) =>
      widget.catalogue().where((p) => p.id == id).firstOrNull ??
      _pickedProducts[id];
  bool closing = false;
  bool childOpen = false;
  QuickCopy get copy => widget.copy;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_publish);
    widget.workspace?.attach(
      this,
      pick: (product) => _pick(product),
      leave: _leave,
      pay: _pay,
    );
    _publish();
    // Opening a safe QR order for editing explicitly takes it to the counter.
    // Live/uncertain claims and orders addressed to another device stay blocked.
    if (widget.workspace?.mainCart == true &&
        widget.controller.find(widget.uuid)?.canMove == true) {
      unawaited(widget.controller.move(widget.uuid));
    }
  }

  void _publish() => widget.workspace?.publish(
    this,
    order: widget.controller.find(widget.uuid)?.json,
    stale: widget.controller.stale,
    cartControls: WorkspaceCartControls(
      busy: childOpen || widget.controller.busy,
      notices: [
        if (drafts.isNotEmpty && !_draftsValid)
          copy.pair(
            'Choose the required options with Add On before payment or transfer.',
            'اختر الخيارات المطلوبة من الإضافات قبل الدفع أو التحويل.',
          ),
        if (drafts.isNotEmpty &&
            _draftsValid &&
            widget.workspace?.mainCart == true)
          copy.pair(
            'Unsent item prices are estimates until saved.',
            'أسعار الأصناف غير المرسلة تقديرية حتى الحفظ.',
          ),
        if (widget.controller.stale) copy.stale,
        if (widget.controller.notice != null &&
            widget.controller.notice != 'added')
          copy.message(widget.controller.notice!),
        if (widget.controller.find(widget.uuid)?.refusal case final refusal?)
          copy.message(refusal),
        if (widget.controller.pending.containsKey(widget.uuid)) copy.uncertain,
      ],
      drafts: [
        for (final draft in drafts) '${draft.$2.quantity} × ${draft.$1}',
      ],
      draftRows: widget.workspace?.mainCart == true ? _draftRows : const [],
      removeDraft: _canEditDrafts ? _removeDraft : null,
      refresh: !childOpen && !widget.controller.busy
          ? widget.controller.refresh
          : null,
      retry:
          !childOpen &&
              !widget.controller.busy &&
              widget.controller.pending.containsKey(widget.uuid)
          ? () async {
              await widget.controller.retry(widget.uuid);
            }
          : null,
      submit:
          !childOpen &&
              widget.controller.canAdd(widget.uuid) &&
              _draftsValid &&
              drafts.isNotEmpty
          ? _submit
          : null,
      move:
          !childOpen &&
              !widget.controller.busy &&
              !widget.controller.stale &&
              drafts.isEmpty &&
              widget.controller.find(widget.uuid)?.canMove == true
          ? () => widget.controller.move(widget.uuid)
          : null,
      voidBill: _canVoid ? _void : null,
      clear: !childOpen && widget.controller.canEdit(widget.uuid)
          ? _clear
          : null,
      quantity:
          !childOpen &&
              (widget.controller.canEdit(widget.uuid) ||
                  (drafts.isNotEmpty && _canEditDrafts))
          ? _quantity
          : null,
      customize:
          !childOpen &&
              (widget.controller.canEdit(widget.uuid) ||
                  (drafts.isNotEmpty && _canEditDrafts))
          ? _customize
          : null,
      transfer: widget.controller.canEdit(widget.uuid) && drafts.isEmpty
          ? (device) => widget.controller.change(widget.uuid, {
              'operation': 'transfer',
              'target_device_id': device,
            })
          : null,
    ),
    canAdd:
        !childOpen &&
        widget.controller.canAdd(widget.uuid) &&
        drafts.length < 50,
    canPay:
        !childOpen &&
        drafts.isEmpty &&
        widget.controller.canPay(widget.uuid) &&
        widget.onPay != null,
  );

  Future<void> _pay() async {
    if (childOpen ||
        drafts.isNotEmpty ||
        !widget.controller.canPay(widget.uuid) ||
        widget.onPay == null) {
      return;
    }
    childOpen = true;
    _publish();
    try {
      await widget.onPay?.call();
    } finally {
      childOpen = false;
      if (mounted) _publish();
    }
  }

  bool get _canVoid =>
      widget.workspace != null &&
      widget.onVoid != null &&
      !childOpen &&
      !closing &&
      drafts.isEmpty &&
      widget.controller.ready &&
      !widget.controller.stale &&
      !widget.controller.busy &&
      !widget.controller.pending.containsKey(widget.uuid) &&
      const {
        'open',
        'held',
        'awaiting_payment',
      }.contains(widget.controller.find(widget.uuid)?.json['status']);

  Future<void> _void() async {
    if (!_canVoid) return;
    setState(() => childOpen = true);
    _publish();
    try {
      if (await widget.onVoid!(widget.uuid) && mounted) _exit();
    } finally {
      if (mounted) {
        setState(() => childOpen = false);
        widget.controller.invalidate();
        await widget.controller.refresh();
        if (mounted) _publish();
      }
    }
  }

  void _exit() {
    if (widget.workspace != null) {
      widget.workspace!.onExit();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_publish);
    widget.workspace?.detach(this);
    super.dispose();
  }

  Future<void> _leave() async {
    if (closing || childOpen || widget.controller.busy) return;
    if (drafts.isEmpty) {
      _exit();
      return;
    }
    closing = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          copy.pair('Discard unsent additions?', 'تجاهل الإضافات غير المرسلة؟'),
        ),
        content: Text(
          copy.pair(
            'The existing bill will not change.',
            'لن تتغير الفاتورة الحالية.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(copy.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(copy.pair('Discard', 'تجاهل')),
          ),
        ],
      ),
    );
    closing = false;
    if (discard == true && mounted) {
      setState(drafts.clear);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _exit();
      });
    }
  }

  Future<void> _pick([QuickProduct? selected]) async {
    if (childOpen ||
        !widget.controller.canAdd(widget.uuid) ||
        drafts.length >= 50) {
      return;
    }
    final products = widget.catalogue();
    final product =
        selected ??
        await showDialog<QuickProduct>(
          context: context,
          builder: (context) => Directionality(
            textDirection: copy.arabic ? TextDirection.rtl : TextDirection.ltr,
            child: _ProductPicker(products, copy),
          ),
        );
    if (product == null || !mounted) return;
    _pickedProducts[product.id] = product;
    // A combo opens its picker and a meal main asks "Make it a meal?"
    // (never a plain line).
    if (widget.workspace?.mainCart == true &&
        selected != null &&
        !product.isCombo &&
        product.meal == null) {
      final index = drafts.indexWhere(
        (d) =>
            d.$2.productId == product.id &&
            d.$2.addonIds.isEmpty &&
            d.$2.combo.isEmpty &&
            d.$2.mealId == null &&
            (d.$2.notes ?? '').isEmpty,
      );
      if (index >= 0 && drafts[index].$2.quantity >= 99) return;
      setState(() {
        final line = QrQuickLine(
          product.id,
          index < 0 ? 1 : drafts[index].$2.quantity + 1,
          [],
        );
        final entry = (copy.name(product.name, product.nameAr), line);
        if (index < 0) {
          drafts.add(entry);
        } else {
          drafts[index] = entry;
        }
      });
      widget.controller.reviewDraft(widget.uuid);
      _publish();
      if (_draftsValid) await _submit();
      return;
    }
    final line = await quickPickLine(
      context,
      product,
      copy,
      catalogue: products,
    );
    if (line != null && mounted) {
      setState(
        () => drafts.add((copy.name(product.name, product.nameAr), line)),
      );
      _publish();
      if (widget.workspace?.mainCart == true) await _submit();
    }
  }

  bool get _canEditDrafts =>
      !childOpen &&
      !closing &&
      widget.controller.ready &&
      !widget.controller.busy &&
      !widget.controller.pending.containsKey(widget.uuid);

  bool get _draftsValid => drafts.every((draft) {
    final product = _product(draft.$2.productId);
    return product != null &&
        product.groups.every((group) {
          final count = group.choices
              .where((choice) => draft.$2.addonIds.contains(choice.id))
              .length;
          return count >= group.min && count <= group.max;
        }) &&
        // LAUNCH combo add-on — a combo / meal's picks fit its lines.
        quickComboValid(draft.$2, product);
  });

  List<Map<String, dynamic>> get _draftRows => [
    for (var index = 0; index < drafts.length; index++) _draftRow(index),
  ];

  Map<String, dynamic> _draftRow(int index) {
    final line = drafts[index].$2;
    final product = _product(line.productId);
    final choices = [
      for (final group in product?.groups ?? <QuickGroup>[])
        for (final choice in group.choices)
          if (line.addonIds.contains(choice.id)) choice,
    ];
    final combo = quickComboRows(line, product, _product);
    final unit = quickDraftUnitBaisas(line, product, combo, [
      for (final c in choices) c.priceBaisas,
    ]);
    return {
      ...quickMealKeys(line, product),
      'id': 'draft-$index',
      'draft_index': index,
      'product_id': line.productId,
      'product_name': product?.name ?? drafts[index].$1,
      'product_name_ar': product?.nameAr ?? '',
      'qty': line.quantity,
      'line_total_baisas': unit * line.quantity,
      'notes': line.notes,
      'addons': [
        for (final choice in choices)
          {
            'add_on_id': choice.id,
            'add_on_name': choice.name,
            'add_on_name_ar': choice.nameAr,
          },
      ],
      if (combo.isNotEmpty) 'combo': combo,
    };
  }

  void _removeDraft(int index) {
    if (!_canEditDrafts || index < 0 || index >= drafts.length) return;
    setState(() => drafts.removeAt(index));
    widget.controller.reviewDraft(widget.uuid);
    _publish();
  }

  Future<void> _clear() async {
    if (!widget.controller.canEdit(widget.uuid)) return;
    // These lines were definitively rejected or never sent. The durable
    // uncertain-request journal is separate and canEdit protects it.
    setState(drafts.clear);
    _publish();
    await widget.controller.change(widget.uuid, {'operation': 'clear'});
  }

  Future<void> _quantity(Map<String, dynamic> line, int quantity) async {
    final c = widget.controller;
    if (quantity < 0 || quantity > 99) return;
    if (line['draft_index'] case final int index) {
      if (!_canEditDrafts || index >= drafts.length) return;
      if (quantity == 0) {
        _removeDraft(index);
        return;
      }
      final old = drafts[index];
      setState(() => drafts[index] = (old.$1, old.$2.withQuantity(quantity)));
      c.reviewDraft(widget.uuid);
      _publish();
      return;
    }
    if (!c.canEdit(widget.uuid)) return;
    final old = (line['qty'] as num).toInt();
    if (quantity > old) {
      final productId = line['product_id'];
      if (productId is! int) return;
      await c.add(widget.uuid, [
        QrQuickLine(
          productId,
          quantity - old,
          [
            for (final a in line['addons'] as List? ?? const [])
              if (qrMap(a)['add_on_id'] is int) qrMap(a)['add_on_id'] as int,
          ],
          notes: line['notes'] as String?,
          // More of a combo / meal = the same items again.
          combo: serverComboPicks(line),
          mealId: (line['meal_id'] as num?)?.toInt(),
        ),
      ]);
    } else {
      await c.change(widget.uuid, {
        'operation': 'quantity',
        'item_id': line['id'],
        if ((line['item_ids'] as List?)?.length case final int count
            when count > 1)
          'item_ids': line['item_ids'],
        'qty': quantity,
      });
    }
  }

  Future<void> _customize(Map<String, dynamic> line) async {
    if (line['draft_index'] is int
        ? !_canEditDrafts
        : !widget.controller.canEdit(widget.uuid)) {
      return;
    }
    final product = _product(line['product_id'] as int);
    if (product == null) return;
    final revision = widget.controller.find(widget.uuid)?.json['edit_revision'];
    childOpen = true;
    _publish();
    QrQuickLine? replacement;
    try {
      replacement = widget.workspace?.editOptions != null
          ? await widget.workspace!.editOptions!(line)
          : await quickPickLine(
              context,
              product,
              copy,
              catalogue: widget.catalogue(),
              initial: line,
            );
    } finally {
      childOpen = false;
      if (mounted) _publish();
    }
    if (replacement != null && mounted) {
      if (line['draft_index'] case final int index) {
        if (!_canEditDrafts || index >= drafts.length) return;
        final updated = replacement;
        setState(() => drafts[index] = (drafts[index].$1, updated));
        widget.controller.reviewDraft(widget.uuid);
        _publish();
        if (_draftsValid) await _submit();
        return;
      }
      if (revision !=
          widget.controller.find(widget.uuid)?.json['edit_revision']) {
        widget.controller.notice = 'order_changed';
        _publish();
        return;
      }
      await widget.controller.change(
        widget.uuid,
        {
          'operation': 'replace',
          'item_id': line['id'],
          if ((line['item_ids'] as List?)?.length case final int count
              when count > 1)
            'item_ids': line['item_ids'],
        },
        lines: [replacement],
      );
    }
  }

  Future<void> _submit() async {
    final c = widget.controller;
    if (!_draftsValid) return;
    if (c.stale) await c.refresh();
    if (!mounted || drafts.isEmpty || !c.canAdd(widget.uuid)) return;
    final ok = await c.add(widget.uuid, drafts.map((d) => d.$2).toList());
    if (mounted && (ok || c.pending.containsKey(widget.uuid))) {
      setState(drafts.clear);
    }
    if (mounted) _publish();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final order = c.find(widget.uuid);
      final pending = c.pending[widget.uuid];
      return PopScope(
        canPop:
            widget.workspace == null && drafts.isEmpty && !c.busy && !childOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: widget.workspace?.mainCart == true
            ? const SizedBox.shrink()
            : Directionality(
                textDirection: copy.arabic
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: Scaffold(
                  appBar: AppBar(
                    leading: widget.workspace == null
                        ? null
                        : IconButton(
                            tooltip: copy.pair(
                              'Back to QR Quick Orders',
                              'العودة إلى طلبات QR السريعة',
                            ),
                            onPressed: _leave,
                            icon: const Icon(Icons.arrow_back),
                          ),
                    title: Text(order?.reference ?? widget.uuid),
                    actions: [
                      if (widget.workspace != null && widget.onVoid != null)
                        TextButton.icon(
                          key: const ValueKey('workspace-void'),
                          onPressed: _canVoid ? _void : null,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(copy.pair('Void bill', 'إلغاء الفاتورة')),
                        ),
                      IconButton(
                        onPressed: c.busy ? null : c.refresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: copy.refresh,
                      ),
                    ],
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (c.busy) const LinearProgressIndicator(),
                      if (c.stale) _notice(copy.stale),
                      if (c.notice != null) _notice(copy.message(c.notice!)),
                      if (order != null) ...[
                        Text(
                          '${copy.total}: ${_money(order.total)}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(copy.state(order.charge, order.session)),
                        if (order.refusal != null)
                          _notice(copy.message(order.refusal!)),
                        if (order.phoneTail.isNotEmpty)
                          Text('•••• ${order.phoneTail}'),
                        _notice(copy.existing),
                        for (final item in order.items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${item['qty']} × ${item['product_name']}',
                            ),
                            subtitle: Text(
                              [
                                // LAUNCH-P4 C7 — a combo's chosen items.
                                ...serverComboLabels(item, arabic: copy.arabic),
                                for (final addon
                                    in (item['addons'] as List? ?? const []))
                                  qrMap(addon)['add_on_name'].toString(),
                                if (item['notes'] != null)
                                  item['notes'].toString(),
                              ].join(' · '),
                            ),
                            trailing: Text(
                              _money(item['line_total_baisas'] as int),
                            ),
                          ),
                        const Divider(),
                      ],
                      if (pending != null) ...[
                        _notice(copy.uncertain),
                        for (final line in pending.lines)
                          Text('${line.quantity} × #${line.productId}'),
                        FilledButton(
                          key: const ValueKey('quick-retry'),
                          onPressed: c.busy ? null : () => c.retry(widget.uuid),
                          child: Text(copy.retry),
                        ),
                      ] else ...[
                        _notice(copy.pricing),
                        if (drafts.isNotEmpty) _notice(copy.draft),
                        for (var i = 0; i < drafts.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${drafts[i].$2.quantity} × ${drafts[i].$1}',
                            ),
                            trailing: IconButton(
                              tooltip: copy.pair(
                                'Remove unsent item',
                                'إزالة صنف غير مرسل',
                              ),
                              onPressed: _canEditDrafts
                                  ? () => _removeDraft(i)
                                  : null,
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              key: const ValueKey('quick-add-items'),
                              onPressed:
                                  c.canAdd(widget.uuid) && drafts.length < 50
                                  ? _pick
                                  : null,
                              child: Text(copy.add),
                            ),
                            FilledButton(
                              key: const ValueKey('quick-submit'),
                              onPressed:
                                  c.canAdd(widget.uuid) && drafts.isNotEmpty
                                  ? _submit
                                  : null,
                              child: Text(copy.submit),
                            ),
                          ],
                        ),
                        if (order?.canMove == true)
                          TextButton(
                            key: const ValueKey('quick-move'),
                            onPressed: !c.stale && !c.busy && drafts.isEmpty
                                ? () => c.move(widget.uuid)
                                : null,
                            child: Text(copy.move),
                          ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const ValueKey('quick-pay'),
                          onPressed:
                              c.canPay(widget.uuid) &&
                                  drafts.isEmpty &&
                                  widget.onPay != null
                              ? _pay
                              : null,
                          child: Text(copy.pay),
                        ),
                        if (widget.onPay == null) _notice(copy.noPayment),
                      ],
                    ],
                  ),
                ),
              ),
      );
    },
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker(this.products, this.copy);
  final List<QuickProduct> products;
  final QuickCopy copy;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    final products = widget.products
        .where(
          (p) => '${p.name} ${p.nameAr}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return AlertDialog(
      title: Text(copy.add),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('quick-product-search'),
              decoration: InputDecoration(
                labelText: copy.pair('Search items', 'ابحث عن صنف'),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in products)
                    ListTile(
                      key: ValueKey('quick-product-${p.id}'),
                      enabled: p.available,
                      title: Text(copy.name(p.name, p.nameAr)),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.cancel),
        ),
      ],
    );
  }
}

class _ProductOptions extends StatefulWidget {
  const _ProductOptions(this.product, this.copy, {this.initial});
  final Map<String, dynamic>? initial;
  final QuickProduct product;
  final QuickCopy copy;
  @override
  State<_ProductOptions> createState() => _ProductOptionsState();
}

class _ProductOptionsState extends State<_ProductOptions> {
  late int qty = (widget.initial?['qty'] as num?)?.toInt() ?? 1;
  late String notes = widget.initial?['notes'] as String? ?? '';
  late final selected = widget.initial != null
      ? <int>{
          for (final a in widget.initial!['addons'] as List? ?? const [])
            if (qrMap(a)['add_on_id'] is int) qrMap(a)['add_on_id'] as int,
        }
      : <int>{
          for (final g in widget.product.groups)
            for (final o in g.choices)
              if (o.selected) o.id,
        };
  bool get valid =>
      selected.length <= 30 &&
      widget.product.groups.every((g) {
        final count = g.choices.where((o) => selected.contains(o.id)).length;
        return count >= g.min && count <= g.max;
      });
  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return AlertDialog(
      title: Text(copy.name(widget.product.name, widget.product.nameAr)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: qty > 1 ? () => setState(() => qty--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$qty'),
                  IconButton(
                    key: const ValueKey('quick-qty-plus'),
                    onPressed: qty < 99 ? () => setState(() => qty++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              for (final group in widget.product.groups) ...[
                Text(
                  '${copy.name(group.name, group.nameAr)} (${group.min}–${group.max})',
                ),
                for (final option in group.choices)
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(copy.name(option.name, option.nameAr)),
                    value: selected.contains(option.id),
                    onChanged: (checked) => setState(() {
                      if (checked != true) {
                        selected.remove(option.id);
                      } else {
                        if (group.max == 1) {
                          selected.removeAll(group.choices.map((o) => o.id));
                        }
                        selected.add(option.id);
                      }
                    }),
                  ),
              ],
              TextFormField(
                initialValue: notes,
                key: const ValueKey('quick-notes'),
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: copy.pair('Notes', 'ملاحظات'),
                ),
                onChanged: (v) => notes = v,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.cancel),
        ),
        FilledButton(
          key: const ValueKey('quick-option-add'),
          onPressed: valid
              ? () => Navigator.pop(
                  context,
                  QrQuickLine(
                    widget.product.id,
                    qty,
                    selected.toList(),
                    notes: notes.isEmpty ? null : notes,
                  ),
                )
              : null,
          child: Text(copy.add),
        ),
      ],
    );
  }
}

/// LAUNCH combo add-on — the server-priced picks of a combo or meal (quick
/// QR, staff table rounds, tablet edits) in the till's combo sheet. Pops a
/// [QrQuickLine] whose `combo` carries identity only (line, product, qty,
/// add-on ids, notes) — the server prices it and refuses client prices. A
/// meal line's product is its main (`meal_id`; the main's add-ons / notes).
Future<QrQuickLine?> _quickComboSheet(
  BuildContext context,
  QuickProduct product,
  QuickCopy copy, {
  required List<QuickProduct> catalogue,
  Map<String, dynamic>? initial,
  bool meal = false,
}) async {
  final mealSetup = meal ? product.meal : null;
  final lines = mealSetup?.lines ?? product.comboLines;
  QuickProduct? item(int id) => catalogue.where((p) => p.id == id).firstOrNull;
  CartItemModifier modifier(QuickGroup group, QuickChoice choice) =>
      CartItemModifier(
        id: '${choice.id}',
        group: group.name,
        label: choice.name,
        labelAr: choice.nameAr,
        price: choice.priceBaisas / 1000,
      );
  List<CartItemModifier> modifiersFor(int productId, Iterable<int> ids) => [
    for (final g in item(productId)?.groups ?? const <QuickGroup>[])
      for (final c in g.choices)
        if (ids.contains(c.id)) modifier(g, c),
  ];
  bool complete(String productId, List<CartItemModifier> modifiers) {
    final ids = {for (final m in modifiers) int.tryParse(m.id)};
    return (item(int.tryParse(productId) ?? 0)?.groups ?? const <QuickGroup>[])
        .every((g) {
          final count = g.choices.where((c) => ids.contains(c.id)).length;
          return count >= g.min && count <= g.max;
        });
  }

  List<pricing.ComboAddOn> addOns(List<CartItemModifier> modifiers) => [
    for (final m in modifiers)
      pricing.ComboAddOn(
        addOnId: int.tryParse(m.id) ?? 0,
        priceDeltaBaisas: (m.price * 1000).round(),
      ),
  ];
  int price(ComboSheetResult draft) {
    final items = pricing.resolveComboPicks(lines, [
      for (final s in draft.selections)
        pricing.ComboPick(
          lineId: s.lineId,
          productId: int.tryParse(s.productId) ?? 0,
          qty: s.qty,
          addOns: addOns(s.modifiers),
        ),
    ]).items;
    if (mealSetup != null) {
      return pricing.ComboSale.meal(
        mealId: mealSetup.id,
        mealPriceBaisas: mealSetup.mealPriceBaisas,
        main: pricing.MealMain(
          productId: product.id,
          priceBaisas: product.priceBaisas,
          addOns: addOns(draft.mainModifiers),
        ),
        items: items,
      ).unitPriceBaisas;
    }
    return pricing.ComboSale.combo(
      comboProductId: product.id,
      comboPriceBaisas: product.priceBaisas,
      items: items,
    ).unitPriceBaisas;
  }

  final initialMainIds = <int>{
    for (final a in (initial?['addons'] as List?) ?? const [])
      if (a is Map && (a['add_on_id'] as num?) != null)
        (a['add_on_id'] as num).toInt(),
    for (final id in (initial?['addon_ids'] as List?) ?? const [])
      if (id is num) id.toInt(),
  };
  final defaultMain = [
    for (final g in product.groups)
      for (final c in g.choices)
        if (c.selected) modifier(g, c),
  ];
  final result = await showDialog<ComboSheetResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Directionality(
      textDirection: copy.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: ComboSheet(
        key: const ValueKey('quick-combo-options'),
        title: mealSetup == null
            ? copy.name(product.name, product.nameAr)
            : '${copy.name(product.name, product.nameAr)} '
                  '${copy.name(mealSetup.name, mealSetup.nameAr)}',
        isMeal: mealSetup != null,
        lines: lines,
        main: mealSetup == null
            ? null
            : ComboSheetMain(
                productId: '${product.id}',
                modifiers: initial == null
                    ? defaultMain
                    : modifiersFor(product.id, initialMainIds),
                notes: initial?['notes'] as String? ?? '',
              ),
        initial: [
          if (initial != null)
            for (final pick in serverComboPicks(initial))
              ComboSelection(
                lineId: pick.lineId,
                productId: '${pick.productId}',
                qty: pick.quantity,
                modifiers: modifiersFor(pick.productId, pick.addonIds),
                notes: pick.notes ?? '',
              ),
        ],
        source: ComboSheetSource(
          itemFor: (id) => switch (item(int.tryParse(id) ?? 0)) {
            final QuickProduct p => ComboSheetItem(
              id: id,
              name: p.name,
              nameAr: p.nameAr,
              available: p.available,
              hasOptions: p.groups.isNotEmpty,
            ),
            null => null,
          },
          unitPriceBaisas: price,
          defaultOptions: (id) => [
            for (final g
                in item(int.tryParse(id) ?? 0)?.groups ?? const <QuickGroup>[])
              for (final c in g.choices)
                if (c.selected) modifier(g, c),
          ],
          optionsComplete: complete,
          editOptions: (sheetContext, id, current) => showDialog(
            context: sheetContext,
            builder: (_) => Directionality(
              textDirection: copy.arabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: _QuickItemOptions(
                item(int.tryParse(id) ?? 0) ??
                    QuickProduct(int.tryParse(id) ?? 0, '#$id'),
                copy,
                current,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (result == null) return null;
  return QrQuickLine(
    product.id,
    ((initial?['qty'] as num?) ?? 1).round().clamp(1, 99),
    mealSetup == null
        ? const []
        : [
            for (final m in result.mainModifiers)
              if (int.tryParse(m.id) case final int id) id,
          ],
    notes: mealSetup == null
        ? (initial?['notes'] as String?)
        : (result.mainNotes.trim().isEmpty ? null : result.mainNotes.trim()),
    mealId: mealSetup?.id,
    combo: [
      for (final s in result.selections)
        QrQuickComboPick(
          s.lineId,
          int.parse(s.productId),
          quantity: s.qty,
          addons: [
            for (final m in s.modifiers)
              if (int.tryParse(m.id) case final int id) id,
          ],
          notes: s.notes.trim().isEmpty ? null : s.notes.trim(),
        ),
    ],
  );
}

/// One item's own options inside a server-priced combo / meal: its add-on
/// groups (minus remove prices shown; nothing auto-ticked) and notes.
class _QuickItemOptions extends StatefulWidget {
  const _QuickItemOptions(this.product, this.copy, this.current);
  final QuickProduct product;
  final QuickCopy copy;
  final ComboItemOptions current;
  @override
  State<_QuickItemOptions> createState() => _QuickItemOptionsState();
}

class _QuickItemOptionsState extends State<_QuickItemOptions> {
  late final selected = <int>{
    for (final m in widget.current.modifiers)
      if (int.tryParse(m.id) case final int id) id,
  };
  late String notes = widget.current.notes;

  bool get valid => widget.product.groups.every((g) {
    final count = g.choices.where((o) => selected.contains(o.id)).length;
    return count >= g.min && count <= g.max;
  });

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;
    return AlertDialog(
      key: const ValueKey('quick-item-options'),
      title: Text(copy.name(widget.product.name, widget.product.nameAr)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final group in widget.product.groups) ...[
                Text(
                  '${copy.name(group.name, group.nameAr)} (${group.min}–${group.max})',
                ),
                for (final option in group.choices)
                  CheckboxListTile(
                    key: ValueKey('quick-item-option-${option.id}'),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(copy.name(option.name, option.nameAr)),
                    subtitle: option.priceBaisas == 0
                        ? null
                        : Text(
                            '${option.priceBaisas < 0 ? '-' : '+'}'
                            '${(option.priceBaisas.abs() / 1000).toStringAsFixed(3)}',
                          ),
                    value: selected.contains(option.id),
                    onChanged: (checked) => setState(() {
                      if (checked != true) {
                        selected.remove(option.id);
                      } else {
                        if (group.max == 1) {
                          selected.removeAll(group.choices.map((o) => o.id));
                        }
                        selected.add(option.id);
                      }
                    }),
                  ),
              ],
              TextFormField(
                initialValue: notes,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: copy.pair('Notes', 'ملاحظات'),
                ),
                onChanged: (v) => notes = v,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.cancel),
        ),
        FilledButton(
          key: const ValueKey('quick-item-options-done'),
          onPressed: valid
              ? () => Navigator.pop<ComboItemOptions>(context, (
                  modifiers: [
                    for (final g in widget.product.groups)
                      for (final c in g.choices)
                        if (selected.contains(c.id))
                          CartItemModifier(
                            id: '${c.id}',
                            group: g.name,
                            label: c.name,
                            labelAr: c.nameAr,
                            price: c.priceBaisas / 1000,
                          ),
                  ],
                  notes: notes,
                ))
              : null,
          child: Text(copy.pair('Done', 'تم')),
        ),
      ],
    );
  }
}

/// LAUNCH combo add-on — pick (or edit, [initial]) one server-priced line:
/// a combo opens the combo sheet (a fixed-only combo is added at once); a
/// main with a meal asks "Make it a meal?" (an existing meal line reopens
/// the meal sheet); anything else opens the add-on sheet.
Future<QrQuickLine?> quickPickLine(
  BuildContext context,
  QuickProduct product,
  QuickCopy copy, {
  List<QuickProduct> catalogue = const [],
  Map<String, dynamic>? initial,
}) async {
  if (product.isCombo) {
    if (initial == null &&
        !comboNeedsSheet(product.comboLines) &&
        product.comboLines.every(
          (l) =>
              catalogue
                  .where((p) => p.id == l.productId)
                  .firstOrNull
                  ?.groups
                  .every((g) => g.min == 0) ??
              true,
        )) {
      return QrQuickLine(product.id, 1, const []);
    }
    return _quickComboSheet(
      context,
      product,
      copy,
      catalogue: catalogue,
      initial: initial,
    );
  }
  final meal = product.meal;
  if (meal != null) {
    final editingMeal = initial != null && initial['meal_id'] == meal.id;
    final yes = initial != null
        ? editingMeal
        : await showMealOffer(
            context,
            mainName: copy.name(product.name, product.nameAr),
            mealName: copy.name(meal.name, meal.nameAr),
            mealPriceBaisas: meal.mealPriceBaisas,
          );
    if (yes == null || !context.mounted) return null;
    if (yes) {
      return _quickComboSheet(
        context,
        product,
        copy,
        catalogue: catalogue,
        initial: initial,
        meal: true,
      );
    }
  }
  if (!context.mounted) return null;
  return showDialog<QrQuickLine>(
    context: context,
    builder: (_) => quickOptionsDialog(product, copy, initial: initial),
  );
}

/// The add-on sheet for a standard server-priced pick (a combo or a meal
/// goes through [quickPickLine]).
Widget quickOptionsDialog(
  QuickProduct product,
  QuickCopy copy, {
  Map<String, dynamic>? initial,
}) => Directionality(
  textDirection: copy.arabic ? TextDirection.rtl : TextDirection.ltr,
  child: _ProductOptions(product, copy, initial: initial),
);
