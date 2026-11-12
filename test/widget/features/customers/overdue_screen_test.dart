import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/customers/presentation/overdue_screen.dart';
import 'package:drift/drift.dart';

void main() {
  late AppDatabase db;

  const shopId = 'shop-overdue-001';
  const ownerId = 'owner-overdue-001';

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);

    final now = DateTime.now().toUtc();

    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Overdue Test Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: ownerId,
        shopId: shopId,
        username: 'owner',
        fullName: 'Shop Owner',
        role: 'shop_owner',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedOverdueCredit({
    int customerId = 1,
    String creditId = 'credit-overdue-001',
    int balanceCents = 500000,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now().toUtc();

    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Overdue Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.credits).insert(
      CreditsCompanion.insert(
        id: creditId,
        shopId: shopId,
        customerId: customerId,
        principalCents: balanceCents,
        balanceCents: balanceCents,
        status: const Value('active'),
        workflowStatus: const Value('disbursed'),
        termPresetDays: const Value(30),
        dueDate: dueDate ?? DateTime.utc(2026, 9, 1),
        disbursedAt: Value(DateTime.utc(2026, 8, 1)),
        disbursedByUserId: Value(ownerId),
        createdAt: now,
      ),
    );
  }

  group('OverdueScreen Widget Tests (Story 6.1)', () {
    testWidgets('shows no overdue credits when none exist', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OverdueScreen(
            shopId: shopId,
            currentUser: AppUser(
              id: ownerId,
              shopId: shopId,
              username: 'owner',
              fullName: 'Shop Owner',
              role: AppRole.shopOwner,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overdue Credits'), findsOneWidget);
      expect(find.text('No overdue credits.'), findsOneWidget);
    });

    testWidgets('shows overdue credit with days overdue counter', (
      WidgetTester tester,
    ) async {
      // Create a credit with due date in the past
      final pastDueDate = DateTime.utc(2026, 9, 1);
      await seedOverdueCredit(
        creditId: 'credit-past-due-001',
        dueDate: pastDueDate,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OverdueScreen(
            shopId: shopId,
            currentUser: AppUser(
              id: ownerId,
              shopId: shopId,
              username: 'owner',
              fullName: 'Shop Owner',
              role: AppRole.shopOwner,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overdue Credits'), findsOneWidget);
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('Status: OVERDUE'), findsOneWidget);
      expect(find.textContaining('Days Overdue:'), findsOneWidget);
    });

    testWidgets('rejects non-owner access', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OverdueScreen(
            shopId: shopId,
            currentUser: AppUser(
              id: 'cashier-id',
              shopId: shopId,
              username: 'cashier',
              fullName: 'Cashier',
              role: AppRole.cashier,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Access denied'), findsOneWidget);
    });

    testWidgets('Story 6.2: Shop Owner can grant due date extension', (
      WidgetTester tester,
    ) async {
      await seedOverdueCredit(
        creditId: 'credit-ext-001',
        dueDate: DateTime.utc(2026, 9, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OverdueScreen(
            shopId: shopId,
            currentUser: AppUser(
              id: ownerId,
              shopId: shopId,
              username: 'owner',
              fullName: 'Shop Owner',
              role: AppRole.shopOwner,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('extend_due_date_button_credit-ext-001')), findsOneWidget);

      await tester.tap(find.byKey(const Key('extend_due_date_button_credit-ext-001')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Grant Due Date Extension'), findsOneWidget);

      // Enter extension reason
      await tester.enterText(
        find.byKey(const Key('extension_reason_field')),
        'Borrower requested 2 weeks extension due to illness',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('submit_extension_button')));
      await tester.pumpAndSettle();

      // Credit should have reset to active and no longer appear in overdue list
      expect(find.text('No overdue credits.'), findsOneWidget);
      expect(find.textContaining('Status: ACTIVE'), findsOneWidget);
    });

    testWidgets('Story 6.3: Staff can log follow-up and see promised pay date banner', (
      WidgetTester tester,
    ) async {
      await seedOverdueCredit(
        creditId: 'credit-followup-001',
        dueDate: DateTime.utc(2026, 9, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OverdueScreen(
            shopId: shopId,
            currentUser: AppUser(
              id: ownerId,
              shopId: shopId,
              username: 'owner',
              fullName: 'Shop Owner',
              role: AppRole.shopOwner,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('log_follow_up_button_credit-followup-001')), findsOneWidget);

      await tester.tap(find.byKey(const Key('log_follow_up_button_credit-followup-001')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Log Customer Follow-Up'), findsOneWidget);

      // Enter notes
      await tester.enterText(
        find.byKey(const Key('follow_up_notes_field')),
        'Spoke with customer; promised to pay next week.',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('submit_follow_up_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Follow-up logged'), findsOneWidget);
    });

    testWidgets('Story 6.4: Shop Owner can record structured resolution', (
      WidgetTester tester,
    ) async {
      await seedOverdueCredit(
        creditId: 'credit-res-001',
        dueDate: DateTime.utc(2026, 9, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: OverdueScreen(
            shopId: shopId,
            currentUser: AppUser(
              id: ownerId,
              shopId: shopId,
              username: 'owner',
              fullName: 'Shop Owner',
              role: AppRole.shopOwner,
              isActive: true,
            ),
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('resolve_case_button_credit-res-001')), findsOneWidget);

      await tester.tap(find.byKey(const Key('resolve_case_button_credit-res-001')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Owner Case Resolution'), findsOneWidget);

      // Enter rationale
      await tester.enterText(
        find.byKey(const Key('resolution_reason_field')),
        'Case flagged for investigation; legal notice sent.',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('submit_resolution_button')));
      await tester.pumpAndSettle();

      // Resolution badge should be displayed
      expect(find.text('UNDER REVIEW'), findsOneWidget);
    });
  });
}

