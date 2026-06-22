/// Static configuration for reaching pos_api.
///
/// Default targets the Android emulator, which reaches the host machine at
/// 10.0.2.2 (the pos_api container is published on host port 8088).
///
/// Override at run/build time for a real device on the LAN:
///   flutter run --dart-define=POS_API_BASE_URL=http://192.168.1.50:8088/api/v1
class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'POS_API_BASE_URL',
    defaultValue: 'https://posapi.mithqal.net/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
