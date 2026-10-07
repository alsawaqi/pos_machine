/// LAUNCH combo add-on — the combo / meal sheet, in the till's design, used
/// by the till's own cart and by its server-priced pickers (quick QR, staff
/// table rounds):
///
/// - "Included": a meal's main and every fixed line ("2 × Burger"); they are
///   not tappable. A fixed line with upgrades shows an "Upgrade?" row (a real
///   product at its upgrade price; no upgrade = served as is).
/// - Choice questions ("Drinks — pick 4") start EMPTY; each item has + / −
///   (the same item may be picked more than once) and shows its extra price.
/// - Every served item has its own options button (remove / instructions /
///   extras, minus remove prices included). Required add-on groups never
///   auto-tick: an item that still needs a choice says so.
/// - Add stays disabled until every choice line holds exactly pick N and
///   every item's required options are chosen.
///
/// The sheet only collects [ComboSelection]s; the caller prices them (the
/// shared pricing package) and builds the cart line or request line.
library;

import 'package:flutter/material.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import '../l10n/l10n.dart';
import '../models/pos_models.dart';

/// What the sheet shows about one product.
class ComboSheetItem {
  const ComboSheetItem({
    required this.id,
    required this.name,
    this.nameAr = '',
    this.available = true,
    this.hasOptions = false,
  });

  final String id;
  final String name;
  final String nameAr;

  /// False = sold out / not sold here: greyed, never newly picked.
  final bool available;
  final bool hasOptions;

  String displayName(bool arabic) =>
      arabic && nameAr.trim().isNotEmpty ? nameAr : name;
}

/// The options of one item, as the options editor returns them.
typedef ComboItemOptions = ({List<CartItemModifier> modifiers, String notes});

/// The sheet's result: the line selections, plus a meal main's options.
class ComboSheetResult {
  const ComboSheetResult({
    required this.selections,
    this.mainModifiers = const <CartItemModifier>[],
    this.mainNotes = '',
  });

  final List<ComboSelection> selections;
  final List<CartItemModifier> mainModifiers;
  final String mainNotes;
}

/// Everything the sheet needs from its caller.
class ComboSheetSource {
  const ComboSheetSource({
    required this.itemFor,
    required this.unitPriceBaisas,
    required this.editOptions,
    this.defaultOptions,
    this.optionsComplete,
  });

  final ComboSheetItem? Function(String productId) itemFor;

  /// The live price of ONE combo / meal for a draft result.
  final int Function(ComboSheetResult draft) unitPriceBaisas;

  /// Opens the item's options (null = cancelled).
  final Future<ComboItemOptions?> Function(
    BuildContext context,
    String productId,
    ComboItemOptions current,
  )
  editOptions;

  /// The merchant's default options for a freshly picked item (never an
  /// auto-tick of a required group).
  final List<CartItemModifier> Function(String productId)? defaultOptions;

  /// Whether [modifiers] satisfy [productId]'s required groups.
  final bool Function(String productId, List<CartItemModifier> modifiers)?
  optionsComplete;
}

/// A meal's main inside the sheet.
class ComboSheetMain {
  const ComboSheetMain({
    required this.productId,
    this.modifiers = const <CartItemModifier>[],
    this.notes = '',
  });

  final String productId;
  final List<CartItemModifier> modifiers;
  final String notes;
}

String _money(int baisas) => '${(baisas / 1000).toStringAsFixed(3)} OMR';
String _plus(int baisas) =>
    '${baisas < 0 ? '-' : '+'}${(baisas.abs() / 1000).toStringAsFixed(3)}';

/// True when [lines] need a sheet: a choice line or a fixed line with
/// upgrades. Otherwise the combo / meal is added with one tap.
bool comboNeedsSheet(List<pricing.ComboLineDef> lines) =>
    lines.any((line) => !line.isFixed || line.upgrades.isNotEmpty);

class ComboSheet extends StatefulWidget {
  const ComboSheet({
    super.key,
    required this.title,
    required this.lines,
    required this.source,
    this.subtitle = '',
    this.main,
    this.initial = const <ComboSelection>[],
    this.isMeal = false,
  });

  final String title;
  final String subtitle;
  final List<pricing.ComboLineDef> lines;
  final ComboSheetSource source;
  final ComboSheetMain? main;
  final List<ComboSelection> initial;
  final bool isMeal;

  @override
  State<ComboSheet> createState() => _ComboSheetState();
}

class _ComboSheetState extends State<ComboSheet> {
  // A fixed line's served product (its own product or an upgrade).
  final _fixed = <int, String>{};
  // A choice line's picks: product id -> how many (in first-pick order).
  final _choices = <int, Map<String, int>>{};
  // Options per served item ('lineId:productId').
  final _options = <String, ComboItemOptions>{};
  late ComboItemOptions _mainOptions;

