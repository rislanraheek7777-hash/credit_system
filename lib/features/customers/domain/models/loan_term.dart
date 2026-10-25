import 'package:meta/meta.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Exception thrown when a loan term violates the approved business rules
/// (Story 4.2, PRD FR-17).
class LoanTermValidationException implements Exception {
  /// Human-readable reason the term was rejected.
  final String message;

  const LoanTermValidationException(this.message);

  @override
  String toString() => 'LoanTermValidationException: $message';
}

/// Exception thrown when a shop's configured IANA time zone identifier cannot
/// be resolved (Story 4.2, PRD FR-17).
class UnsupportedShopTimeZoneException implements Exception {
  /// The offending IANA identifier.
  final String identifier;

  const UnsupportedShopTimeZoneException(this.identifier);

  @override
  String toString() =>
      'UnsupportedShopTimeZoneException: Unknown IANA time zone "$identifier".';
}

/// Lazily-initialised registry for the IANA time zone database.
///
/// `tz.initializeTimeZones()` loads the bundled zone database exactly once.
/// It is invoked on first use so that no application-startup ordering
/// requirement is introduced.
class _TimeZoneRegistry {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    tz.initializeTimeZones();
    _initialized = true;
  }
}

/// Exception thrown when the OFFICIAL due date cannot be finalised at cash
/// disbursement (Story 4.3, PRD FR-19).
class OfficialDueDateValidationException implements Exception {
  /// Human-readable reason the due date could not be finalised.
  final String message;

  const OfficialDueDateValidationException(this.message);

  @override
  String toString() => 'OfficialDueDateValidationException: $message';
}

/// Exception thrown when an agreement has **no recorded agreed term**, so its
/// official calendar due date cannot be calculated at all (Story 4.3).
///
/// The agreed-term columns (`term_preset_days`, `custom_due_date`) were
/// introduced by the schema version 13 migration, which left them empty for
/// every pre-existing agreement. An agreement that was still awaiting
/// disbursement at that point therefore carries no agreed term.
///
/// The recorded target date is still available, but it does not reveal whether
/// the agreed term was a standard preset or a fixed custom date, so the term
/// cannot be recovered reliably and the cash disbursement must not be
/// confirmed on a guess. The agreement itself is left untouched.
class AgreedTermNotRecordedException extends OfficialDueDateValidationException {
  const AgreedTermNotRecordedException(super.message);

  @override
  String toString() => 'AgreedTermNotRecordedException: $message';
}

/// A calendar date (year, month, day) with no time-of-day component.
///
/// Loan due dates are *calendar* dates, not instants: adding "30 days" to an
/// agreement must land on the 30th calendar day in the shop's local time zone,
/// regardless of any daylight-saving transition in between.
@immutable
class LocalCalendarDate implements Comparable<LocalCalendarDate> {
  /// Calendar year.
  final int year;

  /// Calendar month (1-12).
  final int month;

  /// Calendar day of month (1-31).
  final int day;

  const LocalCalendarDate(this.year, this.month, this.day)
      : assert(month >= 1 && month <= 12, 'month must be between 1 and 12'),
        assert(day >= 1 && day <= 31, 'day must be between 1 and 31');

  /// Extracts the calendar date components from a [DateTime].
  ///
  /// The caller is responsible for supplying a [DateTime] that already
  /// represents the desired local wall clock (see [ShopTimeZone.localDateOf]).
  factory LocalCalendarDate.fromDateTime(DateTime value) =>
      LocalCalendarDate(value.year, value.month, value.day);

  /// Parses an ISO `YYYY-MM-DD` calendar date.
  ///
  /// The format is validated strictly: a differently ordered or unpadded
  /// value is rejected rather than silently reinterpreted.
  factory LocalCalendarDate.parseIso(String isoDate) {
    final trimmed = isoDate.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      throw LoanTermValidationException(
        'Invalid ISO calendar date "$isoDate"; expected YYYY-MM-DD.',
      );
    }
    final parts = trimmed.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw LoanTermValidationException(
        'Invalid ISO calendar date "$isoDate"; month or day is out of range.',
      );
    }
    return LocalCalendarDate(year, month, day);
  }

  /// Returns this date advanced by [days] calendar days.
  ///
  /// Uses UTC-normalised civil arithmetic so the result is exact regardless of
  /// daylight-saving transitions or month lengths.
  LocalCalendarDate addDays(int days) {
    final civil = DateTime.utc(year, month, day).add(Duration(days: days));
    return LocalCalendarDate(civil.year, civil.month, civil.day);
  }

  /// The ISO `YYYY-MM-DD` rendering of this date.
  String get isoDate =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalCalendarDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  /// Whether this date falls strictly after [other].
  bool isAfter(LocalCalendarDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is LocalCalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => isoDate;
}

/// The operational IANA time zone of a shop (Story 4.2, PRD FR-17).
///
/// All loan due-date arithmetic is performed in this zone. The approved
/// default is `Asia/Colombo`, matching the `shops.timezone` column default.
@immutable
class ShopTimeZone {
  /// The IANA identifier (e.g. `Asia/Colombo`).
  final String identifier;

