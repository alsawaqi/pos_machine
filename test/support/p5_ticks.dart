import 'dart:convert';

import 'package:pos_machine/core/permissions.dart';

/// LAUNCH-P5 — the preference key of the merchant's tick list.
const p5TickListKey = 'p5_position_permissions_json';

/// A tick list that lets every position do every action without approval.
///
/// Suites written before LAUNCH-P5 (payments, tables, loyalty, recovery)
/// log in a cashier and test their own flows; with the P5 defaults that
/// cashier would now meet the approval sheet at every comp, gift, void or
/// redeem. They seed this list so they keep testing what they test. The
/// per-position gates themselves are covered by the launch_p5_* suites.
String p5AllowAllTickList() => jsonEncode({
  for (final position in PositionPermissions.positions)
    position: {
      'actions': {
        for (final action in PositionPermissions.actions) action: true,
      },
      'discount_max_percent': 100,
    },
});
