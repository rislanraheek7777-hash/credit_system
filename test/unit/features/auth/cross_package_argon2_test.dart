import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/features/auth/data/services/password_hash_service.dart';

// Explicit cross-package check: the standalone backend package and the Flutter
// client must agree on the Argon2id PHC format and parameters. The relative
// import is intentional: it avoids making the client depend on the backend.
// ignore: avoid_relative_lib_imports
import '../../../../backend/lib/src/otp.dart' as backend;

void main() {
  test('backend password hash verifies with the client PasswordHashService', () {
    const password = 'cross-package-password';
    final hash = backend.Argon2PasswordHasher().hash(password);

    expect(hash, startsWith('\$argon2id\$v=19\$m=65536,t=3,p=4\$'));
    final verifier = PasswordHashService();
    expect(verifier.verifyPassword(password, hash), isTrue);
    expect(verifier.verifyPassword('wrong-password', hash), isFalse);
  });
}
