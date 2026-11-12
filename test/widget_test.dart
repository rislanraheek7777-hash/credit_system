import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
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
  });
}

