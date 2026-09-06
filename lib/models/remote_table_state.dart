import 'dart:convert';

String tableSessionsMode(Object? value) =>
    const {'off', 'shadow', 'live'}.contains(value) ? value as String : 'off';

class RemoteTableState {
  const RemoteTableState({
    required this.tableId,
    required this.fetchedAt,
    this.source = 'board',
    this.seatingUuid,
    this.seatingStatus,
    this.origin,
    this.tempReference,
    this.openedAt,
    this.expiresAt,
    this.needsReviewCount = 0,
    this.joinedTableIds = const [],
    this.billOrderUuid,
    this.billStatus,
    this.billGrandTotalBaisas,
    this.billReceiptNumber,
    this.billTempReference,
    this.chargeClaimLive = false,
  });

  final int tableId;
  final String? seatingUuid, seatingStatus, origin, tempReference;
  final DateTime? openedAt, expiresAt;
  final int needsReviewCount;
  final List<int> joinedTableIds;
  final String? billOrderUuid, billStatus;
  final int? billGrandTotalBaisas;
  final String? billReceiptNumber, billTempReference;
  final bool chargeClaimLive;
  final DateTime fetchedAt;
  final String source;

  bool get awaitingPayment => billStatus == 'awaiting_payment';
  bool get occupied => seatingUuid != null || billOrderUuid != null;
  String get serverStatus =>
      seatingStatus ??
      (awaitingPayment
          ? 'billing'
          : occupied
          ? 'open'
          : 'free');
  String? get reference => tempReference ?? billTempReference;

  factory RemoteTableState.fromBoard(
    Map<String, dynamic> row,
    DateTime fetchedAt,
  ) {
    final seating = (row['seating'] as Map?)?.cast<String, dynamic>();
    final bill = (row['bill'] as Map?)?.cast<String, dynamic>();
    return RemoteTableState(
      tableId: (row['table_id'] as num).toInt(),
      seatingUuid: seating?['uuid'] as String?,
      seatingStatus: seating?['status'] as String?,
      origin: seating?['origin'] as String?,
      tempReference: seating?['temp_reference'] as String?,
      openedAt: _date(seating?['opened_at']),
      expiresAt: _date(seating?['expires_at']),
      needsReviewCount: (seating?['needs_review_count'] as num?)?.toInt() ?? 0,
      joinedTableIds: [
        for (final id in (seating?['joined_table_ids'] as List? ?? const []))
          (id as num).toInt(),
      ],
      billOrderUuid: bill?['order_uuid'] as String?,
      billStatus: bill?['status'] as String?,
      billGrandTotalBaisas: (bill?['grand_total_baisas'] as num?)?.toInt(),
      billReceiptNumber: bill?['receipt_number'] as String?,
      billTempReference: bill?['temp_reference'] as String?,
      chargeClaimLive: bill?['charge_claim_live'] == true,
      fetchedAt: fetchedAt,
    );
  }

  Map<String, Object?> toRow() => {
    'table_id': tableId,
    'seating_uuid': seatingUuid,
    'seating_status': seatingStatus,
    'origin': origin,
    'temp_reference': tempReference,
    'opened_at': openedAt?.toIso8601String(),
    'expires_at': expiresAt?.toIso8601String(),
    'needs_review_count': needsReviewCount,
    'joined_table_ids_json': jsonEncode(joinedTableIds),
    'bill_order_uuid': billOrderUuid,
    'bill_status': billStatus,
    'bill_grand_total_baisas': billGrandTotalBaisas,
    'bill_receipt_number': billReceiptNumber,
    'bill_temp_reference': billTempReference,
    'charge_claim_live': chargeClaimLive ? 1 : 0,
    'fetched_at': fetchedAt.toIso8601String(),
    'source': source,
  };

  factory RemoteTableState.fromRow(Map<String, Object?> row) =>
      RemoteTableState(
        tableId: row['table_id'] as int,
        seatingUuid: row['seating_uuid'] as String?,
        seatingStatus: row['seating_status'] as String?,
        origin: row['origin'] as String?,
        tempReference: row['temp_reference'] as String?,
        openedAt: _date(row['opened_at']),
        expiresAt: _date(row['expires_at']),
        needsReviewCount: row['needs_review_count'] as int,
        joinedTableIds: [
          for (final id in jsonDecode(
            row['joined_table_ids_json'] as String? ?? '[]',
          ) as List)
            (id as num).toInt(),
        ],
        billOrderUuid: row['bill_order_uuid'] as String?,
        billStatus: row['bill_status'] as String?,
        billGrandTotalBaisas: row['bill_grand_total_baisas'] as int?,
        billReceiptNumber: row['bill_receipt_number'] as String?,
        billTempReference: row['bill_temp_reference'] as String?,
        chargeClaimLive: row['charge_claim_live'] == 1,
        fetchedAt: DateTime.parse(row['fetched_at'] as String),
        source: row['source'] as String,
      );
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

class RemoteSyncMeta {
  const RemoteSyncMeta({
    this.feedCursor,
    this.boardFetchedAt,
    this.lastFeedOkAt,
    this.lastError,
    this.consecutiveFailures = 0,
    this.lastNotifiedEventId,
  });

  final int? feedCursor;
  final DateTime? boardFetchedAt, lastFeedOkAt;
  final String? lastError;
  final int consecutiveFailures;
  final int? lastNotifiedEventId;

  factory RemoteSyncMeta.fromRow(Map<String, Object?> row) => RemoteSyncMeta(
    feedCursor: row['feed_cursor'] as int?,
    boardFetchedAt: _date(row['board_fetched_at']),
    lastFeedOkAt: _date(row['last_feed_ok_at']),
    lastError: row['last_error'] as String?,
    consecutiveFailures: row['consecutive_failures'] as int? ?? 0,
    lastNotifiedEventId: row['last_notified_event_id'] as int?,
  );

  Map<String, Object?> toRow() => {
    'id': 1,
    'feed_cursor': feedCursor,
    'board_fetched_at': boardFetchedAt?.toIso8601String(),
    'last_feed_ok_at': lastFeedOkAt?.toIso8601String(),
    'last_error': lastError,
    'consecutive_failures': consecutiveFailures,
    if (lastNotifiedEventId != null) 'last_notified_event_id': lastNotifiedEventId,
  };
}

class RemoteTableSnapshot {
  const RemoteTableSnapshot({
    this.tables = const {},
    this.meta = const RemoteSyncMeta(),
  });
  final Map<int, RemoteTableState> tables;
  final RemoteSyncMeta meta;

  Map<String, RemoteTableState> forTableIds(Iterable<String> ids) {
    final result = <String, RemoteTableState>{};
    for (final id in ids) {
      final row = tables[int.tryParse(id)];
      if (row != null) result[id] = row;
    }
    return result;
  }
}

/// Deliberately has no local order or dining-table write methods.
abstract interface class RemoteTableStore {
  Future<List<RemoteTableState>> readRemoteTables();
  Future<RemoteSyncMeta> readRemoteMeta();
  Future<void> replaceRemoteBoard(List<RemoteTableState> rows, DateTime at);
  Future<void> saveRemoteMeta(RemoteSyncMeta meta);
  Future<void> clearRemoteScope();
  Future<List<Map<String, Object?>>> readRemoteDisagreements({int limit = 200});
  Future<void> addRemoteDisagreement(Map<String, Object?> row);
}

class LocalTableShadowView {
  const LocalTableShadowView({
    required this.tableId,
    required this.status,
    this.reference,
  });
  final String tableId, status;
  final String? reference;
}
