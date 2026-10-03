import 'package:flutter/material.dart';
import '../order_workspace/current_order_workspace.dart';
import '../services/local_order_storage_service.dart';
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
import 'workspace_void.dart';
import '../order_workspace/workspace_void.dart'
    show assertWorkspaceVoidJournals;
import '../qr_checkout/payment_review_store.dart';
import '../qr_checkout/qr_checkout_store.dart';
import '../services/qr_settlement_coordinator.dart' show GeolocatorQrLocation;

List<QuickProduct> machineQuickCatalogue(CatalogSnapshot? catalog) {
  if (catalog == null) return [];
  final groups = {for (final group in catalog.addonGroups) group.id: group};
  List<int> ids(Product p) => <int>{
    ...p.addonGroupIds,
    ...?catalog.categoryAddonGroupIds[p.categoryId],
  }.toList();
  // LAUNCH-P2 "sell, but warn": only explicit rules make a product
  // unavailable here (its daily window, an unknown add-on group); cached
  // stock never does.
  return [
    for (final p in catalog.products)
      // LAUNCH-P4 C5 — quick QR is an in-store order type.
      if (int.tryParse(p.id) != null && int.parse(p.id) > 0 && p.soldInStore)
        QuickProduct(
          int.parse(p.id),
          p.name,
          nameAr: p.nameAr,
          priceBaisas: (p.price * 1000).round(),
          // LAUNCH-P4 C6 — sold out is unavailable; C7 — this server-priced
          // picker cannot build a combo's choices yet, so combos are sold
          // through the till cart (and QR web) instead.
          available:
              p.isAvailableAt(DateTime.now()) &&
              !p.soldOut &&
              !p.isCombo &&
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
                        priceBaisas: (o.priceDelta * 1000).round(),
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
  const QrQuickOrdersScreen({
    super.key,
    this.openCheckout,
    this.onOpen,
    this.workspace,
    this.workspaceUuid,
  });
  final Future<void> Function(String?)? openCheckout;
  final Future<void> Function(String)? onOpen;
  final CurrentOrderWorkspace? workspace;
  final String? workspaceUuid;
  @override
  Widget build(BuildContext context, WidgetRef ref) => QrQuickScreen(
    onOpen: onOpen,
    workspace: workspace,
    workspaceUuid: workspaceUuid,
    onVoid: (uuid) => openMachineWorkspaceVoid(context, ref, uuid),
    arabic: Localizations.localeOf(context).languageCode == 'ar',
    createController: () async {
      final api = ref.read(apiServiceProvider);
      final session = ref.read(sessionServiceProvider);
      String scope() => quickDeviceScope(
        api.quickOrderBaseUrl,
        session.companyId,
        session.branchId,
        session.kioskId,
      );
      final gateway = ApiQrQuickGateway(
        api,
        scope,
        cancellationGuard: (uuid) async {
          if (ref
                  .read(qrSettlementCoordinatorProvider)
                  .pendingManagerRecoveries
                  .isNotEmpty ||
              await ref
                  .read(orderSyncRepositoryProvider)
                  .hasUnresolvedStandaloneQrPay(uuid)) {
            throw StateError('Payment evidence requires reconciliation');
          }
          await assertWorkspaceVoidJournals(
            quickDeviceScope(
              api.quickOrderBaseUrl,
              session.companyId,
              session.branchId,
              session.kioskId,
            ),
            uuid,
          );
        },
        mutationGuard: () =>
            (debugOrderStorageOverride ?? LocalOrderStorageService.instance)
                .assertNoPendingCombine(),
        localPaymentOrders: () async {
          final at = scope();
          return ordersWithUnreviewedPayments(
            (await SqliteCheckoutStore.open(at)).db,
            at,
          );
        },
        loadPaymentEvidence: (uuid) async {
          final at = scope();
          return loadPaymentReviewEvidence(
            (await SqliteCheckoutStore.open(at)).db,
            at,
            uuid,
            sending: await ref
                .read(orderSyncRepositoryProvider)
                .hasUnresolvedStandaloneQrPay(uuid),
          );
        },
        recordPaymentReview: (uuid, evidence, requestId, result) async {
          final at = scope();
          await recordPaymentReview(
            (await SqliteCheckoutStore.open(at)).db,
            at,
            uuid,
            evidence,
            requestId,
            result,
          );
        },
        currentGps: () async {
          final fix = await const GeolocatorQrLocation().currentFix();
          return fix == null ? null : {'lat': fix.lat, 'lng': fix.lng};
        },
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
