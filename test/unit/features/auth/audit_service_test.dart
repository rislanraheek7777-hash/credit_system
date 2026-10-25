import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/remote/migration_runner.dart';
import 'package:credit_system/core/data/remote/postgres_executor.dart';
import 'package:credit_system/features/auth/data/services/audit_service.dart';

/// Mock [PostgreSqlExecutor] for unit testing [AuditService].
class MockPostgreSqlExecutor extends PostgreSqlExecutor {
  MockPostgreSqlExecutor() : super.withConnectionString('');

  final List<String> tenantContexts = [];
  final List<String> executedStatements = [];

  @override
  Future<T> transactionWithTenant<T>(
    String shopId,
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) async {
    tenantContexts.add(shopId);
    final mockTx = _MockSqlExecutor(this);
    return await action(mockTx);
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    executedStatements.add(sql);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    executedStatements.add(sql);
    return [];
  }
}

class _MockSqlExecutor implements SqlDatabaseExecutor {
  final MockPostgreSqlExecutor _pg;

  _MockSqlExecutor(this._pg);

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    _pg.executedStatements.add(sql);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    _pg.executedStatements.add(sql);
    return [];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) {
    return action(this);
  }
}

void main() {
  group('AuditService - Append-Only Audit Event Recording (Story 1.8)', () {
    late MockPostgreSqlExecutor mockPg;
    late AuditService auditService;

    setUp(() {
      mockPg = MockPostgreSqlExecutor();
      auditService = AuditService(mockPg);
    });

    test('recordAuditEvent inserts an audit event into audit_events', () async {
      await auditService.recordAuditEvent(
        shopId: 'shop-uuid-456',
        eventCategory: 12,
        actionType: 'staff_deactivated',
        actorId: 'user-uuid-123',
        targetEntityType: 'app_user',
        targetEntityId: 'user-uuid-456',
        reason: 'Staff account deactivated; session revoked',
      );

      // Verify cs_record_audit_event was executed
      final insertSql = mockPg.executedStatements.where(
        (s) => s.contains('cs_record_audit_event'),
      );
      expect(insertSql.isNotEmpty, isTrue);

      // Verify tenant context was set
      expect(mockPg.tenantContexts, contains('shop-uuid-456'));
    });

    test('recordAuditEvent sets transaction-local tenant context', () async {
      await auditService.recordAuditEvent(
        shopId: 'shop-uuid-789',
        eventCategory: 1,
        actionType: 'customer_created',
        actorId: 'user-uuid-123',
        targetEntityType: 'customer',
        targetEntityId: 'customer-uuid-111',
      );

      expect(mockPg.tenantContexts, contains('shop-uuid-789'));
    });

    test('recordAuditEvent validates event category range', () async {
      await expectLater(
        auditService.recordAuditEvent(
          shopId: 'shop-uuid-456',
          eventCategory: 0,
          actionType: 'test',
          actorId: 'user-uuid-123',
          targetEntityType: 'test',
          targetEntityId: 'test-id',
        ),
        throwsA(isA<AuditServiceException>()),
      );

      await expectLater(
        auditService.recordAuditEvent(
          shopId: 'shop-uuid-456',
          eventCategory: 15,
          actionType: 'test',
          actorId: 'user-uuid-123',
          targetEntityType: 'test',
          targetEntityId: 'test-id',
        ),
        throwsA(isA<AuditServiceException>()),
      );
    });

    test('recordAuditEvent rejects missing required fields', () async {
      await expectLater(
        auditService.recordAuditEvent(
          shopId: '',
          eventCategory: 1,
          actionType: 'test',
          actorId: 'user-uuid-123',
          targetEntityType: 'test',
          targetEntityId: 'test-id',
        ),
        throwsA(isA<AuditServiceException>()),
      );

      await expectLater(
        auditService.recordAuditEvent(
          shopId: 'shop-uuid-456',
          eventCategory: 1,
          actionType: '',
          actorId: 'user-uuid-123',
          targetEntityType: 'test',
          targetEntityId: 'test-id',
        ),
        throwsA(isA<AuditServiceException>()),
      );

      await expectLater(
        auditService.recordAuditEvent(
          shopId: 'shop-uuid-456',
          eventCategory: 1,
          actionType: 'test',
          actorId: '',
          targetEntityType: 'test',
          targetEntityId: 'test-id',
        ),
        throwsA(isA<AuditServiceException>()),
      );
    });

    test('recordAuditEvent stores pre_state_json and post_state_json', () async {
      await auditService.recordAuditEvent(
        shopId: 'shop-uuid-456',
        eventCategory: 12,
        actionType: 'permission_modified',
        actorId: 'user-uuid-123',
        targetEntityType: 'app_user',
        targetEntityId: 'user-uuid-456',
        preState: {'role': 'cashier', 'permissions': ['recordPayments']},
        postState: {'role': 'manager', 'permissions': ['recordPayments', 'confirmLoanDisbursement']},
        reason: 'Promoted from Cashier to Manager',
      );

      final insertSql = mockPg.executedStatements.firstWhere(
        (s) => s.contains('cs_record_audit_event'),
      );
      // pre_state_json is @p6, post_state_json is @p7 in the function parameter list
      expect(insertSql.contains('@p6'), isTrue);
      expect(insertSql.contains('@p7'), isTrue);
    });

    test('recordAuditEvent stores optional client_ip and user_agent', () async {
      await auditService.recordAuditEvent(
        shopId: 'shop-uuid-456',
        eventCategory: 14,
        actionType: 'unauthorized_access_attempt',
        actorId: 'user-uuid-123',
        targetEntityType: 'app_user',
        targetEntityId: 'user-uuid-999',
        clientIp: '192.168.1.100',
        userAgent: 'Mozilla/5.0',
      );

      final insertSql = mockPg.executedStatements.firstWhere(
        (s) => s.contains('cs_record_audit_event'),
      );
      expect(insertSql.contains('@p9'), isTrue); // client_ip parameter
      expect(insertSql.contains('@p10'), isTrue); // user_agent parameter
    });

    test('all 14 event categories are accepted', () async {
      for (var category = 1; category <= 14; category++) {
        await auditService.recordAuditEvent(
          shopId: 'shop-uuid-456',
          eventCategory: category,
          actionType: 'test_action_$category',
          actorId: 'user-uuid-123',
          targetEntityType: 'test_entity',
          targetEntityId: 'test-id-$category',
        );
      }
      expect(mockPg.executedStatements.length, equals(14));
    });
  });
}
