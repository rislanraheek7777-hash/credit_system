// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collateral_dao.dart';

// ignore_for_file: type=lint
mixin _$CollateralDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CreditsTable get credits => attachedDatabase.credits;
  $CollateralItemsTable get collateralItems => attachedDatabase.collateralItems;
  $CreditAdministrativeClosuresTable get creditAdministrativeClosures =>
      attachedDatabase.creditAdministrativeClosures;
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
  $$CreditsTableTableManager get credits =>
      $$CreditsTableTableManager(_db.attachedDatabase, _db.credits);
  $$CollateralItemsTableTableManager get collateralItems =>
      $$CollateralItemsTableTableManager(
        _db.attachedDatabase,
        _db.collateralItems,
      );
  $$CreditAdministrativeClosuresTableTableManager
  get creditAdministrativeClosures =>
      $$CreditAdministrativeClosuresTableTableManager(
        _db.attachedDatabase,
        _db.creditAdministrativeClosures,
      );
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
