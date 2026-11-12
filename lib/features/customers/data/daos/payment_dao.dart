import 'dart:convert';

import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/app_users_table.dart';
import '../../../../core/data/local/tables/credits_table.dart';
import '../../../../core/data/local/tables/payments_table.dart';
import '../../../../core/data/local/tables/shops_table.dart';
import '../../../../core/data/local/tables/sync_queue_table.dart';
import '../../../../core/money/money.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../../core/permissions/authorization_guard.dart';
import '../../../../features/auth/domain/models/app_user.dart';
import '../../../../features/customers/domain/models/credit.dart';
import '../../../../features/customers/domain/models/credit_term.dart';
import '../../../../features/customers/domain/models/receipt.dart';
import '../../../shop/data/daos/shop_dao.dart';
import 'customer_dao.dart';
import 'credit_dao.dart';
import 'package:uuid/uuid.dart';

part 'payment_dao.g.dart';

/// Data Access Officer for payment recording and receipt snapshots (Story 5-1,
/// PRD FR-21, FR-22, FR-23, FR-24).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A payment can only be recorded within its owning shop.
///
/// Writes use `attachedDatabase.transaction()` with `BEGIN IMMEDIATE` semantics
/// (Drift default), so the payment record, balance update, receipt snapshot,
/// and local audit/sync queue entry commit or roll back together — no partial
/// state is ever visible (PRD FR-22).
@DriftAccessor(tables: [Credits, Payments, SyncQueue, Shops, AppUsers])
class PaymentDao extends DatabaseAccessor<AppDatabase> with _$PaymentDaoMixin {
  PaymentDao(super.db);

  /// PRD FR-31 audit event category for `Payment recording` (category 8).
  static const int paymentRecordingAuditCategory = 8;

  /// Audit event name for `Payment recording` (PRD FR-31).
  static const String paymentRecordingAuditEvent = 'record_payment';

  /// `entity_type` used by the local audit/sync queue for payments.
  static const String paymentEntityType = 'payment';

  /// `action_type` used by the local audit/sync queue for recording a payment.
  static const String recordPaymentActionType = 'record_payment';

  /// Converts a Drift [PaymentEntry] row into a domain [Receipt].
  Receipt _toDomain(PaymentEntry entry) {
    return Receipt(
      id: entry.id,
      shopId: entry.shopId,
      creditId: entry.creditId,
      receiptNumber: entry.receiptNumber,
      amountCents: entry.amountCents,
      preBalanceCents: entry.preBalanceCents,
      postBalanceCents: entry.postBalanceCents,
      paymentType: entry.paymentType == 'full_settlement'
          ? PaymentType.fullSettlement
          : PaymentType.partialPayment,
      recordedAt: entry.recordedAt,
      recordedByUserId: entry.recordedByUserId,
      customerId: entry.customerId,
      customerName: entry.customerName,
      customerNic: entry.customerNic,
      shopName: entry.shopName,
      shopAddress: entry.shopAddress,
      shopPhone: entry.shopPhone,
      shopTaxId: entry.shopTaxId,
      shopFooterNotes: entry.shopFooterNotes,
      idempotencyKey: entry.idempotencyKey,
    );
  }

  /// Records a cash payment against a disbursed credit in an atomic transaction.
  ///
  /// Steps:
  /// 1. Authorization: actor must be active and hold `recordPayments`.
  /// 2. Idempotency fast path: repeat submission with same key returns the
  ///    existing receipt without re-posting.
  /// 3. Eligibility: credit must exist in actor's shop, be disbursed, and have
  ///    a positive outstanding balance.
  /// 4. Overpayment block: amount must not exceed the current balance.
  /// 5. Atomic transaction:
  ///    a. Insert idempotency guard row in `sync_queue` (unique constraint
  ///       on `(shop_id, idempotency_key)` prevents duplicates).
  ///    b. Conditionally update the credit balance (only if still positive and
  ///       not already settled by a concurrent writer).
  ///    c. Insert the payment/receipt row with full branding snapshot.
  ///    d. Insert the local audit/sync queue entry.
  ///
  /// Returns the [Receipt] for the recorded payment.
  ///
  /// Throws [PermissionDeniedException] when the actor is deactivated or does
  /// not hold `recordPayments`.
  /// Throws [ArgumentError] when [idempotencyKey] is blank, [amount] is not
  /// positive, or [creditId] is blank.
  /// Throws [StateError] when the credit does not exist in the actor's shop,
  /// when the idempotency key is already in use by another operation, or
  /// when the credit is not eligible for payment.
  /// Throws [CreditOverpaymentException] when the payment exceeds the
  /// outstanding balance.
  Future<Receipt> recordPayment({
    required AppUser actor,
    required String idempotencyKey,
    required String creditId,
    required Money amount,
    required DateTime recordedAt,
  }) async {
    // --- Authorization: require an active user with recordPayments ---
    if (!actor.isActive) {
      throw const PermissionDeniedException(
        'Access denied: User account is deactivated.',
      );
    }
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.recordPayments,
      actionDescription: 'record a credit payment',
    );

