import 'package:postgres/postgres.dart';

/// The minimal SQL surface needed by the recovery authority.
abstract interface class SqlExecutor {
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]);

  /// Executes a statement and returns the number of affected rows so callers
  /// can fail closed when a state-changing UPDATE/DELETE matches nothing.
  Future<int> execute(String sql, [List<dynamic>? parameters]);
}

/// A database whose writes can be scoped to a tenant, plus a plain transaction
/// for DDL/migration work that must not set tenant context.
abstract interface class RecoveryDatabase implements SqlExecutor {
  /// Runs [action] inside an atomic transaction with no tenant context.
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action);

  /// Runs [action] with `app.current_shop_id` pinned to [shopId] for the
  /// lifetime of the transaction. [shopId] must be derived from a PostgreSQL
  /// record by the authority, never accepted from an HTTP caller.
  Future<T> transactionWithTenant<T>(
    String shopId,
    Future<T> Function(SqlExecutor tx) action,
  );

  Future<void> close();
}

/// Production PostgreSQL implementation using the least-privilege role named
/// by `DATABASE_URL`. Application requests never issue DDL; only the explicit
/// migration CLI does.
class PgRecoveryDatabase implements RecoveryDatabase {
  PgRecoveryDatabase(this._connectionString);

  final String _connectionString;
  Connection? _connection;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final result = await _execute(sql, parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    final result = await _execute(sql, parameters);
    return result.affectedRows;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) async {
    final connection = await _getConnection();
    return connection.runTx((session) async => action(_TransactionExecutor(session)));
  }

  @override
  Future<T> transactionWithTenant<T>(
    String shopId,
    Future<T> Function(SqlExecutor tx) action,
  ) async {
    final connection = await _getConnection();
    return connection.runTx((session) async {
      // PostgreSQL SET/SET LOCAL cannot accept a bound parameter. set_config
      // is the only safe way to pin a tenant with a query parameter.
      await session.execute(
        "SELECT pg_catalog.set_config('app.current_shop_id', @p0, true)",
        parameters: [shopId],
      );
      return action(_TransactionExecutor(session));
    });
  }

  @override
  Future<void> close() async {
    final connection = _connection;
    if (connection != null && connection.isOpen) {
      await connection.close();
    }
    _connection = null;
  }

  Future<Result> _execute(String sql, List<dynamic>? parameters) async {
    final connection = await _getConnection();
    return connection.execute(sql, parameters: parameters);
  }

  Future<Connection> _getConnection() async {
    final connection = _connection;
    if (connection == null || !connection.isOpen) {
      _connection = await Connection.openFromUrl(_connectionString);
    }
    return _connection!;
  }
}

class _TransactionExecutor implements SqlExecutor {
  _TransactionExecutor(this._session);

  final TxSession _session;

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final result = await _session.execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  @override
  Future<int> execute(String sql, [List<dynamic>? parameters]) async {
    final result = await _session.execute(sql, parameters: parameters);
    return result.affectedRows;
  }
}
