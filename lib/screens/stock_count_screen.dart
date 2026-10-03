import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/count_units.dart';
import '../models/pos_models.dart';
import '../providers/providers.dart';
import '../services/expense_restock_payload.dart';
import '../services/expense_restock_service.dart';

/// Phase A (Additions §2.8) — the day-end physical stock count.
///
/// A BLIND count (LAUNCH-P2): lists every ingredient in the cached catalogue
/// WITHOUT its on-book branch balance — staff type only what is PHYSICALLY
/// on the shelf, in pieces for piece-tracked ingredients ("5 bottles"), in
/// kg or g / l or ml (staff pick; sent in the stored unit) for Weighed and
/// Liquid ones, in the stored unit otherwise. A blank row is skipped. Submitting pushes one
/// `stock.count` event over the device sync pipeline (online-required, like
/// restock requests); the server reconciles: shortfall → waste movement
/// (reason reconciliation_variance), overage → adjustment. The device then
/// only confirms the submit — the variance is shown in the portal, to users
/// who may see stock values, never on the till.
class StockCountScreen extends ConsumerStatefulWidget {
  const StockCountScreen({super.key});

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen> {
  final Map<int, TextEditingController> _counted = {};

  /// LAUNCH item kind — the unit each Weighed / Liquid line is counted in
  /// (kg or g, l or ml); the largest unit until staff switch it.
  final Map<int, String> _countUnit = {};
  final _noteController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _counted.values) {
      c.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(int ingredientId) =>
      _counted.putIfAbsent(ingredientId, TextEditingController.new);

  int get _filledCount => _counted.values
      .where((c) => c.text.trim().isNotEmpty)
      .length;

  /// The unit [ing] is being counted in when it can be counted in more than
  /// one (Weighed / Liquid, not counted in pieces); null otherwise.
  String? _typedUnitFor(IngredientRef ing) {
    if (ing.isPieceCounted) return null;
    final choices = countUnitChoices(ing.unit);
    if (choices.isEmpty) return null;
    return _countUnit[ing.id] ?? choices.first;
  }

  Future<void> _submit(List<IngredientRef> ingredients) async {
    // Captured before any await so localized strings are safe to use after
    // the async gaps below (paired with the existing mounted guards).
    final l10n = L10n.of(context);
    final lines = <StockCountLineInput>[];
    for (final ing in ingredients) {
      final raw = _counted[ing.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final value = double.tryParse(raw);
      if (value == null || value < 0) {
        setState(() => _error = l10n.stockCountInvalidCount(ing.name));
        return;
      }
      if (ing.isPieceCounted &&
          !ing.allowFractionalPieces &&
          value != value.roundToDouble()) {
        setState(() => _error = l10n.stockCountWholeUnitsOnly(
            ing.name, ing.countableLabel ?? ''));
        return;
      }
      final typedUnit = _typedUnitFor(ing);
      lines.add(ing.isPieceCounted
          ? StockCountLineInput(ingredientId: ing.id, countedPieces: value)
          : StockCountLineInput(
              ingredientId: ing.id,
              // Sent in the stored unit, as before (12 l → 12000 ml).
              countedUnits: typedUnit == null
                  ? value
                  : toStoredUnits(value, typedUnit, ing.unit!),
            ));
    }
    if (lines.isEmpty) {
      setState(() => _error = l10n.stockCountEnterAtLeastOne);
      return;
    }

    final note = _noteController.text.trim();
    final staffId = ref.read(sessionControllerProvider).staff?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(expenseRestockServiceProvider).submitStockCount(
            lines: lines,
            staffId: staffId,
            note: note.isEmpty ? null : note,
          );
      // Refresh the cached config so the device's copy of the corrected
      // balances is current without waiting for the next scheduled sync.
      // Best-effort: the count itself already settled server-side.
      try {
        await ref.read(configRepositoryProvider).syncConfig();
      } catch (_) {}
      if (mounted) {
        // Blind count (LAUNCH-P2): the same neutral confirmation whatever
        // the server found — never a variance figure or "matched".
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.stockCountSubmitted)),
        );
        Navigator.of(context).pop();
      }
    } on DeviceActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.stockCountSubmitFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final catalog = ref.watch(catalogProvider).asData?.value;
    final ingredients = catalog?.ingredients ?? const <IngredientRef>[];

    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: Text(l10n.stockCountTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ingredients.isEmpty
              ? _emptyState()
              : Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 4),
                      child: Text(
                        l10n.stockCountInstructions,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        itemCount: ingredients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _row(ingredients[i]),
                      ),
                    ),
                    _footer(ingredients),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _row(IngredientRef ing) {
    final l10n = L10n.of(context);
    final pieceLabel = ing.countableLabel;
    final typedUnit = _typedUnitFor(ing);
    final unit = typedUnit ?? ing.unit ?? '';
    // Blind count (LAUNCH-P2): say what to count in, never how much the
    // books expect.
    final countIn = pieceLabel != null
        ? l10n.stockCountRowCountInPieces(pieceLabel)
        : (unit.isEmpty ? null : l10n.stockCountRowCountInUnit(unit));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16313B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ing.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                if (countIn != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    countIn,
                    style: TextStyle(
                      color: pieceLabel != null
                          ? const Color(0xFFE8B45A)
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
                // LAUNCH item kind — count a Weighed / Liquid line in either
                // unit of its kind (kg or g, l or ml).
                if (typedUnit != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final u in countUnitChoices(ing.unit))
                        ChoiceChip(
                          key: ValueKey('count-unit-${ing.id}-$u'),
                          label: Text(u),
                          selected: u == typedUnit,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _countUnit[ing.id] = u),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _controllerFor(ing.id),
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: pieceLabel ??
                    (unit.isEmpty ? l10n.stockCountQtyHint : unit),
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF0E2129),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(List<IngredientRef> ingredients) {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _noteController,
            enabled: !_busy,
            maxLength: 1000,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.stockCountNoteLabel,
              labelStyle: const TextStyle(color: Colors.white54),
              counterText: '',
              filled: true,
              fillColor: const Color(0xFF16313B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: 280,
            height: 52,
            child: FilledButton(
              onPressed: _busy || _filledCount == 0
                  ? null
                  : () => _submit(ingredients),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.stockCountSubmitButton(_filledCount)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.checklist_rounded, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.stockCountEmptyState,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
