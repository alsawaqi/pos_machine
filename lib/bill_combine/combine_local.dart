import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'combine_models.dart';

/// Read the original local snapshots, never a rehydrated/repriced cart.
Future<CombineLocal> loadCombineLocal(Database db, int tableId) async {
  final records = <Map<String, dynamic>>[];
  Map<String, dynamic>? canonical;
  void add(String table, String pk, Map<String, Object?> row) {
    final draft = combineMap(jsonDecode(row['draft_json'] as String));
    if (draft['diningTableId'] != '$tableId') return;
    if (!combineUuid(draft['serverOrderUuid']) ||
        draft['orderType'] != 'dine_in' ||
        draft['splitCount'] != 1) {
      throw StateError('The local bill cannot be safely identified.');
    }
    final lines = <Map<String, dynamic>>[];
    for (final raw in draft['items'] as List) {
      final item = combineMap(raw), qty = item['qty'];
      if (qty is! int ||
          qty < 1 ||
          qty > 999 ||
          item['gifted'] == true ||
          (item['bundleKey'] != null && item['bundleKey'] != '')) {
        throw StateError(
          'Gifted, bundled or fractional lines need separate review.',
        );
      }
      final productId = int.tryParse(item['id']?.toString() ?? '');
      if (productId == null || productId < 1) {
        throw StateError('Unlinked local item');
      }
      final addons = <Map<String, dynamic>>[];
      for (final raw in item['modifiers'] as List) {
        final addon = combineMap(raw),
            id = int.tryParse(combineMap(raw)['id']?.toString() ?? '');
        if (id == null || id < 1) throw StateError('Unlinked local add-on');
        addons.add({
          'id': id,
          'name': addon['label'],
          'price_delta_baisas': combineBaisas(addon['price']),
        });
      }
      final unit = combineBaisas(item['unitPrice']);
      if (combineBaisas(item['lineTotal']) != unit * qty ||
          unit !=
              combineBaisas(item['basePrice']) +
                  addons.fold<int>(
                    0,
                    (sum, a) => sum + (a['price_delta_baisas'] as int),
                  )) {
        throw StateError('Local stored prices are inconsistent');
      }
      lines.add({
        'product_id': productId,
        'qty': qty,
        'name': item['name'],
        'notes': item['notes'] ?? '',
        'unit_price_baisas': unit,
        'line_total_baisas': unit * qty,
        'addons': addons,
      });
    }
    final discount = combineMap(draft['discount']);
    // Drafts do not retain offer/comp attribution. Do not guess it from the
    // current catalogue; leave those bills unchanged for separate review.
    if (discount['value'] is! num || discount['value'] != 0) {
      throw StateError(
        'Discounted local drafts need separate accounting review.',
      );
    }
    final proof = {'uuid': draft['serverOrderUuid'], 'lines': lines};
    if (canonical != null && combineJson(canonical) != combineJson(proof)) {
      throw StateError('Local copies disagree. Keep both copies.');
    }
    canonical = proof;
    records.add({'table': table, 'pk': pk, 'value': row[pk], 'row': row});
  }

  for (final row in await db.query(
    'held_orders',
    where: 'order_type = ?',
    whereArgs: ['dine_in'],
    orderBy: 'id',
  )) {
    add('held_orders', 'id', row);
  }
  for (final row in await db.query(
    'dining_tables',
    where: 'table_id = ?',
    whereArgs: ['$tableId'],
  )) {
    if (row['paid_at'] != null ||
        row['paid_snapshot_json'] != null ||
        row['primary_table_id'] != null ||
        (row['linked_table_ids_json'] != null &&
            row['linked_table_ids_json'] != '[]') ||
        row['seating_key'] != null ||
        row['seating_uuid'] != null ||
        row['winner_seating_uuid'] != null) {
      throw StateError(
        'Shared, joined or paid local table needs separate reconciliation.',
      );
    }
    add('dining_tables', 'table_id', row);
  }
  for (final table in ['local_table_rounds', 'local_line_cancellations']) {
    if ((await db.query(
      table,
      where: 'table_id = ?',
      whereArgs: ['$tableId'],
      limit: 1,
    )).isNotEmpty) {
      throw StateError('This table already has a local shared-round ledger.');
    }
  }
  if (canonical == null) {
    throw StateError('No original local bill for this table on this device.');
  }
  for (final row in await db.query(
    'order_history',
    columns: ['snapshot_json'],
  )) {
    final history = combineMap(jsonDecode(row['snapshot_json'] as String));
    if (history['serverOrderUuid'] == canonical!['uuid']) {
      throw StateError('Local payment history exists for this bill.');
    }
  }
  return CombineLocal({
    ...canonical!,
    'table_id': tableId,
    'rows': records,
    'discount_baisas': 0,
  });
}
