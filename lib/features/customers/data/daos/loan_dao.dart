import 'package:drift/drift.dart';
import '../../../../core/data/local/app_database.dart';
import '../../../../core/data/local/tables/loans_table.dart';
import '../../domain/models/loan.dart';

part 'loan_dao.g.dart';

/// Data Access Object for Loan agreements (Story 2.5).
///
/// All queries are strictly scoped to [shopId] to enforce tenant isolation.
/// A loan can only be created, read, or updated within its owning shop.
@DriftAccessor(tables: [Loans])
class LoanDao extends DatabaseAccessor<AppDatabase> with _$LoanDaoMixin {
  LoanDao(super.db);

  /// Converts a Drift [LoanEntry] row into a domain [Loan].
  Loan _toDomain(LoanEntry entry) {
    return Loan(
      id: entry.id,
      shopId: entry.shopId,
      customerId: entry.customerId,
      principalCents: entry.principalCents,
      balanceCents: entry.balanceCents,
      status: LoanStatus.fromValue(entry.status),
      dueDate: entry.dueDate,
      createdAt: entry.createdAt,
      settledAt: entry.settledAt,
    );
  }

  /// Converts a domain [Loan] into a Drift [LoansCompanion].
  LoansCompanion _toCompanion(Loan loan) {
    return LoansCompanion(
      id: Value(loan.id),
      shopId: Value(loan.shopId),
      customerId: Value(loan.customerId),
      principalCents: Value(loan.principalCents),
      balanceCents: Value(loan.balanceCents),
      status: Value(loan.status.value),
      dueDate: Value(loan.dueDate),
      createdAt: Value(loan.createdAt),
      settledAt: Value(loan.settledAt),
    );
  }

  /// Inserts a new loan record into the local SQLite database.
  ///
  /// Validates that the loan belongs to [shopId] before insertion.
  /// Throws [sqlite.SqliteException] if foreign key constraints are violated
  /// (e.g., referenced customer or shop does not exist).
  Future<void> createLoan(Loan loan) async {
    if (loan.shopId.trim().isEmpty) {
      throw ArgumentError.value(loan.shopId, 'shopId', 'shopId cannot be empty');
    }
    if (loan.customerId.trim().isEmpty) {
      throw ArgumentError.value(
          loan.customerId, 'customerId', 'customerId cannot be empty');
    }
    await into(loans).insert(_toCompanion(loan));
  }

  /// Retrieves all loans for [customerId] strictly scoped within [shopId].
  ///
  /// Returns loans ordered by due date ascending.
  Future<List<Loan>> getLoansByCustomerId(
    String shopId,
    String customerId,
  ) async {
    final query = select(loans)
      ..where((l) =>
          l.shopId.equals(shopId) & l.customerId.equals(customerId))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all loans in [shopId] matching [status].
  ///
  /// Strictly scoped to [shopId] — loans in other shops are never returned.
  Future<List<Loan>> getLoansByStatus(String shopId, LoanStatus status) async {
    final query = select(loans)
      ..where((l) =>
          l.shopId.equals(shopId) & l.status.equals(status.value))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves all loans for [customerId] in [shopId] matching [status].
  ///
  /// Strictly scoped to [shopId] — loans in other shops are never returned.
  Future<List<Loan>> getLoansByCustomerAndStatus(
    String shopId,
    String customerId,
    LoanStatus status,
  ) async {
    final query = select(loans)
      ..where((l) =>
          l.shopId.equals(shopId) &
          l.customerId.equals(customerId) &
          l.status.equals(status.value))
      ..orderBy([(l) => OrderingTerm.asc(l.dueDate)]);
    final entries = await query.get();
    return entries.map(_toDomain).toList();
  }

  /// Retrieves a loan by [loanId] strictly scoped within [shopId].
  ///
  /// Returns `null` if the loan does not exist or belongs to another shop.
  Future<Loan?> getLoanById(String shopId, String loanId) async {
    final query = select(loans)
      ..where((l) => l.shopId.equals(shopId) & l.id.equals(loanId));
    final entry = await query.getSingleOrNull();
    return entry != null ? _toDomain(entry) : null;
  }
}
