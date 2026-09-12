import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../order_workspace/workspace_void.dart';
import '../providers/providers.dart';
import '../qr_quick/qr_quick_gateway.dart';
import '../services/local_order_storage_service.dart';

Future<bool> openMachineWorkspaceVoid(
  BuildContext context,
  WidgetRef ref,
  String uuid,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    final session = ref.read(sessionServiceProvider);
    String scope() => quickDeviceScope(
      api.quickOrderBaseUrl,
      session.companyId,
      session.branchId,
      session.kioskId,
    );
    final gateway = ApiWorkspaceVoidGateway(api, scope, (orderUuid) async {
      await (debugOrderStorageOverride ?? LocalOrderStorageService.instance)
          .assertNoPendingCombine();
      if (ref
              .read(qrSettlementCoordinatorProvider)
              .pendingManagerRecoveries
              .isNotEmpty ||
          await ref
              .read(orderSyncRepositoryProvider)
              .hasUnresolvedStandaloneQrPay(orderUuid)) {
        throw StateError('Earlier payment needs reconciliation');
      }
      await assertWorkspaceVoidJournals(scope(), orderUuid);
    });
    return await showWorkspaceVoid(
      context,
      gateway,
      uuid,
      arabic: ref.read(settingsControllerProvider).language == 'ar',
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            workspaceVoidError(
              error,
              Localizations.localeOf(context).languageCode == 'ar',
            ),
          ),
        ),
      );
    }
    return false;
  }
}
