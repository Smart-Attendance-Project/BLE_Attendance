import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps the MiniFASNetV2 TFLite model for passive face liveness / anti-spoofing
/// detection. Distinguishes a real (live) face from a presentation attack such
/// as a printed photo or a replayed screen — with no gesture required from the
/// user.
///
/// Model: litert-community/Silent-Face-Anti-Spoofing-LiteRT (Apache-2.0)
/// Architecture: MiniFASNetV2 (minivision-ai), 1.85 MB, ~5 ms/frame.
///
/// Input:  [1, 80, 80, 3]  — NHWC, BGR channel order, pixel values in [0, 1].
///                           (Model weights use NCHW/BGR convention but TFLite
///                           CPU/XNNPACK requires NHWC; we reorder at runtime.)
/// Output: [1, 3]          — softmax over {spoof-print, live, spoof-replay}.
///                           index 1 is the "live" probability.
///                           The face is considered live when argmax == 1 AND
///                           live probability >= [liveThreshold].
///
/// The model expects a crop that is roughly 2.7× the detected face bounding box
/// (wider than the 20 % padding used for MobileFaceNet) so that background
/// texture and neck region contribute to the spoof decision.
///
/// Usage:
/// ```dart
/// final detector = LivenessDetector();
/// await detector.init();
/// final result = detector.check(fullImage, bboxX, bboxY, bboxW, bboxH);
/// if (!result.isLive) { ... }
/// detector.dispose();
/// ```
class LivenessDetector {
  static const int _inputSize = 80;

  /// Scale factor applied to the face bounding box to produce the model crop.
  /// MiniFASNetV2 was trained with a 2.7× scale crop.
  static const double _cropScale = 2.7;

  /// Minimum live-class probability to accept as a real face.
  /// Values below this are treated as spoof even if argmax == 1.
  final double liveThreshold;

  Interpreter? _interpreter;

  LivenessDetector({this.liveThreshold = 0.60});

  /// Initialise the TFLite interpreter from the bundled asset.
  Future<void> init() async {
    _interpreter = await Interpreter.fromAsset('assets/silentface.tflite');
  }

  /// Dispose of the interpreter to free native memory.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Run the liveness check on [fullImage] using the face bounding box.
  ///
  /// [bboxX], [bboxY], [bboxW], [bboxH] are the face bounding box coordinates
  /// as returned by Google ML Kit — they should match the *orientation-corrected*
  /// image (i.e. after [img.bakeOrientation] has been applied).
  ///
  /// Returns a [LivenessResult] with the live probability and a boolean flag.
  LivenessResult check(
    img.Image fullImage, {
    required int bboxX,
    required int bboxY,
    required int bboxW,
    required int bboxH,
  }) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('LivenessDetector not initialised. Call init() first.');
    }

    // --- 1. Produce the 2.7× scale crop --------------------------------
    // The crop is centred on the face bounding box and scaled outward.
    final cx = bboxX + bboxW / 2.0;
    final cy = bboxY + bboxH / 2.0;
    final halfW = (bboxW * _cropScale / 2.0).ceil();
    final halfH = (bboxH * _cropScale / 2.0).ceil();

    final x = (cx - halfW).round().clamp(0, fullImage.width - 1);
    final y = (cy - halfH).round().clamp(0, fullImage.height - 1);
    final w = (cx + halfW).round().clamp(x + 1, fullImage.width) - x;
    final h = (cy + halfH).round().clamp(y + 1, fullImage.height) - y;

    final cropped = img.copyCrop(fullImage, x: x, y: y, width: w, height: h);

    // --- 2. Resize to 80 × 80 ------------------------------------------
    final resized = img.copyResize(
      cropped,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // --- 3. Build NHWC input tensor [1, 80, 80, 3] in BGR, x/255 -------
    // The model was trained with NCHW BGR input, but TFLite's CPU (XNNPACK)
    // delegate only supports NHWC layout. We therefore lay out the data in
    // NHWC order and reshape to [1, 80, 80, 3]; the channel order stays
    // BGR (B=ch0, G=ch1, R=ch2) as the model weights expect.
    final input = Float32List(1 * _inputSize * _inputSize * 3);

    for (int row = 0; row < _inputSize; row++) {
      for (int col = 0; col < _inputSize; col++) {
        final pixel = resized.getPixel(col, row);
        final r = pixel.r.toDouble() / 255.0;
        final g = pixel.g.toDouble() / 255.0;
        final b = pixel.b.toDouble() / 255.0;

        // NHWC index = row*W*C + col*C + channel
        final base = (row * _inputSize + col) * 3;
        input[base + 0] = b; // channel 0 = B
        input[base + 1] = g; // channel 1 = G
        input[base + 2] = r; // channel 2 = R
      }
    }

    final inputTensor = input.reshape([1, _inputSize, _inputSize, 3]);

    // --- 4. Run inference -----------------------------------------------
    final output = List.filled(1 * 3, 0.0).reshape([1, 3]);
    interpreter.run(inputTensor, output);

    // --- 5. Parse output ------------------------------------------------
    // output[0] = [p_spoof_print, p_live, p_spoof_replay]
    final scores = List<double>.from(output[0] as List);
    final liveScore = scores[1];

    // argmax check: the live class must have the highest probability
    final argmax = scores.indexOf(scores.reduce((a, b) => a > b ? a : b));
    final isLive = (argmax == 1) && (liveScore >= liveThreshold);

    return LivenessResult(
      isLive: isLive,
      liveScore: liveScore,
      spoofPrintScore: scores[0],
      spoofReplayScore: scores[2],
    );
  }
}

/// Result of a single liveness check.
class LivenessResult {
  /// Whether the face passed the liveness check.
  final bool isLive;

  /// Probability that this is a real face (0.0 – 1.0).
  final double liveScore;

  /// Probability that this is a printed-photo attack.
  final double spoofPrintScore;

  /// Probability that this is a screen-replay attack.
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
