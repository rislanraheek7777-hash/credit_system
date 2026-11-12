// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'correction_dao.dart';

// ignore_for_file: type=lint
mixin _$CorrectionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CreditsTable get credits => attachedDatabase.credits;
  $PaymentsTable get payments => attachedDatabase.payments;
  $CreditCorrectionsTable get creditCorrections =>
      attachedDatabase.creditCorrections;
  $CreditLedgerEntriesTable get creditLedgerEntries =>
      attachedDatabase.creditLedgerEntries;
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
  $$CreditsTableTableManager get credits =>
      $$CreditsTableTableManager(_db.attachedDatabase, _db.credits);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db.attachedDatabase, _db.payments);
  $$CreditCorrectionsTableTableManager get creditCorrections =>
      $$CreditCorrectionsTableTableManager(
        _db.attachedDatabase,
        _db.creditCorrections,
      );
  $$CreditLedgerEntriesTableTableManager get creditLedgerEntries =>
      $$CreditLedgerEntriesTableTableManager(
        _db.attachedDatabase,
        _db.creditLedgerEntries,
      );
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
