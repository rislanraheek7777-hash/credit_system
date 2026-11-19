import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/settings/presentation/settings_screen.dart';
import 'package:credit_system/main.dart';

void main() {
  testWidgets('Credit System smoke test', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(
        closeStreamsSynchronously: true,
      ),
    );
    var closed = false;
    Future<void> closeDb() async {
      if (closed) return;
      closed = true;
      await db.close();
    }

    addTearDown(closeDb);

    final currentUser = AppUser(
      id: 'user-smoke-1',
      shopId: 'shop-smoke-1',
      username: 'smoke.owner',
      fullName: 'Smoke Owner',
      role: AppRole.shopOwner,
      isActive: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainApp(
          shopId: 'shop-smoke-1',
          currentUser: currentUser,
          database: db,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Credit Details'), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-settings')), findsOneWidget);

    // The Settings bottom-nav tab renders the settings hub (owner sees
    // Staff Management; MainApp wires onLogout, so Logout is shown).
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Shop Profile'), findsOneWidget);
    expect(find.text('Staff Management'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);

    // Regression guard: the Customers AppBar no longer carries the
    // Settings/Shop Profile/Staff Management action IconButtons.
    await tester.tap(find.byKey(const ValueKey('nav-customers')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
  });

  testWidgets('Settings tab hides Staff Management from non-owners', (
    WidgetTester tester,
  ) async {
    final db = AppDatabase.forTesting(
      AppDatabaseConnection.openInMemoryConnection(
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);

    final staffUser = AppUser(
      id: 'user-staff-1',
      shopId: 'shop-smoke-1',
      username: 'smoke.staff',
      fullName: 'Smoke Staff',
      role: AppRole.manager,
      isActive: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainApp(
          shopId: 'shop-smoke-1',
          currentUser: staffUser,
          database: db,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Shop Profile'), findsOneWidget);
    expect(find.text('Staff Management'), findsNothing);
  });

  testWidgets('Settings without onLogout shows no Logout tile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          shopId: 'shop-smoke-1',
          currentUser: AppUser(
            id: 'user-smoke-1',
            shopId: 'shop-smoke-1',
            username: 'smoke.owner',
            fullName: 'Smoke Owner',
            role: AppRole.shopOwner,
            isActive: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Logout'), findsNothing);
  });

  testWidgets('Settings logout requires confirmation and fires onLogout', (
    WidgetTester tester,
  ) async {
    var loggedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          shopId: 'shop-smoke-1',
          currentUser: AppUser(
            id: 'user-smoke-1',
            shopId: 'shop-smoke-1',
            username: 'smoke.owner',
            fullName: 'Smoke Owner',
            role: AppRole.shopOwner,
            isActive: true,
          ),
          onLogout: () => loggedOut = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    // Confirmation dialog is shown; no logout before confirming.
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);
    expect(loggedOut, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
    await tester.pumpAndSettle();

    expect(loggedOut, isTrue);
  });
}

