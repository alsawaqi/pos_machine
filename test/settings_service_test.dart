import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/core/api_config.dart';
import 'package:pos_machine/services/settings_service.dart';

void main() {
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

    test('uses the override when set', () {
      const s = AppSettings(serverBaseUrl: 'http://x:8088/api/v1');
      expect(s.effectiveBaseUrl, 'http://x:8088/api/v1');
      expect(s.usingDefaultServer, isFalse);
    });
  });
}
