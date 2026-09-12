import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../qr_quick/qr_quick_models.dart';
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
  List<Map<String, dynamic>> get items =>
      (json['items'] as List).map(qrMap).toList();

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
  CurrentOrderWorkspace({required this.onExit});
  final VoidCallback onExit;
  Object? _owner;
  bool _disposed = false, _picking = false;
  Future<void> Function(QuickProduct)? _pick;
  Future<void> Function()? _leave, _pay;
  WorkspaceBill? bill;
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
  }) {
    if (_disposed || !identical(_owner, owner)) return;
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
