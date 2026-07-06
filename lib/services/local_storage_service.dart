import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _terminalIdKey = 'terminal_id';
  // Deliberately the SAME literal key SessionService uses — this class is the
  // Soft-POS-side reader of the value SessionService keeps in sync (the
  // existing terminal_id pattern).
  static const String _terminalPinKey = 'terminal_pin';

  static Future<void> saveTerminalId(String terminalId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_terminalIdKey, terminalId);
  }

  static Future<String?> getTerminalId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_terminalIdKey);
  }

  static Future<void> clearTerminalId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_terminalIdKey);
  }

  static Future<void> saveTerminalPin(String terminalPin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_terminalPinKey, terminalPin);
  }

  static Future<String?> getTerminalPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_terminalPinKey);
  }

  static Future<void> clearTerminalPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_terminalPinKey);
  }
}
