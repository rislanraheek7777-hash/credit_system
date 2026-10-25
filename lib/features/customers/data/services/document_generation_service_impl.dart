import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';

import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/customer_masking.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/loan_document_content.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';
import 'package:credit_system/features/customers/domain/services/document_generation_service.dart';

/// Local PDF implementation of [DocumentGenerationService] (Story 4.4).
///
/// PDF generation is entirely local. Document bytes are never stored in SQLite;
/// only the snapshot identifier is persisted on the loan row. That identifier is
/// not a content archive: full immutable content persistence remains pending
/// decision D4.4-03.
class DocumentGenerationServiceImpl implements DocumentGenerationService {
  static const int documentAuditCategory = 2;
  static const String draftGeneratedActionType = 'generate_loan_draft';
  static const String voucherGeneratedActionType =
      'generate_loan_official_ticket';

  final Uuid _uuid;

  DocumentGenerationServiceImpl({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  @override
  Future<Uint8List> generateDraftPdf({
    required Loan loan,
    required AppUser actor,
    required ShopTimeZone shopTimeZone,
    required String shopName,
    required String shopAddress,
    required String shopPhone,
    required String shopTaxId,
    required String disbursingStaffId,
    bool showRawPII = false,
    Customer? customer,
    List<CollateralItem> collateralItems = const [],
  }) async {
    // --- Authorization: draft generation requires createLoans (PRD FR-20). ---
    AuthorizationGuard.checkPermission(
      isActive: actor.isActive,
      effectivePermissions: actor.effectivePermissions,
      permission: AppPermission.createLoans,
      actionDescription: 'generate a draft loan agreement',
    );
    // Tenant boundary: the actor must belong to the loan's shop.
    if (actor.shopId != loan.shopId) {
      throw PermissionDeniedException(
        'Access denied: Actor belongs to shop "${actor.shopId}" but the loan '
        'is in shop "${loan.shopId}". Cross-tenant draft generation is refused.',
        requiredPermission: AppPermission.createLoans.key,
      );
    }

    if (!loan.isPendingDisbursement) {
      throw LoanDisbursementStateException(
        'Loan ${loan.id} is not awaiting disbursement (workflow status: '
        '${loan.workflowStatus.value}). Draft generation is refused.',
      );
    }
    _assertCustomerBelongsToLoan(customer, loan);

    // The caller-supplied showRawPII flag is never trusted: raw PII is only
    // permitted when the actor actually holds viewSensitiveCustomerData.
    final effectiveShowRawPII =
        showRawPII && actor.hasPermission(AppPermission.viewSensitiveCustomerData);

    final content = buildDraftDocumentContent(
      loan: loan,
      shopTimeZone: shopTimeZone,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      shopTaxId: shopTaxId,
      disbursingStaffId: disbursingStaffId,
      showRawPII: effectiveShowRawPII,
      customer: customer,
      collateralItems: collateralItems,
    );
    return _renderPdf(content);
  }

  @override
  Future<Uint8List> generateVoucherPdf({
    required Loan loan,
    required AppUser actor,
    required ShopTimeZone shopTimeZone,
    required String shopName,
    required String shopAddress,
    required String shopPhone,
    required String shopTaxId,
    required String disbursingStaffId,
    required DateTime confirmedDueDate,
    required String documentSnapshotId,
    bool showRawPII = false,
    Customer? customer,
    List<CollateralItem> collateralItems = const [],
    String? shopFooterNotes,
  }) async {
    // --- Authorization: executed vouchers require createLoans OR
    //     viewAndReprintReceipts (PRD FR-20). ---
    final hasVoucherPermission = actor.hasPermission(AppPermission.createLoans) ||
        actor.hasPermission(AppPermission.viewAndReprintReceipts);
    if (!actor.isActive || !hasVoucherPermission) {
      throw PermissionDeniedException(
        'Access denied: Lacking required permission to generate an official '
        'loan voucher. Requires "${AppPermission.createLoans.key}" or '
        '"${AppPermission.viewAndReprintReceipts.key}".',
        requiredPermission: AppPermission.createLoans.key,
      );
    }
    // Tenant boundary: the actor must belong to the loan's shop.
    if (actor.shopId != loan.shopId) {
      throw PermissionDeniedException(
        'Access denied: Actor belongs to shop "${actor.shopId}" but the loan '
        'is in shop "${loan.shopId}". Cross-tenant voucher generation is refused.',
        requiredPermission: AppPermission.createLoans.key,
      );
    }

    if (!loan.isDisbursed) {
      throw LoanDisbursementStateException(
        'Loan ${loan.id} is not disbursed (workflow status: '
        '${loan.workflowStatus.value}). Voucher generation is refused.',
      );
    }
    if (loan.disbursedAt == null) {
      throw LoanDisbursementStateException(
        'Loan ${loan.id} is marked disbursed but has no confirmed cash-handover '
        'timestamp. Official voucher generation is refused.',
      );
    }
    final snapshotId = documentSnapshotId.trim();
    if (snapshotId.isEmpty) {
      throw ArgumentError.value(
        documentSnapshotId,
        'documentSnapshotId',
        'A non-empty snapshot identifier is required for an official voucher.',
      );
    }
    _assertCustomerBelongsToLoan(customer, loan);

    // The caller-supplied showRawPII flag is never trusted: raw PII is only
    // permitted when the actor actually holds viewSensitiveCustomerData.
    final effectiveShowRawPII =
        showRawPII && actor.hasPermission(AppPermission.viewSensitiveCustomerData);

    final content = buildOfficialVoucherContent(
      loan: loan,
      shopTimeZone: shopTimeZone,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      shopTaxId: shopTaxId,
      disbursingStaffId: disbursingStaffId,
      confirmedDueDate: confirmedDueDate,
      documentSnapshotId: snapshotId,
      showRawPII: effectiveShowRawPII,
      customer: customer,
      collateralItems: collateralItems,
      shopFooterNotes: shopFooterNotes,
    );
    return _renderPdf(content);
  }

  @override
  Future<void> persistDocumentSnapshot({
    required AppDatabase db,
    required Loan loan,
    required String documentSnapshotId,
  }) async {
    if (!loan.isDisbursed) {
      throw LoanDisbursementStateException(
        'Loan ${loan.id} is not disbursed (workflow status: '
        '${loan.workflowStatus.value}). A document snapshot may only be '
        'persisted for a confirmed cash disbursement.',
      );
    }
    final snapshotId = documentSnapshotId.trim();
    if (snapshotId.isEmpty) {
      throw ArgumentError.value(
        documentSnapshotId,
        'documentSnapshotId',
        'A non-empty snapshot identifier is required.',
      );
    }

    final existing =
        await (db.select(db.loans)..where(
              (t) => t.id.equals(loan.id) & t.shopId.equals(loan.shopId),
            ))
            .getSingleOrNull();
    if (existing == null) {
      throw StateError(
        'Loan ${loan.id} was not found in shop ${loan.shopId}; the document '
        'snapshot identifier was not persisted.',
      );
    }
    if (existing.documentSnapshotId != null) {
      if (existing.documentSnapshotId == snapshotId) {
        return;
      }
      throw StateError(
        'Loan ${loan.id} already has document snapshot '
        "'${existing.documentSnapshotId}'. Refusing to overwrite it with "
        "'$snapshotId'.",
      );
    }

    final rows =
        await (db.update(db.loans)..where(
              (t) =>
                  t.id.equals(loan.id) &
                  t.shopId.equals(loan.shopId) &
                  t.documentSnapshotId.isNull(),
            ))
            .write(LoansCompanion(documentSnapshotId: Value(snapshotId)));
    if (rows != 1) {
      throw StateError(
        'Failed to persist document snapshot for loan ${loan.id}: expected to '
        'update exactly one row but updated $rows.',
      );
    }
  }

  @override
  Future<void> recordDocumentAuditEvent({
    required AppDatabase db,
    required String shopId,
    required String actorId,
    required String actionType,
    required String customerId,
    required String loanId,
    required bool isDraft,
  }) async {
    final tenantId = shopId.trim();
    final actor = actorId.trim();
    final loan = loanId.trim();
    final customer = customerId.trim();
    final requestedAction = actionType.trim();

    if (tenantId.isEmpty) {
      throw ArgumentError.value(shopId, 'shopId', 'Shop ID is required');
    }
    if (actor.isEmpty) {
      throw ArgumentError.value(actorId, 'actorId', 'Actor ID is required');
    }
    if (loan.isEmpty) {
      throw ArgumentError.value(loanId, 'loanId', 'Loan ID is required');
    }
    if (customer.isEmpty) {
      throw ArgumentError.value(
        customerId,
        'customerId',
        'Customer ID is required',
      );
    }

    final resolvedActionType = requestedAction.isNotEmpty
        ? requestedAction
        : (isDraft ? draftGeneratedActionType : voucherGeneratedActionType);

    // Enforce tenant isolation before queueing the event.
    final loanRow =
        await (db.select(db.loans)
              ..where((t) => t.id.equals(loan) & t.shopId.equals(tenantId)))
            .getSingleOrNull();
    if (loanRow == null) {
      throw ArgumentError.value(
        loanId,
        'loanId',
        'Loan $loan does not exist in shop $tenantId',
      );
    }

    final eventId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'eventCategory': documentAuditCategory,
      'actionType': resolvedActionType,
      'shopId': tenantId,
      'actorId': actor,
      'loanId': loan,
      'customerId': _documentSafeMask(customer),
      'customerIdSha256': sha256.convert(utf8.encode(customer)).toString(),
      'isDraft': isDraft,
      'piiIncluded': false,
      'recordedAt': now.toIso8601String(),
    };

    await db
        .into(db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            id: eventId,
            shopId: tenantId,
            idempotencyKey: eventId,
            entityType: 'loan',
            entityId: loan,
            actionType: resolvedActionType,
            payloadJson: jsonEncode(payload),
            createdAt: now,
          ),
        );
  }

