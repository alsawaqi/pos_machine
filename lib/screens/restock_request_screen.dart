import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/pos_models.dart';
import '../providers/providers.dart';
import '../services/expense_restock_payload.dart';
import '../services/expense_restock_service.dart';

/// Raise a restock request from the device: add ingredient + quantity lines from
/// the cached ingredient catalogue, optional note, submit. Pushed over the device
/// sync pipeline (online-required, like shift close). On success the screen pops
/// back to the POS.
class RestockRequestScreen extends ConsumerStatefulWidget {
  const RestockRequestScreen({super.key});

  @override
  ConsumerState<RestockRequestScreen> createState() =>
      _RestockRequestScreenState();
}

class _RestockRequestScreenState extends ConsumerState<RestockRequestScreen> {
  final List<RestockRequestLineInput> _lines = [];
  int? _selectedId;
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _ingredientName(List<IngredientRef> all, int id) {
    for (final i in all) {
      if (i.id == id) {
        return i.unit == null || i.unit!.isEmpty ? i.name : '${i.name} (${i.unit})';
      }
    }
    return L10n.of(context).restockIngredientFallback(id);
  }

  void _addLine() {
    if (_busy) return;
    final l10n = L10n.of(context);
    final id = _selectedId;
    final qty = double.tryParse(_qtyController.text.trim()) ?? 0;
    if (id == null) {
      setState(() => _error = l10n.restockPickIngredientError);
      return;
    }
    if (qty <= 0) {
      setState(() => _error = l10n.restockQuantityError);
      return;
    }
    setState(() {
      // Merge into an existing line for the same ingredient (the server rejects
      // a request that repeats an ingredient_id).
      final idx = _lines.indexWhere((l) => l.ingredientId == id);
      if (idx >= 0) {
        _lines[idx] = RestockRequestLineInput(
          ingredientId: id,
          quantity: _lines[idx].quantity + qty,
        );
      } else {
        _lines.add(RestockRequestLineInput(ingredientId: id, quantity: qty));
      }
      _qtyController.clear();
      _selectedId = null;
      _error = null;
    });
  }

  void _removeLine(int ingredientId) {
    if (_busy) return;
    setState(() => _lines.removeWhere((l) => l.ingredientId == ingredientId));
  }

  Future<void> _submit() async {
    final l10n = L10n.of(context);
    if (_lines.isEmpty) {
      setState(() => _error = l10n.restockAddAtLeastOneError);
      return;
    }
    final note = _noteController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(expenseRestockServiceProvider).requestRestock(
            lines: _lines,
            note: note.isEmpty ? null : note,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.restockSubmittedSnack)),
        );
        Navigator.of(context).pop();
      }
    } on DeviceActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.restockSubmitFailedError);
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
        title: Text(l10n.restockTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ingredients.isEmpty
                ? _emptyState()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.restockAddIngredientLabel,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 8),
                      _ingredientPicker(ingredients),
                      const SizedBox(height: 16),
                      if (_lines.isNotEmpty) ...[
                        _linesCard(ingredients),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _noteController,
                        enabled: !_busy,
                        maxLength: 1000,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: l10n.restockNoteLabel,
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
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFFF6B6B), fontSize: 14),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Center(
                        child: SizedBox(
                          width: 260,
                          height: 52,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(l10n.restockSubmitButton),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined,
              color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.restockEmptyState,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _ingredientPicker(List<IngredientRef> ingredients) {
    final l10n = L10n.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF16313B),
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedId,
                isExpanded: true,
                dropdownColor: const Color(0xFF16313B),
                style: const TextStyle(color: Colors.white),
                iconEnabledColor: Colors.white54,
                hint: Text(l10n.restockIngredientHint,
                    style: const TextStyle(color: Colors.white54)),
                items: ingredients
                    .map((i) => DropdownMenuItem<int>(
                          value: i.id,
                          child: Text(
                            i.unit == null || i.unit!.isEmpty
                                ? i.name
                                : '${i.name} (${i.unit})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged:
                    _busy ? null : (v) => setState(() => _selectedId = v),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: TextField(
            controller: _qtyController,
            enabled: !_busy,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: l10n.restockQtyHint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF16313B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _addLine,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B3540),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _linesCard(List<IngredientRef> ingredients) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16313B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (final l in _lines)
            ListTile(
              dense: true,
              title: Text(
                _ingredientName(ingredients, l.ingredientId),
                style: const TextStyle(color: Colors.white),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _qtyLabel(l.quantity),
                    style: const TextStyle(
                      color: Color(0xFF35C28B),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => _removeLine(l.ingredientId),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _qtyLabel(double q) {
    // Drop a trailing .0 so whole quantities read "5" not "5.0".
    return q == q.roundToDouble() ? q.toInt().toString() : q.toString();
  }
}
