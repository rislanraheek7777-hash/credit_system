import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';

/// Exception thrown when password hash operations fail.
class PasswordHashException implements Exception {
  final String message;
  const PasswordHashException(this.message);

  @override
  String toString() => 'PasswordHashException: $message';
}

/// Service for securely hashing and verifying passwords using Argon2id.
///
/// Uses the [argon2](https://pub.dev/packages/argon2) package which implements
/// the Argon2id algorithm — the winner of the Password Hashing Competition and
/// recommended by OWASP for password storage.
///
/// Encoded hashes use the PHC string format:
/// `$argon2id$v=19$m=65536,t=3,p=4$<base64 salt>$<base64 hash>`
///
/// Never stores or logs plaintext passwords.
class PasswordHashService {
  static const int _iterations = 3;
  static const int _memoryKiB = 65536; // 64 MiB
  static const int _parallelism = 4;
  static const int _hashLength = 32; // bytes
  static const int _saltLength = 16; // bytes

  final Argon2BytesGenerator _generator = Argon2BytesGenerator();
  final Random _random = Random.secure();

  /// Hashes a plaintext [password] using Argon2id with a randomly generated salt.
  ///
  /// Returns an encoded hash string in PHC format containing algorithm, version,
  /// parameters, salt, and derived hash. The same password hashed twice produces
  /// different outputs due to random salt generation.
  ///
  /// Throws [PasswordHashException] if [password] is null or empty, or if
  /// hashing fails.
  String hashPassword(String password) {
    if (password.isEmpty) {
      throw const PasswordHashException('Password cannot be empty');
    }

    try {
      final salt = Uint8List(_saltLength);
      for (var i = 0; i < _saltLength; i++) {
        salt[i] = _random.nextInt(256);
      }

      final params = Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        iterations: _iterations,
        memory: _memoryKiB,
        lanes: _parallelism,
        version: Argon2Parameters.ARGON2_VERSION_13,
      );

      _generator.init(params);

      final hash = Uint8List(_hashLength);
      _generator.generateBytesFromString(password, hash);

      final saltB64 = base64Url.encode(salt);
      final hashB64 = base64Url.encode(hash);

      return '\$argon2id\$v=19\$m=$_memoryKiB,t=$_iterations,p=$_parallelism\$$saltB64\$$hashB64';
    } catch (e) {
      throw PasswordHashException('Failed to hash password: $e');
    }
  }

  /// Verifies a plaintext [password] against a stored [storedHash].
  ///
  /// Returns `true` if the password matches the hash, `false` otherwise.
  ///
  /// Handles null, empty, malformed, and unsupported hash values safely by
  /// returning `false` rather than throwing.
  bool verifyPassword(String? password, String? storedHash) {
    if (password == null || password.isEmpty) {
      return false;
    }
    if (storedHash == null || storedHash.isEmpty) {
      return false;
    }

    try {
      final parsed = _parsePHC(storedHash);
      if (parsed == null) {
        return false;
      }

      final salt = base64Url.decode(parsed['salt']!);
      final expectedHash = base64Url.decode(parsed['hash']!);

      final params = Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        iterations: int.parse(parsed['t']!),
        memory: int.parse(parsed['m']!),
        lanes: int.parse(parsed['p']!),
        version: Argon2Parameters.ARGON2_VERSION_13,
      );

      _generator.init(params);

      final computed = Uint8List(_hashLength);
      _generator.generateBytesFromString(password, computed);

      return _constantTimeEquals(computed, expectedHash);
    } catch (_) {
      // Malformed, unsupported, or corrupted hash — verification fails safely.
      return false;
    }
  }

  /// Parses a PHC-formatted Argon2id hash string into its components.
  ///
  /// Returns a map with keys: `v`, `m`, `t`, `p`, `salt`, `hash`, or `null`
  /// if the string is malformed or uses an unsupported algorithm/version.
  Map<String, String>? _parsePHC(String encoded) {
    if (!encoded.startsWith('\$argon2id\$')) {
      return null;
    }

    final parts = encoded.split('\$');
    // Expected: ['', 'argon2id', 'v=19', 'm=...,t=...,p=...', 'salt', 'hash']
    if (parts.length != 6) {
      return null;
    }

    final versionPart = parts[2];
    if (!versionPart.startsWith('v=')) {
      return null;
    }
    final version = int.tryParse(versionPart.substring(2));
    if (version != 19) {
      // Only version 19 (0x13) is supported
      return null;
    }

    final paramsPart = parts[3];
    final params = <String, String>{};
    for (final param in paramsPart.split(',')) {
      final kv = param.split('=');
      if (kv.length == 2) {
        params[kv[0]] = kv[1];
      }
    }

    if (!params.containsKey('m') ||
        !params.containsKey('t') ||
        !params.containsKey('p')) {
      return null;
    }

    return {
      'v': version.toString(),
      'm': params['m']!,
      't': params['t']!,
      'p': params['p']!,
      'salt': parts[4],
      'hash': parts[5],
    };
  }

  /// Constant-time comparison of two byte lists to prevent timing attacks.
  ///
  /// Returns `true` if the lists are equal, `false` otherwise.
  /// Always iterates over the full length of both lists to avoid leaking
  /// information through timing differences.
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      // Still iterate to avoid early-return timing leaks, but result is false.
      var result = 0;
      final minLen = a.length < b.length ? a.length : b.length;
      for (var i = 0; i < minLen; i++) {
        result |= a[i] ^ b[i];
      }
      // Account for length difference without branching on it directly
      result |= a.length ^ b.length;
      return result == 0;
    }

    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
