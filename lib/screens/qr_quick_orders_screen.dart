import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/qr_pending_order.dart';
import '../models/pos_models.dart' show Product;
import '../providers/providers.dart';
import '../qr_quick/qr_quick_controller.dart';
import '../qr_quick/qr_quick_gateway.dart';
import '../qr_quick/qr_quick_models.dart';
import '../qr_quick/qr_quick_screen.dart';
import '../qr_quick/qr_quick_store.dart';
import '../services/config_mapper.dart';
import 'qr_pending_sheet.dart';

List<QuickProduct> machineQuickCatalogue(CatalogSnapshot? catalog) {
  if (catalog == null) return [];
  final groups = {for (final group in catalog.addonGroups) group.id: group};
  List<int> ids(Product p) => <int>{
    ...p.addonGroupIds,
    ...?catalog.categoryAddonGroupIds[p.categoryId],
  }.toList();
  bool inStock(Product p) => switch (p.stockMode) {
    'unit' => p.branchStockQty == null || p.branchStockQty! > 0,
    'cooked' => (p.branchStockQty ?? 0) > 0,
    'ingredient' => p.recipe.every(
      (line) =>
          (catalog.ingredientBalances[line.ingredientId] ?? 0) >= line.quantity,
    ),
    _ => true,
  };
  return [
    for (final p in catalog.products)
      if (int.tryParse(p.id) != null && int.parse(p.id) > 0)
        QuickProduct(
          int.parse(p.id),
          p.name,
          nameAr: p.nameAr,
          available:
              p.isAvailableAt(DateTime.now()) &&
              inStock(p) &&
              ids(p).every(groups.containsKey),
          groups: [
            for (final id in ids(p))
              if (groups[id] case final g?)
                QuickGroup(
                  g.name,
                  [
                    for (final o in g.options)
                      QuickChoice(
                        o.id,
                        o.label,
                        nameAr: o.labelAr ?? '',
                        selected: o.isDefault,
                      ),
                  ],
                  nameAr: g.nameAr ?? '',
                  min: g.minSelections ?? 0,
                  max: g.multiSelect
                      ? (g.maxSelections ?? g.options.length)
                      : 1,
                ),
          ],
        ),
  ];
}

class QrQuickOrdersScreen extends ConsumerWidget {
  const QrQuickOrdersScreen({super.key, this.openCheckout});
  final Future<void> Function(String?)? openCheckout;
  @override
  Widget build(BuildContext context, WidgetRef ref) => QrQuickScreen(
    arabic: Localizations.localeOf(context).languageCode == 'ar',
    createController: () async {
      final api = ref.read(apiServiceProvider);
      final session = ref.read(sessionServiceProvider);
      final gateway = ApiQrQuickGateway(
        api,
        () => quickDeviceScope(
          api.quickOrderBaseUrl,
          session.companyId,
          session.branchId,
          session.kioskId,
        ),
      );
      final store = await SqliteQrQuickStore.open(gateway.scope);
      return QrQuickController(gateway, store);
    },
    catalogue: () =>
        machineQuickCatalogue(ref.read(catalogProvider).asData?.value),
    onRecoverPayment: openCheckout == null ? null : () => openCheckout!(null),
    onPay: (context, order) => openCheckout != null
        ? openCheckout!(order.uuid)
        : Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            QrPendingSheet(order: QrPendingOrder.fromJson(order.json)),
      ),
    ),
  );
}
