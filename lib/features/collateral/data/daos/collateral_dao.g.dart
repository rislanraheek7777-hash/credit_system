// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collateral_dao.dart';

// ignore_for_file: type=lint
mixin _$CollateralDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $LoansTable get loans => attachedDatabase.loans;
  $CollateralItemsTable get collateralItems => attachedDatabase.collateralItems;
  $LoanAdministrativeClosuresTable get loanAdministrativeClosures =>
      attachedDatabase.loanAdministrativeClosures;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  CollateralDaoManager get managers => CollateralDaoManager(this);
}

class CollateralDaoManager {
  final _$CollateralDaoMixin _db;
  CollateralDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$AppUsersTableTableManager get appUsers =>
      $$AppUsersTableTableManager(_db.attachedDatabase, _db.appUsers);
  $$LoansTableTableManager get loans =>
      $$LoansTableTableManager(_db.attachedDatabase, _db.loans);
  $$CollateralItemsTableTableManager get collateralItems =>
      $$CollateralItemsTableTableManager(
        _db.attachedDatabase,
        _db.collateralItems,
      );
  $$LoanAdministrativeClosuresTableTableManager
  get loanAdministrativeClosures =>
      $$LoanAdministrativeClosuresTableTableManager(
        _db.attachedDatabase,
        _db.loanAdministrativeClosures,
      );
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
