import 'dart:typed_data';

import '../../../../core/data/local/app_database.dart';
import '../../../auth/domain/models/app_user.dart';
import '../../../../core/permissions/app_permission.dart';
import '../../../collateral/domain/models/collateral_item.dart';
import '../models/customer.dart';
import '../models/credit.dart';
import '../models/credit_term.dart';

/// Abstract service for generating credit agreement documents (Story 4.4).
///
/// Responsibilities:
/// - Draft document generation at PendingDisbursement state with watermark/disclosure.
/// - Official ticket generation at Disbursed state.
/// - PII masking via Story 7.2 masking helpers for NIC/phone across all channels.
/// - Audit event recording for document generation (category 2 / action types
///   `generate_credit_draft` / `generate_credit_official_ticket`).
///
/// Invariants:
/// - Drafts are generated for credits in `pending_disbursement` workflow status.
/// - Official tickets are generated ONLY for credits in `disbursed` workflow status
///   after cash handover has been confirmed. No ticket is created for cancelled or
///   undisbursed credits.
/// - The document snapshot ID is persisted on the credit row exactly once;
///   regeneration must not overwrite an existing snapshot identifier.
/// - The identifier is a reference, not a content archive. This scaffold does
///   not persist the branding/customer/credit/collateral values used to render a
///   document, so it does not by itself make a previously issued document
///   reproducible. Full immutable content storage remains pending decision
///   D4.4-03.
/// - PII masking is consistent across on-screen preview, PDF export, and printed
///   documents (reusing Story 7.2 helpers; no new masking logic).
/// - Every generation request is authorized against the actor's effective
///   permissions and tenant. The caller cannot supply a permission flag.
///
/// Scope note: this is the existing Story 4.4 service contract. The full
/// proposed `credit_documents` / `credit_document_events` append-only architecture
/// is not implemented here and remains unapproved.
abstract class DocumentGenerationService {
  /// Generates a draft document PDF for a credit in `pending_disbursement` state.
  ///
  /// The draft includes the exact Story 4.4 watermark, preliminary due-date
  /// disclosure, and an explicit statement that cash has not been disbursed.
  ///
  /// [customer] supplies the identity values to print. Only a masked NIC and
  /// phone are printed unless the actor holds
  /// [AppPermission.viewSensitiveCustomerData]; the residential address and
  /// customer photo are never printed. The caller-supplied [showRawPII] flag is
  /// never trusted — it is intersected with the actor's actual permissions.
  ///
  /// [shopTimeZone] resolves printed calendar dates (origination and
  /// preliminary due date) in the shop's operational zone. Formatting the UTC
  /// date of a local-midnight instant would print the previous day.
  ///
  /// [actor] must be active, belong to the credit's shop, and hold
  /// [AppPermission.createCredits] (PRD FR-20). Authorization is evaluated from
  /// the actor's effective permissions; no caller-supplied flag is trusted.
  ///
  /// Returns the PDF bytes for on-screen preview or export.
  ///
  /// Throws [PermissionDeniedException] when the actor is unauthorized.
  /// Throws [CreditDisbursementStateException] when the credit is not in
  /// `pending_disbursement` workflow status.
  Future<Uint8List> generateDraftPdf({
    required Credit credit,
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
  });

  /// Generates an official credit ticket PDF for a credit in `disbursed` state.
  ///
  /// The official ticket is generated only after a confirmed cash handover and
  /// renders the confirmed due date supplied by the disbursement operation.
  /// [documentSnapshotId] identifies the snapshot reference persisted on the
  /// credit. The identifier alone does not make the rendered content immutable;
  /// callers must not treat it as a content archive.
  ///
  /// [shopTimeZone] resolves the printed origination date, confirmed due date,
  /// voucher-number date segment, and any custom agreed-term date. The
  /// confirmed cash-handover timestamp remains an actual UTC instant.
  ///
  /// Only a masked NIC and phone are printed unless the actor holds
  /// [AppPermission.viewSensitiveCustomerData]; the residential address and
  /// customer photo are never printed. The caller-supplied [showRawPII] flag is
  /// never trusted — it is intersected with the actor's actual permissions.
  ///
  /// Returns the PDF bytes for on-screen preview or export.
  ///
  /// Throws [PermissionDeniedException] when the actor is unauthorized.
  /// Throws [CreditDisbursementStateException] when the credit is not in `disbursed`
  /// workflow status or has no confirmed disbursement timestamp.
  Future<Uint8List> generateVoucherPdf({
    required Credit credit,
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
  });

  /// Persists the document-snapshot identifier on a disbursed credit.
  ///
  /// The update is tenant-scoped, targeted by credit primary key, and changes only
  /// `document_snapshot_id`. It is idempotent for the same identifier and
  /// refuses to overwrite a different identifier, so a generated document cannot
  /// be silently re-pointed at new content.
  ///
  /// This method stores only the identifier. It does not persist the rendered
  /// document content, so later edits to live customer, shop, credit, or
  /// collateral rows may still change a re-render while D4.4-03 is pending.
  ///
  /// Throws [CreditDisbursementStateException] when the credit is not disbursed.
  /// Throws [StateError] when the credit row is missing or already holds a
  /// different snapshot identifier.
  Future<void> persistDocumentSnapshot({
    required AppDatabase db,
    required Credit credit,
    required String documentSnapshotId,
  });

  /// Records a document-generation audit event in the local sync queue.
  ///
  /// - [actionType] is the FR-31 action type (for example `generate_credit_draft`
  ///   or `generate_credit_official_ticket`).
  /// - The event category is always 2 (credit agreement origination and
  ///   cancellation) per the authoritative FR-31 ordinal catalogue.
  /// - The queued payload contains no raw NIC, address, phone, or document body;
  ///   customer correlation uses a masked value plus a SHA-256 digest.
  /// - The local row is a synchronization queue entry, not an authoritative
  ///   audit record. The authoritative record is the server `audit_events` row.
  ///
  /// Throws [ArgumentError] when required identifiers are blank or the credit does
  /// not belong to [shopId].
  Future<void> recordDocumentAuditEvent({
    required AppDatabase db,
    required String shopId,
    required String actorId,
    required String actionType,
    required String customerId,
    required String creditId,
    required bool isDraft,
  });
}

