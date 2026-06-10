import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
import '../l10n/l10n.dart';
import '../providers/providers.dart';
import '../services/settings_service.dart';

/// Device-local POS settings: the server address (so a real device can be
/// pointed at the right backend without a rebuild), a connection test, and the
/// receipt-printing toggle. Reachable before activation (device-setup gear) and
/// from the in-POS staff menu.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _testing = false;
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
      SettingsService.normalizeBaseUrl(_urlController.text) ?? ApiConfig.baseUrl;

  Future<void> _save() async {
    await ref
        .read(settingsControllerProvider.notifier)
        .setServerBaseUrl(_urlController.text);
    if (!mounted) return;
    // Reflect the normalized value back into the field.
    final saved = ref.read(settingsControllerProvider).serverBaseUrl ?? '';
    _urlController.text = saved;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.of(context).settingsSaved)),
    );
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: Text(l10n.settingsTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _sectionLabel(l10n.settingsSectionServer),
              const SizedBox(height: 8),
              TextField(
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
              const Divider(color: Colors.white12, height: 36),
              // Phase C4 (§9.8) — the language toggle (also a Phase 9 #92
              // deliverable: "Settings: language toggle, …").
              _sectionLabel(l10n.settingsSectionLanguage),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'en',
                    label: Text(l10n.languageEnglish),
                  ),
                  ButtonSegment(
                    value: 'ar',
                    label: Text(l10n.languageArabic),
                  ),
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
            ],
          ),
        ),
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
