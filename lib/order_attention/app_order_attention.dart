import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../qr_quick/qr_quick_gateway.dart';
import 'order_attention.dart';
import 'order_attention_host.dart';

class AppOrderAttention extends ConsumerWidget {
  const AppOrderAttention({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => OrderAttentionHost(
    signal: staffAttentionHosts,
    createController: () => OrderAttentionController(
      identity: () {
        if (staffAttentionHosts.value.isEmpty) return null;
        final session = ref.read(sessionServiceProvider);
        final token = session.deviceToken;
        final staff = session.staff;
        if (staff == null || token == null || token.isEmpty) return null;
        try {
          return AttentionIdentity(
            quickDeviceScope(
              ref.read(apiServiceProvider).quickOrderBaseUrl,
              session.companyId,
              session.branchId,
              session.kioskId,
            ),
            '$token|${staff.id}',
          );
        } catch (_) {
          return null;
        }
      },
      fetch: () => ref.read(apiServiceProvider).fetchOrderAttention(),
      ledger: PreferencesAttentionLedger(),
    ),
    child: child,
  );
}
