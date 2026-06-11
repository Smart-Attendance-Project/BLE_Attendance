import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'ml/face_recognizer.dart';

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
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.3,
    ),
  );
  final FaceRecognizer _recognizer = FaceRecognizer();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _initialising = true;
  bool _processing = false;
  String _statusText = 'Position your face in the oval';
  int _retriesLeft = 3;
  bool _matched = false;
  List<double>? _savedEmbedding;

  @override
  void initState() {
    super.initState();
    _retriesLeft = widget.maxRetries;
    _init();
  }

  Future<void> _init() async {
    try {
      // Load saved embedding
      final embStr = await _storage.read(key: 'face_embedding');
      if (embStr == null) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      _savedEmbedding = List<double>.from(jsonDecode(embStr) as List);

      await _recognizer.init();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initialising = false;
            _statusText = 'No camera found on this device.';
          });
        }
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _initialising = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialising = false;
          _statusText = 'Camera error: ${e.toString().length > 60 ? e.toString().substring(0, 60) : e}';
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _recognizer.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_processing || _cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_savedEmbedding == null) return;

    setState(() {
      _processing = true;
      _statusText = 'Scanning face…';
    });

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Detect faces
      final inputImage = InputImage.fromFilePath(xFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _retriesLeft--;
        setState(() {
          _statusText = 'No face detected. $_retriesLeft retries left.';
          _processing = false;
        });
        if (_retriesLeft <= 0) _failAndPop();
        // Clean up temp file
        try { await File(xFile.path).delete(); } catch (_) {}
        return;
      }

      // Decode + auto-orient (applies EXIF rotation so bounding box coords match)
      final rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        _retriesLeft--;
        setState(() {
          _statusText = 'Failed to process image. $_retriesLeft retries left.';
          _processing = false;
        });
        if (_retriesLeft <= 0) _failAndPop();
        try { await File(xFile.path).delete(); } catch (_) {}
        return;
      }
      final fullImage = img.bakeOrientation(rawImage);

      final face = faces.first;
      final rect = face.boundingBox;
      final x = rect.left.toInt().clamp(0, fullImage.width - 1);
      final y = rect.top.toInt().clamp(0, fullImage.height - 1);
      final w = rect.width.toInt().clamp(1, fullImage.width - x);
      final h = rect.height.toInt().clamp(1, fullImage.height - y);

      final cropped = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);
      final embedding = _recognizer.getEmbedding(cropped);

      final dist = _recognizer.distance(embedding, _savedEmbedding!);
      final match = _recognizer.isMatch(embedding, _savedEmbedding!);

      // Clean up temp file
      try { await File(xFile.path).delete(); } catch (_) {}

      if (match) {
        setState(() {
          _matched = true;
          _statusText = '✅ Face verified! (distance: ${dist.toStringAsFixed(2)})';
          _processing = false;
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _retriesLeft--;
        setState(() {
          _statusText = 'Face does not match (distance: ${dist.toStringAsFixed(2)}). $_retriesLeft retries left.';
          _processing = false;
        });
        if (_retriesLeft <= 0) _failAndPop();
      }
    } catch (e) {
      _retriesLeft--;
      setState(() {
        _statusText = 'Error: ${e.toString().length > 50 ? e.toString().substring(0, 50) : e}';
        _processing = false;
      });
      if (_retriesLeft <= 0) _failAndPop();
    }
  }

  void _failAndPop() async {
    setState(() => _statusText = '❌ Verification failed. No retries left.');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop(false);
  }

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
        title: const Text('Verify Face', style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _initialising
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : (_cameraController == null)
              ? Center(
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
                )
              : Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CameraPreview(_cameraController!),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _OvalOverlayPainter(
                            color: overlayColor,
                          ),
                        ),
                      ),
                      // Status text
                      Positioned(
                        bottom: 24,
                        left: 24,
                        right: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(160),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      // Retries indicator
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(160),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Retries: $_retriesLeft',
                            style: TextStyle(
                              color: _retriesLeft <= 1 ? Colors.red.shade300 : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _processing || _matched || _retriesLeft <= 0 ? null : _verify,
                      icon: _processing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.face_rounded),
                      label: Text(_processing ? 'Verifying…' : 'Scan Face'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Oval overlay painter (shared style with registration page).
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
