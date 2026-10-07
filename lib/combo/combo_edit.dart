/// LAUNCH combo add-on, client fix order 1 (T-C3) — editing a line a live
/// table already sent. Changing a sent combo's or meal's items (or a plain
/// line's options) changes its round identity: the sent copy must be
/// cancelled with the usual approval before the new one is added, never
/// silently left on the bill next to it.
library;

import '../models/pos_models.dart';
import '../services/order_sync_payload.dart';

/// Whether editing [before] into [after] changes the line's table round
/// identity (its `tableLineFingerprint`).
bool tableLineChanged(CartItem before, CartItem after) {
  final a = buildTableRoundLines([before]);
  final b = buildTableRoundLines([after]);
  return a.isNotEmpty &&
      b.isNotEmpty &&
      tableLineFingerprint(a.single) != tableLineFingerprint(b.single);
}

/// On a live table, an edit that changes the sent line goes through
/// [approveSentReduction] for the whole line first (the sent part becomes
/// one approved cancellation; the edited line is then one new add). False =
/// refused or cancelled: leave the cart as it is.
Future<bool> guardSentLineEdit({
  required bool liveTable,
  required CartItem before,
  required CartItem after,
  required Future<bool> Function(CartItem item, int reduction)
  approveSentReduction,
}) async {
  if (!liveTable || !tableLineChanged(before, after)) return true;
  return approveSentReduction(before, before.qty);
}
