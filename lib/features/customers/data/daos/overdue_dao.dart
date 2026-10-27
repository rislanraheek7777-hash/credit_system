import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/app_users_table.dart';
import '../../../../core/data/local/tables/customer_follow_ups_table.dart';
import '../../../../core/data/local/tables/due_date_extensions_table.dart';
import '../../../../core/data/local/tables/loan_resolutions_table.dart';
import '../../../../core/data/local/tables/loans_table.dart';
import '../../../../core/data/local/tables/shops_table.dart';
import '../../../../core/data/local/tables/sync_queue_table.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../auth/domain/models/app_user.dart';
import '../../domain/models/customer_follow_up.dart';
import '../../domain/models/due_date_extension.dart';
import '../../domain/models/loan.dart';
import '../../domain/models/loan_resolution.dart';
import '../../domain/models/loan_term.dart';

part 'overdue_dao.g.dart';

/// Data Access Object for overdue loan governance: extensions, follow-ups, and owner resolutions
/// (Epic 6: Stories 6.2, 6.3, 6.4; PRD FR-26, FR-27, FR-28).
@DriftAccessor(
  tables: [
    Loans,
    DueDateExtensions,
    CustomerFollowUps,
    LoanResolutions,
    SyncQueue,
    Shops,
    AppUsers,
  ],
)
class OverdueDao extends DatabaseAccessor<AppDatabase> with _$OverdueDaoMixin {
  OverdueDao(super.db);

  static const String loanEntityType = 'loan';
  static const String grantDueDateExtensionActionType = 'grant_due_date_extension';
  static const String recordCustomerFollowUpActionType = 'record_customer_follow_up';
  static const String recordLoanResolutionActionType = 'record_loan_resolution';

  static const int extensionAuditCategory = 8;
  static const int followUpAuditCategory = 9;
  static const int resolutionAuditCategory = 10;

  DueDateExtension _toDomainExtension(DueDateExtensionEntry entry) {
    return DueDateExtension(
      id: entry.id,
      shopId: entry.shopId,
      loanId: entry.loanId,
      previousDueDate: entry.previousDueDate,
      newDueDate: entry.newDueDate,
      reason: entry.reason,
      grantedByUserId: entry.grantedByUserId,
      createdAt: entry.createdAt,
    );
  }

  CustomerFollowUp _toDomainFollowUp(CustomerFollowUpEntry entry) {
    return CustomerFollowUp(
      id: entry.id,
      shopId: entry.shopId,
      loanId: entry.loanId,
      customerId: entry.customerId,
      staffId: entry.staffId,
      channel: FollowUpChannel.fromValue(entry.channel),
      notes: entry.notes,
      promisedPaymentDate: entry.promisedPaymentDate,
      createdAt: entry.createdAt,
    );
  }

  LoanResolution _toDomainResolution(LoanResolutionEntry entry) {
    return LoanResolution(
      id: entry.id,
      shopId: entry.shopId,
      loanId: entry.loanId,
      resolutionType: LoanResolutionType.fromValue(entry.resolutionType),
      reason: entry.reason,
      resolvedByUserId: entry.resolvedByUserId,
      createdAt: entry.createdAt,
    );
  }

  Loan _toDomainLoan(LoanEntry entry) {
    return Loan(
      id: entry.id,
      shopId: entry.shopId,
      customerId: entry.customerId,
      principalCents: entry.principalCents,
      balanceCents: entry.balanceCents,
      status: LoanStatus.fromValue(entry.status),
      workflowStatus: LoanWorkflowStatus.fromValue(entry.workflowStatus),
      dueDate: entry.dueDate,
      createdAt: entry.createdAt,
      settledAt: entry.settledAt,
      termPresetDays: entry.termPresetDays,
      customDueDate: entry.customDueDate,
      disbursedAt: entry.disbursedAt,
      disbursedByUserId: entry.disbursedByUserId,
      cancelledAt: entry.cancelledAt,
      cancellationReason: entry.cancellationReason,
      correctionPending: entry.correctionPending,
    );
  }

  Future<ShopTimeZone> resolveShopTimeZone(String shopId) async {
    final query = select(attachedDatabase.shops)..where((s) => s.id.equals(shopId));
    final shop = await query.getSingleOrNull();
    final identifier = shop?.timezone ?? ShopTimeZone.defaultIdentifier;
    try {
      return ShopTimeZone(identifier);
    } on UnsupportedShopTimeZoneException {
      return ShopTimeZone.defaultTimeZone();
    }
  }

