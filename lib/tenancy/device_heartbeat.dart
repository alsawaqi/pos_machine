import 'dart:async';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'business_identity.dart';

class DeviceHeartbeat {
  static Timer? _timer;
  static bool _sending = false;
  static Future<int?> Function()? pendingCount;
  static String? Function()? printerStatus;
  static final Set<Object> _tenders = {};
  static int get tendersInFlight => _tenders.length;
  static Future<T> trackTender<T>(Future<T> Function() action) async {
    final token = Object();
    _tenders.add(token);
    try {
      return await BusinessBoundary.trackPayment(action);
    } finally {
      _tenders.remove(token);
    }
  }

  static Future<Map<String, dynamic>> metadata() async {
    int? pending;
    try {
      pending = await pendingCount?.call();
    } catch (_) {
      /* Unknown, never zero. */
    }
    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version + '+' + info.buildNumber;
    } catch (_) {
      /* An unavailable platform build stays unknown. */
    }
    final printer = printerStatus?.call();
    return {
      if (pending != null) 'pending_outbox_count': pending + tendersInFlight,
      'quarantined_count': BusinessBoundary.quarantinedCount,
      if (version != null) 'app_version': version,
      if (printer != null) 'printer_status': printer,
    };
  }

  static Future<void> report(Dio client) async {
    if (_sending || BusinessBoundary.current == null) return;
    _sending = true;
    final generation = BusinessBoundary.generation.value;
    try {
      if (BusinessBoundary.current?.isProvisional == true) {
        final identity = await client.get<dynamic>('/device/identity');
        final data = identity.data is Map
            ? (identity.data as Map)['data']
            : null;
        if (data is Map) {
          final resolved = BusinessIdentity.parse({
            'company_id': data['company_id'],
            'branch_id': data['branch_id'],
            'device_uuid': data['uuid'],
          });
          if (resolved != null)
            await BusinessBoundary.completeIdentity(resolved, generation);
        }
      }
      final data = await metadata();
      BusinessBoundary.assertGeneration(generation);
      final response = await client.post<dynamic>(
        '/device/heartbeat',
        data: data,
      );
      if (response.statusCode == 200)
        await BusinessBoundary.confirmHeartbeat(generation);
    } catch (_) {
      // Refusals are handled by the credential-aware interceptor.
    } finally {
      _sending = false;
    }
  }

  static void start(Dio client) {
    if (!BusinessBoundary.initialized || pendingCount == null) return;
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(report(client)),
    );
    unawaited(report(client));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
