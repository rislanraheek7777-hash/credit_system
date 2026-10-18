// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_photo_exception_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomerPhotoExceptionDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CustomerPhotoExceptionsTable get customerPhotoExceptions =>
      attachedDatabase.customerPhotoExceptions;
  CustomerPhotoExceptionDaoManager get managers =>
      CustomerPhotoExceptionDaoManager(this);
}

class CustomerPhotoExceptionDaoManager {
  final _$CustomerPhotoExceptionDaoMixin _db;
  CustomerPhotoExceptionDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$AppUsersTableTableManager get appUsers =>
      $$AppUsersTableTableManager(_db.attachedDatabase, _db.appUsers);
  $$CustomerPhotoExceptionsTableTableManager get customerPhotoExceptions =>
      $$CustomerPhotoExceptionsTableTableManager(
        _db.attachedDatabase,
        _db.customerPhotoExceptions,
      );
}
