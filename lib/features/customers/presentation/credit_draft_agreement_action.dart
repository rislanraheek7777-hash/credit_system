import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/services/document_generation_service_impl.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/customers/presentation/credit_draft_agreement_view_screen.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

/// The shared "View Draft Agreement" action (Story 4.4).
///
/// The draft agreement is offered from every credit list — the customer
/// profile's credit cards and the shop-wide credit list — so the data access,
/// the `generate_credit_draft` audit event and the on-screen document review
/// live here once instead of being copied per surface.
///
/// Tapping the button **shows** the draft agreement on screen: every detail
/// of the credit is rendered from the same resolved content the PDF renderer
/// uses (customer identity with document masking, dates, amounts, agreed
/// term, pledged item receipts, shop branding and the mandatory draft
/// watermark and disclosures). Nothing is persisted: no PDF is produced, no
/// file is written, and no print or download hand-off is performed. The
/// `generate_credit_draft` audit event is still queued so there is a record
/// that the draft was produced for review.
///
/// The action is only offered for an agreement that has **not** been
/// disbursed yet and for an actor that holds `createCredits`: a draft slip
/// must never be produced for an agreement whose cash has already changed
/// hands, and only staff who may create agreements may request one.
///
/// Authorization, the tenant boundary and the `pending_disbursement`
/// precondition are enforced by [DocumentGenerationServiceImpl] itself; this
/// widget only decides whether the action is *offered* and renders the
/// outcome.
class CreditDraftAgreementAction extends StatefulWidget {
  const CreditDraftAgreementAction({
    super.key,
    required this.credit,
    required this.currentUser,
    this.database,
    this.shopTimeZone,
  });

  /// The agreement to show the draft of.
  final Credit credit;

  /// The authenticated actor requesting the draft.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  /// The shop's operational time zone.
  ///
  /// When omitted, the zone configured on the shop profile is used, falling
  /// back to the approved default for an unresolvable identifier.
  final ShopTimeZone? shopTimeZone;

  /// The key of the action button offered for [creditId].
  static Key buttonKey(String creditId) =>
      Key('view_draft_agreement_button_$creditId');

  /// The key of the inline failure message shown for [creditId].
  static Key errorKey(String creditId) => Key('draft_error_display_$creditId');

  /// The key of the on-screen draft agreement view for [creditId].
  static Key viewKey(String creditId) =>
      Key('credit_draft_agreement_view_$creditId');

  /// Whether the draft action may be offered for [credit] to [actor].
  ///
  /// A draft exists only for an agreement that is still awaiting cash
  /// disbursement, and only an actor holding `createCredits` may request one.
  ///
  /// The permission is evaluated through [AppUser.hasPermission], so a
  /// deactivated account — including a deactivated shop owner — is never
  /// offered the action. An active shop owner already holds `createCredits`
  /// through the owner role template.
  static bool isAvailableFor(Credit credit, AppUser actor) {
    if (!credit.isPendingDisbursement) return false;
    return actor.hasPermission(AppPermission.createCredits);
  }

  @override
  State<CreditDraftAgreementAction> createState() =>
      _CreditDraftAgreementActionState();
}

class _CreditDraftAgreementActionState extends State<CreditDraftAgreementAction> {
  bool _isOpening = false;
  String? _error;