  void _assertCustomerBelongsToLoan(Customer? customer, Loan loan) {
    if (customer == null) return;
    if (customer.id != loan.customerId || customer.shopId != loan.shopId) {
      throw ArgumentError.value(
        customer.id,
        'customer',
        'Customer does not match the loan borrower in shop ${loan.shopId}.',
      );
    }
  }

  /// Fail-closed mask for audit correlation values.
  ///
  /// [maskNic] returns values of eight characters or fewer unchanged; an audit
  /// payload must never contain a raw short identifier.
  String _documentSafeMask(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '****';
    if (trimmed.length <= 8) return '****';
    return maskNic(trimmed);
  }

  Future<Uint8List> _renderPdf(LoanDocumentContent content) async {
    final document = pw.Document(
      // Kept uncompressed so mandatory text remains inspectable in QA.
      compress: false,
      title: content.reference,
      author: 'Credit Management System',
      subject: content.title,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _watermarkHeader(content),
        footer: (context) => _footer(content, context),
        build: (context) => [
          pw.Text(
            content.title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          ...content.headerLines.map(_bodyLine),
          pw.Divider(color: PdfColors.grey),
          ...content.bodyLines.map(_bodyLine),
        ],
      ),
    );

    return await document.save();
  }

  pw.Widget _watermarkHeader(LoanDocumentContent content) {
    final watermark = content.watermark;
    if (watermark == null) {
      return pw.SizedBox();
    }
    return pw.Container(
      alignment: pw.Alignment.center,
      width: double.infinity,
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        watermark,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.red,
        ),
      ),
    );
  }

  pw.Widget _footer(LoanDocumentContent content, pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (content.watermark != null)
          pw.Container(
            alignment: pw.Alignment.center,
            width: double.infinity,
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              content.watermark!,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red,
              ),
            ),
          ),
        ...content.footerLines.map(
          (line) => pw.Text(
            line,
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
        ),
      ],
    );
  }

  pw.Widget _bodyLine(String line) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
    );
  }
}
