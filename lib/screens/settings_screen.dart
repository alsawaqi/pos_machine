import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_config.dart';
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
      const SnackBar(content: Text('Settings saved.')),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await ref.read(apiServiceProvider).pingBaseUrl(_candidateUrl);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok
          ? 'Server reachable at $_candidateUrl'
          : 'Could not reach $_candidateUrl';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: const Text('Settings'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _sectionLabel('Server'),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _fieldDecoration(
                  label: 'Server address',
                  hint: 'e.g. 192.168.1.50:8088',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                settings.usingDefaultServer
                    ? 'Using the built-in default: ${ApiConfig.baseUrl}'
                    : 'Active: ${settings.effectiveBaseUrl}',
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
                      label: const Text('Test connection'),
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
                      child: const Text('Save'),
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
                child: const Text(
                  'Reset to default',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const Divider(color: Colors.white12, height: 36),
              _sectionLabel('Receipts'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.printReceipts,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setPrintReceipts(v),
                title: const Text(
                  'Print receipts',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Print a Sunmi receipt when an order completes.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.printKitchenTickets,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setPrintKitchenTickets(v),
                title: const Text(
                  'Print kitchen tickets',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Print an items-only kitchen ticket when an order completes or is held.',
                  style: TextStyle(color: Colors.white54),
                ),
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
