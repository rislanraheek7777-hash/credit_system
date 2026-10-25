// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collateral_custody_event_dao.dart';

// ignore_for_file: type=lint
mixin _$CollateralCustodyEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $LoansTable get loans => attachedDatabase.loans;
  $CollateralItemsTable get collateralItems => attachedDatabase.collateralItems;
  $CollateralCustodyEventsTable get collateralCustodyEvents =>
      attachedDatabase.collateralCustodyEvents;
  CollateralCustodyEventDaoManager get managers =>
      CollateralCustodyEventDaoManager(this);
}

class CollateralCustodyEventDaoManager {
  final _$CollateralCustodyEventDaoMixin _db;
  CollateralCustodyEventDaoManager(this._db);
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
  $$CollateralCustodyEventsTableTableManager get collateralCustodyEvents =>
      $$CollateralCustodyEventsTableTableManager(
        _db.attachedDatabase,
        _db.collateralCustodyEvents,
      );
}
