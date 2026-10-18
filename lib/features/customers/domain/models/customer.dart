import 'package:meta/meta.dart';

/// Validation exception thrown when customer profile invariants are violated.
class CustomerValidationException extends ArgumentError {
  CustomerValidationException(super.message);
}

/// Thrown when a customer with the same NIC already exists in the active shop.
/// Carries the existing profile so the UI can offer to open it instead of creating a duplicate.
class DuplicateNicException implements Exception {
  final Customer existingCustomer;
  final String message;
  DuplicateNicException(this.existingCustomer, {required this.message});
}

/// Thrown when a phone number is shared with existing customer(s) in the shop
/// and explicit staff confirmation has not yet been provided.
/// A shared phone never automatically means the same person.
class SharedPhoneDuplicateException implements Exception {
  final List<Customer> existingCustomers;
  final String sharedPhone;
  final String message;
  SharedPhoneDuplicateException(
    this.existingCustomers,
    this.sharedPhone, {
    required this.message,
  });
}

/// Clean architecture domain entity representing a borrower customer profile (Story 2.1).
@immutable
class Customer {
  /// Canonical UUID primary key.
  final String id;

  /// Associated shop tenant boundary.
  final String shopId;

  /// Full legal name of the customer.
  final String fullName;

  /// Normalized National Identity Card (NIC) number (uppercase, trimmed).
  final String nic;

  /// Contact phone number.
  final String phone;

  /// Residential address.
  final String address;

  /// Optional relative path or URI to the customer's KYC photograph.
  final String? photoUri;

  /// Optional SHA-256 checksum of the customer's KYC photograph.
  final String? photoHash;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC last-update timestamp.
  final DateTime updatedAt;

  Customer({
    required this.id,
    required this.shopId,
    required this.fullName,
    required String nic,
    required this.phone,
    required this.address,
    this.photoUri,
    this.photoHash,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : nic = normalizeNic(nic),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc() {
    _validate();
  }

  /// Normalizes an NIC string by trimming whitespace and converting to uppercase.
  static String normalizeNic(String raw) => raw.trim().toUpperCase();

  /// Normalizes a Sri Lankan phone number to local display format for comparison.
  ///
  /// Equivalent formats resolve to the same value:
  /// - `0771234567` → `0771234567`
  /// - `+94771234567` → `0771234567`
  /// - `077 123 4567` → `0771234567`
  /// - `+94 77 123 4567` → `0771234567`
  ///
  /// The original display value is preserved by the caller; this only produces
  /// a comparable normalized form. Throws [ArgumentError] for empty input.
  static String normalizePhone(String raw) {
    if (raw.trim().isEmpty) {
      throw ArgumentError.value(raw, 'phone', 'Phone number cannot be empty.');
    }

    final digits = raw.trim().replaceAll(RegExp(r'[\s\-\(\)\.]+'), '');

    // International format: +94 77 XXX XXXX → 077 XXX XXXX
    if (digits.startsWith('+94')) {
      return '0${digits.substring(3)}';
    }

    // International format with double zero: 0094 77 XXX XXXX → 077 XXX XXXX
    if (digits.startsWith('0094')) {
      return '0${digits.substring(4)}';
    }

    return digits;
  }

  /// Validates a Sri Lankan phone number after normalization.
  ///
  /// Accepts mobile numbers (`07X XXX XXXX`, 10 digits) and landline numbers
  /// (`0XX XXX XXX` to `0XXXX XXXXX`, 9–10 digits). Does not guess at ambiguous
  /// inputs; returns `false` for anything that does not match a known pattern.
  static bool isValidPhoneFormat(String phone) {
    try {
      final normalized = normalizePhone(phone);
      // Mobile: 07X followed by 8 digits (10 digits total).
      final mobilePattern = RegExp(r'^07[0-9]{8}$');
      // Landline: area code 01–06 or 08–09 (excludes 07 mobile prefix),
      // followed by 7–8 digits (9–10 digits total).
      final landlinePattern = RegExp(r'^0[1-689][0-9]{7,8}$');
      return mobilePattern.hasMatch(normalized) ||
          landlinePattern.hasMatch(normalized);
    } on ArgumentError {
      return false;
    }
  }

  /// Validates Sri Lankan National Identity Card (NIC) format.
  ///
  /// Supports:
  /// - Old format: 9 digits followed by 'V' or 'X' (e.g., 901234567V, 901234567X)
  /// - New format: 12 numeric digits (e.g., 199012345678)
  static bool isValidNicFormat(String nic) {
    final normalized = normalizeNic(nic);
    final oldFormatRegex = RegExp(r'^[0-9]{9}[VX]$');
    final newFormatRegex = RegExp(r'^[0-9]{12}$');
    return oldFormatRegex.hasMatch(normalized) || newFormatRegex.hasMatch(normalized);
  }

  void _validate() {
    if (id.trim().isEmpty) {
      throw CustomerValidationException('Customer ID cannot be empty');
    }
    if (shopId.trim().isEmpty) {
      throw CustomerValidationException('Shop ID cannot be empty');
    }
    if (fullName.trim().isEmpty) {
      throw CustomerValidationException('Customer full name cannot be empty');
    }
    if (fullName.length > 255) {
      throw CustomerValidationException('Customer full name cannot exceed 255 characters');
    }
    if (nic.isEmpty) {
      throw CustomerValidationException('Customer NIC cannot be empty');
    }
    if (!isValidNicFormat(nic)) {
      throw CustomerValidationException(
        'Invalid NIC format: "$nic". Must be 9 digits followed by V/X or 12 numeric digits.',
      );
    }
    if (phone.trim().isEmpty) {
      throw CustomerValidationException('Customer phone number cannot be empty');
    }
    if (phone.length > 50) {
      throw CustomerValidationException('Customer phone number cannot exceed 50 characters');
    }
    if (address.trim().isEmpty) {
      throw CustomerValidationException('Customer residential address cannot be empty');
    }
  }

  /// Returns a copy of this [Customer] with the given fields replaced.
  Customer copyWith({
    String? id,
    String? shopId,
    String? fullName,
    String? nic,
    String? phone,
    String? address,
    String? photoUri,
    String? photoHash,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      fullName: fullName ?? this.fullName,
      nic: nic ?? this.nic,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      photoUri: photoUri ?? this.photoUri,
      photoHash: photoHash ?? this.photoHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Customer &&
        other.id == id &&
        other.shopId == shopId &&
        other.fullName == fullName &&
        other.nic == nic &&
        other.phone == phone &&
        other.address == address &&
        other.photoUri == photoUri &&
        other.photoHash == photoHash;
  }

  @override
  int get hashCode => Object.hash(
        id,
        shopId,
        fullName,
        nic,
        phone,
        address,
        photoUri,
        photoHash,
      );
}
