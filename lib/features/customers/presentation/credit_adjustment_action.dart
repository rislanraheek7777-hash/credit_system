import 'package:flutter/material.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';

/// The per-credit "Settle" action (Story 5.6).
///
/// Staff propose an adjustment (partial forgiveness or increase) from the
/// customer profile's credit cards; the Shop Owner approves or rejects it in
/// the correction review queue. The action itself records nothing — it hands
/// control to [onRequestAdjustment], which the profile owns, opens the
/// adjustment proposal screen, and reloads the credit list when the proposal
/// returns so the lock state shows immediately.
///
/// Visibility mirrors the 2026-11-18 every-card pattern: offered to any
/// active actor holding `requestCorrections`, regardless of the credit's
/// eligibility — eligibility (disbursed workflow, `active`/`overdue` status,
/// positive balance, no pending correction) is enforced by the proposal
/// screen and the DAO behind it.
///
/// While a correction/adjustment proposal is pending on this credit, the
/// action renders disabled with a lock subtitle — no second proposal, and no
/// payment, can start until the Shop Owner decides it.
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

  /// Invoked when the staff member taps Settle.
  final VoidCallback onRequestAdjustment;

  /// The key of the request-adjustment action offered for [creditId].
  static Key buttonKey(String creditId) =>
      Key('request_adjustment_button_$creditId');

  /// The key of the lock notice rendered while a proposal is pending on
  /// [creditId].
  static Key lockNoticeKey(String creditId) =>
      Key('request_adjustment_lock_$creditId');

  /// Whether the request-adjustment action may be offered to [actor].
  ///
  /// The permission is evaluated through [AppUser.hasPermission], so a
  /// deactivated account — including a deactivated shop owner — is never
  /// offered the action. The credit eligibility check is intentionally
  /// omitted (2026-11-18 visibility pattern); eligibility is enforced by the
  /// proposal screen and the DAO.
  static bool isAvailableFor(AppUser actor) {
    return actor.hasPermission(AppPermission.requestCorrections);
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
            icon: Icon(locked ? Icons.lock_outline : Icons.volunteer_activism_outlined),
            label: const Text('Settle'),
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                key: CreditAdjustmentAction.lockNoticeKey(credit.id),
                'Locked: an adjustment or correction is pending Shop Owner review.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
