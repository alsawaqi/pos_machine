/// Phase C1 — kitchen ticket (blueprint §6.10): "just the items, quantities,
/// add-ons, notes — printed to the kitchen thermal printer". NO prices appear
/// anywhere on a kitchen ticket.
///
/// This file is PURE (no printer plugin import) so the ticket layout is
/// unit-testable exactly like order_sync_payload: the builder turns the
/// already-flowing CartItem.toMap item shape into a list of styled lines, and
/// [SunmiReceiptService.printKitchenTicket] renders them fail-safe.
library;

/// One printable line of a kitchen ticket, with the minimal style hints the
/// Sunmi renderer needs. [fontSize] null = the printer's default size.
class KitchenTicketLine {
  const KitchenTicketLine(
    this.text, {
    this.bold = false,
    this.fontSize,
    this.center = false,
  });

  final String text;
  final bool bold;
  final int? fontSize;
  final bool center;
}

/// Everything a kitchen ticket shows. [items] is the CartItem.toMap shape
/// (`name`, `qty`, `modifiers` [{group,label}], `notes`) that both completed
/// snapshots (OrderSnapshot.items) and held drafts (draft.items[i].toMap())
/// already produce — prices in those maps are simply never printed.
class KitchenTicketData {
  const KitchenTicketData({
    required this.orderLabel,
    required this.orderTypeLabel,
    required this.time,
    required this.items,
    this.tableLabel = '',
    this.deliveryProvider = '',
    this.isReprint = false,
    this.isHold = false,
  });

  /// 'Order #1450' for completed orders, the held reference ('REF-1450') for
  /// holds — whatever identifies the ticket to the kitchen.
  final String orderLabel;
  final String orderTypeLabel;

  /// 'Table 4 | Main Hall' (empty = not dine-in / unknown).
  final String tableLabel;

  /// Provider name for delivery orders (empty = none).
  final String deliveryProvider;

  /// Order time for completed prints, hold time for holds, the ORIGINAL order
  /// time for reprints.
  final DateTime time;

  final bool isReprint;
  final bool isHold;
  final List<Map<String, dynamic>> items;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 'dd/MM HH:mm' — compact, unambiguous on a 32-char ticket.
String formatKitchenTicketTime(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)} ${_two(t.hour)}:${_two(t.minute)}';

const String _divider = '--------------------------------';

/// Build the kitchen ticket lines. Layout: KITCHEN header (+ REPRINT / ON HOLD
/// banner), order label large, type + time, table / delivery context, then per
/// item a large "qty x NAME" line with its add-ons (`+ label`) and prep notes
/// (`** note`) indented under it. No money values, ever.
List<KitchenTicketLine> buildKitchenTicketLines(KitchenTicketData t) {
  final lines = <KitchenTicketLine>[
    const KitchenTicketLine('KITCHEN', bold: true, fontSize: 36, center: true),
  ];

  if (t.isReprint) {
    lines.add(
      const KitchenTicketLine('*** REPRINT ***', bold: true, center: true),
    );
  }
  if (t.isHold) {
    lines.add(
      const KitchenTicketLine('*** ON HOLD ***', bold: true, center: true),
    );
  }

  lines
    ..add(
      KitchenTicketLine(t.orderLabel, bold: true, fontSize: 32, center: true),
    )
    ..add(
      KitchenTicketLine(
        '${t.orderTypeLabel}  ${formatKitchenTicketTime(t.time)}',
        center: true,
      ),
    );

  if (t.tableLabel.trim().isNotEmpty) {
    lines.add(
      KitchenTicketLine(t.tableLabel.trim(), bold: true, center: true),
    );
  }
  if (t.deliveryProvider.trim().isNotEmpty) {
    lines.add(
      KitchenTicketLine(
        'Delivery via ${t.deliveryProvider.trim()}',
        bold: true,
        center: true,
      ),
    );
  }

  lines.add(const KitchenTicketLine(_divider));

  for (final item in t.items) {
    final name = item['name']?.toString() ?? 'Item';
    final qtyNum = (item['qty'] as num?) ?? 1;
    // Whole quantities print as integers ('2 x'), fractional ones as-is.
    final qty = qtyNum == qtyNum.truncateToDouble()
        ? qtyNum.toInt().toString()
        : qtyNum.toString();

    lines.add(KitchenTicketLine('$qty x $name', bold: true, fontSize: 30));

    for (final raw in (item['modifiers'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final label = raw['label']?.toString().trim() ?? '';
      if (label.isEmpty) continue;
      final group = raw['group']?.toString().trim() ?? '';
      lines.add(
        KitchenTicketLine(group.isEmpty ? '  + $label' : '  + $group: $label'),
      );
    }

    final notes = item['notes']?.toString().trim() ?? '';
    if (notes.isNotEmpty) {
      lines.add(KitchenTicketLine('  ** $notes', bold: true));
    }
  }

  lines.add(const KitchenTicketLine(_divider));
  return lines;
}