  /// Grants an official due date extension on an active or overdue loan (Story 6.2, FR-26).
  ///
  /// Requires Shop Owner role. Requires non-empty reason and a new due date strictly
  /// greater than the current date in the shop's operational timezone.
  /// Resets overdue status back to Active.
  Future<Loan> grantDueDateExtension({
    required AppUser actor,
    required String idempotencyKey,
    required String loanId,
    required DateTime newDueDate,
    required String reason,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException('Access denied: User account is deactivated.');
    }
    if (actor.role != AppRole.shopOwner) {
      throw const PermissionDeniedException('Access denied: Due date extensions require the Shop Owner role.');
    }

    final trimmedKey = idempotencyKey.trim();
    if (trimmedKey.isEmpty) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey', 'Idempotency key cannot be empty');
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Extension reason cannot be empty');
    }

    final loanEntry = await (select(loans)..where((l) => l.shopId.equals(actor.shopId) & l.id.equals(loanId))).getSingleOrNull();
    if (loanEntry == null) {
      throw StateError('Cannot extend due date: loan ID "$loanId" not found in shop "${actor.shopId}".');
    }

    final loan = _toDomainLoan(loanEntry);
    if (loan.status == LoanStatus.settled || loan.status == LoanStatus.cancelled) {
      throw StateError('Cannot extend due date for a ${loan.status.value} loan.');
    }

    final shopTimeZone = await resolveShopTimeZone(actor.shopId);
    final today = shopTimeZone.localDateOf(DateTime.now().toUtc());
    final newCalDate = shopTimeZone.localDateOf(newDueDate);
    if (!newCalDate.isAfter(today)) {
      throw ArgumentError.value(
        newDueDate,
        'newDueDate',
        'New due date must be strictly after the current date (${today.isoDate}) in shop time zone (${shopTimeZone.identifier}).',
      );
    }

    final normalizedNewDueDateUtc = shopTimeZone.instantAtStartOfDay(newCalDate);
    final previousDueDate = loan.dueDate;
    final extensionId = const Uuid().v4();
    final nowUtc = DateTime.now().toUtc();

    await attachedDatabase.transaction(() async {
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: trimmedKey,
          entityType: loanEntityType,
          entityId: loanId,
          actionType: grantDueDateExtensionActionType,
          payloadJson: jsonEncode({
            'auditCategory': extensionAuditCategory,
            'auditEvent': 'due_date_extension',
            'actorId': actor.id,
            'loanId': loanId,
            'previousDueDate': previousDueDate.toIso8601String(),
            'newDueDate': normalizedNewDueDateUtc.toIso8601String(),
            'newDueDateLocal': newCalDate.isoDate,
            'reason': trimmedReason,
          }),
          createdAt: nowUtc,
          updatedAt: Value(nowUtc),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      await into(dueDateExtensions).insert(
        DueDateExtensionsCompanion.insert(
          id: extensionId,
          shopId: actor.shopId,
          loanId: loanId,
          previousDueDate: previousDueDate,
          newDueDate: normalizedNewDueDateUtc,
          reason: trimmedReason,
          grantedByUserId: actor.id,
          createdAt: nowUtc,
        ),
      );

      await (update(loans)..where((l) => l.shopId.equals(actor.shopId) & l.id.equals(loanId))).write(
        LoansCompanion(
          dueDate: Value(normalizedNewDueDateUtc),
          status: Value(LoanStatus.active.value),
          workflowStatus: Value(LoanWorkflowStatus.disbursed.value),
        ),
      );
    });

