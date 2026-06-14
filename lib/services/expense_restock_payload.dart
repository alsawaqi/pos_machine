import 'order_sync_payload.dart' show uuidV4;

/// Builds the pos_api `/device/sync/push` events for a device-logged expense and
/// a device-raised restock request (Phase 5).
///
/// Wire contract (pos_api ExpenseLogHandler / RestockRequestHandler; money =
/// integer BAISAS, restock quantity = a plain decimal number, NOT baisas):
///   expense.log     { category, amount_baisas, note?, staff_id?, logged_at? }
///                   → result { expense_id, status: 'recorded' }
///   restock.request { lines: [{ ingredient_id, quantity }], note?, requested_at? }
///                   → result { restock_request_id, status: 'submitted', lines }
///
/// company_id + branch_id are derived server-side from the authenticated device
/// (never sent). Events carry a stable client_event_id so a re-push settles
/// exactly once. Pure — no I/O — so unit-testable.

/// The five server-side expense categories (pos_api Expense::CATEGORIES). Any
/// other value is rejected by the handler, so the device offers exactly these.
const expenseCategories = <String>[
  'utilities',
  'supplies',
  'maintenance',
  'salaries',
  'other',
];

/// One restock line as entered in the UI (before merge). [quantity] is a plain
/// number in the ingredient's own unit (kg, litre, piece…), never baisas.
class RestockRequestLineInput {
  const RestockRequestLineInput({required this.ingredientId, required this.quantity});
  final int ingredientId;
  final double quantity;
}

/// Build the `expense.log` event. Money is integer baisas. [note]/[staffId]/
/// [loggedAt] are omitted from the payload when null/empty.
Map<String, dynamic> buildExpenseLogEvent({
  required String category,
  required int amountBaisas,
  int? staffId,
  String? note,
  DateTime? loggedAt,
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  final payload = <String, dynamic>{
    'category': category,
    'amount_baisas': amountBaisas,
  };
  if (staffId != null) payload['staff_id'] = staffId;
  if (note != null && note.isNotEmpty) payload['note'] = note;
  if (loggedAt != null) payload['logged_at'] = loggedAt.toUtc().toIso8601String();
  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'expense.log',
    'client_timestamp': ts,
    'payload': payload,
  };
}

/// One day-end count line as entered in the UI. Exactly one of [countedPieces]
/// (piece-tracked ingredients — the server converts via units_per_piece) or
/// [countedUnits] (base-unit ingredients) is set. Zero IS a valid count
/// ("no bottles left").
class StockCountLineInput {
  const StockCountLineInput({
    required this.ingredientId,
    this.countedPieces,
    this.countedUnits,
  }) : assert(countedPieces != null || countedUnits != null);
  final int ingredientId;
  final double? countedPieces;
  final double? countedUnits;
}

/// Build the Phase A `stock.count` event (Additions §2.8). Lines with negative
/// amounts are dropped; a duplicate ingredient_id keeps the LAST entry (the
/// server rejects duplicates). Payload:
///   { lines: [{ ingredient_id, counted_pieces? | counted_units? }],
///     note?, staff_id?, counted_at? }
/// → result { stock_count_id, lines, lines_with_variance }
Map<String, dynamic> buildStockCountEvent({
  required List<StockCountLineInput> lines,
  String? note,
  int? staffId,
  DateTime? countedAt,
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();

  final byIngredient = <int, Map<String, dynamic>>{};
  for (final l in lines) {
    final line = <String, dynamic>{'ingredient_id': l.ingredientId};
    if (l.countedPieces != null) {
      if (l.countedPieces! < 0) continue;
      line['counted_pieces'] = l.countedPieces;
    } else {
      if (l.countedUnits == null || l.countedUnits! < 0) continue;
      line['counted_units'] = l.countedUnits;
    }
    byIngredient[l.ingredientId] = line; // last entry wins
  }

  final payload = <String, dynamic>{
    'lines': byIngredient.values.toList(),
  };
  if (note != null && note.isNotEmpty) payload['note'] = note;
  if (staffId != null) payload['staff_id'] = staffId;
  if (countedAt != null) {
    payload['counted_at'] = countedAt.toUtc().toIso8601String();
  }
  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'stock.count',
    'client_timestamp': ts,
    'payload': payload,
  };
}

/// The waste reasons offered on the device — mirror of pos_merchant's
/// App\Enums\WasteReason. 'other' carries a free-text note.
const productWasteReasons = <String>[
  'expired',
  'spoiled',
  'broken',
  'dropped',
  'contamination',
  'other',
];

/// One product-waste line as entered in the UI: how many units of a cooked or
/// bought-in product were wasted, and why.
class ProductWasteLineInput {
  const ProductWasteLineInput({
    required this.productId,
    required this.qty,
    required this.reason,
  });
  final int productId;
  final double qty;
  final String reason;
}

/// Build the `product.waste` event. Non-positive lines are dropped. Payload:
///   { lines: [{ product_id, qty, reason }], note?, staff_id?, wasted_at? }
/// → result { wasted_lines, total_qty }
Map<String, dynamic> buildProductWasteEvent({
  required List<ProductWasteLineInput> lines,
  String? note,
  int? staffId,
  DateTime? wastedAt,
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();

  final payloadLines = <Map<String, dynamic>>[];
  for (final l in lines) {
    if (l.qty <= 0) continue;
    payloadLines.add(<String, dynamic>{
      'product_id': l.productId,
      'qty': l.qty,
      'reason': l.reason,
    });
  }

  final payload = <String, dynamic>{'lines': payloadLines};
  if (note != null && note.isNotEmpty) payload['note'] = note;
  if (staffId != null) payload['staff_id'] = staffId;
  if (wastedAt != null) payload['wasted_at'] = wastedAt.toUtc().toIso8601String();
  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'product.waste',
    'client_timestamp': ts,
    'payload': payload,
  };
}

/// Build the `restock.request` event. Duplicate ingredient lines are MERGED
/// (summed) and non-positive quantities dropped — the server rejects a request
/// that repeats an ingredient_id, so the client must dedupe first.
Map<String, dynamic> buildRestockRequestEvent({
  required List<RestockRequestLineInput> lines,
  String? note,
  DateTime? requestedAt,
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();

  final merged = <int, double>{};
  for (final l in lines) {
    if (l.quantity <= 0) continue;
    merged.update(l.ingredientId, (q) => q + l.quantity,
        ifAbsent: () => l.quantity);
  }
  final payloadLines = merged.entries
      .map((e) => <String, dynamic>{'ingredient_id': e.key, 'quantity': e.value})
      .toList();

  final payload = <String, dynamic>{'lines': payloadLines};
  if (note != null && note.isNotEmpty) payload['note'] = note;
  if (requestedAt != null) {
    payload['requested_at'] = requestedAt.toUtc().toIso8601String();
  }
  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'restock.request',
    'client_timestamp': ts,
    'payload': payload,
  };
}
