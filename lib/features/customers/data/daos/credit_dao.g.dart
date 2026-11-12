// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_dao.dart';

// ignore_for_file: type=lint
mixin _$CreditDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CreditsTable get credits => attachedDatabase.credits;
  CreditDaoManager get managers => CreditDaoManager(this);
}

class CreditDaoManager {
  final _$CreditDaoMixin _db;
  CreditDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$AppUsersTableTableManager get appUsers =>
      $$AppUsersTableTableManager(_db.attachedDatabase, _db.appUsers);
  $$CreditsTableTableManager get credits =>
      $$CreditsTableTableManager(_db.attachedDatabase, _db.credits);
}
