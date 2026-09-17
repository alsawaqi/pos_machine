import 'dart:async';
import 'package:flutter/material.dart';
import 'order_attention.dart';

/// Above the staff navigator: stays visible on catalog, quick, table and pay
/// routes. A separate bar reserves its own space and never overlays a tender.
class OrderAttentionHost extends StatefulWidget {
  const OrderAttentionHost({
    super.key,
    required this.child,
    required this.createController,
    this.signal,
    this.showBanner = true,
  });
  final Widget child;
  final bool showBanner;
  final OrderAttentionController Function() createController;
  final Listenable? signal;

  @override
  State<OrderAttentionHost> createState() => _OrderAttentionHostState();
}

class _OrderAttentionHostState extends State<OrderAttentionHost>
    with WidgetsBindingObserver {
  late final OrderAttentionController controller;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    controller = widget.createController();
    WidgetsBinding.instance.addObserver(this);
    widget.signal?.addListener(_changed);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      controller.setActive(false);
    } else {
      _start();
    }
  }

  void _changed() {
    // Session/navigation changes can occur during a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.contextChanged();
    });
  }

  void _start() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(controller.refresh());
    });
    unawaited(controller.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    controller.setActive(foreground);
    if (foreground) {
      _start();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.signal?.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) {
      if (!widget.showBanner) return child!;
      final snap = controller.snapshot;
      final quick = snap?.quick.length ?? 0;
      final rounds = snap?.rounds.length ?? 0;
      final problem =
          controller.stale ||
          controller.storageFailed ||
          controller.soundUnavailable;
      final visible = quick + rounds > 0 || problem;
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      final summary = ar
          ? 'بانتظار الموظف: طلبات QR السريعة $quick · جولات الطاولات $rounds'
          : 'Staff attention: QR quick $quick · Table rounds $rounds';
      final warning = controller.stale
          ? (ar
                ? 'تعذر تحديث التنبيهات — تحقق من الاتصال'
                : 'Alerts not updating — check connection')
          : controller.storageFailed
          ? (ar
                ? 'تعذر حفظ التنبيهات — الصوت متوقف'
                : 'Alert storage unavailable — sound paused')
          : controller.soundUnavailable
          ? (ar
                ? 'الصوت غير متاح — تحقق من مستوى الصوت'
                : 'Sound unavailable — check device volume')
          : '';
      return Column(
        // Paint the navigator first, otherwise its route BlockSemantics hides
        // the notification button from accessibility. Layout still puts the
        // reserved notification bar above the navigator.
        verticalDirection: VerticalDirection.up,
        children: [
          Expanded(child: child!),
          if (!visible)
            const SizedBox.shrink()
          else
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: SafeArea(
                bottom: false,
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 4,
                    ),
                    child: Row(
                      key: const ValueKey('order-attention-bar'),
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            [
                              if (controller.newArrivals > 0)
                                ar ? 'طلب جديد' : 'New order',
                              summary,
                              if (warning.isNotEmpty) warning,
                            ].join('\n'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Semantics(
                          container: true,
                          label: ar
                              ? 'اختبار صوت التنبيه'
                              : 'Test notification sound',
                          child: IconButton(
                            key: const ValueKey('order-attention-test-sound'),
                            onPressed: controller.testSound,
                            icon: const Icon(
                              Icons.volume_up_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
