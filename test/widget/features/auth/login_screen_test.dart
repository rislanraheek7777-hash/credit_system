import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/data/secure_storage.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/auth_service.dart';
import 'package:credit_system/features/auth/data/services/jwt_service.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/auth/presentation/login_screen.dart';
import 'package:credit_system/features/auth/presentation/signup_screen.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

void main() {
  late AppDatabase db;
  late ShopDao shopDao;
  late UserDao userDao;
  late _TestAuthService fakeAuth;

  setUp(() async {
    db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(),
    );
    shopDao = ShopDao(db);
    userDao = UserDao(db);
    await shopDao.createShop(
      ShopProfile(id: 'shop-a', name: 'Alpha Jewellers'),
    );
    await shopDao.createShop(
      ShopProfile(id: 'shop-b', name: 'Beta Jewellers'),
    );
    addTearDown(db.close);
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    fakeAuth = _TestAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          injectedDatabase: db,
          injectedAuthService: fakeAuth,
          onAuthenticated: (user, offline) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the username-only migration notice', (tester) async {
    await pumpLogin(tester);
    expect(find.byKey(const Key('usernameOnlyNotice')), findsOneWidget);
    expect(
      find.textContaining('Email and phone are no longer login identifiers'),
      findsOneWidget,
    );
  });

  testWidgets('signup exposes the username field used for login', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SignupScreen()),
    );
    expect(find.byKey(const Key('signupUsernameField')), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
  });

  testWidgets('forgot-credentials button opens the recovery dialog',
      (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.byKey(const Key('forgotCredentialsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Recover access'), findsOneWidget);
    expect(find.byKey(const Key('recoveryIdentifierField')), findsOneWidget);
  });

  testWidgets('a cached username in two tenants requires an explicit choice', (tester) async {
    for (final shopId in ['shop-a', 'shop-b']) {
      await userDao.createUser(
        AppUser(
          id: 'user-$shopId',
          shopId: shopId,
          username: 'shared.user',
          fullName: 'Shared User',
          role: AppRole.cashier,
        ),
      );
    }
    await pumpLogin(tester);

    await tester.enterText(
      find.byKey(const Key('usernameField')),
      'shared.user',
    );
    await tester.enterText(
      find.byKey(const Key('passwordField')),
      'some-password',
    );
    await tester.tap(find.text('Login'));
    // The login button shows a looping progress indicator while the tenant
    // picker is resolved, so pump fixed frames instead of pumping to settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Select your shop'), findsOneWidget);
    expect(find.byKey(const Key('tenantOption-shop-a')), findsOneWidget);
    expect(find.byKey(const Key('tenantOption-shop-b')), findsOneWidget);
    expect(find.text('Alpha Jewellers'), findsOneWidget);
    expect(find.text('Beta Jewellers'), findsOneWidget);

    // Selecting a tenant must drive the login for that tenant, never the
    // first cached shop.
    await tester.tap(find.byKey(const Key('tenantOption-shop-b')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fakeAuth.authenticatedShopId, equals('shop-b'));
  });
}

class _TestAuthService extends AuthService {
  _TestAuthService()
      : super(
          jwt: JwtService('test-only-secret'),
          passwordHash: PasswordHashService(),
          secureStorage: _InMemorySecureStorage(),
        );

  String? authenticatedShopId;

  @override
  Future<AuthResult> authenticate(
    String shopId,
    String username,
    String password,
  ) async {
    authenticatedShopId = shopId;
    throw StateError('stop after recording tenant');
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
