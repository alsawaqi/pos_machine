import 'dart:async';
import 'package:flutter/material.dart';
import 'recovery_controller.dart';
import 'recovery_models.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({
    super.key,
    required this.createController,
    this.arabic = false,
  });
  final Future<RecoveryController> Function() createController;
  final bool arabic;
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen>
    with WidgetsBindingObserver {
  RecoveryController? c;
  String? setupError;
  bool leaving = false;
  String t(String en, String ar) => widget.arabic ? ar : en;
  String money(int amount) => 'OMR ${(amount / 1000).toStringAsFixed(3)}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
  }

  Future<void> start() async {
    try {
      final controller = await widget.createController();
      if (!mounted) {
        controller.dispose();
        return;
      }
      c = controller;
      controller.addListener(changed);
      controller.setForeground(
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      await controller.start();
    } catch (e) {
      if (mounted) setState(() => setupError = e.toString());
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      c?.setForeground(state == AppLifecycleState.resumed);
  void close() {
    if (c?.canLeave != true && setupError == null) return;
    setState(() => leaving = true);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c?.removeListener(changed);
    c?.dispose();
    super.dispose();
  }

  Widget lines(String title, List<Map<String, dynamic>> items) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (items.isEmpty) Text(t('None', 'لا يوجد')),
          for (final line in items)
            ListTile(
              title: Text('${line['qty']} × ${line['name']}'),
              subtitle: Text(
                [
                  line['notes'],
                  for (final addon in recoveryMaps(line['addons']))
                    addon['name'],
                ].whereType<String>().where((v) => v.isNotEmpty).join(' · '),
              ),
              trailing: Text(money(line['line_total_baisas'] as int)),
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final controller = c,
        local = c?.local,
        preview = c?.preview,
        attempt = c?.attempt;
    final delta =
        attempt?.delta ??
        (local != null && preview != null
            ? local.delta(preview)
            : <Map<String, dynamic>>[]);
    final deltaState = const {
      'delta_ready',
      'delta_pending',
    }.contains(attempt?.state);
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) close();
      },
      child: Directionality(
        textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          key: const ValueKey('draft-recovery-review'),
          appBar: AppBar(
            title: Text(
              t('Recover this bill draft', 'استعادة مسودة هذه الفاتورة'),
            ),
            leading: IconButton(
              onPressed: close,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (controller == null || controller.busy)
                const LinearProgressIndicator(),
              Text(
                t(
                  'Review the original local draft and the items already received on this same bill. Original copies stay in the recovery archive.',
                  'راجع المسودة المحلية الأصلية والأصناف المستلمة على الفاتورة نفسها. تبقى النسخ الأصلية في أرشيف الاستعادة.',
                ),
              ),
              if (setupError != null || controller?.error != null)
                Text(
                  setupError ?? controller!.error!,
                  key: const ValueKey('draft-recovery-error'),
                ),
              if (local != null)
                lines(
                  t('Original local draft', 'المسودة المحلية الأصلية'),
                  local.items.map(recoveryLocalLine).toList(),
                ),
              if (preview != null) ...[
                Text(preview.proof['table_label'] as String),
                Text(
                  (recoveryMap(preview.proof['bill'])['receipt_number'] ??
                          recoveryMap(
                            preview.proof['bill'],
                          )['temp_reference'] ??
                          local!.uuid)
                      .toString(),
                  key: const ValueKey('draft-recovery-reference'),
                ),
                lines(
                  t(
                    'Already received from this device',
                    'تم الاستلام من هذا الجهاز',
                  ),
                  [
                    for (final ack in recoveryMaps(
                      preview.proof['acknowledged'],
                    ))
                      ...recoveryMaps(ack['lines']).map(recoveryPriced),
                  ],
                ),
                lines(
                  t('Saved unsent additions', 'إضافات محفوظة غير مرسلة'),
                  delta.map((slice) {
                    final line = recoveryLocalLine(
                      recoveryMap(slice['original']),
                    );
                    return {
                      ...line,
                      'qty': slice['qty'],
                      'line_total_baisas':
                          (line['unit_price_baisas'] as int) *
                          (slice['qty'] as int),
                    };
                  }).toList(),
                ),
              ],
              if (controller?.unresolved == true)
                Text(
                  t(
                    'Recovery is saved. Finish this request before payment or other table work. Uncertain replies keep the same request identity.',
                    'تم حفظ الاستعادة. أكمل هذا الطلب قبل الدفع أو تعديل الطاولة. تحتفظ المحاولات بنفس هوية الطلب.',
                  ),
                  key: const ValueKey('draft-recovery-pending'),
                ),
              if (attempt?.state == 'done' ||
                  attempt?.state == 'not_applied') ...[
                Text(
                  attempt!.state == 'done' &&
                          attempt.json['delta_ack'] != null &&
                          recoveryMap(
                                attempt.json['delta_ack'],
                              )['round_status'] !=
                              'accepted'
                      ? t(
                          'Saved additions sent for review. Continue on this bill in Dine-In.',
                          'أُرسلت الإضافات المحفوظة للمراجعة. تابع الفاتورة في داخل المطعم.',
                        )
                      : attempt.state == 'done'
                      ? t(
                          'Original draft archived. Continue on this bill in Dine-In. New accepted additions can use the bill’s kitchen-print action.',
                          'تمت أرشفة المسودة الأصلية. تابع الفاتورة في داخل المطعم. يمكن طباعة الإضافات الجديدة المقبولة من الفاتورة.',
                        )
                      : t(
                          'Recovery was not applied. The original local draft is unchanged.',
                          'لم يتم تنفيذ الاستعادة. المسودة المحلية الأصلية لم تتغير.',
                        ),
                  key: const ValueKey('draft-recovery-result'),
                ),
                FilledButton(onPressed: close, child: Text(t('Done', 'تم'))),
              ] else if (deltaState) ...[
                Text(
                  t(
                    'Only these saved additions will be sent. The server prices new items; received items are not sent again.',
                    'ستُرسل هذه الإضافات المحفوظة فقط. يحدد الخادم أسعار الإضافات ولا تُرسل الأصناف المستلمة مجدداً.',
                  ),
                ),
                FilledButton(
                  key: const ValueKey('draft-recovery-send'),
                  onPressed: controller!.busy || !controller.foreground
                      ? null
                      : () => unawaited(controller.sendSavedAdditions()),
                  child: Text(
                    attempt?.state == 'delta_pending'
                        ? t(
                            'Retry saved additions',
                            'إعادة محاولة الإضافات المحفوظة',
                          )
                        : t('Send saved additions', 'إرسال الإضافات المحفوظة'),
                  ),
                ),
              ] else if (preview != null)
                FilledButton(
                  key: const ValueKey('draft-recovery-confirm'),
                  onPressed: controller!.busy || !controller.foreground
                      ? null
                      : () => unawaited(controller.confirm()),
                  child: Text(
                    controller.unresolved
                        ? t(
                            'Retry saved recovery',
                            'إعادة محاولة الاستعادة المحفوظة',
                          )
                        : t('Confirm draft recovery', 'تأكيد استعادة المسودة'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
