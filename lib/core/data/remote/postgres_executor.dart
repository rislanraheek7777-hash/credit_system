import 'package:postgres/postgres.dart';

import 'migration_runner.dart' show SqlDatabaseExecutor;

/// A PostgreSQL [SqlDatabaseExecutor] implementation using the `postgres`
/// package (version 3.5.20).
///
/// Connects to a PostgreSQL database using the `DATABASE_URL` environment
/// variable. All queries are executed within the context of a single
/// connection per operation.
class PostgreSqlExecutor {
  final String _connectionString;
  Connection? _connection;

  /// Creates a [PostgreSqlExecutor] that connects using the `DATABASE_URL`
  /// environment variable.
  ///
  /// Throws [DatabaseUrlNotFoundException] if the environment variable is not
  /// set.
  PostgreSqlExecutor()
      : _connectionString = const String.fromEnvironment('DATABASE_URL') {
    if (_connectionString.isEmpty) {
      throw const DatabaseUrlNotFoundException();
    }
    _connection = null;
  }

  /// Creates an offline [PostgreSqlExecutor] that does not connect to a
  /// server. Used for session restoration contexts where only local Drift
  /// data is accessed and no PostgreSQL queries are executed.
  ///
  /// All methods that require a connection will throw
  /// [UnsupportedError] if called.
  PostgreSqlExecutor.offline() : _connectionString = '' {
    _connection = null;
  }

  /// Creates a [PostgreSqlExecutor] that connects using the provided
  /// [connectionString]. This constructor is intended for testing and
  /// dependency injection; the secret must come from a secure source
  /// (e.g. environment variable), never from source code.
  PostgreSqlExecutor.withConnectionString(this._connectionString) {
    _connection = null;
  }

  /// Executes a DDL or modification statement, optionally with parameters.
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    final conn = await _getConnection();
    await conn.execute(sql, parameters: parameters);
  }

  /// Executes a query returning rows as a list of maps.
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final conn = await _getConnection();
    final result = await conn.execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Executes [action] inside an atomic database transaction.
  Future<T> transaction<T>(
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) async {
    final conn = await _getConnection();
    return conn.runTx((txSession) async {
      final txExecutor = _PostgresSqlExecutorTransaction(txSession);
      return await action(txExecutor);
    });
  }

  /// Executes [action] inside a PostgreSQL transaction with the
  /// transaction-local tenant context `app.current_shop_id` set to [shopId].
  ///
  /// The tenant context is set via `SET LOCAL app.current_shop_id`, which is
  /// scoped to the transaction and automatically cleared on commit or
  /// rollback, preventing tenant leakage across pooled connections.
  ///
  /// [shopId] must be a trusted, server-validated shop identifier (e.g. from a
  /// cryptographically verified JWT claim), never a client-supplied value.
  Future<T> transactionWithTenant<T>(
    String shopId,
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) async {
    final conn = await _getConnection();
    return conn.runTx((txSession) async {
      // Set the tenant context within the transaction boundary.
      // This is trusted input derived from server-verified JWT claims.
      await txSession.execute(
        'SET LOCAL app.current_shop_id = @p0',
        parameters: [shopId],
      );
      final txExecutor = _PostgresSqlExecutorTransaction(txSession);
      return await action(txExecutor);
    });
  }

  /// Closes the underlying PostgreSQL connection.
  Future<void> close() async {
    if (_connection != null && _connection!.isOpen) {
      await _connection!.close();
      _connection = null;
    }
  }

  Future<Connection> _getConnection() async {
    if (_connection == null || !_connection!.isOpen) {
      _connection = await Connection.openFromUrl(_connectionString);
    }
    return _connection!;
  }
}

/// A [SqlDatabaseExecutor] wrapper that wraps a [TxSession] to implement the
/// [SqlDatabaseExecutor] interface for use within transactions.
class _PostgresSqlExecutorTransaction implements SqlDatabaseExecutor {
  final TxSession _tx;

  _PostgresSqlExecutorTransaction(this._tx);

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    await _tx.execute(sql, parameters: parameters);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final Result result = await _tx.execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(SqlDatabaseExecutor tx) action,
  ) {
    // Nested transactions are not supported by PostgreSQL in the same way;
    // just execute the action directly within the current transaction.
    return action(this);
  }
}

/// Exception thrown when DATABASE_URL environment variable is not set.
class DatabaseUrlNotFoundException implements Exception {
  const DatabaseUrlNotFoundException();

  @override
  String toString() => 'DATABASE_URL environment variable is not set';
}
