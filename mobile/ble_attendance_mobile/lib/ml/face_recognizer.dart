import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps the MobileFaceNet TFLite model for on-device face embedding
/// generation and comparison.
///
/// Usage:
/// ```dart
/// final recognizer = FaceRecognizer();
/// await recognizer.init();
/// final embedding = recognizer.getEmbedding(croppedFaceImage);
/// final match = recognizer.isMatch(embedding, savedEmbedding);
/// recognizer.dispose();
/// ```
class FaceRecognizer {
  static const int inputSize = 112;
  static const int embeddingSize = 192;
  static const double defaultThreshold = 1.0;

  Interpreter? _interpreter;

  /// Initialise the TFLite interpreter from the bundled asset.
  Future<void> init() async {
    _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
  }

  /// Dispose of the interpreter to free native memory.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Generate a 192-dimensional embedding from a cropped face image.
  ///
  /// [faceImage] should already be cropped to the face bounding box.
  /// The method handles resizing to 112×112 and normalising pixel values.
  List<double> getEmbedding(img.Image faceImage) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('FaceRecognizer not initialised. Call init() first.');
    }

    // Resize to model input dimensions
    final resized = img.copyResize(faceImage, width: inputSize, height: inputSize);

    // Build input tensor [1, 112, 112, 3] with normalised float32 values
    final input = Float32List(1 * inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        // Normalise from [0, 255] to [-1, 1]
        input[idx++] = (pixel.r.toDouble() - 127.5) / 127.5;
        input[idx++] = (pixel.g.toDouble() - 127.5) / 127.5;
        input[idx++] = (pixel.b.toDouble() - 127.5) / 127.5;
      }
    }

    // Reshape to [1, 112, 112, 3]
    final inputTensor = input.reshape([1, inputSize, inputSize, 3]);

    // Output tensor [1, 192]
    final output = List.filled(1 * embeddingSize, 0.0).reshape([1, embeddingSize]);

    interpreter.run(inputTensor, output);

    // Flatten and L2-normalise the output embedding
    final embedding = List<double>.from(output[0] as List);
    return _l2Normalise(embedding);
  }

  /// Compute the Euclidean (L2) distance between two embeddings.
  double distance(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'Embedding dimensions do not match: ${a.length} vs ${b.length}',
      );
    }
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  /// Returns `true` when the Euclidean distance between the two embeddings
  /// is below [threshold] (lower distance = more similar).
  bool isMatch(
    List<double> a,
    List<double> b, {
    double threshold = defaultThreshold,
  }) {
    return distance(a, b) < threshold;
  }

  List<double> _l2Normalise(List<double> vec) {
    double norm = 0;
    for (final v in vec) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0) return vec;
    return vec.map((v) => v / norm).toList();
  }
}
