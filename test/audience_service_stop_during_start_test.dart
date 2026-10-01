// LAUNCH-P1 device finding (T3, 2026-10-01): a 401 right after launch closed
// the POS screen while the audience camera was still opening. stop() found
// nothing to stop, the start finished afterwards, and the customer camera plus
// face detection kept running behind the activation screen (~250% CPU) until
// the app was restarted.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pos_machine/services/audience_service.dart';

const _detectorChannel = MethodChannel('google_mlkit_face_detector');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCamera camera;
  var detectorsClosed = 0;

  setUp(() {
    camera = _FakeCamera();
    CameraPlatform.instance = camera;
    PermissionHandlerPlatform.instance = _GrantedPermissions();
    detectorsClosed = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_detectorChannel, (call) async {
          if (call.method == 'vision#closeFaceDetector') detectorsClosed++;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_detectorChannel, null);
  });

  test('a normal start streams frames and stop releases everything', () async {
    final audience = AudienceService();
    await audience.start();
    expect(audience.running, isTrue);
    expect(camera.streaming, isTrue);

    await audience.stop();
    expect(audience.running, isFalse);
    expect(camera.streaming, isFalse);
    expect(camera.disposed, [1]);
    expect(detectorsClosed, 1);
  });

  test(
    'stop while the camera list is loading: the camera never opens',
    () async {
      final audience = AudienceService();
      camera.camerasGate = Completer<void>();
      final starting = audience.start();
      await _settle();

      await audience.stop();
      camera.camerasGate!.complete();
      await starting;

      expect(camera.created, 0);
      expect(camera.streaming, isFalse);
      expect(audience.running, isFalse);
    },
  );

  test(
    'stop while the camera initialises: it is released, never streamed',
    () async {
      final audience = AudienceService();
      camera.initializeGate = Completer<void>();
      final starting = audience.start();
      await _settle();
      expect(camera.created, 1);

      await audience.stop();
      camera.initializeGate!.complete();
      await starting;

      expect(camera.streamStarts, 0);
      expect(camera.streaming, isFalse);
      expect(camera.disposed, [1]);
      expect(detectorsClosed, 1);
      expect(audience.running, isFalse);
    },
  );

  test(
    'after a cancelled start, the next start opens the camera again',
    () async {
      final audience = AudienceService();
      camera.initializeGate = Completer<void>();
      final starting = audience.start();
      await _settle();
      await audience.stop();
      camera.initializeGate!.complete();
      await starting;

      camera.initializeGate = null;
      await audience.start();
      expect(audience.running, isTrue);
      expect(camera.streaming, isTrue);
      await audience.stop();
    },
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _GrantedPermissions extends PermissionHandlerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {for (final p in permissions) p: PermissionStatus.granted};
}

class _FakeCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  Completer<void>? camerasGate;
  Completer<void>? initializeGate;
  int created = 0;
  int streamStarts = 0;
  final disposed = <int>[];
  StreamController<CameraImageData>? _frames;
  bool get streaming => _frames?.hasListener ?? false;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    await camerasGate?.future;
    return const [
      CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
    ];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async => ++created;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializeGate?.future;
  }

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    streamStarts++;
    _frames = StreamController<CameraImageData>();
    return _frames!.stream;
  }

  @override
  Future<void> dispose(int cameraId) async => disposed.add(cameraId);
}
