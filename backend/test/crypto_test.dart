import 'package:credential_recovery_backend/src/otp.dart';
import 'package:credential_recovery_backend/src/reference.dart';
import 'package:test/test.dart';

void main() {
  group('OTP and reference cryptography', () {
    const pepper = 'server-only-pepper';

    test('generated codes are high-entropy hex and never equal their digest',
        () {
      final otp = OtpAuthority(pepper);
      final code = otp.generate();
      expect(code, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(code, isNot(equals(otp.generate())));
      expect(otp.hash(code), matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(otp.hash(code), isNot(equals(code)));
      expect(otp.hash(code), equals(otp.hash(code)));
    });

    test('digest comparison is symmetric and rejects different or short input',
        () {
      final otp = OtpAuthority(pepper);
      final digest = otp.hash('a-code');
      expect(otp.constantTimeEquals(digest, otp.hash('a-code')), isTrue);
      expect(otp.constantTimeEquals(digest, otp.hash('other')), isFalse);
      expect(otp.constantTimeEquals(digest, 'abc'), isFalse);
    });

    test('the reference HMAC binds operation id to its expiry', () {
      final first = OperationReference(pepper);
      final second = OperationReference(pepper);
      final expiry = DateTime.parse('2026-11-25T12:00:00.000Z');
      final digest =
          first.digestFor('11111111-2222-4333-8444-555555555555', expiry);
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        second.digestFor('11111111-2222-4333-8444-555555555555', expiry),
        equals(digest),
      );
      expect(
        second.digestFor(
          '11111111-2222-4333-8444-555555555555',
          expiry.add(const Duration(minutes: 5)),
        ),
        isNot(equals(digest)),
      );
      expect(
        second.digestFor('22222222-3333-4444-8555-666666666666', expiry),
        isNot(equals(digest)),
      );
      expect(
        OperationReference('other-pepper')
            .digestFor('11111111-2222-4333-8444-555555555555', expiry),
        isNot(equals(digest)),
      );
    });
  });
}
