import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Passive face liveness / anti-spoofing detector using image analysis and
/// ML Kit face classification features.
///
/// Replaces the previous TFLite-based MiniFASNetV2 approach which produced
/// unreliable scores on Android due to tflite_flutter + XNNPACK
/// incompatibilities with NCHW models.
///
/// Combines multiple lightweight signals:
///   1. **Sharpness** (Laplacian variance) — re-photographed images lose focus.
///   2. **Color distribution** — printed/screen images have compressed colour
///      range compared to real skin under natural lighting.
///   3. **Edge density** — screens/prints often exhibit moiré, halftone dots,
///      or unnaturally uniform textures.
///   4. **Eye openness** (from ML Kit) — both eyes should be open.
///   5. **Head pose** (from ML Kit) — face should be roughly frontal.
///
/// None of these signals is strong enough alone, but the weighted combination
/// provides a practical liveness gate for an attendance-verification scenario
/// (where face embedding matching already prevents unknown-person attacks).
///
/// Usage:
/// ```dart
/// final detector = LivenessDetector();
/// await detector.init();
/// final result = detector.check(
///   fullImage,
///   bboxX: ..., bboxY: ..., bboxW: ..., bboxH: ...,
///   leftEyeOpenProbability: face.leftEyeOpenProbability,
///   rightEyeOpenProbability: face.rightEyeOpenProbability,
///   headEulerAngleY: face.headEulerAngleY,
/// );
/// if (!result.isLive) { ... }
/// detector.dispose();
/// ```
class LivenessDetector {
  /// Minimum combined score to accept as a live face.
  final double liveThreshold;

  LivenessDetector({this.liveThreshold = 0.45});

  /// Kept for API compatibility — nothing heavy to load.
  Future<void> init() async {
    debugPrint('[LivenessDetector] Initialised (image-analysis mode)');
  }

  /// Kept for API compatibility — nothing to dispose.
  void dispose() {
    // No-op.
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Run the liveness check on [fullImage] using the face bounding box and
  /// optional ML Kit classification features.
  ///
  /// [bboxX], [bboxY], [bboxW], [bboxH] are the face bounding box coordinates
  /// as returned by Google ML Kit — they should match the *orientation-corrected*
  /// image (i.e. after [img.bakeOrientation] has been applied).
  LivenessResult check(
    img.Image fullImage, {
    required int bboxX,
    required int bboxY,
    required int bboxW,
    required int bboxH,
    // Optional ML Kit face-classification features.
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
    double? headEulerAngleY,
    double? headEulerAngleZ,
  }) {
    // --- 1. Crop the face region with 10 % padding for analysis. -----------
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

    // Resize to a fixed size for consistent analysis regardless of capture
    // resolution.
    const analysisSize = 100;
    final resized = img.copyResize(
      faceCrop,
      width: analysisSize,
      height: analysisSize,
      interpolation: img.Interpolation.linear,
    );

    double totalWeight = 0.0;
    double weightedScore = 0.0;

    // --- Signal 1: Sharpness (Laplacian variance) --------------------------
    // Re-photographed images (photo-of-photo / screen capture) typically lose
    // sharpness. Real camera captures are in-focus with high gradient variance.
    {
      const w = 0.25;
      totalWeight += w;
      final sharpness = _laplacianVariance(resized);
      // Real faces: variance typically 200 – 3 000+
      // Re-photographed: 30 – 150
      // Scale linearly: 0 at ≤ 30, 1.0 at ≥ 250
      final s = ((sharpness - 30.0) / 220.0).clamp(0.0, 1.0);
      weightedScore += w * s;
      debugPrint(
        '[LivenessDetector] Sharpness: ${sharpness.toStringAsFixed(1)} '
        '→ ${s.toStringAsFixed(2)}',
      );
    }

    // --- Signal 2: Colour distribution naturalness -------------------------
    // Real skin under natural lighting has diverse channel intensities.
    // Printed / screen images tend to compress the colour range.
    {
      const w = 0.25;
      totalWeight += w;
      final colorScore = _colorDistributionScore(resized);
      weightedScore += w * colorScore;
      debugPrint(
        '[LivenessDetector] Colour: ${colorScore.toStringAsFixed(2)}',
      );
    }

    // --- Signal 3: Edge density / texture ----------------------------------
    // Moiré patterns (screens) and halftone dots (prints) create unusual
    // edge density compared to a smooth real skin surface.
    {
      const w = 0.15;
      totalWeight += w;
      final edgeScore = _edgeDensityScore(resized);
      weightedScore += w * edgeScore;
      debugPrint(
        '[LivenessDetector] Edge density: ${edgeScore.toStringAsFixed(2)}',
      );
    }

    // --- Signal 4: Eye openness (ML Kit) -----------------------------------
    if (leftEyeOpenProbability != null && rightEyeOpenProbability != null) {
      const w = 0.20;
      totalWeight += w;
      // Average of both eyes; ≥ 0.4 is comfortably "open".
      final eyeAvg =
          ((leftEyeOpenProbability + rightEyeOpenProbability) / 2.0)
              .clamp(0.0, 1.0);
      weightedScore += w * eyeAvg;
      debugPrint(
        '[LivenessDetector] Eyes: L=${leftEyeOpenProbability.toStringAsFixed(2)} '
        'R=${rightEyeOpenProbability.toStringAsFixed(2)} '
        '→ ${eyeAvg.toStringAsFixed(2)}',
      );
    }

    // --- Signal 5: Head pose (ML Kit) --------------------------------------
    if (headEulerAngleY != null) {
      const w = 0.15;
      totalWeight += w;
      // Frontal face (Y ≈ 0) → 1.0; extreme side (|Y| ≥ 45°) → 0.0.
      final poseScore =
          (1.0 - (headEulerAngleY.abs() / 45.0)).clamp(0.0, 1.0);
      weightedScore += w * poseScore;
      debugPrint(
        '[LivenessDetector] Head Y: ${headEulerAngleY.toStringAsFixed(1)}° '
        '→ ${poseScore.toStringAsFixed(2)}',
      );
    }

    // --- Final decision ----------------------------------------------------
    final liveScore = totalWeight > 0 ? weightedScore / totalWeight : 0.0;
    final isLive = liveScore >= liveThreshold;

    // Attribute remaining spoof probability equally to print/replay.
    final spoofTotal = isLive ? 0.0 : (1.0 - liveScore);

    debugPrint(
      '[LivenessDetector] FINAL: live=${liveScore.toStringAsFixed(3)}, '
      'isLive=$isLive (threshold=$liveThreshold)',
    );

    return LivenessResult(
      isLive: isLive,
      liveScore: liveScore,
      spoofPrintScore: spoofTotal * 0.5,
      spoofReplayScore: spoofTotal * 0.5,
    );
  }

  // -------------------------------------------------------------------------
  // Image-analysis helpers
  // -------------------------------------------------------------------------

  /// Compute the variance of a discrete Laplacian over a greyscale version
  /// of [image]. Higher variance ⇒ sharper (more in-focus) image.
  double _laplacianVariance(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 3 || h < 3) return 0.0;

    // Build greyscale buffer.
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

    // Laplacian kernel: [0,1,0; 1,-4,1; 0,1,0]
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
    return (sumSq / count) - (mean * mean); // variance
  }

