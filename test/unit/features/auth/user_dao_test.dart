import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/data/services/password_hash_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

void main() {
  late AppDatabase db;
  late UserDao userDao;
  late ShopDao shopDao;

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    userDao = UserDao(db);
    shopDao = ShopDao(db);

    // Create a base shop tenant for foreign key association
    await shopDao.createShop(
      ShopProfile(
        id: 'shop-alpha-100',
        name: 'Alpha Jewellers',
      ),
    );

    // Create a second shop tenant for multi-tenant isolation testing
    await shopDao.createShop(
      ShopProfile(
        id: 'shop-beta-200',
        name: 'Beta Jewellers',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('UserDao Local Persistence & Staff Administration Tests (Story 1.7)', () {
    test('creates and retrieves counter staff with default cashier permissions', () async {
      final user = AppUser(
        id: 'user-001',
        shopId: 'shop-alpha-100',
        username: 'staff.anura',
        fullName: 'Anura Kumara',
        role: AppRole.cashier,
      );

      await userDao.createUser(user);

      final retrieved = await userDao.getUserById('user-001');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('user-001'));
      expect(retrieved.shopId, equals('shop-alpha-100'));
      expect(retrieved.username, equals('staff.anura'));
      expect(retrieved.fullName, equals('Anura Kumara'));
      expect(retrieved.role, equals(AppRole.cashier));
      expect(retrieved.isActive, isTrue);
      expect(retrieved.sessionVersion, equals(1));
      expect(retrieved.hasPermission(AppPermission.recordPayments), isTrue);
      expect(retrieved.hasPermission(AppPermission.approveCorrections), isFalse);
    });

    test('creates and retrieves custom staff with granular permissions', () async {
      final customPermissions = {
        AppPermission.viewCustomers,
        AppPermission.viewOverdueCredits,
        AppPermission.confirmCollateralReturn,
      };

      final customUser = AppUser(
        id: 'user-002',
        shopId: 'shop-alpha-100',
        username: 'staff.custom',
        fullName: 'Custom Staff Member',
        role: AppRole.custom,
        customPermissions: customPermissions,
      );

      await userDao.createUser(customUser);

      final retrieved = await userDao.getUserById('user-002');
      expect(retrieved, isNotNull);
      expect(retrieved!.role, equals(AppRole.custom));
      expect(retrieved.customPermissions, equals(customPermissions));
      expect(retrieved.hasPermission(AppPermission.confirmCollateralReturn), isTrue);
      expect(retrieved.hasPermission(AppPermission.recordPayments), isFalse);
    });

    test('SHOP-SCOPED FILTERING: getUsersByShopId strictly returns only users for requested shop', () async {
      // 2 users in Shop Alpha
      await userDao.createUser(
        AppUser(
          id: 'alpha-user-1',
          shopId: 'shop-alpha-100',
          username: 'alpha.user1',
          fullName: 'Alpha User One',
          role: AppRole.shopOwner,
        ),
      );
      await userDao.createUser(
        AppUser(
          id: 'alpha-user-2',
          shopId: 'shop-alpha-100',
          username: 'alpha.user2',
          fullName: 'Alpha User Two',
          role: AppRole.cashier,
        ),
      );

      // 1 user in Shop Beta
      await userDao.createUser(
        AppUser(
          id: 'beta-user-1',
          shopId: 'shop-beta-200',
          username: 'beta.user1',
          fullName: 'Beta User One',
          role: AppRole.cashier,
        ),
      );

      final alphaUsers = await userDao.getUsersByShopId('shop-alpha-100');
      expect(alphaUsers.length, equals(2));
      expect(alphaUsers.map((u) => u.id), containsAll(['alpha-user-1', 'alpha-user-2']));
      expect(alphaUsers.any((u) => u.shopId != 'shop-alpha-100'), isFalse);

      final betaUsers = await userDao.getUsersByShopId('shop-beta-200');
      expect(betaUsers.length, equals(1));
      expect(betaUsers.first.id, equals('beta-user-1'));
    });

    test('SESSION REVOCATION ON PERMISSION UPDATE: increments sessionVersion to revoke sessions', () async {
      final user = AppUser(
        id: 'user-003',
        shopId: 'shop-alpha-100',
        username: 'staff.promoted',
        fullName: 'Promoted Staff',
        role: AppRole.cashier,
        sessionVersion: 1,
      );
      await userDao.createUser(user);

      // Promote from Cashier to Manager within shop-alpha-100
      await userDao.updateUserPermissions(
        'shop-alpha-100',
        'user-003',
        role: AppRole.manager,
      );

      final updated = await userDao.getUserById('user-003');
      expect(updated!.role, equals(AppRole.manager));
      expect(updated.sessionVersion, equals(2)); // Monotonically incremented!
      expect(updated.hasPermission(AppPermission.confirmCreditDisbursement), isTrue);
    });

    test('DEACTIVATION & SESSION REVOCATION: deactivating user sets isActive=false and increments sessionVersion', () async {
      final user = AppUser(
        id: 'user-004',
        shopId: 'shop-alpha-100',
        username: 'staff.terminated',
        fullName: 'Terminated Staff',
        role: AppRole.cashier,
        sessionVersion: 1,
      );
      await userDao.createUser(user);

      // Deactivate user within shop-alpha-100
      await userDao.deactivateUser('shop-alpha-100', 'user-004');

      final deactivated = await userDao.getUserById('user-004');
      expect(deactivated!.isActive, isFalse);
      expect(deactivated.sessionVersion, equals(2));

      // Token from old session (version 1) is immediately rejected by session validation
      expect(deactivated.isSessionValid(1), isFalse);
      // Even token with version 2 is rejected because account is deactivated
      expect(deactivated.isSessionValid(2), isFalse);
    });

    test('CROSS-SHOP MUTATION DEFENSE: mismatched shopId rejects permission update without altering target record or sessionVersion', () async {
      final user = AppUser(
        id: 'user-target-005',
        shopId: 'shop-alpha-100',
        username: 'alpha.victim',
        fullName: 'Alpha Victim Staff',
        role: AppRole.cashier,
        sessionVersion: 1,
      );
      await userDao.createUser(user);

      // Attempt to mutate user belonging to Shop Alpha using Shop Beta tenant scope
      expect(
        () => userDao.updateUserPermissions(
          'shop-beta-200',
          'user-target-005',
          role: AppRole.shopOwner,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot find user with ID "user-target-005" in shop "shop-beta-200"'),
        )),
      );

      // Verify the target record in Shop Alpha was NOT changed and sessionVersion was preserved
      final unchanged = await userDao.getUserById('user-target-005');
      expect(unchanged!.role, equals(AppRole.cashier));
      expect(unchanged.sessionVersion, equals(1));
    });

    test('CROSS-SHOP MUTATION DEFENSE: mismatched shopId rejects deactivation without altering active state or sessionVersion', () async {
      final user = AppUser(
        id: 'user-target-006',
        shopId: 'shop-alpha-100',
        username: 'alpha.victim2',
        fullName: 'Alpha Victim Staff 2',
        role: AppRole.cashier,
        sessionVersion: 1,
      );
      await userDao.createUser(user);

      // Attempt to deactivate user belonging to Shop Alpha using Shop Beta tenant scope
      expect(
        () => userDao.deactivateUser('shop-beta-200', 'user-target-006'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot find user with ID "user-target-006" in shop "shop-beta-200"'),
        )),
      );

      // Verify user remains active and sessionVersion unchanged
      final unchanged = await userDao.getUserById('user-target-006');
      expect(unchanged!.isActive, isTrue);
      expect(unchanged.sessionVersion, equals(1));
    });

    test('PASSWORD HASH: persists and retrieves passwordHash correctly', () async {
      final hash = '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash';
      final user = AppUser(
        id: 'user-pw-001',
        shopId: 'shop-alpha-100',
        username: 'staff.withhash',
        fullName: 'Staff With Hash',
        role: AppRole.cashier,
        passwordHash: hash,
      );

      await userDao.createUser(user);

      final retrieved = await userDao.getUserById('user-pw-001');
      expect(retrieved, isNotNull);
      expect(retrieved!.passwordHash, equals(hash));
    });

    test('PASSWORD HASH: user created without hash retains passwordHash == null', () async {
      final user = AppUser(
        id: 'user-pw-002',
        shopId: 'shop-alpha-100',
        username: 'staff.nohash',
        fullName: 'Staff No Hash',
        role: AppRole.cashier,
      );

      await userDao.createUser(user);

      final retrieved = await userDao.getUserById('user-pw-002');
      expect(retrieved, isNotNull);
      expect(retrieved!.passwordHash, isNull);
    });

    test('PASSWORD HASH: updateUserPassword increments sessionVersion and preserves shop scoping', () async {
      final user = AppUser(
        id: 'user-pw-003',
        shopId: 'shop-alpha-100',
        username: 'staff.pwupdate',
        fullName: 'Staff PW Update',
        role: AppRole.cashier,
        sessionVersion: 1,
      );
      await userDao.createUser(user);

      final newHash = '\$argon2id\$v=19\$m=65536,t=3,p=4\$newSalt\$newHash';
      await userDao.updateUserPassword(
        'shop-alpha-100',
        'user-pw-003',
        passwordHash: newHash,
      );

      final updated = await userDao.getUserById('user-pw-003');
      expect(updated!, isNotNull);
      expect(updated.passwordHash, equals(newHash));
      expect(updated.sessionVersion, equals(2)); // Incremented to revoke sessions
    });

    test('PASSWORD HASH: updateUserPassword rejects cross-shop updates', () async {
      final user = AppUser(
        id: 'user-pw-004',
        shopId: 'shop-alpha-100',
        username: 'staff.crossshop',
        fullName: 'Staff Cross Shop',
        role: AppRole.cashier,
      );
      await userDao.createUser(user);

      // Attempt to update password for user in Shop Alpha using Shop Beta scope
      expect(
        () => userDao.updateUserPassword(
          'shop-beta-200',
          'user-pw-004',
          passwordHash: '\$argon2id\$v=19\$m=65536,t=3,p=4\$salt\$hash',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot find user with ID "user-pw-004" in shop "shop-beta-200"'),
        )),
      );

      // Verify the user was not changed
      final unchanged = await userDao.getUserById('user-pw-004');
      expect(unchanged!.passwordHash, isNull);
      expect(unchanged.sessionVersion, equals(1));
    });

    test('CREATE USER WITH PASSWORD: hashes plaintext password before persistence', () async {
      final user = AppUser(
        id: 'user-pw-create-001',
        shopId: 'shop-alpha-100',
        username: 'staff.withpw',
        fullName: 'Staff With Password',
        role: AppRole.cashier,
      );

      const plaintext = 'InitialPassword123';
      await userDao.createUserWithPassword(user, plaintext);

      final retrieved = await userDao.getUserById('user-pw-create-001');
      expect(retrieved, isNotNull);
      expect(retrieved!.passwordHash, isNotNull);
      expect(retrieved.passwordHash, isNot(plaintext)); // plaintext not stored

      // The stored hash verifies the original password
      final service = PasswordHashService();
      expect(service.verifyPassword(plaintext, retrieved.passwordHash), isTrue);
      expect(service.verifyPassword('wrong-password', retrieved.passwordHash), isFalse);
    });

    test('CREATE USER WITH PASSWORD: rejects empty plaintext password', () async {
      final user = AppUser(
        id: 'user-pw-create-002',
        shopId: 'shop-alpha-100',
        username: 'staff.nopw',
        fullName: 'Staff No Password',
        role: AppRole.cashier,
      );

      expect(
        () => userDao.createUserWithPassword(user, ''),
        throwsA(isA<PasswordHashException>()),
      );
    });

    test('CREATE USER WITH PASSWORD: same username in same shop is rejected', () async {
      final user1 = AppUser(
        id: 'user-dup-001',
        shopId: 'shop-alpha-100',
        username: 'dup.user',
        fullName: 'Duplicate User',
        role: AppRole.cashier,
      );
      final user2 = AppUser(
        id: 'user-dup-002',
        shopId: 'shop-alpha-100',
        username: 'dup.user',
        fullName: 'Duplicate User Two',
        role: AppRole.cashier,
      );

      await userDao.createUserWithPassword(user1, 'Password123');

      expect(
        () => userDao.createUserWithPassword(user2, 'Password456'),
        throwsA(isA<Exception>()),
      );
    });

    test('CREATE USER WITH PASSWORD: same username in different shop is allowed', () async {
      final userAlpha = AppUser(
        id: 'user-shop-001',
        shopId: 'shop-alpha-100',
        username: 'same.user',
        fullName: 'Same User Alpha',
        role: AppRole.cashier,
      );
      final userBeta = AppUser(
        id: 'user-shop-002',
        shopId: 'shop-beta-200',
        username: 'same.user',
        fullName: 'Same User Beta',
        role: AppRole.cashier,
      );

      await userDao.createUserWithPassword(userAlpha, 'PasswordAlpha');
      await userDao.createUserWithPassword(userBeta, 'PasswordBeta');

      final alphaUser = await userDao.getUserById('user-shop-001');
      final betaUser = await userDao.getUserById('user-shop-002');
      expect(alphaUser!.username, equals('same.user'));
      expect(betaUser!.username, equals('same.user'));
      expect(alphaUser.shopId, equals('shop-alpha-100'));
      expect(betaUser.shopId, equals('shop-beta-200'));
    });

    test('login identifier: resolves user by username within shop', () async {
      final user = AppUser(
        id: 'user-login-001',
        shopId: 'shop-alpha-100',
        username: 'staff.login',
        email: 'login@example.com',
        phone: '+94771112222',
        fullName: 'Login User',
        role: AppRole.cashier,
      );
      await userDao.createUser(user);

      final byUsername = await userDao.getUserByLoginIdentifier(
        'shop-alpha-100',
        'staff.login',
      );
      expect(byUsername, isNotNull);
      expect(byUsername!.id, equals('user-login-001'));

      final byEmail = await userDao.getUserByLoginIdentifier(
        'shop-alpha-100',
        'login@example.com',
      );
      expect(byEmail, isNotNull);
      expect(byEmail!.id, equals('user-login-001'));

      final byPhone = await userDao.getUserByLoginIdentifier(
        'shop-alpha-100',
        '+94771112222',
      );
      expect(byPhone, isNotNull);
      expect(byPhone!.id, equals('user-login-001'));

      final missing = await userDao.getUserByLoginIdentifier(
        'shop-alpha-100',
        'nobody@example.com',
      );
      expect(missing, isNull);
    });

    test('login identifier: global lookup resolves across shops', () async {
      final user = AppUser(
        id: 'user-global-001',
        shopId: 'shop-beta-200',
        username: 'global.user',
        email: 'global@example.com',
        fullName: 'Global User',
        role: AppRole.cashier,
      );
      await userDao.createUser(user);

      final resolved = await userDao.getUserByLoginIdentifierGlobal(
        'global@example.com',
      );
      expect(resolved, isNotNull);
      expect(resolved!.shopId, equals('shop-beta-200'));

      final scopedMiss = await userDao.getUserByLoginIdentifier(
        'shop-alpha-100',
        'global@example.com',
      );
      expect(scopedMiss, isNull);
    });
  });
}

