/// LAUNCH-P1 (decision 2a) — where this device may sell: only at its
/// branch's location (`branch`, the default) or anywhere (`any`). Set by the
/// admin per device; delivered on activation and in `/device/config`.
enum DeviceLocationMode {
  branch('branch'),
  any('any');

  const DeviceLocationMode(this.wire);

  final String wire;

  /// Null when the server did not send a value (older server). Any other
  /// non-empty value fails closed to [branch].
  static DeviceLocationMode? fromWire(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    return value == 'any' ? any : branch;
  }

  /// Activation response `data`: the device section first.
  static DeviceLocationMode? fromActivation(Map<String, dynamic> data) =>
      fromWire(_device(data)?['location_mode'] ?? data['location_mode']);

  /// `/device/config` (full or delta): the device section of `data` or
  /// `meta`, then a flat `meta.location_mode` (where the per-device SoftPOS
  /// contract lives).
  static DeviceLocationMode? fromConfig(
    Map<String, dynamic> data,
    Map<String, dynamic> meta,
  ) =>
      fromWire(_device(data)?['location_mode']) ??
      fromWire(_device(meta)?['location_mode']) ??
      fromWire(meta['location_mode']) ??
      fromWire(data['location_mode']);

  static Map? _device(Map<String, dynamic> map) {
    final device = map['device'];
    return device is Map ? device : null;
  }
}
