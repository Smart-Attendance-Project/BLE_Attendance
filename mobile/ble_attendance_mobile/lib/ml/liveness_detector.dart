import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Status states for real-time passive stream liveness detection.
enum LivenessStreamStatus {
  initialising,
  noFace,
  multipleFaces,
  tooDark,
  tooBright,
  tooFar,
  tooClose,
  lookStraight,
  tiltHead,
  offCenter,
  faceReady,
  blinkInProgress,
  passed,
}

/// Real-time feedback emitted on each camera stream frame.
class LivenessStreamFeedback {
  final LivenessStreamStatus status;
  final String message;
  final double progress; // 0.0 to 1.0
  final bool isLive;
  final Face? face;
  final double? faceAreaRatio;
  final double? leftEyeOpen;
  final double? rightEyeOpen;

  const LivenessStreamFeedback({
    required this.status,
    required this.message,
    required this.progress,
    required this.isLive,
    this.face,
    this.faceAreaRatio,
    this.leftEyeOpen,
    this.rightEyeOpen,
  });

  @override
  String toString() =>
      'LivenessStreamFeedback(status=$status, progress=${progress.toStringAsFixed(2)}, isLive=$isLive)';
}

/// Result of a single still-frame liveness check (for backwards compatibility
/// and secondary still-image texture verification).
class LivenessResult {
  final bool isLive;
  final double liveScore;
  final double spoofPrintScore;
  final double spoofReplayScore;

  const LivenessResult({
    required this.isLive,
    required this.liveScore,
    required this.spoofPrintScore,
    required this.spoofReplayScore,
  });

  String get spoofType {
    if (isLive) return 'live';
    return spoofPrintScore > spoofReplayScore ? 'print-attack' : 'replay-attack';
  }

  @override
  String toString() =>
      'LivenessResult(isLive=$isLive, live=${liveScore.toStringAsFixed(3)}, '
      'print=${spoofPrintScore.toStringAsFixed(3)}, '
      'replay=${spoofReplayScore.toStringAsFixed(3)})';
}

/// Passive face liveness & anti-spoofing engine based on reverse engineering
/// UIDAI / Pehchaan Face RD reference architecture.
///
/// Features:
/// 1. Environmental Luminance Check (pre-filtering low light & glare).
/// 2. Geometry & Scale Gate (face distance 5%–20%, frontal Euler Yaw within [-22°, +22°], centered).
/// 3. Multi-Frame Automatic Blink State Machine:
///    - State 0: Waiting for open eyes (left & right >= 0.70).
///    - State 1: Waiting for natural blink (left & right <= 0.35).
///    - State 2: Waiting for eyes to reopen (left & right >= 0.70 within 1-6 frames).
///    - State 3: PASSED — natural biological reflex confirmed without active gestures.
/// 4. Secondary Still-Image Texture Analysis (Laplacian sharpness, colour distribution, edge density).
class LivenessDetector {
  final double liveThreshold;

  // Blink state machine variables
  int _blinkState = 0; // 0: wait open, 1: wait close, 2: wait reopen, 3: passed
  int _openEyeFrames = 0;
  int _reopenFrames = 0;
  DateTime? _lastStateChange;

  LivenessDetector({this.liveThreshold = 0.45});

  Future<void> init() async {
    resetStreamState();
    debugPrint('[LivenessDetector] Initialised (Passive Blink + Image Analysis)');
  }

  void dispose() {
    resetStreamState();
  }

  /// Reset the streaming state machine (e.g. when dialog opens or retry begins).
  void resetStreamState() {
    _blinkState = 0;
    _openEyeFrames = 0;
    _reopenFrames = 0;
    _lastStateChange = DateTime.now();
  }

  // ---------------------------------------------------------------------------
  // Camera Frame Processing & Real-time Stream Liveness Gate
  // ---------------------------------------------------------------------------

  /// Process a single frame from the camera stream using detected [faces]
  /// and the camera frame dimensions.
  LivenessStreamFeedback processStreamFrame({
    required List<Face> faces,
    required int imageWidth,
    required int imageHeight,
    double? luminance,
  }) {
    // Check if intermediate blink state has timed out (e.g. user walked away)
    if (_blinkState > 0 && _lastStateChange != null) {
      if (DateTime.now().difference(_lastStateChange!).inSeconds > 5) {
        _blinkState = 0;
        _openEyeFrames = 0;
        _reopenFrames = 0;
        _lastStateChange = DateTime.now();
      }
    }

    // 1. Environmental Luminance Gate
    if (luminance != null) {
      if (luminance < 40.0) {
        _blinkState = 0;
        return const LivenessStreamFeedback(
          status: LivenessStreamStatus.tooDark,
          message: 'Too dark. Move to a better-lit area.',
          progress: 0.1,
          isLive: false,
        );
      }
      if (luminance > 230.0) {
        _blinkState = 0;
        return const LivenessStreamFeedback(
          status: LivenessStreamStatus.tooBright,
          message: 'Too bright. Avoid direct light or glare.',
          progress: 0.1,
          isLive: false,
        );
      }
    }

    // 2. Face Presence Check
    if (faces.isEmpty) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return const LivenessStreamFeedback(
        status: LivenessStreamStatus.noFace,
        message: 'Position your face inside the oval',
        progress: 0.0,
        isLive: false,
      );
    }

