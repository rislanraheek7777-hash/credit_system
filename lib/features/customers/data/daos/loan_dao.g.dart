// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'loan_dao.dart';

// ignore_for_file: type=lint
mixin _$LoanDaoMixin on DatabaseAccessor<AppDatabase> {
  $ShopsTable get shops => attachedDatabase.shops;
  $CustomersTable get customers => attachedDatabase.customers;
  $LoansTable get loans => attachedDatabase.loans;
  LoanDaoManager get managers => LoanDaoManager(this);
}

class LoanDaoManager {
  final _$LoanDaoMixin _db;
  LoanDaoManager(this._db);
  $$ShopsTableTableManager get shops =>
      $$ShopsTableTableManager(_db.attachedDatabase, _db.shops);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$LoansTableTableManager get loans =>
      $$LoansTableTableManager(_db.attachedDatabase, _db.loans);
}
