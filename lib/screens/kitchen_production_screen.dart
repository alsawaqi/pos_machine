import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/kitchen_production.dart';
import '../providers/providers.dart';
import '../services/pos_api_service.dart';

/// P-G1 — the KITCHEN production screen: cooked products made ahead of sale
/// in two-phase timed batches. ONLINE-ONLY by design: starting a batch
/// deducts ingredients server-side against fresh locked balances, so the
/// screen always fetches live numbers (`GET /device/kitchen`).
///
/// Entry is gated by the merchant's `kitchen_positions` policy in
/// StaffPosScreen (the reports-screen precedent). Cancel is manager-gated:
/// the PIN rides the cancel request and pos_api verifies it against the
/// company's manager_approval_positions policy.
class KitchenProductionScreen extends ConsumerStatefulWidget {
  const KitchenProductionScreen({super.key, this.staffId});

  /// The logged-in staff member (stamped on start/finish/cancel).
  final int? staffId;

  @override
  ConsumerState<KitchenProductionScreen> createState() =>
      _KitchenProductionScreenState();
}

class _KitchenProductionScreenState
    extends ConsumerState<KitchenProductionScreen> {
  // The branch-reports palette — the satellite-screen look.
  static const _bg = Color(0xFF0E1D26);
  static const _card = Color(0xFF16313B);
  static const _cardBorder = Color(0xFF1F4250);
  static const _accent = Color(0xFF35C28B);
  static const _warn = Color(0xFFFFB45D);
  static const _danger = Color(0xFFFF6B6B);

  KitchenData? _data;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Live elapsed timers on the in-progress batches.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_data?.active.isNotEmpty ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiServiceProvider).fetchKitchen();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.isNetwork ? L10n.of(context).kitchenOffline : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = L10n.of(context).kitchenLoadFailed;
      });
    }
  }

  void _toast(String message, {Color color = _accent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _apiErrorText(Object e) {
    final l10n = L10n.of(context);
    if (e is ApiException) {
      return e.isNetwork ? l10n.kitchenOffline : e.message;
    }
    return l10n.kitchenLoadFailed;
  }

  // ------------------------------------------------------------ actions

  Future<void> _startBatch(KitchenProduct product) async {
    final data = _data;
    if (data == null) return;
    final request = await showDialog<_StartBatchRequest>(
      context: context,
      builder: (_) => _StartBatchDialog(
        product: product,
        ingredients: data.ingredients,
        isAr: Directionality.of(context) == TextDirection.rtl,
      ),
    );
    if (request == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiServiceProvider).startProduction(
            productId: product.id,
            quantity: request.quantity,
            staffId: widget.staffId,
            extras: request.extras,
          );
      if (!mounted) return;
      _toast(L10n.of(context).kitchenBatchStarted);
    } catch (e) {
      if (!mounted) return;
      _toast(_apiErrorText(e), color: _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _finishBatch(ProductionBatch batch) async {
    // P-G1.5 — the chef confirms (or adjusts) the batch expiry. Prefilled
    // from the product's shelf life; one tap keeps the default.
    final shelfLifeDays = _data?.products
        .where((p) => p.id == batch.productId)
        .firstOrNull
        ?.shelfLifeDays;
    final choice = await showDialog<_FinishExpiryChoice>(
      context: context,
      builder: (_) => _FinishBatchDialog(
        batch: batch,
        shelfLifeDays: shelfLifeDays,
        isAr: Directionality.of(context) == TextDirection.rtl,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiServiceProvider).finishProduction(
            uuid: batch.uuid,
            staffId: widget.staffId,
            expiresAtIso: choice.expiresAt?.toIso8601String(),
          );
      if (!mounted) return;
      _toast(L10n.of(context).kitchenBatchFinished);
    } catch (e) {
      if (!mounted) return;
      _toast(_apiErrorText(e), color: _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _cancelBatch(ProductionBatch batch) async {
    final l10n = L10n.of(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _ManagerPinPromptDialog(),
    );
    if (pin == null || pin.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final cancelled = await ref.read(apiServiceProvider).cancelProduction(
            uuid: batch.uuid,
            pin: pin,
            staffId: widget.staffId,
          );
      if (!mounted) return;
      if (cancelled == null) {
        _toast(l10n.kitchenPinInvalid, color: _danger);
      } else {
        _toast(l10n.kitchenBatchCancelled, color: _warn);
      }
    } catch (e) {
      if (!mounted) return;
      _toast(_apiErrorText(e), color: _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  // ------------------------------------------------------------ helpers

  /// Category display names resolved from the cached catalog (the kitchen
  /// payload carries ids; the catalog products carry the names).
  Map<int, String> _categoryNames(bool isAr) {
    final catalog = ref.read(catalogProvider).asData?.value;
    if (catalog == null) return const <int, String>{};
    final out = <int, String>{};
    for (final p in catalog.products) {
      final id = p.categoryId;
      if (id == null || out.containsKey(id)) continue;
      final en = p.category;
      out[id] = isAr ? (catalog.categoryNamesAr[en] ?? en) : en;
    }
    return out;
  }

  static String _elapsed(DateTime? startedAt) {
    if (startedAt == null) return '--:--';
    final d = DateTime.now().difference(startedAt);
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String _qty(double v) {
    final s = v.toStringAsFixed(3);
    return s.contains('.')
        ? s.replaceAll(RegExp(r'\.?0+$'), '')
        : s;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.soup_kitchen_outlined, color: _accent),
            const SizedBox(width: 10),
            Text(
              l10n.kitchenTitle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.kitchenRefresh,
            onPressed: _loading || _busy ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: () => unawaited(_load()))
              : _buildContent(l10n, isAr),
    );
  }

  Widget _buildContent(L10n l10n, bool isAr) {
    final data = _data!;
    final categoryNames = _categoryNames(isAr);

    // Group the cooked products by category (stable order: as delivered).
    final sections = <int?, List<KitchenProduct>>{};
    for (final p in data.products) {
      sections.putIfAbsent(p.categoryId, () => <KitchenProduct>[]).add(p);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- products, grouped by menu category ----
        Expanded(
          flex: 3,
          child: data.products.isEmpty
              ? Center(
                  child: Text(
                    l10n.kitchenNoProducts,
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entry in sections.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          entry.key != null
                              ? (categoryNames[entry.key] ?? l10n.kitchenOtherCategory)
                              : l10n.kitchenOtherCategory,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final product in entry.value)
                            _ProductCard(
                              product: product,
                              isAr: isAr,
                              enabled: !_busy,
                              onTap: () => unawaited(_startBatch(product)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
        ),
        // ---- active batches ----
        Container(width: 1, color: _cardBorder),
        SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.kitchenActiveTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: data.active.isEmpty
                    ? Center(
                        child: Text(
                          l10n.kitchenNoActive,
                          style: const TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: data.active.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final batch = data.active[index];
                          return _ActiveBatchCard(
                            batch: batch,
                            isAr: isAr,
                            elapsed: _elapsed(batch.startedAt),
                            enabled: !_busy,
                            onFinish: () => unawaited(_finishBatch(batch)),
                            onCancel: () => unawaited(_cancelBatch(batch)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- widgets

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _KitchenProductionScreenState._accent,
            ),
            onPressed: onRetry,
            child: Text(l10n.kitchenRetry),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.isAr,
    required this.enabled,
    required this.onTap,
  });

  final KitchenProduct product;
  final bool isAr;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = isAr ? (product.nameAr ?? product.name) : product.name;
    final max = product.maxProducible;
    final canMakeAny = max == null || max > 0;
    final shelf = product.branchStockQty ?? 0;

    return InkWell(
      onTap: enabled && canMakeAny ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: canMakeAny ? 1 : 0.45,
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _KitchenProductionScreenState._card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _KitchenProductionScreenState._cardBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      color: Colors.white38, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    l10n.kitchenShelfCount(
                        _KitchenProductionScreenState._qty(shelf)),
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(
                    canMakeAny
                        ? Icons.local_fire_department_outlined
                        : Icons.block_rounded,
                    color: canMakeAny
                        ? _KitchenProductionScreenState._accent
                        : _KitchenProductionScreenState._danger,
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      max == null
                          ? l10n.kitchenNoRecipe
                          : l10n.kitchenCanMake(max),
                      style: TextStyle(
                        color: canMakeAny
                            ? _KitchenProductionScreenState._accent
                            : _KitchenProductionScreenState._danger,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBatchCard extends StatelessWidget {
  const _ActiveBatchCard({
    required this.batch,
    required this.isAr,
    required this.elapsed,
    required this.enabled,
    required this.onFinish,
    required this.onCancel,
  });

  final ProductionBatch batch;
  final bool isAr;
  final String elapsed;
  final bool enabled;
  final VoidCallback onFinish;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = isAr
        ? (batch.productNameAr ?? batch.productName ?? '')
        : (batch.productName ?? '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _KitchenProductionScreenState._card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _KitchenProductionScreenState._cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$name × ${_KitchenProductionScreenState._qty(batch.quantity)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _KitchenProductionScreenState._warn.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        color: _KitchenProductionScreenState._warn, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      elapsed,
                      style: const TextStyle(
                        color: _KitchenProductionScreenState._warn,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((batch.startedBy ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              l10n.kitchenStartedBy(batch.startedBy!),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (batch.expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.kitchenExpiresOn(
                '${batch.expiresAt!.year}-${batch.expiresAt!.month.toString().padLeft(2, '0')}-${batch.expiresAt!.day.toString().padLeft(2, '0')}',
              ),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _KitchenProductionScreenState._accent,
                  ),
                  onPressed: enabled ? onFinish : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(l10n.kitchenFinish),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _KitchenProductionScreenState._danger,
                  side: const BorderSide(
                      color: _KitchenProductionScreenState._danger),
                ),
                onPressed: enabled ? onCancel : null,
                child: Text(l10n.kitchenCancelBatch),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- dialogs

class _StartBatchRequest {
  const _StartBatchRequest({required this.quantity, required this.extras});

  final int quantity;
  final List<({int ingredientId, double quantity})> extras;
}

/// The start dialog: a quantity stepper, the LOCKED recipe preview
/// (per-piece x quantity, against the live balances), and the declared
/// extras editor. Confirm returns a [_StartBatchRequest]; the server is
/// still the authority (it re-checks fresh balances under lock).
class _StartBatchDialog extends StatefulWidget {
  const _StartBatchDialog({
    required this.product,
    required this.ingredients,
    required this.isAr,
  });

  final KitchenProduct product;
  final List<KitchenIngredient> ingredients;
  final bool isAr;

  @override
  State<_StartBatchDialog> createState() => _StartBatchDialogState();
}

class _ExtraRow {
  int? ingredientId;
  final TextEditingController qty = TextEditingController();
}

class _StartBatchDialogState extends State<_StartBatchDialog> {
  int _quantity = 1;
  final List<_ExtraRow> _extras = [];

  @override
  void dispose() {
    for (final row in _extras) {
      row.qty.dispose();
    }
    super.dispose();
  }

  /// Whether the live balances cover quantity x recipe (extras are checked
  /// server-side; this is just the immediate UI guard).
  bool get _recipeCovered {
    for (final line in widget.product.recipe) {
      if (line.quantity * _quantity > line.branchBalance + 1e-9) return false;
    }
    return true;
  }

  List<({int ingredientId, double quantity})> get _extraPayload => [
        for (final row in _extras)
          if (row.ingredientId != null &&
              (double.tryParse(row.qty.text.trim()) ?? 0) > 0)
            (
              ingredientId: row.ingredientId!,
              quantity: double.parse(row.qty.text.trim()),
            ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final product = widget.product;
    final name = widget.isAr ? (product.nameAr ?? product.name) : product.name;
    final max = product.maxProducible;

    return AlertDialog(
      backgroundColor: const Color(0xFF16313B),
      title: Text(
        l10n.kitchenStartBatchTitle(name),
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- quantity stepper ----
              Row(
                children: [
                  Text(
                    l10n.kitchenQuantity,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.white70),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '$_quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _quantity++),
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.white70),
                  ),
                ],
              ),
              if (max != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    l10n.kitchenCanMake(max),
                    style: TextStyle(
                      color: _quantity <= max
                          ? const Color(0xFF35C28B)
                          : const Color(0xFFFF6B6B),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              // ---- locked recipe ----
              if (product.recipe.isNotEmpty) ...[
                Text(
                  l10n.kitchenRecipeLocked,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                for (final line in product.recipe)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.isAr ? (line.nameAr ?? line.name) : line.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        Text(
                          '${_KitchenProductionScreenState._qty(line.quantity * _quantity)} ${line.unit}',
                          style: TextStyle(
                            color: line.quantity * _quantity >
                                    line.branchBalance + 1e-9
                                ? const Color(0xFFFF6B6B)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' / ${_KitchenProductionScreenState._qty(line.branchBalance)}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                if (!_recipeCovered)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.kitchenInsufficient,
                      style: const TextStyle(
                          color: Color(0xFFFF6B6B), fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
              // ---- declared extras ----
              Row(
                children: [
                  Text(
                    l10n.kitchenExtrasTitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _extras.add(_ExtraRow())),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(l10n.kitchenAddExtra),
                  ),
                ],
              ),
              for (final (index, row) in _extras.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          initialValue: row.ingredientId,
                          dropdownColor: const Color(0xFF16313B),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            isDense: true,
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                          ),
                          items: [
                            for (final ingredient in widget.ingredients)
                              DropdownMenuItem(
                                value: ingredient.id,
                                child: Text(
                                  widget.isAr
                                      ? (ingredient.nameAr ?? ingredient.name)
                                      : ingredient.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => row.ingredientId = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: row.qty,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.kitchenExtraQtyHint(
                              row.ingredientId != null
                                  ? widget.ingredients
                                      .firstWhere(
                                        (i) => i.id == row.ingredientId,
                                        orElse: () => const KitchenIngredient(
                                          id: 0,
                                          name: '',
                                          unit: '',
                                          branchBalance: 0,
                                        ),
                                      )
                                      .unit
                                  : '',
                            ),
                            hintStyle: const TextStyle(color: Colors.white30),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _extras.removeAt(index).qty.dispose();
                        }),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.kitchenDialogCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF35C28B),
          ),
          onPressed: _recipeCovered &&
                  (widget.product.maxProducible == null ||
                      _quantity <= widget.product.maxProducible!)
              ? () => Navigator.of(context).pop(_StartBatchRequest(
                    quantity: _quantity,
                    extras: _extraPayload,
                  ))
              : null,
          child: Text(l10n.kitchenStart),
        ),
      ],
    );
  }
}

/// P-G1.5 — the chef's confirmed batch expiry. `expiresAt` null = the
/// batch never expires (a deliberate choice, distinct from cancelling).
class _FinishExpiryChoice {
  const _FinishExpiryChoice(this.expiresAt);

  final DateTime? expiresAt;
}

/// P-G1.5 — the Finish dialog: confirm the batch expiry with one tap
/// (prefilled from the product's shelf life) or adjust it with the quick
/// chips / date picker. The chef's entry is the per-batch truth.
class _FinishBatchDialog extends StatefulWidget {
  const _FinishBatchDialog({
    required this.batch,
    required this.shelfLifeDays,
    required this.isAr,
  });

  final ProductionBatch batch;
  final int? shelfLifeDays;
  final bool isAr;

  @override
  State<_FinishBatchDialog> createState() => _FinishBatchDialogState();
}

class _FinishBatchDialogState extends State<_FinishBatchDialog> {
  /// Days-from-today for the selected chip; null = never expires;
  /// -1 = a custom picker date held in [_customDate].
  int? _selectedDays;
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _selectedDays = widget.shelfLifeDays; // null = never (the default flows)
  }

  DateTime? get _resolved {
    if (_selectedDays == -1) {
      final d = _customDate;
      return d == null ? null : DateTime(d.year, d.month, d.day, 23, 59, 59);
    }
    return defaultBatchExpiry(DateTime.now(), _selectedDays);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = widget.isAr
        ? (widget.batch.productNameAr ?? widget.batch.productName ?? '')
        : (widget.batch.productName ?? '');

    // Quick chips: today / tomorrow / +2d (+ the product default when it
    // is bigger than 2 days) / never.
    final dayChips = <int>{0, 1, 2, if ((widget.shelfLifeDays ?? 0) > 2) widget.shelfLifeDays!}
        .toList()
      ..sort();

    String chipLabel(int days) => switch (days) {
          0 => l10n.kitchenExpiryToday,
          1 => l10n.kitchenExpiryTomorrow,
          _ => l10n.kitchenExpiryInDays(days),
        };

    return AlertDialog(
      backgroundColor: const Color(0xFF16313B),
      title: Text(
        l10n.kitchenFinishTitle(name),
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.kitchenExpiryLabel,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in dayChips)
                  ChoiceChip(
                    label: Text(chipLabel(days)),
                    selected: _selectedDays == days,
                    selectedColor: const Color(0xFF35C28B),
                    labelStyle: TextStyle(
                      color: _selectedDays == days ? Colors.white : Colors.white70,
                    ),
                    backgroundColor: const Color(0xFF0E1D26),
                    onSelected: (_) => setState(() => _selectedDays = days),
                  ),
                ChoiceChip(
                  label: Text(l10n.kitchenExpiryNever),
                  selected: _selectedDays == null,
                  selectedColor: const Color(0xFFFFB45D),
                  labelStyle: TextStyle(
                    color: _selectedDays == null ? Colors.white : Colors.white70,
                  ),
                  backgroundColor: const Color(0xFF0E1D26),
                  onSelected: (_) => setState(() => _selectedDays = null),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_outlined,
                      size: 16, color: Colors.white70),
                  label: Text(
                    _selectedDays == -1 && _customDate != null
                        ? '${_customDate!.year}-${_customDate!.month.toString().padLeft(2, '0')}-${_customDate!.day.toString().padLeft(2, '0')}'
                        : l10n.kitchenExpiryPickDate,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  backgroundColor: _selectedDays == -1
                      ? const Color(0xFF35C28B)
                      : const Color(0xFF0E1D26),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _customDate ?? now.add(const Duration(days: 1)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() {
                        _customDate = picked;
                        _selectedDays = -1;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _resolved == null
                  ? l10n.kitchenExpiryNeverHint
                  : l10n.kitchenExpiryResolvedHint(
                      '${_resolved!.year}-${_resolved!.month.toString().padLeft(2, '0')}-${_resolved!.day.toString().padLeft(2, '0')}',
                    ),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.kitchenDialogCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF35C28B),
          ),
          onPressed: _selectedDays == -1 && _customDate == null
              ? null
              : () => Navigator.of(context).pop(_FinishExpiryChoice(_resolved)),
          child: Text(l10n.kitchenFinish),
        ),
      ],
    );
  }
}

/// P-G1.5 — the day-end disposition screen, shown right before shift close
/// when cooked pieces have EXPIRED at this branch. Per product the closer
/// splits the expired remainder across Waste (free), Give-away (manager
/// PIN + a required comment naming the recipient), and Keep-on-sale
/// (manager PIN, audited). ONLINE-ONLY — the server is the authority.
class DayEndDispositionScreen extends ConsumerStatefulWidget {
  const DayEndDispositionScreen({
    super.key,
    required this.items,
    this.staffId,
  });

  final List<DispositionItem> items;
  final int? staffId;

  @override
  ConsumerState<DayEndDispositionScreen> createState() =>
      _DayEndDispositionScreenState();
}

class _DispositionEntry {
  _DispositionEntry(this.item) : waste = item.expiredQty;

  final DispositionItem item;
  double waste;
  double gift = 0;
  double carry = 0;
  final TextEditingController giftComment = TextEditingController();

  double get total => waste + gift + carry;
}

class _DayEndDispositionScreenState
    extends ConsumerState<DayEndDispositionScreen> {
  static const _bg = Color(0xFF0E1D26);
  static const _card = Color(0xFF16313B);
  static const _cardBorder = Color(0xFF1F4250);
  static const _accent = Color(0xFF35C28B);
  static const _warn = Color(0xFFFFB45D);
  static const _danger = Color(0xFFFF6B6B);

  late final List<_DispositionEntry> _entries =
      widget.items.map(_DispositionEntry.new).toList();
  bool _busy = false;

  @override
  void dispose() {
    for (final e in _entries) {
      e.giftComment.dispose();
    }
    super.dispose();
  }

  bool get _needsApproval =>
      _entries.any((e) => e.gift > 0 || e.carry > 0);

  bool get _giftCommentsOk => _entries.every(
      (e) => e.gift <= 0 || e.giftComment.text.trim().isNotEmpty);

  bool get _splitsOk => _entries.every(
      (e) => (e.total - e.item.expiredQty).abs() < 0.001);

  Future<void> _submit() async {
    final l10n = L10n.of(context);

    String? pin;
    if (_needsApproval) {
      pin = await showDialog<String>(
        context: context,
        builder: (_) => const _ManagerPinPromptDialog(),
      );
      if (pin == null || pin.isEmpty || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final ok = await ref.read(apiServiceProvider).applyDisposition(
            staffId: widget.staffId,
            pin: pin,
            items: [
              for (final e in _entries)
                if (e.waste > 0 || e.gift > 0 || e.carry > 0)
                  {
                    'product_id': e.item.productId,
                    'waste_qty': e.waste,
                    'give_away_qty': e.gift,
                    'carry_over_qty': e.carry,
                    if (e.gift > 0)
                      'give_away_comment': e.giftComment.text.trim(),
                  },
            ],
          );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.kitchenPinInvalid),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.dispositionDone),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.isNetwork ? l10n.kitchenOffline : e.message),
        backgroundColor: _danger,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _qty(double v) {
    final s = v.toStringAsFixed(3);
    return s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s;
  }

  Widget _stepper({
    required String label,
    required Color color,
    required double value,
    required double maxTotal,
    required double currentTotal,
    required void Function(double) onChanged,
  }) {
    final canAdd = currentTotal < maxTotal - 0.001;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(color: color, fontSize: 13)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > 0 ? () => onChanged(value - 1 < 0 ? 0 : value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline,
              color: Colors.white54, size: 20),
        ),
        SizedBox(
          width: 44,
          child: Text(
            _qty(value),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: canAdd ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline,
              color: Colors.white54, size: 20),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isAr = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.schedule_outlined, color: _warn),
            const SizedBox(width: 10),
            Text(
              l10n.dispositionTitle,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.dispositionSubtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final item = entry.item;
                final name = isAr ? (item.nameAr ?? item.name) : item.name;
                final remaining = item.expiredQty - entry.total;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            l10n.dispositionExpiredCount(
                                _qty(item.expiredQty), _qty(item.branchStockQty)),
                            style: const TextStyle(
                                color: _warn, fontSize: 12.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _stepper(
                        label: l10n.dispositionWaste,
                        color: _danger,
                        value: entry.waste,
                        maxTotal: item.expiredQty,
                        currentTotal: entry.total,
                        onChanged: (v) => setState(() => entry.waste = v),
                      ),
                      _stepper(
                        label: l10n.dispositionGiveAway,
                        color: _warn,
                        value: entry.gift,
                        maxTotal: item.expiredQty,
                        currentTotal: entry.total,
                        onChanged: (v) => setState(() => entry.gift = v),
                      ),
                      _stepper(
                        label: l10n.dispositionCarryOver,
                        color: _accent,
                        value: entry.carry,
                        maxTotal: item.expiredQty,
                        currentTotal: entry.total,
                        onChanged: (v) => setState(() => entry.carry = v),
                      ),
                      if (remaining.abs() > 0.001)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l10n.dispositionRemaining(_qty(remaining)),
                            style: const TextStyle(
                                color: _danger, fontSize: 12),
                          ),
                        ),
                      if (entry.gift > 0) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: entry.giftComment,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.dispositionGiftCommentHint,
                            hintStyle: const TextStyle(color: Colors.white30),
                            enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.dispositionSkip,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: !_busy && _splitsOk && _giftCommentsOk
                        ? () => unawaited(_submit())
                        : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(l10n.dispositionSubmit),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A minimal manager-PIN prompt for the cancel gate. The PIN itself rides
/// the cancel request and is verified server-side (the device never decides).
class _ManagerPinPromptDialog extends StatefulWidget {
  const _ManagerPinPromptDialog();

  @override
  State<_ManagerPinPromptDialog> createState() =>
      _ManagerPinPromptDialogState();
}

class _ManagerPinPromptDialogState extends State<_ManagerPinPromptDialog> {
  final TextEditingController _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF16313B),
      title: Text(
        l10n.kitchenPinTitle,
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 8,
        style: const TextStyle(
            color: Colors.white, fontSize: 22, letterSpacing: 8),
        decoration: InputDecoration(
          hintText: l10n.kitchenPinHint,
          hintStyle: const TextStyle(
              color: Colors.white30, fontSize: 14, letterSpacing: 0),
          counterText: '',
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (v.trim().length >= 4) Navigator.of(context).pop(v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.kitchenDialogCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B6B),
          ),
          onPressed: _pin.text.trim().length >= 4
              ? () => Navigator.of(context).pop(_pin.text.trim())
              : null,
          child: Text(l10n.kitchenCancelBatch),
        ),
      ],
    );
  }
}
