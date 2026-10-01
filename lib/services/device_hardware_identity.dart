import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// LAUNCH-P1 (decision 1a) — what the physical device says about itself at
/// activation, so the server can lock an enrollment code to the device it was
/// made for. Values are trimmed only; the server normalises them.
@immutable
class DeviceHardwareIdentity {
  const DeviceHardwareIdentity({this.serial, this.manufacturer, this.model});

  /// The serial printed on the device sticker, or null when unreadable.
  final String? serial;
  final String? manufacturer;
  final String? model;

  static const unknown = DeviceHardwareIdentity();
}

/// Reads [DeviceHardwareIdentity] through the app's `mithqal/device_identity`
/// platform channel (MainActivity → DeviceIdentityBridge).
///
/// Never throws: a missing host (tests, web, an older APK), a vendor SDK that
/// refuses, a slow hardware init or a blank value all become null. The server
/// then decides — it refuses with `activation_serial_missing` when the serial
/// lock is enforced.
class DeviceHardwareIdentityReader {
  const DeviceHardwareIdentityReader({
    this.channel = defaultChannel,
    this.timeout = const Duration(seconds: 8),
  });

  static const defaultChannel = MethodChannel('mithqal/device_identity');

  final MethodChannel channel;

  /// The vendor SDK may power the secure module on first; never wait forever.
  final Duration timeout;

  /// The sticker serial, or null when it cannot be read.
  Future<String?> getHardwareSerial() async =>
      _clean(await _invoke<Object?>('getHardwareSerial'));

  Future<DeviceHardwareIdentity> read() async {
    final serial = await getHardwareSerial();
    final info = await _invoke<Object?>('getBuildInfo');
    final map = info is Map ? info : const {};
    return DeviceHardwareIdentity(
      serial: serial,
      manufacturer: _clean(map['manufacturer']),
      model: _clean(map['model']),
    );
  }

  Future<T?> _invoke<T>(String method) async {
    try {
      return await channel.invokeMethod<T>(method).timeout(timeout);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _clean(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