  final tz.Location _location;

  const ShopTimeZone._(this.identifier, this._location);

  /// The approved default operational time zone.
  static const String defaultIdentifier = 'Asia/Colombo';

  /// Resolves [identifier] to a usable shop time zone.
  ///
  /// Throws [UnsupportedShopTimeZoneException] when the identifier is not a
  /// known IANA zone — it fails closed rather than silently falling back to a
  /// different zone, which would mis-date every loan in that shop.
  factory ShopTimeZone(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      throw const UnsupportedShopTimeZoneException('');
    }
    _TimeZoneRegistry.ensureInitialized();
    try {
      return ShopTimeZone._(
        trimmed,
        tz.getLocation(trimmed),
      );
    } on tz.LocationNotFoundException {
      throw UnsupportedShopTimeZoneException(trimmed);
    }
  }

  /// The approved default shop time zone (`Asia/Colombo`).
  factory ShopTimeZone.defaultTimeZone() =>
      ShopTimeZone(ShopTimeZone.defaultIdentifier);

  /// The calendar date on which [instant] falls in this zone.
  LocalCalendarDate localDateOf(DateTime instant) {
    final local = tz.TZDateTime.from(instant, _location);
    return LocalCalendarDate(local.year, local.month, local.day);
  }

  /// The instant of local midnight (00:00) on [date] in this zone.
  ///
  /// Daylight-saving gaps are resolved by the underlying zone database to the
  /// first valid instant of that local day.
  DateTime instantAtStartOfDay(LocalCalendarDate date) =>
      tz.TZDateTime(_location, date.year, date.month, date.day).toUtc();

  /// The local wall-clock rendering of [instant] in this zone.
  tz.TZDateTime toLocal(DateTime instant) =>
      tz.TZDateTime.from(instant, _location);

  @override
  bool operator ==(Object other) =>
      other is ShopTimeZone && other.identifier == identifier;

  @override
  int get hashCode => identifier.hashCode;

  @override
  String toString() => 'ShopTimeZone($identifier)';
}

/// The approved standard loan term duration presets (Story 4.2, PRD FR-17).
///
/// Version 1 supports exactly 30, 60 and 90 *calendar* days. Business-day
/// arithmetic excluding public holidays is explicitly out of scope for V1.
enum LoanTermPreset {
  /// 30 calendar days.
  thirtyDays(30, '30 Days'),

  /// 60 calendar days.
  sixtyDays(60, '60 Days'),

  /// 90 calendar days.
  ninetyDays(90, '90 Days');

  /// The number of calendar days added to the agreement creation date.
  final int calendarDays;

  /// The human-readable preset label shown in the origination form.
  final String label;

  const LoanTermPreset(this.calendarDays, this.label);

  /// Resolves the preset whose [calendarDays] equals [days], or `null`.
  static LoanTermPreset? fromCalendarDays(int days) {
    for (final preset in LoanTermPreset.values) {
      if (preset.calendarDays == days) return preset;
    }
    return null;
  }
}

/// A selected loan term: either a standard duration preset or a custom
/// calendar due date (Story 4.2, PRD FR-17).
@immutable
class LoanTerm {
  /// The selected preset, or `null` for a custom term.
  final LoanTermPreset? preset;

  /// The selected custom calendar date, or `null` for a preset term.
  final LocalCalendarDate? customDate;

  const LoanTerm.preset(this.preset) : customDate = null;

  const LoanTerm.custom(this.customDate) : preset = null;

  /// Whether this term uses a custom calendar date.
  bool get isCustom => customDate != null;

  /// The term's display label, e.g. `30 Days` or `Custom — 2026-11-30`.
  String get displayLabel => isCustom
      ? 'Custom — ${customDate!.isoDate}'
      : preset!.label;

  @override
  bool operator ==(Object other) =>
      other is LoanTerm &&
      other.preset == preset &&
      other.customDate == customDate;

  @override
  int get hashCode => Object.hash(preset, customDate);

  @override
  String toString() => 'LoanTerm($displayLabel)';
}

/// Computes the *preliminary* due date of a loan agreement
/// (Story 4.2, PRD FR-17).
///
/// A preliminary due date is explicitly tentative: the official calendar due
/// date is only finalised upon confirmed cash disbursement (Story 4.3,
/// PRD FR-19). All arithmetic is performed in the shop's operational time
/// zone, at calendar-date granularity, so that "30 days" always means the
/// 30th calendar day regardless of daylight-saving transitions.
class PreliminaryDueDateCalculator {
  /// The shop's operational time zone.
  final ShopTimeZone shopTimeZone;

  const PreliminaryDueDateCalculator({required this.shopTimeZone});

  /// The local calendar date on which the agreement is created.
  LocalCalendarDate creationDate(DateTime createdAt) =>
      shopTimeZone.localDateOf(createdAt);

  /// The preliminary due date for a standard duration [preset].
  ///
  /// Agreement creation date + preset calendar days, in the shop's time zone.
  DateTime preliminaryDueDateForPreset(
    DateTime createdAt,
    LoanTermPreset preset,
  ) {
    final target = creationDate(createdAt).addDays(preset.calendarDays);
    return shopTimeZone.instantAtStartOfDay(target);
  }

