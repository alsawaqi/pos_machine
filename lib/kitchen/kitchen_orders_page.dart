import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mithqal_kitchen_android/mithqal_kitchen_android.dart';
import '../providers/providers.dart';

class KitchenOrdersPage extends ConsumerWidget {
  const KitchenOrdersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Settings sync may replace the controller while this route stays open.
    final controller = ref.watch(kitchenPosProvider);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(arabic ? 'طلبات المطبخ' : 'Kitchen orders')),
        body: Center(
          child: Text(
            arabic
                ? 'سجّل الدخول لفتح طلبات المطبخ.'
                : 'Sign in to open kitchen orders.',
          ),
        ),
      );
    }
    return KitchenPosScreen(
      key: ObjectKey(controller),
      controller: controller,
      arabic: arabic,
    );
  }
}
