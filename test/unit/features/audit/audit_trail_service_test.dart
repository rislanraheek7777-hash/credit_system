import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/audit/domain/models/audit_event_record.dart';
import 'package:credit_system/features/audit/domain/services/audit_trail_service.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';

void main() {
  const testShopId = 'shop-audit-01';

  final ownerUser = AppUser(
    id: 'user-owner-01',
    shopId: testShopId,
    username: 'shop.owner',
    fullName: 'Shop Owner',
    role: AppRole.shopOwner,
  );

  final auditorUser = AppUser(
    id: 'user-auditor-01',
    shopId: testShopId,
    username: 'auditor.staff',
    fullName: 'Auditor Staff',
    role: AppRole.custom,
    customPermissions: const {AppPermission.viewAuditLogs},
  );

  final cashierUser = AppUser(
    id: 'user-cashier-01',
    shopId: testShopId,
    username: 'counter.cashier',
    fullName: 'Counter Cashier',
    role: AppRole.cashier,
  );

  final now = DateTime.now().toUtc();

  final mockEvents = [
    AuditEventRecord(
      id: 'audit-001',
      shopId: testShopId,
      eventCategory: 1,
      actionType: 'customer_created',
      actorId: 'user-cashier-01',
      targetEntityType: 'customer',
      targetEntityId: 'cust-100',
      postStateJson: {'fullName': 'Sunil Perera', 'nic': '851234567V'},
      serverTimestamp: now.subtract(const Duration(minutes: 30)),
    ),
    AuditEventRecord(
      id: 'audit-002',
      shopId: testShopId,
      eventCategory: 2,
      actionType: 'loan_agreement_origination',
      actorId: 'user-cashier-01',
      targetEntityType: 'loan',
      targetEntityId: 'loan-201',
      postStateJson: {'principalCents': 5000000, 'balanceCents': 5000000},
      serverTimestamp: now.subtract(const Duration(minutes: 25)),
    ),
    AuditEventRecord(
      id: 'audit-003',
      shopId: testShopId,
      eventCategory: 2,
      actionType: 'cancel_loan_agreement',
      actorId: 'user-owner-01',
      targetEntityType: 'loan',
      targetEntityId: 'loan-202',
      reason: 'Customer withdrew agreement before disbursement',
      serverTimestamp: now.subtract(const Duration(minutes: 20)),
    ),
    AuditEventRecord(
      id: 'audit-004',
      shopId: testShopId,
      eventCategory: 2,
      actionType: 'loan_term_reagreed',
      actorId: 'user-owner-01',
      targetEntityType: 'loan',
      targetEntityId: 'loan-203',
      reason: 'Customer negotiated term extension before disbursement',
      serverTimestamp: now.subtract(const Duration(minutes: 15)),
    ),
    AuditEventRecord(
      id: 'audit-005',
      shopId: testShopId,
      eventCategory: 12,
      actionType: 'staff_user_created',
      actorId: 'user-owner-01',
      targetEntityType: 'app_user',
      targetEntityId: 'user-staff-02',
      postStateJson: {
        'username': 'new.cashier',
        'password_hash': 'argon2id\$secret_hash_value',
        'role': 'cashier',
      },
      serverTimestamp: now.subtract(const Duration(minutes: 10)),
    ),
    AuditEventRecord(
      id: 'audit-006',
      shopId: testShopId,
      eventCategory: 14,
      actionType: 'unauthorized_customer_profile_access',
      actorId: 'user-cashier-01',
      targetEntityType: 'customer',
      targetEntityId: 'cust-999',
      reason: 'User lacks viewCustomers permission',
      serverTimestamp: now.subtract(const Duration(minutes: 5)),
    ),
  ];

  late AuditTrailService service;

  setUp(() {
    service = AuditTrailService(localMockStore: mockEvents);
  });

  group('Story 7.3: AuditTrailService RBAC & Inspection', () {
    test('AC-1: Shop Owner and Auditor with viewAuditLogs can retrieve audit logs', () async {
      final ownerRecords = await service.getAuditEvents(
        shopId: testShopId,
        actor: ownerUser,
      );
      expect(ownerRecords.length, equals(6));

      final auditorRecords = await service.getAuditEvents(
        shopId: testShopId,
        actor: auditorUser,
      );
      expect(auditorRecords.length, equals(6));
    });

    test('AC-1: Cashier without viewAuditLogs is rejected with 403 Forbidden', () async {
      expect(
        () => service.getAuditEvents(
          shopId: testShopId,
          actor: cashierUser,
        ),
        throwsA(isA<AuditAccessForbiddenException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(403),
        )),
      );
    });

    test('Cross-tenant inspection attempt is blocked with 403 Forbidden', () async {
      expect(
        () => service.getAuditEvents(
          shopId: 'shop-unauthorized-99',
          actor: auditorUser,
        ),
        throwsA(isA<AuditAccessForbiddenException>()),
      );
    });

    test('Filtering by category returns only matching category records', () async {
      // Category 2: Loan agreement actions
      final cat2Records = await service.getAuditEvents(
        shopId: testShopId,
        actor: ownerUser,
        categoryFilter: 2,
      );

      expect(cat2Records.length, equals(3));
      expect(
        cat2Records.map((e) => e.actionType).toSet(),
        containsAll([
          'loan_agreement_origination',
          'cancel_loan_agreement',
          'loan_term_reagreed',
        ]),
      );

      // Category 14: Security events
      final cat14Records = await service.getAuditEvents(
        shopId: testShopId,
        actor: ownerUser,
        categoryFilter: 14,
      );
      expect(cat14Records.length, equals(1));
      expect(cat14Records.first.actionType, equals('unauthorized_customer_profile_access'));
    });

    test('Filtering by actorId returns only records authored by that actor', () async {
      final cashierLogs = await service.getAuditEvents(
        shopId: testShopId,
        actor: ownerUser,
        actorIdFilter: 'user-cashier-01',
      );
      expect(cashierLogs.length, equals(3));
      for (final l in cashierLogs) {
        expect(l.actorId, equals('user-cashier-01'));
      }
    });

    test('AC-2: Sensitive password/token keys in pre/post snapshots are redacted strictly', () {
      final staffCreatedRecord = mockEvents.firstWhere(
        (e) => e.actionType == 'staff_user_created',
      );

      // Raw map has password_hash
      expect(staffCreatedRecord.postStateJson!['password_hash'], equals('argon2id\$secret_hash_value'));

      // Sanitized map strictly redacts it
      final sanitized = staffCreatedRecord.sanitizedPostState!;
      expect(sanitized['username'], equals('new.cashier'));
      expect(sanitized['password_hash'], equals('[REDACTED]'));
    });
  });
}
