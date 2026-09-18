import '../strings/softpos_strings.dart';
import '../services/local_storage_service.dart';
import '../services/mosambee_payment_service.dart';
import 'card_reversal_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
import '../data/order_sync_repository.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../models/remote_table_state.dart';
import '../models/table_sync_models.dart';
import '../widgets/table_reconciliation_sheet.dart';
import '../services/settings_service.dart';
import 'audience_spike_screen.dart';

/// Device-local POS settings: a debug/profile server address and connection
/// test, plus operational preferences. Reachable before activation
/// (device-setup gear) and from the in-POS top-bar gear. Release builds retain
/// the debug code but do not render the Server section.
///
/// P-F1 — [showOperations] (true when opened from the POS) adds the
/// operational actions that used to live on the logout sheet: close shift,
/// log expense, request restock, stock count, reprint shift summary. Tapping
/// one POPS this screen with its action key — the POS screen dispatches it so
/// the flows keep their controller/session context. Pre-activation (device
/// setup) there is no staff session, so the section stays hidden.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.showOperations = false});

  final bool showOperations;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _testing = false;
  bool _retryingAttention = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(settingsControllerProvider).serverBaseUrl ?? '',
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String get _candidateUrl =>
      SettingsService.normalizeBaseUrl(_urlController.text) ??
      ApiConfig.baseUrl;

  Future<void> _showCardTerminal() async {
    final profile = await LocalStorageService.getSoftposProfile();
    final terminalId = await LocalStorageService.getTerminalId();
    final terminalPin = await LocalStorageService.getTerminalPin();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(softposText(context, 'terminal')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: SoftposTerminalPanel(
              profile: profile,
              reason: profile.unavailableReason(
                terminalId: terminalId,
                terminalPin: terminalPin,
              ),
              check: MosambeePaymentService().checkTerminal,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    await ref
        .read(settingsControllerProvider.notifier)
        .setServerBaseUrl(_urlController.text);
    if (!mounted) return;
    // Reflect the normalized value back into the field.
    final saved = ref.read(settingsControllerProvider).serverBaseUrl ?? '';
    _urlController.text = saved;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.of(context).settingsSaved)));
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await ref.read(apiServiceProvider).pingBaseUrl(_candidateUrl);
    if (!mounted) return;
    final l10n = L10n.of(context);
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok
          ? l10n.settingsServerReachable(_candidateUrl)
          : l10n.settingsServerUnreachable(_candidateUrl);
    });
  }

  Future<void> _showSyncAttention(List<OrderSyncAttention> items) async {
    final l10n = L10n.of(context);
    final retry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final material = MaterialLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(_attentionTitle(l10n, items)),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items) ...[
                    Builder(
                      builder: (context) {
                        final row = item.row;
                        final awaitingGps =
                            item.reason == OrderSyncAttentionReason.awaitingGps;
                        final created = row.createdAt.toLocal();
                        final orderNumber = row.orderNumber ?? 0;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            awaitingGps
                                ? Icons.location_off_rounded
                                : Icons.error_rounded,
                            color: awaitingGps
                                ? const Color(0xFFD97706)
                                : const Color(0xFFDC2626),
                          ),
                          title: Text(
                            orderNumber > 0
                                ? l10n.posStorageOrderNumber(orderNumber)
                                : l10n.posPaymentOrderRef(row.orderUuid),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${material.formatMediumDate(created)} · '
                                '${TimeOfDay.fromDateTime(created).format(context)}',
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                awaitingGps
                                    ? l10n.settingsGpsHeldStatus
                                    : row.lastError?.trim().isNotEmpty == true
                                    ? row.lastError!.trim()
                                    : l10n.settingsUnknownSyncError,
                                style: TextStyle(
                                  color: awaitingGps
                                      ? const Color(0xFF9A6700)
                                      : const Color(0xFFB3261E),
                                  fontSize: 12,
                                ),
                              ),
                              if (orderNumber > 0) ...[
                                const SizedBox(height: 3),
                                Text(
                                  l10n.posPaymentOrderRef(row.orderUuid),
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(),
                  ],
                  Text(
                    _attentionDialogBody(l10n, items),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonClose),
            ),
            FilledButton.icon(
              key: const ValueKey('settings-stuck-sales-retry-all'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.settingsRetryAll),
            ),
          ],
        );
      },
    );

    if (retry != true || !mounted) return;
    setState(() => _retryingAttention = true);
    try {
      await ref.read(orderSyncRepositoryProvider).retryAttention();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _gpsHoldCount(items) > 0
                ? l10n.settingsAttentionRetryStarted
                : l10n.settingsRetryStarted,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsRetryFailed)));
    } finally {
      if (mounted) setState(() => _retryingAttention = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final releaseBuild = ref.watch(releaseBuildProvider);
    final attentionItems =
        ref.watch(orderSyncAttentionProvider).asData?.value ??
        const <OrderSyncAttention>[];
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: Text(l10n.settingsTitle),
        actions: [
          if (widget.showOperations)
            TextButton.icon(
              onPressed: _showCardTerminal,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.credit_card),
              label: Text(softposText(context, 'terminal')),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.showOperations) ...[
                _sectionLabel(l10n.settingsSectionOperations),
                const SizedBox(height: 4),
                if (attentionItems.isNotEmpty) ...[
                  _syncAttentionTile(l10n, attentionItems),
                  const SizedBox(height: 8),
                ],
                _operationTile(
                  icon: Icons.point_of_sale_rounded,
                  title: l10n.posMenuCloseShift,
                  subtitle: l10n.posMenuCloseShiftSub,
                  action: 'close_shift',
                ),
                _operationTile(
                  icon: Icons.receipt_long_rounded,
                  title: l10n.posMenuLogExpense,
                  subtitle: l10n.posMenuLogExpenseSub,
                  action: 'log_expense',
                ),
                _operationTile(
                  icon: Icons.inventory_2_rounded,
                  title: l10n.posMenuRequestRestock,
                  subtitle: l10n.posMenuRequestRestockSub,
                  action: 'restock_request',
                ),
                _operationTile(
                  icon: Icons.checklist_rounded,
                  title: l10n.posMenuStockCount,
                  subtitle: l10n.posMenuStockCountSub,
                  action: 'stock_count',
                ),
                _operationTile(
                  icon: Icons.delete_sweep_rounded,
                  title: l10n.posMenuWasteProduct,
                  subtitle: l10n.posMenuWasteProductSub,
                  action: 'waste_product',
                ),
                _operationTile(
                  icon: Icons.summarize_rounded,
                  title: l10n.posMenuShiftSummary,
                  subtitle: l10n.posMenuShiftSummarySub,
                  action: 'shift_summary',
                ),
                const Divider(color: Colors.white12, height: 36),
              ],
              if (widget.showOperations) ...[
                const _TableSoakSection(),
                const TableReconciliationSettingsSection(),
                const Divider(color: Colors.white12, height: 36),
              ],
              if (!releaseBuild) ...[
                _sectionLabel(l10n.settingsSectionServer),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('settings-server-address'),
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: _fieldDecoration(
                    label: l10n.settingsServerAddress,
                    hint: l10n.settingsServerHint,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  settings.usingDefaultServer
                      ? l10n.settingsUsingDefault(ApiConfig.baseUrl)
                      : l10n.settingsActive(settings.effectiveBaseUrl),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: Text(l10n.settingsTestConnection),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(l10n.commonSave),
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testOk
                          ? const Color(0xFF35C28B)
                          : const Color(0xFFFF6B6B),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                TextButton(
                  onPressed: settings.usingDefaultServer
                      ? null
                      : () async {
                          await ref
                              .read(settingsControllerProvider.notifier)
                              .setServerBaseUrl(null);
                          if (mounted) _urlController.text = '';
                        },
                  child: Text(
                    l10n.settingsResetDefault,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                const Divider(color: Colors.white12, height: 36),
              ],
              _sectionLabel(l10n.settingsSectionReceipts),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.printReceipts,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setPrintReceipts(v),
                title: Text(
                  l10n.settingsPrintReceipts,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  l10n.settingsPrintReceiptsHint,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.printKitchenTickets,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setPrintKitchenTickets(v),
                title: Text(
                  l10n.settingsPrintKitchenTickets,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  l10n.settingsPrintKitchenTicketsHint,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('settings-print-qr-kitchen-rounds'),
                contentPadding: EdgeInsets.zero,
                value: settings.printQrKitchenRounds,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setPrintQrKitchenRounds(v),
                title: Text(
                  l10n.settingsPrintQrKitchenRounds,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  l10n.settingsPrintQrKitchenRoundsHint,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
              ListTile(
                key: const ValueKey('settings-unified-dine-in'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  settings.language == 'ar'
                      ? 'طلبات الطاولات داخل المطعم'
                      : 'Table orders are in Dine-In',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Divider(color: Colors.white12, height: 36),
              // Phase 1A — anonymous on-device audience measurement (camera).
              _sectionLabel('Audience measurement'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.audienceMeasurement,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setAudienceMeasurement(v),
                title: const Text(
                  'Count viewers on the customer screen',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Anonymous on-device face counting while ads play. No images are stored — counts only.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const Divider(color: Colors.white12, height: 36),
              // Phase C4 (§9.8) — the language toggle (also a Phase 9 #92
              // deliverable: "Settings: language toggle, …").
              _sectionLabel(l10n.settingsSectionLanguage),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
                  ButtonSegment(value: 'ar', label: Text(l10n.languageArabic)),
                ],
                selected: {settings.language},
                onSelectionChanged: (selection) => ref
                    .read(settingsControllerProvider.notifier)
                    .setLanguage(selection.first),
                style: SegmentedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  selectedForegroundColor: Colors.white,
                  selectedBackgroundColor: const Color(0xFF35C28B),
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.settingsLanguageHint,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const Divider(color: Colors.white12, height: 36),
              // FEASIBILITY SPIKE — anonymous on-device audience counting on the
              // customer screen. Debug entry only; not wired to any backend yet.
              _sectionLabel('Audience (experimental)'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.groups_2_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Audience camera spike',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Live face count from the customer-facing camera (debug)',
                  style: TextStyle(color: Colors.white54),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AudienceSpikeScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _operationTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Colors.white70),
    title: Text(title, style: const TextStyle(color: Colors.white)),
    subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
    onTap: () => Navigator.of(context).pop(action),
  );

  int _gpsHoldCount(List<OrderSyncAttention> items) => items
      .where((item) => item.reason == OrderSyncAttentionReason.awaitingGps)
      .length;

  String _attentionTitle(L10n l10n, List<OrderSyncAttention> items) {
    final gpsCount = _gpsHoldCount(items);
    if (gpsCount == items.length) {
      return l10n.settingsGpsHeldSalesCount(items.length);
    }
    if (gpsCount == 0) return l10n.settingsStuckSalesCount(items.length);
    return l10n.settingsAttentionSalesCount(items.length);
  }

  String _attentionSubtitle(L10n l10n, List<OrderSyncAttention> items) {
    final gpsCount = _gpsHoldCount(items);
    if (gpsCount == items.length) return l10n.settingsGpsHeldSalesSubtitle;
    if (gpsCount == 0) return l10n.settingsStuckSalesSubtitle;
    return l10n.settingsAttentionSalesSubtitle;
  }

  String _attentionDialogBody(L10n l10n, List<OrderSyncAttention> items) {
    final gpsCount = _gpsHoldCount(items);
    if (gpsCount == items.length) return l10n.settingsGpsHeldSalesDialogBody;
    if (gpsCount == 0) return l10n.settingsStuckSalesDialogBody;
    return l10n.settingsAttentionSalesDialogBody;
  }

  Widget _syncAttentionTile(L10n l10n, List<OrderSyncAttention> items) {
    final gpsOnly = _gpsHoldCount(items) == items.length;
    final accent = gpsOnly ? const Color(0xFFFBBF24) : const Color(0xFFFF6B6B);
    return Material(
      key: const ValueKey('settings-stuck-sales-tile'),
      color: gpsOnly ? const Color(0xFF3A2B0A) : const Color(0xFF3A171B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: gpsOnly ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Icon(
          gpsOnly ? Icons.location_off_rounded : Icons.error_rounded,
          color: accent,
        ),
        title: Text(
          _attentionTitle(l10n, items),
          style: TextStyle(color: accent, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          _attentionSubtitle(l10n, items),
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: _retryingAttention
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.chevron_right, color: accent),
        onTap: _retryingAttention ? null : () => _showSyncAttention(items),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Colors.white38,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
    ),
  );

  InputDecoration _fieldDecoration({required String label, String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF16313B),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF35C28B)),
        ),
      );
}

/// Opening history reads the local verdict ledger only, in every mode. It
/// neither starts polling nor acknowledges rows that the cashier has not seen.
class TableReconciliationSettingsSection extends ConsumerStatefulWidget {
  const TableReconciliationSettingsSection({super.key});
  @override
  ConsumerState<TableReconciliationSettingsSection> createState() =>
      _TableReconciliationSettingsSectionState();
}

class _TableReconciliationSettingsSectionState
    extends ConsumerState<TableReconciliationSettingsSection> {
  Future<List<TableSyncVerdict>>? _rows;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ExpansionTile(
      key: const ValueKey('table-reconciliation-settings'),
      title: Text(l10n.tableReconciledSettings),
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: EdgeInsets.zero,
      onExpansionChanged: (expanded) {
        if (expanded) {
          setState(() {
            _rows = ref
                .read(tableLedgerStoreProvider)
                .readTableSyncVerdicts(limit: 200);
          });
        }
      },
      children: [
        Text(l10n.tableReconciledHistory),
        SizedBox(
          height: 280,
          child: FutureBuilder<List<TableSyncVerdict>>(
            future: _rows,
            builder: (context, value) {
              if (value.hasError) {
                return Center(child: Text(l10n.tableHistoryUnavailable));
              }
              if (value.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return TableReconciliationHistoryPanel(
                rows: value.data ?? const [],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TableSoakSection extends ConsumerStatefulWidget {
  const _TableSoakSection();
  @override
  ConsumerState<_TableSoakSection> createState() => _TableSoakSectionState();
}

class _TableSoakSectionState extends ConsumerState<_TableSoakSection> {
  late Future<(RemoteSyncMeta, List<Map<String, Object?>>)> _loaded;

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  Future<(RemoteSyncMeta, List<Map<String, Object?>>)> _load() async {
    final storedScope = ref
        .read(sharedPreferencesProvider)
        .getString('table_shadow_scope');
    if (storedScope == null) {
      return (const RemoteSyncMeta(), <Map<String, Object?>>[]);
    }
    final session = ref.read(sessionServiceProvider);
    final base = ref.read(settingsServiceProvider).effectiveBaseUrl;
    final scope =
        '$base|${session.companyId}|${session.branchId}|${session.kioskId}';
    if (storedScope != scope) {
      return (const RemoteSyncMeta(), <Map<String, Object?>>[]);
    }
    try {
      final store = ref.read(remoteTableStoreProvider);
      return (
        await store.readRemoteMeta(),
        await store.readRemoteDisagreements(),
      );
    } catch (_) {
      return (
        const RemoteSyncMeta(
          lastError: 'shadow_unavailable',
          consecutiveFailures: 1,
        ),
        <Map<String, Object?>>[],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(tableSessionsModeProvider);
    if (mode != 'off') {
      ref.listen(remoteBoardProvider, (_, _) {
        if (mounted) {
          setState(() {
            _loaded = _load();
          });
        }
      });
    }
    return FutureBuilder<(RemoteSyncMeta, List<Map<String, Object?>>)>(
      future: _loaded,
      builder: (context, value) => TableSoakPanel(
        mode: mode,
        meta: value.data?.$1 ?? const RemoteSyncMeta(),
        rows: value.data?.$2 ?? const [],
      ),
    );
  }
}

class TableSoakPanel extends StatelessWidget {
  const TableSoakPanel({
    super.key,
    required this.mode,
    required this.meta,
    required this.rows,
  });
  final String mode;
  final RemoteSyncMeta meta;
  final List<Map<String, Object?>> rows;

  String _status(Object? value, BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return switch (value) {
      'available' || 'free' => ar ? 'متاحة' : 'Free',
      'occupied' || 'open' || 'active' => ar ? 'مشغولة' : 'Occupied',
      'billing' ||
      'awaiting_payment' => ar ? 'بانتظار الدفع' : 'Awaiting payment',
      'paid' => ar ? 'مدفوعة' : 'Paid',
      'closed' => ar ? 'مغلقة' : 'Closed',
      _ => ar ? 'غير معروف' : 'Unknown',
    };
  }

  static const _columns = [
    'observed_at',
    'table_id',
    'local_status',
    'server_status',
    'server_origin',
    'server_reference',
    'local_reference',
    'kind',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final visible = rows.take(200).toList(growable: false);
    final modeLabel = switch (mode) {
      'shadow' => l10n.tableModeShadow,
      'live' => l10n.tableModeLive,
      _ => l10n.tableModeOff,
    };
    final details = [
      l10n.tableSoakMode(modeLabel),
      l10n.tableSoakCursor(meta.feedCursor?.toString() ?? '—'),
      l10n.tableSoakLastSuccess(meta.lastFeedOkAt?.toIso8601String() ?? '—'),
      l10n.tableSoakFailures(meta.consecutiveFailures),
      if (meta.lastError != null) l10n.tableSoakError(meta.lastError!),
    ];
    final lines = [
      for (final row in visible)
        _columns.map((key) => row[key]?.toString() ?? '').join('\t'),
    ];
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.white70, fontSize: 12),
      child: Column(
        key: const ValueKey('table-soak-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tableSoakTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final detail in details) Text(detail),
          TextButton.icon(
            key: const ValueKey('table-soak-copy'),
            icon: const Icon(Icons.copy),
            label: Text(l10n.tableSoakCopy),
            onPressed: () => Clipboard.setData(
              ClipboardData(
                text: [
                  l10n.tableSoakTitle,
                  ...details,
                  _columns.join('\t'),
                  ...lines,
                ].join('\n'),
              ),
            ),
          ),
          if (visible.isEmpty)
            Text(l10n.tableSoakEmpty)
          else
            SizedBox(
              height: 220,
              child: ListView.builder(
                key: const ValueKey('table-soak-rows'),
                itemCount: visible.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    '${Localizations.localeOf(context).languageCode == 'ar' ? 'الطاولة' : 'Table'} ${visible[index]['table_id']} · '
                    '${Localizations.localeOf(context).languageCode == 'ar' ? 'محلي' : 'Local'}: ${_status(visible[index]['local_status'], context)} · '
                    '${Localizations.localeOf(context).languageCode == 'ar' ? 'الخادم' : 'Server'}: ${_status(visible[index]['server_status'], context)}',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