  static const _ink = Color(0xFF17232B);
  static const _muted = Color(0xFF5B6B73);
  static const _ok = Color(0xFF2E7D5B);
  static const _warn = Color(0xFFB54708);

  String _key(int lineId, String productId) => '$lineId:$productId';

  ComboItemOptions _defaults(String productId) => (
    modifiers: widget.source.defaultOptions?.call(productId) ?? const [],
    notes: '',
  );

  @override
  void initState() {
    super.initState();
    final main = widget.main;
    _mainOptions = (
      modifiers: main?.modifiers ?? const <CartItemModifier>[],
      notes: main?.notes ?? '',
    );
    final initial = <int, List<ComboSelection>>{};
    for (final s in widget.initial) {
      (initial[s.lineId] ??= <ComboSelection>[]).add(s);
    }
    for (final line in widget.lines) {
      final picks = initial[line.id] ?? const <ComboSelection>[];
      if (line.isFixed) {
        final own = '${line.productId}';
        final pick = picks.firstOrNull;
        _fixed[line.id] = pick?.productId ?? own;
        _options[_key(line.id, pick?.productId ?? own)] = pick == null
            ? _defaults(own)
            : (modifiers: pick.modifiers, notes: pick.notes);
      } else {
        final counts = _choices[line.id] = <String, int>{};
        for (final pick in picks) {
          counts[pick.productId] = (counts[pick.productId] ?? 0) + pick.qty;
          _options[_key(line.id, pick.productId)] = (
            modifiers: pick.modifiers,
            notes: pick.notes,
          );
        }
      }
    }
  }

  int _picked(pricing.ComboLineDef line) =>
      (_choices[line.id] ?? const <String, int>{}).values.fold(
        0,
        (a, b) => a + b,
      );

  ComboItemOptions _optionsOf(int lineId, String productId) =>
      _options[_key(lineId, productId)] ?? _defaults(productId);

  bool _complete(String productId, ComboItemOptions options) =>
      widget.source.optionsComplete?.call(productId, options.modifiers) ?? true;

  ComboSheetResult get _result {
    final selections = <ComboSelection>[];
    for (final line in widget.lines) {
      if (line.isFixed) {
        final served = _fixed[line.id]!;
        final options = _optionsOf(line.id, served);
        // An untouched fixed line is served as is (no selection).
        if (served == '${line.productId}' &&
            options.modifiers.isEmpty &&
            options.notes.trim().isEmpty) {
          continue;
        }
        selections.add(
          ComboSelection(
            lineId: line.id,
            productId: served,
            qty: line.quantity,
            modifiers: options.modifiers,
            notes: options.notes,
          ),
        );
        continue;
      }
      for (final entry
          in (_choices[line.id] ?? const <String, int>{}).entries) {
        if (entry.value < 1) continue;
        final options = _optionsOf(line.id, entry.key);
        selections.add(
          ComboSelection(
            lineId: line.id,
            productId: entry.key,
            qty: entry.value,
            modifiers: options.modifiers,
            notes: options.notes,
          ),
        );
      }
    }
    return ComboSheetResult(
      selections: selections,
      mainModifiers: _mainOptions.modifiers,
      mainNotes: _mainOptions.notes,
    );
  }

  bool get _valid {
    final main = widget.main;
    if (main != null && !_complete(main.productId, _mainOptions)) return false;
    for (final line in widget.lines) {
      if (line.isFixed) {
        final served = _fixed[line.id]!;
        if (!_complete(served, _optionsOf(line.id, served))) return false;
      } else {
        if (_picked(line) != line.pickCount) return false;
        for (final entry in _choices[line.id]!.entries) {
          if (entry.value > 0 &&
              !_complete(entry.key, _optionsOf(line.id, entry.key))) {
            return false;
          }
        }
      }
    }
    return true;
  }

  void _step(pricing.ComboLineDef line, String productId, int delta) {
    final counts = _choices[line.id]!;
    final now = counts[productId] ?? 0;
    if (delta > 0 && _picked(line) >= line.pickCount) return;
    if (delta > 0 && widget.source.itemFor(productId)?.available == false) {
      return;
    }
    setState(() {
      final next = now + delta;
      if (next <= 0) {
        counts.remove(productId);
        _options.remove(_key(line.id, productId));
      } else {
        counts[productId] = next;
        _options.putIfAbsent(
          _key(line.id, productId),
          () => _defaults(productId),
        );
      }
    });
  }

  void _upgrade(pricing.ComboLineDef line, String productId) {
    if (_fixed[line.id] == productId) return;
    if (widget.source.itemFor(productId)?.available == false) return;
    setState(() {
      _options.remove(_key(line.id, _fixed[line.id]!));
      _fixed[line.id] = productId;
      _options[_key(line.id, productId)] = _defaults(productId);
    });
  }

