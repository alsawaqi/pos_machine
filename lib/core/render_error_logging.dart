import 'package:flutter/foundation.dart';

/// Keep framework/build failures in local logs, including when a reporting SDK
/// replaces Flutter's console handler. Preserve that SDK's reporting callback.
void installRenderErrorLogging() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
    if (previous != null && previous != FlutterError.presentError) {
      previous(details);
    }
  };
}