  /// The preliminary due date for a custom calendar date.
  ///
  /// Throws [LoanTermValidationException] when [customDate] is not strictly
  /// after the agreement creation date.
  DateTime preliminaryDueDateForCustom(
    DateTime createdAt,
    LocalCalendarDate customDate,
  ) {
    validateCustomDate(createdAt, customDate);
    return shopTimeZone.instantAtStartOfDay(customDate);
  }

  /// The preliminary due date for a selected [term].
  DateTime preliminaryDueDateFor(DateTime createdAt, LoanTerm term) {
    if (term.isCustom) {
      return preliminaryDueDateForCustom(createdAt, term.customDate!);
    }
    return preliminaryDueDateForPreset(createdAt, term.preset!);
  }

  /// Enforces `Custom Due Date > Agreement Creation Date` (PRD FR-17).
  ///
  /// The comparison is made at *calendar-date* granularity in the shop's time
  /// zone, so a same-day selection is rejected alongside past dates.
  void validateCustomDate(
    DateTime createdAt,
    LocalCalendarDate customDate,
  ) {
    final creation = creationDate(createdAt);
    if (!customDate.isAfter(creation)) {
      throw LoanTermValidationException(
        'Custom Due Date must be strictly after the Agreement Creation Date '
        '($creation.isoDate). Selected: ${customDate.isoDate}.',
      );
    }
  }

  /// Whether [customDate] would pass [validateCustomDate].
  bool isCustomDateValid(DateTime createdAt, LocalCalendarDate customDate) {
    try {
      validateCustomDate(createdAt, customDate);
      return true;
    } on LoanTermValidationException {
      return false;
    }
  }
}

/// Computes the **official** calendar due date at cash disbursement
/// (Story 4.3, PRD FR-19).
///
/// The official due date is finalised from the **agreed term** and the
/// **confirmed disbursement date** — never from the preliminary due date that
/// was stored at origination:
///
/// - **Preset term (30/60/90 days):**
///   `Official Due Date = Disbursement Date (shop local) + N calendar days`.
/// - **Custom term:** the agreed custom calendar date is confirmed and saved,
///   but only when it is *strictly after* the disbursement date in the shop's
///   local time. When the disbursement was delayed past the agreed date the
///   confirmation is **blocked** and staff must select a valid future date.
class OfficialDueDateCalculator {
  /// The shop's operational time zone.
  final ShopTimeZone shopTimeZone;

  const OfficialDueDateCalculator({required this.shopTimeZone});

  /// The shop-local calendar date on which the cash was handed over.
  LocalCalendarDate disbursementDate(DateTime disbursedAt) =>
      shopTimeZone.localDateOf(disbursedAt);

  /// The official due date for an agreed preset term of [termPresetDays]
  /// calendar days.
  DateTime officialDueDateForPreset(
    DateTime disbursedAt,
    int termPresetDays,
  ) {
    final target = disbursementDate(disbursedAt).addDays(termPresetDays);
    return shopTimeZone.instantAtStartOfDay(target);
  }

  /// The official due date for an agreed custom calendar date.
  ///
  /// Throws [OfficialDueDateValidationException] when the custom date is not
  /// strictly after the disbursement date in the shop's local time.
  DateTime officialDueDateForCustom(
    DateTime disbursedAt,
    LocalCalendarDate customDate,
  ) {
    validateCustomDateAgainstDisbursement(disbursedAt, customDate);
    return shopTimeZone.instantAtStartOfDay(customDate);
  }

  /// The official due date for a loan's agreed term.
  ///
  /// Exactly one of [termPresetDays] and [customDueDate] must be present.
  DateTime officialDueDate({
    required DateTime disbursedAt,
    required int? termPresetDays,
    required LocalCalendarDate? customDueDate,
  }) {
    if (termPresetDays != null) {
      return officialDueDateForPreset(disbursedAt, termPresetDays);
    }
    if (customDueDate != null) {
      return officialDueDateForCustom(disbursedAt, customDueDate);
    }
    throw const AgreedTermNotRecordedException(
      'No recorded agreed term for this agreement, so the official calendar '
      'due date cannot be calculated and the cash disbursement cannot be '
      'confirmed. A term must be agreed and recorded on the agreement before '
      'the cash can be disbursed.',
    );
  }

  /// Enforces `Custom Due Date > Disbursement Date (in Shop Local Time)`
  /// (PRD FR-19).
  ///
  /// The comparison is made at calendar-date granularity in the shop's time
  /// zone, so a same-day disbursement against a same-day agreed due date is
  /// refused.
  void validateCustomDateAgainstDisbursement(
    DateTime disbursedAt,
    LocalCalendarDate customDate,
  ) {
    final disbursed = disbursementDate(disbursedAt);
    if (!customDate.isAfter(disbursed)) {
      throw OfficialDueDateValidationException(
        'The agreed custom due date (${customDate.isoDate}) must be strictly '
        'after the disbursement date (${disbursed.isoDate}) in the shop time '
        'zone. Select a valid future date before confirming the disbursement.',
      );
    }
  }
}
