// Shared masking helpers for customer identity data (Story 2.5).
//
// Used by the customer search and profile screens to mask sensitive fields
// when the viewer does not possess [viewSensitiveCustomerData].
//
// Masking rules:
// - NIC: show first 4 and last 4 characters, mask the middle with `****`.
//   Example: `198512345678` → `1985****5678`; `851234567V` → `8512****567V`.
// - Phone: show country code, area prefix, and last 3 digits.
//   Example: `+94771234567` → `+94 77 **** 123`; `0771234567` → `077 **** 123`.
// - Address: omitted entirely (shown as `Address withheld`).

/// Masks a NIC for display.
///
/// Short NICs (<= 8 chars) are returned unchanged.
String maskNic(String nic) {
  if (nic.length <= 8) return nic;
  return '${nic.substring(0, 4)}****${nic.substring(nic.length - 4)}';
}

/// Masks a Sri Lankan phone number for display.
///
/// Normalizes the input first, then masks the middle digits.
/// Examples:
///   `+94771234567` → `+94 77 **** 123`
///   `0771234567`   → `077 **** 123`
///   `+94 77 123 4567` → `+94 77 **** 123`
String maskPhone(String phone) {
  final normalized = _normalizePhoneDigits(phone);
  if (normalized.length <= 6) return normalized;

  // International format: +94 XX **** XX
  if (normalized.startsWith('+94')) {
    final rest = normalized.substring(3);
    if (rest.length >= 5) {
      return '+94 ${rest.substring(0, 2)} **** ${rest.substring(rest.length - 3)}';
    }
    return '+94 ${rest.substring(0, min(2, rest.length))} ****';
  }

  // Local format: XX **** XX
  if (normalized.length >= 6) {
    return '${normalized.substring(0, 3)} **** ${normalized.substring(normalized.length - 3)}';
  }

  return normalized;
}

/// Returns `Address withheld` when the address should not be displayed.
const String kAddressWithheld = 'Address withheld';

int min(int a, int b) => a < b ? a : b;

/// Strips formatting characters from a phone number, keeping only digits
/// and a leading `+`.
String _normalizePhoneDigits(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('+')) {
    return '+${trimmed.substring(1).replaceAll(RegExp(r'[^\d]'), '')}';
  }
  return trimmed.replaceAll(RegExp(r'[^\d]'), '');
}
