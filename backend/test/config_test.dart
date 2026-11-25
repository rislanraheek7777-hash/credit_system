import 'package:credential_recovery_backend/src/config.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('environment configuration', () {
    test('reads every secret and setting from the injected environment', () {
      final config =
          RecoveryConfig.fromEnvironment(validEnvironment()..addAll({
            'CS_RECOVERY_SERVER_HOST': '127.0.0.1',
            'CS_RECOVERY_SERVER_PORT': '9090',
            'CS_RECOVERY_MIGRATION_SQL_PATH': 'sql/003.sql',
          }));

      expect(config.databaseUrl, contains('postgres://'));
      expect(config.otpPepper, equals('server-only-pepper'));
      expect(config.abuseShopId, isNotEmpty);
      expect(config.smtp.password, equals('smtp-password'));
      expect(config.sms.apiKey, equals('server-only-key'));
      expect(config.host, equals('127.0.0.1'));
      expect(config.port, equals(9090));
      expect(config.servesTls, isFalse);
    });

    test('SMTP_TLS accepts only literal true; cleartext is refused at startup',
        () {
      final enabled = validEnvironment()..['CS_RECOVERY_SMTP_TLS'] = 'true';
      expect(RecoveryConfig.fromEnvironment(enabled).smtp.useTls, isTrue);

      for (final value in ['false', 'TRUE', '1', 'yes', '']) {
        final env = validEnvironment()..['CS_RECOVERY_SMTP_TLS'] = value;
        expect(
          () => RecoveryConfig.fromEnvironment(env),
          throwsA(isA<RecoveryConfigException>()),
          reason: '$value must not silently disable TLS',
        );
      }
    });

    test('SMTP and SMS can be enabled independently', () {
      final smtpOnly = validEnvironment()..remove('CS_RECOVERY_SMS_ENDPOINT');
      expect(RecoveryConfig.fromEnvironment(smtpOnly).smtp.useTls, isTrue);

      final smsOnly = validEnvironment()
        ..remove('CS_RECOVERY_SMTP_HOST')
        ..remove('CS_RECOVERY_EMAIL_FROM');
      expect(RecoveryConfig.fromEnvironment(smsOnly).sms.endpoint,
          contains('https://'));

      final neither = validEnvironment()
        ..remove('CS_RECOVERY_SMS_ENDPOINT')
        ..remove('CS_RECOVERY_SMTP_HOST')
        ..remove('CS_RECOVERY_EMAIL_FROM');
      expect(
        () => RecoveryConfig.fromEnvironment(neither),
        throwsA(isA<RecoveryConfigException>()),
      );
    });

    test('cleartext SMS endpoints are rejected', () {
      final env = validEnvironment()
        ..['CS_RECOVERY_SMS_ENDPOINT'] = 'http://sms.example.test/send';
      expect(
        () => RecoveryConfig.fromEnvironment(env),
        throwsA(isA<RecoveryConfigException>()),
      );
    });

    test('ports are parsed strictly and HELO identity is configurable', () {
      final env = validEnvironment()
        ..['CS_RECOVERY_SMTP_PORT'] = '465'
        ..['CS_RECOVERY_SERVER_PORT'] = '8443'
        ..['CS_RECOVERY_SMTP_HELO'] = 'recovery.example.internal';
      final config = RecoveryConfig.fromEnvironment(env);
      expect(config.smtp.port, equals(465));
      expect(config.port, equals(8443));
      expect(config.smtp.helo, equals('recovery.example.internal'));

      for (final entry in [
        const MapEntry('CS_RECOVERY_SMTP_PORT', 'abc'),
        const MapEntry('CS_RECOVERY_SMTP_PORT', '0'),
        const MapEntry('CS_RECOVERY_SMTP_PORT', '70000'),
        const MapEntry('CS_RECOVERY_SERVER_PORT', '99999'),
      ]) {
        final bad = validEnvironment()..[entry.key] = entry.value;
        expect(
          () => RecoveryConfig.fromEnvironment(bad),
          throwsA(isA<RecoveryConfigException>()),
          reason: '${entry.key}=${entry.value} must fail startup',
        );
      }

      final badHelo = validEnvironment()..['CS_RECOVERY_SMTP_HELO'] = 'a\r\nb';
      expect(
        () => RecoveryConfig.fromEnvironment(badHelo),
        throwsA(isA<RecoveryConfigException>()),
      );
    });

    test('non-loopback listeners require a TLS certificate and key', () {
      final plain = validEnvironment()
        ..['CS_RECOVERY_SERVER_HOST'] = '0.0.0.0';
      expect(
        () => RecoveryConfig.fromEnvironment(plain),
        throwsA(isA<RecoveryConfigException>()),
      );

      final secured = validEnvironment()
        ..['CS_RECOVERY_SERVER_HOST'] = '0.0.0.0'
        ..['CS_RECOVERY_TLS_CERT_PATH'] = '/etc/tls/cert.pem'
        ..['CS_RECOVERY_TLS_KEY_PATH'] = '/etc/tls/key.pem';
      expect(RecoveryConfig.fromEnvironment(secured).servesTls, isTrue);

      final halfConfigured = validEnvironment()
        ..['CS_RECOVERY_TLS_CERT_PATH'] = '/etc/tls/cert.pem';
      expect(
        () => RecoveryConfig.fromEnvironment(halfConfigured),
        throwsA(isA<RecoveryConfigException>()),
      );
    });

    test('fails closed with no pepper, no abuse shop and no database URL', () {
      for (final missing in [
        'CS_RECOVERY_OTP_PEPPER',
        'CS_RECOVERY_ABUSE_SHOP_ID',
        'DATABASE_URL',
      ]) {
        final env = validEnvironment()..remove(missing);
        expect(
          () => RecoveryConfig.fromEnvironment(env),
          throwsA(isA<RecoveryConfigException>()),
          reason: '$missing must be required',
        );
      }
    });

    test('rejects a malformed abuse shop id', () {
      final env = validEnvironment()
        ..['CS_RECOVERY_ABUSE_SHOP_ID'] = 'not-a-uuid';
      expect(
        () => RecoveryConfig.fromEnvironment(env),
        throwsA(isA<RecoveryConfigException>()),
      );
    });
  });
}
