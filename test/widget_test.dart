import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/main.dart';

void main() {
  testWidgets('Credit System smoke test', (WidgetTester tester) async {
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
        home: MainApp(shopId: 'shop-smoke-1', currentUser: currentUser),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
  });
}