  Future<void> _edit(int? lineId, String productId) async {
    final current = lineId == null
        ? _mainOptions
        : _optionsOf(lineId, productId);
    final next = await widget.source.editOptions(context, productId, current);
    if (next == null || !mounted) return;
    setState(() {
      if (lineId == null) {
        _mainOptions = next;
      } else {
        _options[_key(lineId, productId)] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final price = widget.source.unitPriceBaisas(_result);
    String nameOf(String id) =>
        widget.source.itemFor(id)?.displayName(arabic) ?? '#$id';
    final fixedLines = widget.lines.where((l) => l.isFixed).toList();
    final choiceLines = widget.lines.where((l) => !l.isFixed).toList();
    return Dialog(
      key: const ValueKey('combo-sheet'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (widget.main != null || fixedLines.isNotEmpty) ...[
                      _heading(l10n.posComboIncluded),
                      const SizedBox(height: 8),
                      if (widget.main case final main?)
                        _includedRow(
                          key: const ValueKey('combo-main'),
                          label: nameOf(main.productId),
                          productId: main.productId,
                          lineId: null,
                          options: _mainOptions,
                          optionsKey: const ValueKey('combo-options-main'),
                          l10n: l10n,
                          arabic: arabic,
                        ),
                      for (final line in fixedLines) ...[
                        _includedRow(
                          key: ValueKey('combo-fixed-${line.id}'),
                          label:
                              '${line.quantity > 1 ? '${line.quantity} × ' : ''}'
                              '${nameOf(_fixed[line.id]!)}',
                          extra: _fixed[line.id] == '${line.productId}'
                              ? 0
                              : line.upgrades
                                    .where(
                                      (u) =>
                                          '${u.productId}' == _fixed[line.id],
                                    )
                                    .firstOrNull
                                    ?.upgradePriceBaisas,
                          productId: _fixed[line.id]!,
                          lineId: line.id,
                          options: _optionsOf(line.id, _fixed[line.id]!),
                          optionsKey: ValueKey(
                            'combo-options-${line.id}-${_fixed[line.id]}',
                          ),
                          l10n: l10n,
                          arabic: arabic,
                        ),
                        if (line.upgrades.isNotEmpty)
                          _upgradeRow(line, l10n, arabic, nameOf),
                      ],
                      const SizedBox(height: 12),
                    ],
                    for (final line in choiceLines) ...[
                      _choiceHeader(line, l10n, arabic),
                      const SizedBox(height: 8),
                      for (final item in line.items)
                        _choiceItem(line, item, l10n, arabic, nameOf),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton.icon(
                        key: const ValueKey('combo-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(l10n.commonCancel),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _ink,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: FilledButton.icon(
                        key: const ValueKey('combo-confirm'),
                        onPressed: _valid
                            ? () => Navigator.of(context).pop(_result)
                            : null,
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: Text(
                          widget.isMeal
                              ? l10n.posMealAdd(_money(price))
                              : l10n.posComboAdd(_money(price)),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2C9255),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
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

  Widget _heading(String text, {Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _optionsButton({
    required Key key,
    required int? lineId,
    required String productId,
    required ComboItemOptions options,
    required L10n l10n,
    required bool arabic,
  }) {
    final item = widget.source.itemFor(productId);
    final missing = !_complete(productId, options);
    final summary = [
      for (final m in options.modifiers)
        '${m.displayLabel(arabic)}'
            '${m.price == 0 ? '' : ' ${_plus((m.price * 1000).round())}'}',
      if (options.notes.trim().isNotEmpty) options.notes.trim(),
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Text(
            missing ? l10n.posComboNeedsOptions : summary,
            style: TextStyle(
              fontSize: 13,
              fontWeight: missing ? FontWeight.w700 : FontWeight.w500,
              color: missing ? _warn : const Color(0xFF33454E),
            ),
          ),
        ),
        TextButton.icon(
          key: key,
          onPressed: () => _edit(lineId, productId),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: Text(
            item?.hasOptions == false
                ? l10n.posComboItemNotes
                : l10n.posComboItemOptions,
          ),
        ),
      ],
    );
  }

  Widget _includedRow({
    required Key key,
    required String label,
    required String productId,
    required int? lineId,
    required ComboItemOptions options,
    required Key optionsKey,
    required L10n l10n,
    required bool arabic,
    int? extra,
  }) => Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F6F8),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD5DEE3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: _ok),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
            if (extra != null && extra != 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(
                  _plus(extra),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ),
          ],
        ),
        _optionsButton(
          key: optionsKey,
          lineId: lineId,
          productId: productId,
          options: options,
          l10n: l10n,
          arabic: arabic,
        ),
      ],
    ),
  );

  Widget _upgradeRow(
    pricing.ComboLineDef line,
    L10n l10n,
    bool arabic,
    String Function(String id) nameOf,
  ) {
    final own = '${line.productId}';
    Widget chip(Key key, String label, String id, int? price) {
      final selected = _fixed[line.id] == id;
      final available = widget.source.itemFor(id)?.available ?? false;
      final enabled = selected || available || id == own;
      return InkWell(
        key: key,
        onTap: enabled ? () => _upgrade(line, id) : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _ink
                : (enabled ? Colors.white : const Color(0xFFEDEFF1)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _ink : const Color(0xFFD5DEE3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? Colors.white
                      : (enabled ? _ink : const Color(0xFF8A969C)),
                ),
              ),
              if (price != null || !enabled)
                Text(
                  !enabled ? l10n.posSoldOutBadge : _plus(price!),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white70 : _muted,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.posComboUpgradeAsk,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              chip(
                ValueKey('combo-upgrade-${line.id}-none'),
                l10n.posComboNoUpgrade(nameOf(own)),
                own,
                null,
              ),
              for (final u in line.upgrades)
                chip(
                  ValueKey('combo-upgrade-${line.id}-${u.productId}'),
                  nameOf('${u.productId}'),
                  '${u.productId}',
                  u.upgradePriceBaisas,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choiceHeader(pricing.ComboLineDef line, L10n l10n, bool arabic) {
    final name = arabic && (line.nameAr ?? '').trim().isNotEmpty
        ? line.nameAr!.trim()
        : (line.name ?? '').trim();
    final picked = _picked(line);
    return _heading(
      l10n.posComboPickQuestion(name, line.pickCount),
      trailing: Text(
        l10n.posComboPickedOf(picked, line.pickCount),
        key: ValueKey('combo-line-count-${line.id}'),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: picked == line.pickCount ? _ok : _warn,
        ),
      ),
    );
  }

  Widget _choiceItem(
    pricing.ComboLineDef line,
    pricing.ComboChoiceItemDef def,
    L10n l10n,
    bool arabic,
    String Function(String id) nameOf,
  ) {
    final id = '${def.productId}';
    final item = widget.source.itemFor(id);
    if (item == null) return const SizedBox.shrink();
    final qty = _choices[line.id]?[id] ?? 0;
    final full = _picked(line) >= line.pickCount;
    final canAdd = item.available && !full;
    return Container(
      key: ValueKey('combo-choice-${line.id}-$id'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: qty > 0
            ? const Color(0xFFEAF6EF)
            : (item.available ? Colors.white : const Color(0xFFEDEFF1)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: qty > 0 ? const Color(0xFF2C9255) : const Color(0xFFD5DEE3),
          width: qty > 0 ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName(arabic),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: item.available ? _ink : const Color(0xFF8A969C),
                      ),
                    ),
                    if (!item.available)
                      Text(
                        l10n.posSoldOutBadge,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB3261E),
                        ),
                      )
                    else if (def.extraPriceBaisas != 0)
                      Text(
                        _plus(def.extraPriceBaisas),
                        key: ValueKey('combo-choice-${line.id}-$id-extra'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _muted,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('combo-choice-${line.id}-$id-minus'),
                onPressed: qty > 0 ? () => _step(line, id, -1) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$qty',
                  key: ValueKey('combo-choice-${line.id}-$id-qty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('combo-choice-${line.id}-$id-plus'),
                onPressed: canAdd ? () => _step(line, id, 1) : null,
                icon: const Icon(Icons.add_circle_rounded),
                color: const Color(0xFF2C9255),
              ),
            ],
          ),
          if (qty > 0)
            _optionsButton(
              key: ValueKey('combo-options-${line.id}-$id'),
              lineId: line.id,
              productId: id,
              options: _optionsOf(line.id, id),
              l10n: l10n,
              arabic: arabic,
            ),
        ],
      ),
    );
  }
}

/// "Make it a meal? +1.200": true = yes, false = no (the main alone), null
/// = cancelled.
Future<bool?> showMealOffer(
  BuildContext context, {
  required String mainName,
  required String mealName,
  required int mealPriceBaisas,
}) => showDialog<bool>(
  context: context,
  builder: (dialogContext) {
    final l10n = L10n.of(dialogContext);
    return AlertDialog(
      key: const ValueKey('meal-offer'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(l10n.posMealOfferTitle(_plus(mealPriceBaisas))),
      content: Text('$mainName $mealName'),
      actions: [
        TextButton(
          key: const ValueKey('meal-offer-no'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.posMealOfferNo),
        ),
        FilledButton(
          key: const ValueKey('meal-offer-yes'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.posMealOfferYes),
        ),
      ],
    );
  },
);
