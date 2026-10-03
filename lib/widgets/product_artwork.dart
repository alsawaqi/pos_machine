import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// LAUNCH-P4 H11 — a product's picture on the till: the merchant's photo,
/// downloaded once and cached on the device (works offline afterwards), or —
/// when there is no photo, or it cannot load — a neutral placeholder with the
/// product's initials. Never a stock coffee picture.
///
/// [imageAsset] remains only for the built-in demo catalogue.
class ProductArtwork extends StatelessWidget {
  const ProductArtwork({
    super.key,
    required this.name,
    this.imageUrl,
    this.imageAsset,
    this.width = 84,
    this.height = 84,
    this.radius = 18,
  });

  /// The name to draw initials from (already Arabic in an Arabic UI).
  final String name;
  final String? imageUrl;
  final String? imageAsset;
  final double width;
  final double height;
  final double radius;

  /// Tests replace the network image (no HTTP / disk cache in widget tests).
  @visibleForTesting
  static Widget Function(String url, Widget fallback)? debugNetworkImage;

  /// Up to two initials, e.g. "Iced Latte" → "IL", "لاتيه بارد" → "لب".
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    String first(String w) => String.fromCharCode(w.runes.first);
    final text = words.length == 1
        ? first(words.first)
        : '${first(words[0])}${first(words[1])}';
    return text.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _InitialsPlaceholder(
      initials: initialsOf(name),
      seed: name,
      size: width.isFinite ? (width < height ? width : height) : height,
    );
    final url = imageUrl?.trim() ?? '';
    final Widget child;
    if (url.isNotEmpty) {
      child =
          debugNetworkImage?.call(url, placeholder) ??
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    } else if (imageAsset != null) {
      child = Image.asset(
        imageAsset!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else {
      child = placeholder;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

class _InitialsPlaceholder extends StatelessWidget {
  const _InitialsPlaceholder({
    required this.initials,
    required this.seed,
    required this.size,
  });

  final String initials;
  final String seed;
  final double size;

  static const _palette = <List<Color>>[
    [Color(0xFF2F5D62), Color(0xFF1E3B3F)],
    [Color(0xFF5B4B8A), Color(0xFF3A2F5B)],
    [Color(0xFF8A5A44), Color(0xFF5C3A2C)],
    [Color(0xFF3D5A80), Color(0xFF263A55)],
    [Color(0xFF4F772D), Color(0xFF31491C)],
    [Color(0xFF7A4069), Color(0xFF512A45)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palette[seed.hashCode.abs() % _palette.length];
    return DecoratedBox(
      key: const ValueKey('product-initials-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: (size.isFinite ? size : 80) * 0.34,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
