import 'dart:convert';

const tableCancelRefusals = {
  'bill_changed',
  'bill_reserved',
  'bill_has_payment',
  'nothing_to_cancel',
  'bill_terminal',
  'cancel_request_conflict',
};
String tableCancelText(String code, bool ar) {
  const text = {
    'bill_changed': [
      'The bill changed. Reload the items and request approval again.',
      'تغيرت الفاتورة. حدّث الأصناف واطلب الموافقة مجدداً.',
    ],
    'bill_reserved': [
      'Resolve the payment result and reopen the bill before cancelling.',
      'تحقق من نتيجة الدفع وأعد فتح الفاتورة قبل الإلغاء.',
    ],
    'bill_has_payment': [
      'This bill has a payment and cannot be cancelled here.',
      'تحتوي الفاتورة على دفعة ولا يمكن إلغاؤها هنا.',
    ],
    'nothing_to_cancel': [
      'There are no accepted items to cancel. Use Clear Table for an empty session.',
      'لا توجد أصناف مقبولة للإلغاء. استخدم إخلاء الطاولة للجلسة الفارغة.',
    ],
    'bill_terminal': [
      'This bill is already closed. Refresh the tables.',
      'هذه الفاتورة مغلقة بالفعل. حدّث الطاولات.',
    ],
    'cancel_request_conflict': [
      'This saved cancellation conflicts with the server record. Ask a manager to review it.',
      'يتعارض الإلغاء المحفوظ مع سجل الخادم. اطلب من المدير مراجعته.',
    ],
    'cancel_offline': [
      'Connect to the server before cancelling a table bill.',
      'اتصل بالخادم قبل إلغاء فاتورة الطاولة.',
    ],
    'cancel_pending': [
      'The cancellation is saved. Retry the same request; do not enter it again.',
      'تم حفظ الإلغاء. أعد محاولة نفس الطلب ولا تدخله مجدداً.',
    ],
    'cancel_blocked': [
      'Resolve saved actions and send or remove unsent items before cancelling.',
      'تحقق من الإجراءات المحفوظة وأرسل أو أزل الأصناف غير المرسلة قبل الإلغاء.',
    ],
    'cancelled': [
      'Table bill cancelled. Nothing was charged.',
      'تم إلغاء فاتورة الطاولة. لم يتم تحصيل أي مبلغ.',
    ],
    'replayed': [
      'The saved cancellation was already applied.',
      'تم تطبيق الإلغاء المحفوظ مسبقاً.',
    ],
  };
  return (text[code] ?? text['cancel_blocked']!)[ar ? 1 : 0];
}

/// The API groups every accepted remainder across rounds, independent of prices.
class BillCancelGroup {
  const BillCancelGroup(this.selector, this.label, this.qty, this.prepared);
  final Map<String, dynamic> selector;
  final String label;
  final int qty;
  final bool prepared;
  String get key => jsonEncode(selector);
  static List<BillCancelGroup> fromRounds(List<Map<String, dynamic>> rounds) {
    final groups = <String, BillCancelGroup>{};
    for (final round in rounds) {
      if (round['status'] != 'accepted') continue;
      for (final raw in round['priced_lines'] as List) {
        final line = Map<String, dynamic>.from(raw as Map);
        if (line['held_reason'] != null) continue;
        final qty = (line['qty'] as int) - (line['cancelled_qty'] as int? ?? 0);
        if (qty <= 0) continue;
        final addons = (line['addons'] as List? ?? []).cast<Map>();
        final ids = addons.map((a) => a['add_on_id'] as int).toSet().toList()
          ..sort();
        final notes = (line['notes'] as String? ?? '')
            .replaceAll(RegExp(r'\s+', unicode: true), ' ')
            .trim()
            .toLowerCase();
        final selector = <String, dynamic>{
          'product_id': line['product_id'],
          'addon_ids': ids,
          'notes': notes.isEmpty ? null : notes,
        };
        final key = jsonEncode(selector), previous = groups[key];
        final label = [
          line['product_name'] ?? line['name'] ?? line['product_id'],
          ...addons.map((a) => a['name'] ?? a['add_on_id']),
          if (notes.isNotEmpty) notes,
        ].join(' · ');
        groups[key] = BillCancelGroup(
          selector,
          previous?.label ?? label,
          qty + (previous?.qty ?? 0),
          round['kitchen_printed_at'] != null || previous?.prepared == true,
        );
      }
    }
    return groups.values.toList();
  }
}

String? cancellationFailedCode(
  Map<String, dynamic> event,
  List<Map<String, dynamic>> response,
) {
  if (!const {
        'table.session.cancel_bill',
        'table.session.cancel_line',
      }.contains(event['event_type']) ||
      response.length != 1) {
    return null;
  }
  final ack = response.single;
  if (ack['client_event_id'] != event['client_event_id'] ||
      ack['status'] != 'failed') {
    return null;
  }
  final result = ack['result'];
  final code = result is Map ? result['refusal_code'] : null;
  return code is String && tableCancelRefusals.contains(code) ? code : null;
}

/// Money is read solely from the server's recorded waste evidence.
String? cancellationWasteNotice(Map<String, dynamic> result, bool ar) {
  final blocks = result['lines'] is List
      ? (result['lines'] as List).cast<Map>().map((l) => l['waste'])
      : [result['waste']];
  var cost = 0;
  var booked = false;
  for (final block in blocks) {
    if (block is Map &&
        block['booked'] == true &&
        block['cost_baisas'] is int &&
        (block['cost_baisas'] as int) >= 0) {
      booked = true;
      cost += block['cost_baisas'] as int;
    }
  }
  if (!booked) return null;
  final amount = (cost / 1000).toStringAsFixed(3);
  return ar ? 'تم تسجيل الهدر: $amount ر.ع.' : 'Waste recorded: OMR $amount';
}

/// Strict success proof; malformed results remain uncertain, never retire a copy.
void validateBillCancellation(
  Map<String, dynamic> request,
  Map<String, dynamic> result,
  String bill,
  String seating,
) {
  if (!const {'cancelled', 'replayed'}.contains(result['outcome']) ||
      result['client_request_id'] != request['client_request_id'] ||
      result['seating_key'] != request['seating_key'] ||
      result['table_id'] != request['table_id'] ||
      result['order_uuid'] != bill ||
      (result['winner_table_session_uuid'] ?? result['table_session_uuid']) !=
          seating ||
      result['status'] != 'void' ||
      result['grand_total_baisas'] != 0 ||
      result['lines'] is! List) {
    throw const FormatException('Uncertain bill cancellation');
  }
  final sent = (request['lines'] as List).cast<Map>(),
      received = (result['lines'] as List).cast<Map>();
  if (sent.length != received.length ||
      received.map((l) => l['client_request_id']).toSet().length !=
          sent.length) {
    throw const FormatException('Incomplete cancellation');
  }
  for (final line in sent) {
    final ack = received
        .where((r) => r['client_request_id'] == line['client_request_id'])
        .single;
    if (ack['cancelled_qty'] != line['qty'] ||
        ack['unlinked_line_count'] != 0 ||
        ack['waste'] is! Map) {
      throw const FormatException('Uncertain cancelled quantity');
    }
  }
}
