import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/core/api_config.dart';
import 'package:pos_machine/main.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService.normalizeBaseUrl', () {
    test('blank → null (fall back to default)', () {
      expect(SettingsService.normalizeBaseUrl(null), isNull);
      expect(SettingsService.normalizeBaseUrl(''), isNull);
      expect(SettingsService.normalizeBaseUrl('   '), isNull);
    });

    test('host:port → http scheme + /api/v1 suffix', () {
      expect(
        SettingsService.normalizeBaseUrl('192.168.1.50:8088'),
        'http://192.168.1.50:8088/api/v1',
      );
    });

    test('trailing slashes stripped before suffixing', () {
      expect(
        SettingsService.normalizeBaseUrl('http://10.0.0.5:8088///'),
        'http://10.0.0.5:8088/api/v1',
      );
    });

    test('an explicit /api/v1 is preserved (idempotent)', () {
      expect(
        SettingsService.normalizeBaseUrl('https://pos.example.com/api/v1'),
        'https://pos.example.com/api/v1',
      );
      expect(
        SettingsService.normalizeBaseUrl('https://pos.example.com/api/v2'),
        'https://pos.example.com/api/v2',
      );
    });

    test('https scheme is kept', () {
      expect(
        SettingsService.normalizeBaseUrl('https://pos.example.com'),
        'https://pos.example.com/api/v1',
      );
    });
  });

  group('AppSettings.effectiveBaseUrl', () {
    test('falls back to the compile-time default when unset', () {
      const s = AppSettings();
      expect(s.effectiveBaseUrl, ApiConfig.baseUrl);
      expect(s.usingDefaultServer, isTrue);
    });

    test('debug uses the override; release ignores and clears it', () async {
      const override = 'http://x:8088/api/v1';
      SharedPreferences.setMockInitialValues({
        'server_base_url': override,
        'websocket_config_json': '{"host":"old.example"}',
      });
      final preferences = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), preferences);
      final debug = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sessionServiceProvider.overrideWithValue(session),
          releaseBuildProvider.overrideWithValue(false),
        ],
      );
      final release = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          sessionServiceProvider.overrideWithValue(session),
          releaseBuildProvider.overrideWithValue(true),
        ],
      );
      addTearDown(debug.dispose);
      addTearDown(release.dispose);

      final debugSettings = debug.read(settingsServiceProvider).snapshot();
      expect(debugSettings.effectiveBaseUrl, override);
      expect(debugSettings.usingDefaultServer, isFalse);
      expect(debug.read(apiServiceProvider).baseUrlGetter!(), override);
      expect(
        debugSettings.copyWith(printReceipts: false).effectiveBaseUrl,
        override,
      );

      await applyServerAddressPolicyAtStartup(
        buildMode: debug,
        preferences: preferences,
        session: session,
      );
      expect(preferences.getString('server_base_url'), override);
      expect(preferences.containsKey('websocket_config_json'), isTrue);

      final releaseSettings = release.read(settingsServiceProvider).snapshot();
      expect(releaseSettings.effectiveBaseUrl, ApiConfig.baseUrl);
      expect(releaseSettings.usingDefaultServer, isTrue);
      expect(
        release.read(apiServiceProvider).baseUrlGetter!(),
        ApiConfig.baseUrl,
      );
      expect(
        releaseSettings.copyWith(printReceipts: false).effectiveBaseUrl,
        ApiConfig.baseUrl,
      );

      await applyServerAddressPolicyAtStartup(
        buildMode: release,
        preferences: preferences,
        session: session,
      );
      expect(preferences.containsKey('server_base_url'), isFalse);
      expect(preferences.containsKey('websocket_config_json'), isFalse);
      expect(
        release.read(settingsServiceProvider).effectiveBaseUrl,
        ApiConfig.baseUrl,
      );
    });
  });

  group('QR kitchen-round printing setting', () {
    test(
      'defaults OFF in both the value object and persisted snapshot',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();

        expect(const AppSettings().printQrKitchenRounds, isFalse);
        expect(
          SettingsService(preferences).snapshot().printQrKitchenRounds,
          isFalse,
        );
      },
    );

    test('persists opt-in and opt-out across service instances', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = SettingsService(preferences);

      await settings.savePrintQrKitchenRounds(true);
      expect(preferences.getBool('print_qr_kitchen_rounds'), isTrue);
      expect(
        SettingsService(preferences).snapshot().printQrKitchenRounds,
        isTrue,
      );

      await settings.savePrintQrKitchenRounds(false);
      expect(preferences.getBool('print_qr_kitchen_rounds'), isFalse);
      expect(
        SettingsService(preferences).snapshot().printQrKitchenRounds,
        isFalse,
      );
    });
  });
}
