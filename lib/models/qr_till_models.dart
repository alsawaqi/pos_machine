enum QrReleaseOutcome { cancelled, uncertain }

enum QrTender { cash, card }

class QrBoardOrder {
  const QrBoardOrder({
    required this.uuid,
    required this.status,
    required this.acceptedTotalBaisas,
    this.receiptNumber,
  });

  final String uuid;
  final String status;
  final String? receiptNumber;
  final int acceptedTotalBaisas;

  factory QrBoardOrder.fromJson(Map<String, dynamic> json) => QrBoardOrder(
    uuid: json['uuid']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    receiptNumber: _nullableString(json['receipt_number']),
    acceptedTotalBaisas: (json['accepted_total_baisas'] as num?)?.toInt() ?? 0,
  );
}

class QrPendingRound {
  const QrPendingRound({
    required this.id,
    required this.roundNo,
    required this.subtotalBaisas,
    required this.taxBaisas,
    required this.totalBaisas,
    this.submittedAt,
  });

  final int id;
  final int roundNo;
  final int subtotalBaisas;
  final int taxBaisas;
  final int totalBaisas;
  final DateTime? submittedAt;

  factory QrPendingRound.fromJson(Map<String, dynamic> json) => QrPendingRound(
    id: (json['id'] as num?)?.toInt() ?? 0,
    roundNo: (json['round_no'] as num?)?.toInt() ?? 0,
    subtotalBaisas: (json['subtotal_baisas'] as num?)?.toInt() ?? 0,
    taxBaisas: (json['tax_baisas'] as num?)?.toInt() ?? 0,
    totalBaisas: (json['total_baisas'] as num?)?.toInt() ?? 0,
    submittedAt: DateTime.tryParse(json['submitted_at']?.toString() ?? ''),
  );
}

class QrTableBoardRow {
  const QrTableBoardRow({
    required this.tableId,
    required this.tableLabel,
    required this.tableStatus,
    required this.tableDeleted,
    required this.orphaned,
    required this.pendingRounds,
    this.sessionUuid,
    this.sessionStatus,
    this.expiresAt,
    this.order,
  });

  final int tableId;
  final String tableLabel;
  final String tableStatus;
  final bool tableDeleted;
  final String? sessionUuid;
  final String? sessionStatus;
  final DateTime? expiresAt;
  final bool orphaned;
  final QrBoardOrder? order;
  final List<QrPendingRound> pendingRounds;

  bool get hasMissingSession => order != null && sessionUuid == null;

  factory QrTableBoardRow.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    final rawRounds = json['pending_rounds'];
    return QrTableBoardRow(
      tableId: (json['table_id'] as num?)?.toInt() ?? 0,
      tableLabel: json['table_label']?.toString() ?? '',
      tableStatus: json['table_status']?.toString() ?? '',
      tableDeleted: json['table_deleted'] == true,
      sessionUuid: _nullableString(json['session_uuid']),
      sessionStatus: _nullableString(json['session_status']),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      orphaned: json['orphaned'] == true,
      order: rawOrder is Map
          ? QrBoardOrder.fromJson(rawOrder.cast<String, dynamic>())
          : null,
      pendingRounds: rawRounds is List
          ? rawRounds
                .whereType<Map>()
                .map(
                  (row) => QrPendingRound.fromJson(row.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <QrPendingRound>[],
    );
  }
}

class QrOrderAddon {
  const QrOrderAddon({
    required this.addOnId,
    required this.name,
    required this.priceDeltaBaisas,
  });

  final int? addOnId;
  final String name;
  final int priceDeltaBaisas;

