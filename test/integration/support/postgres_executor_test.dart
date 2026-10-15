import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/data/remote/migration_runner.dart';
import 'postgres_executor.dart';

void main() {
  group('PostgresExecutor parameter map conversion', () {
    test('empty list yields empty map', () {
      final map = PostgresExecutor.toMap([]);
      expect(map, isEmpty);
    });

    test('null yields empty map', () {
      final map = PostgresExecutor.toMap(null);
      expect(map, isEmpty);
    });

    test('positional list converted to named map', () {
      final list = [42, 'hello', true];
      final map = PostgresExecutor.toMap(list);
      expect(map, equals({'p0': 42, 'p1': 'hello', 'p2': true}));
    });
  });

  group('Transaction executor nested behavior', () {
    test('nested transaction returns same executor', () async {
      // Create a dummy executor that throws on any real DB call.
      final dummy = _DummyExecutor();
      // Inside transaction, the executor should be the same instance.
      final result = await dummy.transaction((tx) async {
        expect(tx, same(dummy));
        return 123;
      });
      expect(result, 123);
    });
  });
}

// Minimal dummy implementation of SqlDatabaseExecutor that only supports transaction.
class _DummyExecutor implements SqlDatabaseExecutor {
  @override
  Future<void> execute(String sql, [List<dynamic>? parameters]) async => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> query(String sql, [List<dynamic>? parameters]) async => throw UnimplementedError();

  @override
  Future<T> transaction<T>(Future<T> Function(SqlDatabaseExecutor tx) action) async {
    // Directly invoke the action – mimics the behaviour of _PostgresTxExecutor.
    return await action(this);
  }
}
