import 'package:flutter/material.dart';
import 'business_identity.dart';

/// Above the navigator: dialogs and pushed payment routes cannot cover a block.
class TenancyGate extends StatelessWidget {
  const TenancyGate({super.key, required this.child, required this.activation});
  final Widget child;
  final Widget Function(BuildContext) activation;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: BusinessBoundary.blocked,
    builder: (context, reason, _) => reason == null
        ? child
        : _BlockedScreen(
            suspended: reason == 'company_suspended',
            activation: activation,
          ),
  );
}

class _BlockedScreen extends StatefulWidget {
  const _BlockedScreen({required this.suspended, required this.activation});
  final bool suspended;
  final Widget Function(BuildContext) activation;
  @override
  State<_BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<_BlockedScreen> {
  bool activating = false;
  @override
  Widget build(BuildContext context) {
    if (activating && !widget.suspended)
      return Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(builder: widget.activation),
      );
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    widget.suspended
                        ? (ar ? 'الحساب موقوف' : 'Account suspended')
                        : (ar
                              ? 'يحتاج هذا الجهاز إلى التفعيل'
                              : 'This device needs activation'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  if (!widget.suspended)
                    FilledButton(
                      onPressed: () => setState(() => activating = true),
                      child: Text(ar ? 'تفعيل الجهاز' : 'Activate device'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
