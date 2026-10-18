// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shop_dao.dart';

// ignore_for_file: type=lint
mixin _$ShopDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  ShopDaoManager get managers => ShopDaoManager(this);
}

class ShopDaoManager {
  final _$ShopDaoMixin _db;
  ShopDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
}