  /// Score in [0, 1] reflecting how "natural" the colour distribution looks.
  /// Real faces under real lighting have per-channel standard deviations
  /// roughly in the 25 – 60 range. Flat / printed images are lower.
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

    debugPrint(
      '[LivenessDetector]   stdR=${stdR.toStringAsFixed(1)} '
      'stdG=${stdG.toStringAsFixed(1)} stdB=${stdB.toStringAsFixed(1)} '
      'avg=${avgStd.toStringAsFixed(1)}',
    );

    // Score: 0 when avgStd ≤ 8, 1.0 when avgStd ≥ 35.
    return ((avgStd - 8.0) / 27.0).clamp(0.0, 1.0);
  }

  /// Score in [0, 1] based on edge density. Screens produce moiré artefacts
  /// (very high edge density) while prints may look unnaturally smooth (very
  /// low edge density). Real faces sit in a natural middle band.
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
    debugPrint(
      '[LivenessDetector]   edgeDensity=${density.toStringAsFixed(3)} '
      '($edgePixels/$totalPixels)',
    );

    // Natural face: edge density roughly 0.10 – 0.45.
    // Screen moiré: > 0.55.
    // Very smooth print: < 0.05.
    // Map the natural range [0.05, 0.55] → [1.0, 0.0] outside it.
    if (density < 0.05) {
      return (density / 0.05).clamp(0.0, 1.0);
    } else if (density > 0.55) {
      return (1.0 - (density - 0.55) / 0.20).clamp(0.0, 1.0);
    }
    return 1.0; // within the healthy range
  }
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

/// Result of a single liveness check.
class LivenessResult {
  /// Whether the face passed the liveness check.
  final bool isLive;

  /// Combined liveness probability (0.0 – 1.0).
  final double liveScore;

  /// Estimated probability that this is a printed-photo attack.
  final double spoofPrintScore;

  /// Estimated probability that this is a screen-replay attack.
  final double spoofReplayScore;

  const LivenessResult({
    required this.isLive,
    required this.liveScore,
    required this.spoofPrintScore,
    required this.spoofReplayScore,
  });

  /// Human-readable spoof type string for debug/logging.
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
