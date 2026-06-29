import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/pos_models.dart';

/// Phase 3 — the advertising loop for the customer (secondary) screen.
///
/// Plays an ordered list of [SliderSlide]s continuously: images for their set
/// duration, videos muted and CAPPED at the same duration (advance at the cap
/// OR when the clip ends, whichever comes first). It runs autonomously on its
/// own timer + video controller, so it NEVER restarts when the order state
/// changes around it — keep it mounted with a stable (Global)Key across the
/// full-screen ⇄ split-screen layouts and only its geometry changes.
///
/// [onSlideElapsed] fires when a slide leaves the screen, reporting the actual
/// milliseconds it was visible — the device turns that into play-time telemetry
/// (Phase 3C). Empty [slides] renders nothing (caller falls back to its non-ad
/// layout).
class AdSlider extends StatefulWidget {
  const AdSlider({
    super.key,
    required this.slides,
    this.onSlideElapsed,
    this.muted = true,
    this.fit = BoxFit.cover,
  });

  final List<SliderSlide> slides;
  final void Function(SliderSlide slide, int shownMs)? onSlideElapsed;
  final bool muted;
  final BoxFit fit;

  @override
  State<AdSlider> createState() => _AdSliderState();
}

class _AdSliderState extends State<AdSlider> {
  int _index = 0;
  Timer? _timer;
  VideoPlayerController? _video;
  DateTime? _shownAt;

  @override
  void initState() {
    super.initState();
    _startCurrent();
  }

  @override
  void didUpdateWidget(AdSlider old) {
    super.didUpdateWidget(old);
    // Only a genuine change to the loop restarts it — order-state rebuilds pass
    // the same slides and must not interrupt playback.
    if (!_sameSlides(old.slides, widget.slides)) {
      _index = 0;
      _restart();
    }
  }

  bool _sameSlides(List<SliderSlide> a, List<SliderSlide> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].itemId != b[i].itemId ||
          a[i].url != b[i].url ||
          a[i].durationSeconds != b[i].durationSeconds) {
        return false;
      }
    }
    return true;
  }

  SliderSlide? get _current => widget.slides.isEmpty
      ? null
      : widget.slides[_index % widget.slides.length];

  void _restart() {
    _timer?.cancel();
    _disposeVideo();
    _startCurrent();
  }

  void _startCurrent() {
    final slide = _current;
    if (slide == null) return;
    _shownAt = DateTime.now();
    final capMs = (slide.durationSeconds <= 0 ? 6 : slide.durationSeconds) * 1000;
    if (slide.isVideo) {
      _playVideo(slide, capMs);
    } else {
      if (mounted) setState(() {});
      _timer = Timer(Duration(milliseconds: capMs), _advance);
    }
  }

  Future<void> _playVideo(SliderSlide slide, int capMs) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(slide.url));
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || _video != controller) {
        controller.dispose();
        return;
      }
      await controller.setVolume(widget.muted ? 0 : 1);
      await controller.setLooping(false);
      await controller.play();
      controller.addListener(_videoTick);
      if (mounted) setState(() {});
      // Cap: advance at the builder duration even if the clip is longer.
      _timer = Timer(Duration(milliseconds: capMs), _advance);
    } catch (_) {
      // Unplayable clip — don't stall the loop; skip after a short beat.
      _timer = Timer(const Duration(seconds: 1), _advance);
    }
  }

  void _videoTick() {
    final c = _video;
    if (c == null) return;
    final v = c.value;
    // Clip finished before the cap → advance early.
    if (v.isInitialized &&
        v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration) {
      _advance();
    }
  }

  void _advance() {
    if (!mounted) return;
    final slide = _current;
    if (slide != null && _shownAt != null) {
      final ms = DateTime.now().difference(_shownAt!).inMilliseconds;
      widget.onSlideElapsed?.call(slide, ms);
    }
    _timer?.cancel();
    _disposeVideo();
    if (widget.slides.isEmpty) return;
    setState(() => _index = (_index + 1) % widget.slides.length);
    _startCurrent();
  }

  void _disposeVideo() {
    final c = _video;
    _video = null;
    if (c != null) {
      c.removeListener(_videoTick);
      c.dispose();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _current;
    if (slide == null) return const ColoredBox(color: Colors.black);

    Widget media;
    if (slide.isVideo) {
      final c = _video;
      media = (c != null && c.value.isInitialized)
          ? FittedBox(
              fit: widget.fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          : const ColoredBox(color: Colors.black);
    } else {
      media = CachedNetworkImage(
        imageUrl: slide.url,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, _) => const ColoredBox(color: Colors.black),
        errorWidget: (_, _, _) => const ColoredBox(color: Colors.black),
      );
    }

    return ClipRect(
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: KeyedSubtree(key: ValueKey<int>(slide.itemId), child: media),
        ),
      ),
    );
  }
}
