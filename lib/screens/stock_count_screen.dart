import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../providers/providers.dart';
import '../services/expense_restock_payload.dart';
import '../services/expense_restock_service.dart';

/// Phase A (Additions §2.8) — the day-end physical stock count.
///
/// Lists every ingredient in the cached catalogue with its on-book branch
/// balance; staff type what is PHYSICALLY on the shelf — in pieces for
/// piece-tracked ingredients ("5 bottles"), in the base unit otherwise. A
/// blank row is skipped. Submitting pushes one `stock.count` event over the
/// device sync pipeline (online-required, like restock requests); the server
/// reconciles: shortfall → waste movement (reason reconciliation_variance),
/// overage → adjustment. The result snackbar reports how many lines varied.
class StockCountScreen extends ConsumerStatefulWidget {
  const StockCountScreen({super.key});

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen> {
  final Map<int, TextEditingController> _counted = {};
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
      lines.add(ing.isPieceCounted
          ? StockCountLineInput(ingredientId: ing.id, countedPieces: value)
          : StockCountLineInput(ingredientId: ing.id, countedUnits: value));
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
      final result =
          await ref.read(expenseRestockServiceProvider).submitStockCount(
                lines: lines,
                staffId: staffId,
                note: note.isEmpty ? null : note,
              );
      // Refresh the cached config so the corrected balances reach the
      // sold-out logic without waiting for the next scheduled sync.
      // Best-effort: the count itself already settled server-side.
      try {
        await ref.read(configRepositoryProvider).syncConfig();
      } catch (_) {}
      if (mounted) {
        final variance = (result['lines_with_variance'] as num?)?.toInt() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(variance == 0
                ? l10n.stockCountSubmittedNoVariance
                : l10n.stockCountSubmittedWithVariance(variance)),
          ),
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
    final balances = catalog?.ingredientBalances ?? const <int, double>{};

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
                        itemBuilder: (context, i) =>
                            _row(ingredients[i], balances[ingredients[i].id]),
                      ),
                    ),
                    _footer(ingredients),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _row(IngredientRef ing, double? balance) {
    final l10n = L10n.of(context);
    final pieceLabel = ing.countableLabel;
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
                const SizedBox(height: 2),
                Text(
                  pieceLabel != null
                      ? l10n.stockCountRowPieceHint(
                          pieceLabel, _fmt(balance), ing.unit ?? '')
                      : l10n.stockCountRowOnBook(
                          _fmt(balance), ing.unit ?? ''),
                  style: TextStyle(
                    color: pieceLabel != null
                        ? const Color(0xFFE8B45A)
                        : Colors.white38,
                    fontSize: 12,
                  ),
                ),
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
                hintText: pieceLabel ?? (ing.unit ?? l10n.stockCountQtyHint),
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

  static String _fmt(double? v) {
    if (v == null) return '0';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);
  }
}
