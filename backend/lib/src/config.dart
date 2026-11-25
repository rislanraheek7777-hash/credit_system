import 'dart:io';

/// Configuration failure. The service refuses to start rather than falling
/// back to an insecure default.
class RecoveryConfigException implements Exception {
  final String message;

  const RecoveryConfigException(this.message);

  @override
  String toString() => 'RecoveryConfigException: $message';
}

/// Outbound SMTP settings. Credentials come from the process environment and
/// are never serialized into an API response or an audit record.
class SmtpConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String from;
  final bool useTls;
  final String helo;

  const SmtpConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.from,
    required this.useTls,
    this.helo = 'localhost',
  });
}

/// Outbound SMS provider settings. [endpoint] is the provider's full URL.
class SmsConfig {
  final String endpoint;
  final String sender;
  final String apiKey;

  const SmsConfig({
    required this.endpoint,
    required this.sender,
    required this.apiKey,
  });
}

/// Every secret and connection setting of the recovery authority.
///
/// Only the public backend URL is a client build-time constant; everything in
/// this class is read from OS environment variables at process start.
class RecoveryConfig {
  final String databaseUrl;
  final String otpPepper;
  final String abuseShopId;
  final SmtpConfig smtp;
  final SmsConfig sms;
  final String host;
  final int port;
  final String tlsCertPath;
  final String tlsKeyPath;

  const RecoveryConfig({
    required this.databaseUrl,
    required this.otpPepper,
    required this.abuseShopId,
    required this.smtp,
    required this.sms,
    required this.host,
    required this.port,
    required this.tlsCertPath,
    required this.tlsKeyPath,
  });

  bool get servesTls => tlsCertPath.isNotEmpty;

