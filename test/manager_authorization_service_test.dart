import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/services/manager_authorization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.manager_biometrics');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'authenticate';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('manager registration stores biometric approval locally', () async {
    final service = ManagerAuthorizationService();

    final registered = await service.registerManagerFingerprint();

    expect(registered, isTrue);
    expect(await service.isManagerRegistered(), isTrue);
    expect(calls, <String>['authenticate']);
  });

  test('manager cancellation requires prior biometric registration', () async {
    SharedPreferences.setMockInitialValues({
      'manager_biometric_registered': true,
    });
    final service = ManagerAuthorizationService();

    final authorized = await service.authenticateCancellation();

    expect(authorized, isTrue);
    expect(calls, <String>['authenticate']);
  });
}