    final updated = await (select(loans)..where((l) => l.shopId.equals(actor.shopId) & l.id.equals(loanId))).getSingle();
    return _toDomainLoan(updated);
  }

  /// Retrieves chronological extension history for a loan (Story 6.2).
  Future<List<DueDateExtension>> getExtensionHistory({
    required String shopId,
    required String loanId,
  }) async {
    final query = select(dueDateExtensions)
      ..where((e) => e.shopId.equals(shopId) & e.loanId.equals(loanId))
      ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomainExtension).toList();
  }

  /// Records customer follow-up notes and promise-to-pay commitment (Story 6.3, FR-27).
  Future<CustomerFollowUp> recordFollowUp({
    required AppUser actor,
    required String loanId,
    required int customerId,
    required FollowUpChannel channel,
    required String notes,
    DateTime? promisedPaymentDate,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException('Access denied: User account is deactivated.');
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.recordCustomerNotes,
      actionDescription: 'record customer follow-up notes',
    );

    final trimmedNotes = notes.trim();
    if (trimmedNotes.isEmpty) {
      throw ArgumentError.value(notes, 'notes', 'Follow-up notes cannot be empty');
    }

    final loanEntry = await (select(loans)..where((l) => l.shopId.equals(actor.shopId) & l.id.equals(loanId))).getSingleOrNull();
    if (loanEntry == null) {
      throw StateError('Cannot record follow-up: loan ID "$loanId" not found in shop "${actor.shopId}".');
    }

    final followUpId = const Uuid().v4();
    final nowUtc = DateTime.now().toUtc();
    final promisedUtc = promisedPaymentDate?.toUtc();

    await attachedDatabase.transaction(() async {
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: loanEntityType,
          entityId: loanId,
          actionType: recordCustomerFollowUpActionType,
          payloadJson: jsonEncode({
            'auditCategory': followUpAuditCategory,
            'auditEvent': 'customer_follow_up_note',
            'actorId': actor.id,
            'loanId': loanId,
            'customerId': customerId,
            'channel': channel.value,
            'notes': trimmedNotes,
            'promisedPaymentDate': promisedUtc?.toIso8601String(),
          }),
          createdAt: nowUtc,
          updatedAt: Value(nowUtc),
        ),
      );

      await into(customerFollowUps).insert(
        CustomerFollowUpsCompanion.insert(
          id: followUpId,
          shopId: actor.shopId,
          loanId: loanId,
          customerId: customerId,
          staffId: actor.id,
          channel: channel.value,
          notes: trimmedNotes,
          promisedPaymentDate: Value(promisedUtc),
          createdAt: nowUtc,
        ),
      );
    });

    final created = await (select(customerFollowUps)..where((f) => f.id.equals(followUpId))).getSingle();
    return _toDomainFollowUp(created);
  }

  /// Retrieves follow-up notes in reverse chronological order (Story 6.3).
  Future<List<CustomerFollowUp>> getFollowUps({
    required String shopId,
    required String loanId,
  }) async {
    final query = select(customerFollowUps)
      ..where((f) => f.shopId.equals(shopId) & f.loanId.equals(loanId))
      ..orderBy([(f) => OrderingTerm.desc(f.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomainFollowUp).toList();
  }

  /// Records a structured administrative case resolution by the Shop Owner (Story 6.4, FR-28).
  Future<LoanResolution> recordResolution({
    required AppUser actor,
    required String loanId,
    required LoanResolutionType resolutionType,
    required String reason,
  }) async {
    if (!actor.isActive) {
      throw const PermissionDeniedException('Access denied: User account is deactivated.');
    }
    if (actor.role != AppRole.shopOwner) {
      throw const PermissionDeniedException('Access denied: Case resolution requires the Shop Owner role.');
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Resolution rationale cannot be empty');
    }

    final loanEntry = await (select(loans)..where((l) => l.shopId.equals(actor.shopId) & l.id.equals(loanId))).getSingleOrNull();
    if (loanEntry == null) {
      throw StateError('Cannot record resolution: loan ID "$loanId" not found in shop "${actor.shopId}".');
    }

    final resolutionId = const Uuid().v4();
    final nowUtc = DateTime.now().toUtc();

    await attachedDatabase.transaction(() async {
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: const Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: const Uuid().v4(),
          entityType: loanEntityType,
          entityId: loanId,
          actionType: recordLoanResolutionActionType,
          payloadJson: jsonEncode({
            'auditCategory': resolutionAuditCategory,
            'auditEvent': 'loan_case_resolution',
            'actorId': actor.id,
            'loanId': loanId,
            'resolutionType': resolutionType.value,
            'reason': trimmedReason,
          }),
          createdAt: nowUtc,
          updatedAt: Value(nowUtc),
        ),
      );

      await into(loanResolutions).insert(
        LoanResolutionsCompanion.insert(
          id: resolutionId,
          shopId: actor.shopId,
          loanId: loanId,
          resolutionType: resolutionType.value,
          reason: trimmedReason,
          resolvedByUserId: actor.id,
          createdAt: nowUtc,
        ),
      );
    });

    final created = await (select(loanResolutions)..where((r) => r.id.equals(resolutionId))).getSingle();
    return _toDomainResolution(created);
  }

  /// Retrieves resolutions for a loan, newest first (Story 6.4).
  Future<List<LoanResolution>> getResolutions({
    required String shopId,
    required String loanId,
  }) async {
    final query = select(loanResolutions)
      ..where((r) => r.shopId.equals(shopId) & r.loanId.equals(loanId))
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    final entries = await query.get();
    return entries.map(_toDomainResolution).toList();
  }

  /// Retrieves the latest resolution for a loan, or null if not resolved.
  Future<LoanResolution?> getLatestResolution({
    required String shopId,
    required String loanId,
  }) async {
    final query = select(loanResolutions)
      ..where((r) => r.shopId.equals(shopId) & r.loanId.equals(loanId))
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
      ..limit(1);
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomainResolution(entry) : null;
  }
}
