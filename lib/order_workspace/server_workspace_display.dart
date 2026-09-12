import 'package:flutter/material.dart';

/// Customer-facing projection only: no cart objects, tender controls or PII.
class ServerWorkspaceDisplay extends StatelessWidget {
  const ServerWorkspaceDisplay({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final ar = data['language'] == 'ar';
    final paid = data['status'] == 'paid';
    final items = (data['items'] as List? ?? const []).whereType<Map>();
    String money(Object? value) =>
        value is int ? 'OMR ${(value / 1000).toStringAsFixed(3)}' : '—';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: const Color(0xFFF5F1EA),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  paid
                      ? (ar ? 'اكتمل الدفع' : 'Payment complete')
                      : (ar ? 'طلبك' : 'Your order'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  data['reference']?.toString() ?? '',
                  key: const ValueKey('server-display-reference'),
                ),
                if (data['stale'] == true)
                  Text(
                    ar ? 'بانتظار تحديث الفاتورة' : 'Waiting for a bill update',
                  ),
                const Divider(height: 30),
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in items)
                        ListTile(
                          title: Text(
                            '${item['qty']} × ${(ar ? item['name_ar'] : null) ?? item['name'] ?? ''}',
                          ),
                          subtitle: Text(
                            [
                              if (item['notes'] is String) item['notes'],
                              ...((item['addons'] as List?) ?? const []),
                            ].whereType<String>().join(' · '),
                          ),
                          trailing: Text(money(item['total_baisas'])),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Text(
                  '${ar ? 'الإجمالي' : 'Total'}: ${money(data['total_baisas'])}',
                  key: const ValueKey('server-display-total'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
