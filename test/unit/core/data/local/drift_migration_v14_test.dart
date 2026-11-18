import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:credit_system/core/data/local/app_database.dart';

/// Regression coverage for the schema version 13 -> 14 rebuild of the `credits`
/// table (Story 4.3, Phase 2 / U-5).
///
/// The rebuild adds the six approved Tier 1 cross-field CHECK constraints that
/// enforce the cancelled/settled state machine at the persistence boundary.
/// SQLite cannot add a CHECK constraint in place, so the table is rebuilt
/// row-by-row.
///
/// These tests exercise the migration the way a *device* runs it:
///
/// - a persistent database file (not an in-memory database),
/// - foreign-key enforcement switched on in the connection setup callback,
///   exactly as `AppDatabaseConnection.openSandboxedConnection` does,
/// - a genuine version 13 schema that carries the real foreign keys and the
///   version 13 CHECK constraints, but **not** the Tier 1 constraints.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('credit_system_v14_migration');
    dbFile = File(p.join(tempDir.path, 'credit_system.sqlite'));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Opens the database exactly the way the running application does: a
  /// persistent file with `PRAGMA foreign_keys = ON` applied by the connection
  /// setup callback, which Drift runs *before* any migration.
  AppDatabase openWithDeviceSemantics(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
    );
    return AppDatabase.forTesting(executor);
  }

  /// Opens the database with Drift's migrations **disabled**, so that opening
  /// it cannot advance the schema version.
  ///
  /// This is what proves that a fixture is genuinely at a given schema
  /// version: the file is read exactly as it is, with nothing rewritten
  /// behind the scenes.
  AppDatabase openWithoutMigrations(File file) {
    final executor = NativeDatabase(
      file,
      setup: (db) => db.execute('PRAGMA foreign_keys = ON;'),
      enableMigrations: false,
    );
    return AppDatabase.forTesting(executor);
  }

  group('schema version 13 -> 14 rebuild of the credits table', () {
    test('a genuine version 13 database stays at version 13 when it is '
        'reopened without an upgrade', () async {
      seedV13Database(dbFile);

      expect(readUserVersion(dbFile), equals(13),
          reason: 'The fixture must start as a genuine version 13 database.');

      // Open the very same file with migrations disabled, so that nothing can
      // advance the schema version behind the scenes.
      final db = openWithoutMigrations(dbFile);
      addTearDown(() async => db.close());

      // The version 13 data is readable as it is.
      final row = await db
          .customSelect(
            'SELECT status, workflow_status, term_preset_days FROM credits WHERE id = ?',
            variables: [Variable<String>('credit-v13-pending')],
          )
          .getSingle();
      expect(row.read<String>('status'), equals('active'));
      expect(row.read<String>('workflow_status'), equals('pending_disbursement'));
      expect(row.readNullable<int>('term_preset_days'), equals(30));

      // The schema version on disk is untouched.
      expect(readUserVersion(dbFile), equals(13),
          reason: 'Without a migration the database must stay at version 13.');

      // And the Tier 1 constraints are genuinely absent from the version 13
      // schema: a row that the version 14 schema rejects is accepted here.
      // Written as raw SQL because this connection never migrates, so the
      // on-disk schema still has TEXT customer ids.
      final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      await db.customStatement('''
        INSERT INTO credits (
          id, shop_id, customer_id, principal_cents, balance_cents, status,
          workflow_status, cancelled_at, cancellation_reason, due_date,
          created_at
        ) VALUES (
          'credit-v13-tier1-violation', 'shop-v13', 'cust-v13', 500000, 500000,
          'cancelled', 'disbursed', $nowEpoch,
          'Customer abandoned the agreement', $nowEpoch, $nowEpoch
        );
      ''');

      expect(readUserVersion(dbFile), equals(13),
          reason: 'Reading the database must not change its schema version.');
    });

    test('a genuine version 13 database upgrades to version 17', () async {
      seedV13Database(dbFile);

      expect(readUserVersion(dbFile), equals(13),
          reason: 'The fixture must start as a genuine version 13 database.');

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      // Drift opens the database lazily, so the migration only runs once the
      // first query is issued.
      await (db.select(db.credits)..where((l) => l.id.equals('credit-v13-pending')))
          .getSingle();

      expect(readUserVersion(dbFile), equals(25),
          reason: 'Opening a version 13 database must migrate it to 20.');
      expect(db.schemaVersion, equals(25));

      // The version 13 agreements survive the rebuild with their values.
      final pending = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v13-pending')))
          .getSingle();
      expect(pending.status, equals('active'));
      expect(pending.workflowStatus, equals('pending_disbursement'));
      expect(pending.termPresetDays, equals(30));
      expect(pending.customDueDate, isNull);
      expect(pending.disbursedAt, isNull);
      expect(pending.disbursedByUserId, isNull);
      expect(pending.principalCents, equals(500000));
      expect(pending.balanceCents, equals(500000));
    });

    test('preserves the disbursement record of a version 13 agreement',
        () async {
      seedV13Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final disbursed = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v13-disbursed')))
          .getSingle();
      expect(disbursed.workflowStatus, equals('disbursed'));
      expect(disbursed.termPresetDays, equals(60));
      expect(disbursed.disbursedAt, isNotNull);
      expect(disbursed.disbursedByUserId, equals('user-v13'));

      // A legacy version 12 backfilled record (disbursed, but with no
      // disbursement record) stays valid and unchanged.
      final legacy = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v13-legacy')))
          .getSingle();
      expect(legacy.workflowStatus, equals('disbursed'));
      expect(legacy.disbursedAt, isNull);
      expect(legacy.disbursedByUserId, isNull);
    });

    test('reopens successfully after the upgrade', () async {
      seedV13Database(dbFile);

      final first = openWithDeviceSemantics(dbFile);
      await (first.select(first.credits)
            ..where((l) => l.id.equals('credit-v13-pending')))
          .getSingle();
      await first.close();

      // The migration must have recorded the new schema version on disk.
      expect(readUserVersion(dbFile), equals(25));

      // Second launch on the same file: the migration must not run again and
      // the database must open cleanly.
      final second = openWithDeviceSemantics(dbFile);
      addTearDown(() async => second.close());

      expect(second.schemaVersion, equals(25));
      final credit = await (second.select(second.credits)
            ..where((l) => l.id.equals('credit-v13-pending')))
          .getSingle();
      expect(credit.balanceCents, equals(500000));
      expect(credit.termPresetDays, equals(30));

      final item = await (second.select(second.collateralItems)
            ..where((c) => c.id.equals('coll-v13-a')))
          .getSingle();
      expect(item.creditId, equals('credit-v13-pending'),
          reason: 'The child reference must survive a full close/reopen cycle.');
    });

    test('a second launch does not re-run the migration', () async {
      seedV13Database(dbFile);

      final first = openWithDeviceSemantics(dbFile);
      // Force the database open so the migration runs.
      expect(await first.select(first.credits).get(), hasLength(3));
      await first.close();

      expect(readUserVersion(dbFile), equals(25),
          reason: 'Drift must record the new schema version after the '
              'migration committed.');

      final second = openWithDeviceSemantics(dbFile);
      addTearDown(() async => second.close());

      expect(await second.select(second.credits).get(), hasLength(3));
      expect(await second.select(second.collateralItems).get(), hasLength(3));
      expect(readUserVersion(dbFile), equals(25));
    });

    test('keeps every collateral item bound to its agreement', () async {
      seedV13Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final items = await db.select(db.collateralItems).get();
      expect(items, hasLength(3));

      final bound = items.where((i) => i.creditId != null).toList();
      expect(bound, hasLength(2),
          reason: 'Both pledged items must still reference their agreement.');
      expect(
        bound.map((i) => i.creditId),
        containsAll(<String>['credit-v13-pending', 'credit-v13-disbursed']),
      );

      final unbound = items.firstWhere((i) => i.creditId == null);
      expect(unbound.id, equals('coll-v13-unbound'));
    });

    test('leaves no dangling foreign-key reference behind', () async {
      seedV13Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final violations = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(violations, isEmpty,
          reason: 'The rebuilt table must not leave dangling references.');
    });

    test('leaves foreign-key enforcement active after the migration',
        () async {
      seedV13Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final enabled = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(enabled.read<bool>('foreign_keys'), isTrue,
          reason: 'The migration must not leave the connection without foreign '
              'key enforcement.');

      // A child row that points at a non-existent agreement must be refused.
      await expectLater(
        db.into(db.collateralItems).insert(CollateralItemsCompanion.insert(
          id: 'coll-dangling',
          shopId: 'shop-v13',
          customerId: 1,
          creditId: const Value('credit-does-not-exist'),
          itemReferenceId: 'COLL-DANGLING',
          category: 'gold',
          description: const Value('Dangling item'),
          conditionGrade: const Value('Good'),
          weightMilligrams: const Value(1000),
          estimatedValueCents: 1000,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        )),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('recreates the credits indexes', () async {
      seedV13Database(dbFile);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      final indexRows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'credits';",
          )
          .get();
      final indexNames = indexRows.map((r) => r.read<String>('name')).toList();
      expect(indexNames, containsAll(<String>[
        'idx_credits_shop_id',
        'idx_credits_shop_customer',
        'idx_credits_shop_status',
        'idx_credits_shop_customer_status',
      ]));
    });

    test('repairs a database left half-migrated by a failed attempt',
        () async {
      seedV13Database(dbFile, withOrphanStagingTable: true);

      final db = openWithDeviceSemantics(dbFile);
      addTearDown(() async => db.close());

      // The orphan staging table from the failed attempt is gone ...
      final staging = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '_credits_v14';",
          )
          .get();
      expect(staging, isEmpty);

      // ... and the authoritative rows were migrated, not lost.
      expect(await db.select(db.credits).get(), hasLength(3));
      expect(await db.select(db.collateralItems).get(), hasLength(3));
      final credit = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-v13-pending')))
          .getSingle();
      expect(credit.balanceCents, equals(500000));
    });

    test('produces the same credits schema as a fresh installation', () async {
      seedV13Database(dbFile);
      final upgraded = openWithDeviceSemantics(dbFile);
      await (upgraded.select(upgraded.credits)).get();
      final upgradedSchema = await _describeTable(upgraded, 'credits');
      final upgradedChecks = await _checkConstraints(upgraded, 'credits');
      await upgraded.close();

      // A brand new database is created straight at schema version 15.
      final freshFile = File(p.join(tempDir.path, 'fresh.sqlite'));
      final fresh = openWithDeviceSemantics(freshFile);
      addTearDown(() async => fresh.close());
      await (fresh.select(fresh.credits)).get();

      expect(
        upgradedSchema,
        equals(await _describeTable(fresh, 'credits')),
        reason: 'An upgraded database must end up with the same columns, '
            'foreign keys and indexes as a freshly installed one.',
      );
      expect(
        upgradedChecks,
        equals(await _checkConstraints(fresh, 'credits')),
        reason: 'The upgraded table must carry exactly the same CHECK '
            'constraints as a freshly installed one.',
      );
    });
  });

  group('Tier 1 CHECK constraints on the credits table', () {
    late AppDatabase db;

    setUp(() async {
      // A fresh database is created straight at schema version 14.
      final file = File(p.join(tempDir.path, 'v14.sqlite'));
      db = openWithDeviceSemantics(file);
      addTearDown(() async => db.close());
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(ShopEntry(
        id: 'shop-v14',
        name: 'V14 Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.appUsers).insert(AppUserEntry(
        id: 'user-v14',
        shopId: 'shop-v14',
        username: 'v14.staff',
        fullName: 'V14 Staff',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.customers).insert(CustomerEntry(
        id: 1,
        shopId: 'shop-v14',
        fullName: 'V14 Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ));
    });

    /// Inserts a credit, returning the error if the database rejected it.
    Future<Object?> insertCredit({
      required String id,
      String status = 'active',
      String workflowStatus = 'pending_disbursement',
      DateTime? disbursedAt,
      String? disbursedByUserId,
      DateTime? cancelledAt,
      String? cancellationReason,
      DateTime? settledAt,
      int termPresetDays = 30,
    }) async {
      final now = DateTime.now().toUtc();
      try {
        await db.into(db.credits).insert(CreditsCompanion.insert(
          id: id,
          shopId: 'shop-v14',
          customerId: 1,
          principalCents: 500000,
          balanceCents: 500000,
          status: Value(status),
          workflowStatus: Value(workflowStatus),
          termPresetDays: Value(termPresetDays),
          disbursedAt: disbursedAt == null ? const Value.absent() : Value(disbursedAt),
          disbursedByUserId: disbursedByUserId == null
              ? const Value.absent()
              : Value(disbursedByUserId),
          cancelledAt:
              cancelledAt == null ? const Value.absent() : Value(cancelledAt),
          cancellationReason: cancellationReason == null
              ? const Value.absent()
              : Value(cancellationReason),
          dueDate: now,
          createdAt: now,
          settledAt: settledAt == null ? const Value.absent() : Value(settledAt),
        ));
        return null;
      } catch (error) {
        return error;
      }
    }

    test('rejects a cancelled status whose workflow status is not cancelled',
        () async {
      final now = DateTime.now().toUtc();

      // Violates only "cancelled status requires workflow_status = 'cancelled'".
      final error = await insertCredit(
        id: 'credit-c1',
        status: 'cancelled',
        workflowStatus: 'disbursed',
        cancelledAt: now,
        cancellationReason: 'Customer abandoned the agreement',
      );
      expect(error, isA<sqlite.SqliteException>());

      // The otherwise identical row is accepted once the workflow status
      // matches, which isolates this constraint.
      expect(
        await insertCredit(
          id: 'credit-c1-ok',
          status: 'cancelled',
          workflowStatus: 'cancelled',
          cancelledAt: now,
          cancellationReason: 'Customer abandoned the agreement',
        ),
        isNull,
      );
    });

    test('rejects a cancelled status that carries a disbursement timestamp',
        () async {
      final now = DateTime.now().toUtc();

      final error = await insertCredit(
        id: 'credit-c2',
        status: 'cancelled',
        workflowStatus: 'cancelled',
        cancelledAt: now,
        cancellationReason: 'Customer abandoned the agreement',
        disbursedAt: now,
        disbursedByUserId: 'user-v14',
      );
      expect(error, isA<sqlite.SqliteException>());

      // Without the disbursement record the same cancelled agreement is
      // accepted.
      expect(
        await insertCredit(
          id: 'credit-c2-ok',
          status: 'cancelled',
          workflowStatus: 'cancelled',
          cancelledAt: now,
          cancellationReason: 'Customer abandoned the agreement',
        ),
        isNull,
      );
    });

    test('rejects a cancelled status that carries a disbursing staff member',
        () async {
      final now = DateTime.now().toUtc();

      final error = await insertCredit(
        id: 'credit-c3',
        status: 'cancelled',
        workflowStatus: 'cancelled',
        cancelledAt: now,
        cancellationReason: 'Customer abandoned the agreement',
        disbursedAt: now,
        disbursedByUserId: 'user-v14',
      );
      expect(error, isA<sqlite.SqliteException>());

      expect(
        await insertCredit(
          id: 'credit-c3-ok',
          status: 'cancelled',
          workflowStatus: 'cancelled',
          cancelledAt: now,
          cancellationReason: 'Customer abandoned the agreement',
        ),
        isNull,
      );
    });

    test('rejects a settled status whose workflow status is not disbursed',
        () async {
      final now = DateTime.now().toUtc();

      final error = await insertCredit(
        id: 'credit-c4',
        status: 'settled',
        workflowStatus: 'pending_disbursement',
        settledAt: now,
      );
      expect(error, isA<sqlite.SqliteException>());

      expect(
        await insertCredit(
          id: 'credit-c4-ok',
          status: 'settled',
          workflowStatus: 'disbursed',
          settledAt: now,
        ),
        isNull,
      );
    });

    test('rejects a non-cancelled status that carries cancellation details',
        () async {
      final now = DateTime.now().toUtc();

      // A cancellation timestamp on a live agreement.
      final withTimestamp = await insertCredit(
        id: 'credit-c5',
        status: 'active',
        cancelledAt: now,
      );
      expect(withTimestamp, isA<sqlite.SqliteException>());

      // A non-empty cancellation reason on a live agreement.
      final withReason = await insertCredit(
        id: 'credit-c5-b',
        status: 'active',
        cancellationReason: 'Customer abandoned the agreement',
      );
      expect(withReason, isA<sqlite.SqliteException>());

      // The same live agreement without cancellation details is accepted.
      expect(await insertCredit(id: 'credit-c5-ok', status: 'active'), isNull);

      // An empty cancellation reason is not a cancellation detail.
      expect(
        await insertCredit(
          id: 'credit-c5-ok-b',
          status: 'active',
          cancellationReason: '',
        ),
        isNull,
      );
    });

    test('rejects a non-settled status that carries a settlement timestamp',
        () async {
      final now = DateTime.now().toUtc();

      final error = await insertCredit(
        id: 'credit-c6',
        status: 'active',
        settledAt: now,
      );
      expect(error, isA<sqlite.SqliteException>());

      expect(
        await insertCredit(
          id: 'credit-c6-ok',
          status: 'settled',
          workflowStatus: 'disbursed',
          settledAt: now,
        ),
        isNull,
      );
    });

    test('accepts a valid cancelled agreement', () async {
      final now = DateTime.now().toUtc();

      expect(
        await insertCredit(
          id: 'credit-cancelled',
          status: 'cancelled',
          workflowStatus: 'cancelled',
          cancelledAt: now,
          cancellationReason: 'Customer abandoned the agreement',
        ),
        isNull,
      );

      final stored = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-cancelled')))
          .getSingle();
      expect(stored.status, equals('cancelled'));
      expect(stored.workflowStatus, equals('cancelled'));
      expect(stored.cancelledAt, isNotNull);
      expect(stored.cancellationReason,
          equals('Customer abandoned the agreement'));
    });

    test('accepts a valid settled agreement', () async {
      final now = DateTime.now().toUtc();

      expect(
        await insertCredit(
          id: 'credit-settled',
          status: 'settled',
          workflowStatus: 'disbursed',
          settledAt: now,
          disbursedAt: now,
          disbursedByUserId: 'user-v14',
        ),
        isNull,
      );

      final stored = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-settled')))
          .getSingle();
      expect(stored.status, equals('settled'));
      expect(stored.workflowStatus, equals('disbursed'));
      expect(stored.settledAt, isNotNull);
    });

    test('accepts a legacy disbursed record without a disbursement timestamp',
        () async {
      // Agreements that predate the disbursement workflow were backfilled to
      // 'disbursed' by the version 12 migration without a disbursement record.
      expect(
        await insertCredit(
          id: 'credit-legacy-disbursed',
          status: 'active',
          workflowStatus: 'disbursed',
          termPresetDays: 60,
        ),
        isNull,
      );

      final stored = await (db.select(db.credits)
            ..where((l) => l.id.equals('credit-legacy-disbursed')))
          .getSingle();
      expect(stored.workflowStatus, equals('disbursed'));
      expect(stored.disbursedAt, isNull);
      expect(stored.disbursedByUserId, isNull);
    });
  });
}

/// Reads `PRAGMA user_version` straight from the database file, which is what
/// the next launch of the application will use to decide whether a migration
/// is required.
int readUserVersion(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    return raw.select('PRAGMA user_version').first.values.first as int;
  } finally {
    raw.close();
  }
}

/// Captures the columns, foreign keys and indexes of [tableName] in a form
/// that can be compared between two databases.
Future<List<String>> _describeTable(AppDatabase db, String tableName) async {
  final columns = await db.customSelect('PRAGMA table_info("$tableName")').get();
  final foreignKeys =
      await db.customSelect('PRAGMA foreign_key_list("$tableName")').get();
  final indexes = await db.customSelect('PRAGMA index_list("$tableName")').get();

  final columnRows = columns
      .map((r) => '${r.read<String>('name')}:${r.read<String>('type')}:'
          'notnull=${r.read<int>('notnull')}:pk=${r.read<int>('pk')}:'
          'default=${r.readNullable<String>('dflt_value')}')
      .toList()
    ..sort();

  final foreignKeyRows = foreignKeys
      .map((r) => '${r.read<String>('from')}->'
          '${r.read<String>('table')}.${r.read<String>('to')}:'
          'on_delete=${r.read<String>('on_delete')}')
      .toList()
    ..sort();

  final indexRows = indexes
      .map((r) => '${r.read<String>('name')}:unique=${r.read<int>('unique')}:'
          'origin=${r.read<String>('origin')}')
      .toList()
    ..sort();

  return [...columnRows, ...foreignKeyRows, ...indexRows];
}

/// Captures the CHECK constraints of [tableName] as a sorted list, so that the
/// constraints of an upgraded table can be compared with those of a freshly
/// installed one.
Future<List<String>> _checkConstraints(AppDatabase db, String tableName) async {
  final rows = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?;",
        variables: [Variable<String>(tableName)],
      )
      .get();
  if (rows.isEmpty) return const [];

  final sql = rows.first.readNullable<String>('sql') ?? '';
  final constraints = RegExp(r'CHECK\s*\((?:[^()]|\([^()]*\))*\)',
          caseSensitive: false)
      .allMatches(sql)
      .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim())
      .toList()
    ..sort();
  return constraints;
}

