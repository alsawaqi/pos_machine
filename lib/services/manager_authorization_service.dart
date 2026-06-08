import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManagerAuthorizationService {
  static const _channel = MethodChannel('com.example.manager_biometrics');
  static const _registeredKey = 'manager_biometric_registered';

  Future<bool> isManagerRegistered() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_registeredKey) ?? false;
  }

  Future<bool> registerManagerFingerprint() async {
    final approved = await _authenticate(
      title: 'Register Manager Fingerprint',
      subtitle: 'Manager authorization setup',
      description: 'Place the manager fingerprint on the device sensor.',
      negativeButton: 'Cancel',
    );
    if (!approved) return false;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_registeredKey, true);
    return true;
  }

  Future<bool> authenticateCancellation() async {
    if (!await isManagerRegistered()) return false;
    return _authenticate(
      title: 'Manager Approval Required',
      subtitle: 'Cancel completed order',
      description: 'Place your fingerprint to unlock order cancellation.',
      negativeButton: 'Cancel',
    );
  }

  /// Generic manager approval (e.g. an approval-required discount). Returns
  /// false when no manager is registered or the biometric is declined/absent.
  Future<bool> authenticateManagerApproval({
    String subtitle = 'Manager approval',
    String description = 'Place the manager fingerprint to approve.',
  }) async {
    if (!await isManagerRegistered()) return false;
    return _authenticate(
      title: 'Manager Approval Required',
      subtitle: subtitle,
      description: description,
      negativeButton: 'Cancel',
    );
  }

  Future<bool> _authenticate({
    required String title,
    required String subtitle,
    required String description,
    required String negativeButton,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('authenticate', {
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'negativeButton': negativeButton,
      });
      return result == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
