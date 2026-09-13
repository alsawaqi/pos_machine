import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';

class LocalStorageService {
  static const _secure = FlutterSecureStorage();
  static Future<void> saveTerminalId(String terminalId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terminal_id', terminalId);
  }

  static Future<String?> getTerminalId() async =>
      (await SharedPreferences.getInstance()).getString('terminal_id');
  static Future<void> clearTerminalId() async {
    await (await SharedPreferences.getInstance()).remove('terminal_id');
  }

  static Future<void> saveTerminalPin(String terminalPin) async {
    if (terminalPin.trim().isEmpty) return clearTerminalPin();
    await _secure.write(key: 'terminal_pin', value: terminalPin.trim());
    await (await SharedPreferences.getInstance()).remove('terminal_pin');
  }

  static Future<String?> getTerminalPin() async {
    final prefs = await SharedPreferences.getInstance();
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
    await (await SharedPreferences.getInstance()).remove('terminal_pin');
  }

  static Future<SoftPosProfile> getSoftposProfile() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      'softpos_profile',
    );
    return SoftPosProfile.fromJson(raw == null ? null : softPosObject(raw));
  }

  static Future<void> saveSoftposProfile(SoftPosProfile profile) async {
    await (await SharedPreferences.getInstance()).setString(
      'softpos_profile',
      jsonEncode(profile.toJson()),
    );
  }
}
