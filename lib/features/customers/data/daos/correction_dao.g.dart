// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'correction_dao.dart';

// ignore_for_file: type=lint
mixin _$CorrectionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $LoansTable get loans => attachedDatabase.loans;
  $PaymentsTable get payments => attachedDatabase.payments;
  $LoanCorrectionsTable get loanCorrections => attachedDatabase.loanCorrections;
  $LoanLedgerEntriesTable get loanLedgerEntries =>
      attachedDatabase.loanLedgerEntries;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  CorrectionDaoManager get managers => CorrectionDaoManager(this);
}

class CorrectionDaoManager {
  final _$CorrectionDaoMixin _db;
  CorrectionDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$AppUsersTableTableManager get appUsers =>
      $$AppUsersTableTableManager(_db.attachedDatabase, _db.appUsers);
  $$LoansTableTableManager get loans =>
      $$LoansTableTableManager(_db.attachedDatabase, _db.loans);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db.attachedDatabase, _db.payments);
  $$LoanCorrectionsTableTableManager get loanCorrections =>
      $$LoanCorrectionsTableTableManager(
        _db.attachedDatabase,
        _db.loanCorrections,
      );
  $$LoanLedgerEntriesTableTableManager get loanLedgerEntries =>
      $$LoanLedgerEntriesTableTableManager(
        _db.attachedDatabase,
        _db.loanLedgerEntries,
      );
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
