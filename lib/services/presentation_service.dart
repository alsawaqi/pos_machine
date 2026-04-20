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

    final displays = await getPresentationDisplays();

    if (displays.isEmpty) return false;

    final first = Map<String, dynamic>.from(displays.first as Map);
    final int displayId = (first['displayId'] as num).toInt();

    _activeDisplayId = displayId;
    debugPrint(
      'PresentationService opening displayId=$displayId with tag=$_engineTag',
    );

    return await _hostChannel.invokeMethod<bool>(
          'openRearDisplay',
          <String, dynamic>{
            'displayId': displayId,
            'engineId': _engineTag,
          },
        ) ??
        false;
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

  void listenFromCustomer(void Function(dynamic data) onData) {
    _frontChannel.setMethodCallHandler((call) async {
      onData(call.arguments);
    });
  }
}
