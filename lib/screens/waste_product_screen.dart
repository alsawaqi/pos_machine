import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../providers/providers.dart';
import '../services/expense_restock_payload.dart';
import '../services/expense_restock_service.dart';

/// Record wastage of cooked or ready/bought-in products at this branch.
///
/// Lists every shelf-tracked product (stock_mode unit | cooked, with a branch
/// shelf count) from the cached catalogue; staff type how many of each were
/// wasted and pick ONE reason for the batch (a free-text note is required for
/// "other"). Submitting pushes a single `product.waste` event through the device
/// sync pipeline (online-required, like the stock count); the server writes a
/// negative 'waste' movement per line with the reason + a frozen cost and
/// decrements the shelf. The merchant Loss/Waste report surfaces it.
class WasteProductScreen extends ConsumerStatefulWidget {
  const WasteProductScreen({super.key});

  @override
  ConsumerState<WasteProductScreen> createState() => _WasteProductScreenState();
}

class _WasteProductScreenState extends ConsumerState<WasteProductScreen> {
  final Map<String, TextEditingController> _qty = {};
  final _noteController = TextEditingController();
  String _reason = productWasteReasons.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String productId) =>
      _qty.putIfAbsent(productId, TextEditingController.new);

  int get _filledCount =>
      _qty.values.where((c) => c.text.trim().isNotEmpty).length;

  String _reasonLabel(L10n l10n, String r) => switch (r) {
        'expired' => l10n.wasteReasonExpired,
        'spoiled' => l10n.wasteReasonSpoiled,
        'broken' => l10n.wasteReasonBroken,
        'dropped' => l10n.wasteReasonDropped,
        'contamination' => l10n.wasteReasonContamination,
        _ => l10n.wasteReasonOther,
      };

  Future<void> _submit(List<Product> products) async {
    final l10n = L10n.of(context);
    final note = _noteController.text.trim();

    if (_reason == 'other' && note.isEmpty) {
      setState(() => _error = l10n.wasteProductNoteRequiredForOther);
      return;
    }

    final lines = <ProductWasteLineInput>[];
    for (final p in products) {
      final raw = _qty[p.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final value = double.tryParse(raw);
      if (value == null || value <= 0) {
        setState(() => _error = l10n.wasteProductInvalidQty(p.name));
        return;
      }
      final pid = int.tryParse(p.id);
      if (pid == null) continue; // non-catalog (demo) product — cannot reference
      lines.add(ProductWasteLineInput(
          productId: pid, qty: value, reason: _reason));
    }
    if (lines.isEmpty) {
      setState(() => _error = l10n.wasteProductEnterAtLeastOne);
      return;
    }

    final staffId = ref.read(sessionControllerProvider).staff?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(expenseRestockServiceProvider).submitProductWaste(
            lines: lines,
            staffId: staffId,
            note: note.isEmpty ? null : note,
          );
      // Refresh the cached config so the reduced shelf counts reach the
      // sold-out / cap logic without waiting for the next scheduled sync.
      try {
        await ref.read(configRepositoryProvider).syncConfig();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wasteProductSubmitted(lines.length))),
        );
        Navigator.of(context).pop();
      }
    } on DeviceActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.wasteProductSubmitFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final catalog = ref.watch(catalogProvider).asData?.value;
    // Cooked + bought-in products that hold a branch shelf count.
    final products = (catalog?.products ?? const <Product>[])
        .where((p) =>
            (p.stockMode == 'unit' || p.stockMode == 'cooked') &&
            p.branchStockQty != null)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: Text(l10n.wasteProductTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: products.isEmpty
              ? _emptyState(l10n)
              : Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 4),
                      child: Text(
                        l10n.wasteProductInstructions,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        itemCount: products.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _row(l10n, products[i]),
                      ),
                    ),
                    _footer(l10n, products),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _row(L10n l10n, Product p) {
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
                Text(p.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  l10n.wasteProductOnShelf(_fmt(p.branchStockQty)),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _controllerFor(p.id),
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
                hintText: '0',
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

  Widget _footer(L10n l10n, List<Product> products) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reason,
            dropdownColor: const Color(0xFF16313B),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.wasteProductReasonLabel,
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF16313B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            items: [
              for (final r in productWasteReasons)
                DropdownMenuItem(value: r, child: Text(_reasonLabel(l10n, r))),
            ],
            onChanged:
                _busy ? null : (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            enabled: !_busy,
            maxLength: 1000,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.wasteProductNoteLabel,
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
                  : () => _submit(products),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.wasteProductSubmitButton(_filledCount)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(L10n l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_sweep_rounded,
              color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.wasteProductEmptyState,
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
