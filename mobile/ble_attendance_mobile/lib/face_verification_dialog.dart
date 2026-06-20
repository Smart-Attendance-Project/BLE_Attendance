import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'ml/face_recognizer.dart';

// ---------------------------------------------------------------------------
// Verification phases
// ---------------------------------------------------------------------------

enum _Phase { initialising, capturing, result }

// ---------------------------------------------------------------------------
// Main dialog
// ---------------------------------------------------------------------------

/// Full-screen dialog for verifying a student's face during attendance
/// finalisation.
///
/// Opens the front camera, captures and compares against the saved embedding.
/// Allows up to [maxRetries] attempts. Returns `true` on a successful match.
class FaceVerificationDialog extends StatefulWidget {
  const FaceVerificationDialog({super.key, this.maxRetries = 3});
  final int maxRetries;

  @override
  State<FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends State<FaceVerificationDialog> {
  // Camera & ML
  CameraController? _cam;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
      enableLandmarks: true,
      minFaceSize: 0.3,
    ),
  );
  final FaceRecognizer _recognizer = FaceRecognizer();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // State
  _Phase _phase = _Phase.initialising;
  String _statusText = 'Initialising…';
  int _retriesLeft = 3;
  bool _matched = false;
  bool _processing = false;
  List<List<double>>? _savedEmbeddings;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _retriesLeft = widget.maxRetries;
    _init();
  }

  @override
  void dispose() {
    _cam?.dispose();
    _faceDetector.close();
    _recognizer.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Initialisation
  // -----------------------------------------------------------------------

  Future<void> _init() async {
    try {
      final embStr = await _storage.read(key: 'face_embedding');
      if (embStr == null) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      final decoded = jsonDecode(embStr);
      List<List<double>> embeddingsList = [];
      if (decoded is List) {
        if (decoded.isNotEmpty) {
          if (decoded[0] is List) {
            embeddingsList = decoded
                .map((item) => List<double>.from(item as List))
                .toList();
          } else {
            embeddingsList = [List<double>.from(decoded)];
          }
        }
      }
      _savedEmbeddings = embeddingsList;

      await _recognizer.init();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _phase = _Phase.result;
            _statusText = 'No camera found on this device.';
          });
        }
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cam = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cam!.initialize();

      if (mounted) {
        setState(() {
          _phase = _Phase.capturing;
          _statusText = 'Position your face in the oval and tap Scan Face';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.result;
          _statusText = 'Camera error: ${_short(e)}';
        });
      }
    }
  }

  // -----------------------------------------------------------------------
  // Capture + embedding verification
  // -----------------------------------------------------------------------

  Future<void> _captureAndVerify() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_savedEmbeddings == null || _savedEmbeddings!.isEmpty) return;
    if (_processing) return;

    setState(() {
      _processing = true;
      _statusText = 'Verifying…';
    });

    try {
      final xFile = await _cam!.takePicture();
      final bytes = await xFile.readAsBytes();

      final inputImage = InputImage.fromFilePath(xFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _handleFailedAttempt('No face detected during capture.');
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }

      final rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        _handleFailedAttempt('Failed to process image.');
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }
      final fullImage = img.bakeOrientation(rawImage);
      final rect = faces.first.boundingBox;

      // Crop with 20 % padding for robust embeddings
      final cropped = FaceRecognizer.cropFace(
        fullImage,
        bboxX: rect.left.toInt(),
        bboxY: rect.top.toInt(),
        bboxW: rect.width.toInt(),
        bboxH: rect.height.toInt(),
        padding: 0.2,
      );

      // Crop face region without padding strictly for lighting checks (ignores background)
      final faceOnly = FaceRecognizer.cropFace(
        fullImage,
        bboxX: rect.left.toInt(),
        bboxY: rect.top.toInt(),
        bboxW: rect.width.toInt(),
        bboxH: rect.height.toInt(),
        padding: 0.0,
      );

      // Analyze face lighting (brightness & evenness)
      final lighting = FaceRecognizer.analyzeFaceLighting(faceOnly);
      final avgBrightness = lighting['avg']!;
      final lightingDiff = lighting['diff']!;

      if (avgBrightness < 95.0) {
        _handleFailedAttempt(
          'Too dark (${avgBrightness.toStringAsFixed(0)}/255). Move to a well-lit area.',
        );
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }

      if (lightingDiff > 65.0) {
        _handleFailedAttempt(
          'Lighting is too uneven. Avoid direct side/backlight.',
        );
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }

      final embedding = _recognizer.getEmbedding(cropped);

      bool match = false;
      double bestDist = 999.0;

      if (_savedEmbeddings != null) {
        for (final saved in _savedEmbeddings!) {
          final dist = _recognizer.distance(embedding, saved);
          if (dist < bestDist) {
            bestDist = dist;
          }
          if (_recognizer.isMatch(embedding, saved)) {
            match = true;
          }
        }
      }

      try {
        await File(xFile.path).delete();
      } catch (_) {}

      if (match) {
        setState(() {
          _matched = true;
          _phase = _Phase.result;
          _statusText =
              '✅ Face verified! (distance: ${bestDist.toStringAsFixed(2)})';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _handleFailedAttempt(
          'Face does not match (distance: ${bestDist.toStringAsFixed(2)}).',
        );
      }
    } catch (e) {
      _handleFailedAttempt('Error: ${_short(e)}');
    }
  }

  void _handleFailedAttempt(String message) {
    _retriesLeft--;
    if (_retriesLeft <= 0) {
      setState(() {
        _phase = _Phase.result;
        _processing = false;
        _statusText = '❌ Verification failed. No retries left.';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop(false);
      });
    } else {
      setState(() {
        _phase = _Phase.capturing;
        _processing = false;
        _statusText = '$message\nRetries left: $_retriesLeft — try again.';
      });
    }
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  // -----------------------------------------------------------------------
  // Build UI
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overlayColor = _matched
        ? const Color(0xFF16A34A)
        : (_retriesLeft <= 0 ? Colors.red : cs.primary);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Verify Face',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _phase == _Phase.initialising
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : (_cam == null)
          ? _buildErrorBody()
          : _buildCameraBody(overlayColor),
    );
  }

  Widget _buildErrorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 16),
            Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBody(Color overlayColor) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CameraPreview(_cam!),
              ),
              // Oval overlay
              IgnorePointer(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _OvalOverlayPainter(color: overlayColor),
                ),
              ),

              // Status text
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // Retries indicator
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Retries: $_retriesLeft',
                    style: TextStyle(
                      color: _retriesLeft <= 1
                          ? Colors.red.shade300
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Scan Face button
        Padding(
          padding: const EdgeInsets.all(24),
          child: _phase == _Phase.capturing
              ? FilledButton.icon(
                  onPressed: _processing ? null : _captureAndVerify,
                  icon: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.face_rounded),
                  label: Text(_processing ? 'Verifying…' : 'Scan Face'),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Oval overlay painter (shared style with registration page).
// ---------------------------------------------------------------------------

class _OvalOverlayPainter extends CustomPainter {
  _OvalOverlayPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.65,
      height: size.height * 0.52,
    );

    final bgPaint = Paint()..color = Colors.black.withAlpha(120);
    final ovalPath = Path()..addOval(ovalRect);
    final bgPath = Path()
      ..addRect(rect)
      ..addPath(ovalPath, Offset.zero);
    bgPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, bgPaint);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter old) => old.color != color;
}
