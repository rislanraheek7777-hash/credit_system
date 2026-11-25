import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/data/daos/user_dao.dart';
import 'package:credit_system/features/auth/presentation/signup_screen.dart';

void main() {
  testWidgets('signup persists the exact username entered by the staff member',
      (tester) async {
    final db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(),
    );
    addTearDown(db.close);
    final userDao = UserDao(db);

    await tester.pumpWidget(MaterialApp(home: SignupScreen(database: db)));

    final fields = find.byType(TextFormField);
    expect(fields.evaluate().length, equals(6));
    await tester.enterText(fields.at(0), 'New Owner');
    await tester.enterText(
      find.byKey(const Key('signupUsernameField')),
      'new.owner',
    );
    await tester.enterText(fields.at(2), 'owner@example.test');
    await tester.enterText(fields.at(3), '+94770000009');
    await tester.enterText(fields.at(4), 'InitialPassword123');
    await tester.enterText(fields.at(5), 'InitialPassword123');

    await tester.tap(find.byKey(const Key('signup_button')));
    await tester.pumpAndSettle();

    final persisted = await userDao.getUserByUsername('default-shop', 'new.owner');
    expect(persisted, isNotNull);
    expect(persisted!.username, equals('new.owner'));
    expect(persisted.fullName, equals('New Owner'));
  });
}
