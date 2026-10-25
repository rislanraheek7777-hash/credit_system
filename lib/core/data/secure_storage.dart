import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exception thrown when secure storage operations fail.
class SecureStorageException implements Exception {
  final String message;
  const SecureStorageException(this.message);
  @override
  String toString() => 'SecureStorageException: $message';
}

/// Abstract interface for secure key-value storage.
///
/// On Android, iOS, macOS, Linux, and Windows, this is backed by
/// [flutter_secure_storage], which uses platform-native encrypted storage
/// (Keychain on iOS/macOS, Keystore on Android, Credential Manager on
/// Windows, libsecret on Linux).
///
/// On Flutter Web, [flutter_secure_storage_web] is used, which stores values
/// in `window.localStorage` with XOR-based obfuscation. This is **not**
/// encryption: the obfuscation key is embedded in the package source code and
/// is accessible to any script running on the same origin. Values stored on
/// Web should be treated as obfuscated, not encrypted. Sensitive data such as
/// plaintext passwords must never be stored here.
abstract class SecureStorage {
  /// Writes [value] for [key]. Returns `true` on success.
  Future<bool> write({required String key, required String value});

  /// Reads the value for [key], or `null` if not present.
  Future<String?> read({required String key});

  /// Deletes the value for [key]. Returns `true` if a value was deleted.
  Future<bool> delete({required String key});

  /// Deletes all values. Returns `true` on success.
  Future<bool> deleteAll();
}

/// Concrete [SecureStorage] implementation backed by
/// `package:flutter_secure_storage/flutter_secure_storage.dart`.
///
/// Platform support:
/// - Android: EncryptedSharedPreferences (Android Keystore-backed)
/// - iOS/macOS: Keychain
/// - Windows: Windows Credential Manager
/// - Linux: libsecret
/// - Web: window.localStorage with XOR obfuscation (NOT encryption — see class docs)
class FlutterSecureStorageService implements SecureStorage {
  final FlutterSecureStorage _storage;

  FlutterSecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<bool> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (e) {
      throw SecureStorageException('Failed to write key "$key": $e');
    }
  }

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      throw SecureStorageException('Failed to read key "$key": $e');
    }
  }

  @override
  Future<bool> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
      return true;
    } catch (e) {
      throw SecureStorageException('Failed to delete key "$key": $e');
    }
  }

  @override
  Future<bool> deleteAll() async {
    try {
      await _storage.deleteAll();
      return true;
    } catch (e) {
      throw SecureStorageException('Failed to clear secure storage: $e');
    }
  }
}
