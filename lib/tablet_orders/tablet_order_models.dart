import 'dart:math';

import '../qr_quick/qr_quick_models.dart';
import '../services/row_parsing.dart';

/// LAUNCH-P6 Part C — a customer tablet order as the staff list shows it
/// (`GET device/tablet-orders`, the "Row" of the server contract). Display
/// and action data only: never a cart, a price input or payment authority.
/// The server prices, numbers and settles it.
class TabletOrderRow {
  TabletOrderRow(Map<String, dynamic> json)
    : json = Map.unmodifiable(json),
      charge = TabletCharge(json['charge']),
      redeem = json['redeem'] == null ? null : TabletRedeem(json['redeem']),
      takenBy = TabletPerson.read(json['taken_by']),
      sentToKitchen = TabletPerson.read(json['sent_to_kitchen']) {
    if (uuid.isEmpty ||
        json['tablet_order_uuid'] is! String ||
        !orderTypes.contains(json['order_type']) ||
        !states.contains(json['state']) ||
        json['lines'] is! List ||
        json['total_baisas'] is! int ||
        (json['grand_total_baisas'] != null &&
            json['grand_total_baisas'] is! int) ||
        (json['paid'] != null && json['paid'] is! bool) ||
        (json['unpaid'] != null && json['unpaid'] is! bool) ||
        (json['table'] != null && json['table'] is! Map)) {
      throw const FormatException('Invalid tablet order row');
    }
    for (final line in json['lines'] as List) {
      if (line is! Map || line['qty'] is! num) {
        throw const FormatException('Invalid tablet order line');
      }
    }
  }

  static const orderTypes = {'dine_in', 'quick', 'to_go'};
  static const states = {'pending', 'sent', 'closed'};

  final Map<String, dynamic> json;
  final TabletCharge charge;
  final TabletRedeem? redeem;
  final TabletPerson? takenBy;
  final TabletPerson? sentToKitchen;

  /// The attention key of this order (`tablet:<uuid>`).
  String get attentionKey => 'tablet:$uuid';
  String get uuid => json['tablet_order_uuid'] as String? ?? '';
  String get orderUuid => json['order_uuid'] as String? ?? '';
  String get orderType => json['order_type'] as String;
  bool get dineIn => orderType == 'dine_in';
  bool get toGo => orderType == 'to_go';
  String get state => json['state'] as String;
  bool get pending => state == 'pending';
  bool get sent => state == 'sent';
  bool get closed => state == 'closed';
  bool get paid => json['paid'] == true;
  bool get unpaid => json['unpaid'] == true;

  /// "Unpaid" badge: sent to the kitchen and not paid yet.
  bool get sentUnpaid => sent && unpaid;
  String? get orderNumber => _text(json['order_number']);
  String? get tempReference => _text(json['temp_reference']);
  Map<String, dynamic>? get table =>
      json['table'] is Map ? Map<String, dynamic>.from(json['table']) : null;
  String? get tableName => _text(table?['name']);
  int? get tableId => (table?['id'] as num?)?.toInt();
  String? get tableSessionUuid => _text(json['table_session_uuid']);
  int? get roundId => (json['round_id'] as num?)?.toInt();
  String? get roundStatus => _text(json['round_status']);
  List<Map<String, dynamic>> get lines => [
    for (final line in json['lines'] as List) Map<String, dynamic>.from(line),
  ];

  /// What the customer submitted.
  int get totalBaisas => json['total_baisas'] as int;

  /// The order (or table bill) now — this is what cash pays.
  int? get grandTotalBaisas => json['grand_total_baisas'] as int?;
  int get payableBaisas => grandTotalBaisas ?? totalBaisas;
  String? get phoneMasked => _text(json['phone_masked']);
  String get payment => json['payment'] as String? ?? 'cash';
  int? get readyInMinutes => (json['ready_in_minutes'] as num?)?.toInt();
  DateTime? get submittedAt =>
      DateTime.tryParse(json['submitted_at']?.toString() ?? '');
  bool get recoveryNeeded => json['recovery_needed'] == true;

  /// A redeem still waiting for staff ("Use 50 points … ?").
  bool get redeemWaiting => redeem?.status == 'requested';

  /// "Table 5" for dine in, "#27" for Quick / To go.
  String label({required String tableWord}) {
    if (dineIn) return '$tableWord ${tableName ?? '?'}';
    final number = orderNumber ?? tempReference;
    return number == null ? '#' : '#$number';
  }

