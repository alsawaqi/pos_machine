import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SessionService session;
  final settings = <String, dynamic>{
    'kitchen_v2': {
      'mode': 'active',
      'identity': {'company_id': 100, 'branch_id': 10, 'device_id': 1},
    },
    'position_permissions': {'manager': ['kitchen.submit']},
    'shift_end_reminder_at': '22:00',
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    session = SessionService(
      const FlutterSecureStorage(), await SharedPreferences.getInstance());
  });
  test('setup availability does not activate legacy order routing', () async {
    await session.saveStaffSettings({'kitchen_v2': {'mode': 'legacy', 'setup_enabled': true}});
    expect(session.kitchenV2SetupAvailable, isTrue);
    expect(session.kitchenV2Enabled, isFalse);
    await session.saveStaffSettings({'kitchen_v2': {'mode': 'legacy'}});
    expect(session.kitchenV2SetupAvailable, isFalse);
    await session.saveStaffSettings({'kitchen_v2': {'mode': 'pending'}});
    expect(session.kitchenV2SetupAvailable, isTrue);
    expect(session.kitchenV2Enabled, isTrue);
  });
  test('identical config polling does not recreate kitchen session', () async {
    await session.saveStaffSettings(settings);
    final revision = session.staffSettingsRevision.value;
    for (var i = 0; i < 3; i++) {
      await session.saveStaffSettings(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(settings)) as Map));
    }
    expect(session.staffSettingsRevision.value, revision);
  });
  test('kitchen assignment change still invalidates the session', () async {
    await session.saveStaffSettings(settings);
    final revision = session.staffSettingsRevision.value;
    await session.saveStaffSettings({'kitchen_v2': {
      'mode': 'active',
      'identity': {'company_id': 100, 'branch_id': 20, 'device_id': 1},
    }});
    expect(session.staffSettingsRevision.value, revision + 1);
    expect(session.kitchenV2['identity']['branch_id'], 20);
  });
  test('permission revocation still invalidates unchanged kitchen config', () async {
    await session.saveStaffSettings(settings);
    final revision = session.staffSettingsRevision.value;
    await session.saveStaffSettings({...settings, 'position_permissions': {}});
    expect(session.staffSettingsRevision.value, revision + 1);
  });
  test('explicit reminder clearing notifies once and absent keys retain values', () async {
    await session.saveStaffSettings(settings);
    final revision = session.staffSettingsRevision.value;
    await session.saveStaffSettings({'shift_end_reminder_at': null});
    expect(session.staffSettingsRevision.value, revision + 1);
    expect(session.shiftEndReminderAt, isNull);
    expect(session.kitchenV2, settings['kitchen_v2']);
    await session.saveStaffSettings({'shift_end_reminder_at': null});
    expect(session.staffSettingsRevision.value, revision + 1);
  });
}
