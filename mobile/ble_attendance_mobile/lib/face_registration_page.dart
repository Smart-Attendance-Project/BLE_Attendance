import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'ml/face_recognizer.dart';
import 'ml/liveness_detector.dart';

/// Callback signature for uploading the embedding to the server.
/// Returns `true` if the server accepted it, `false` or throws on failure.
typedef EmbeddingUploader = Future<bool> Function(List<double> embedding);

/// Full-screen page for registering a student's face using passive liveness
/// detection.
///
/// Features:
/// - Real-time camera stream analysis (distance, orientation, lighting).
/// - Passive natural blink state machine (no gestures needed).
/// - Automatic capture upon completed blink cycle.
/// - Uploads 192-d embedding to backend and caches locally upon confirmation.
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
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true,
      enableLandmarks: true,
      minFaceSize: 0.25,
    ),
  );
  final FaceRecognizer _recognizer = FaceRecognizer();
  final LivenessDetector _livenessDetector = LivenessDetector();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _initialising = true;
  bool _processing = false;
  String _statusText = 'Position your face in the oval';
  bool _success = false;

  // Stream state
  bool _isStreamActive = false;
  bool _isProcessingFrame = false;
  bool _isCapturingStill = false;
  LivenessStreamFeedback? _streamFeedback;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _recognizer.init();
      await _livenessDetector.init();
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

      if (mounted) {
        setState(() => _initialising = false);
        _startImageStream();
      }
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
    _stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    _recognizer.dispose();
    _livenessDetector.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Real-time Stream Liveness Engine
  // -----------------------------------------------------------------------

  Future<void> _startImageStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_isStreamActive) return;
    _isStreamActive = true;
    _livenessDetector.resetStreamState();

    try {
      await _cameraController!.startImageStream((CameraImage image) async {
        if (!_isStreamActive ||
            _isProcessingFrame ||
            _isCapturingStill ||
            _processing ||
            _success) {
          return;
        }
        _isProcessingFrame = true;

        try {
          final inputImage = LivenessDetector.inputImageFromCameraImage(
            image: image,
            camera: _cameraController!.description,
          );
          if (inputImage == null) return;

          final luminance = LivenessDetector.calculateLuminance(image);
          final faces = await _faceDetector.processImage(inputImage);

          final feedback = _livenessDetector.processStreamFrame(
            faces: faces,
            imageWidth: image.width,
            imageHeight: image.height,
            luminance: luminance,
          );

          if (mounted && !_isCapturingStill && !_success) {
            setState(() {
              _streamFeedback = feedback;
              _statusText = feedback.message;
            });

            // Automatic registration capture on natural blink!
            if (feedback.status == LivenessStreamStatus.passed && !_processing) {
              _onPassiveBlinkConfirmed();
            }
          }
        } catch (e) {
          debugPrint('[FaceRegistrationPage] Stream frame error: $e');
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      debugPrint('[FaceRegistrationPage] startImageStream error: $e');
      _isStreamActive = false;
    }
  }

  Future<void> _stopImageStream() async {
    if (!_isStreamActive) return;
    _isStreamActive = false;
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('[FaceRegistrationPage] stopImageStream error: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Capture & Registration Flow
  // -----------------------------------------------------------------------

  Future<void> _onPassiveBlinkConfirmed() async {
    if (_processing || _isCapturingStill || _success) return;
    _isCapturingStill = true;

    setState(() {
      _processing = true;
      _statusText = '✅ Blink confirmed! Capturing face profile…';
    });

    await _stopImageStream();
    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      _processing = false;
      _isCapturingStill = false;
      return;
    }

    try {
      final xFile = await _cameraController!.takePicture();
      await _processRegistrationPicture(xFile, isPassiveBlinkVerified: true);
    } catch (e) {
      setState(() {
        _statusText = 'Capture error: ${_shortError(e)}';
        _processing = false;
      });
      _resumeStreamDelayed();
    } finally {
      _isCapturingStill = false;
    }
  }

  Future<void> _manualCapture() async {
    if (_processing ||
        _isCapturingStill ||
        _success ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _isCapturingStill = true;
    setState(() {
      _processing = true;
      _statusText = 'Detecting face…';
    });

    await _stopImageStream();
    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      _processing = false;
      _isCapturingStill = false;
      return;
    }

    try {
      final xFile = await _cameraController!.takePicture();
      await _processRegistrationPicture(xFile, isPassiveBlinkVerified: false);
    } catch (e) {
      setState(() {
        _statusText = 'Capture error: ${_shortError(e)}';
        _processing = false;
      });
      _resumeStreamDelayed();
    } finally {
      _isCapturingStill = false;
    }
  }

  Future<void> _processRegistrationPicture(
    XFile xFile, {
    required bool isPassiveBlinkVerified,
  }) async {
    try {
      final bytes = await xFile.readAsBytes();
      final inputImage = InputImage.fromFilePath(xFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _statusText = 'No face detected. Try again.';
          _processing = false;
        });
        _resumeStreamDelayed();
        return;
      }
      if (faces.length > 1) {
        setState(() {
          _statusText = 'Multiple faces detected. Only one face allowed.';
          _processing = false;
        });
        _resumeStreamDelayed();
        return;
      }

      final rawImage = img.decodeImage(bytes);
      if (rawImage == null) {
        setState(() {
          _statusText = 'Failed to process image. Try again.';
          _processing = false;
        });
        _resumeStreamDelayed();
        return;
      }
      final fullImage = img.bakeOrientation(rawImage);
      final face = faces.first;
      final rect = face.boundingBox;

      // Crop with 20% padding for robust embeddings
      final cropped = FaceRecognizer.cropFace(
        fullImage,
        bboxX: rect.left.toInt(),
        bboxY: rect.top.toInt(),
        bboxW: rect.width.toInt(),
        bboxH: rect.height.toInt(),
        padding: 0.2,
      );

      // Analyze face lighting
      final faceOnly = FaceRecognizer.cropFace(
        fullImage,
        bboxX: rect.left.toInt(),
        bboxY: rect.top.toInt(),
        bboxW: rect.width.toInt(),
        bboxH: rect.height.toInt(),
        padding: 0.0,
      );

      final lighting = FaceRecognizer.analyzeFaceLighting(faceOnly);
      final avgBrightness = lighting['avg']!;

      if (avgBrightness < 80.0 && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text(
              'Low Light Warning',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'You are registering in low light. This may cause issues during attendance verification. Please keep your face well-lit.',
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

      // Secondary liveness check
      final stillLiveness = _livenessDetector.check(
        fullImage,
        bboxX: rect.left.toInt(),
        bboxY: rect.top.toInt(),
        bboxW: rect.width.toInt(),
        bboxH: rect.height.toInt(),
        leftEyeOpenProbability: face.leftEyeOpenProbability,
        rightEyeOpenProbability: face.rightEyeOpenProbability,
        headEulerAngleY: face.headEulerAngleY,
        headEulerAngleZ: face.headEulerAngleZ,
      );

      if (!isPassiveBlinkVerified && !stillLiveness.isLive) {
        setState(() {
          _statusText =
              'Liveness check failed (${stillLiveness.spoofType}). '
              'Please blink naturally at the camera.';
          _processing = false;
        });
        _resumeStreamDelayed();
        return;
      }

      // Generate embedding
      setState(() => _statusText = 'Generating biometric embedding…');
      final embedding = _recognizer.getEmbedding(cropped);

      // Upload to server
      setState(() => _statusText = 'Uploading to server…');
      try {
        final ok = await widget.onUpload(embedding);
        if (!ok) {
          setState(() {
            _statusText = 'Server rejected the registration. Try again.';
            _processing = false;
          });
          _resumeStreamDelayed();
          return;
        }
      } catch (e) {
        setState(() {
          _statusText = 'Upload failed: ${_shortError(e)}';
          _processing = false;
        });
        _resumeStreamDelayed();
        return;
      }

      // Save locally
      setState(() => _statusText = 'Saving face profile locally…');
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
      _resumeStreamDelayed();
    }
  }

  void _resumeStreamDelayed() {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && !_success && !_processing) {
        _startImageStream();
      }
    });
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

  Color _resolveOverlayColor(ColorScheme cs) {
    if (_success) return const Color(0xFF16A34A);

    final fb = _streamFeedback;
    if (fb == null) return Colors.white54;

    switch (fb.status) {
      case LivenessStreamStatus.passed:
        return const Color(0xFF16A34A);
      case LivenessStreamStatus.blinkInProgress:
        return Colors.cyanAccent;
      case LivenessStreamStatus.faceReady:
        return Colors.lightBlueAccent;
      case LivenessStreamStatus.tooFar:
      case LivenessStreamStatus.tooClose:
      case LivenessStreamStatus.lookStraight:
      case LivenessStreamStatus.tiltHead:
      case LivenessStreamStatus.offCenter:
        return Colors.amber;
      case LivenessStreamStatus.noFace:
        return Colors.white54;
      case LivenessStreamStatus.multipleFaces:
      case LivenessStreamStatus.tooDark:
      case LivenessStreamStatus.tooBright:
        return Colors.redAccent;
      case LivenessStreamStatus.initialising:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final overlayColor = _resolveOverlayColor(cs);
    final progress = _streamFeedback?.progress ?? 0.0;

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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CameraPreview(_cameraController!),
                          ),
                          // Top blinking instruction card
                          Positioned(
                            top: 24,
                            left: 24,
                            right: 24,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(190),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.amber.withAlpha(180),
                                  width: 1.2,
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.remove_red_eye_rounded,
                                    color: Colors.amber,
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Blink Eyes to Register',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Align in oval & BLINK naturally to capture automatically.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Dynamic Oval Guide Overlay
                          IgnorePointer(
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _OvalOverlayPainter(
                                color: overlayColor,
                                progress: progress,
                              ),
                            ),
                          ),

                          // Bottom status card with progress bar
                          Positioned(
                            bottom: 24,
                            left: 24,
                            right: 24,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(180),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: overlayColor.withAlpha(120),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _statusText,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (!_success && progress > 0.0) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: Colors.white24,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          overlayColor,
                                        ),
                                        minHeight: 4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Manual Capture Button (Fallback)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _processing || _success ? null : _manualCapture,
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
                          label: Text(
                            _processing ? 'Processing…' : 'Capture Face Manually',
                          ),
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

class _OvalOverlayPainter extends CustomPainter {
  _OvalOverlayPainter({
    required this.color,
    this.progress = 0.0,
  });

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.65,
      height: size.height * 0.52,
    );

    final bgPaint = Paint()..color = Colors.black.withAlpha(130);
    final ovalPath = Path()..addOval(ovalRect);
    final bgPath = Path()
      ..addRect(rect)
      ..addPath(ovalPath, Offset.zero);
    bgPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, bgPaint);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawOval(ovalRect, borderPaint);

    if (progress > 0.0 && progress < 1.0) {
      final progressPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * pi * progress;
      canvas.drawArc(ovalRect, -pi / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter old) =>
      old.color != color || old.progress != progress;
}
