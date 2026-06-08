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
