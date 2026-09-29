import 'dart:async';
import 'package:dio/dio.dart';
import 'business_identity.dart';

class DeviceHeartbeat {
  static Timer? _timer;
  static bool _sending = false;
  static Future<int> Function()? pendingCount;
  static String? Function()? printerStatus;
  static void start(Dio client, String appVersion) {
    if (!BusinessBoundary.initialized) return;
    _timer?.cancel();
    Future<void> report() async {
      if (_sending || BusinessBoundary.current == null || pendingCount == null)
        return;
      _sending = true;
      final generation = BusinessBoundary.generation.value;
      try {
        final pending = await pendingCount!();
        BusinessBoundary.assertGeneration(generation);
        final response = await client.post<dynamic>(
          '/device/heartbeat',
          data: {
            'pending_outbox_count': pending,
            'quarantined_count': BusinessBoundary.quarantinedCount,
            'app_version': appVersion,
            if (printerStatus?.call() != null)
              'printer_status': printerStatus!(),
          },
        );
        if (response.statusCode == 200)
          await BusinessBoundary.confirmHeartbeat(generation);
      } catch (_) {
        // Never report zero after an unreadable store. Its last reliable report
        // becomes stale and the server blocks reassignment until resolved.
      } finally {
        _sending = false;
      }
    }

    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(report()),
    );
    unawaited(report());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
