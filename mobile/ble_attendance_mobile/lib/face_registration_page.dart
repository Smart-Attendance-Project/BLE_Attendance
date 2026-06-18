import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
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
/// detected and captured, generates the embedding, uploads it, and saves it locally.
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
      enableClassification: true,
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
    try {
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
          _statusText = 'Camera error: ${_shortError(e)}';
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

  Future<void> _capture() async {
    if (_processing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
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

      // Decode + auto-orient (applies EXIF rotation so bounding box coords match)
      final rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        setState(() {
          _statusText = 'Failed to process image. Try again.';
          _processing = false;
        });
        return;
      }
      final fullImage = img.bakeOrientation(rawImage);

      final face = faces.first;
      final rect = face.boundingBox;

      // Crop with 20% padding for robust embeddings (matches verification)
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

      if (avgBrightness < 95.0) {
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text(
                'Low Light Warning',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: const Text(
                'IF You are registering in low light. You may face issues during attendance verification. so keep your face in light',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }

      // Generate embedding (includes preprocessing)
      final embedding = _recognizer.getEmbedding(cropped);

      // Upload to server first. Registration/re-registration is intentionally
      // online so the DB remains the source of truth for future logins.
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

      setState(() => _statusText = 'Saving face profile…');

      // Save locally only after server confirms.
      final embStr = await _storage.read(key: 'face_embedding');
      List<List<double>> embeddingsList = [];
      if (embStr != null) {
        final decoded = jsonDecode(embStr);
        if (decoded is List) {
          if (decoded.isNotEmpty && decoded[0] is List) {
            embeddingsList = decoded
                .map((item) => List<double>.from(item as List))
                .toList();
          } else {
            embeddingsList = [List<double>.from(decoded)];
          }
        }
      }

      embeddingsList.add(embedding);
      await _storage.write(
        key: 'face_embedding',
        value: jsonEncode(embeddingsList),
      );
      await _storage.write(key: 'face_registered', value: 'true');

      // Clean up the temp photo file
      try {
        await File(xFile.path).delete();
      } catch (_) {}

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
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      return 'Server error (${e.response?.statusCode ?? '-'})';
    }
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
        title: const Text(
          'Register Face',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _initialising
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : (_cameraController == null)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            )
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
                      // Instruction card overlay at the top
                      Positioned(
                        top: 24,
                        left: 24,
                        right: 24,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(160),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.wb_sunny_rounded,
                                color: Colors.amber,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Keep your face in the oval under good light intensity.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Oval guide overlay
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _OvalOverlayPainter(
                            success: _success,
                            color: _success
                                ? const Color(0xFF16A34A)
                                : cs.primary,
                          ),
                        ),
                      ),
                      // Status text at the bottom of the preview
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
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(_processing ? 'Processing…' : 'Capture Face'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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
