import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/storage/photo_storage_service.dart';

void main() {
  late Directory tempDir;
  late PhotoStorageService storageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('credit_system_photo_test_');
    storageService = PhotoStorageService(baseDirectoryOverride: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PhotoStorageService - Local Sandboxed Storage Tests (Story 2.2)', () {
    test('computes normalized relative photo path using forward slashes', () {
      final path = PhotoStorageService.getRelativePhotoPath(
        shopId: 'shop-alpha-101',
        customerId: 'cust-uuid-1',
        timestampMs: 1729000000000,
      );

      expect(path, equals('photos/shop-alpha-101/customers/cust-uuid-1_1729000000000.jpg'));
    });

    test('saves photo bytes to sandboxed tenant directory and returns relative path', () async {
      final sampleBytes = [1, 2, 3, 4, 5, 6, 7, 8];
      final relativePath = await storageService.saveCustomerPhoto(
        shopId: 'shop-001',
        customerId: 'cust-001',
        bytes: sampleBytes,
        timestampMs: 123456789,
      );

      expect(relativePath, equals('photos/shop-001/customers/cust-001_123456789.jpg'));

      final resolvedFile = await storageService.resolveRelativePath(relativePath);
      expect(await resolvedFile.exists(), isTrue);
      expect(await resolvedFile.readAsBytes(), equals(sampleBytes));
    });

    test('strictly isolates photos by shopId and prevents collision between tenants', () async {
      final bytesAlpha = [10, 20, 30];
      final bytesBeta = [40, 50, 60];

      final pathAlpha = await storageService.saveCustomerPhoto(
        shopId: 'shop-alpha',
        customerId: 'cust-shared-id',
        bytes: bytesAlpha,
        timestampMs: 1111,
      );

      final pathBeta = await storageService.saveCustomerPhoto(
        shopId: 'shop-beta',
        customerId: 'cust-shared-id',
        bytes: bytesBeta,
        timestampMs: 1111,
      );

      expect(pathAlpha, contains('photos/shop-alpha/customers/'));
      expect(pathBeta, contains('photos/shop-beta/customers/'));

      final fileAlpha = await storageService.resolveRelativePath(pathAlpha);
      final fileBeta = await storageService.resolveRelativePath(pathBeta);

      expect(await fileAlpha.readAsBytes(), equals(bytesAlpha));
      expect(await fileBeta.readAsBytes(), equals(bytesBeta));
    });

    test('rejects path traversal attempts in shopId or customerId', () async {
      expect(
        () => storageService.saveCustomerPhoto(
          shopId: '../malicious_shop',
          customerId: 'cust-1',
          bytes: [1, 2],
        ),
        throwsA(isA<PhotoStorageException>()),
      );

      expect(
        () => storageService.saveCustomerPhoto(
          shopId: 'shop/sub/dir',
          customerId: 'cust-1',
          bytes: [1, 2],
        ),
        throwsA(isA<PhotoStorageException>()),
      );

      expect(
        () => storageService.saveCustomerPhoto(
          shopId: 'shop-1',
          customerId: '../../root_file',
          bytes: [1, 2],
        ),
        throwsA(isA<PhotoStorageException>()),
      );
    });

    test('rejects empty photo bytes', () async {
      expect(
        () => storageService.saveCustomerPhoto(
          shopId: 'shop-1',
          customerId: 'cust-1',
          bytes: [],
        ),
        throwsA(isA<PhotoStorageException>()),
      );
    });

    test('deletePhotoIfExists removes target file cleanly without throwing if missing', () async {
      final path = await storageService.saveCustomerPhoto(
        shopId: 'shop-del',
        customerId: 'cust-del',
        bytes: [1, 2, 3],
        timestampMs: 9999,
      );

      final file = await storageService.resolveRelativePath(path);
      expect(await file.exists(), isTrue);

      await storageService.deletePhotoIfExists(path);
      expect(await file.exists(), isFalse);

      // Deleting already deleted file does not throw
      await expectLater(
        storageService.deletePhotoIfExists(path),
        completes,
      );
    });
  });
}