  factory QrOrderAddon.fromJson(Map<String, dynamic> json) => QrOrderAddon(
    addOnId: (json['add_on_id'] as num?)?.toInt(),
    name: json['add_on_name']?.toString() ?? '',
    priceDeltaBaisas: (json['price_delta_baisas'] as num?)?.toInt() ?? 0,
  );
}

class QrOrderItem {
  const QrOrderItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPriceBaisas,
    required this.lineDiscountBaisas,
    required this.lineTotalBaisas,
    required this.status,
    required this.addons,
    this.notes,
  });

  final int id;
  final int? productId;
  final String name;
  final double quantity;
  final int unitPriceBaisas;
  final int lineDiscountBaisas;
  final int lineTotalBaisas;
  final String status;
  final String? notes;
  final List<QrOrderAddon> addons;

  factory QrOrderItem.fromJson(Map<String, dynamic> json) {
    final rawAddons = json['addons'];
    return QrOrderItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt(),
      name: json['product_name']?.toString() ?? '',
      quantity: (json['qty'] as num?)?.toDouble() ?? 0,
      unitPriceBaisas: (json['unit_price_baisas'] as num?)?.toInt() ?? 0,
      lineDiscountBaisas: (json['line_discount_baisas'] as num?)?.toInt() ?? 0,
      lineTotalBaisas: (json['line_total_baisas'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '',
      notes: _nullableString(json['notes']),
      addons: rawAddons is List
          ? rawAddons
                .whereType<Map>()
                .map(
                  (row) => QrOrderAddon.fromJson(row.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <QrOrderAddon>[],
    );
  }
}

class QrActiveOrder {
  const QrActiveOrder({
    required this.uuid,
    required this.status,
    required this.source,
    required this.subtotalBaisas,
    required this.discountTotalBaisas,
    required this.compTotalBaisas,
    required this.taxTotalBaisas,
    required this.grandTotalBaisas,
    required this.items,
    this.tableId,
    this.customerId,
    this.plateNumber,
    this.receiptNumber,
  });

  final String uuid;
  final String status;
  final String source;
  final int? tableId;
  final int? customerId;
  final String? plateNumber;
  final String? receiptNumber;
  final int subtotalBaisas;
  final int discountTotalBaisas;
  final int compTotalBaisas;
  final int taxTotalBaisas;
  final int grandTotalBaisas;
  final List<QrOrderItem> items;

  bool get isQrWeb => source == 'qr_web';
  bool get isSettleable => isQrWeb && (status == 'open' || status == 'held');

  factory QrActiveOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return QrActiveOrder(
      uuid: json['uuid']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      tableId: (json['table_id'] as num?)?.toInt(),
      customerId: (json['customer_id'] as num?)?.toInt(),
      plateNumber: _nullableString(json['plate_number']),
      receiptNumber: _nullableString(json['receipt_number']),
      subtotalBaisas: (json['subtotal_baisas'] as num?)?.toInt() ?? 0,
      discountTotalBaisas:
          (json['discount_total_baisas'] as num?)?.toInt() ?? 0,
      compTotalBaisas: (json['comp_total_baisas'] as num?)?.toInt() ?? 0,
      taxTotalBaisas: (json['tax_total_baisas'] as num?)?.toInt() ?? 0,
      grandTotalBaisas: (json['grand_total_baisas'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((row) => QrOrderItem.fromJson(row.cast<String, dynamic>()))
                .toList(growable: false)
          : const <QrOrderItem>[],
    );
  }
}

class QrSettlementClaim {
  const QrSettlementClaim({
    required this.orderUuid,
    required this.frozenAmountBaisas,
    required this.status,
    required this.deadlineAt,
    this.claimedAt,
    this.alreadyClaimedByThisDevice = false,
  });

  final String orderUuid;
  final int frozenAmountBaisas;
  final String status;
  final DateTime deadlineAt;
  final DateTime? claimedAt;
  final bool alreadyClaimedByThisDevice;

  factory QrSettlementClaim.fromJson(Map<String, dynamic> json) {
    final deadline = DateTime.tryParse(
      (json['charge_deadline_at'] ?? json['deadline_at'])?.toString() ?? '',
    );
    if (deadline == null) {
      throw const FormatException('Settlement claim deadline is missing.');
    }
    return QrSettlementClaim(
      orderUuid: (json['order_uuid'] ?? json['uuid'])?.toString() ?? '',
      frozenAmountBaisas:
          ((json['charge_amount_baisas'] ?? json['amount_baisas']) as num?)
              ?.toInt() ??
          0,
      status: json['status']?.toString() ?? 'awaiting_payment',
      deadlineAt: deadline,
      claimedAt: DateTime.tryParse(json['charge_claimed_at']?.toString() ?? ''),
      alreadyClaimedByThisDevice:
          json['already_claimed_by_this_device'] == true,
    );
  }
}

class QrOrderActionResult {
  const QrOrderActionResult({
    required this.orderUuid,
    required this.status,
    this.receiptNumber,
    this.sessionStatus,
  });

  final String orderUuid;
  final String status;
  final String? receiptNumber;
  final String? sessionStatus;

  factory QrOrderActionResult.fromJson(Map<String, dynamic> json) =>
      QrOrderActionResult(
        orderUuid: json['order_uuid']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        receiptNumber: _nullableString(json['receipt_number']),
        sessionStatus: _nullableString(json['session_status']),
      );
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
