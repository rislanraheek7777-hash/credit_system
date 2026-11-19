import 'package:flutter/material.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

/// The per-credit "Settle" action (spec: Credit Settle Button in Customer
/// Profile).
///
/// The action is offered on the customer profile's credit cards to an
/// active actor holding `recordPayments`, regardless of the credit's
/// payment eligibility (visibility rule restored at the human's request on
/// 2026-11-18). Eligibility — disbursed, financially active or overdue,
/// positive balance — is enforced by the settle summary screen and the
/// payment path behind it. It mirrors [CreditDraftAgreementAction]'s
/// per-card presentation so a credit card keeps a single, consistent action
/// pattern.
///
/// The action itself records nothing: it hands control to [onSettle], which the
/// profile owns. The profile opens the dedicated settle summary screen — it
/// shows the borrower, the credit identity, the outstanding balance and the
/// collateral at stake, with the amount pre-filled to the full balance —
/// and reloads the credit list when the settlement returns, so
/// overpayment validation, the concurrency lock, idempotency, receipts and
/// audit behaviour all stay on the existing payment path.
class CreditSettleAction extends StatelessWidget {
  const CreditSettleAction({
    super.key,
    required this.credit,
    required this.currentUser,
    required this.onSettle,
  });

  /// The agreement this action settles.
  final Credit credit;

  /// The authenticated actor.
  final AppUser currentUser;

  /// Invoked when the staff member taps Settle.
  final VoidCallback onSettle;

  /// The key of the settle action offered for [creditId].
  static Key buttonKey(String creditId) => Key('settle_credit_button_$creditId');

  /// Whether the settle action may be offered for [credit] to [actor].
  ///
  /// The permission is evaluated through [AppUser.hasPermission], so a
  /// deactivated account — including a deactivated shop owner — is never
  /// offered the action. The credit eligibility check is intentionally
  /// omitted here so the settle button appears on every credit card in the
  /// customer profile — restored at the human's request on 2026-11-18,
  /// overriding the frozen spec's eligible-only visibility. Eligibility is
  /// still enforced by the settle summary screen when the settlement flow is
  /// initiated, where an ineligible credit shows an explanation and no
  /// settlement form.
  static bool isAvailableFor(Credit credit, AppUser actor) {
    return actor.hasPermission(AppPermission.recordPayments);
  }

  @override
  Widget build(BuildContext context) {
    if (!CreditSettleAction.isAvailableFor(credit, currentUser)) {
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
          OutlinedButton.icon(
            key: CreditSettleAction.buttonKey(credit.id),
            onPressed: onSettle,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Settle'),
          ),
        ],
      ),
    );
  }
}
