import 'package:drift/drift.dart';

import 'app_users_table.dart';
import 'loans_table.dart';
import 'shops_table.dart';

/// Local SQLite schema for payment receipts (Story 5-1, PRD FR-21).
///
/// Stores immutable payment transaction records scoped to a shop tenant,
/// linked to a disbursed loan agreement. Each row is a receipt snapshot
/// capturing branding and transaction details at the moment of payment
/// confirmation (PRD FR-24).
///
/// Binds: PRD FR-21, FR-22, FR-23, FR-24; AD-1 (tenant isolation);
/// AD-2 (integer minor units).
@DataClassName('PaymentEntry')
@TableIndex(name: 'idx_payments_shop_id', columns: {#shopId})
@TableIndex(name: 'idx_payments_shop_loan', columns: {#shopId, #loanId})
@TableIndex(name: 'idx_payments_receipt_number', columns: {#shopId, #receiptNumber})
class Payments extends Table {
  /// Canonical UUIDv4 primary key.
  TextColumn get id => text()();

  /// Tenant shop association (immutable foreign key boundary).
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.restrict)();

  /// Associated loan agreement (immutable foreign key boundary).
  TextColumn get loanId =>
      text().references(Loans, #id, onDelete: KeyAction.restrict)();

  /// Unique human-readable receipt number (e.g. `RCP-<shop>-<YYYYMMDD>-<short>`).
  TextColumn get receiptNumber => text().withLength(min: 1, max: 100)();

  /// Payment amount in integer minor units (cents), strictly positive.
  IntColumn get amountCents => integer()();

  /// Outstanding balance in minor units before this payment was applied.
  IntColumn get preBalanceCents => integer()();

  /// Outstanding balance in minor units after this payment was applied.
  IntColumn get postBalanceCents => integer()();

  /// Payment type: `partial` or `full_settlement`.
  TextColumn get paymentType => text().withLength(min: 1, max: 30)();

  /// UTC timestamp when the payment was confirmed.
  DateTimeColumn get recordedAt => dateTime()();

  /// User UUID of the staff member who recorded the payment.
  TextColumn get recordedByUserId =>
      text().references(AppUsers, #id, onDelete: KeyAction.restrict)();

  /// Customer borrower identifier (denormalized for receipt snapshot).
  IntColumn get customerId => integer()();

  /// Customer full name at time of payment (masked per RBAC in UI layer).
  TextColumn get customerName => text()();

  /// Customer NIC at time of payment (masked per RBAC in UI layer).
  TextColumn get customerNic => text()();

  /// Shop branding snapshot: shop name.
  TextColumn get shopName => text()();

  /// Shop branding snapshot: business address.
  TextColumn get shopAddress => text().nullable()();

  /// Shop branding snapshot: contact phone.
  TextColumn get shopPhone => text().nullable()();

  /// Shop branding snapshot: tax/registration number.
  TextColumn get shopTaxId => text().nullable()();

  /// Shop branding snapshot: receipt footer notes.
  TextColumn get shopFooterNotes => text().nullable()();

  /// Client-generated UUIDv4 idempotency key to prevent duplicate payments.
  TextColumn get idempotencyKey => text().withLength(min: 1, max: 100)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, receiptNumber},
    {shopId, idempotencyKey},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (amount_cents > 0)',
    "CHECK (payment_type IN ('partial', 'full_settlement'))",
    'CHECK (pre_balance_cents >= 0)',
    'CHECK (post_balance_cents >= 0)',
    'CHECK (post_balance_cents <= pre_balance_cents)',
  ];
}
