import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// FEASIBILITY SPIKE — anonymous audience measurement on the customer screen.
///
/// Proves the Sunmi second-screen camera + on-device Google ML Kit face
/// detection can reliably COUNT how many people are looking at the ad slider,
/// at real viewing distance, without cooking the device. This is throwaway
/// validation UI: it shows a live preview + bounding boxes + a big face count
/// so we can aim the camera and read detection quality. The production version
/// will run HEADLESS (no preview) and emit only aggregate counts.
///
/// PRIVACY: every frame is processed in memory and discarded immediately. No
/// image, frame, or face template is ever stored or transmitted. We count
/// faces, we do not identify anyone.
class AudienceSpikeScreen extends StatefulWidget {
  const AudienceSpikeScreen({super.key});

  @override
  State<AudienceSpikeScreen> createState() => _AudienceSpikeScreenState();
}

class _AudienceSpikeScreenState extends State<AudienceSpikeScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  FaceDetector? _detector;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _initialising = true;
  bool _detecting = false; // a frame is mid-detection (back-pressure guard)
  String? _error;

  // Live metrics.
  List<Face> _faces = const [];
  Size? _imageSize; // unrotated camera buffer size
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  final Set<int> _seenTrackingIds = <int>{}; // distinct faces this session
  int _detsThisSecond = 0;
  int _detsPerSecond = 0; // rough "how hard is it working" gauge
  Timer? _rateTimer;

  // Detection-rotation override, to find what the sensor needs on this unit.
  // null = auto (derive from sensorOrientation).
  int? _rotationOverrideDeg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _detsPerSecond = _detsThisSecond;
        _detsThisSecond = 0;
      });
    });
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rateTimer?.cancel();
    _teardownCamera();
    _detector?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _teardownCamera();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _bootstrap() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _initialising = false;
        _error = 'Camera permission denied. Enable it in system settings.';
      });
      return;
    }

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: true, // trackingId → don't double-count a lingerer
        minFaceSize: 0.05, // detect smaller/farther faces (signage distance)
      ),
    );

    try {
      _cameras = await availableCameras();
    } catch (e) {
      setState(() {
        _initialising = false;
        _error = 'Could not enumerate cameras: $e';
      });
      return;
    }
    if (_cameras.isEmpty) {
      setState(() {
        _initialising = false;
        _error = 'No cameras available on this device.';
      });
      return;
    }

    // Sunmi dual-screen units expose the customer-facing camera as FRONT.
    _cameraIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_cameraIndex < 0) _cameraIndex = 0;

    await _startCamera();
  }

  Future<void> _startCamera() async {
    final description = _cameras[_cameraIndex];
    final controller = CameraController(
      description,
      ResolutionPreset.medium, // 480p — enough for faces, light on the CPU
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // ML Kit's preferred format
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.startImageStream(_onFrame);
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = 'Camera start failed: $e';
      });
    }
  }

  Future<void> _teardownCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {/* ignore */}
    await controller.dispose();
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    await _teardownCamera();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() {
      _initialising = true;
      _faces = const [];
    });
    await _startCamera();
  }

  void _cycleRotation() {
    const ladder = <int?>[null, 0, 90, 180, 270];
    final i = ladder.indexOf(_rotationOverrideDeg);
    setState(() {
      _rotationOverrideDeg = ladder[(i + 1) % ladder.length];
    });
  }

  Future<void> _onFrame(CameraImage image) async {
    final detector = _detector;
    if (detector == null || _detecting) return; // drop frame if still busy
    _detecting = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await detector.processImage(input);
      if (!mounted) return;
      for (final f in faces) {
        if (f.trackingId != null) _seenTrackingIds.add(f.trackingId!);
      }
      _detsThisSecond++;
      setState(() {
        _faces = faces;
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    } catch (_) {
      // A bad frame is not fatal — keep streaming.
    } finally {
      _detecting = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _cameras[_cameraIndex];

    final InputImageRotation? rotation = _rotationOverrideDeg != null
        ? InputImageRotationValue.fromRawValue(_rotationOverrideDeg!)
        : InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;
    _rotation = rotation;

    if (image.planes.isEmpty) return null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: const Text('Audience spike (debug)'),
        actions: [
          IconButton(
            tooltip: 'Detection rotation: '
                '${_rotationOverrideDeg == null ? "auto" : "$_rotationOverrideDeg°"}',
            icon: const Icon(Icons.screen_rotation_outlined),
            onPressed: _initialising ? null : _cycleRotation,
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed:
                (_initialising || _cameras.length < 2) ? null : _switchCamera,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white54, size: 56),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (_initialising || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final camera = _cameras[_cameraIndex];
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        // Bounding boxes (best-effort overlay; the COUNT is the real signal).
        if (_imageSize != null)
          CustomPaint(
            painter: _FaceBoxPainter(
              faces: _faces,
              imageSize: _imageSize!,
              rotation: _rotation,
              lensDirection: camera.lensDirection,
            ),
          ),
        _buildHud(camera),
      ],
    );
  }

  Widget _buildHud(CameraDescription camera) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${_faces.length}',
                      style: const TextStyle(
                        color: Color(0xFF35C28B),
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'faces now',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'distinct seen this session: ${_seenTrackingIds.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  'detections/sec: $_detsPerSecond   ·   '
                  'cam: ${camera.lensDirection.name} '
                  '(sensor ${camera.sensorOrientation}°)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  'detect rotation: '
                  '${_rotationOverrideDeg == null ? "auto (${_rotation.rawValue}°)" : "$_rotationOverrideDeg°"}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Privacy: frames are processed on-device and discarded instantly. '
              'No images are stored or sent. Faces are counted, not identified.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps ML Kit face boxes (camera-buffer coords) onto the preview canvas,
/// accounting for rotation and front-camera mirroring. Ported from the
/// google_mlkit example coordinate translator. Best-effort: minor drift is
/// acceptable for this spike — the face COUNT is the validated signal.
class _FaceBoxPainter extends CustomPainter {
  _FaceBoxPainter({
    required this.faces,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final List<Face> faces;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF35C28B);

    for (final face in faces) {
      final box = face.boundingBox;
      final left = _translateX(box.left, size);
      final right = _translateX(box.right, size);
      final top = _translateY(box.top, size);
      final bottom = _translateY(box.bottom, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left < right ? left : right,
            top < bottom ? top : bottom,
            left < right ? right : left,
            top < bottom ? bottom : top,
          ),
          const Radius.circular(8),
        ),
        paint,
      );
    }
  }

  double _translateX(double x, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x * canvasSize.width / imageSize.height;
      case InputImageRotation.rotation270deg:
        return canvasSize.width - x * canvasSize.width / imageSize.height;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        if (lensDirection == CameraLensDirection.back) {
          return x * canvasSize.width / imageSize.width;
        }
        return canvasSize.width - x * canvasSize.width / imageSize.width;
    }
  }

  double _translateY(double y, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * canvasSize.height / imageSize.width;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }

  @override
  bool shouldRepaint(_FaceBoxPainter oldDelegate) =>
      oldDelegate.faces != faces || oldDelegate.imageSize != imageSize;
}
