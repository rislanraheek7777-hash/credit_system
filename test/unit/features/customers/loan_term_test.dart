import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';

void main() {
  group('LoanTermPreset - approved presets only (AC-1)', () {
    test('exposes exactly the 30, 60 and 90 calendar-day presets', () {
      expect(
        LoanTermPreset.values.map((p) => p.calendarDays).toList(),
        equals([30, 60, 90]),
      );
    });

    test('fromCalendarDays resolves the known presets', () {
      expect(
        LoanTermPreset.fromCalendarDays(30),
        equals(LoanTermPreset.thirtyDays),
      );
      expect(
        LoanTermPreset.fromCalendarDays(60),
        equals(LoanTermPreset.sixtyDays),
      );
      expect(
        LoanTermPreset.fromCalendarDays(90),
        equals(LoanTermPreset.ninetyDays),
      );
    });

    test('fromCalendarDays rejects durations that are not approved presets', () {
      expect(LoanTermPreset.fromCalendarDays(45), isNull);
      expect(LoanTermPreset.fromCalendarDays(0), isNull);
    });
  });

  group('LocalCalendarDate - exact civil arithmetic', () {
    test('addDays crosses month boundaries correctly', () {
      expect(
        const LocalCalendarDate(2026, 1, 31).addDays(1),
        equals(const LocalCalendarDate(2026, 2, 1)),
      );
      expect(
        const LocalCalendarDate(2026, 12, 31).addDays(1),
        equals(const LocalCalendarDate(2027, 1, 1)),
      );
    });

    test('addDays handles leap years', () {
      expect(
        const LocalCalendarDate(2028, 2, 28).addDays(1),
        equals(const LocalCalendarDate(2028, 2, 29)),
      );
      expect(
        const LocalCalendarDate(2026, 2, 28).addDays(1),
        equals(const LocalCalendarDate(2026, 3, 1)),
      );
    });

    test('comparison is calendar-date granular, not instant granular', () {
      const earlier = LocalCalendarDate(2026, 3, 15);
      const later = LocalCalendarDate(2026, 3, 16);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier.isAfter(later), isFalse);
      expect(
        const LocalCalendarDate(2026, 3, 15).isAfter(earlier),
        isFalse,
        reason: 'A same-day comparison must not be "after".',
      );
    });

    test('parseIso parses a valid ISO date and rejects malformed input', () {
      expect(
        LocalCalendarDate.parseIso('2026-11-30'),
        equals(const LocalCalendarDate(2026, 11, 30)),
      );
      expect(() => LocalCalendarDate.parseIso('30-11-2026'), throwsA(anything));
      expect(() => LocalCalendarDate.parseIso('2026-11'), throwsA(anything));
    });

    test('isoDate renders a zero-padded YYYY-MM-DD string', () {
      expect(const LocalCalendarDate(2026, 1, 5).isoDate, equals('2026-01-05'));
    });
  });

  group('ShopTimeZone - configured shop time zone', () {
    test('resolves the approved Asia/Colombo default', () {
      final zone = ShopTimeZone.defaultTimeZone();
      expect(zone.identifier, equals('Asia/Colombo'));
    });

    test('fails closed for an unknown IANA identifier', () {
      expect(
        () => ShopTimeZone('Not/A_Zone'),
        throwsA(isA<UnsupportedShopTimeZoneException>()),
      );
    });

    test('fails closed for a blank identifier', () {
      expect(
        () => ShopTimeZone('   '),
        throwsA(isA<UnsupportedShopTimeZoneException>()),
      );
    });

    test('localDateOf uses the zone calendar date, not the UTC date', () {
      final zone = ShopTimeZone.defaultTimeZone();
      // 2026-03-15T20:00Z is already 2026-03-16 01:30 in Colombo (UTC+05:30).
      final instant = DateTime.utc(2026, 3, 15, 20);
      expect(
        zone.localDateOf(instant),
        equals(const LocalCalendarDate(2026, 3, 16)),
      );
    });

    test('instantAtStartOfDay returns local midnight of that day', () {
      final zone = ShopTimeZone.defaultTimeZone();
      expect(
        zone.instantAtStartOfDay(const LocalCalendarDate(2026, 3, 16)),
        equals(DateTime.utc(2026, 3, 15, 18, 30)),
        reason: 'Colombo midnight is 18:30 UTC the previous day.',
      );
    });
  });

  group('PreliminaryDueDateCalculator - preset durations (AC-1)', () {
    final zone = ShopTimeZone.defaultTimeZone();
    final calculator = PreliminaryDueDateCalculator(shopTimeZone: zone);

    test('30 day preset adds 30 calendar days', () {
      final createdAt = DateTime.utc(2026, 3, 16, 4);
      final due = calculator.preliminaryDueDateForPreset(
        createdAt,
        LoanTermPreset.thirtyDays,
      );
      expect(
        zone.localDateOf(due),
        equals(const LocalCalendarDate(2026, 4, 15)),
      );
    });

    test('60 day preset adds 60 calendar days', () {
      final createdAt = DateTime.utc(2026, 3, 16, 4);
      final due = calculator.preliminaryDueDateForPreset(
        createdAt,
        LoanTermPreset.sixtyDays,
      );
      expect(
        zone.localDateOf(due),
        equals(const LocalCalendarDate(2026, 5, 15)),
      );
    });

    test('90 day preset adds 90 calendar days', () {
      final createdAt = DateTime.utc(2026, 3, 16, 4);
      final due = calculator.preliminaryDueDateForPreset(
        createdAt,
        LoanTermPreset.ninetyDays,
      );
      expect(
        zone.localDateOf(due),
        equals(const LocalCalendarDate(2026, 6, 14)),
      );
    });

    test('the result depends on the shop time zone, not on UTC', () {
      final createdAt = DateTime.utc(2026, 3, 15, 20);

      final colombo = PreliminaryDueDateCalculator(
        shopTimeZone: ShopTimeZone.defaultTimeZone(),
      ).preliminaryDueDateForPreset(createdAt, LoanTermPreset.thirtyDays);

      final utc = PreliminaryDueDateCalculator(
        shopTimeZone: ShopTimeZone('UTC'),
      ).preliminaryDueDateForPreset(createdAt, LoanTermPreset.thirtyDays);

      expect(
        ShopTimeZone.defaultTimeZone().localDateOf(colombo),
        equals(const LocalCalendarDate(2026, 4, 15)),
      );
      expect(
        ShopTimeZone('UTC').localDateOf(utc),
        equals(const LocalCalendarDate(2026, 4, 14)),
        reason: 'The same instant is a different calendar day in each zone.',
      );
    });

    test('the calculated date is independent of the time of day', () {
      final morning = DateTime.utc(2026, 3, 16, 1);
      final night = DateTime.utc(2026, 3, 16, 18);
      expect(
        zone.localDateOf(
          calculator.preliminaryDueDateForPreset(
            morning,
            LoanTermPreset.thirtyDays,
          ),
        ),
        equals(
          zone.localDateOf(
            calculator.preliminaryDueDateForPreset(
              night,
              LoanTermPreset.thirtyDays,
            ),
          ),
        ),
      );
    });

    test('a daylight-saving transition does not shift the calendar result', () {
      // America/New_York enters DST on 2026-03-08. Civil-date arithmetic must
      // still land on 2026-03-31, not 2026-03-30.
      final newYork = ShopTimeZone('America/New_York');
      final nyCalculator = PreliminaryDueDateCalculator(shopTimeZone: newYork);
      final createdAt = DateTime.utc(2026, 3, 1, 17); // 12:00 in New York
      final due = nyCalculator.preliminaryDueDateForPreset(
        createdAt,
        LoanTermPreset.thirtyDays,
      );
      expect(
        newYork.localDateOf(due),
        equals(const LocalCalendarDate(2026, 3, 31)),
      );
    });
  });

  group('PreliminaryDueDateCalculator - custom due date (AC-2)', () {
    final zone = ShopTimeZone.defaultTimeZone();
    final calculator = PreliminaryDueDateCalculator(shopTimeZone: zone);
    final createdAt = DateTime.utc(2026, 3, 16, 4);

    test('accepts a strictly later calendar date', () {
      final due = calculator.preliminaryDueDateForCustom(
        createdAt,
        const LocalCalendarDate(2026, 3, 17),
      );
      expect(
        zone.localDateOf(due),
        equals(const LocalCalendarDate(2026, 3, 17)),
      );
    });

    test('rejects a same-day date (strictly greater is required)', () {
      expect(
        () => calculator.preliminaryDueDateForCustom(
          createdAt,
          const LocalCalendarDate(2026, 3, 16),
        ),
        throwsA(isA<LoanTermValidationException>()),
      );
    });

    test('rejects a past date', () {
      expect(
        () => calculator.preliminaryDueDateForCustom(
          createdAt,
          const LocalCalendarDate(2026, 3, 15),
        ),
        throwsA(isA<LoanTermValidationException>()),
      );
    });

    test('rejects the day immediately before the creation date', () {
      expect(
        () => calculator.preliminaryDueDateForCustom(
          createdAt,
          const LocalCalendarDate(2026, 3, 15),
        ),
        throwsA(isA<LoanTermValidationException>()),
      );
    });

    test('isCustomDateValid mirrors the validation outcome', () {
      expect(
        calculator.isCustomDateValid(
          createdAt,
          const LocalCalendarDate(2026, 3, 17),
        ),
        isTrue,
      );
      expect(
        calculator.isCustomDateValid(
          createdAt,
          const LocalCalendarDate(2026, 3, 16),
        ),
        isFalse,
      );
    });

    test('a same-day custom date is rejected even when the instants differ', () {
      // 2026-03-16T20:00Z is 2026-03-17 in Colombo — a genuinely later day.
      final lateCreatedAt = DateTime.utc(2026, 3, 16, 20);
      expect(
        calculator.isCustomDateValid(
          lateCreatedAt,
          const LocalCalendarDate(2026, 3, 16),
        ),
        isFalse,
        reason: 'The creation day in Colombo is 2026-03-17, so 03-16 is past.',
      );
      expect(
        calculator.isCustomDateValid(
          lateCreatedAt,
          const LocalCalendarDate(2026, 3, 17),
        ),
        isFalse,
        reason: 'Same calendar day as creation must be rejected.',
      );
      expect(
        calculator.isCustomDateValid(
          lateCreatedAt,
          const LocalCalendarDate(2026, 3, 18),
        ),
        isTrue,
      );
    });
  });

  group('LoanTerm', () {
    test('a preset term reports the preset label and is not custom', () {
      const term = LoanTerm.preset(LoanTermPreset.sixtyDays);
      expect(term.isCustom, isFalse);
      expect(term.preset, equals(LoanTermPreset.sixtyDays));
      expect(term.displayLabel, equals('60 Days'));
    });

    test('a custom term reports the ISO custom date and is custom', () {
      const term = LoanTerm.custom(LocalCalendarDate(2026, 11, 30));
      expect(term.isCustom, isTrue);
      expect(term.customDate, equals(const LocalCalendarDate(2026, 11, 30)));
      expect(term.displayLabel, contains('2026-11-30'));
    });
  });

  group('OfficialDueDateCalculator - preset terms (Story 4.3, PRD FR-19)', () {
    final zone = ShopTimeZone.defaultTimeZone();
    final calculator = OfficialDueDateCalculator(shopTimeZone: zone);

    // 2026-10-15 06:00Z is 2026-10-15 11:30 in Asia/Colombo.
    final disbursedAt = DateTime.utc(2026, 10, 15, 6);

    test('30-day preset disbursed 2026-10-15 gives 2026-11-14 (TC-1)', () {
      final due = calculator.officialDueDate(
        disbursedAt: disbursedAt,
        termPresetDays: 30,
        customDueDate: null,
      );
      expect(zone.localDateOf(due), equals(const LocalCalendarDate(2026, 11, 14)));
    });

    test('60-day preset disbursed 2026-10-15 gives 2026-12-14 (TC-2)', () {
      final due = calculator.officialDueDate(
        disbursedAt: disbursedAt,
        termPresetDays: 60,
        customDueDate: null,
      );
      expect(zone.localDateOf(due), equals(const LocalCalendarDate(2026, 12, 14)));
    });

    test('90-day preset disbursed 2026-10-15 gives 2027-01-13 (TC-3)', () {
      final due = calculator.officialDueDate(
        disbursedAt: disbursedAt,
        termPresetDays: 90,
        customDueDate: null,
      );
      expect(zone.localDateOf(due), equals(const LocalCalendarDate(2027, 1, 13)));
    });

    test('the result is independent of the time of day of the disbursement',
        () {
      final morning = calculator.officialDueDate(
        disbursedAt: DateTime.utc(2026, 10, 15, 0, 30),
        termPresetDays: 30,
        customDueDate: null,
      );
      final night = calculator.officialDueDate(
        disbursedAt: DateTime.utc(2026, 10, 15, 11),
        termPresetDays: 30,
        customDueDate: null,
      );
      expect(zone.localDateOf(morning), equals(zone.localDateOf(night)));
    });

    test('a daylight-saving transition does not shift the calendar result',
        () {
      final newYork = ShopTimeZone('America/New_York');
      final nyCalculator = OfficialDueDateCalculator(shopTimeZone: newYork);
      // 2026-03-01 12:00 in New York; DST starts on 2026-03-08.
      final due = nyCalculator.officialDueDate(
        disbursedAt: DateTime.utc(2026, 3, 1, 17),
        termPresetDays: 30,
        customDueDate: null,
      );
      expect(newYork.localDateOf(due), equals(const LocalCalendarDate(2026, 3, 31)));
    });

    test('the shop time zone, not UTC, determines the calendar day', () {
      final utcCalculator =
          OfficialDueDateCalculator(shopTimeZone: ShopTimeZone('UTC'));
      final utcDue = utcCalculator.officialDueDate(
        disbursedAt: disbursedAt,
        termPresetDays: 30,
        customDueDate: null,
      );
      final colomboDue = calculator.officialDueDate(
        disbursedAt: disbursedAt,
        termPresetDays: 30,
        customDueDate: null,
      );
      // Both are local midnight of their own zone's 30th day.
      expect(
        ShopTimeZone('UTC').localDateOf(utcDue),
        equals(const LocalCalendarDate(2026, 11, 14)),
      );
      expect(
        zone.localDateOf(colomboDue),
        equals(const LocalCalendarDate(2026, 11, 14)),
      );
      // But they are different instants.
      expect(utcDue.isAtSameMomentAs(colomboDue), isFalse);
    });
  });

  group('OfficialDueDateCalculator - custom terms (Story 4.3, PRD FR-19)', () {
    final zone = ShopTimeZone.defaultTimeZone();
    final calculator = OfficialDueDateCalculator(shopTimeZone: zone);

    test('a custom date strictly after the disbursement date is confirmed (TC-4)',
        () {
      final due = calculator.officialDueDate(
        disbursedAt: DateTime.utc(2026, 10, 12, 6),
        termPresetDays: null,
        customDueDate: const LocalCalendarDate(2026, 11, 20),
      );
      expect(zone.localDateOf(due), equals(const LocalCalendarDate(2026, 11, 20)));
    });

    test('a custom date equal to the disbursement date is blocked (TC-5)',
        () {
      expect(
        () => calculator.officialDueDate(
          disbursedAt: DateTime.utc(2026, 10, 15, 6),
          termPresetDays: null,
          customDueDate: const LocalCalendarDate(2026, 10, 15),
        ),
        throwsA(isA<OfficialDueDateValidationException>()),
      );
    });

    test('a custom date before the disbursement date is blocked (TC-5)', () {
      expect(
        () => calculator.officialDueDate(
          disbursedAt: DateTime.utc(2026, 10, 16, 6),
          termPresetDays: null,
          customDueDate: const LocalCalendarDate(2026, 10, 15),
        ),
        throwsA(isA<OfficialDueDateValidationException>()),
      );
    });

    test('an agreement with no recorded term cannot be finalised', () {
      expect(
        () => calculator.officialDueDate(
          disbursedAt: DateTime.utc(2026, 10, 15, 6),
          termPresetDays: null,
          customDueDate: null,
        ),
        throwsA(isA<OfficialDueDateValidationException>()),
      );
    });
  });
}
