import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/expense_restock_payload.dart';
import '../services/expense_restock_service.dart';

/// Log a petty-cash expense from the device: pick a category, enter the amount
/// on the keypad (OMR, stored as baisas), optional note. Pushed over the device
/// sync pipeline (online-required, like shift close). On success the screen pops
/// back to the POS.
class LogExpenseScreen extends ConsumerStatefulWidget {
  const LogExpenseScreen({super.key});

  @override
  ConsumerState<LogExpenseScreen> createState() => _LogExpenseScreenState();
}

class _LogExpenseScreenState extends ConsumerState<LogExpenseScreen> {
  String _category = expenseCategories.first;
  int _amountBaisas = 0;
  final _noteController = TextEditingController();
  bool _busy = false;
  String? _error;

  static String _money(int baisas) => (baisas / 1000).toStringAsFixed(3);

  /// Localized display name for the const fallback category KEYS (shown only
  /// offline before the first config sync — config-driven categories carry
  /// their own server-provided name). The keys themselves stay untranslated:
  /// they are the API contract. Unknown keys fall back to capitalization.
  static String _fallbackCategoryName(L10n l10n, String category) {
    switch (category) {
      case 'utilities':
        return l10n.expenseCategoryUtilities;
      case 'supplies':
        return l10n.expenseCategorySupplies;
      case 'maintenance':
        return l10n.expenseCategoryMaintenance;
      case 'salaries':
        return l10n.expenseCategorySalaries;
      case 'other':
        return l10n.expenseCategoryOther;
      default:
        return category[0].toUpperCase() + category.substring(1);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _tap(String digit) {
    if (_busy) return;
    final next = _amountBaisas * 10 + int.parse(digit);
    if (next > 9999999999) return;
    setState(() {
      _amountBaisas = next;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _amountBaisas == 0) return;
    setState(() => _amountBaisas ~/= 10);
  }

  Future<void> _submit() async {
    // Captured before the first await; reused in the post-await handlers below.
    final l10n = L10n.of(context);
    if (_amountBaisas <= 0) {
      setState(() => _error = l10n.expenseAmountGreaterThanZeroError);
      return;
    }
    final staffId = ref.read(sessionControllerProvider).staff?.id;
    final note = _noteController.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(expenseRestockServiceProvider).logExpense(
            category: _category,
            amountBaisas: _amountBaisas,
            staffId: staffId,
            note: note.isEmpty ? null : note,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.expenseRecordedMessage)),
        );
        Navigator.of(context).pop();
      }
    } on DeviceActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.expenseSubmitFailedError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // Prefer the company's config-driven expense categories (value = key, label
    // = name); fall back to the hardcoded const keys when none are cached
    // (offline before the first config sync). Sourced from the same Drift-backed
    // catalog stream that feeds the controller's expenseCategories.
    final configCategories =
        ref.watch(catalogProvider).asData?.value.expenseCategories ??
            const <({String key, String name})>[];
    final categoryEntries = configCategories.isNotEmpty
        ? configCategories
        : expenseCategories
            .map((k) => (key: k, name: _fallbackCategoryName(l10n, k)))
            .toList();

    // Keep the selection valid against the available set (the field initialiser
    // seeds the const first key, which may not exist among config categories).
    if (categoryEntries.isNotEmpty &&
        !categoryEntries.any((c) => c.key == _category)) {
      _category = categoryEntries.first.key;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: Text(l10n.expenseTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.expenseCategoryLabel,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categoryEntries.map((c) {
                    final selected = c.key == _category;
                    return ChoiceChip(
                      label: Text(c.name),
                      selected: selected,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _category = c.key),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      selectedColor: const Color(0xFF35C28B),
                      backgroundColor: const Color(0xFF16313B),
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                _amountCard(l10n.expenseAmountOmrLabel, _money(_amountBaisas)),
                const SizedBox(height: 14),
                TextField(
                  controller: _noteController,
                  enabled: !_busy,
                  maxLength: 1000,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.expenseNoteOptionalLabel,
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
                    style:
                        const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
                  ),
                ],
                const SizedBox(height: 18),
                Center(child: _keypad()),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.expenseRecordButton),
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

  Widget _amountCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF16313B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '<'];
    return SizedBox(
      width: 300,
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          return Material(
            color: const Color(0xFF1B3540),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (k == '<') {
                  _backspace();
                } else if (k == '00') {
                  _tap('0');
                  _tap('0');
                } else {
                  _tap(k);
                }
              },
              child: Center(
                child: k == '<'
                    ? const Icon(Icons.backspace_outlined, color: Colors.white70)
                    : Text(
                        k,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
