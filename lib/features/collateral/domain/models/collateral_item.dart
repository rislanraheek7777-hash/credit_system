import 'package:meta/meta.dart';

import 'package:credit_system/core/money/money.dart';

/// Validation exception thrown when collateral item invariants are violated.
class CollateralItemValidationException extends ArgumentError {
  CollateralItemValidationException(super.message);
}

/// Exception thrown when an illegal custody state transition is attempted.
class CollateralCustodyTransitionException implements Exception {
  final String from;
  final String to;
  final String reason;

  const CollateralCustodyTransitionException(
    this.from,
    this.to, {
    this.reason = '',
  });

  @override
  String toString() =>
      'CollateralCustodyTransitionException: Cannot transition custody from "$from" to "$to". $reason';
}

/// Collateral item category (FR-14).
enum CollateralItemCategory {
  gold('gold'),
  electronics('electronics'),
  valuables('valuables');

  final String value;
  const CollateralItemCategory(this.value);

  /// Resolves [CollateralItemCategory] from raw database text.
  static CollateralItemCategory fromValue(String value) {
    for (final category in CollateralItemCategory.values) {
      if (category.value == value) {
        return category;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid collateral category');
  }
}

/// Collateral item custody state (FR-16).
///
/// Valid transitions:
///   `inCustody` → `handoverRequested` (staff requests return)
///   `inCustody` → `discrepancy` (staff reports discrepancy)
///   `inCustody` → `exceptionHeld` (Shop Owner places on exception hold)
///   `handoverRequested` → `handoverReported` (staff confirms physical handover)
///   `handoverRequested` → `inCustody` (staff cancels request)
///   `handoverReported` → `returned` (owner confirms return)
///   `handoverReported` → `inCustody` (owner rejects handover)
///   `handoverReported` → `exceptionHeld` (Shop Owner places on exception hold)
///   `discrepancy` → `returned` (owner resolves and confirms return)
///   `discrepancy` → `inCustody` (owner resolves, item stays)
///   `discrepancy` → `exceptionHeld` (owner decides to hold)
///
/// Invalid transitions throw [CollateralCustodyTransitionException].
enum CollateralCustodyStatus {
  inCustody('in_custody'),
  handoverRequested('handover_requested'),
  handoverReported('handover_reported'),
  returned('returned'),
  exceptionHeld('exception_held'),
  discrepancy('discrepancy');

  final String value;
  const CollateralCustodyStatus(this.value);

  /// Resolves [CollateralCustodyStatus] from raw database text.
  static CollateralCustodyStatus fromValue(String value) {
    for (final status in CollateralCustodyStatus.values) {
      if (status.value == value) {
        return status;
      }
    }
    throw ArgumentError.value(value, 'value', 'Invalid collateral custody status');
  }

  /// Whether this is a terminal state (no further transitions allowed).
  bool get isTerminal =>
      this == returned || this == exceptionHeld;

  /// Whether a transition from [current] to [target] is valid.
  static bool isValidTransition(CollateralCustodyStatus current, CollateralCustodyStatus target) {
    if (current.isTerminal) {
      return false; // Terminal states cannot transition further
    }
    if (current == inCustody) {
      return target == handoverRequested || target == discrepancy || target == exceptionHeld;
    }
    if (current == handoverRequested) {
      return target == handoverReported || target == inCustody;
    }
    if (current == handoverReported) {
      return target == returned || target == inCustody || target == exceptionHeld;
    }
    if (current == discrepancy) {
      return target == returned || target == inCustody || target == exceptionHeld;
    }
    return false;
  }
}

/// Clean architecture domain entity representing a pledged collateral item (Story 3.1).
///
/// Money (estimated value) is stored in integer minor units (cents) — never as
/// floating point. Weight is stored as integer milligrams — never as Dart `double`.
///
/// Binds:
/// - FR-13: Multi-item collateral registration per credit
/// - FR-14: Decimal weight calibration without floating point
/// - FR-16: Independent per-item custody tracking
/// - AD-2: Integer minor units / weight precision
/// - AD-3: Custody state machine
@immutable
class CollateralItem {
  /// Canonical UUIDv4 primary key.
  final String id;

  /// Associated shop tenant UUID boundary.
  final String shopId;

  /// Associated customer borrower (database-assigned integer id).
  final int customerId;

  /// Optional associated credit UUID (nullable until Epic 4 enforces binding).
  final String? creditId;

  /// Unique item reference within the shop (e.g., "COLL-001").
  final String itemReferenceId;

  /// Item category.
  final CollateralItemCategory category;

  /// Human-readable description.
  final String description;

  /// Condition grade.
  final String conditionGrade;

  /// Weight in integer milligrams (e.g., 5.5 g → 5500 mg).
  final int weightMilligrams;

  /// Estimated collateral value in integer minor units (cents).
  final int estimatedValueCents;

  /// Optional local file URI or sandboxed path to the item photograph.
  final String? photoUri;

  /// Optional SHA-256 hash of the item photograph.
  final String? photoHash;

  /// Custody state.
  final CollateralCustodyStatus custodyStatus;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC last-update timestamp.
  final DateTime updatedAt;

  CollateralItem({
    required this.id,
    required this.shopId,
    required this.customerId,
    this.creditId,
    required this.itemReferenceId,
    required this.category,
    required this.description,
    required this.conditionGrade,
    required this.weightMilligrams,
    required this.estimatedValueCents,
    this.photoUri,
    this.photoHash,
    this.custodyStatus = CollateralCustodyStatus.inCustody,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc() {
    _validateWeightAndValue();
    _validate();
  }

  void _validateWeightAndValue() {
    if (weightMilligrams <= 0) {
      throw CollateralItemValidationException(
        'Weight must be positive (milligrams)',
      );
    }
    if (estimatedValueCents < 0) {
      throw CollateralItemValidationException('Estimated value cannot be negative');
    }
  }

  /// Returns the estimated value as a [Money] instance.
  Money get estimatedValue => Money.fromCents(estimatedValueCents);

  /// Parses a decimal gram string (e.g., "5.5") into integer milligrams (5500).
  ///
  /// Supports up to 3 decimal places in grams (e.g., "5.555" → 5555 mg).
  /// Rejects non-numeric input and negative values.
  /// Throws [CollateralItemValidationException] for invalid input.
  static int parseWeightGrams(String grams) {
    final trimmed = grams.trim();
    if (trimmed.isEmpty) {
      throw CollateralItemValidationException('Weight cannot be empty');
    }

    bool isNegative = false;
    String cleanStr = trimmed;

    if (cleanStr.startsWith('-')) {
      isNegative = true;
      cleanStr = cleanStr.substring(1).trim();
    }

    if (cleanStr.isEmpty) {
      throw CollateralItemValidationException(
        'Weight contains only a sign without digits',
      );
    }

    final parts = cleanStr.split('.');
    if (parts.length > 2) {
      throw CollateralItemValidationException(
        'Weight contains multiple decimal points: "$grams"',
      );
    }

    final String integerStr = parts[0];
    final String? decimalStr = parts.length == 2 ? parts[1] : null;

    // Validate integer part is all digits
    if (integerStr.isNotEmpty && !RegExp(r'^\d+$').hasMatch(integerStr)) {
      throw CollateralItemValidationException(
        'Weight integer part contains non-digit characters: "$grams"',
      );
    }

    // Validate decimal part is all digits (max 3 places for milligram precision)
    int milliCents = 0;
    if (decimalStr != null) {
      if (decimalStr.isEmpty) {
        throw CollateralItemValidationException(
          'Weight cannot have a trailing decimal point without digits: "$grams"',
        );
      }
      if (decimalStr.length > 3) {
        throw CollateralItemValidationException(
          'Weight cannot have more than 3 decimal places: "$grams"',
        );
      }
      if (!RegExp(r'^\d+$').hasMatch(decimalStr)) {
        throw CollateralItemValidationException(
          'Weight decimal part contains non-digit characters: "$grams"',
        );
      }

      // Pad to 3 decimal places (milligrams)
      final padded = decimalStr.padRight(3, '0');
      milliCents = int.parse(padded);
    }

    int major = 0;
    if (integerStr.isNotEmpty) {
      major = int.parse(integerStr);
    } else if (decimalStr == null) {
      throw CollateralItemValidationException(
        'No numeric digits found in weight',
      );
    }

    final totalMg = major * 1000 + milliCents;
    final signedMg = isNegative ? -totalMg : totalMg;

    if (signedMg <= 0) {
      throw CollateralItemValidationException('Weight must be positive');
    }

    return signedMg;
  }

  /// Formats integer milligrams into a decimal gram string (e.g., 5500 → "5.500 g").
  static String formatWeightMilligrams(int milligrams) {
    final absMg = milligrams.abs();
    final sign = milligrams < 0 ? '-' : '';
    final grams = absMg / 1000;
    return '$sign${grams.toStringAsFixed(3)} g';
  }

  void _validate() {
    if (id.trim().isEmpty) {
      throw CollateralItemValidationException('Collateral item ID cannot be empty');
    }
    if (shopId.trim().isEmpty) {
      throw CollateralItemValidationException('Shop ID cannot be empty');
    }
    if (customerId <= 0) {
      throw CollateralItemValidationException('Customer ID must be a positive integer');
    }
    if (itemReferenceId.trim().isEmpty) {
      throw CollateralItemValidationException('Item reference ID cannot be empty');
    }
    if (description.trim().isEmpty) {
      throw CollateralItemValidationException('Description cannot be empty');
    }
    if (conditionGrade.trim().isEmpty) {
      throw CollateralItemValidationException('Condition grade cannot be empty');
    }
    if (estimatedValueCents < 0) {
      throw CollateralItemValidationException('Estimated value cannot be negative');
    }
  }

  /// Transitions custody to [newStatus]. Throws [CollateralCustodyTransitionException]
  /// if the transition is invalid.
  CollateralItem transitionCustody(CollateralCustodyStatus newStatus) {
    if (!CollateralCustodyStatus.isValidTransition(custodyStatus, newStatus)) {
      throw CollateralCustodyTransitionException(
        custodyStatus.value,
        newStatus.value,
        reason: 'Invalid custody state transition',
      );
    }
    return copyWith(custodyStatus: newStatus, updatedAt: DateTime.now().toUtc());
  }

  /// Returns a copy of this [CollateralItem] with the given fields replaced.
  CollateralItem copyWith({
    String? id,
    String? shopId,
    int? customerId,
    String? creditId,
    String? itemReferenceId,
    CollateralItemCategory? category,
    String? description,
    String? conditionGrade,
    int? weightMilligrams,
    int? estimatedValueCents,
    String? photoUri,
    String? photoHash,
    CollateralCustodyStatus? custodyStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CollateralItem(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      customerId: customerId ?? this.customerId,
      creditId: creditId ?? this.creditId,
      itemReferenceId: itemReferenceId ?? this.itemReferenceId,
      category: category ?? this.category,
      description: description ?? this.description,
      conditionGrade: conditionGrade ?? this.conditionGrade,
      weightMilligrams: weightMilligrams ?? this.weightMilligrams,
      estimatedValueCents: estimatedValueCents ?? this.estimatedValueCents,
      photoUri: photoUri ?? this.photoUri,
      photoHash: photoHash ?? this.photoHash,
      custodyStatus: custodyStatus ?? this.custodyStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CollateralItem &&
        other.id == id &&
        other.shopId == shopId &&
        other.customerId == customerId &&
        other.creditId == creditId &&
        other.itemReferenceId == itemReferenceId &&
        other.category == category &&
        other.description == description &&
        other.conditionGrade == conditionGrade &&
        other.weightMilligrams == weightMilligrams &&
        other.estimatedValueCents == estimatedValueCents &&
        other.photoUri == photoUri &&
        other.photoHash == photoHash &&
        other.custodyStatus == custodyStatus;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        customerId,
        creditId,
        itemReferenceId,
        category,
        description,
        conditionGrade,
        weightMilligrams,
        estimatedValueCents,
        photoUri,
        photoHash,
        custodyStatus,
      );

  @override
  String toString() {
    return 'CollateralItem(id: $id, ref: $itemReferenceId, category: ${category.value}, '
        'weight: ${formatWeightMilligrams(weightMilligrams)}, '
        'value: $estimatedValueCents cents, custody: ${custodyStatus.value})';
  }
}