  @override
  void didUpdateWidget(covariant CreditDraftAgreementAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.credit.id == widget.credit.id) return;
    // The credit list reused this element for a different agreement. Clear
    // the previous agreement's outcome so it is never shown against the new
    // one, and so a leftover spinner cannot disable the new button.
    _isOpening = false;
    _error = null;
  }

  /// Loads the data behind the draft, records the audit event and opens the
  /// on-screen draft agreement view.
  ///
  /// A refusal — a missing permission, a cross-tenant credit or an agreement
  /// that is no longer awaiting disbursement — is surfaced as an inline
  /// message; it never crashes the screen and never claims the agreement was
  /// shown when it was not. Nothing is saved or transmitted: the only write
  /// is the Category 2 sync-queue audit entry.
  Future<void> _openDraftView() async {
    if (_isOpening) return;

    // Snapshot everything the sequence reads from the widget, so a parent
    // rebuild mid-load cannot make the content, the audit event and the view
    // reference different agreements.
    final credit = widget.credit;
    final actor = widget.currentUser;
    final database = widget.database;
    final providedTimeZone = widget.shopTimeZone;

    setState(() {
      _isOpening = true;
      _error = null;
    });

    try {
      final db = database ?? AppDatabase();
      final shopDao = ShopDao(db);
      final customerDao = CustomerDao(db);
      final collateralDao = CollateralDao(db);

      final shop = await shopDao.getShopById(credit.shopId);
      final customer = await customerDao.getCustomerById(
        credit.shopId,
        credit.customerId,
      );
      // Only the items pledged to *this* agreement belong on its slip.
      final collateral = await collateralDao.getCollateralItemsByCreditId(
        credit.shopId,
        credit.id,
      );

      final service = DocumentGenerationServiceImpl();
      final content = await service.buildDraftContent(
        credit: credit,
        actor: actor,
        shopTimeZone: _resolveShopTimeZone(providedTimeZone, shop),
        shopName: shop?.name ?? 'Not recorded',
        shopAddress: shop?.businessAddress ?? 'Not recorded',
        shopPhone: shop?.contactPhone ?? 'Not recorded',
        shopTaxId: shop?.registrationNumber ?? 'Not recorded',
        disbursingStaffId: actor.id,
        customer: customer,
        collateralItems: collateral,
      );

      await service.recordDocumentAuditEvent(
        db: db,
        shopId: credit.shopId,
        actorId: actor.id,
        actionType: DocumentGenerationServiceImpl.draftGeneratedActionType,
        customerId: credit.customerId.toString(),
        creditId: credit.id,
        isDraft: true,
      );

      if (!mounted) return;
      // The credit list may have reused this element for another agreement
      // while the content was being resolved; the outcome belongs to the
      // agreement it was resolved for, not to the one now on screen.
      if (widget.credit.id != credit.id) return;

      setState(() {
        _isOpening = false;
      });

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CreditDraftAgreementViewScreen(
            key: CreditDraftAgreementAction.viewKey(credit.id),
            content: content,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Draft agreement view failed: $e');
      if (!mounted) return;
      setState(() {
        _isOpening = false;
        // The raw failure may carry SQL or driver detail, so it is logged
        // rather than shown to staff.
        _error =
            'The draft agreement could not be opened. Please try again or '
            'ask the shop owner.';
      });
    }
  }

  /// Resolves the time zone used to render the slip's dates.
  ShopTimeZone _resolveShopTimeZone(
    ShopTimeZone? provided,
    ShopProfile? shop,
  ) {
    if (provided != null) return provided;

    final identifier = shop?.timezone ?? ShopTimeZone.defaultIdentifier;
    try {
      return ShopTimeZone(identifier);
    } on UnsupportedShopTimeZoneException {
      return ShopTimeZone.defaultTimeZone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final credit = widget.credit;
    final available =
        CreditDraftAgreementAction.isAvailableFor(credit, widget.currentUser);

    // A refusal must stay visible even when the action itself is no longer
    // offered — the agreement may have been disbursed, or the account
    // deactivated, while the content was being resolved. Hiding the widget
    // would swallow the failure and leave the staff member with nothing.
    if (!available && _error == null) {
      return const SizedBox.shrink();
    }

    // The action owns its own vertical inset, so a card that does not offer
    // the action gains no dead spacing and both surfaces render it the same.
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (available) ...[
            OutlinedButton.icon(
              key: CreditDraftAgreementAction.buttonKey(credit.id),
              onPressed: _isOpening ? null : _openDraftView,
              icon: _isOpening
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.description_outlined),
              label: const Text('View Draft Agreement'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              key: CreditDraftAgreementAction.errorKey(credit.id),
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}
