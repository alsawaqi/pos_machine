import 'dart:math' as math;
import 'package:flutter/material.dart';

typedef LoyaltyApprover = ({int id, String name});

String loyaltyText(bool ar, String key) {
  const copy = <String, (String, String)>{
    'loyalty': ('Redeem points', 'استبدال النقاط'),
    'clear': ('Clear redemption', 'إزالة الاستبدال'),
    'cancel': ('Cancel', 'إلغاء'),
    'approve': ('Redeem', 'استبدال'),
    'empty': (
      'No whole reward blocks are available for this bill.',
      'لا تتوفر مكافآت كاملة لهذه الفاتورة.',
    ),
    'loyalty_no_customer': (
      'Attach a customer before redeeming points.',
      'أضف عميلاً قبل استبدال النقاط.',
    ),
    'loyalty_insufficient': (
      'Not enough available points or stamps. Other unpaid bills may hold them.',
      'النقاط أو الأختام المتاحة غير كافية. قد تكون محجوزة لفواتير أخرى غير مدفوعة.',
    ),
    'loyalty_customer_limit': (
      'This customer has reached today’s redemption limit.',
      'وصل العميل إلى حد الاستبدال اليومي.',
    ),
    'loyalty_staff_limit': (
      'This approver has reached the redemption limit for this shift.',
      'وصل المشرف إلى حد الاستبدال لهذه الوردية.',
    ),
    'loyalty_rule_unsupported': (
      'This reward cannot be redeemed at the table.',
      'لا يمكن استبدال هذه المكافأة على الطاولة.',
    ),
    'approval_required': (
      'A verified staff approval is required. Try the manager PIN.',
      'تلزم موافقة موظف موثّقة. استخدم رمز المشرف.',
    ),
    'validation_failed': (
      'The redemption request is invalid. Refresh and select it again.',
      'طلب الاستبدال غير صالح. حدّث الفاتورة واختر مجدداً.',
    ),
    'offline': (
      'Connect to the server before redeeming points.',
      'اتصل بالخادم قبل استبدال النقاط.',
    ),
  };
  final pair = copy[key];
  return pair == null
      ? key
      : ar
      ? pair.$2
      : pair.$1;
}

String loyaltyEarnedText(bool ar, Object? raw) {
  if (raw is! Map) return '';
  final parts = <String>[];
  final points = raw['points'];
  final stamps = raw['stamps'];
  if (points is num && points > 0) {
    parts.add(ar ? 'لقد كسبت $points نقطة' : 'You earned $points points');
  }
  if (stamps is num && stamps > 0) {
    parts.add(ar ? 'لقد كسبت $stamps أختام' : 'You earned $stamps stamps');
  }
  return parts.join(' · ');
}

