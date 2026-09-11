import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final quickEvidenceKey = GlobalKey();
Future<void> loadQuickEvidenceFonts(WidgetTester tester) async {
  if (Platform.environment['QR_QUICK_SCREENSHOT_DIR'] == null) return;
  await tester.runAsync(() async {
    for (final entry in {
      'QuickEvidence': 'C:/Windows/Fonts/tahoma.ttf',
      'MaterialIcons': 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
}

Future<void> captureQuickEvidence(WidgetTester tester, String name) async {
  final path = Platform.environment['QR_QUICK_SCREENSHOT_DIR'];
  if (path == null) return;
  await tester.pump(const Duration(milliseconds: 250));
  final boundary =
      quickEvidenceKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
