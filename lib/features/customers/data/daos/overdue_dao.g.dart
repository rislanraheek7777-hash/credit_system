// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'overdue_dao.dart';

// ignore_for_file: type=lint
mixin _$OverdueDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $CreditsTable get credits => attachedDatabase.credits;
  $DueDateExtensionsTable get dueDateExtensions =>
      attachedDatabase.dueDateExtensions;
  $CustomerFollowUpsTable get customerFollowUps =>
      attachedDatabase.customerFollowUps;
  $CreditResolutionsTable get creditResolutions =>
      attachedDatabase.creditResolutions;
  $SyncQueueTable get syncQueue => attachedDatabase.syncQueue;
  OverdueDaoManager get managers => OverdueDaoManager(this);
}

class OverdueDaoManager {
  final _$OverdueDaoMixin _db;
  OverdueDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$AppUsersTableTableManager get appUsers =>
      $$AppUsersTableTableManager(_db.attachedDatabase, _db.appUsers);
  $$CreditsTableTableManager get credits =>
      $$CreditsTableTableManager(_db.attachedDatabase, _db.credits);
  $$DueDateExtensionsTableTableManager get dueDateExtensions =>
      $$DueDateExtensionsTableTableManager(
        _db.attachedDatabase,
        _db.dueDateExtensions,
      );
  $$CustomerFollowUpsTableTableManager get customerFollowUps =>
      $$CustomerFollowUpsTableTableManager(
        _db.attachedDatabase,
        _db.customerFollowUps,
      );
  $$CreditResolutionsTableTableManager get creditResolutions =>
      $$CreditResolutionsTableTableManager(
        _db.attachedDatabase,
        _db.creditResolutions,
      );
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db.attachedDatabase, _db.syncQueue);
}
