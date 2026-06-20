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
  static const double defaultThreshold = 0.85;

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

  /// Crop the face region from [fullImage] using the given bounding box,
  /// with additional [padding] (fraction of bbox dimensions) to include
  /// forehead, chin, and ears — produces more robust embeddings.
  static img.Image cropFace(
    img.Image fullImage, {
    required int bboxX,
    required int bboxY,
    required int bboxW,
    required int bboxH,
    double padding = 0.2,
  }) {
    final padW = (bboxW * padding).round();
    final padH = (bboxH * padding).round();

    final x = (bboxX - padW).clamp(0, fullImage.width - 1);
    final y = (bboxY - padH).clamp(0, fullImage.height - 1);
    final w = (bboxW + 2 * padW).clamp(1, fullImage.width - x);
    final h = (bboxH + 2 * padH).clamp(1, fullImage.height - y);

    return img.copyCrop(fullImage, x: x, y: y, width: w, height: h);
  }

  /// Apply per-channel histogram equalisation to normalise brightness and
  /// contrast, making the embedding more robust to lighting changes.
  static img.Image equalizeLighting(img.Image src) {
    final w = src.width;
    final h = src.height;
    final totalPixels = w * h;
    if (totalPixels == 0) return src;

    final result = src.clone();

    for (int c = 0; c < 3; c++) {
      final hist = List<int>.filled(256, 0);
      for (int py = 0; py < h; py++) {
        for (int px = 0; px < w; px++) {
          final pixel = src.getPixel(px, py);
          final val =
              (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b)
                  .toInt()
                  .clamp(0, 255);
          hist[val]++;
        }
      }

      final cdf = List<int>.filled(256, 0);
      cdf[0] = hist[0];
      for (int i = 1; i < 256; i++) {
        cdf[i] = cdf[i - 1] + hist[i];
      }

      int cdfMin = totalPixels;
      for (int i = 0; i < 256; i++) {
        if (cdf[i] > 0) {
          cdfMin = cdf[i];
          break;
        }
      }

      final denom = totalPixels - cdfMin;
      final lut = List<int>.filled(256, 0);
      if (denom > 0) {
        for (int i = 0; i < 256; i++) {
          lut[i] = ((cdf[i] - cdfMin) * 255 ~/ denom).clamp(0, 255);
        }
      }

      for (int py = 0; py < h; py++) {
        for (int px = 0; px < w; px++) {
          final pixel = result.getPixel(px, py);
          final origVal =
              (c == 0 ? pixel.r : c == 1 ? pixel.g : pixel.b)
                  .toInt()
                  .clamp(0, 255);
          final nv = lut[origVal];
          if (c == 0) {
            pixel.r = nv as num;
          } else if (c == 1) {
            pixel.g = nv as num;
          } else {
            pixel.b = nv as num;
          }
        }
      }
    }

    return result;
  }

  /// Preprocesses face image with brightness boost, contrast adjustment,
  /// and histogram equalization.
  static img.Image preprocessFace(img.Image src) {
    final result = src.clone();

    // 1. Brightness boost
    const double brightnessBoost = 15.0;
    // 2. Contrast adjustment
    const double contrastFactor = 1.15; // > 1 increases contrast

    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);

        // Boost brightness
        double r = pixel.r.toDouble() + brightnessBoost;
        double g = pixel.g.toDouble() + brightnessBoost;
        double b = pixel.b.toDouble() + brightnessBoost;

        // Adjust contrast: new_val = 128 + (old_val - 128) * factor
        r = 128.0 + (r - 128.0) * contrastFactor;
        g = 128.0 + (g - 128.0) * contrastFactor;
        b = 128.0 + (b - 128.0) * contrastFactor;

        // Clamp to [0, 255]
        pixel.r = r.clamp(0.0, 255.0);
        pixel.g = g.clamp(0.0, 255.0);
        pixel.b = b.clamp(0.0, 255.0);
      }
    }

    // 3. Histogram equalization
    return equalizeLighting(result);
  }

  /// Generate a 192-dimensional embedding from a cropped face image.
  ///
  /// [faceImage] should already be cropped to the face bounding box.
  /// The method handles lighting normalisation, resizing to 112×112,
  /// and normalising pixel values.
  List<double> getEmbedding(img.Image faceImage) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('FaceRecognizer not initialised. Call init() first.');
    }

    // Preprocess face image (brightness, contrast, and histogram equalization)
    final preprocessed = preprocessFace(faceImage);

    // Resize to model input dimensions
    final resized =
        img.copyResize(preprocessed, width: inputSize, height: inputSize);

    // Build input tensor [1, 112, 112, 3] with normalised float32 values
    final input = Float32List(1 * inputSize * inputSize * 3);
    int idx = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        // MobileFaceNet was trained with BGR channel order (OpenCV convention).
        // Swap R and B when building the input tensor.
        input[idx++] = (pixel.b.toDouble() - 127.5) / 127.5; // B → channel 0
        input[idx++] = (pixel.g.toDouble() - 127.5) / 127.5; // G → channel 1
        input[idx++] = (pixel.r.toDouble() - 127.5) / 127.5; // R → channel 2
      }
    }

    // Reshape to [1, 112, 112, 3]
    final inputTensor = input.reshape([1, inputSize, inputSize, 3]);

    // Output tensor [1, 192]
    final output =
        List.filled(1 * embeddingSize, 0.0).reshape([1, embeddingSize]);

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

  /// Analyze the lighting of a face image, returning the average brightness
  /// and the difference in brightness between the left and right halves.
  static Map<String, double> analyzeFaceLighting(img.Image faceImage) {
    if (faceImage.width == 0 || faceImage.height == 0) {
      return {'avg': 0.0, 'diff': 0.0};
    }

    final midX = faceImage.width ~/ 2;
    double leftLuminance = 0.0;
    int leftCount = 0;
    double rightLuminance = 0.0;
    int rightCount = 0;

    for (int y = 0; y < faceImage.height; y++) {
      for (int x = 0; x < faceImage.width; x++) {
        final pixel = faceImage.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        // Standard relative luminance formula
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

        if (x < midX) {
          leftLuminance += luminance;
          leftCount++;
        } else {
          rightLuminance += luminance;
          rightCount++;
        }
      }
    }

    final avgLeft = leftCount > 0 ? leftLuminance / leftCount : 0.0;
    final avgRight = rightCount > 0 ? rightLuminance / rightCount : 0.0;
    final avgTotal = (leftLuminance + rightLuminance) / (leftCount + rightCount);
    final difference = (avgLeft - avgRight).abs();

    return {'avg': avgTotal, 'diff': difference};
  }
}
