import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../qr_quick/qr_quick_models.dart';
import '../models/pos_models.dart';
import '../qr_checkout/qr_checkout_models.dart' show frozenCheckoutMap;

/// Display-only server data. Never a local cart or an order/payment payload.
class WorkspaceBill {
  WorkspaceBill(Map<String, dynamic> order)
    : json = frozenCheckoutMap(qrMap(jsonDecode(jsonEncode(order)))) {
    if (json['uuid'] is! String ||
        (json['uuid'] as String).isEmpty ||
        json['grand_total_baisas'] is! int ||
        (json['grand_total_baisas'] as int) < 0 ||
        json['items'] is! List) {
      throw const FormatException('Invalid workspace bill');
    }
    for (final line in items) {
      if (line['product_name'] is! String ||
          line['qty'] is! num ||
          !(line['qty'] as num).isFinite ||
          (line['qty'] as num) < 0 ||
          line['line_total_baisas'] is! int) {
        throw const FormatException('Invalid workspace bill line');
      }
    }
  }
  final Map<String, dynamic> json;
  String get uuid => json['uuid'] as String;
  String get reference =>
      (json['receipt_number'] ?? json['temp_reference'] ?? uuid).toString();
  int get total => json['grand_total_baisas'] as int;
  int get subtotal =>
      json['subtotal_baisas'] as int? ??
      items.fold(0, (sum, line) => sum + (line['line_total_baisas'] as int));
  int get discount => json['discount_total_baisas'] as int? ?? 0;
  int get comp => json['comp_total_baisas'] as int? ?? 0;
  int get tax =>
      json['tax_total_baisas'] as int? ?? total - subtotal + discount + comp;
  List<WorkspaceCartItem> get cartItems =>
      items.map(WorkspaceCartItem.new).toList();

  /// Group display-equivalent lines while retaining every server identity.
  /// Original rounds remain untouched for pricing, audit and retry recovery.
  List<Map<String, dynamic>> get groupedItems {
    final rows = <String, Map<String, dynamic>>{};
    for (final line in items) {
      final qty = line['qty'] as num;
      final addons = (line['addons'] as List? ?? const []).map(qrMap).toList()
        ..sort((a, b) => '${a['add_on_id']}'.compareTo('${b['add_on_id']}'));
      final key = jsonEncode([
        line['product_id'] ?? line['id'],
        line['product_name'],
        line['product_name_ar'],
        line['notes'] ?? '',
        [
          for (final a in addons)
            [a['add_on_id'], a['add_on_name'], a['price_delta_baisas']],
        ],
        (line['line_total_baisas'] as int) / qty,
        line['unit_price_baisas'],
        ((line['line_discount_baisas'] as num?) ?? 0) / qty,
      ]);
      final row = rows[key];
      if (row == null) {
        rows[key] = {
          ...line,
          'item_ids': [line['id']],
        };
      } else {
        row['qty'] = (row['qty'] as num) + qty;
        row['line_total_baisas'] =
            (row['line_total_baisas'] as int) +
            (line['line_total_baisas'] as int);
        (row['item_ids'] as List).add(line['id']);
      }
    }
    return rows.values.toList();
  }

  /// Same customer screen as a cashier sale; only display fields cross engines.
  Map<String, dynamic> cartDisplay({
    required bool stale,
    bool arabic = false,
  }) => {
    ...OrderSnapshot.initial().toMap(),
    'type': 'order_snapshot',
    'orderNumber': 0,
    'receiptNumber': (json['receipt_number'] ?? json['temp_reference'] ?? '')
        .toString(),
    'orderType': json['order_type'] ?? 'quick_order',
    'items': [
      for (final item in cartItems)
        {
          'name': item.product.name,
          'nameAr': item.product.nameAr,
          'qty': item.serverQuantity,
          'unitPrice': item.unitPrice,
          'lineTotal': item.lineTotal,
          'notes': item.notes,
          'detailLines': item.detailLinesFor(arabic),
        },
    ],
    'rawSubtotal': subtotal / 1000,
    'discountAmount': discount / 1000,
    'compAmount': comp / 1000,
    'subtotal': (subtotal - discount) / 1000,
    'tax': tax / 1000,
    'total': total / 1000,
    'activePaymentBaseTotal': total / 1000,
    'payableTotal': total / 1000,
    'paymentStatus': json['status'] == 'paid' ? 'Paid' : 'Waiting',
    'note': stale
        ? (arabic ? 'بانتظار تحديث الفاتورة' : 'Waiting for a bill update')
        : json['preview_pending'] == true
        ? (arabic
              ? 'إجمالي تقديري — أصناف بانتظار الحفظ'
              : 'Estimated total — items awaiting confirmation')
        : '',
    'language': arabic ? 'ar' : 'en',
  };
  List<Map<String, dynamic>> get items => (json['items'] as List)
      .map(qrMap)
      .where((line) => line['status'] != 'void' && (line['qty'] as num) > 0)
      .toList();

