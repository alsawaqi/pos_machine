import 'package:flutter/painting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

Future<void> wipeMerchantCaches() async {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  await DefaultCacheManager().emptyCache();
  await Sentry.configureScope((scope) async {
    for (final tag in [
      'company_id',
      'branch_id',
      'terminal_id',
      'device_code',
      'kiosk_id',
    ]) {
      await scope.removeTag(tag);
    }
    await scope.setUser(null);
  });
}
