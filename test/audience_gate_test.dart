import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/services/session_service.dart';

/// Marketing #46 — the server-driven audience-measurement consent is
/// TRI-STATE on the device: true/false = the admin stated a policy (it
/// supersedes the local Settings toggle), null = older server, local toggle
/// stays in charge. The persistence must round-trip all three.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SessionService> session() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionService(const FlutterSecureStorage(), prefs);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to null — no server policy stated', () async {
    final s = await session();
    expect(s.serverAudienceMeasurement, isNull);
  });

  test('round-trips an explicit ON and OFF', () async {
    final s = await session();
    await s.saveServerAudienceMeasurement(true);
    expect(s.serverAudienceMeasurement, isTrue);
    await s.saveServerAudienceMeasurement(false);
    expect(s.serverAudienceMeasurement, isFalse);
  });

  test('an older server (null) clears the stored policy entirely', () async {
    final s = await session();
    await s.saveServerAudienceMeasurement(true);
    await s.saveServerAudienceMeasurement(null);
    // Back to "no policy" — NOT false: the local toggle regains control.
    expect(s.serverAudienceMeasurement, isNull);
  });
}
