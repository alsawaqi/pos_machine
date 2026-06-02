import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner for the device activation code. Pops with the scanned
/// string, or null if the user backs out / can't scan.
///
/// Sunmi dual-screen POS terminals (e.g. T3) usually expose only a FRONT
/// (customer-facing) camera, while mobile_scanner defaults to the rear one —
/// which surfaces as "no camera available". So we default to the front camera
/// and offer a switch-camera control; if the camera still can't start, the real
/// error is shown with a "enter manually" escape hatch.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.front,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (_) {
      // Single-camera device — nothing to switch to.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: const Text('Scan activation code'),
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(
              error: error,
              onManual: () => Navigator.of(context).pop(),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Text(
              "Point the camera at the activation QR code. If it doesn't open, tap the switch-camera icon, or go back and enter the code manually.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error, required this.onManual});

  final MobileScannerException error;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final detail = error.errorDetails?.message;
    final message = (detail != null && detail.isNotEmpty)
        ? detail
        : 'Could not start the camera (${error.errorCode.name}).';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                'Try the switch-camera icon above, use the device scanner, or enter the code manually.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onManual,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: const Text('Enter the code manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
