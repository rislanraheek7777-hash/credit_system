import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exceptions thrown during photo storage operations.
class PhotoStorageException implements Exception {
  final String message;
  const PhotoStorageException(this.message);

  @override
  String toString() => 'PhotoStorageException: $message';
}

/// Service managing local sandboxed customer photo storage (PRD FR-9, AD-5, Story 2.2).
///
/// Ensures:
/// 1. App-private documents sandbox storage (`photos/{shopId}/customers/`).
/// 2. Tenant isolation by preventing directory traversal (`..`, separators) in `shopId`.
/// 3. Returns only relative paths for SQLite persistence, decoupled from OS absolute sandbox paths.
class PhotoStorageService {
  final Directory? baseDirectoryOverride;

  /// Default constructor resolves the system sandboxed documents directory.
  /// Pass [baseDirectoryOverride] for hermetic, isolated unit tests.
  const PhotoStorageService({this.baseDirectoryOverride});

  /// Resolves the absolute root storage directory for sandboxed files.
  Future<Directory> getBaseDirectory() async {
    if (baseDirectoryOverride != null) {
      return baseDirectoryOverride!;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Validates that an identifier does not contain path traversal characters.
  static void _validatePathIdentifier(String identifier, String paramName) {
    if (identifier.trim().isEmpty) {
      throw PhotoStorageException('$paramName cannot be empty.');
    }
    if (identifier.contains('/') ||
        identifier.contains('\\') ||
        identifier.contains('..')) {
      throw PhotoStorageException(
        'Invalid $paramName "$identifier": path traversal characters are forbidden.',
      );
    }
  }

  /// Computes the relative storage path for a customer photograph:
  /// `photos/{shopId}/customers/{customerId}_{timestampMs}.jpg`
  static String getRelativePhotoPath({
    required String shopId,
    required String customerId,
    required int timestampMs,
  }) {
    _validatePathIdentifier(shopId, 'shopId');
    _validatePathIdentifier(customerId, 'customerId');
    return p.join('photos', shopId, 'customers', '${customerId}_$timestampMs.jpg').replaceAll('\\', '/');
  }

  /// Resolves an existing relative path to an absolute [File] in sandboxed storage.
  Future<File> resolveRelativePath(String relativePath) async {
    if (relativePath.contains('..') || p.isAbsolute(relativePath)) {
      throw const PhotoStorageException('Invalid relative path.');
    }
    final baseDir = await getBaseDirectory();
    return File(p.join(baseDir.path, relativePath));
  }

  /// Saves compressed photo [bytes] to the sandboxed path for [shopId] and [customerId].
  ///
  /// Atomically writes to a temporary file before renaming to avoid partial/corrupt files.
  /// Returns the relative path suitable for persistence in [Customers.photoUri].
  Future<String> saveCustomerPhoto({
    required String shopId,
    required String customerId,
    required List<int> bytes,
    int? timestampMs,
  }) async {
    _validatePathIdentifier(shopId, 'shopId');
    _validatePathIdentifier(customerId, 'customerId');

    if (bytes.isEmpty) {
      throw const PhotoStorageException('Cannot save empty photo bytes.');
    }

    final ts = timestampMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    final relativePath = getRelativePhotoPath(
      shopId: shopId,
      customerId: customerId,
      timestampMs: ts,
    );

    final baseDir = await getBaseDirectory();
    final targetFile = File(p.join(baseDir.path, relativePath));
    final parentDir = targetFile.parent;

    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    // Write to a temporary file first, then atomically replace
    final tempFile = File('${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
    try {
      tempFile.writeAsBytesSync(bytes, flush: true);
      tempFile.renameSync(targetFile.path);
    } catch (e) {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      throw PhotoStorageException('Failed to write photo file to disk: $e');
    }

    return relativePath;
  }

  /// Safely deletes a photo file by its relative path if it exists.
  Future<void> deletePhotoIfExists(String relativePath) async {
    try {
      final file = await resolveRelativePath(relativePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }
}

