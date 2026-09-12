import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'combine_controller.dart';
import 'combine_models.dart';

class CombineScreen extends StatefulWidget {
  const CombineScreen({
    super.key,
    required this.createController,
    this.arabic = false,
  });
  final Future<CombineController> Function() createController;
  final bool arabic;
  @override
  State<CombineScreen> createState() => _CombineScreenState();
}

class _CombineScreenState extends State<CombineScreen>
    with WidgetsBindingObserver {
  CombineController? c;
  final pin = TextEditingController();
  bool leaving = false;
  String? setupError;
  String t(String en, String ar) => widget.arabic ? ar : en;
  String money(Object? value) =>
      value is int ? 'OMR ${(value / 1000).toStringAsFixed(3)}' : '—';
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
      controller.setForeground(
        WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      controller.addListener(changed);
      await controller.start();
    } catch (e) {
      if (mounted) setState(() => setupError = e.toString());
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    c?.setForeground(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.resumed) pin.clear();
  }

  void close() {
    if (c?.canLeave != true && setupError == null) return;
    setState(() => leaving = true);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pin.dispose();
    c?.removeListener(changed);
    c?.dispose();
    super.dispose();
  }

  Widget bill(String title, Map<String, dynamic> value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Text(
            (value['receipt_number'] ??
                    value['temp_reference'] ??
                    value['uuid'])
                .toString(),
          ),
          for (final raw in value['items'] as List)
            Builder(
              builder: (_) {
                final line = combineMap(raw);
                return ListTile(
                  title: Text('${line['qty']} × ${line['name']}'),
                  subtitle: Text(
                    [
                          line['notes'] ?? '',
                          for (final a in line['addons'] as List)
                            combineMap(a)['name'],
                        ]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                  ),
                  trailing: Text(money(line['line_total_baisas'])),
                );
              },
            ),
          Text(
            '${t('Discount', 'الخصم')}: ${money(value['discount_total_baisas'])}',
          ),
          Text('${t('Tax', 'الضريبة')}: ${money(value['tax_total_baisas'])}'),
          Text(
            '${t('Total', 'الإجمالي')}: ${money(value['grand_total_baisas'])}',
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final controller = c, preview = c?.preview;
    final done = c?.attempt?.state == 'done',
        released = c?.attempt?.state == 'not_applied';
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) close();
      },
      child: Directionality(
        textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          key: const ValueKey('combine-review'),
          appBar: AppBar(
            title: Text(t('Review separate bills', 'مراجعة الفواتير المنفصلة')),
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
                  'Manager approval: combine only bills for the same party. Original prices and the QR reference stay. This does not send another kitchen ticket.',
                  'موافقة المدير: دمج فواتير المجموعة نفسها فقط. تبقى الأسعار الأصلية ومرجع QR. لن تُطبع تذكرة مطبخ جديدة.',
                ),
              ),
              if (setupError != null || controller?.error != null)
                Text(
                  setupError ?? controller!.error!,
                  key: const ValueKey('combine-error'),
                ),
              if (preview != null) ...[
                Text(preview.json['table_label'] as String),
                bill(
                  t('Original staff bill', 'فاتورة الموظف الأصلية'),
                  preview.source,
                ),
                bill(
                  t('QR bill to keep', 'فاتورة QR التي ستبقى'),
                  preview.target,
                ),
                Text(
                  '${t('Combined total', 'الإجمالي بعد الدمج')}: ${money(preview.json['combined_grand_total_baisas'])}',
                  key: const ValueKey('combine-total'),
                ),
              ],
              if (controller?.unresolved == true)
                Text(
                  t(
                    'This request is saved. Do not take payment on the old bill. Retry this request; do not create another. If it was never applied, the server can release it after the preview expires.',
                    'تم حفظ الطلب. لا تستلم دفعة للفاتورة القديمة. أعد المحاولة بنفس الطلب ولا تنشئ غيره. إذا لم يُنفذ، يمكن للخادم تحريره بعد انتهاء المعاينة.',
                  ),
                  key: const ValueKey('combine-pending'),
                ),
              if (done || released) ...[
                Text(
                  done
                      ? t(
                          'Combined. Original local copy archived; use the QR bill.',
                          'تم الدمج وأرشفة النسخة المحلية الأصلية. استخدم فاتورة QR.',
                        )
                      : t(
                          'Not combined. The original local bill is unchanged. Review again when ready.',
                          'لم يتم الدمج. الفاتورة المحلية الأصلية لم تتغير. راجعها مجدداً عندما تكون جاهزاً.',
                        ),
                  key: const ValueKey('combine-result'),
                ),
                FilledButton(onPressed: close, child: Text(t('Done', 'تم'))),
              ] else if (preview != null) ...[
                if (controller?.attempt?.state != 'confirmed')
                  TextField(
                    controller: pin,
                    key: const ValueKey('combine-pin'),
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: t('Manager PIN', 'الرقم السري للمدير'),
                    ),
                  ),
                FilledButton(
                  key: const ValueKey('combine-confirm'),
                  onPressed: controller!.busy || !controller.foreground
                      ? null
                      : () {
                          final value = pin.text;
                          pin.clear();
                          unawaited(controller.confirm(value));
                        },
                  child: Text(
                    controller.unresolved
                        ? t(
                            'Retry saved request / finish recovery',
                            'إعادة محاولة الطلب المحفوظ / إكمال الاستعادة',
                          )
                        : t('Approve and combine', 'موافقة ودمج'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
