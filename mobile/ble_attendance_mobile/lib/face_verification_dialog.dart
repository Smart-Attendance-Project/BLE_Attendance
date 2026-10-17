import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import 'ml/face_recognizer.dart';
import 'ml/liveness_detector.dart';

// ---------------------------------------------------------------------------
// Verification phases
// ---------------------------------------------------------------------------

enum _Phase { initialising, capturing, result }

// ---------------------------------------------------------------------------
// Main dialog
// ---------------------------------------------------------------------------

/// Full-screen dialog for verifying a student's face during attendance
/// finalisation using passive liveness detection.
///
/// Features:
/// - Real-time camera stream analysis (lighting, face distance, orientation).
/// - Passive natural blink state machine (no complex interactive gestures needed).
/// - Automatic capture upon completed blink cycle.
/// - Secondary still-image texture analysis.
/// - Face embedding comparison against saved profile.
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
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true,
      enableLandmarks: true,
      minFaceSize: 0.25,
    ),
  );
  final FaceRecognizer _recognizer = FaceRecognizer();
  final LivenessDetector _livenessDetector = LivenessDetector();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // State
  _Phase _phase = _Phase.initialising;
  String _statusText = 'Initialising…';
  int _retriesLeft = 3;
  bool _matched = false;
  bool _processing = false;
  List<List<double>>? _savedEmbeddings;

  // Stream state
  bool _isStreamActive = false;
  bool _isProcessingFrame = false;
  bool _isCapturingStill = false;
  LivenessStreamFeedback? _streamFeedback;

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
    _stopImageStream();
    _cam?.dispose();
    _faceDetector.close();
    _recognizer.dispose();
    _livenessDetector.dispose();
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
      await _livenessDetector.init();

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
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _cam!.initialize();

      if (mounted) {
        setState(() {
          _phase = _Phase.capturing;
          _statusText = 'Position your face in the oval';
        });
        _startImageStream();
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
  // Real-time Stream Liveness Engine
  // -----------------------------------------------------------------------

  Future<void> _startImageStream() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_isStreamActive) return;
    _isStreamActive = true;
    _livenessDetector.resetStreamState();

    try {
      await _cam!.startImageStream((CameraImage image) async {
        if (!_isStreamActive ||
            _isProcessingFrame ||
            _isCapturingStill ||
            _processing) {
          return;
        }
        _isProcessingFrame = true;

        try {
          final inputImage = LivenessDetector.inputImageFromCameraImage(
            image: image,
            camera: _cam!.description,
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

          if (mounted && _phase == _Phase.capturing && !_isCapturingStill) {
            setState(() {
              _streamFeedback = feedback;
              _statusText = feedback.message;
            });

            // Automatic capture trigger when passive blink is verified!
            if (feedback.status == LivenessStreamStatus.passed && !_processing) {
              _onLivenessConfirmed();
            }
          }
        } catch (e) {
          debugPrint('[FaceVerificationDialog] Stream error: $e');
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      debugPrint('[FaceVerificationDialog] startImageStream error: $e');
      _isStreamActive = false;
    }
  }

  Future<void> _stopImageStream() async {
    if (!_isStreamActive) return;
    _isStreamActive = false;
    try {
      if (_cam != null && _cam!.value.isInitialized) {
        await _cam!.stopImageStream();
      }
    } catch (e) {
      debugPrint('[FaceVerificationDialog] stopImageStream error: $e');
    }
  }

  // -----------------------------------------------------------------------
  // Capture & Verification Execution
  // -----------------------------------------------------------------------

  Future<void> _onLivenessConfirmed() async {
    if (_processing || _isCapturingStill) return;
    _isCapturingStill = true;

    setState(() {
      _processing = true;
      _statusText = '✅ Blink confirmed! Verifying identity…';
    });

    await _stopImageStream();
    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted || _cam == null || !_cam!.value.isInitialized) {
      _processing = false;
      _isCapturingStill = false;
      return;
    }

    try {
      final xFile = await _cam!.takePicture();
      await _verifyPictureFile(xFile, isPassiveBlinkVerified: true);
    } catch (e) {
      _handleFailedAttempt('Capture error: ${_short(e)}');
    } finally {
      _isCapturingStill = false;
    }
  }

  Future<void> _manualCaptureAndVerify() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_savedEmbeddings == null || _savedEmbeddings!.isEmpty) return;
    if (_processing || _isCapturingStill) return;

    _isCapturingStill = true;
    setState(() {
      _processing = true;
      _statusText = 'Verifying…';
    });

    await _stopImageStream();
    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted || _cam == null || !_cam!.value.isInitialized) {
      _processing = false;
      _isCapturingStill = false;
      return;
    }

    try {
      final xFile = await _cam!.takePicture();
      await _verifyPictureFile(xFile, isPassiveBlinkVerified: false);
    } catch (e) {
      _handleFailedAttempt('Capture error: ${_short(e)}');
    } finally {
      _isCapturingStill = false;
    }
  }

  Future<void> _verifyPictureFile(
    XFile xFile, {
    required bool isPassiveBlinkVerified,
  }) async {
    try {
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

      // Crop with 20% padding for robust embeddings
      final cropped = FaceRecognizer.cropFace(
        fullImage,
        bboxX: rect.left.toInt(),
        bboxY: rect.top.toInt(),
        bboxW: rect.width.toInt(),
        bboxH: rect.height.toInt(),
        padding: 0.2,
      );

      // Crop face strictly for lighting checks
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
      final lightingDiff = lighting['diff']!;

      if (avgBrightness < 80.0) {
        _handleFailedAttempt(
          'Too dark (${avgBrightness.toStringAsFixed(0)}/255). Move to a well-lit area.',
        );
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }

      if (lightingDiff > 75.0) {
        _handleFailedAttempt(
          'Lighting is too uneven. Avoid direct side/backlight.',
        );
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }

      // Secondary still-image texture check
      final face = faces.first;
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

      // If passive blink was not verified in stream (manual tap), require strict still score
      if (!isPassiveBlinkVerified && !stillLiveness.isLive) {
        _handleFailedAttempt(
          'Liveness check failed (${stillLiveness.spoofType}). '
          'Please blink naturally at the camera.',
        );
        try {
          await File(xFile.path).delete();
        } catch (_) {}
        return;
      }

      // Generate embedding and compare
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

      // Resume stream after a brief pause
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _phase == _Phase.capturing && !_processing) {
          _startImageStream();
        }
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

  Color _resolveOverlayColor(ColorScheme cs) {
    if (_matched) return const Color(0xFF16A34A);
    if (_retriesLeft <= 0) return Colors.red;

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
    final progress = _streamFeedback?.progress ?? 0.0;

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
              // Dynamic Oval Overlay with progress arc
              IgnorePointer(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _OvalOverlayPainter(
                    color: overlayColor,
                    progress: progress,
                  ),
                ),
              ),

              // Status card with real-time passive detection hint
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
                      if (_phase == _Phase.capturing && progress > 0.0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(overlayColor),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Top instruction card: explicit blinking guidance
              Positioned(
                top: 16,
                left: 16,
                right: 124,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
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
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Blink Eyes to Verify',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Align in oval & BLINK naturally',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

        // Optional Manual Scan Button (Fallback)
        Padding(
          padding: const EdgeInsets.all(24),
          child: _phase == _Phase.capturing
              ? SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _processing ? null : _manualCaptureAndVerify,
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
                    label: Text(_processing ? 'Verifying…' : 'Scan Face Manually'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Oval overlay painter
// ---------------------------------------------------------------------------

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

    // Dimmed background
    final bgPaint = Paint()..color = Colors.black.withAlpha(130);
    final ovalPath = Path()..addOval(ovalRect);
    final bgPath = Path()
      ..addRect(rect)
      ..addPath(ovalPath, Offset.zero);
    bgPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(bgPath, bgPaint);

    // Main oval border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawOval(ovalRect, borderPaint);

    // Progress arc around the oval
    if (progress > 0.0 && progress < 1.0) {
      final progressPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      // Draw arc sweeping around oval
      final sweepAngle = 2 * pi * progress;
      canvas.drawArc(ovalRect, -pi / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter old) =>
      old.color != color || old.progress != progress;
}
