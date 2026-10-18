import 'package:meta/meta.dart';

/// Validation exception thrown when shop profile properties violate domain rules.
class ShopProfileValidationException implements Exception {
  final String message;
  const ShopProfileValidationException(this.message);

  @override
  String toString() => 'ShopProfileValidationException: $message';
}

/// Domain entity representing a shop profile and configuration in Story 1.6.
@immutable
class ShopProfile {
  /// Unique identifier of the shop.
  final String id;

  /// Business trading name.
  final String name;

  /// Primary operating currency code (ISO 4217, 3 uppercase characters, default 'LKR').
  final String currencyCode;

  /// Operational IANA timezone identifier (default 'Asia/Colombo').
  final String timezone;

  /// Physical or business street address.
  final String? businessAddress;

  /// Contact phone number.
  final String? contactPhone;

  /// Contact email.
  final String? contactEmail;

  /// Registration or tax identification number.
  final String? registrationNumber;

  /// URI or path to shop logo image.
  final String? logoUri;

  /// Receipt header notes.
  final String? receiptHeaderNotes;

  /// Receipt footer notes.
  final String? receiptFooterNotes;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  final DateTime updatedAt;

  ShopProfile({
    required this.id,
    required this.name,
    this.currencyCode = 'LKR',
    this.timezone = 'Asia/Colombo',
    this.businessAddress,
    this.contactPhone,
    this.contactEmail,
    this.registrationNumber,
    this.logoUri,
    this.receiptHeaderNotes,
    this.receiptFooterNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc() {
    _validate();
  }

  /// Validates shop profile invariants.
  void _validate() {
    if (id.trim().isEmpty) {
      throw const ShopProfileValidationException('Shop ID cannot be empty');
    }
    if (name.trim().isEmpty) {
      throw const ShopProfileValidationException('Shop name cannot be empty');
    }
    if (name.length > 255) {
      throw const ShopProfileValidationException('Shop name cannot exceed 255 characters');
    }
    if (currencyCode.length != 3 || currencyCode != currencyCode.toUpperCase()) {
      throw const ShopProfileValidationException(
        'Currency code must be an uppercase 3-letter ISO 4217 code (e.g. LKR)',
      );
    }
    if (!isValidIanaTimezone(timezone)) {
      throw ShopProfileValidationException(
        'Invalid IANA timezone identifier: "$timezone"',
      );
    }
    if (contactEmail != null && contactEmail!.trim().isNotEmpty) {
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailRegex.hasMatch(contactEmail!.trim())) {
        throw ShopProfileValidationException(
          'Invalid email address format: "$contactEmail"',
        );
      }
    }
  }

  /// Structural and semantic validation for IANA Timezone identifiers.
  ///
  /// Conforms to IANA standard timezone formats:
  /// - Area/Location (e.g., 'Asia/Colombo', 'America/New_York', 'Europe/London')
  /// - 3-level locations (e.g., 'America/Argentina/Buenos_Aires', 'America/Indiana/Indianapolis')
  /// - Standard special names: 'UTC', 'GMT', 'Etc/UTC', 'Etc/GMT[+-]...'
  static bool isValidIanaTimezone(String tz) {
    final trimmed = tz.trim();
    if (trimmed.isEmpty) return false;

    // Special top-level UTC/GMT designations
    if (trimmed == 'UTC' || trimmed == 'GMT') return true;

    // Standard IANA format: Area/Location or Area/Subarea/Location
    // Valid areas include Africa, America, Antarctica, Arctic, Asia, Atlantic, Australia, Europe, Indian, Pacific, Etc
    final ianaRegex = RegExp(
      r'^(Africa|America|Antarctica|Arctic|Asia|Atlantic|Australia|Europe|Indian|Pacific|Etc)/[a-zA-Z0-9_\-\+]+(/[a-zA-Z0-9_\-\+]+)?$',
    );

    return ianaRegex.hasMatch(trimmed);
  }

  /// Returns a copy of this [ShopProfile] with the given fields replaced.
  ShopProfile copyWith({
    String? id,
    String? name,
    String? currencyCode,
    String? timezone,
    String? businessAddress,
    String? contactPhone,
    String? contactEmail,
    String? registrationNumber,
    String? logoUri,
    String? receiptHeaderNotes,
    String? receiptFooterNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShopProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      currencyCode: currencyCode ?? this.currencyCode,
      timezone: timezone ?? this.timezone,
      businessAddress: businessAddress ?? this.businessAddress,
      contactPhone: contactPhone ?? this.contactPhone,
      contactEmail: contactEmail ?? this.contactEmail,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      logoUri: logoUri ?? this.logoUri,
      receiptHeaderNotes: receiptHeaderNotes ?? this.receiptHeaderNotes,
      receiptFooterNotes: receiptFooterNotes ?? this.receiptFooterNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShopProfile &&
        other.id == id &&
        other.name == name &&
        other.currencyCode == currencyCode &&
        other.timezone == timezone &&
        other.businessAddress == businessAddress &&
        other.contactPhone == contactPhone &&
        other.contactEmail == contactEmail &&
        other.registrationNumber == registrationNumber &&
        other.logoUri == logoUri &&
        other.receiptHeaderNotes == receiptHeaderNotes &&
        other.receiptFooterNotes == receiptFooterNotes;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        currencyCode,
        timezone,
        businessAddress,
        contactPhone,
        contactEmail,
        registrationNumber,
        logoUri,
        receiptHeaderNotes,
        receiptFooterNotes,
      );
}
