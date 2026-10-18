import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// Exception thrown when image optimization, compression, or validation fails.
class PhotoCompressionException implements Exception {
  final String message;
  const PhotoCompressionException(this.message);

  @override
  String toString() => 'PhotoCompressionException: $message';
}

/// Result of a successful photo compression pass.
class CompressedPhotoResult {
  /// Compressed JPEG bytes.
  final Uint8List bytes;

  /// Cryptographic SHA-256 hash of [bytes].
  final String sha256Hash;

  /// Final width in pixels.
  final int width;

  /// Final height in pixels.
  final int height;

  /// Compressed file size in bytes.
  int get sizeInBytes => bytes.length;

  const CompressedPhotoResult({
    required this.bytes,
    required this.sha256Hash,
    required this.width,
    required this.height,
  });
}

/// Client-side image optimization pipeline for KYC identity photos (Story 2.2, FR-9, AD-5).
///
/// Invariants:
/// 1. Maximum dimension: Longest edge <= 1600 pixels (aspect ratio strictly preserved).
/// 2. Target file size: 150 KB – 300 KB.
/// 3. Hard limit: Compressed file size MUST NOT exceed 500 KB (512,000 bytes).
/// 4. Cryptographic integrity: Generates authoritative SHA-256 checksum on compressed output.
/// 5. Standard format: Encodes as JPEG (.jpg) with calibrated quality factors.
class CustomerPhotoCompressor {
  /// Maximum allowed dimension on either width or height.
  static const int maxDimension = 1600;

  /// Hard ceiling for compressed customer photographs (500 KB = 500 * 1024 = 512,000 bytes).
  static const int maxFileSizeBytes = 500 * 1024;

  /// Target upper bound for standard compression (300 KB).
  static const int targetUpperFileSizeBytes = 300 * 1024;

  /// Initial encoding quality percentage.
  static const int initialQuality = 85;

  /// Minimum acceptable quality floor to preserve facial clarity and KYC legibility.
  static const int minQualityFloor = 50;

  const CustomerPhotoCompressor();

  /// Compresses, resizes, and hashes raw customer photograph [rawBytes].
  ///
  /// Throws [PhotoCompressionException] if:
  /// - [rawBytes] is empty or malformed/unsupported format.
  /// - Compressed result exceeds the 500 KB hard limit even after iterative reduction.
  Future<CompressedPhotoResult> compress(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) {
      throw const PhotoCompressionException('Raw photo input bytes cannot be empty.');
    }

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw const PhotoCompressionException(
        'Failed to decode image: unsupported format or corrupt image data.',
      );
    }

    // Step 1: Downscale if either dimension exceeds 1600px, maintaining aspect ratio.
    img.Image workingImage = decoded;
    if (workingImage.width > maxDimension || workingImage.height > maxDimension) {
      if (workingImage.width >= workingImage.height) {
        workingImage = img.copyResize(
          workingImage,
          width: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      } else {
        workingImage = img.copyResize(
          workingImage,
          height: maxDimension,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // Step 2: Iterative compression loop targeting <= 300 KB and strictly <= 500 KB.
    int quality = initialQuality;
    Uint8List compressedBytes = Uint8List.fromList(img.encodeJpg(workingImage, quality: quality));

    // If compressed size exceeds the 500 KB hard ceiling, iteratively reduce quality.
    while (compressedBytes.length > maxFileSizeBytes && quality > minQualityFloor) {
      quality -= 10;
      compressedBytes = Uint8List.fromList(img.encodeJpg(workingImage, quality: quality));
    }

    // If still over 500 KB after reducing quality to floor, downscale dimensions by 20% steps.
    int currentWidth = workingImage.width;
    int currentHeight = workingImage.height;
    while (compressedBytes.length > maxFileSizeBytes && currentWidth > 400 && currentHeight > 400) {
      currentWidth = (currentWidth * 0.8).round();
      currentHeight = (currentHeight * 0.8).round();
      workingImage = img.copyResize(
        workingImage,
        width: currentWidth,
        height: currentHeight,
        interpolation: img.Interpolation.linear,
      );
      compressedBytes = Uint8List.fromList(img.encodeJpg(workingImage, quality: minQualityFloor));
    }

    // Hard ceiling assertion
    if (compressedBytes.length > maxFileSizeBytes) {
      throw PhotoCompressionException(
        'Unable to compress customer photo below 500 KB limit without unacceptable loss of legibility. '
        'Final size: ${(compressedBytes.length / 1024).toStringAsFixed(1)} KB.',
      );
    }

    // Step 3: Compute authoritative SHA-256 hash
    final digest = sha256.convert(compressedBytes);

    return CompressedPhotoResult(
      bytes: compressedBytes,
      sha256Hash: digest.toString(),
      width: workingImage.width,
      height: workingImage.height,
    );
  }
}
