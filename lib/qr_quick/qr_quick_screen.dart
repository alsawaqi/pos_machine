import 'dart:async';
import 'package:flutter/material.dart';
import 'qr_quick_controller.dart';
import 'qr_quick_copy.dart';
import 'qr_quick_models.dart';

class QrQuickScreen extends StatefulWidget {
  const QrQuickScreen({
    super.key,
    required this.createController,
    required this.catalogue,
    this.onPay,
    this.onRecoverPayment,
    this.arabic = false,
  });
  final Future<QrQuickController> Function() createController;
  final List<QuickProduct> Function() catalogue;
  final Future<void> Function(BuildContext, QrQuickOrder)? onPay;
  final Future<void> Function()? onRecoverPayment;
  final bool arabic;
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
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  void _schedule() {
    timer?.cancel();
    if (!foreground || covered > 0 || !mounted) return;
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(controller?.refresh());
    });
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
        _schedule();
      }
    }
  }

  Future<void> _pay(String uuid) async {
    if (paying) return;
    paying = true;
    final c = controller!;
    try {
      await c.refresh();
      if (!mounted || !c.canPay(uuid) || widget.onPay == null) return;
      await _child(() => widget.onPay!(context, c.find(uuid)!));
    } finally {
      paying = false;
    }
  }

  Future<void> _open(String uuid) => _child(
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
  Widget build(BuildContext context) => Directionality(
    textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      appBar: AppBar(
        title: Text(copy.title),
        actions: [
          if (widget.onRecoverPayment != null)
            IconButton(
              key: const ValueKey('quick-payment-recovery'),
              tooltip: arabic ? 'تحقق من نتيجة الدفع' : 'Check payment result',
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
                    for (final order in c.orders)
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
                              if (c.pending.containsKey(order.uuid))
                                Text(copy.uncertain),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonal(
                                    key: ValueKey('quick-review-${order.uuid}'),
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
  });
  final QrQuickController controller;
  final String uuid;
  final List<QuickProduct> Function() catalogue;
  final QuickCopy copy;
  final Future<void> Function()? onPay;
  @override
  State<_QuickEditor> createState() => _QuickEditorState();
}

class _QuickEditorState extends State<_QuickEditor> {
  final drafts = <(String, QrQuickLine)>[];
  bool closing = false;
  QuickCopy get copy => widget.copy;
  Future<void> _leave() async {
    if (closing || widget.controller.busy) return;
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
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> _pick() async {
    final products = widget.catalogue();
    final product = await showDialog<QuickProduct>(
      context: context,
      builder: (context) => Directionality(
        textDirection: copy.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: _ProductPicker(products, copy),
      ),
    );
    if (product == null || !mounted) return;
    final line = await showDialog<QrQuickLine>(
      context: context,
      builder: (_) => Directionality(
        textDirection: copy.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: _ProductOptions(product, copy),
      ),
    );
    if (line != null && mounted) {
      setState(
        () => drafts.add((copy.name(product.name, product.nameAr), line)),
      );
    }
  }

  Future<void> _submit() async {
    final c = widget.controller;
    await c.refresh();
    if (!mounted || !c.canAdd(widget.uuid)) return;
    final ok = await c.add(widget.uuid, drafts.map((d) => d.$2).toList());
    if (mounted && (ok || c.pending.containsKey(widget.uuid))) {
      setState(drafts.clear);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final order = c.find(widget.uuid);
      final pending = c.pending[widget.uuid];
      return PopScope(
        canPop: drafts.isEmpty && !c.busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && drafts.isNotEmpty) unawaited(_leave());
        },
        child: Directionality(
          textDirection: copy.arabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(order?.reference ?? widget.uuid),
              actions: [
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
                      title: Text('${item['qty']} × ${item['product_name']}'),
                      subtitle: Text(
                        [
                          for (final addon
                              in (item['addons'] as List? ?? const []))
                            qrMap(addon)['add_on_name'].toString(),
                          if (item['notes'] != null) item['notes'].toString(),
                        ].join(' · '),
                      ),
                      trailing: Text(_money(item['line_total_baisas'] as int)),
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
                      title: Text('${drafts[i].$2.quantity} × ${drafts[i].$1}'),
                      trailing: IconButton(
                        tooltip: copy.pair(
                          'Remove unsent item',
                          'إزالة صنف غير مرسل',
                        ),
                        onPressed: c.busy
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
                        key: const ValueKey('quick-add-items'),
                        onPressed: c.canAdd(widget.uuid) && drafts.length < 50
                            ? _pick
                            : null,
                        child: Text(copy.add),
                      ),
                      FilledButton(
                        key: const ValueKey('quick-submit'),
                        onPressed: c.canAdd(widget.uuid) && drafts.isNotEmpty
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
                    onPressed: c.canPay(widget.uuid) && drafts.isEmpty
                        ? widget.onPay
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
  const _ProductOptions(this.product, this.copy);
  final QuickProduct product;
  final QuickCopy copy;
  @override
  State<_ProductOptions> createState() => _ProductOptionsState();
}

class _ProductOptionsState extends State<_ProductOptions> {
  int qty = 1;
  String notes = '';
  late final selected = <int>{
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
              TextField(
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
