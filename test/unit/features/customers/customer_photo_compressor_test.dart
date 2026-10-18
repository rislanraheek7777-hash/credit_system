import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'package:credit_system/features/customers/domain/services/customer_photo_compressor.dart';

void main() {
  const compressor = CustomerPhotoCompressor();

  /// Helper to generate a test image encoded as JPEG or PNG.
  Uint8List createTestImageBytes({
    required int width,
    required int height,
    bool asJpeg = true,
  }) {
    final image = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Draw recognizable multi-color gradient
        final r = (x * 255) ~/ width;
        final g = (y * 255) ~/ height;
        final b = ((x + y) * 255) ~/ (width + height);
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return Uint8List.fromList(asJpeg ? img.encodeJpg(image) : img.encodePng(image));
  }

  group('CustomerPhotoCompressor - Compression & Resizing Pipeline Tests (Story 2.2)', () {
    test('rejects empty input bytes with PhotoCompressionException', () async {
      expect(
        () => compressor.compress(Uint8List(0)),
        throwsA(isA<PhotoCompressionException>()),
      );
    });

    test('rejects corrupt or non-image data with PhotoCompressionException', () async {
      final corruptBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(
        () => compressor.compress(corruptBytes),
        throwsA(isA<PhotoCompressionException>()),
      );
    });

    test('preserves dimensions when longest edge is under 1600 pixels', () async {
      final inputBytes = createTestImageBytes(width: 800, height: 600);
      final result = await compressor.compress(inputBytes);

      expect(result.width, equals(800));
      expect(result.height, equals(600));
      expect(result.sizeInBytes, lessThanOrEqualTo(CustomerPhotoCompressor.maxFileSizeBytes));

      // Check format by decoding
      final decoded = img.decodeJpg(result.bytes);
      expect(decoded, isNotNull);
      if (decoded != null) {
        expect(decoded.width, equals(800));
        expect(decoded.height, equals(600));
      }
    });

    test('downscales high-resolution images so longest edge is exactly 1600 pixels', () async {
      // 2400x1800 -> aspect ratio 4:3 -> longest edge should become 1600, height 1200
      final largeBytes = createTestImageBytes(width: 2400, height: 1800);
      final result = await compressor.compress(largeBytes);

      expect(result.width, equals(1600));
      expect(result.height, equals(1200));
      expect(result.sizeInBytes, lessThanOrEqualTo(CustomerPhotoCompressor.maxFileSizeBytes));
    });

    test('downscales tall portrait images so height is exactly 1600 pixels', () async {
      // 1500x3000 -> tall portrait -> height becomes 1600, width becomes 800
      final tallBytes = createTestImageBytes(width: 1500, height: 3000);
      final result = await compressor.compress(tallBytes);

      expect(result.height, equals(1600));
      expect(result.width, equals(800));
      expect(result.sizeInBytes, lessThanOrEqualTo(CustomerPhotoCompressor.maxFileSizeBytes));
    });

    test('guarantees output file size strictly satisfies 500 KB hard limit', () async {
      // Create a noisy image that compresses poorly
      final inputBytes = createTestImageBytes(width: 2000, height: 2000);
      final result = await compressor.compress(inputBytes);

      expect(result.sizeInBytes, lessThanOrEqualTo(CustomerPhotoCompressor.maxFileSizeBytes));
      expect(result.sizeInBytes, greaterThan(0));
    });

    test('generates valid, reproducible cryptographic SHA-256 hash matching compressed bytes', () async {
      final inputBytes = createTestImageBytes(width: 640, height: 480);
      final result = await compressor.compress(inputBytes);

      final expectedHash = sha256.convert(result.bytes).toString();
      expect(result.sha256Hash, equals(expectedHash));
      expect(result.sha256Hash.length, equals(64)); // Standard SHA-256 hex string length
    });
  });
}
