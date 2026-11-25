import 'package:credential_recovery_backend/src/migration.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  const sql = 'CREATE TABLE public.credential_recovery_challenges (id uuid);';

  test('first apply records schema_migrations', () async {
    final db = FakeRecoveryDatabase();
    final applier = MigrationApplier(db);

    expect(await applier.apply(sql), isTrue);
    expect(db.allSql, contains(sql));
    expect(
      db.allSql.any((statement) => statement.startsWith('INSERT INTO schema_migrations')),
      isTrue,
    );
  });

  test('a second identical apply is a no-op', () async {
    final db = FakeRecoveryDatabase();
    final applier = MigrationApplier(db);

    await applier.apply(sql);
    expect(await applier.apply(sql), isFalse);
    expect(db.allSql.where((statement) => statement == sql), hasLength(1));
    expect(
      db.allSql.where((s) => s.startsWith('INSERT INTO schema_migrations')),
      hasLength(1),
    );
  });

  test('a changed SQL file fails closed instead of re-applying', () async {
    final db = FakeRecoveryDatabase();
    final applier = MigrationApplier(db);
    await applier.apply(sql);

    await expectLater(
      applier.apply('$sql\n-- tampered'),
      throwsA(isA<StateError>()),
    );
  });

  test('an explicitly recorded version is recognised as already applied',
      () async {
    final db = FakeRecoveryDatabase();
    db.setMigrationRecord(3, MigrationApplier.computeChecksum(sql));

    expect(await MigrationApplier(db).apply(sql), isFalse);
    expect(db.allSql, isNot(contains(sql)));
  });
}
