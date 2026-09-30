import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/tenant_preferences.dart';

Future<Directory> loadFix2ReleaseStorage() async {
  BusinessBoundary.resetForTest();
  const root = 'test/fixtures/release_01d17de';
  final dir = await Directory.systemTemp.createTemp('fix2-money-t3-');
  for (final f in Directory(root + '/generated').listSync().whereType<File>()) {
    await f.copy(dir.path + '/' + f.uri.pathSegments.last);
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await databaseFactory.setDatabasesPath(dir.path);
  SharedPreferences.setMockInitialValues(
    Map<String, Object>.from(
      jsonDecode(File(root + '/prefs.json').readAsStringSync()),
    ),
  );
  FlutterSecureStorage.setMockInitialValues({
    'device_token': 'release-fixture-token',
  });
  final raw = await SharedPreferences.getInstance();
  await BusinessBoundary.initialize(raw);
  await SessionService(
    const FlutterSecureStorage(),
    TenantPreferences(raw),
  ).load();
  return dir;
}
