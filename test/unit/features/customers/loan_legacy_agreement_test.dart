import 'dart:io';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/loan_dao.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Compatibility coverage for loan agreements created **before** Story 4.3
/// (Story 4.3, finding T6).
///
/// Story 4.3 added the agreed-term columns (`term_preset_days`,
/// `custom_due_date`) and the schema version 13 migration left them empty for
/// every pre-existing agreement. An agreement that was still awaiting
/// disbursement therefore has no recorded term, and the official calendar due
/// date cannot be calculated from it.
///
/// These tests use the real SQLite/Drift persistence path, including a real
/// schema version 12 -> 13 upgrade.
void main() {
  const shopId = 'shop-legacy';
  const customerId = 1;
  const managerId = 'user-legacy';
  const itemId = 'coll-legacy';

  final zone = ShopTimeZone.defaultTimeZone();

  /// The disbursement instant used throughout: 2026-10-15 06:00Z.
  final disbursedAt = DateTime.utc(2026, 10, 15, 6);

  AppUser manager() => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'legacy.manager',
        fullName: 'Legacy Manager',
        role: AppRole.manager,
        isActive: true,
      );

  group('a legacy agreement produced by the schema version 12 -> 13 upgrade',
      () {
    test('cannot be disbursed and leaves no trace of the attempt', () async {
      final tempDir = Directory.systemTemp.createTempSync('legacy_agreement');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final file = File(p.join(tempDir.path, 'credit_system.sqlite'));

      // A version 12 database: the loans table has no agreed-term columns and
      // the agreement is still awaiting disbursement.
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(_v12Schema);
      const now = 1791000000;
      raw.execute('''
        INSERT INTO "shops" ("id", "name", "currency_code", "timezone", "created_at", "updated_at")
        VALUES ('$shopId', 'Legacy Shop', 'LKR', 'Asia/Colombo', $now, $now);
      ''');
      raw.execute('''
        INSERT INTO "app_users" ("id", "shop_id", "username", "full_name", "role", "is_active", "session_version", "permissions", "password_hash", "created_at", "updated_at")
        VALUES ('$managerId', '$shopId', 'legacy.manager', 'Legacy Manager', 'manager', 1, 1, NULL, NULL, $now, $now);
      ''');
      raw.execute('''
        INSERT INTO "customers" ("id", "shop_id", "full_name", "nic", "phone", "address", "created_at", "updated_at")
        VALUES ('$customerId', '$shopId', 'Legacy Customer', '851234567V', '0771234567', '1 Main St', $now, $now);
      ''');
      // The agreed term was a 30-day preset, so the recorded target date is
      // the creation date + 30 days. The agreed term itself was never stored.
      raw.execute('''
        INSERT INTO "loans" ("id", "shop_id", "customer_id", "principal_cents", "balance_cents", "status", "workflow_status", "due_date", "created_at")
        VALUES ('loan-legacy', '$shopId', '$customerId', 500000, 500000, 'active', 'pending_disbursement', 1793613600, $now);
      ''');
      raw.execute('''
        INSERT INTO "collateral_items" ("id", "shop_id", "customer_id", "loan_id", "item_reference_id", "category", "description", "condition_grade", "weight_milligrams", "estimated_value_cents", "custody_status", "created_at", "updated_at")
        VALUES ('$itemId', '$shopId', '$customerId', 'loan-legacy', 'COLL-LEGACY-001', 'gold', '22K gold necklace', 'Good', 5500, 1500000, 'in_custody', $now, $now);
      ''');
      raw.close();

      // Opening the database runs the real schema version 12 -> 13 upgrade.
      final db = AppDatabase.forTesting(NativeDatabase(
        file,
        setup: (d) => d.execute('PRAGMA foreign_keys = ON;'),
      ));
      addTearDown(() async => db.close());
      final loanDao = LoanDao(db);

      // The upgraded agreement has no recorded term ...
      final legacy = await loanDao.getLoanById(shopId, 'loan-legacy');
      expect(legacy, isNotNull);
      expect(legacy!.termPresetDays, isNull);
      expect(legacy.customDueDate, isNull);
      expect(legacy.workflowStatus,
          equals(LoanWorkflowStatus.pendingDisbursement));

      // ... so the cash disbursement cannot be confirmed.
      Object? failure;
      try {
        await loanDao.confirmLoanDisbursement(
          actor: manager(),
          idempotencyKey: 'legacy-disbursement',
          loanId: legacy.id,
          disbursedAt: disbursedAt,
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull,
          reason: 'A legacy agreement without a recorded term must not be '
              'disbursed on an invented due date.');
      expect(failure.toString(), contains('term'),
          reason: 'The refusal must explain that the agreed term is missing.');
      expect(failure, isA<AgreedTermNotRecordedException>(),
          reason: 'A missing agreed term must be distinguishable from a '
              'custom due date that is no longer in the future, because the '
              'two need different instructions.');
      expect(failure, isA<OfficialDueDateValidationException>(),
          reason: 'The new exception stays compatible with the existing '
              'catch sites for official due-date failures.');
      expect(failure.toString(), contains('No recorded agreed term'),
          reason: 'The refusal must state that the agreed term was never '
              'recorded, which is what makes the agreement un-disbursable.');
      expect(failure.toString(), isNot(contains('Re-agree the term')),
          reason: 'The refusal must not send the operator to an operation that '
              'does not exist.');

      // The agreement is untouched ...
      final after = await loanDao.getLoanById(shopId, 'loan-legacy');
      expect(after!.workflowStatus,
          equals(LoanWorkflowStatus.pendingDisbursement));
      expect(after.disbursedAt, isNull);
      expect(after.disbursedByUserId, isNull);
      expect(after.dueDate, equals(legacy.dueDate));
      expect(after.principalCents, equals(500000));
      expect(after.balanceCents, equals(500000));

      // ... no idempotency claim was left behind ...
      final claims = (await db.select(db.syncQueue).get())
          .where((r) => r.idempotencyKey == 'legacy-disbursement')
          .toList();
      expect(claims, isEmpty,
          reason: 'A failed attempt must not claim the idempotency key.');

      // ... and no misleading audit/sync record was produced.
      final events = (await db.select(db.syncQueue).get())
          .where((r) =>
              r.actionType == LoanDao.confirmLoanDisbursementActionType)
          .toList();
      expect(events, isEmpty);
    });
  });

  group('agreements with a recorded term are unaffected', () {
    late AppDatabase db;
    late LoanDao loanDao;

    setUp(() async {
      db = AppDatabase.forTesting(
          AppDatabaseConnection.openInMemoryConnection());
      loanDao = LoanDao(db);
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(ShopEntry(
        id: shopId,
        name: 'Legacy Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.appUsers).insert(AppUserEntry(
        id: managerId,
        shopId: shopId,
        username: 'legacy.manager',
        fullName: 'Legacy Manager',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.customers).insert(CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Legacy Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    Future<Loan> originate({
      required String idempotencyKey,
      required String itemId,
      int? termPresetDays,
      DateTime? customDueDate,
    }) async {
      return loanDao.createLoanAgreement(
        actor: manager(),
        idempotencyKey: idempotencyKey,
        customerId: customerId,
        principal: const Money(500000),
        dueDate: zone.instantAtStartOfDay(
          const LocalCalendarDate(2026, 11, 14),
        ),
        createdAt: DateTime.now().toUtc(),
        collateralItemIds: [itemId],
        termPresetDays: termPresetDays,
        customDueDate: customDueDate,
      );
    }

    test('a new agreement with a preset term still disburses correctly',
        () async {
      await CollateralDao(db).createCollateralItem(CollateralItem(
        id: 'coll-preset',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-PRESET-001',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Good',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      ));

      final loan = await originate(
        idempotencyKey: 'preset-origin',
        itemId: 'coll-preset',
        termPresetDays: 30,
      );

      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'preset-disbursement',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      expect(disbursed.workflowStatus, equals(LoanWorkflowStatus.disbursed));
      expect(disbursed.dueDateAsCalendarDate(zone), equals('2026-11-14'),
          reason: 'AC-2: a 30-day preset disbursed 2026-10-15 gives 2026-11-14.');
    });

    test('a new agreement with a custom term still disburses correctly',
        () async {
      await CollateralDao(db).createCollateralItem(CollateralItem(
        id: 'coll-custom',
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'COLL-CUSTOM-001',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Good',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      ));

      final custom = zone.instantAtStartOfDay(
        const LocalCalendarDate(2026, 11, 20),
      );
      final loan = await originate(
        idempotencyKey: 'custom-origin',
        itemId: 'coll-custom',
        customDueDate: custom,
      );

      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'custom-disbursement',
        loanId: loan.id,
        disbursedAt: disbursedAt,
      );

      expect(disbursed.workflowStatus, equals(LoanWorkflowStatus.disbursed));
      expect(disbursed.dueDateAsCalendarDate(zone), equals('2026-11-20'));
    });
  });

  group('the recorded target date of a legacy agreement', () {
    late AppDatabase db;
    late LoanDao loanDao;

    /// A legacy agreement: the agreed term was never stored, only the target
    /// date that was recorded at origination.
    Future<Loan> insertLegacyAgreement({
      required String loanId,
      required DateTime createdAt,
      required DateTime targetDate,
      required String itemId,
    }) async {
      await db.into(db.loans).insert(LoansCompanion.insert(
        id: loanId,
        shopId: shopId,
        customerId: customerId,
        principalCents: 500000,
        balanceCents: 500000,
        status: const Value('active'),
        workflowStatus: const Value('pending_disbursement'),
        dueDate: targetDate,
        createdAt: createdAt,
      ));
      await CollateralDao(db).createCollateralItem(CollateralItem(
        id: itemId,
        shopId: shopId,
        customerId: customerId,
        itemReferenceId: 'REF-$itemId',
        category: CollateralItemCategory.gold,
        description: '22K gold necklace',
        conditionGrade: 'Good',
        weightMilligrams: 5500,
        estimatedValueCents: 1500000,
      ));
      return (await loanDao.getLoanById(shopId, loanId))!;
    }

    setUp(() async {
      db = AppDatabase.forTesting(
          AppDatabaseConnection.openInMemoryConnection());
      loanDao = LoanDao(db);
      final now = DateTime.now().toUtc();
      await db.into(db.shops).insert(ShopEntry(
        id: shopId,
        name: 'Legacy Shop',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.appUsers).insert(AppUserEntry(
        id: managerId,
        shopId: shopId,
        username: 'legacy.manager',
        fullName: 'Legacy Manager',
        role: 'manager',
        isActive: true,
        sessionVersion: 1,
        createdAt: now,
        updatedAt: now,
      ));
      await db.into(db.customers).insert(CustomerEntry(
        id: customerId,
        shopId: shopId,
        fullName: 'Legacy Customer',
        nic: '851234567V',
        phone: '0771234567',
        address: '1 Main St',
        createdAt: now,
        updatedAt: now,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    test('is the only surviving trace of the agreed term', () async {
      // The creation instant and the target date that was recorded for a
      // 30-day preset term.
      final createdAt = DateTime.utc(2026, 10, 15, 6);
      final targetDate =
          zone.instantAtStartOfDay(const LocalCalendarDate(2026, 11, 14));

      final legacy = await insertLegacyAgreement(
        loanId: 'loan-trace',
        createdAt: createdAt,
        targetDate: targetDate,
        itemId: 'coll-trace',
      );
      expect(legacy.termPresetDays, isNull,
          reason: 'The agreed term was never recorded.');
      expect(legacy.customDueDate, isNull);
      expect(legacy.dueDate.isAtSameMomentAs(targetDate), isTrue,
          reason: 'The target date recorded at origination survives.');
      expect(zone.localDateOf(legacy.dueDate).isoDate, equals('2026-11-14'));
    });

    test('recovers the agreed date under the ruling that the recorded target '
        'date is the agreed date, using the approved calculation', () async {
      final createdAt = DateTime.utc(2026, 10, 15, 6);
      final targetDate =
          zone.instantAtStartOfDay(const LocalCalendarDate(2026, 11, 14));

      final legacy = await insertLegacyAgreement(
        loanId: 'loan-recovered',
        createdAt: createdAt,
        targetDate: targetDate,
        itemId: 'coll-recovered',
      );

      // Simulate the backfill that the outstanding Product/BA ruling would
      // authorise: the recorded target date becomes the agreed custom date.
      // No new calculation logic is involved - the approved calculator already
      // handles a custom term.
      final recovered = zone.instantAtStartOfDay(
        zone.localDateOf(legacy.dueDate),
      );
      await (db.update(db.loans)..where((l) => l.id.equals(legacy.id)))
          .write(LoansCompanion(customDueDate: Value(recovered)));

      final disbursed = await loanDao.confirmLoanDisbursement(
        actor: manager(),
        idempotencyKey: 'recovered-disbursement',
        loanId: legacy.id,
        disbursedAt: disbursedAt,
      );

      expect(disbursed.workflowStatus, equals(LoanWorkflowStatus.disbursed));
      expect(disbursed.dueDateAsCalendarDate(zone), equals('2026-11-14'),
          reason: 'The recovered agreed date produces the approved official '
              'due date through the existing calculation.');
    });

    test('cannot reveal whether the agreed term was a preset or a fixed '
        'custom date, so the preset reading is not implementable', () async {
      // Created on 2026-10-01 with a 30-day term, so the recorded target date
      // is 2026-10-31. The cash is handed over later, on 2026-10-20.
      final createdAt = DateTime.utc(2026, 10, 1, 6);
      final targetDate =
          zone.instantAtStartOfDay(const LocalCalendarDate(2026, 10, 31));
      final handoverAt = DateTime.utc(2026, 10, 20, 6);

      final legacy = await insertLegacyAgreement(
        loanId: 'loan-ambiguous',
        createdAt: createdAt,
        targetDate: targetDate,
        itemId: 'coll-ambiguous',
      );

      // The recorded target date is exactly 30 calendar days after the
      // creation date, so it is equally consistent with a 30-day preset term
      // and with a fixed custom date of 2026-10-31.
      final elapsedDays = _calendarDaysBetween(
        zone.localDateOf(createdAt),
        zone.localDateOf(legacy.dueDate),
      );
      expect(elapsedDays, equals(30));
      expect(elapsedDays, isIn(<int>[30, 60, 90]));

      // The two readings produce different official due dates, so the
      // recorded data alone cannot decide which one the customer agreed.
      final presetReading = zone.instantAtStartOfDay(
        zone.localDateOf(handoverAt).addDays(elapsedDays),
      );
      final customReading = legacy.dueDate;
      expect(presetReading.isAtSameMomentAs(customReading), isFalse,
          reason: 'The two candidate official due dates differ, so recovering '
              'the term requires a business decision, not a data lookup.');
      expect(zone.localDateOf(presetReading).isoDate, equals('2026-11-19'));
      expect(zone.localDateOf(customReading).isoDate, equals('2026-10-31'));
    });
  });
}

/// The number of calendar days from [from] to [to].
int _calendarDaysBetween(LocalCalendarDate from, LocalCalendarDate to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// A minimal but faithful schema version 12 database: the loans table has no
/// agreed-term columns and the other tables carry their real foreign keys.
const _v12Schema = '''
CREATE TABLE "shops" (
  "id" TEXT NOT NULL PRIMARY KEY, "name" TEXT NOT NULL,
  "currency_code" TEXT NOT NULL DEFAULT 'LKR', "timezone" TEXT NOT NULL DEFAULT 'Asia/Colombo',
  "business_address" TEXT, "contact_phone" TEXT, "contact_email" TEXT, "registration_number" TEXT,
  "logo_uri" TEXT, "receipt_header_notes" TEXT, "receipt_footer_notes" TEXT,
  "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL);
CREATE TABLE "app_users" (
  "id" TEXT NOT NULL PRIMARY KEY, "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
  "username" TEXT NOT NULL, "full_name" TEXT NOT NULL, "role" TEXT NOT NULL,
  "is_active" INTEGER NOT NULL DEFAULT 1, "session_version" INTEGER NOT NULL DEFAULT 1,
  "permissions" TEXT, "password_hash" TEXT,
  "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL);
CREATE TABLE "sync_queue" (
  "id" TEXT NOT NULL PRIMARY KEY, "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
  "idempotency_key" TEXT NOT NULL, "entity_type" TEXT NOT NULL, "entity_id" TEXT NOT NULL,
  "action_type" TEXT NOT NULL, "payload_json" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending_server_ack', "retry_count" INTEGER NOT NULL DEFAULT 0,
  "last_error" TEXT, "created_at" INTEGER NOT NULL, "updated_at" INTEGER,
  UNIQUE ("shop_id", "idempotency_key"));
CREATE TABLE "customers" (
  "id" TEXT NOT NULL PRIMARY KEY, "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
  "full_name" TEXT NOT NULL, "nic" TEXT NOT NULL, "phone" TEXT NOT NULL, "address" TEXT NOT NULL,
  "photo_uri" TEXT, "photo_hash" TEXT, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL);
CREATE TABLE "loans" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
  "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
  "principal_cents" INTEGER NOT NULL, "balance_cents" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active', "workflow_status" TEXT NOT NULL DEFAULT 'pending_disbursement',
  "due_date" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "settled_at" INTEGER);
CREATE TABLE "collateral_items" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "shop_id" TEXT NOT NULL REFERENCES "shops" ("id") ON DELETE RESTRICT,
  "customer_id" TEXT NOT NULL REFERENCES "customers" ("id") ON DELETE RESTRICT,
  "loan_id" TEXT REFERENCES "loans" ("id") ON DELETE RESTRICT,
  "item_reference_id" TEXT NOT NULL, "category" TEXT NOT NULL, "description" TEXT NOT NULL,
  "condition_grade" TEXT NOT NULL, "weight_milligrams" INTEGER NOT NULL,
  "estimated_value_cents" INTEGER NOT NULL, "photo_uri" TEXT, "photo_hash" TEXT,
  "custody_status" TEXT NOT NULL DEFAULT 'in_custody',
  "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL,
  UNIQUE ("shop_id", "item_reference_id"));
PRAGMA user_version = 12;
''';
