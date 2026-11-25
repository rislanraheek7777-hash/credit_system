import 'package:flutter/material.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

/// The per-credit "Settle" action.
///
/// Any active authenticated actor posts an adjustment (partial forgiveness or
/// increase) from the customer profile's credit cards; it takes effect in the
/// ledger immediately on submit, with no owner approval step. The action
/// itself records nothing — it hands control to [onRequestAdjustment], which
/// the profile owns, opens the adjustment screen, and reloads the credit list
/// when the adjustment returns so the new balance shows immediately.
///
/// Visibility mirrors the 2026-11-18 every-card pattern: offered to any
/// active actor, regardless of the credit's eligibility — eligibility
/// (disbursed workflow, `active`/`overdue` status, positive balance, no
/// pending correction) is checked by the adjustment screen only.
///
/// While a genuine payment correction is pending on this credit, the action
/// renders disabled with a lock subtitle — no adjustment and no payment can
/// start until that correction is resolved by the Shop Owner.
class CreditAdjustmentAction extends StatelessWidget {
  const CreditAdjustmentAction({
    super.key,
    required this.credit,
    required this.currentUser,
    required this.onRequestAdjustment,
  });

  /// The agreement this action targets.
  final Credit credit;

  /// The authenticated actor.
  final AppUser currentUser;

  /// Invoked when the actor taps Settle.
  final VoidCallback onRequestAdjustment;

  /// The key of the request-adjustment action offered for [creditId].
  static Key buttonKey(String creditId) =>
      Key('request_adjustment_button_$creditId');

  /// The key of the lock notice rendered while a payment correction is pending
  /// on [creditId].
  static Key lockNoticeKey(String creditId) =>
      Key('request_adjustment_lock_$creditId');

  /// Whether the adjustment action may be offered to [actor].
  ///
  /// Any active authenticated actor may post an immediate adjustment — no
  /// `requestCorrections` permission or owner role is required. Deactivated
  /// accounts are never offered the action. The credit eligibility check is
  /// intentionally omitted (2026-11-18 visibility pattern); eligibility is
  /// checked by the adjustment screen only.
  static bool isAvailableFor(AppUser actor) {
    return actor.isActive;
  }

  @override
  Widget build(BuildContext context) {
    if (!CreditAdjustmentAction.isAvailableFor(currentUser)) {
      return const SizedBox.shrink();
    }

    final locked = credit.correctionPending;

    // The action owns its own vertical inset, so a card that does not offer
    // the action gains no dead spacing and both surfaces render it the same.
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: CreditAdjustmentAction.buttonKey(credit.id),
            onPressed: locked ? null : onRequestAdjustment,
            icon: Icon(locked ? Icons.lock_outline : Icons.receipt),
            label: const Text('Settle'),
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                key: CreditAdjustmentAction.lockNoticeKey(credit.id),
                'Locked: a payment correction is pending Shop Owner review.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
