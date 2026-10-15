import 'package:postgres/postgres.dart';

import 'package:credit_system/core/data/remote/migration_runner.dart';

/// Test‑only implementation of [SqlDatabaseExecutor] that forwards calls to a
/// real PostgreSQL connection from the `postgres` package (version 3.5.20).
///
/// The adapter is deliberately placed under `test/` so it is not shipped with the
/// production app. It provides the exact three methods required by
/// `MigrationRunner` and mirrors transaction semantics using the driver's
/// `runTx` API.
class PostgresExecutor implements SqlDatabaseExecutor {
  final Connection _connection;

  PostgresExecutor(this._connection);

  /// Convenience factory to open a connection using the new `Connection` API.
  static Future<PostgresExecutor> open({
    required String host,
    int port = 5432,
    required String database,
    required String username,
    required String password,
    bool enableSsl = false,
  }) async {
    final conn = await Connection.open(
      Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      settings: ConnectionSettings(
        sslMode: enableSsl ? SslMode.require : SslMode.disable,
      ),
    );
    return PostgresExecutor(conn);
  }

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    // Use Sql.named for legacy @pX placeholders, otherwise positional parameters.
    if (parameters != null && parameters.isNotEmpty && sql.contains('@p')) {
      await _connection.execute(Sql.named(sql), parameters: toMap(parameters));
    } else {
      await _connection.execute(sql, parameters: parameters);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    // Execute the statement (the driver returns a Result containing rows).
    final Result result = await _connection.execute(
      sql,
      parameters: toMap(parameters),
    );
    return result.map<Map<String, dynamic>>((ResultRow row) => row.toColumnMap()).toList();
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlDatabaseExecutor tx) action) async {
    return await _connection.runTx<T>((TxSession tx) async {
      final txExec = _PostgresTxExecutor(tx);
      return await action(txExec);
    });
  }

  /// Closes the underlying connection. Tests should call this in `tearDown`.
  Future<void> close() async => await _connection.close();

  /// Helper to transform a positional parameter list into the map format
  /// that `postgres` expects (`substitutionValues`). The driver expands keys like
  /// `@p0`, `@p1`, … when they appear in the SQL.
  static Map<String, dynamic> toMap(List<dynamic>? parameters) {
    if (parameters == null || parameters.isEmpty) return {};
    final map = <String, dynamic>{};
    for (var i = 0; i < parameters.length; i++) {
      map['p$i'] = parameters[i];
    }
    return map;
  }
}

/// Transaction‑scoped executor that forwards calls to a `TxSession`.
class _PostgresTxExecutor implements SqlDatabaseExecutor {
  final TxSession _tx;

  _PostgresTxExecutor(this._tx);

  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async {
    if (parameters != null && parameters.isNotEmpty && sql.contains('@p')) {
      await _tx.execute(Sql.named(sql), parameters: PostgresExecutor.toMap(parameters));
    } else {
      await _tx.execute(sql, parameters: parameters);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? parameters,
  ]) async {
    final Result result = await _tx.execute(
      sql,
      parameters: PostgresExecutor.toMap(parameters),
    );
    return result.map<Map<String, dynamic>>((ResultRow row) => row.toColumnMap()).toList();
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlDatabaseExecutor tx) action) async {
    // Nested transactions are not supported; just invoke the action directly.
    return await action(this);
  }
}