  /// Reads and validates the runtime environment. [env] is injectable for
  /// tests; production always passes [Platform.environment].
  factory RecoveryConfig.fromEnvironment([Map<String, String>? env]) {
    final values = env ?? Platform.environment;
    final pepper = values['CS_RECOVERY_OTP_PEPPER'] ?? '';
    final abuseShopId = values['CS_RECOVERY_ABUSE_SHOP_ID'] ?? '';
    final databaseUrl = values['DATABASE_URL'] ?? '';
    final smtpHost = values['CS_RECOVERY_SMTP_HOST'] ?? '';
    final smtpFrom = values['CS_RECOVERY_EMAIL_FROM'] ?? '';
    final smsEndpoint = values['CS_RECOVERY_SMS_ENDPOINT'] ?? '';
    final smtpTls = values['CS_RECOVERY_SMTP_TLS'] ?? 'true';
    final smtpHelo = values['CS_RECOVERY_SMTP_HELO'] ?? 'localhost';
    final host = values['CS_RECOVERY_SERVER_HOST'] ?? '127.0.0.1';
    final tlsCertPath = values['CS_RECOVERY_TLS_CERT_PATH'] ?? '';
    final tlsKeyPath = values['CS_RECOVERY_TLS_KEY_PATH'] ?? '';

    if (pepper.isEmpty) {
      throw const RecoveryConfigException(
        'CS_RECOVERY_OTP_PEPPER is required',
      );
    }
    // Fail closed: an un-attributable security event must have a reserved
    // tenant to live in, never a real customer's audit trail.
    if (!isUuid(abuseShopId)) {
      throw const RecoveryConfigException(
        'CS_RECOVERY_ABUSE_SHOP_ID must be a UUID of the reserved platform shop',
      );
    }
    if (databaseUrl.isEmpty) {
      throw const RecoveryConfigException('DATABASE_URL is required');
    }
    // Each delivery channel can be enabled independently. A half-configured
    // channel fails closed, and at least one channel must be usable.
    final smtpConfigured = smtpHost.isNotEmpty || smtpFrom.isNotEmpty;
    final smsConfigured = smsEndpoint.isNotEmpty;
    if (smtpConfigured && (smtpHost.isEmpty || smtpFrom.isEmpty)) {
      throw const RecoveryConfigException(
        'CS_RECOVERY_SMTP_HOST and CS_RECOVERY_EMAIL_FROM must be set together',
      );
    }
    if (!smtpConfigured && !smsConfigured) {
      throw const RecoveryConfigException(
        'At least one of SMTP or SMS delivery must be configured',
      );
    }
    // OTP and bearer credentials must never traverse cleartext.
    if (smsConfigured && Uri.tryParse(smsEndpoint)?.scheme != 'https') {
      throw const RecoveryConfigException(
        'CS_RECOVERY_SMS_ENDPOINT must use https',
      );
    }
    // TLS is mandatory for an enabled SMTP channel.
    if (smtpConfigured && smtpTls != 'true') {
      throw const RecoveryConfigException(
        'CS_RECOVERY_SMTP_TLS must be the literal "true"; cleartext SMTP is not permitted',
      );
    }
    if (smtpHelo.isEmpty ||
        RegExp(r'[\r\n\u0000-\u001f\u007f]').hasMatch(smtpHelo)) {
      throw const RecoveryConfigException(
        'CS_RECOVERY_SMTP_HELO must be a non-empty, header-safe identifier',
      );
    }
    if (tlsCertPath.isEmpty != tlsKeyPath.isEmpty) {
      throw const RecoveryConfigException(
        'CS_RECOVERY_TLS_CERT_PATH and CS_RECOVERY_TLS_KEY_PATH must be set together',
      );
    }
    // Plain HTTP is only acceptable on a loopback listener. A network-facing
    // service must present a TLS certificate from the environment.
    if (!isLoopbackHost(host) && tlsCertPath.isEmpty) {
      throw const RecoveryConfigException(
        'Non-loopback CS_RECOVERY_SERVER_HOST requires CS_RECOVERY_TLS_CERT_PATH '
        'and CS_RECOVERY_TLS_KEY_PATH',
      );
    }

    return RecoveryConfig(
      databaseUrl: databaseUrl,
      otpPepper: pepper,
      abuseShopId: abuseShopId,
      smtp: SmtpConfig(
        host: smtpHost,
        port: parsePort(values['CS_RECOVERY_SMTP_PORT'], 465,
            'CS_RECOVERY_SMTP_PORT'),
        username: values['CS_RECOVERY_SMTP_USER'] ?? '',
        password: values['CS_RECOVERY_SMTP_PASSWORD'] ?? '',
        from: smtpFrom,
        useTls: smtpTls == 'true',
        helo: smtpHelo,
      ),
      sms: SmsConfig(
        endpoint: smsEndpoint,
        sender: values['CS_RECOVERY_SMS_SENDER'] ?? '',
        apiKey: values['CS_RECOVERY_SMS_API_KEY'] ?? '',
      ),
      host: host,
      port: parsePort(
        values['CS_RECOVERY_SERVER_PORT'],
        8081,
        'CS_RECOVERY_SERVER_PORT',
      ),
      tlsCertPath: tlsCertPath,
      tlsKeyPath: tlsKeyPath,
    );
  }
}

/// Strict UUIDv4-v-shaped validator used for every caller-supplied reference.
bool isUuid(String value) => RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);

/// Strict port parsing: an invalid or out-of-range value must fail startup
/// instead of silently falling back to a different listener/provider port.
int parsePort(String? raw, int fallback, String name) {
  if (raw == null || raw.isEmpty) return fallback;
  final value = int.tryParse(raw);
  if (value == null || value < 1 || value > 65535) {
    throw RecoveryConfigException('$name must be an integer between 1 and 65535');
  }
  return value;
}

bool isLoopbackHost(String host) {
  if (host.toLowerCase() == 'localhost') return true;
  final address = InternetAddress.tryParse(host.replaceAll('[', '').replaceAll(']', ''));
  return address?.isLoopback ?? false;
}