    // --- Input validation ---
    final key = idempotencyKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'idempotencyKey cannot be empty',
      );
    }
    if (amount.minorUnits <= 0) {
      throw ArgumentError.value(
        amount.minorUnits,
        'amount',
        'Payment amount must be a positive value in minor units',
      );
    }

    // --- Idempotency fast path ---
    final claimed = await _findIdempotencyClaim(actor.shopId, key);
    if (claimed != null) {
      return _resolveRecordedPayment(
        shopId: actor.shopId,
        creditId: creditId,
        idempotencyKey: key,
        claim: claimed,
      );
    }

    // --- The credit must exist in the actor's own shop ---
    final creditDao = CreditDao(db);
    final credit = await creditDao.getCreditById(actor.shopId, creditId);
    if (credit == null) {
      throw StateError(
        'Cannot record payment: credit ID "$creditId" not found in shop '
        '"${actor.shopId}".',
      );
    }

    // --- The credit must be disbursed and eligible for payment ---
    if (!credit.isDisbursed) {
      throw const CreditOverpaymentException(
        'Payments cannot be recorded on credits that have not been disbursed.',
      );
    }
    if (credit.status == CreditStatus.settled) {
      throw const CreditOverpaymentException(
        'Payments cannot be recorded on a settled credit.',
      );
    }
    if (credit.balanceCents <= 0) {
      throw const CreditOverpaymentException(
        'The credit has no outstanding balance.',
      );
    }

    // --- Overpayment block ---
    if (amount.minorUnits > credit.balanceCents) {
      throw CreditOverpaymentException(
        'Payment of ${amount.format()} exceeds the outstanding balance of '
        '${Money.fromCents(credit.balanceCents).format()}.',
      );
    }

    // --- Shop branding snapshot ---
    final shopDao = ShopDao(db);
    final shop = await shopDao.getShopById(actor.shopId);
    final customerDao = CustomerDao(db);
    final customer =
        await customerDao.getCustomerById(actor.shopId, credit.customerId);

    // Generate a deterministic receipt number.
    final receiptNumber =
        'RCP-${_shortId(actor.shopId, 6)}-${_compactDate(recordedAt)}-${_shortId(const Uuid().v4(), 8)}';

    final now = recordedAt.toUtc();

    var duplicated = false;

    await attachedDatabase.transaction(() async {
      // --- Re-read the credit inside the transaction to get the current
      //     balance. This prevents TOCTOU races where another concurrent
      //     payment changed the balance after our initial read. ---
      final currentCredit = await creditDao.getCreditById(actor.shopId, creditId);
      if (currentCredit == null) {
        throw StateError(
          'Cannot record payment: credit ID "$creditId" not found in shop '
          '"${actor.shopId}".',
        );
      }

      // --- Story 5.5 correction lock: while a correction is pending on this
      //     credit, new payments are blocked until a Shop Owner approves or
      //     rejects the pending correction. Enforced inside the transaction
      //     lock, not merely in the UI. ---
      if (currentCredit.correctionPending) {
        throw CreditCorrectionPendingException(
          'Cannot record payment: credit ID "$creditId" has a pending correction '
          'request. Payments are blocked until a Shop Owner approves or '
          'rejects the correction.',
        );
      }

      // --- Overpayment block: check against the current balance inside
      //     the transaction, after acquiring the write lock. ---
      if (amount.minorUnits > currentCredit.balanceCents) {
        throw CreditOverpaymentException(
          'Payment of ${amount.format()} exceeds the outstanding balance of '
          '${Money.fromCents(currentCredit.balanceCents).format()}.',
        );
      }

      // --- Idempotency guard row (written first so concurrent submissions
      //     with the same key cannot produce a second payment) ---
      final guard = await into(syncQueue).insertReturningOrNull(
        SyncQueueCompanion.insert(
          id: Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: key,
          entityType: paymentEntityType,
          entityId: creditId,
          actionType: recordPaymentActionType,
          payloadJson: jsonEncode({
            'auditCategory': paymentRecordingAuditCategory,
            'auditEvent': paymentRecordingAuditEvent,
            'actorId': actor.id,
            'creditId': creditId,
            'receiptNumber': receiptNumber,
            'amountCents': amount.minorUnits,
            'preBalanceCents': currentCredit.balanceCents,
            'postBalanceCents':
                currentCredit.balanceCents - amount.minorUnits,
            'paymentType':
                amount.minorUnits == currentCredit.balanceCents
                    ? 'full_settlement'
                    : 'partial',
            'recordedAt': now.toIso8601String(),
            'shopTimeZone': ShopTimeZone.defaultTimeZone().identifier,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
        mode: InsertMode.insertOrIgnore,
      );

      if (guard == null) {
        // Another submission with the same idempotency key already claimed it.
        duplicated = true;
        return;
      }

      // --- Conditional balance update: only if the credit is still eligible.
      //     The WHERE clause checks status and workflow status; the balance
      //     check was already performed above inside the transaction lock. ---
      final newBalanceCents = currentCredit.balanceCents - amount.minorUnits;
      final isFullSettlement = newBalanceCents == 0;

      final affected = await (update(credits)
            ..where((l) =>
                l.shopId.equals(actor.shopId) &
                l.id.equals(credit.id) &
                l.workflowStatus.equals(
                    CreditWorkflowStatus.disbursed.value) &
                l.status.isIn([
                  CreditStatus.active.value,
                  CreditStatus.overdue.value,
                ])))
          .write(CreditsCompanion(
        balanceCents: Value(newBalanceCents),
        status: Value(
            isFullSettlement ? CreditStatus.settled.value : CreditStatus.active.value),
        settledAt: Value(isFullSettlement ? now : null),
      ));

      if (affected == 0) {
        // Another writer modified the credit first. Roll back this transaction.
        final refreshed = await creditDao.getCreditById(actor.shopId, credit.id);
        throw CreditOverpaymentException(
          'Unable to record payment: the credit balance or state changed '
          'concurrently (current balance: '
          '${refreshed != null ? Money.fromCents(refreshed.balanceCents).format() : 'unknown'}).',
        );
      }

      // --- Insert the payment/receipt row ---
      await into(payments).insert(
        PaymentsCompanion.insert(
          id: Uuid().v4(),
          shopId: actor.shopId,
          creditId: creditId,
          receiptNumber: receiptNumber,
          amountCents: amount.minorUnits,
          preBalanceCents: currentCredit.balanceCents,
          postBalanceCents: newBalanceCents,
          paymentType:
              isFullSettlement ? 'full_settlement' : 'partial',
          recordedAt: now,
          recordedByUserId: actor.id,
          customerId: credit.customerId,
          customerName: customer?.fullName ?? 'Not recorded',
          customerNic: customer?.nic ?? 'Not recorded',
          shopName: shop?.name ?? 'Not recorded',
          shopAddress: Value(shop?.businessAddress),
          shopPhone: Value(shop?.contactPhone),
          shopTaxId: Value(shop?.registrationNumber),
          shopFooterNotes: Value(shop?.receiptFooterNotes),
          idempotencyKey: key,
        ),
      );

      // --- Local audit/sync queue entry ---
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: Uuid().v4(),
          shopId: actor.shopId,
          idempotencyKey: Uuid().v4(),
          entityType: paymentEntityType,
          entityId: creditId,
          actionType: recordPaymentActionType,
          payloadJson: jsonEncode({
            'auditCategory': paymentRecordingAuditCategory,
            'auditEvent': paymentRecordingAuditEvent,
            'actorId': actor.id,
            'creditId': creditId,
            'receiptNumber': receiptNumber,
            'amountCents': amount.minorUnits,
            'preBalanceCents': currentCredit.balanceCents,
            'postBalanceCents': newBalanceCents,
            'paymentType':
                isFullSettlement ? 'full_settlement' : 'partial',
            'recordedAt': now.toIso8601String(),
            'customerId': customer?.nic ?? 'Not recorded',
            'shopId': actor.shopId,
          }),
          createdAt: now,
          updatedAt: Value(now),
        ),
      );
    });

    if (duplicated) {
      return _resolveRecordedPayment(
        shopId: actor.shopId,
        creditId: creditId,
        idempotencyKey: key,
      );
    }

    // Return the receipt for the recorded payment.
    final entry = await (select(payments)
          ..where((p) =>
              p.shopId.equals(actor.shopId) & p.receiptNumber.equals(receiptNumber)))
        .getSingle();
    return _toDomain(entry);
  }

  /// Retrieves all payments for a credit, ordered by recorded date descending.
  Future<List<Receipt>> getPaymentsByCredit(
    String shopId,
    String creditId, {
    int? limit,
  }) async {
    final query = select(payments)
      ..where((p) => p.shopId.equals(shopId) & p.creditId.equals(creditId))
      ..orderBy([(p) => OrderingTerm.desc(p.recordedAt)]);
    if (limit != null) {
      query.limit(limit);
    }
    final entries = await query.get();
    return entries.map(_toDomain).toList(growable: false);
  }

  /// Retrieves a receipt by its number, strictly scoped to [shopId].
  Future<Receipt?> getReceiptByNumber(
    String shopId,
    String receiptNumber,
  ) async {
    final entry = await (select(payments)
          ..where((p) =>
              p.shopId.equals(shopId) & p.receiptNumber.equals(receiptNumber)))
        .getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }

  /// Returns the local audit/sync record that claims [idempotencyKey] within
  /// [shopId], or `null` when the key has not been used yet.
  Future<SyncQueueRecord?> _findIdempotencyClaim(
    String shopId,
    String idempotencyKey,
  ) async {
    final query = select(syncQueue)
      ..where((s) =>
          s.shopId.equals(shopId) & s.idempotencyKey.equals(idempotencyKey));
    return query.getSingleOrNull();
  }

  /// Resolves the outcome of a payment that was already recorded under
  /// [idempotencyKey].
  Future<Receipt> _resolveRecordedPayment({
    required String shopId,
    required String creditId,
    required String idempotencyKey,
    SyncQueueRecord? claim,
  }) async {
    final claimed =
        claim ?? await _findIdempotencyClaim(shopId, idempotencyKey);

    if (claimed == null ||
        claimed.entityType != paymentEntityType ||
        claimed.actionType != recordPaymentActionType ||
        claimed.entityId != creditId) {
      throw StateError(
        'Idempotency key "$idempotencyKey" is already in use for a different '
        'operation or credit.',
      );
    }

    final payload = jsonDecode(claimed.payloadJson) as Map<dynamic, dynamic>;
    final receiptNumber = payload['receiptNumber'] as String?;

    if (receiptNumber == null) {
      throw StateError(
        'Idempotency key "$idempotencyKey" references a payment without a '
        'receipt number.',
      );
    }

    final entry = await (select(payments)
          ..where((p) =>
              p.shopId.equals(shopId) & p.receiptNumber.equals(receiptNumber)))
        .getSingleOrNull();

    if (entry == null) {
      throw StateError(
        'Idempotency key "$idempotencyKey" references a missing payment.',
      );
    }

    return _toDomain(entry);
  }

  /// Short alphanumeric identifier derived from a value.
  String _shortId(String value, int length) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (cleaned.isEmpty) return 'UNKNOWN';
    return cleaned.length <= length ? cleaned : cleaned.substring(0, length);
  }

  /// Compact calendar date segment `YYYYMMDD` in UTC.
  String _compactDate(DateTime instant) {
    final utc = instant.toUtc();
    return '${utc.year}${_two(utc.month)}${utc.day.toString().padLeft(2, '0')}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