  /// Staff may still change the lines (F-8): not sent, not paid, not closed
  /// and no cash being taken.
  bool get editable =>
      pending && unpaid && charge.state == 'none' && !recoveryNeeded;

  /// Quick / To go: the cash can be taken (the claim then the existing pay).
  bool get canTakeCash =>
      !dineIn && unpaid && !closed && charge.state == 'none' && !redeemWaiting;

  /// The lines as edit requests (identity only, never a price).
  List<QrQuickLine> get editLines => [
    for (final line in lines)
      if (((line['qty'] as num?) ?? 0) > 0 &&
          (line['product_id'] as num?) != null)
        QrQuickLine(
          (line['product_id'] as num).toInt(),
          (line['qty'] as num).round().clamp(1, 99),
          <int>{
            for (final a in (line['addons'] as List?) ?? const [])
              if (a is Map && (a['add_on_id'] as num?) != null)
                (a['add_on_id'] as num).toInt(),
            for (final id in (line['addon_ids'] as List?) ?? const [])
              if (id is num) id.toInt(),
          }.toList(),
          combo: serverComboPicks(line),
        ),
  ];

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

/// F-15 — the cash claim on an unpaid order.
class TabletCharge {
  TabletCharge(Object? value)
    : state = value is Map && states.contains(value['state'])
          ? value['state'] as String
          : (value == null ? 'none' : 'unknown'),
      deviceId = value is Map ? (value['device_id'] as num?)?.toInt() : null,
      deadlineAt = value is Map
          ? DateTime.tryParse(value['deadline_at']?.toString() ?? '')
          : null,
      heldByThisDevice = value is Map && value['held_by_this_device'] == true;

  static const states = {'none', 'claimed', 'lapsed', 'uncertain', 'recovered'};

  /// `none | claimed | lapsed | uncertain | recovered`; `unknown` for a
  /// state this build does not know (treated as needing recovery).
  final String state;
  final int? deviceId;
  final DateTime? deadlineAt;
  final bool heldByThisDevice;
  bool get beingPaid => state == 'claimed';
}

/// Who took, sent or resolved a tablet order.
class TabletPerson {
  const TabletPerson({this.staffId, this.name, this.deviceId, this.at});
  final int? staffId;
  final String? name;
  final int? deviceId;
  final DateTime? at;

  static TabletPerson? read(Object? value) => value is Map
      ? TabletPerson(
          staffId: (value['staff_id'] as num?)?.toInt(),
          name: TabletOrderRow._text(value['name']),
          deviceId: (value['device_id'] as num?)?.toInt(),
          at: DateTime.tryParse(value['at']?.toString() ?? ''),
        )
      : null;
}

/// The customer's points request on the order.
class TabletRedeem {
  TabletRedeem(Object? value)
    : json = value is Map
          ? Map<String, dynamic>.unmodifiable(value)
          : throw const FormatException('Invalid redeem') {
    if (!statuses.contains(json['status'])) {
      throw const FormatException('Unknown redeem status');
    }
  }
  static const statuses = {'requested', 'approved', 'rejected', 'superseded'};
  final Map<String, dynamic> json;
  String get status => json['status'] as String;
  String? get ruleName => TabletOrderRow._text(json['rule_name']);
  String get kind => json['kind'] as String? ?? 'points';
  bool get stamps => kind == 'stamps';
  int get blocks => (json['blocks'] as num?)?.toInt() ?? 0;
  bool get available => json['available'] != false;

  /// What approving takes now (requested), what the bill's slot takes now
  /// (approved; 0 once gone), nothing (rejected / superseded).
  int get units => (json['units'] as num?)?.toInt() ?? 0;
  int get amountBaisas => (json['amount_baisas'] as num?)?.toInt() ?? 0;

  /// For display (Part C note 3): a rejected request shows 0; an approved
  /// one shows what was approved.
  int get shownUnits => switch (status) {
    'approved' => (json['approved_units'] as num?)?.toInt() ?? units,
    'requested' => units,
    _ => 0,
  };
  int get shownAmountBaisas => switch (status) {
    'approved' =>
      (json['approved_amount_baisas'] as num?)?.toInt() ?? amountBaisas,
    'requested' => amountBaisas,
    _ => 0,
  };
  TabletPerson? get resolvedBy => TabletPerson.read(json['resolved_by']);
}

/// The tablet orders of a list response; a bad row is skipped and logged.
List<TabletOrderRow> parseTabletOrderRows(Object? rows) =>
    parseRowsSkippingBad(rows, TabletOrderRow.new, list: 'tablet-orders');

/// A request id (UUID v4) for idempotent staff writes.
String tabletRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
