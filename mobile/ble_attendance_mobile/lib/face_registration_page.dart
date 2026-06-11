import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'ml/face_recognizer.dart';

/// Callback signature for uploading the embedding to the server.
/// Returns `true` if the server accepted it, `false` or throws on failure.
typedef EmbeddingUploader = Future<bool> Function(List<double> embedding);

/// Full-screen page for registering a student's face.
///
/// Opens the front camera, shows an oval guide, and once a single face is
/// detected and captured, generates the embedding, saves it locally **and**
/// uploads it to the server via [onUpload].
class FaceRegistrationPage extends StatefulWidget {
  const FaceRegistrationPage({super.key, required this.onUpload});
  final EmbeddingUploader onUpload;

  @override
  State<FaceRegistrationPage> createState() => _FaceRegistrationPageState();
}

class _FaceRegistrationPageState extends State<FaceRegistrationPage> {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      minFaceSize: 0.3,
    ),
  );
  final FaceRecognizer _recognizer = FaceRecognizer();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _initialising = true;
  bool _processing = false;
  String _statusText = 'Position your face in the oval';
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _recognizer.init();
    final cameras = await availableCameras();
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
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _recognizer.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_processing || _cameraController == null || !_cameraController!.value.isInitialized) return;
    setState(() {
      _processing = true;
      _statusText = 'Detecting face…';
    });

    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Detect faces with ML Kit
      final inputImage = InputImage.fromFilePath(xFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _statusText = 'No face detected. Try again.';
          _processing = false;
        });
        return;
      }
      if (faces.length > 1) {
        setState(() {
          _statusText = 'Multiple faces detected. Only one face allowed.';
          _processing = false;
        });
        return;
      }

      setState(() => _statusText = 'Processing face…');

      // Decode the full image and crop to the face bounding box
      final fullImage = img.decodeImage(bytes);
      if (fullImage == null) {
        setState(() {
          _statusText = 'Failed to process image. Try again.';
          _processing = false;
        });
        return;
      }

      final face = faces.first;
      final rect = face.boundingBox;

      // Clamp the bounding box to image bounds
      final x = rect.left.toInt().clamp(0, fullImage.width - 1);
      final y = rect.top.toInt().clamp(0, fullImage.height - 1);
      final w = rect.width.toInt().clamp(1, fullImage.width - x);
      final h = rect.height.toInt().clamp(1, fullImage.height - y);

      final cropped = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);

      // Generate embedding
      final embedding = _recognizer.getEmbedding(cropped);

      // Upload to server first
      setState(() => _statusText = 'Uploading to server…');
      try {
        final ok = await widget.onUpload(embedding);
        if (!ok) {
          setState(() {
            _statusText = 'Server rejected the registration. Try again.';
            _processing = false;
          });
          return;
        }
      } catch (e) {
        setState(() {
          _statusText = 'Upload failed: ${_shortError(e)}';
          _processing = false;
        });
        return;
      }

      // Save locally after server confirms
      await _storage.write(key: 'face_embedding', value: jsonEncode(embedding));
      await _storage.write(key: 'face_registered', value: 'true');

      // Clean up the temp photo file
      try { await File(xFile.path).delete(); } catch (_) {}

      setState(() {
        _success = true;
        _statusText = '✅ Face registered successfully!';
        _processing = false;
      });

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _statusText = 'Error: ${_shortError(e)}';
        _processing = false;
      });
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Register Face', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _initialising
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Camera preview
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CameraPreview(_cameraController!),
                      ),
                      // Oval guide overlay
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _OvalOverlayPainter(
                            success: _success,
                            color: _success ? const Color(0xFF16A34A) : cs.primary,
                          ),
                        ),
                      ),
                      // Status text at the bottom of the preview
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
                    ],
                  ),
                ),
                // Capture button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _processing || _success ? null : _capture,
                      icon: _processing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(_processing ? 'Processing…' : 'Capture Face'),
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

/// Draws a semi-transparent overlay with an oval cutout in the centre.
class _OvalOverlayPainter extends CustomPainter {
  _OvalOverlayPainter({required this.success, required this.color});
  final bool success;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.65,
      height: size.height * 0.52,
    );

    // Semi-transparent background
    final bgPaint = Paint()..color = Colors.black.withAlpha(120);
    final ovalPath = Path()..addOval(ovalRect);
    final bgPath = Path()
      ..addRect(rect)
      ..addPath(ovalPath, Offset.zero);
    bgPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, bgPaint);

    // Oval border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter old) =>
      old.success != success || old.color != color;
}
