enum QrReleaseOutcome { cancelled, uncertain }

enum QrTender { cash, card }

class QrBoardOrder {
  const QrBoardOrder({
    required this.uuid,
    required this.status,
    required this.acceptedTotalBaisas,
    this.receiptNumber,
    this.tempReference,
  });

  final String uuid;
  final String status;
  final String? receiptNumber;
  final String? tempReference;
  final int acceptedTotalBaisas;

  factory QrBoardOrder.fromJson(Map<String, dynamic> json) => QrBoardOrder(
    uuid: json['uuid']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    receiptNumber: _nullableString(json['receipt_number']),
    tempReference: _nullableString(json['temp_reference']),
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

class QrBoardRound {
  const QrBoardRound({
    required this.id,
    required this.roundNo,
    required this.status,
    required this.totalBaisas,
    this.submittedAt,
  });

  final int id;
  final int roundNo;
  final String status;
  final int totalBaisas;
  final DateTime? submittedAt;

  factory QrBoardRound.fromJson(Map<String, dynamic> json) => QrBoardRound(
    id: (json['id'] as num?)?.toInt() ?? 0,
    roundNo: (json['round_no'] as num?)?.toInt() ?? 0,
    status: json['status']?.toString() ?? '',
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
    this.rounds = const <QrBoardRound>[],
    this.acceptedRoundCount = 0,
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
  final List<QrBoardRound> rounds;
  final int acceptedRoundCount;

  bool get hasMissingSession => order != null && sessionUuid == null;

  factory QrTableBoardRow.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    final rawRounds = json['pending_rounds'];
    final rawBoardRounds = json['rounds'];
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
      rounds: rawBoardRounds is List
          ? rawBoardRounds
                .whereType<Map>()
                .map(
                  (row) => QrBoardRound.fromJson(row.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <QrBoardRound>[],
      acceptedRoundCount: (json['accepted_round_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class QrRoundDisplayLine {
  const QrRoundDisplayLine({
    required this.name,
    required this.quantity,
    required this.unitPriceBaisas,
    required this.lineDiscountBaisas,
    required this.lineTotalBaisas,
    required this.addons,
    this.nameAr,
    this.notes,
    this.cancelledQuantity = 0,
    this.components = const <Map<String, dynamic>>[],
  });

  final String name;
  final String? nameAr;
  // LAUNCH-P4 C7 — a combo line's chosen items as the server froze them
  // (name / name_ar / qty per ONE combo / addons / notes).
  final List<Map<String, dynamic>> components;
  final double quantity;
  final double cancelledQuantity;
  double get remainingQuantity =>
      (quantity - cancelledQuantity).clamp(0, quantity).toDouble();
  final int unitPriceBaisas;
  final int lineDiscountBaisas;
  final int lineTotalBaisas;
  final String? notes;
  final List<QrOrderAddon> addons;

  factory QrRoundDisplayLine.fromJson(Map<String, dynamic> json) {
    final rawAddons = json['addons'];
    return QrRoundDisplayLine(
      name: (json['product_name'] ?? json['name'])?.toString() ?? '',
      nameAr: _nullableString(json['product_name_ar'] ?? json['name_ar']),
      quantity: (json['qty'] as num?)?.toDouble() ?? 0,
      cancelledQuantity: (json['cancelled_qty'] as num?)?.toDouble() ?? 0,
      unitPriceBaisas: (json['unit_price_baisas'] as num?)?.toInt() ?? 0,
      lineDiscountBaisas: (json['line_discount_baisas'] as num?)?.toInt() ?? 0,
      lineTotalBaisas: (json['line_total_baisas'] as num?)?.toInt() ?? 0,
      notes: _nullableString(json['notes']),
      addons: rawAddons is List
          ? rawAddons
                .whereType<Map>()
                .map(
                  (row) => QrOrderAddon.fromJson(row.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <QrOrderAddon>[],
      components: [
        for (final c in (json['components'] as List?) ?? const [])
          if (c is Map) c.cast<String, dynamic>(),
      ],
    );
  }

  Map<String, dynamic> toKitchenItem({required bool arabic}) => {
    'name': arabic && nameAr != null ? nameAr : name,
    'qty': remainingQuantity,
    'notes': ?notes,
    'modifiers': [
      for (final addon in addons)
        {
          'group': '',
          'label': arabic && addon.nameAr != null ? addon.nameAr : addon.name,
        },
    ],
    // LAUNCH-P4 C7 — combo components print under the combo.
    if (components.isNotEmpty)
      'components': [
        for (final c in components)
          {
            'name':
                arabic &&
                    _nullableString(c['product_name_ar'] ?? c['name_ar']) !=
                        null
                ? _nullableString(c['product_name_ar'] ?? c['name_ar'])
                : (c['product_name'] ?? c['name'])?.toString() ?? '',
            'qty': (c['qty'] as num?)?.toInt() ?? 1,
            'notes': ?_nullableString(c['notes']),
            'modifiers': [
              for (final a in (c['addons'] as List?) ?? const [])
                if (a is Map)
                  {
                    'group': '',
                    'label': arabic && _nullableString(a['name_ar']) != null
                        ? _nullableString(a['name_ar'])
                        : (a['name'] ?? a['add_on_name'])?.toString() ?? '',
                  },
            ],
          },
      ],
  };
}

class QrDeviceRound {
  const QrDeviceRound({
    required this.id,
    required this.roundNo,
    required this.status,
    required this.lines,
    required this.subtotalBaisas,
    required this.taxBaisas,
    required this.totalBaisas,
    this.submittedAt,
    this.resolvedAt,
  });

  final int id;
  final int roundNo;
  final String status;
  final List<QrRoundDisplayLine> lines;
  final int subtotalBaisas;
  final int taxBaisas;
  final int totalBaisas;
  final DateTime? submittedAt;
  final DateTime? resolvedAt;

  factory QrDeviceRound.fromJson(Map<String, dynamic> json) {
    final rawLines = json['priced_lines'];
    return QrDeviceRound(
      id: (json['id'] as num?)?.toInt() ?? 0,
      roundNo: (json['round_no'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? '',
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map(
                  (line) =>
                      QrRoundDisplayLine.fromJson(line.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <QrRoundDisplayLine>[],
      subtotalBaisas: (json['subtotal_baisas'] as num?)?.toInt() ?? 0,
      taxBaisas: (json['tax_baisas'] as num?)?.toInt() ?? 0,
      totalBaisas: (json['total_baisas'] as num?)?.toInt() ?? 0,
      submittedAt: DateTime.tryParse(json['submitted_at']?.toString() ?? ''),
      resolvedAt: DateTime.tryParse(json['resolved_at']?.toString() ?? ''),
    );
  }
}

class QrRoundEnvelope {
  const QrRoundEnvelope({
    required this.round,
    required this.orderUuid,
    this.sessionUuid,
    this.tableLabel,
    this.receiptNumber,
    this.tempReference,
    this.ticketKey,
    this.claimedByDeviceId,
    this.printedAt,
    this.needsReview = false,
  });

  final QrDeviceRound round;
  final String orderUuid;
  final String? sessionUuid;
  final String? tableLabel;
  final String? receiptNumber;
  final String? tempReference;

  final String? ticketKey;
  final int? claimedByDeviceId;
  final DateTime? printedAt;
  final bool needsReview;

  factory QrRoundEnvelope.fromJson(Map<String, dynamic> json) {
    final rawRound = json['round'];
    if (rawRound is! Map) {
      throw const FormatException('QR round response is missing the round.');
    }
    return QrRoundEnvelope(
      round: QrDeviceRound.fromJson(rawRound.cast<String, dynamic>()),
      orderUuid: json['order_uuid']?.toString() ?? '',
      sessionUuid: _nullableString(json['session_uuid']),
      tableLabel: _nullableString(json['table_label']),
      receiptNumber: _nullableString(json['receipt_number']),
      tempReference: _nullableString(json['temp_reference']),
      ticketKey: _nullableString(json['ticket_key']),
      claimedByDeviceId: (json['claimed_by_device_id'] as num?)?.toInt(),
      printedAt: DateTime.tryParse(json['printed_at']?.toString() ?? ''),
      needsReview: json['needs_review'] == true,
    );
  }

  /// The accepted-round print feed deliberately flattens each round row,
  /// unlike detail/confirm/reject which nest it under `round`. Keep this
  /// parser explicit so private server-only fields are never retained.
  factory QrRoundEnvelope.fromFeedJson(Map<String, dynamic> json) =>
      QrRoundEnvelope(
        round: QrDeviceRound.fromJson({
          'id': json['id'],
          'round_no': json['round_no'],
          'status': 'accepted',
          'priced_lines': json['priced_lines'],
          'subtotal_baisas': json['subtotal_baisas'],
          'tax_baisas': json['tax_baisas'],
          'total_baisas': json['total_baisas'],
          'submitted_at': json['submitted_at'],
          'resolved_at': json['resolved_at'],
        }),
        orderUuid: json['order_uuid']?.toString() ?? '',
        sessionUuid: _nullableString(json['session_uuid']),
        tableLabel: _nullableString(json['table_label']),
        receiptNumber: _nullableString(json['receipt_number']),
        tempReference: _nullableString(json['temp_reference']),
        ticketKey: _nullableString(json['ticket_key']),
        claimedByDeviceId: (json['claimed_by_device_id'] as num?)?.toInt(),
        printedAt: DateTime.tryParse(json['printed_at']?.toString() ?? ''),
        needsReview: json['needs_review'] == true,
      );
}

class QrKitchenTicket {
  const QrKitchenTicket({
    required this.ticketKey,
    required this.roundId,
    required this.orderUuid,
    required this.replayed,
    required this.pricedLines,
    this.claimedByDeviceId,
    this.claimedAt,
    this.printResult,
    this.printedAt,
    this.printPending = false,
  });

  final String ticketKey;
  final int roundId;
  final String orderUuid;
  final bool replayed;
  final List<QrRoundDisplayLine> pricedLines;
  final int? claimedByDeviceId;
  final DateTime? claimedAt;
  final String? printResult;
  final DateTime? printedAt;
  final bool printPending;

  factory QrKitchenTicket.fromJson(Map<String, dynamic> json) {
    if (json['ticket_key'] is! String ||
        json['round_id'] is! num ||
        json['order_uuid'] is! String ||
        json['replayed'] is! bool ||
        json['priced_lines'] is! List) {
      throw const FormatException('Invalid kitchen print claim.');
    }
    return QrKitchenTicket(
      ticketKey: json['ticket_key'] as String,
      roundId: (json['round_id'] as num).toInt(),
      orderUuid: json['order_uuid'] as String,
      replayed: json['replayed'] as bool,
      pricedLines: [
        for (final line in json['priced_lines'] as List)
          QrRoundDisplayLine.fromJson((line as Map).cast<String, dynamic>()),
      ],
      claimedByDeviceId: (json['claimed_by_device_id'] as num?)?.toInt(),
      claimedAt: DateTime.tryParse(json['claimed_at']?.toString() ?? ''),
      printResult: _nullableString(json['print_result']),
      printedAt: DateTime.tryParse(json['printed_at']?.toString() ?? ''),
      printPending: json['print_pending'] == true,
    );
  }

  QrRoundEnvelope forPrinting(QrRoundEnvelope envelope) {
    if (!printPending && !envelope.needsReview) return envelope;
    final round = envelope.round;
    return QrRoundEnvelope(
      round: QrDeviceRound(
        id: round.id,
        roundNo: round.roundNo,
        status: round.status,
        lines: pricedLines,
        subtotalBaisas: round.subtotalBaisas,
        taxBaisas: round.taxBaisas,
        totalBaisas: round.totalBaisas,
        submittedAt: round.submittedAt,
        resolvedAt: round.resolvedAt,
      ),
      orderUuid: envelope.orderUuid,
      sessionUuid: envelope.sessionUuid,
      tableLabel: envelope.tableLabel,
      receiptNumber: envelope.receiptNumber,
      tempReference: envelope.tempReference,
      ticketKey: ticketKey,
      claimedByDeviceId: claimedByDeviceId,
      printedAt: printedAt,
      needsReview: envelope.needsReview,
    );
  }
}

class QrAcceptedRoundsPage {
  const QrAcceptedRoundsPage({
    required this.rounds,
    required this.skippedExpiredCount,
    this.nextCursor,
    this.latestCursor,
  });

  final List<QrRoundEnvelope> rounds;
  final String? nextCursor;
  final String? latestCursor;
  final int skippedExpiredCount;
}

class QrOrderAddon {
  const QrOrderAddon({
    required this.addOnId,
    required this.name,
    required this.priceDeltaBaisas,
    this.nameAr,
  });

  final int? addOnId;
  final String name;
  final String? nameAr;
  final int priceDeltaBaisas;

  factory QrOrderAddon.fromJson(Map<String, dynamic> json) => QrOrderAddon(
    addOnId: (json['add_on_id'] as num?)?.toInt(),
    name: (json['add_on_name'] ?? json['name'])?.toString() ?? '',
    nameAr: _nullableString(json['add_on_name_ar'] ?? json['name_ar']),
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
    this.combo = const <Map<String, dynamic>>[],
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
  // LAUNCH-P4 C7 — a combo line's chosen items as the server nests them
  // (`combo`, per ONE combo); display-only.
  final List<Map<String, dynamic>> combo;

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
      combo: [
        for (final c
            in ((json['combo'] ?? json['components']) as List?) ?? const [])
          if (c is Map) c.cast<String, dynamic>(),
      ],
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
    this.tempReference,
  });

  final String uuid;
  final String status;
  final String source;
  final int? tableId;
  final int? customerId;
  final String? plateNumber;
  final String? receiptNumber;
  final String? tempReference;
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
      tempReference: _nullableString(json['temp_reference']),
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
    this.receiptNumber,
    this.tempReference,
    this.claimedAt,
    this.alreadyClaimedByThisDevice = false,
  });

  final String orderUuid;
  final int frozenAmountBaisas;
  final String status;
  final DateTime deadlineAt;
  final String? receiptNumber;
  final String? tempReference;
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
      receiptNumber: _nullableString(json['receipt_number']),
      tempReference: _nullableString(json['temp_reference']),
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
    this.tempReference,
    this.sessionStatus,
  });

  final String orderUuid;
  final String status;
  final String? receiptNumber;
  final String? tempReference;
  final String? sessionStatus;

  factory QrOrderActionResult.fromJson(Map<String, dynamic> json) =>
      QrOrderActionResult(
        orderUuid: json['order_uuid']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        receiptNumber: _nullableString(json['receipt_number']),
        tempReference: _nullableString(json['temp_reference']),
        sessionStatus: _nullableString(json['session_status']),
      );
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
