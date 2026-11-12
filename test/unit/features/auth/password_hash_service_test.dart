import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';

void main() {
  group('PasswordHashService - Argon2id Password Hashing', () {
    late PasswordHashService service;

    setUp(() {
      service = PasswordHashService();
    });

    test('hashes the same password twice with independently salted hashes', () {
      final hash1 = service.hashPassword('correct-password');
      final hash2 = service.hashPassword('correct-password');

      // Different salts produce different encoded hashes
      expect(hash1, isNot(equals(hash2)));

      // Both verify the original password
      expect(service.verifyPassword('correct-password', hash1), isTrue);
      expect(service.verifyPassword('correct-password', hash2), isTrue);
    });

    test('verifies the original password correctly', () {
      final hash = service.hashPassword('my-secure-password');
      expect(service.verifyPassword('my-secure-password', hash), isTrue);
    });

    test('rejects incorrect passwords', () {
      final hash = service.hashPassword('correct-password');
      expect(service.verifyPassword('wrong-password', hash), isFalse);
      expect(service.verifyPassword('Correct-Password', hash), isFalse);
      expect(service.verifyPassword('correct-password ', hash), isFalse);
    });

    test('returns false for null or empty password', () {
      final hash = service.hashPassword('some-password');
      expect(service.verifyPassword(null, hash), isFalse);
      expect(service.verifyPassword('', hash), isFalse);
    });

    test('returns false for null or empty stored hash', () {
      expect(service.verifyPassword('some-password', null), isFalse);
      expect(service.verifyPassword('some-password', ''), isFalse);
    });

    test('handles malformed hash strings safely', () {
      expect(service.verifyPassword('password', 'not-a-valid-hash'), isFalse);
      expect(service.verifyPassword('password', ''), isFalse);
      expect(
        service.verifyPassword('password', '\$argon2id\$v=19\$bad\$params'), isFalse,
      );
      expect(
        service.verifyPassword('password', '\$argon2d\$v=19\$m=65536,t=3,p=4\$salt\$hash'),
        isFalse,
      );
      expect(
        service.verifyPassword('password', '\$argon2id\$v=13\$m=65536,t=3,p=4\$salt\$hash'),
        isFalse,
      );
    });

    test('never stores plaintext password in the hash', () {
      final password = 'my-secret-password';
      final hash = service.hashPassword(password);

      // The encoded hash should not contain the plaintext password
      expect(hash, isNot(contains(password)));

      // The hash should contain the PHC format identifier
      expect(hash, startsWith('\$argon2id\$v=19\$'));
    });

    test('produces different hashes for different passwords', () {
      final hash1 = service.hashPassword('password-one');
      final hash2 = service.hashPassword('password-two');
      expect(hash1, isNot(equals(hash2)));
    });

    test('hashes and verifies long passwords', () {
      final longPassword = 'A' * 1000;
      final hash = service.hashPassword(longPassword);
      expect(service.verifyPassword(longPassword, hash), isTrue);
    });

    test('hashes and verifies passwords with special characters', () {
      final specialPassword = 'p@ssw0rd!#\$%^&*()_+-=[]{}|;:,.<>?';
      final hash = service.hashPassword(specialPassword);
      expect(service.verifyPassword(specialPassword, hash), isTrue);
    });

    test('hashes and verifies unicode passwords', () {
      final unicodePassword = 'pässwörd 🔐 日本語';
      final hash = service.hashPassword(unicodePassword);
      expect(service.verifyPassword(unicodePassword, hash), isTrue);
    });
  });
}

