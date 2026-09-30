import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/merchant_caches.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'identity change removes merchant images and merchant crash context',
    () async {
      BusinessBoundary.resetForTest();
      SharedPreferences.setMockInitialValues({
        BusinessBoundary.identityKey: const BusinessIdentity(1, 2, 'd').encoded,
      });
      await BusinessBoundary.initialize(await SharedPreferences.getInstance());
      await Sentry.init((options) {
        options.dsn = 'https://test@example.invalid/1';
        options.transport = _NoTransport();
      });
      await Sentry.configureScope((scope) async {
        for (final key in [
          'company_id',
          'branch_id',
          'terminal_id',
          'device_code',
          'kiosk_id',
        ])
          await scope.setTag(key, 'old');
        await scope.setTag('unrelated', 'keep');
        await scope.setUser(SentryUser(id: 'old-staff'));
      });
      final dir = await Directory.systemTemp.createTemp('fix1-image-cache-');
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(dir.path);
      await DefaultCacheManager().putFile(
        'merchant-logo',
        Uint8List.fromList([1, 2, 3]),
        key: 'merchant-logo',
      );
      expect(
        await DefaultCacheManager().getFileFromCache('merchant-logo'),
        isNotNull,
      );

      final pixels = Completer<ImageInfo>();
      PaintingBinding.instance.imageCache.putIfAbsent(
        'old-merchant-image',
        () => OneFrameImageStreamCompleter(pixels.future),
      );
      expect(PaintingBinding.instance.imageCache.pendingImageCount, 1);
      BusinessBoundary.registerWiper(wipeMerchantCaches);
      await BusinessBoundary.accept(const BusinessIdentity(3, 4, 'd'));
      expect(PaintingBinding.instance.imageCache.pendingImageCount, 0);
      expect(PaintingBinding.instance.imageCache.liveImageCount, 0);
      expect(
        await DefaultCacheManager().getFileFromCache('merchant-logo'),
        isNull,
      );
      await DefaultCacheManager().dispose();
      PathProviderPlatform.instance = paths;
      await dir.delete(recursive: true);
      await Sentry.configureScope((scope) async {
        for (final key in [
          'company_id',
          'branch_id',
          'terminal_id',
          'device_code',
          'kiosk_id',
        ])
          expect(scope.tags.containsKey(key), false);
        expect(scope.tags['unrelated'], 'keep');
        expect(scope.user, isNull);
      });
      await Sentry.close();
      BusinessBoundary.resetForTest();
    },
  );
}

class _NoTransport extends Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => SentryId.empty();
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
