import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:uuid/uuid.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/data/daos/overdue_dao.dart';
import 'package:credit_system/features/customers/domain/models/customer_follow_up.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/loan_resolution.dart';

void main() {
  late AppDatabase db;
  late OverdueDao overdueDao;

  const shopId = 'shop-gov-001';
  const ownerId = 'owner-gov-001';
  const cashierId = 'cashier-gov-001';
  const customerId = 'cust-gov-001';
  const loanId = 'loan-gov-001';

  final ownerUser = AppUser(
    id: ownerId,
    shopId: shopId,
    username: 'owner',
    fullName: 'Shop Owner',
    role: AppRole.shopOwner,
    isActive: true,
  );

  final cashierUser = AppUser(
    id: cashierId,
    shopId: shopId,
    username: 'cashier',
    fullName: 'Counter Cashier',
    role: AppRole.cashier,
    isActive: true,
  );

  final cashierWithNotes = AppUser(
    id: cashierId,
    shopId: shopId,
    username: 'cashier',
    fullName: 'Counter Cashier',
    role: AppRole.custom,
    isActive: true,
    customPermissions: {AppPermission.recordCustomerNotes},
  );

  setUp(() async {
    final executor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(executor);
    overdueDao = OverdueDao(db);

    final now = DateTime.now().toUtc();

    await db.into(db.shops).insert(
      ShopEntry(
        id: shopId,
        name: 'Governance Test Shop',
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

    await db.into(db.appUsers).insert(
      AppUserEntry(
        id: cashierId,
        shopId: shopId,
        username: 'cashier',
        fullName: 'Counter Cashier',
        role: 'cashier',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.customers).insert(
      CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Test Borrower',
        nic: '901234567V',
        phone: '0712345678',
        address: 'Colombo 03',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.into(db.loans).insert(
      LoansCompanion.insert(
        id: loanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 1000000,
        balanceCents: 1000000,
        status: const Value('overdue'),
        workflowStatus: const Value('disbursed'),
        dueDate: DateTime.utc(2026, 9, 1),
        createdAt: now,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Story 6.2: Due Date Extension Tests', () {
    test('grantDueDateExtension resets overdue status to active and updates dueDate', () async {
      final newDueDate = DateTime.now().add(const Duration(days: 14));
      final updated = await overdueDao.grantDueDateExtension(
        actor: ownerUser,
        idempotencyKey: const Uuid().v4(),
        loanId: loanId,
        newDueDate: newDueDate,
        reason: 'Customer requested 2-week extension due to family emergency',
      );

      expect(updated.status, equals(LoanStatus.active));
      expect(updated.workflowStatus, equals(LoanWorkflowStatus.disbursed));

      final history = await overdueDao.getExtensionHistory(
        shopId: shopId,
        loanId: loanId,
      );
      expect(history.length, equals(1));
      expect(history.first.reason, contains('family emergency'));
      expect(history.first.grantedByUserId, equals(ownerId));

      // Verify audit event category 8 in SyncQueue
      final syncQueueRows = await db.select(db.syncQueue).get();
      final extensionEvents = syncQueueRows.where((r) => r.actionType == 'grant_due_date_extension');
      expect(extensionEvents, isNotEmpty);
      expect(extensionEvents.first.payloadJson, contains('"auditCategory":8'));
    });

    test('grantDueDateExtension rejects non-owner actor', () async {
      final newDueDate = DateTime.now().add(const Duration(days: 14));
      expect(
        () => overdueDao.grantDueDateExtension(
          actor: cashierUser,
          idempotencyKey: const Uuid().v4(),
          loanId: loanId,
          newDueDate: newDueDate,
          reason: 'Cashier attempt',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('grantDueDateExtension rejects past or same-day due date', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 1));
      expect(
        () => overdueDao.grantDueDateExtension(
          actor: ownerUser,
          idempotencyKey: const Uuid().v4(),
          loanId: loanId,
          newDueDate: pastDate,
          reason: 'Invalid past date',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('grantDueDateExtension rejects empty reason', () async {
      final newDueDate = DateTime.now().add(const Duration(days: 14));
      expect(
        () => overdueDao.grantDueDateExtension(
          actor: ownerUser,
          idempotencyKey: const Uuid().v4(),
          loanId: loanId,
          newDueDate: newDueDate,
          reason: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Story 6.3: Delinquency Customer Follow-Up Tests', () {
    test('recordFollowUp records note and optional promised payment date', () async {
      final promisedDate = DateTime.now().add(const Duration(days: 5));
      final followUp = await overdueDao.recordFollowUp(
        actor: cashierWithNotes,
        loanId: loanId,
        customerId: customerId,
        channel: FollowUpChannel.phoneCall,
        notes: 'Contacted borrower; agreed to pay partial amount next Friday.',
        promisedPaymentDate: promisedDate,
      );

      expect(followUp.notes, contains('agreed to pay'));
      expect(followUp.channel, equals(FollowUpChannel.phoneCall));
      expect(followUp.promisedPaymentDate, isNotNull);

      final followUps = await overdueDao.getFollowUps(
        shopId: shopId,
        loanId: loanId,
      );
      expect(followUps.length, equals(1));
      expect(followUps.first.id, equals(followUp.id));

      // Verify audit event category 9 in SyncQueue
      final syncQueueRows = await db.select(db.syncQueue).get();
      final followUpEvents = syncQueueRows.where((r) => r.actionType == 'record_customer_follow_up');
      expect(followUpEvents, isNotEmpty);
      expect(followUpEvents.first.payloadJson, contains('"auditCategory":9'));
    });

    test('recordFollowUp rejects actor without recordCustomerNotes permission', () async {
      final userWithoutNotes = AppUser(
        id: 'no-notes-user',
        shopId: shopId,
        username: 'nonotes',
        fullName: 'No Notes User',
        role: AppRole.custom,
        isActive: true,
        customPermissions: {},
      );

      expect(
        () => overdueDao.recordFollowUp(
          actor: userWithoutNotes,
          loanId: loanId,
          customerId: customerId,
          channel: FollowUpChannel.phoneCall,
          notes: 'No permission note',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('recordFollowUp rejects empty notes', () async {
      expect(
        () => overdueDao.recordFollowUp(
          actor: cashierWithNotes,
          loanId: loanId,
          customerId: customerId,
          channel: FollowUpChannel.inPerson,
          notes: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Story 6.4: Owner Case Resolution Tests', () {
    test('recordResolution saves structured administrative resolution', () async {
      final resolution = await overdueDao.recordResolution(
        actor: ownerUser,
        loanId: loanId,
        resolutionType: LoanResolutionType.collateralRetained,
        reason: 'Borrower untraceable after formal notices; collateral held for legal determination.',
      );

      expect(resolution.resolutionType, equals(LoanResolutionType.collateralRetained));
      expect(resolution.reason, contains('untraceable'));
      expect(resolution.resolvedByUserId, equals(ownerId));

      final latest = await overdueDao.getLatestResolution(
        shopId: shopId,
        loanId: loanId,
      );
      expect(latest, isNotNull);
      expect(latest!.id, equals(resolution.id));

      // Verify audit event category 10 in SyncQueue
      final syncQueueRows = await db.select(db.syncQueue).get();
      final resEvents = syncQueueRows.where((r) => r.actionType == 'record_loan_resolution');
      expect(resEvents, isNotEmpty);
      expect(resEvents.first.payloadJson, contains('"auditCategory":10'));
    });

    test('recordResolution rejects non-owner actor', () async {
      expect(
        () => overdueDao.recordResolution(
          actor: cashierUser,
          loanId: loanId,
          resolutionType: LoanResolutionType.underReview,
          reason: 'Cashier trying to resolve',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('recordResolution rejects empty reason', () async {
      expect(
        () => overdueDao.recordResolution(
          actor: ownerUser,
          loanId: loanId,
          resolutionType: LoanResolutionType.ownerSettledWrittenOff,
          reason: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