  Map<String, dynamic> display({required bool stale}) => {
    'type': 'server_bill_snapshot',
    'reference': reference,
    'total_baisas': total,
    'status': json['status']?.toString() ?? '',
    'stale': stale,
    'items': [
      for (final item in items)
        {
          'name': item['product_name'],
          'name_ar': item['product_name_ar'],
          'qty': item['qty'],
          'total_baisas': item['line_total_baisas'],
          'notes': item['notes'],
          'addons': [
            for (final raw in (item['addons'] as List? ?? const []))
              (qrMap(raw)['add_on_name'] ?? qrMap(raw)['name'] ?? '')
                  .toString(),
          ],
        },
    ],
  };
}

/// Connects the existing server-bill editor to the MAIN catalogue and footer.
/// It has no cart, pricing, database, network or tender capability of its own.
class CurrentOrderWorkspace extends ChangeNotifier {
  CurrentOrderWorkspace({
    required this.onExit,
    this.mainCart = false,
    this.tableLabel,
    this.editOptions,
  });
  final Future<QrQuickLine?> Function(Map<String, dynamic>)? editOptions;
  final bool mainCart;
  final String? tableLabel;
  bool get dineIn => tableLabel != null;
  bool returnToList = true;
  // Correction returns to the existing local cart without invoking leave/send.
  bool returnToLocalCart = false;
  WorkspaceCartControls? cartControls;
  final VoidCallback onExit;
  Object? _owner;
  bool _disposed = false, _picking = false;
  Future<void> Function(QuickProduct)? _pick;
  Future<void> Function()? _leave, _pay;
  WorkspaceBill? bill;
  WorkspaceBill? get cartBill {
    final saved =
        bill ??
        (dineIn
            ? WorkspaceBill({
                'uuid': 'unsent-table-display',
                'temp_reference': tableLabel,
                'order_type': 'dine_in',
                'grand_total_baisas': 0,
                'subtotal_baisas': 0,
                'items': [],
              })
            : null);
    if (!mainCart || saved == null) return saved;
    final drafts = cartControls?.draftRows ?? const <Map<String, dynamic>>[];
    final pending = cartControls?.pendingRows ?? const <Map<String, dynamic>>[];
    final pendingTax = cartControls?.pendingTax ?? 0;
    // Display estimate only. The server still prices the submitted ID-only round.
    final draftSubtotal = drafts.fold<int>(
      0,
      (sum, line) => sum + (line['line_total_baisas'] as int),
    );
    final draftTax = (taxTotalFor(draftSubtotal / 1000) * 1000).round();
    final preview = [
      ...drafts,
      ...pending,
    ].fold<int>(0, (sum, line) => sum + (line['line_total_baisas'] as int));
    return WorkspaceBill({
      ...saved.json,
      if (dineIn) 'order_type': 'dine_in',
      'preview_pending': drafts.isNotEmpty || pending.isNotEmpty,
      'items': [...saved.groupedItems, ...pending, ...drafts],
      'subtotal_baisas': saved.subtotal + preview,
      'grand_total_baisas': saved.total + preview + pendingTax + draftTax,
      'tax_total_baisas': saved.tax + pendingTax + draftTax,
    });
  }

  bool stale = true, addEnabled = false, payEnabled = false;
  bool get canAdd => !_disposed && !_picking && addEnabled && _pick != null;
  bool get canPay => !_disposed && !_picking && payEnabled && _pay != null;

