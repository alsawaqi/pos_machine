import 'dart:convert';

/// LAUNCH-P5 C1 — the merchant's tick list per staff position
/// (`settings.position_permissions` in the device config).
///
/// A ticked action needs no approval. Anything not ticked opens the approval
/// sheet (lib/core/manager_auth.dart). A manual discount is also capped by the
/// position's `discount_max_percent`: above it, the discount needs approval.
///
/// Missing positions, actions or limits always resolve to the shared defaults
/// (`D:\launch-work\p5\shared\position_permissions_defaults.json`, copied to
/// test/fixtures and checked by test/launch_p5_permissions_test.dart). An
/// unknown position is allowed nothing.
class PositionPermissions {
  const PositionPermissions._(this._actions, this._discountMax);

  final Map<String, Map<String, bool>> _actions;
  final Map<String, int> _discountMax;

  static const positions = <String>[
    'cashier',
    'waiter',
    'kitchen',
    'supervisor',
    'manager',
  ];

  static const actions = <String>[
    'order.void_unpaid',
    'order.void_paid',
    'table.cancel_line',
    'table.cancel_bill',
    'discount.manual',
    'comp',
    'gift',
    'loyalty.redeem',
    'sold_out.toggle',
    'receipt.reprint',
    'kitchen.reprint',
    'reports.view',
    'kitchen.screen',
    'shift.close_other',
    'payout',
    'stock.waste',
    'stock.count',
    'training.use',
    'approvals.give',
  ];

  /// The fixed defaults (identical to the shared fixture).
  static final PositionPermissions defaults = PositionPermissions._(
    _defaultActions,
    _defaultDiscountMax,
  );

  /// Resolve the config value (a map, or its JSON text). Anything missing or
  /// malformed falls back to [defaults], value by value.
  factory PositionPermissions.resolve(Object? raw) {
    Object? value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        value = null;
      }
    }
    final source = value is Map ? value : const <Object?, Object?>{};
    final resolved = <String, Map<String, bool>>{};
    final limits = <String, int>{};
    for (final position in positions) {
      final entry = source[position];
      final given = entry is Map ? entry['actions'] : null;
      resolved[position] = {
        for (final action in actions)
          action: given is Map && given[action] is bool
              ? given[action] as bool
              : _defaultActions[position]![action]!,
      };
      final max = entry is Map ? entry['discount_max_percent'] : null;
      limits[position] = max is num && max >= 0 && max <= 100
          ? max.floor()
          : _defaultDiscountMax[position]!;
    }
    // The kitchen position may always open the kitchen screen.
    resolved['kitchen']!['kitchen.screen'] = true;
    return PositionPermissions._(resolved, limits);
  }

  static String? _normalize(String? position) {
    final p = position?.trim().toLowerCase() ?? '';
    return p.isEmpty ? null : p;
  }

  /// Whether [position] may do [action] without an approval. For
  /// `discount.manual`, [amountPercent] (the discount as a % of the order
  /// subtotal) must also be within the position's maximum.
  bool allows(String? position, String action, {double? amountPercent}) {
    final p = _normalize(position);
    if (p == null) return false;
    final rules = _actions[p];
    if (rules == null || rules[action] != true) return false;
    if (action == 'discount.manual' && amountPercent != null) {
      return amountPercent <= (_discountMax[p] ?? 0) + 0.000001;
    }
    return true;
  }

  /// The largest manual discount (%) [position] may give without approval.
  int discountMaxPercent(String? position) =>
      _discountMax[_normalize(position) ?? ''] ?? 0;

  /// The `{position: {actions, discount_max_percent}}` shape of the wire.
  Map<String, dynamic> toJson() => {
    for (final position in positions)
      position: {
        'actions': Map<String, bool>.from(_actions[position]!),
        'discount_max_percent': _discountMax[position],
      },
  };
}

/// A manual discount as a percentage of the order subtotal. An amount
/// discount on an empty order counts as 100 %.
double discountPercentOf({
  required double discountAmount,
  required double subtotal,
}) {
  if (discountAmount <= 0) return 0;
  if (subtotal <= 0) return 100;
  return discountAmount / subtotal * 100;
}

/// The logged-in person's view of the tick list: the one `can` helper every
/// gate on the till goes through.
class StaffPermissions {
  const StaffPermissions(this.matrix, this.position);

  final PositionPermissions matrix;
  final String? position;

  bool can(String action, {double? amountPercent}) =>
      matrix.allows(position, action, amountPercent: amountPercent);

  int get discountMaxPercent => matrix.discountMaxPercent(position);
}

const Map<String, int> _defaultDiscountMax = {
  'cashier': 10,
  'waiter': 10,
  'kitchen': 0,
  'supervisor': 25,
  'manager': 100,
};

const Map<String, Map<String, bool>> _defaultActions = {
  'cashier': {
    'order.void_unpaid': false,
    'order.void_paid': false,
    'table.cancel_line': false,
    'table.cancel_bill': false,
    'discount.manual': true,
    'comp': false,
    'gift': false,
    'loyalty.redeem': false,
    'sold_out.toggle': false,
    'receipt.reprint': true,
    'kitchen.reprint': false,
    'reports.view': false,
    'kitchen.screen': false,
    'shift.close_other': false,
    'payout': false,
    'stock.waste': true,
    'stock.count': true,
    'training.use': true,
    'approvals.give': false,
  },
  'waiter': {
    'order.void_unpaid': false,
    'order.void_paid': false,
    'table.cancel_line': false,
    'table.cancel_bill': false,
    'discount.manual': true,
    'comp': false,
    'gift': false,
    'loyalty.redeem': false,
    'sold_out.toggle': false,
    'receipt.reprint': true,
    'kitchen.reprint': false,
    'reports.view': false,
    'kitchen.screen': false,
    'shift.close_other': false,
    'payout': false,
    'stock.waste': true,
    'stock.count': true,
    'training.use': true,
    'approvals.give': false,
  },
  'kitchen': {
    'order.void_unpaid': false,
    'order.void_paid': false,
    'table.cancel_line': false,
    'table.cancel_bill': false,
    'discount.manual': false,
    'comp': false,
    'gift': false,
    'loyalty.redeem': false,
    'sold_out.toggle': false,
    'receipt.reprint': true,
    'kitchen.reprint': false,
    'reports.view': false,
    'kitchen.screen': true,
    'shift.close_other': false,
    'payout': false,
    'stock.waste': true,
    'stock.count': true,
    'training.use': true,
    'approvals.give': false,
  },
  'supervisor': {
    'order.void_unpaid': true,
    'order.void_paid': false,
    'table.cancel_line': true,
    'table.cancel_bill': false,
    'discount.manual': true,
    'comp': false,
    'gift': false,
    'loyalty.redeem': true,
    'sold_out.toggle': true,
    'receipt.reprint': true,
    'kitchen.reprint': true,
    'reports.view': false,
    'kitchen.screen': false,
    'shift.close_other': true,
    'payout': true,
    'stock.waste': true,
    'stock.count': true,
    'training.use': true,
    'approvals.give': false,
  },
  'manager': {
    'order.void_unpaid': true,
    'order.void_paid': true,
    'table.cancel_line': true,
    'table.cancel_bill': true,
    'discount.manual': true,
    'comp': true,
    'gift': true,
    'loyalty.redeem': true,
    'sold_out.toggle': true,
    'receipt.reprint': true,
    'kitchen.reprint': true,
    'reports.view': true,
    'kitchen.screen': true,
    'shift.close_other': true,
    'payout': true,
    'stock.waste': true,
    'stock.count': true,
    'training.use': true,
    'approvals.give': true,
  },
};
