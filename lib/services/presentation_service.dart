import 'package:flutter_presentation_display/flutter_presentation_display.dart';
import '../models/pos_models.dart';

class PresentationService {
  PresentationService._();
  static final PresentationService instance = PresentationService._();

  final FlutterPresentationDisplay _display = FlutterPresentationDisplay();
  int? _activeDisplayId;

  Future<List<dynamic>> getPresentationDisplays() async {
    return await _display.getDisplays(
          category: DISPLAY_CATEGORY_PRESENTATION,
        ) ??
        <dynamic>[];
  }

  Future<bool> openFirstRearDisplay() async {
    final displays =
        await _display.getDisplays(category: DISPLAY_CATEGORY_PRESENTATION) ??
        [];

    if (displays.isEmpty) return false;

    final first = displays.first;
    final int displayId = first.displayId as int;

    _activeDisplayId = displayId;

    return await _display.showSecondaryDisplay(
          displayId: displayId,
          routerName: 'secondaryDisplayMain',
        ) ??
        false;
  }

  Future<void> closeRearDisplay() async {
    if (_activeDisplayId == null) return;
    await _display.hideSecondaryDisplay(displayId: _activeDisplayId!);
    _activeDisplayId = null;
  }

  Future<void> sendOrder(OrderSnapshot snapshot) async {
    await _display.transferDataToPresentation({
      'type': 'order_snapshot',
      ...snapshot.toMap(),
    });
  }

  void listenFromCustomer(void Function(dynamic data) onData) {
    _display.listenDataFromPresentationDisplay(onData);
  }
}