  void attach(
    Object owner, {
    required Future<void> Function(QuickProduct) pick,
    required Future<void> Function() leave,
    required Future<void> Function() pay,
  }) {
    if (_disposed) return;
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError('Workspace already has a bill editor');
    }
    _owner = owner;
    _pick = pick;
    _leave = leave;
    _pay = pay;
  }

  void publish(
    Object owner, {
    required Map<String, dynamic>? order,
    required bool stale,
    required bool canAdd,
    required bool canPay,
    WorkspaceCartControls? cartControls,
  }) {
    if (_disposed || !identical(_owner, owner)) return;
    this.cartControls = cartControls;
    try {
      bill = order == null ? null : WorkspaceBill(order);
      this.stale = stale;
      addEnabled = canAdd && !stale;
      payEnabled = canPay && !stale && bill != null;
    } catch (_) {
      bill = null;
      this.stale = true;
      addEnabled = payEnabled = false;
    }
    notifyListeners();
  }

  Future<void> pick(QuickProduct product) async {
    if (!canAdd || !product.available) return;
    _picking = true;
    notifyListeners();
    try {
      await _pick!(product);
    } finally {
      _picking = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> requestPay() async {
    if (canPay) await _pay!();
  }

  Future<void> requestClose() async {
    if (_disposed || _picking) return;
    if (_leave == null) {
      onExit();
    } else {
      await _leave!();
    }
  }

  void detach(Object owner) {
    if (_disposed || !identical(_owner, owner)) return;
    _owner = null;
    _pick = null;
    _leave = _pay = null;
    bill = null;
    addEnabled = payEnabled = false;
    stale = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pick = null;
    _leave = _pay = null;
    super.dispose();
  }
}

/// A frozen server line rendered by the existing cart widgets. Never persisted
/// into the cashier draft, repriced by the catalogue, or sent as order.create.
class WorkspaceCartItem extends CartItem {
  WorkspaceCartItem(Map<String, dynamic> line)
    : serverQuantity = line['qty'] as num,
      frozenTotal = (line['line_total_baisas'] as int) / 1000,
      super(
        product: Product(
          id: (line['product_id'] ?? line['order_item_id'] ?? '').toString(),
          name: line['product_name'] as String,
          nameAr: line['product_name_ar'] as String? ?? '',
          category: '',
          price: (line['qty'] as num) > 0
              ? (line['line_total_baisas'] as int) / 1000 / (line['qty'] as num)
              : 0,
        ),
        qty: (line['qty'] as num).toInt(),
        notes: line['notes'] as String? ?? '',
        modifiers: [
          for (final raw in line['addons'] as List? ?? const [])
            CartItemModifier(
              id: (qrMap(raw)['add_on_id'] ?? '').toString(),
              group: '',
              label: (qrMap(raw)['add_on_name'] ?? qrMap(raw)['name'] ?? '')
                  .toString(),
              labelAr:
                  (qrMap(raw)['add_on_name_ar'] ?? qrMap(raw)['name_ar'] ?? '')
                      .toString(),
              price: 0,
            ),
        ],
      );
  final num serverQuantity;
  final double frozenTotal;
  @override
  double get lineTotal => frozenTotal;
  @override
  List<String> detailLinesFor(bool arabic) => [
    for (final modifier in modifiers)
      if (modifier.displayLabel(arabic).isNotEmpty)
        modifier.displayLabel(arabic),
    if (notes.isNotEmpty) notes,
  ];
}

/// Guarded actions supplied by the QR controller to the normal cart surface.
class WorkspaceCartControls {
  const WorkspaceCartControls({
    this.busy = false,
    this.notices = const [],
    this.drafts = const [],
    this.draftRows = const [],
    this.pendingRows = const [],
    this.pendingTax = 0,
    this.removeDraft,
    this.refresh,
    this.retry,
    this.submit,
    this.move,
    this.voidBill,
    this.clear,
    this.quantity,
    this.customize,
    this.transfer,
    this.actions = const [],
  });
  final List<WorkspaceAction> actions;
  final bool busy;
  final List<String> notices, drafts;
  final List<Map<String, dynamic>> draftRows, pendingRows;
  final int pendingTax;
  final void Function(int)? removeDraft;
  final Future<void> Function()? refresh, retry, submit, move, voidBill, clear;
  final Future<void> Function(Map<String, dynamic>, int)? quantity;
  final Future<void> Function(Map<String, dynamic>)? customize;
  final Future<bool> Function(int)? transfer;
}

class WorkspaceAction {
  const WorkspaceAction(this.label, this.run);
  final String label;
  final Future<void> Function()? run;
}
