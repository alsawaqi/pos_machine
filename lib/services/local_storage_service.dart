import 'package:pos_machine/tenancy/tenant_preferences.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';

class LocalStorageService {
  static const _secure = FlutterSecureStorage();
  static Future<void> saveTerminalId(String terminalId) async {
    final prefs = await businessPreferences();
    await prefs.setString('terminal_id', terminalId);
  }

  static Future<String?> getTerminalId() async =>
      (await businessPreferences()).getString('terminal_id');
  static Future<void> clearTerminalId() async {
    await (await businessPreferences()).remove('terminal_id');
  }

  static Future<void> saveTerminalPin(String terminalPin) async {
    if (terminalPin.trim().isEmpty) return clearTerminalPin();
    await _secure.write(key: 'terminal_pin', value: terminalPin.trim());
    await (await businessPreferences()).remove('terminal_pin');
  }

  static Future<String?> getTerminalPin() async {
    final prefs = await businessPreferences();
    var pin = await _secure.read(key: 'terminal_pin');
    final legacy = prefs.getString('terminal_pin');
    if (pin == null && legacy != null && legacy.trim().isNotEmpty) {
      pin = legacy.trim();
      await _secure.write(key: 'terminal_pin', value: pin);
    }
    await prefs.remove('terminal_pin');
    return pin;
  }

  static Future<void> clearTerminalPin() async {
    await _secure.delete(key: 'terminal_pin');
    await (await businessPreferences()).remove('terminal_pin');
  }

  static Future<SoftPosProfile> getSoftposProfile() async {
    final raw = (await businessPreferences()).getString('softpos_profile');
    return SoftPosProfile.fromJson(raw == null ? null : softPosObject(raw));
  }

  static Future<void> saveSoftposProfile(SoftPosProfile profile) async {
    await (await businessPreferences()).setString(
      'softpos_profile',
      jsonEncode(profile.toJson()),
    );
  }
}
