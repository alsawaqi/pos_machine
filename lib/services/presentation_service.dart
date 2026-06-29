import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/pos_models.dart';

class PresentationService {
  PresentationService._();
  static final PresentationService instance = PresentationService._();

  static const MethodChannel _hostChannel = MethodChannel(
    'pos_machine/rear_display_host',
  );
  static const MethodChannel _frontChannel = MethodChannel(
    'pos_machine/front_display_channel',
  );

  final String _engineTag =
      'customer_display_${DateTime.now().microsecondsSinceEpoch}';
  int? _activeDisplayId;
  // Phase 3 — the advertising loop last pushed to the customer screen, kept so
  // we can re-send it the moment a (re)opened display is ready (it runs its own
  // playback timer, independent of order updates).
  List<SliderSlide> _lastSlides = const [];
  final bool _supportsRearDisplay =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<List<dynamic>> getPresentationDisplays() async {
    if (!_supportsRearDisplay) return <dynamic>[];

    return await _hostChannel.invokeListMethod<dynamic>(
          'getPresentationDisplays',
        ) ??
        <dynamic>[];
  }

  Future<bool> openFirstRearDisplay() async {
    if (!_supportsRearDisplay) return false;

    final displays = await _loadPresentationDisplays();

    if (displays.isEmpty) {
      debugPrint(
        'PresentationService did not find a non-default display. The customer screen may still be in mirror-only mode.',
      );
      return false;
    }

    final first = displays.first;
    final int requestedDisplayId = (first['displayId'] as num).toInt();

    final prepared =
        await _hostChannel.invokeMapMethod<String, dynamic>(
          'prepareRearDisplay',
          <String, dynamic>{'displayId': requestedDisplayId},
        ) ??
        <String, dynamic>{};
    final preparedMap = Map<String, dynamic>.from(prepared);
    final targetDisplay = await _awaitPreparedDisplay(
      preferredSerial: preparedMap['serial']?.toString(),
      fallbackDisplayId:
          (preparedMap['displayId'] as num?)?.toInt() ?? requestedDisplayId,
    );
    final int displayId = (targetDisplay['displayId'] as num).toInt();

    _activeDisplayId = displayId;
    debugPrint(
      'PresentationService opening displayId=$displayId with tag=$_engineTag',
    );

    final opened =
        await _hostChannel.invokeMethod<bool>(
          'openRearDisplay',
          <String, dynamic>{'displayId': displayId, 'engineId': _engineTag},
        ) ??
        false;

    if (!opened) {
      _activeDisplayId = null;
      debugPrint(
        'PresentationService failed to open displayId=$displayId as a customer Presentation.',
      );
    }

    return opened;
  }

  Future<List<Map<String, dynamic>>> _loadPresentationDisplays() async {
    final displays = await getPresentationDisplays();

    final mapped = displays
        .whereType<Map>()
        .map((display) => Map<String, dynamic>.from(display))
        .where((display) => display['isDefaultDisplay'] != true)
        .toList();

    mapped.sort((a, b) {
      final aSunmi = a['isSunmiUsbDisplay'] == true ? 1 : 0;
      final bSunmi = b['isSunmiUsbDisplay'] == true ? 1 : 0;
      if (aSunmi != bSunmi) return bSunmi.compareTo(aSunmi);

      final aPresentation = a['isPresentationCategory'] == true ? 1 : 0;
      final bPresentation = b['isPresentationCategory'] == true ? 1 : 0;
      if (aPresentation != bPresentation) {
        return bPresentation.compareTo(aPresentation);
      }

      final aId = (a['displayId'] as num?)?.toInt() ?? -1;
      final bId = (b['displayId'] as num?)?.toInt() ?? -1;
      return bId.compareTo(aId);
    });

    debugPrint('PresentationService display candidates: $mapped');
    return mapped;
  }

  Future<Map<String, dynamic>> _awaitPreparedDisplay({
    required int fallbackDisplayId,
    String? preferredSerial,
  }) async {
    Map<String, dynamic>? candidate;

    for (var attempt = 0; attempt < 8; attempt++) {
      final displays = await _loadPresentationDisplays();
      candidate = _pickDisplay(
        displays,
        fallbackDisplayId: fallbackDisplayId,
        preferredSerial: preferredSerial,
      );

      if (candidate != null) {
        if (preferredSerial == null || candidate['serial'] == preferredSerial) {
          return candidate;
        }
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    return candidate ?? <String, dynamic>{'displayId': fallbackDisplayId};
  }

  Map<String, dynamic>? _pickDisplay(
    List<Map<String, dynamic>> displays, {
    required int fallbackDisplayId,
    String? preferredSerial,
  }) {
    final usableDisplays = displays
        .where((display) => display['isDefaultDisplay'] != true)
        .toList();

    if (preferredSerial != null) {
      for (final display in usableDisplays) {
        if (display['serial']?.toString() == preferredSerial) {
          return display;
        }
      }
    }

    for (final display in usableDisplays) {
      if ((display['displayId'] as num?)?.toInt() == fallbackDisplayId) {
        return display;
      }
    }

    return usableDisplays.isEmpty ? null : usableDisplays.first;
  }

  Future<void> closeRearDisplay() async {
    if (!_supportsRearDisplay) return;
    if (_activeDisplayId == null) return;
    await _hostChannel.invokeMethod<void>('hideRearDisplay');
    _activeDisplayId = null;
  }

  Future<void> sendOrder(OrderSnapshot snapshot) async {
    if (!_supportsRearDisplay) return;

    await _hostChannel.invokeMethod<void>('transferDataToRear', {
      'type': 'order_snapshot',
      ...snapshot.toMap(),
    });
  }

  /// Phase 3 — push the advertising loop to the customer screen. Sent on a
  /// separate `slider_set` message (NOT folded into the frequent order push) so
  /// the secondary updates the loop only when it actually changes, and its
  /// continuous playback is never restarted by an order update. Remembered so a
  /// freshly (re)opened display can be re-seeded via [resendSlides].
  Future<void> sendSlides(List<SliderSlide> slides) async {
    _lastSlides = slides;
    if (!_supportsRearDisplay) return;

    // Best-effort: a missing channel (no rear display / test host) or a
    // not-yet-ready display must never bubble up and fail the caller (e.g. a
    // catalog apply). Mirrors how the controller treats the presentation path.
    try {
      await _hostChannel.invokeMethod<void>('transferDataToRear', {
        'type': 'slider_set',
        'slides': slides.map((s) => s.toJson()).toList(),
      });
    } catch (_) {
      // swallow — the loop re-seeds on the next catalog change / display open
    }
  }

  /// Re-send the last-known loop (e.g. right after the rear display opens or
  /// reconnects, so it isn't left blank until the next catalog change).
  Future<void> resendSlides() => sendSlides(_lastSlides);

  void listenFromCustomer(void Function(dynamic data) onData) {
    _frontChannel.setMethodCallHandler((call) async {
      if (call.method != 'customerEvent') return;
      onData(call.arguments);
    });
  }
}
