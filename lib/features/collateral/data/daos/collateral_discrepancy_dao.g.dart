// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collateral_discrepancy_dao.dart';

// ignore_for_file: type=lint
mixin _$CollateralDiscrepancyDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $AppUsersTable get appUsers => attachedDatabase.appUsers;
  $LoansTable get loans => attachedDatabase.loans;
  $CollateralItemsTable get collateralItems => attachedDatabase.collateralItems;
  $CollateralDiscrepanciesTable get collateralDiscrepancies =>
      attachedDatabase.collateralDiscrepancies;
  CollateralDiscrepancyDaoManager get managers =>
      CollateralDiscrepancyDaoManager(this);
}

class CollateralDiscrepancyDaoManager {
  final _$CollateralDiscrepancyDaoMixin _db;
  CollateralDiscrepancyDaoManager(this._db);
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
  $$CollateralDiscrepanciesTableTableManager get collateralDiscrepancies =>
      $$CollateralDiscrepanciesTableTableManager(
        _db.attachedDatabase,
        _db.collateralDiscrepancies,
      );
}
