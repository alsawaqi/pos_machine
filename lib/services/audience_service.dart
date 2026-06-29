import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// Phase 1A — ANONYMOUS audience measurement on the customer-facing camera.
///
/// Headless (no preview): opens the front / customer-facing camera, runs Google
/// ML Kit face detection on a throttled frame stream entirely on-device, and
/// keeps a short rolling buffer of {face count, tracking ids, attentive count}.
/// When an ad slide finishes, [enrich] folds the audience seen during that
/// slide's window into its `slider.display` telemetry payload.
///
/// PRIVACY: frames are processed in memory and discarded immediately. No image,
/// frame, or face template is ever stored or transmitted — only the aggregate
/// integer counts produced here. Faces are counted, never identified.
///
/// Purely auxiliary: every failure is swallowed so it can never disturb a sale.
class _Sample {
  const _Sample({
    required this.tsMs,
    required this.count,
    required this.attentive,
    required this.ids,
  });

  final int tsMs;
  final int count;
  final int attentive;
  final Set<int> ids;
}

class AudienceService {
  CameraController? _controller;
  FaceDetector? _detector;
  final List<_Sample> _buffer = <_Sample>[];

  bool _starting = false;
  bool _busy = false;
  int _lastProcessMs = 0;

  // Throttle inference to protect the fanless device — the camera streams
  // faster, but detection only runs a few times a second.
  static const int _minIntervalMs = 350; // ~3 detections/sec
  static const int _bufferWindowMs = 120000; // keep ~2 min of samples
  // A face is "attending" when roughly oriented toward the screen.
  static const double _yawLimit = 25;
  static const double _pitchLimit = 20;

  bool get running => _controller?.value.isInitialized == true;

  /// Start the camera + detector. Idempotent and best-effort: returns quietly if
  /// permission is denied, no camera exists, or anything fails.
  Future<void> start() async {
    if (running || _starting) return;
    _starting = true;
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableTracking: true, // tracking ids → distinct people, no recount
          minFaceSize: 0.05, // detect faces at signage distance
        ),
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // ML Kit's preferred format
      );
      await controller.initialize();
      await controller.startImageStream(_onFrame);
      _controller = controller;
    } catch (e) {
      debugPrint('AudienceService start failed: $e');
      await stop();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    _buffer.clear();
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {/* ignore */}
      try {
        await controller.dispose();
      } catch (_) {/* ignore */}
    }
    try {
      await _detector?.close();
    } catch (_) {/* ignore */}
    _detector = null;
  }

  Future<void> _onFrame(CameraImage image) async {
    final detector = _detector;
    if (detector == null || _busy) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastProcessMs < _minIntervalMs) return;
    _lastProcessMs = nowMs;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await detector.processImage(input);
      final ids = <int>{};
      var attentive = 0;
      for (final f in faces) {
        if (f.trackingId != null) ids.add(f.trackingId!);
        final yaw = f.headEulerAngleY;
        final pitch = f.headEulerAngleX;
        final yawOk = yaw == null || yaw.abs() <= _yawLimit;
        final pitchOk = pitch == null || pitch.abs() <= _pitchLimit;
        if (yawOk && pitchOk) attentive++;
      }
      _buffer.add(_Sample(
        tsMs: nowMs,
        count: faces.length,
        attentive: attentive,
        ids: ids,
      ));
      final cutoff = nowMs - _bufferWindowMs;
      _buffer.removeWhere((s) => s.tsMs < cutoff);
    } catch (_) {
      // A bad frame is not fatal — keep streaming.
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final rotation = InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );
    if (rotation == null || image.planes.isEmpty) return null;
    final plane = image.planes.first; // NV21 is a single interleaved plane
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Fold the audience measured over the last [windowMs] of samples into a
  /// `slider.display` event payload. Returns the event UNCHANGED when the camera
  /// isn't running (so impressions keep NULL audience = "not measured"). When
  /// running, the fields are always present — 0 means "measured, nobody watched".
  Map<String, dynamic> enrich(Map<String, dynamic> event) {
    if (!running) return event;
    final rawPayload = event['payload'];
    if (rawPayload is! Map) return event;
    final payload = Map<String, dynamic>.from(rawPayload);

    final durationMs = (payload['duration_ms'] as num?)?.toInt() ?? 0;
    final window = durationMs > 0 ? durationMs : _minIntervalMs;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoff = nowMs - window;
    final recent = _buffer.where((s) => s.tsMs >= cutoff).toList(growable: false);

    var peak = 0;
    var sum = 0;
    var attentiveSamples = 0;
    final ids = <int>{};
    for (final s in recent) {
      peak = math.max(peak, s.count);
      sum += s.count;
      ids.addAll(s.ids);
      if (s.attentive > 0) attentiveSamples++;
    }
    final avg = recent.isEmpty ? 0 : (sum / recent.length).round();
    final attentionMs =
        recent.isEmpty ? 0 : (attentiveSamples / recent.length * window).round();

    payload['viewers_peak'] = peak;
    payload['viewers_avg'] = avg;
    payload['viewers_distinct'] = ids.length;
    payload['attention_ms'] = attentionMs;
    return <String, dynamic>{...event, 'payload': payload};
  }
}
