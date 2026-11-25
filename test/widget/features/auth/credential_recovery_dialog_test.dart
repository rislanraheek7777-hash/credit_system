import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/otp_gateway.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/presentation/credential_recovery_dialog.dart';

void main() {
  const genericMessage =
      'If the account exists, a recovery code has been sent.';
  const genericFailure =
      'Unable to complete recovery. Please check your details and try again.';
  const offlineMessage =
      'Recovery is unavailable while offline. Please try again when connected.';

  late _FakeAuthService fake;

  setUp(() {
    fake = _FakeAuthService();
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    bool isOnline = true,
    UserDao? userDao,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CredentialRecoveryDialog(
          authService: fake,
          isOnline: () async => isOnline,
          userDao: userDao,
        ),
      ),
    );
  }

  Future<void> requestCode(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('recoveryIdentifierField')),
      'staff.anura',
    );
    await tester.tap(find.byKey(const Key('recoveryRequestButton')));
    await tester.pumpAndSettle();
  }

  Future<void> confirmCode(
    WidgetTester tester,
    String otp, {
    String password = 'new-secure-password',
    String confirmation = 'new-secure-password',
  }) async {
    await tester.enterText(find.byKey(const Key('recoveryOtpField')), otp);
    await tester.enterText(
      find.byKey(const Key('recoveryNewPasswordField')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('recoveryConfirmPasswordField')),
      confirmation,
    );
    await tester.tap(find.byKey(const Key('recoveryConfirmButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('step one shows only the generic acknowledgement', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Recover access'), findsOneWidget);
    expect(find.byKey(const Key('recoveryIdentifierField')), findsOneWidget);
    expect(find.byKey(const Key('recoveryOtpField')), findsNothing);

    await requestCode(tester);

    expect(find.byKey(const Key('recoveryGenericMessage')), findsOneWidget);
    expect(find.text(genericMessage), findsOneWidget);
    // No username, shop id, or channel is disclosed before verification.
    expect(find.textContaining('staff.anura'), findsNothing);
    expect(find.byKey(const Key('recoveredUsername')), findsNothing);
    expect(find.textContaining('shop-'), findsNothing);
    expect(fake.lastChannel, equals(RecoveryChannel.email));
  });

  testWidgets('SMS channel selection is passed to the server', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.byKey(const Key('recoveryChannelSms')));
    await tester.pumpAndSettle();
    await requestCode(tester);

    expect(fake.lastChannel, equals(RecoveryChannel.sms));
  });

  testWidgets('username is shown only after successful OTP verification', (tester) async {
    await pumpDialog(tester);
    await requestCode(tester);

    await confirmCode(tester, 'correct-code');

    expect(find.byKey(const Key('recoveredUsername')), findsOneWidget);
    expect(find.text('Username: staff.anura'), findsOneWidget);
    expect(find.text('Password updated'), findsOneWidget);
    expect(fake.lastConfirmedOtp, equals('correct-code'));
    expect(fake.lastNewPassword, equals('new-secure-password'));
    expect(fake.lastConfirmedOperationId,
        equals('33333333-4444-4555-8666-777777777777'),
        reason: 'verify must use the authoritative stored operation id');
  });

  testWidgets('a failed verification shows the same generic error with no username', (tester) async {
    fake.confirmShouldFail = true;
    await pumpDialog(tester);
    await requestCode(tester);

    await confirmCode(tester, 'wrong-code');

    expect(find.byKey(const Key('recoveryError')), findsOneWidget);
    expect(find.text(genericFailure), findsOneWidget);
    expect(find.byKey(const Key('recoveredUsername')), findsNothing);
  });

  testWidgets('offline blocks both steps without calling the service', (tester) async {
    await pumpDialog(tester, isOnline: false);

    await requestCode(tester);

    expect(find.text(offlineMessage), findsOneWidget);
    expect(fake.requestCallCount, equals(0));
    expect(find.byKey(const Key('recoveryOtpField')), findsNothing);

    // The same gate applies to step two.
    await pumpDialog(tester, isOnline: true);
    await requestCode(tester);
    fake.confirmOffline = true;
    await confirmCode(tester, 'some-code');
    expect(find.text(offlineMessage), findsOneWidget);
    expect(fake.confirmCallCount, equals(1));
  });

  testWidgets('password must be at least 8 characters and confirmed', (tester) async {
    await pumpDialog(tester);
    await requestCode(tester);

    await confirmCode(tester, 'correct-code', password: 'short', confirmation: 'short');
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.byKey(const Key('recoveredUsername')), findsNothing);

    await confirmCode(
      tester,
      'correct-code',
      password: 'long-enough-password',
      confirmation: 'different-password',
    );
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.byKey(const Key('recoveredUsername')), findsNothing);
  });

  testWidgets('resend requests a fresh operation id and shows the same generic message', (tester) async {
    await pumpDialog(tester);
    await requestCode(tester);
    final firstOperationId = fake.lastClientOperationId;

    await tester.tap(find.byKey(const Key('recoveryResendButton')));
    await tester.pumpAndSettle();

    expect(fake.requestCallCount, equals(2));
    expect(fake.lastClientOperationId, isNot(equals(firstOperationId)));
    expect(find.byKey(const Key('recoveryGenericMessage')), findsOneWidget);
    expect(find.text('Username: staff.anura'), findsNothing);
  });

  testWidgets('a step-two failure clears the generic success notice', (tester) async {
    fake.confirmShouldFail = true;
    await pumpDialog(tester);
    await requestCode(tester);
    expect(find.byKey(const Key('recoveryGenericMessage')), findsOneWidget);

    await confirmCode(tester, 'wrong-code');

    expect(find.byKey(const Key('recoveryGenericMessage')), findsNothing);
    expect(find.byKey(const Key('recoveryError')), findsOneWidget);
  });

  testWidgets('request-level offline error is surfaced with the generic offline message', (tester) async {
    fake.requestOffline = true;
    await pumpDialog(tester);

    await requestCode(tester);

    expect(find.text(offlineMessage), findsOneWidget);
    expect(find.byKey(const Key('recoveryGenericMessage')), findsNothing);
    expect(find.byKey(const Key('recoveredUsername')), findsNothing);
  });

  testWidgets('cache-seeding failure keeps the reset success visible',
      (tester) async {
    final db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(),
    );
    addTearDown(db.close);

    await pumpDialog(tester, userDao: _FailingUserDao(db));
    await requestCode(tester);
    await confirmCode(tester, 'correct-code');

    expect(find.text('Password updated'), findsOneWidget);
    expect(find.byKey(const Key('recoveredUsername')), findsOneWidget);
    expect(find.byKey(const Key('recoveryCacheWarning')), findsOneWidget);
    expect(find.byKey(const Key('recoveryError')), findsNothing);
  });

  testWidgets('offline resend shows an error, never a green success message',
      (tester) async {
    await pumpDialog(tester);
    await requestCode(tester);
    expect(find.byKey(const Key('recoveryGenericMessage')), findsOneWidget);

    fake.requestOffline = true;
    await tester.tap(find.byKey(const Key('recoveryResendButton')));
    await tester.pumpAndSettle();

    expect(find.text(offlineMessage), findsOneWidget);
    expect(find.byKey(const Key('recoveryGenericMessage')), findsNothing);
  });

  testWidgets('a transport failure never shows the green success message',
      (tester) async {
    fake.requestFails = true;
    await pumpDialog(tester);

    await requestCode(tester);

    expect(find.text(genericFailure), findsOneWidget);
    expect(find.byKey(const Key('recoveryGenericMessage')), findsNothing);
    expect(find.byKey(const Key('recoveryOtpField')), findsNothing);
  });

  testWidgets('successful recovery seeds only minimal fresh-device identity',
      (tester) async {
    final db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(),
    );
    addTearDown(db.close);
    await ShopDao(db).createShop(
      ShopProfile(id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', name: 'Test Shop'),
    );
    final userDao = UserDao(db);

    await pumpDialog(tester, userDao: userDao);
    await requestCode(tester);
    await confirmCode(tester, 'correct-code');

    final seeded =
        await userDao.getUserById('11111111-2222-4333-8444-555555555555');
    expect(seeded, isNotNull);
    expect(seeded!.username, equals('staff.anura'));
    expect(seeded.shopId, equals('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
    expect(seeded.sessionVersion, equals(4));
    // Cache seeding never writes a password hash.
    expect(seeded.passwordHash, isNull);
  });
}

class _FailingUserDao extends UserDao {
  _FailingUserDao(super.db);

  @override
  Future<void> seedRecoveryIdentity({
    required String userId,
    required String shopId,
    required String username,
    required String role,
    required int sessionVersion,
  }) async {
    throw StateError('local cache unavailable');
  }
}

/// AuthService double that records calls instead of touching any database.
class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          jwt: JwtService('test-only-secret'),
          passwordHash: PasswordHashService(),
          secureStorage: _InMemorySecureStorage(),
        );

  RecoveryChannel? lastChannel;
  String? lastIdentifier;
  String? lastClientOperationId;
  String? lastConfirmedOperationId;
  String? lastConfirmedOtp;
  String? lastNewPassword;
  int requestCallCount = 0;
  int confirmCallCount = 0;
  bool requestOffline = false;
  bool requestFails = false;
  bool confirmOffline = false;
  bool confirmShouldFail = false;

  @override
  Future<CredentialRecoveryRequestResult> requestCredentialRecovery({
    required String identifier,
    required RecoveryChannel channel,
    required String clientOperationId,
    String? idempotencyKey,
  }) async {
    requestCallCount++;
    lastIdentifier = identifier;
    lastChannel = channel;
    lastClientOperationId = clientOperationId;
    if (requestOffline) {
      throw const CredentialRecoveryOfflineException();
    }
    if (requestFails) {
      throw const CredentialRecoveryException('transport failure');
    }
    // Simulate an authoritative acknowledgement that differs from the locally
    // generated id; /verify must use the stored one.
    return CredentialRecoveryRequestResult(
      clientOperationId: '33333333-4444-4555-8666-777777777777',
      idempotencyKey: idempotencyKey ?? clientOperationId,
    );
  }

  @override
  Future<CredentialRecoveryConfirmResult> confirmCredentialRecovery({
    required String clientOperationId,
    required String otp,
    required String newPassword,
  }) async {
    confirmCallCount++;
    lastConfirmedOperationId = clientOperationId;
    lastConfirmedOtp = otp;
    lastNewPassword = newPassword;
    if (confirmOffline) {
      throw const CredentialRecoveryOfflineException();
    }
    if (confirmShouldFail) {
      throw const CredentialRecoveryException('generic failure');
    }
    return const CredentialRecoveryConfirmResult(
      username: 'staff.anura',
      userId: '11111111-2222-4333-8444-555555555555',
      shopId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      role: 'cashier',
      sessionVersion: 4,
    );
  }
}

class _InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<bool> write({required String key, required String value}) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<bool> delete({required String key}) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<bool> deleteAll() async {
    _values.clear();
    return true;
  }
}