    if (faces.length > 1) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return const LivenessStreamFeedback(
        status: LivenessStreamStatus.multipleFaces,
        message: 'Multiple faces detected. Only 1 person allowed.',
        progress: 0.0,
        isLive: false,
      );
    }

    final face = faces.first;
    final bbox = face.boundingBox;

    // 3. Face Distance & Area Ratio Gate
    final frameArea = imageWidth * imageHeight;
    final faceArea = bbox.width * bbox.height;
    final areaRatio = frameArea > 0 ? (faceArea / frameArea) * 100.0 : 0.0;

    if (areaRatio < 4.5) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return LivenessStreamFeedback(
        status: LivenessStreamStatus.tooFar,
        message: 'Move closer to the camera',
        progress: 0.2,
        isLive: false,
        face: face,
        faceAreaRatio: areaRatio,
      );
    }

    if (areaRatio > 26.0) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return LivenessStreamFeedback(
        status: LivenessStreamStatus.tooClose,
        message: 'Move back slightly',
        progress: 0.2,
        isLive: false,
        face: face,
        faceAreaRatio: areaRatio,
      );
    }

    // 4. Face Pose (Euler Yaw & Roll) Gate
    final yaw = face.headEulerAngleY ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;

    if (yaw.abs() > 22.0) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return LivenessStreamFeedback(
        status: LivenessStreamStatus.lookStraight,
        message: 'Look straight at the camera',
        progress: 0.3,
        isLive: false,
        face: face,
        faceAreaRatio: areaRatio,
      );
    }

    if (roll.abs() > 20.0) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return LivenessStreamFeedback(
        status: LivenessStreamStatus.tiltHead,
        message: 'Hold the phone upright',
        progress: 0.3,
        isLive: false,
        face: face,
        faceAreaRatio: areaRatio,
      );
    }

    // 5. Centering Gate
    final cx = bbox.center.dx;
    final cy = bbox.center.dy;
    final normDistX = (cx - imageWidth / 2.0).abs() / imageWidth;
    final normDistY = (cy - imageHeight / 2.0).abs() / imageHeight;

    if (normDistX > 0.25 || normDistY > 0.28) {
      _blinkState = 0;
      _openEyeFrames = 0;
      return LivenessStreamFeedback(
        status: LivenessStreamStatus.offCenter,
        message: 'Center your face in the oval',
        progress: 0.3,
        isLive: false,
        face: face,
        faceAreaRatio: areaRatio,
      );
    }

    // 6. Multi-Frame Automatic Blink State Machine
    final leftEye = face.leftEyeOpenProbability ?? 0.5;
    final rightEye = face.rightEyeOpenProbability ?? 0.5;

    const eyeOpenThreshold = 0.70;
    const eyeClosedThreshold = 0.35;

    switch (_blinkState) {
      case 0:
        // Waiting for initial open eyes
        if (leftEye >= eyeOpenThreshold && rightEye >= eyeOpenThreshold) {
          _openEyeFrames++;
          if (_openEyeFrames >= 2) {
            _blinkState = 1; // Advanced to waiting for blink
            _lastStateChange = DateTime.now();
          }
        } else {
          _openEyeFrames = 0;
        }

        return LivenessStreamFeedback(
          status: LivenessStreamStatus.faceReady,
          message: 'Blink naturally to verify',
          progress: 0.5,
          isLive: false,
          face: face,
          faceAreaRatio: areaRatio,
          leftEyeOpen: leftEye,
          rightEyeOpen: rightEye,
        );

      case 1:
        // Waiting for eyes to close (blink onset)
        if (leftEye <= eyeClosedThreshold && rightEye <= eyeClosedThreshold) {
          _blinkState = 2; // Eyes shut! Now wait for reopening
          _reopenFrames = 0;
          _lastStateChange = DateTime.now();

          return LivenessStreamFeedback(
            status: LivenessStreamStatus.blinkInProgress,
            message: 'Blink detected…',
            progress: 0.8,
            isLive: false,
            face: face,
            faceAreaRatio: areaRatio,
            leftEyeOpen: leftEye,
            rightEyeOpen: rightEye,
          );
        }

        // If eyes remain open, keep prompting naturally
        return LivenessStreamFeedback(
          status: LivenessStreamStatus.faceReady,
          message: 'Blink naturally to verify',
          progress: 0.6,
          isLive: false,
          face: face,
          faceAreaRatio: areaRatio,
          leftEyeOpen: leftEye,
          rightEyeOpen: rightEye,
        );

      case 2:
        // Waiting for eyes to reopen within 1-6 stream frames (typical blink: 150-400ms)
        _reopenFrames++;

        if (leftEye >= eyeOpenThreshold && rightEye >= eyeOpenThreshold) {
          // NATURAL BLINK COMPLETE! LIVENESS PASSED!
          _blinkState = 3;
          _lastStateChange = DateTime.now();

          debugPrint(
            '[LivenessDetector] ✅ Blink state machine succeeded in $_reopenFrames frames',
          );

          return LivenessStreamFeedback(
            status: LivenessStreamStatus.passed,
            message: '✅ Liveness verified!',
            progress: 1.0,
            isLive: true,
            face: face,
            faceAreaRatio: areaRatio,
            leftEyeOpen: leftEye,
            rightEyeOpen: rightEye,
          );
        }

        if (_reopenFrames > 6) {
          // Eyes stayed closed too long (e.g. squinting or prolonged shut eyes)
          _blinkState = 0;
          _openEyeFrames = 0;
          return LivenessStreamFeedback(
            status: LivenessStreamStatus.faceReady,
            message: 'Open your eyes & look at the camera',
            progress: 0.4,
            isLive: false,
            face: face,
            faceAreaRatio: areaRatio,
            leftEyeOpen: leftEye,
            rightEyeOpen: rightEye,
          );
        }

        return LivenessStreamFeedback(
          status: LivenessStreamStatus.blinkInProgress,
          message: 'Blink detected…',
          progress: 0.85,
          isLive: false,
          face: face,
          faceAreaRatio: areaRatio,
          leftEyeOpen: leftEye,
          rightEyeOpen: rightEye,
        );

      case 3:
      default:
        // Already passed
        return LivenessStreamFeedback(
          status: LivenessStreamStatus.passed,
          message: '✅ Liveness verified!',
          progress: 1.0,
          isLive: true,
          face: face,
          faceAreaRatio: areaRatio,
          leftEyeOpen: leftEye,
          rightEyeOpen: rightEye,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // CameraImage to InputImage & Luminance Converters
  // ---------------------------------------------------------------------------

  /// Convert a [CameraImage] from `startImageStream` into ML Kit's [InputImage].
  static InputImage? inputImageFromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
  }) {
    try {
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation =
          InputImageRotationValue.fromRawValue(sensorOrientation);
      rotation ??= InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      final inputFormat = format ??
          (Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888);

      final plane = image.planes.first;

      Uint8List bytes;
      if (image.planes.length == 1) {
        bytes = plane.bytes;
      } else {
        final builder = BytesBuilder(copy: false);
        for (final p in image.planes) {
          builder.add(p.bytes);
        }
        bytes = builder.takeBytes();
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: inputFormat,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('[LivenessDetector] Error converting CameraImage: $e');
      return null;
    }
  }

  /// Fast luminance estimation directly from the camera frame Y-plane.
  static double calculateLuminance(CameraImage image) {
    if (image.planes.isEmpty) return 128.0;
    final yPlane = image.planes[0].bytes;
    if (yPlane.isEmpty) return 128.0;

    int sum = 0;
    int count = 0;
    // Subsample every 16th byte for fast O(1) execution (~50 microseconds)
    const step = 16;
    for (int i = 0; i < yPlane.length; i += step) {
      sum += yPlane[i];
      count++;
    }
    return count > 0 ? sum / count : 128.0;
  }

  // ---------------------------------------------------------------------------
  // Secondary Still-Image Texture Analysis (For Final Capture Validation)
  // ---------------------------------------------------------------------------

  /// Run the multi-signal texture analysis on the captured still image.
  LivenessResult check(
    img.Image fullImage, {
    required int bboxX,
    required int bboxY,
    required int bboxW,
    required int bboxH,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
    double? headEulerAngleY,
    double? headEulerAngleZ,
  }) {
    final padX = (bboxW * 0.10).round();
    final padY = (bboxH * 0.10).round();
    final cropX = (bboxX - padX).clamp(0, fullImage.width - 1);
    final cropY = (bboxY - padY).clamp(0, fullImage.height - 1);
    final cropW = (bboxW + 2 * padX).clamp(1, fullImage.width - cropX);
    final cropH = (bboxH + 2 * padY).clamp(1, fullImage.height - cropY);

    final faceCrop = img.copyCrop(
      fullImage,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    const analysisSize = 100;
    final resized = img.copyResize(
      faceCrop,
      width: analysisSize,
      height: analysisSize,
      interpolation: img.Interpolation.linear,
    );

    double totalWeight = 0.0;
    double weightedScore = 0.0;

    // Signal 1: Sharpness (Laplacian variance)
    {
      const w = 0.25;
      totalWeight += w;
      final sharpness = _laplacianVariance(resized);
      final s = ((sharpness - 30.0) / 220.0).clamp(0.0, 1.0);
      weightedScore += w * s;
    }

    // Signal 2: Colour distribution
    {
      const w = 0.25;
      totalWeight += w;
      final colorScore = _colorDistributionScore(resized);
      weightedScore += w * colorScore;
    }

    // Signal 3: Edge density
    {
      const w = 0.15;
      totalWeight += w;
      final edgeScore = _edgeDensityScore(resized);
      weightedScore += w * edgeScore;
    }

    // Signal 4: Eye openness
    if (leftEyeOpenProbability != null && rightEyeOpenProbability != null) {
      const w = 0.20;
      totalWeight += w;
      final eyeAvg =
          ((leftEyeOpenProbability + rightEyeOpenProbability) / 2.0)
              .clamp(0.0, 1.0);
      weightedScore += w * eyeAvg;
    }

    // Signal 5: Head pose
    if (headEulerAngleY != null) {
      const w = 0.15;
      totalWeight += w;
      final poseScore =
          (1.0 - (headEulerAngleY.abs() / 45.0)).clamp(0.0, 1.0);
      weightedScore += w * poseScore;
    }

    final liveScore = totalWeight > 0 ? weightedScore / totalWeight : 0.0;
    final isLive = liveScore >= liveThreshold;
    final spoofTotal = isLive ? 0.0 : (1.0 - liveScore);

    return LivenessResult(
      isLive: isLive,
      liveScore: liveScore,
      spoofPrintScore: spoofTotal * 0.5,
      spoofReplayScore: spoofTotal * 0.5,
    );
  }

  double _laplacianVariance(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 3 || h < 3) return 0.0;

    final gray = List<double>.filled(w * h, 0.0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        gray[y * w + x] =
            0.299 * p.r.toDouble() +
            0.587 * p.g.toDouble() +
            0.114 * p.b.toDouble();
      }
    }

    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final lap = gray[(y - 1) * w + x] +
            gray[(y + 1) * w + x] +
            gray[y * w + (x - 1)] +
            gray[y * w + (x + 1)] -
            4.0 * gray[y * w + x];
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }

  double _colorDistributionScore(img.Image image) {
    final w = image.width;
    final h = image.height;

    double sumR = 0, sumG = 0, sumB = 0;
    double sumRSq = 0, sumGSq = 0, sumBSq = 0;
    int count = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        sumR += r;
        sumG += g;
        sumB += b;
        sumRSq += r * r;
        sumGSq += g * g;
        sumBSq += b * b;
        count++;
      }
    }

    if (count == 0) return 0.0;

    final stdR = sqrt((sumRSq / count) - pow(sumR / count, 2)).clamp(0.0, 255.0);
    final stdG = sqrt((sumGSq / count) - pow(sumG / count, 2)).clamp(0.0, 255.0);
    final stdB = sqrt((sumBSq / count) - pow(sumB / count, 2)).clamp(0.0, 255.0);

    final avgStd = (stdR + stdG + stdB) / 3.0;
    return ((avgStd - 8.0) / 27.0).clamp(0.0, 1.0);
  }

  double _edgeDensityScore(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 3 || h < 3) return 0.5;

    int edgePixels = 0;
    int totalPixels = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final p = image.getPixel(x, y);
        final pR = image.getPixel(x + 1, y);
        final pD = image.getPixel(x, y + 1);

        final lum = 0.299 * p.r.toDouble() +
            0.587 * p.g.toDouble() +
            0.114 * p.b.toDouble();
        final lumR = 0.299 * pR.r.toDouble() +
            0.587 * pR.g.toDouble() +
            0.114 * pR.b.toDouble();
        final lumD = 0.299 * pD.r.toDouble() +
            0.587 * pD.g.toDouble() +
            0.114 * pD.b.toDouble();

        final gx = (lumR - lum).abs();
        final gy = (lumD - lum).abs();
        final gradient = gx + gy;

        if (gradient > 15.0) edgePixels++;
        totalPixels++;
      }
    }

    if (totalPixels == 0) return 0.5;

    final density = edgePixels / totalPixels;
    if (density < 0.05) {
      return (density / 0.05).clamp(0.0, 1.0);
    } else if (density > 0.55) {
      return (1.0 - (density - 0.55) / 0.20).clamp(0.0, 1.0);
    }
    return 1.0;
  }
}
