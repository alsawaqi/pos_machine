/// LAUNCH-P4 C2 — draws the receipt layout ([buildReceiptLines]) as a
/// black-on-white bitmap for the thermal printer.
///
/// Why a bitmap: the Sunmi printer's text API renders Arabic letters
/// unjoined and in the wrong order. Flutter's own text engine shapes Arabic
/// (and mixed Arabic/English lines) correctly, so the whole receipt is laid
/// out here and sent with `printImage`, in strips so a long receipt never
/// exceeds the printer's bitmap limits.
///
/// On the device no font is named: Android's own fonts are used (Roboto for
/// Latin, Noto Naskh Arabic for Arabic). Tests pass [fontFamily] /
/// [fontFamilyFallback] to render deterministically with bundled fixtures.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'receipt_layout.dart';

/// 58 mm paper = 384 dots; 80 mm paper = 576 dots.
const int kReceipt58mmWidth = 384;
const int kReceipt80mmWidth = 576;

class ReceiptRenderOptions {
  const ReceiptRenderOptions({
    this.width = kReceipt58mmWidth,
    this.fontFamily,
    this.fontFamilyFallback,
  });

  final int width;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
}

typedef _Painter = void Function(Canvas canvas, double top);

class _Block {
  _Block(this.height, this.paint);
  final double height;
  final _Painter paint;
}

/// Lay the receipt out and record it; returns the picture and its height.
({ui.Picture picture, int height}) recordReceipt(
  List<ReceiptLine> lines, {
  ReceiptRenderOptions options = const ReceiptRenderOptions(),
}) {
  final width = options.width.toDouble();
  final scale = width / kReceipt58mmWidth;
  final pad = 6 * scale;
  final content = width - pad * 2;
  const black = Color(0xFF000000);

  TextStyle style(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        color: black,
        fontSize: size * scale,
        fontWeight: weight,
        height: 1.25,
        fontFamily: options.fontFamily,
        fontFamilyFallback: options.fontFamilyFallback,
      );

  TextPainter painter(
    String text,
    TextStyle style, {
    TextAlign align = TextAlign.left,
    TextDirection direction = TextDirection.ltr,
    required double maxWidth,
  }) => TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: direction,
  )..layout(minWidth: maxWidth, maxWidth: maxWidth);

  _Block text(
    String value,
    TextStyle s, {
    TextAlign align = TextAlign.center,
    TextDirection direction = TextDirection.ltr,
    double indent = 0,
  }) {
    final p = painter(
      value,
      s,
      align: align,
      direction: direction,
      maxWidth: content - indent,
    );
    return _Block(
      p.height,
      (canvas, top) => p.paint(canvas, Offset(pad + indent, top)),
    );
  }

  _Block pair(String label, String amount, TextStyle s) {
    final a = TextPainter(
      text: TextSpan(text: amount, style: s),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: content * 0.6);
    final gap = 8 * scale;
    final l = painter(label, s, maxWidth: content - a.width - gap);
    return _Block(
      l.height > a.height ? l.height : a.height,
      (canvas, top) {
        l.paint(canvas, Offset(pad, top));
        a.paint(canvas, Offset(pad + content - a.width, top));
      },
    );
  }

  final blocks = <_Block>[_Block(6 * scale, (_, _) {})];
  for (final line in lines) {
    switch (line.kind) {
      case ReceiptLineKind.heading:
        blocks.add(text(line.text, style(30, weight: FontWeight.w700)));
      case ReceiptLineKind.title:
        blocks.add(text(line.text, style(24, weight: FontWeight.w700)));
      case ReceiptLineKind.centered:
        blocks.add(text(line.text, style(19)));
      case ReceiptLineKind.note:
        blocks.add(text(line.text, style(19, weight: FontWeight.w700)));
      case ReceiptLineKind.pair:
        blocks.add(
          pair(
            line.text,
            line.amount,
            style(20, weight: line.bold ? FontWeight.w700 : FontWeight.w400),
          ),
        );
      case ReceiptLineKind.item:
        blocks.add(
          pair(line.text, line.amount, style(21, weight: FontWeight.w700)),
        );
      case ReceiptLineKind.itemAr:
        blocks.add(
          text(
            line.text,
            style(21),
            align: TextAlign.right,
            direction: TextDirection.rtl,
          ),
        );
      case ReceiptLineKind.detail:
        blocks.add(
          text(line.text, style(18), align: TextAlign.left, indent: 14 * scale),
        );
      case ReceiptLineKind.total:
        blocks
          ..add(_Block(4 * scale, (_, _) {}))
          ..add(
            pair(line.text, line.amount, style(26, weight: FontWeight.w700)),
          )
          ..add(_Block(4 * scale, (_, _) {}));
      case ReceiptLineKind.divider:
        final h = 14 * scale;
        blocks.add(
          _Block(h, (canvas, top) {
            final paint = Paint()
              ..color = black
              ..strokeWidth = 2 * scale;
            final dash = 8 * scale;
            final y = top + h / 2;
            for (var x = pad; x < pad + content; x += dash * 1.6) {
              final end = (x + dash).clamp(pad, pad + content);
              canvas.drawLine(Offset(x, y), Offset(end, y), paint);
            }
          }),
        );
      case ReceiptLineKind.gap:
        blocks.add(_Block(10 * scale, (_, _) {}));
    }
  }
  blocks.add(_Block(10 * scale, (_, _) {}));

  final height = blocks.fold<double>(0, (sum, b) => sum + b.height).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  var top = 0.0;
  for (final block in blocks) {
    block.paint(canvas, top);
    top += block.height;
  }
  return (picture: recorder.endRecording(), height: height);
}

/// The whole receipt as one image (tests and previews).
Future<ui.Image> renderReceiptImage(
  List<ReceiptLine> lines, {
  ReceiptRenderOptions options = const ReceiptRenderOptions(),
}) async {
  final recorded = recordReceipt(lines, options: options);
  return recorded.picture.toImage(options.width, recorded.height);
}

/// The receipt as PNG strips of at most [maxStripHeight] dots, top to
/// bottom, ready for `SunmiPrinter.printImage`.
Future<List<Uint8List>> renderReceiptPngStrips(
  List<ReceiptLine> lines, {
  ReceiptRenderOptions options = const ReceiptRenderOptions(),
  int maxStripHeight = 800,
}) async {
  final recorded = recordReceipt(lines, options: options);
  final strips = <Uint8List>[];
  for (var y = 0; y < recorded.height; y += maxStripHeight) {
    final h = (recorded.height - y) < maxStripHeight
        ? recorded.height - y
        : maxStripHeight;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..translate(0, -y.toDouble())
      ..drawPicture(recorded.picture);
    final image = await recorder.endRecording().toImage(options.width, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data != null) strips.add(data.buffer.asUint8List());
  }
  return strips;
}
