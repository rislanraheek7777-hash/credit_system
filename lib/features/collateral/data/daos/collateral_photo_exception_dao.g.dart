// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collateral_photo_exception_dao.dart';

// ignore_for_file: type=lint
mixin _$CollateralPhotoExceptionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CreditsTable get credits => attachedDatabase.credits;
  $CollateralItemsTable get collateralItems => attachedDatabase.collateralItems;
  $CollateralPhotoExceptionsTable get collateralPhotoExceptions =>
      attachedDatabase.collateralPhotoExceptions;
  CollateralPhotoExceptionDaoManager get managers =>
      CollateralPhotoExceptionDaoManager(this);
}

class CollateralPhotoExceptionDaoManager {
  final _$CollateralPhotoExceptionDaoMixin _db;
  CollateralPhotoExceptionDaoManager(this._db);
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
  $$CollateralPhotoExceptionsTableTableManager get collateralPhotoExceptions =>
      $$CollateralPhotoExceptionsTableTableManager(
        _db.attachedDatabase,
        _db.collateralPhotoExceptions,
      );
}
