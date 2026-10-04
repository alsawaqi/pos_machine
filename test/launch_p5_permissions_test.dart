import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/permissions.dart';

/// LAUNCH-P5 C1 — the tick list resolver against the shared defaults
/// fixture (Claude's file; copied byte for byte, never edited).
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/position_permissions_defaults.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final defaults = fixture['defaults'] as Map<String, dynamic>;

  test('positions and actions match the fixture', () {
    expect(PositionPermissions.positions, fixture['positions']);
    expect(PositionPermissions.actions, fixture['actions']);
  });

  test('the built-in defaults equal the fixture exactly', () {
    expect(PositionPermissions.defaults.toJson(), defaults);
  });

  test('a missing setting resolves to the fixture defaults', () {
    for (final raw in <Object?>[null, '', 'not json', 42, <String, dynamic>{}]) {
      expect(PositionPermissions.resolve(raw).toJson(), defaults);
    }
  });

  test('given values win, missing ones fall back one by one', () {
    final resolved = PositionPermissions.resolve({
      'cashier': {
        'actions': {'order.void_unpaid': true, 'payout': 'yes'},
        'discount_max_percent': 15,
      },
      'supervisor': {'discount_max_percent': 400},
      'stranger': {
        'actions': {'comp': true},
      },
    });
    expect(resolved.allows('cashier', 'order.void_unpaid'), isTrue);
    // A non-boolean value falls back to the default (false).
    expect(resolved.allows('cashier', 'payout'), isFalse);
    expect(resolved.discountMaxPercent('cashier'), 15);
    // Out of range falls back.
    expect(resolved.discountMaxPercent('supervisor'), 25);
    // Positions outside the five are never allowed anything.
    expect(resolved.allows('stranger', 'comp'), isFalse);
    expect(resolved.allows(null, 'receipt.reprint'), isFalse);
    expect(resolved.allows('', 'receipt.reprint'), isFalse);
  });

  test('the JSON text form resolves too', () {
    final resolved = PositionPermissions.resolve(
      jsonEncode({
        'waiter': {
          'actions': {'gift': true},
        },
      }),
    );
    expect(resolved.allows('Waiter', 'gift'), isTrue);
    expect(resolved.allows('waiter', 'comp'), isFalse);
  });

  test('the kitchen position can always open the kitchen screen', () {
    final resolved = PositionPermissions.resolve({
      'kitchen': {
        'actions': {'kitchen.screen': false},
      },
    });
    expect(resolved.allows('kitchen', 'kitchen.screen'), isTrue);
  });

  test('a manual discount is checked against the position maximum', () {
    final m = PositionPermissions.defaults;
    expect(m.allows('cashier', 'discount.manual', amountPercent: 10), isTrue);
    expect(
      m.allows('cashier', 'discount.manual', amountPercent: 10.01),
      isFalse,
    );
    expect(
      m.allows('supervisor', 'discount.manual', amountPercent: 25),
      isTrue,
    );
    expect(m.allows('manager', 'discount.manual', amountPercent: 100), isTrue);
    // Kitchen has no manual discount at all.
    expect(m.allows('kitchen', 'discount.manual', amountPercent: 0), isFalse);
  });

  test('an amount discount is compared as a % of the subtotal', () {
    expect(discountPercentOf(discountAmount: 1, subtotal: 10), 10);
    expect(discountPercentOf(discountAmount: 0, subtotal: 10), 0);
    expect(discountPercentOf(discountAmount: 1, subtotal: 0), 100);
  });

  test('StaffPermissions.can binds the logged-in position', () {
    final cashier = StaffPermissions(PositionPermissions.defaults, 'cashier');
    final manager = StaffPermissions(PositionPermissions.defaults, 'manager');
    expect(cashier.can('sold_out.toggle'), isFalse);
    expect(manager.can('sold_out.toggle'), isTrue);
    expect(cashier.can('discount.manual', amountPercent: 20), isFalse);
    expect(cashier.discountMaxPercent, 10);
  });
}