/// Catalogue and balances are display hints; only whole-block intent leaves here.
Future<Map<String, dynamic>?> pickTableLoyalty(
  BuildContext context, {
  required Map<String, dynamic> bill,
  required List<Map<String, dynamic>> rules,
  required Future<Map<String, dynamic>> Function(int) customer,
  required Future<LoyaltyApprover?> Function() approve,
}) async {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  final attached = bill['customer'];
  if (attached is! Map || attached['id'] is! int) return null;
  final Map<String, dynamic> current;
  try {
    current = await customer(attached['id'] as int);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loyaltyText(ar, 'offline'))));
    }
    return null;
  }
  if (!context.mounted) return null;
  final accounts = (current['loyalty'] as List? ?? const []).whereType<Map>();
  final state = bill['adjustment_state'] as Map? ?? const {};
  final active = state['loyalty'] as Map?;
  final previous = (active?['amount_baisas'] as num? ?? 0).toInt();
  final net =
      (bill['subtotal_baisas'] as num? ?? 0).toInt() -
      (bill['discount_total_baisas'] as num? ?? 0).toInt() -
      (bill['comp_total_baisas'] as num? ?? 0).toInt() +
      previous;
  final options =
      <
        ({
          int id,
          String name,
          int units,
          int value,
          int max,
          bool stamps,
          int available,
        })
      >[];
  num number(Object? n) => n is num ? n : num.tryParse('$n') ?? 0;
  for (final rule in rules) {
    if (rule['active'] != true) continue;
    final config = rule['config'] as Map? ?? const {};
    final stamps = rule['type'] == 'visit_based';
    if (!stamps && rule['type'] != 'spend_based') continue;
    if (stamps &&
        !const ['fixed', 'fixed_off'].contains(config['reward_type'])) {
      continue;
    }
    final units = number(
      config[stamps ? 'stamps_required' : 'redemption_points'],
    ).toInt();
    final value =
        (number(config[stamps ? 'reward_value' : 'redemption_value']) * 1000)
            .round();
    if (units <= 0 || value <= 0) continue;
    final account = accounts
        .where((a) => a['rule_id'] == rule['id'])
        .firstOrNull;
    final available = math.max(
      0,
      number(
        account?[stamps ? 'available_stamps' : 'available_points'],
      ).toInt(),
    );
    final max = math.min(50, math.min(available ~/ units, (net - 1) ~/ value));
    if (max < 1) continue;
    options.add((
      id: rule['id'] as int,
      name: '${rule['name']}',
      units: units,
      value: value,
      max: max,
      stamps: stamps,
      available: available,
    ));
  }
  var selected = 0, blocks = 1;
  final intent = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final option = options.isEmpty ? null : options[selected];
        final unitName = option?.stamps == true
            ? (ar ? 'ختم' : 'stamps')
            : (ar ? 'نقطة' : 'points');
        return AlertDialog(
          key: const ValueKey('table-loyalty-picker'),
          title: Text(loyaltyText(ar, 'loyalty')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (options.isEmpty) Text(loyaltyText(ar, 'empty')),
                for (var i = 0; i < options.length; i++)
                  ListTile(
                    key: ValueKey('table-loyalty-rule-${options[i].id}'),
                    title: Text(options[i].name),
                    subtitle: Text(
                      '${ar ? 'المتاح' : 'Available'}: ${options[i].available} ${options[i].stamps ? (ar ? 'ختم' : 'stamps') : (ar ? 'نقطة' : 'points')}',
                    ),
                    selected: selected == i,
                    onTap: () => setState(() {
                      selected = i;
                      blocks = 1;
                    }),
                  ),
                if (option != null) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('table-loyalty-minus'),
                        onPressed: blocks > 1
                            ? () => setState(() => blocks--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text(
                        '$blocks / ${option.max}',
                        key: const ValueKey('table-loyalty-blocks'),
                      ),
                      IconButton(
                        key: const ValueKey('table-loyalty-plus'),
                        onPressed: blocks < option.max
                            ? () => setState(() => blocks++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Text(
                    ar
                        ? 'استبدال ${blocks * option.units} $unitName مقابل ${(blocks * option.value / 1000).toStringAsFixed(3)} ر.ع.'
                        : 'Redeem ${blocks * option.units} $unitName for OMR ${(blocks * option.value / 1000).toStringAsFixed(3)}',
                    key: const ValueKey('table-loyalty-money'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(loyaltyText(ar, 'cancel')),
            ),
            if (previous > 0)
              TextButton(
                key: const ValueKey('table-loyalty-clear'),
                onPressed: () =>
                    Navigator.pop(dialog, {'kind': 'loyalty', 'mode': 'clear'}),
                child: Text(loyaltyText(ar, 'clear')),
              ),
            FilledButton(
              key: const ValueKey('table-loyalty-apply'),
              onPressed: option == null
                  ? null
                  : () => Navigator.pop(dialog, {
                      'kind': 'loyalty',
                      'mode': 'redeem',
                      'rule_id': option.id,
                      'blocks': blocks,
                    }),
              child: Text(loyaltyText(ar, 'approve')),
            ),
          ],
        );
      },
    ),
  );
  if (intent == null || !context.mounted) return null;
  if (intent['mode'] == 'clear') return intent;
  final who = await approve();
  if (who == null ||
      who.id <= 0 ||
      who.name.trim().isEmpty ||
      !context.mounted) {
    return null;
  }
  return {...intent, 'authorized_by': who.name, 'approved_by_staff_id': who.id};
}