/// Creates a genuine version 13 database on disk: the real foreign keys, the
/// version 13 credits schema (with the version 13 columns and the version 13
/// CHECK constraints, but **without** the Tier 1 constraints), agreements in
/// the states a version 13 database can hold, collateral bound to them, and
/// local audit/sync records.
void seedV13Database(File file, {bool withOrphanStagingTable = false}) {
  final db = sqlite.sqlite3.open(file.path);
  db.execute('''
    CREATE TABLE "shops" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "name" TEXT NOT NULL,
      "currency_code" TEXT NOT NULL DEFAULT 'LKR',
      "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
      "business_address" TEXT,
      "contact_phone" TEXT,
      "contact_email" TEXT,
      "registration_number" TEXT,
      "logo_uri" TEXT,
      "receipt_header_notes" TEXT,
      "receipt_footer_notes" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "app_users" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "username" TEXT NOT NULL,
      "full_name" TEXT NOT NULL,
      "role" TEXT NOT NULL,
      "is_active" INTEGER NOT NULL DEFAULT 1,
      "session_version" INTEGER NOT NULL DEFAULT 1,
      "permissions" TEXT,
      "password_hash" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "sync_queue" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "idempotency_key" TEXT NOT NULL,
      "entity_type" TEXT NOT NULL,
      "entity_id" TEXT NOT NULL,
      "action_type" TEXT NOT NULL,
      "payload_json" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending_server_ack',
      "retry_count" INTEGER NOT NULL DEFAULT 0,
      "last_error" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER,
      UNIQUE ("shop_id", "idempotency_key")
    );
    CREATE UNIQUE INDEX "idx_sync_queue_idempotency" ON "sync_queue" ("shop_id", "idempotency_key");
    CREATE TABLE "customers" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "full_name" TEXT NOT NULL,
      "nic" TEXT NOT NULL,
      "phone" TEXT NOT NULL,
      "address" TEXT NOT NULL,
      "photo_uri" TEXT,
      "photo_hash" TEXT,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "customer_photo_exceptions" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "target_customer_id" TEXT NOT NULL,
      "customer_nic" TEXT NOT NULL,
      "requested_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "request_reason" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
      "reviewed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "review_notes" TEXT,
      "reviewed_at" INTEGER,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL
    );
    CREATE TABLE "credits" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
      "principal_cents" INTEGER NOT NULL,
      "balance_cents" INTEGER NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'active',
      "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement',
      "term_preset_days" INTEGER,
      "custom_due_date" INTEGER,
      "disbursed_at" INTEGER,
      "disbursed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "cancelled_at" INTEGER,
      "cancellation_reason" TEXT,
      "due_date" INTEGER NOT NULL,
      "created_at" INTEGER NOT NULL,
      "settled_at" INTEGER,
      CHECK (principal_cents >= 0),
      CHECK (balance_cents >= 0),
      CHECK (balance_cents <= principal_cents),
      CHECK (status IN ('active', 'overdue', 'settled', 'cancelled')),
      CHECK (status <> 'settled' OR settled_at IS NOT NULL),
      CHECK (status <> 'cancelled' OR (cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL AND length(trim(cancellation_reason)) > 0)),
      CHECK (workflow_status IN ('pending_disbursement', 'disbursed', 'cancelled')),
      CHECK (term_preset_days IS NULL OR term_preset_days IN (30, 60, 90)),
      CHECK (NOT (term_preset_days IS NOT NULL AND custom_due_date IS NOT NULL)),
      CHECK ((disbursed_at IS NULL) = (disbursed_by_user_id IS NULL))
    );
    CREATE TABLE "collateral_items" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
      "credit_id" TEXT REFERENCES "credits" ("id") ON DELETE RESTRICT,
      "item_reference_id" TEXT NOT NULL,
      "category" TEXT NOT NULL,
      "description" TEXT NOT NULL,
      "condition_grade" TEXT NOT NULL,
      "weight_milligrams" INTEGER NOT NULL,
      "estimated_value_cents" INTEGER NOT NULL,
      "photo_uri" TEXT,
      "photo_hash" TEXT,
      "custody_status" TEXT NOT NULL DEFAULT 'in_custody',
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL,
      UNIQUE ("shop_id", "item_reference_id")
    );
    CREATE TABLE "collateral_photo_exceptions" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "collateral_item_id" TEXT NOT NULL REFERENCES "collateral_items" ("id") ON DELETE RESTRICT,
      "requested_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "request_reason" TEXT NOT NULL,
      "status" TEXT NOT NULL DEFAULT 'pending_owner_approval',
      "reviewed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "review_notes" TEXT,
      "reviewed_at" INTEGER,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL,
      CHECK (status IN ('pending_owner_approval', 'approved', 'rejected', 'consumed'))
    );
    CREATE TABLE "collateral_custody_events" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "collateral_item_id" TEXT NOT NULL REFERENCES "collateral_items" ("id") ON DELETE RESTRICT,
      "reported_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "previous_status" TEXT NOT NULL,
      "new_status" TEXT NOT NULL,
      "reason" TEXT NOT NULL,
      "created_at" INTEGER NOT NULL
    );
    CREATE TABLE "collateral_discrepancies" (
      "id" TEXT NOT NULL PRIMARY KEY,
      "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
      "collateral_item_id" TEXT NOT NULL REFERENCES "collateral_items" ("id") ON DELETE RESTRICT,
      "reported_by_user_id" TEXT NOT NULL REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "discrepancy_reason" TEXT NOT NULL,
      "status" TEXT NOT NULL,
      "resolved_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
      "resolution_notes" TEXT,
      "resolved_at" INTEGER,
      "created_at" INTEGER NOT NULL,
      "updated_at" INTEGER NOT NULL,
      CHECK (status IN ('pending', 'resolved'))
    );
    CREATE INDEX "idx_credits_shop_id" ON "credits" ("shop_id");
    CREATE INDEX "idx_credits_shop_customer" ON "credits" ("shop_id", "customer_id");
    CREATE INDEX "idx_credits_shop_status" ON "credits" ("shop_id", "status");
    CREATE INDEX "idx_credits_shop_customer_status" ON "credits" ("shop_id", "customer_id", "status");
    PRAGMA user_version = 13;
  ''');

  const now = 1793000000;
  db.execute('''
    INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
    VALUES ('shop-v13', 'V13 Shop', 'LKR', 'Asia/Colombo', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
    VALUES ('user-v13', 'shop-v13', 'v13.staff', 'V13 Staff', 'manager', 1, 1, NULL, NULL, $now, $now);
  ''');
  db.execute('''
    INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
    VALUES ('cust-v13', 'shop-v13', 'V13 Customer', '198512345678', '+94 77 123 4567', '45 Park Road', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "customer_photo_exceptions" ("id", "shop_id", "target_customer_id", "customer_nic", "requested_by_user_id", "request_reason", "status", "created_at", "updated_at")
    VALUES ('cpe-cust-v13', 'shop-v13', 'cust-v13', '198512345678', 'user-v13', 'Customer photo missing', 'pending_owner_approval', $now, $now);
  ''');
  // An agreement awaiting disbursement, with an agreed 30-day term.
  db.execute('''
    INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "due_date", "created_at")
    VALUES ('credit-v13-pending', 'shop-v13', 'cust-v13', 500000, 500000, 'active', 'pending_disbursement', 30, $now, $now);
  ''');
  // An agreement whose cash was handed over, with a 60-day term and a
  // disbursement record.
  db.execute('''
    INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "disbursed_at", "disbursed_by_user_id", "due_date", "created_at")
    VALUES ('credit-v13-disbursed', 'shop-v13', 'cust-v13', 750000, 750000, 'active', 'disbursed', 60, $now, 'user-v13', $now, $now);
  ''');
  // A legacy agreement that predates the disbursement workflow: backfilled to
  // 'disbursed' by the version 12 migration and therefore carrying no
  // disbursement record.
  db.execute('''
    INSERT INTO "credits" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
    VALUES ('credit-v13-legacy', 'shop-v13', 'cust-v13', 250000, 250000, 'active', 'disbursed', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v13-a', 'shop-v13', 'cust-v13', 'credit-v13-pending', 'COLL-V13-A', 'gold', '22K gold necklace', 'Good', 5500, 1500000, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v13-b', 'shop-v13', 'cust-v13', 'credit-v13-disbursed', 'COLL-V13-B', 'electronics', 'Laptop', 'Fair', 1200, 400000, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "credit_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
    VALUES ('coll-v13-unbound', 'shop-v13', 'cust-v13', NULL, 'COLL-V13-C', 'valuables', 'Watch', 'Like New', 300, 900000, 'in_custody', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_photo_exceptions" ("id", "shop_id", "collateral_item_id", "requested_by_user_id", "request_reason", "status", "created_at", "updated_at")
    VALUES ('cpe-v13', 'shop-v13', 'coll-v13-a', 'user-v13', 'Camera failure', 'pending_owner_approval', $now, $now);
  ''');
  db.execute('''
    INSERT INTO "collateral_custody_events" ("id", "shop_id", "collateral_item_id", "reported_by_user_id", "previous_status", "new_status", "reason", "created_at")
    VALUES ('cce-v13', 'shop-v13', 'coll-v13-a', 'user-v13', 'in_custody', 'handover_requested', 'Customer requested release', $now);
  ''');
  db.execute('''
    INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
    VALUES ('sync-v13-a', 'shop-v13', '00000000-0000-4000-8000-000000000101', 'credit', 'credit-v13-pending', 'create_credit', '{"auditCategory":2}', 'pending_server_ack', 0, $now);
  ''');
  db.execute('''
    INSERT INTO "sync_queue" ("id", "shop_id", "idempotency_key", "entity_type", "entity_id", "action_type", "payload_json", "status", "retry_count", "created_at")
    VALUES ('sync-v13-b', 'shop-v13', '00000000-0000-4000-8000-000000000102', 'credit', 'credit-v13-disbursed', 'confirm_credit_disbursement', '{"auditCategory":4}', 'pending_server_ack', 0, $now);
  ''');

  if (withOrphanStagingTable) {
    // Exactly the state a device is left in when the rebuild fails: the
    // staging table survives, the authoritative "credits" table is intact.
    db.execute('''
      CREATE TABLE "_credits_v14" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
        "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
        "principal_cents" INTEGER NOT NULL,
        "balance_cents" INTEGER NOT NULL,
        "status" TEXT NOT NULL DEFAULT 'active',
        "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement',
        "term_preset_days" INTEGER,
        "custom_due_date" INTEGER,
        "disbursed_at" INTEGER,
        "disbursed_by_user_id" TEXT REFERENCES "app_users" ("id") ON DELETE RESTRICT,
        "cancelled_at" INTEGER,
        "cancellation_reason" TEXT,
        "due_date" INTEGER NOT NULL,
        "created_at" INTEGER NOT NULL,
        "settled_at" INTEGER
      );
    ''');
    db.execute('''
      INSERT INTO "_credits_v14" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "term_preset_days", "due_date", "created_at")
      VALUES ('credit-v13-pending', 'shop-v13', 'cust-v13', 500000, 500000, 'active', 'pending_disbursement', 30, $now, $now);
    ''');
  }

  db.close();
}



