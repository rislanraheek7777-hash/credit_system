import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';
import 'package:crypto/crypto.dart';

/// Generates and hashes recovery codes. The pepper never leaves the backend
/// process and is only ever combined with a freshly generated code.
class OtpAuthority {
  OtpAuthority(this._pepper);

  final String _pepper;
  final Random _random = Random.secure();

  static const int maxAttempts = 5;
  static const String _alphabet = '0123456789abcdef';
  static const int _codeLength = 16;

  /// 64 bits of entropy, URL/mail safe, and never stored in plaintext.
  String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < _codeLength; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  /// The only form of the code that is persisted.
  String hash(String otp) =>
      sha256.convert(utf8.encode('$_pepper:$otp')).toString();

  /// Compares two fixed-length digests without an early-exit timing leak.
  bool constantTimeEquals(String a, String b) =>
      _constantTimeBytes(utf8.encode(a), utf8.encode(b));

  static bool _constantTimeBytes(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    var diff = a.length ^ b.length;
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      diff |= left ^ right;
    }
    return diff == 0;
  }
}

/// Produces the password hash that the Flutter client will verify on its next
/// login. Injectable so API tests never pay for Argon2 work.
abstract interface class PasswordHasher {
  String hash(String password);
}

/// Argon2id with the exact parameters used by the client's
/// `PasswordHashService`, encoded in the same PHC string format.
class Argon2PasswordHasher implements PasswordHasher {
  static const int _iterations = 3;
  static const int _memoryKiB = 65536;
  static const int _parallelism = 4;
  static const int _hashLength = 32;
  static const int _saltLength = 16;

  final Argon2BytesGenerator _generator = Argon2BytesGenerator();
  final Random _random = Random.secure();

  @override
  String hash(String password) {
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', 'must not be empty');
    }
    final salt = Uint8List(_saltLength);
    for (var i = 0; i < _saltLength; i++) {
      salt[i] = _random.nextInt(256);
    }
    _generator.init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        iterations: _iterations,
        memory: _memoryKiB,
        lanes: _parallelism,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
    final hash = Uint8List(_hashLength);
    _generator.generateBytesFromString(password, hash);
    return '\$argon2id\$v=19\$m=$_memoryKiB,t=$_iterations,p=$_parallelism'
        '\$${base64Url.encode(salt)}\$${base64Url.encode(hash)}';
  }
}
