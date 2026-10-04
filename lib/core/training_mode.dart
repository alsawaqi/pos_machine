import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import 'training_flag.dart';

export 'training_flag.dart';

/// LAUNCH-P5 C7 — training mode (behind the `training.use` tick).
///
/// While it is on:
///  * a red TRAINING banner shows over the till;
///  * sales are kept in a separate in-memory store ([TrainingOrderStore]),
///    never in the order history, and nothing enters the outbox;
///  * no stock, kitchen print, card, SoftPOS, QR, station, table-server or
///    loyalty call is made — the API client refuses every request outside
///    [TrainingMode.allows] (config, staff status, approvers, the approval
///    PIN check and the device heartbeat);
///  * receipts print "TRAINING — NOT A RECEIPT / تدريب — ليس إيصالاً";
///  * anything that could still reach the server carries `training: true`
///    (the server refuses it);
///  * no shift or clock-in is needed.
/// Leaving training discards everything done in it.
final trainingModeProvider = NotifierProvider<TrainingModeController, bool>(
  TrainingModeController.new,
);

class TrainingModeController extends Notifier<bool> {
  SharedPreferences _prefs() => ref.read(sharedPreferencesProvider);

  @override
  bool build() {
    var on = false;
    try {
      on = _prefs().getBool(TrainingMode.preferenceKey) ?? false;
    } catch (_) {}
    TrainingMode.active = on;
    return on;
  }

  Future<void> enter() async {
    TrainingMode.active = true;
    TrainingOrderStore.clear();
    state = true;
    try {
      await _prefs().setBool(TrainingMode.preferenceKey, true);
    } catch (_) {}
  }

  /// Leave training: everything done in it is discarded.
  Future<void> exit() async {
    TrainingOrderStore.clear();
    TrainingMode.active = false;
    state = false;
    try {
      await _prefs().remove(TrainingMode.preferenceKey);
    } catch (_) {}
  }
}
