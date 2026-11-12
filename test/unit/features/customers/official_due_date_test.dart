import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/data/daos/collateral_dao.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/daos/credit_dao.dart';
import 'package:credit_system/features/customers/domain/models/credit.dart';
import 'package:credit_system/features/customers/domain/models/credit_term.dart';
import 'package:flutter_test/flutter_test.dart';

/// Coverage for the official calendar due date of Story 4.3 AC-2 / PRD FR-19.
///
/// The official due date is a **calendar date in the shop's operational time
/// zone**, computed as
/// `Disbursement Date (in Shop Local Time) + N calendar days`. It is
/// persisted as the UTC instant of shop-local midnight of that calendar date,
/// so the calendar date must always be read back in the shop's own zone.
///
/// The three approved AC-2 examples are asserted explicitly, together with
/// month and year boundaries, a leap-year boundary and a daylight-saving
/// boundary.
void main() {
  const shopId = '11111111-1111-1111-1111-111111111601';
  const customerId = 1;
  const managerId = '11111111-1111-1111-1111-111111111604';
  const itemId = 'coll-due-1';

  late AppDatabase db;
  late CreditDao creditDao;
  late String shopTimeZoneIdentifier;

  /// 2026-10-15 06:00Z is 2026-10-15 11:30 in Asia/Colombo.
  final disbursedOnOctober15 = DateTime.utc(2026, 10, 15, 6);

  AppUser manager() => AppUser(
        id: managerId,
        shopId: shopId,
        username: 'due.manager',
        fullName: 'Due Manager',
        role: AppRole.manager,
        isActive: true,
      );

  setUp(() async {
    final inMemoryExecutor = AppDatabaseConnection.openInMemoryConnection();
    db = AppDatabase.forTesting(inMemoryExecutor);
    creditDao = CreditDao(db);
    shopTimeZoneIdentifier = 'Asia/Colombo';

    final now = DateTime.now().toUtc();
    await db.into(db.shops).insert(ShopEntry(
      id: shopId,
      name: 'Due Date Shop',
      currencyCode: 'LKR',
      timezone: shopTimeZoneIdentifier,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.appUsers).insert(AppUserEntry(
      id: managerId,
      shopId: shopId,
      username: 'due.manager',
      fullName: 'Due Manager',
      role: 'manager',
      isActive: true,
      sessionVersion: 1,
      createdAt: now,
      updatedAt: now,
    ));
    await db.into(db.customers).insert(CustomerEntry(
      id: customerId,
      shopId: shopId,
      fullName: 'Due Date Customer',
      nic: '851234567V',
      phone: '0771234567',
      address: '1 Main St',
      createdAt: now,
      updatedAt: now,
    ));
    await CollateralDao(db).createCollateralItem(CollateralItem(
      id: itemId,
      shopId: shopId,
      customerId: customerId,
      itemReferenceId: 'COLL-DUE-001',
      category: CollateralItemCategory.gold,
      description: '22K gold necklace',
      conditionGrade: 'Like New',
      weightMilligrams: 5500,
      estimatedValueCents: 1500000,
    ));
  });

  tearDown(() async {
    await db.close();
  });

  ShopTimeZone zone() => ShopTimeZone(shopTimeZoneIdentifier);

  /// Originates an agreement with the given preset term and confirms its cash
  /// disbursement at [disbursedAt].
  ///
  /// Returns the reloaded agreement.
  Future<Credit> disburse({
    required int termPresetDays,
    required DateTime disbursedAt,
    String idempotencyKey = 'due-key',
  }) async {
    final shopZone = zone();
    final created = await creditDao.createCreditAgreement(
      actor: manager(),
      idempotencyKey: 'orig-$idempotencyKey',
      customerId: customerId,
      principal: const Money(500000),
      dueDate: shopZone.instantAtStartOfDay(
        LocalCalendarDate(2026, 10, 14),
      ),
      createdAt: DateTime.now().toUtc(),
      collateralItemIds: const [itemId],
      termPresetDays: termPresetDays,
    );

    await creditDao.confirmCreditDisbursement(
      actor: manager(),
      idempotencyKey: idempotencyKey,
      creditId: created.id,
      disbursedAt: disbursedAt,
    );

    // Reload the agreement from the database so the assertions below see the
    // persisted value, not the in-memory one.
    final reloaded = await creditDao.getCreditById(shopId, created.id);
    expect(reloaded, isNotNull);
    return reloaded!;
  }

  group('Story 4.3 AC-2 — the approved preset examples', () {
    test('a 30-day preset disbursed on October 15 produces November 14',
        () async {
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: disbursedOnOctober15,
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-11-14'));
      expect(credit.dueDate.toUtc(), equals(DateTime.utc(2026, 11, 13, 18, 30)),
          reason: 'The persisted instant is shop-local midnight of 2026-11-14.');
    });

    test('a 60-day preset disbursed on October 15 produces December 14',
        () async {
      final credit = await disburse(
        termPresetDays: 60,
        disbursedAt: disbursedOnOctober15,
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-12-14'));
    });

    test(
        'a 90-day preset disbursed on October 15 produces January 13 of the '
        'following year', () async {
      final credit = await disburse(
        termPresetDays: 90,
        disbursedAt: disbursedOnOctober15,
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2027-01-13'));
    });
  });

  group('Story 4.3 AC-2 — calendar boundaries', () {
    test('a month boundary is crossed by calendar days, not elapsed hours',
        () async {
      // 2026-01-31 + 30 calendar days = 2026-03-02 (2026 is not a leap year).
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: DateTime.utc(2026, 1, 31, 6),
        idempotencyKey: 'month-boundary',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-03-02'));
    });

    test('a year boundary is crossed into the following year', () async {
      // 2026-12-20 + 30 calendar days = 2027-01-19.
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: DateTime.utc(2026, 12, 20, 6),
        idempotencyKey: 'year-boundary',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2027-01-19'));
    });

    test('a leap-year February is handled by calendar arithmetic', () async {
      // 2028-02-01 + 30 calendar days = 2028-03-02 (February 2028 has 29 days).
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: DateTime.utc(2028, 2, 1, 6),
        idempotencyKey: 'leap-year',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2028-03-02'));
    });

    test('a daylight-saving transition does not shift the calendar date',
        () async {
      // America/New_York enters daylight saving on 2026-03-08.
      shopTimeZoneIdentifier = 'America/New_York';
      await db.into(db.shops).insertOnConflictUpdate(ShopEntry(
        id: shopId,
        name: 'Due Date Shop',
        currencyCode: 'LKR',
        timezone: shopTimeZoneIdentifier,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ));

      // 2026-03-01 12:00 in New York; daylight saving starts on 2026-03-08.
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: DateTime.utc(2026, 3, 1, 17),
        idempotencyKey: 'dst',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-03-31'));
    });
  });

  group('the shop\'s configured time zone is what decides the calendar date',
      () {
    test('a shop in a zone east of UTC keeps its agreed calendar date',
        () async {
      // Asia/Colombo is UTC+05:30, so shop-local midnight is 18:30 UTC on the
      // previous day.
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: disbursedOnOctober15,
        idempotencyKey: 'east',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-11-14'));
      expect(
        credit.dueDate.toUtc().toIso8601String().substring(0, 10),
        equals('2026-11-13'),
        reason: 'The UTC calendar date of the stored instant differs from the '
            'agreed calendar date, which is exactly why it must never be '
            'rendered directly.',
      );
    });

    test('a shop in a zone west of UTC keeps its agreed calendar date',
        () async {
      shopTimeZoneIdentifier = 'America/New_York';
      await db.into(db.shops).insertOnConflictUpdate(ShopEntry(
        id: shopId,
        name: 'Due Date Shop',
        currencyCode: 'LKR',
        timezone: shopTimeZoneIdentifier,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ));

      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: DateTime.utc(2026, 10, 15, 14),
        idempotencyKey: 'west',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-11-14'));
    });

    test('a shop in UTC keeps its agreed calendar date', () async {
      shopTimeZoneIdentifier = 'UTC';
      await db.into(db.shops).insertOnConflictUpdate(ShopEntry(
        id: shopId,
        name: 'Due Date Shop',
        currencyCode: 'LKR',
        timezone: shopTimeZoneIdentifier,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ));

      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: DateTime.utc(2026, 10, 15, 6),
        idempotencyKey: 'utc',
      );

      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-11-14'));
      expect(credit.dueDate.toUtc(), equals(DateTime.utc(2026, 11, 14)));
    });

    test('an unresolvable shop zone falls back to the approved default',
        () async {
      await db.into(db.shops).insertOnConflictUpdate(ShopEntry(
        id: shopId,
        name: 'Due Date Shop',
        currencyCode: 'LKR',
        timezone: 'Not/A_Zone',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ));

      final resolved = await creditDao.resolveShopTimeZone(shopId);
      expect(resolved.identifier, equals(ShopTimeZone.defaultIdentifier));
    });
  });

  group('persistence and reload', () {
    test('the persisted and reloaded due date is the agreed calendar date',
        () async {
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: disbursedOnOctober15,
        idempotencyKey: 'reload',
      );

      // The value read straight from the database row.
      final row = await (db.select(db.credits)
            ..where((l) => l.id.equals(credit.id)))
          .getSingle();
      expect(zone().localDateOf(row.dueDate).isoDate, equals('2026-11-14'));
      expect(
        row.dueDate.toUtc(),
        equals(DateTime.utc(2026, 11, 13, 18, 30)),
        reason: 'The stored instant must be shop-local midnight.',
      );

      // ... and the domain rendering of the reloaded agreement agrees.
      expect(credit.dueDateAsCalendarDate(zone()), equals('2026-11-14'));
    });

    test('the disbursement event record carries the agreed calendar date',
        () async {
      final credit = await disburse(
        termPresetDays: 30,
        disbursedAt: disbursedOnOctober15,
        idempotencyKey: 'event',
      );

      final rows = await db.select(db.syncQueue).get();
      final event = rows.firstWhere(
        (r) => r.actionType == CreditDao.confirmCreditDisbursementActionType,
      );

      final payload =
          (event.payloadJson.isEmpty ? '{}' : event.payloadJson);
      expect(payload, contains('2026-11-14'),
          reason: 'The event payload records the official due date as the '
              'shop-local calendar date.');
      expect(payload, contains(credit.id));
    });
  });
}

