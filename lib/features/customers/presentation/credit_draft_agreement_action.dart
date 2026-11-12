import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/customers/data/daos/customer_dao.dart';
import 'package:credit_system/features/customers/data/services/document_generation_service_impl.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:credit_system/features/shop/data/daos/shop_dao.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';
import 'voucher_pdf_viewer_web.dart' if (dart.library.io) 'voucher_pdf_viewer_mobile.dart';

/// Hands a generated document to the user.
///
/// Returns the path the document was saved to, or `null` when the platform
/// took the document itself (a browser download).
typedef DocumentPresenter = Future<String?> Function(
  Uint8List bytes,
  String fileName,
);

/// The shared "View / Print Draft Agreement" action (Story 4.4).
///
/// The draft slip is offered from every credit list — the customer profile's
/// credit cards and the shop-wide credit list — so the PDF generation, the
/// `generate_credit_draft` audit event and the document hand-off live here
/// once instead of being copied per surface.
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
    this.documentPresenter,
  });

  /// The agreement the draft slip is generated for.
  final Credit credit;

  /// The authenticated actor requesting the draft slip.
  final AppUser currentUser;

  /// Optional injected [AppDatabase] for testing.
  final AppDatabase? database;

  /// The shop's operational time zone.
  ///
  /// When omitted, the zone configured on the shop profile is used, falling
  /// back to the approved default for an unresolvable identifier.
  final ShopTimeZone? shopTimeZone;

  /// Optional injected document presenter for testing.
  ///
  /// Defaults to [viewVoucherPdf], which waits on a platform channel that
  /// never resolves under `flutter test`, so the hand-off is only observable
  /// through an injected presenter.
  final DocumentPresenter? documentPresenter;

  /// The key of the action button offered for [creditId].
  static Key buttonKey(String creditId) =>
      Key('view_draft_agreement_button_$creditId');

  /// The key of the inline failure message shown for [creditId].
  static Key errorKey(String creditId) => Key('draft_error_display_$creditId');

  /// The key of the confirmation shown after a successful generation.
  static Key generatedKey(String creditId) =>
      Key('draft_generated_display_$creditId');

  /// The key of the saved-file path shown for [creditId].
  static Key savedPathKey(String creditId) =>
      Key('draft_saved_path_display_$creditId');

  /// Whether the draft action may be offered for [credit] to [actor].
  ///
  /// A draft slip exists only for an agreement that is still awaiting cash
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
  bool _isGenerating = false;
  bool _generated = false;
  String? _error;
  String? _filePath;

  @override
  void didUpdateWidget(covariant CreditDraftAgreementAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.credit.id == widget.credit.id) return;
    // The credit list reused this element for a different agreement. Clear
    // the previous agreement's outcome so it is never shown against the new
    // one, and so a leftover spinner cannot disable the new button.
    _isGenerating = false;
    _generated = false;
    _error = null;
    _filePath = null;
  }


  /// Generates the watermarked draft slip, records the audit event and hands
  /// the document to the platform viewer.
  ///
  /// A refusal — a missing permission, a cross-tenant credit or an agreement
  /// that is no longer awaiting disbursement — is surfaced as an inline
  /// message; it never crashes the screen and never claims a document was
  /// produced when it was not.
  Future<void> _generateDraft() async {
    if (_isGenerating) return;

    // Snapshot everything the sequence reads from the widget, so a parent
    // rebuild mid-generation cannot make the PDF, the file name and the audit
    // event reference different agreements.
    final credit = widget.credit;
    final actor = widget.currentUser;
    final database = widget.database;
    final providedTimeZone = widget.shopTimeZone;
    final presenter = widget.documentPresenter ?? viewVoucherPdf;

    setState(() {
      _isGenerating = true;
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
      final bytes = await service.generateDraftPdf(
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

      final fileName = 'draft_agreement_${credit.id}.pdf';
      // The platform viewer can stall (the mobile path waits on a platform
      // channel), so the hand-off is bounded: a stall becomes an ordinary
      // inline failure the staff member can retry from.
      final savedPath = await presenter(bytes, fileName).timeout(
        const Duration(seconds: 30),
      );

      if (!mounted) return;
      // The credit list may have reused this element for another agreement
      // while the document was being generated; the outcome belongs to the
      // agreement it was produced for, not to the one now on screen.
      if (widget.credit.id != credit.id) return;

      setState(() {
        _isGenerating = false;
        _generated = true;
        _filePath = savedPath;
      });

      if (savedPath != null) {
        _showDraftSavedDialog(savedPath);
      } else {
        _showDraftDownloadedDialog();
      }
    } catch (e) {
      debugPrint('Draft agreement generation failed: $e');
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generated = false;
        // A failed retry must not leave the previous document's path on
        // screen next to the new failure message.
        _filePath = null;
        // The raw failure may carry SQL or driver detail, so it is logged
        // rather than shown to staff.
        _error =
            'The draft agreement could not be generated. Please try again or '
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

  void _showDraftSavedDialog(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft Agreement Saved'),
        content: Text('Draft agreement PDF saved to:\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showDraftDownloadedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft Agreement Downloaded'),
        content: const Text(
          'The draft agreement PDF has been downloaded to your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credit = widget.credit;
    final available =
        CreditDraftAgreementAction.isAvailableFor(credit, widget.currentUser);

    // A refusal must stay visible even when the action itself is no longer
    // offered — the agreement may have been disbursed, or the account
    // deactivated, while the document was being generated. Hiding the widget
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
              onPressed: _isGenerating ? null : _generateDraft,
              icon: _isGenerating
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.description_outlined),
              label: const Text('View / Print Draft Agreement'),
            ),
            if (_generated && _error == null) ...[
              const SizedBox(height: 4),
              Text(
                'Draft agreement slip generated.',
                key: CreditDraftAgreementAction.generatedKey(credit.id),
                style: const TextStyle(color: Colors.green),
              ),
            ],
            if (_filePath != null) ...[
              const SizedBox(height: 4),
              Text(
                'Saved: $_filePath',
                key: CreditDraftAgreementAction.savedPathKey(credit.id),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
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
