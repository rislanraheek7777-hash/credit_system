// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_dao.dart';

// ignore_for_file: type=lint
mixin _$PaymentDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CreditsTable get credits => attachedDatabase.credits;
  $PaymentsTable get payments => attachedDatabase.payments;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  PaymentDaoManager get managers => PaymentDaoManager(this);
}

class PaymentDaoManager {
  final _$PaymentDaoMixin _db;
  PaymentDaoManager(this._db);
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
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
