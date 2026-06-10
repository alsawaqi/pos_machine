import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';

class ManagerAuthorizationService {
  static const _channel = MethodChannel('com.example.manager_biometrics');
  static const _registeredKey = 'manager_biometric_registered';

  /// Wired by the owning screen (`_managerAuthorization.localize = () =>
  /// ref.read(l10nProvider);`) so prompts resolve without a BuildContext.
  L10n Function()? localize;

  L10n get _l10n => localize?.call() ?? lookupL10n(const Locale('en'));

  Future<bool> isManagerRegistered() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_registeredKey) ?? false;
  }

  Future<bool> registerManagerFingerprint() async {
    final approved = await _authenticate(
      title: _l10n.managerAuthRegisterTitle,
      subtitle: _l10n.managerAuthRegisterSubtitle,
      description: _l10n.managerAuthRegisterDescription,
      negativeButton: _l10n.commonCancel,
    );
    if (!approved) return false;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_registeredKey, true);
    return true;
  }

  Future<bool> authenticateCancellation() async {
    if (!await isManagerRegistered()) return false;
    return _authenticate(
      title: _l10n.managerAuthApprovalRequiredTitle,
      subtitle: _l10n.managerAuthCancelOrderSubtitle,
      description: _l10n.managerAuthCancelOrderDescription,
      negativeButton: _l10n.commonCancel,
    );
  }

  /// Generic manager approval (e.g. an approval-required discount). Returns
  /// false when no manager is registered or the biometric is declined/absent.
  Future<bool> authenticateManagerApproval({
    String? subtitle,
    String? description,
  }) async {
    if (!await isManagerRegistered()) return false;
    return _authenticate(
      title: _l10n.managerAuthApprovalRequiredTitle,
      subtitle: subtitle ?? _l10n.managerAuthDefaultSubtitle,
      description: description ?? _l10n.managerAuthDefaultDescription,
      negativeButton: _l10n.commonCancel,
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
