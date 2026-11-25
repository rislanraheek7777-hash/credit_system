import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:credential_recovery_backend/src/audit.dart';
import 'package:credential_recovery_backend/src/config.dart';
import 'package:credential_recovery_backend/src/database.dart';
import 'package:credential_recovery_backend/src/delivery.dart';
import 'package:credential_recovery_backend/src/otp.dart';
import 'package:credential_recovery_backend/src/reference.dart';
import 'package:credential_recovery_backend/src/routes.dart';

/// Entrypoint of the standalone credential recovery authority.
///
/// Start with:
///   dart run bin/server.dart
///
/// All secrets and connection details are read from OS environment variables.
/// Schema migration is never performed here; run `bin/migrate.dart` or have a
/// DBA apply `003_credential_recovery.sql` explicitly.
Future<void> main() async {
  final config = RecoveryConfig.fromEnvironment();
  final database = PgRecoveryDatabase(config.databaseUrl);

  // Fail closed if the reserved abuse tenant does not exist: otherwise the
  // system-actor row cannot be created and Category 14 events would be lost.
  final abuseShop = await database.transactionWithTenant(
    config.abuseShopId,
    (tx) => tx.query(
      'SELECT id FROM public.shops WHERE id = @p0::uuid',
      [config.abuseShopId],
    ),
  );
  if (abuseShop.isEmpty) {
    throw StateError(
      'CS_RECOVERY_ABUSE_SHOP_ID does not match a reserved shop record',
    );
  }

  final routes = RecoveryRoutes(
    database: database,
    auditor: RecoveryAuditor(database, config.abuseShopId),
    otp: OtpAuthority(config.otpPepper),
    reference: OperationReference(config.otpPepper),
    delivery: RecoveryDelivery(
      config.smtp,
      config.sms,
      httpClient: http.Client(),
    ),
    passwordHasher: Argon2PasswordHasher(),
  );

  SecurityContext? securityContext;
  if (config.servesTls) {
    securityContext = SecurityContext()
      ..useCertificateChain(config.tlsCertPath)
      ..usePrivateKey(config.tlsKeyPath);
  }
  final server = await shelf_io.serve(
    routes.handler,
    config.host,
    config.port,
    securityContext: securityContext,
  );
  stdout.writeln(
    'Credential recovery authority listening on '
    '${server.address.host}:${server.port}',
  );

  // Graceful shutdown: stop accepting requests, then release the DB pool.
  await Future.any<Object>([
    ProcessSignal.sigterm.watch().first,
    ProcessSignal.sigint.watch().first,
  ]);
  await server.close();
  await database.close();
}
