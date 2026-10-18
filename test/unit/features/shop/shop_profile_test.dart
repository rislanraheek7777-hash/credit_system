import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/money/money.dart';
import 'package:credit_system/features/shop/domain/models/shop_profile.dart';

void main() {
  group('ShopProfile Domain Model & Validation Tests (Story 1.6)', () {
    test('creates valid ShopProfile with defaults (LKR and Asia/Colombo)', () {
      final profile = ShopProfile(
        id: 'shop-uuid-001',
        name: 'Perera Jewellers Colombo',
      );

      expect(profile.id, equals('shop-uuid-001'));
      expect(profile.name, equals('Perera Jewellers Colombo'));
      expect(profile.currencyCode, equals('LKR'));
      expect(profile.timezone, equals('Asia/Colombo'));
      expect(profile.businessAddress, isNull);
      expect(profile.contactPhone, isNull);
      expect(profile.contactEmail, isNull);
      expect(profile.registrationNumber, isNull);
      expect(profile.logoUri, isNull);
      expect(profile.receiptHeaderNotes, isNull);
      expect(profile.receiptFooterNotes, isNull);
    });

    test('creates full ShopProfile with all 7 profile & receipt branding fields', () {
      final now = DateTime.now().toUtc();
      final profile = ShopProfile(
        id: 'shop-uuid-002',
        name: 'City Credit & Pawn Mart',
        currencyCode: 'LKR',
        timezone: 'Asia/Colombo',
        businessAddress: '123 Galle Road, Colombo 03, Sri Lanka',
        contactPhone: '+94 11 234 5678',
        contactEmail: 'info@citycredit.lk',
        registrationNumber: 'PV-123456',
        logoUri: '/data/user/0/com.credit_system/app_flutter/logos/shop_logo.png',
        receiptHeaderNotes: 'Authorized Licensed Pawnbroker under Central Bank Guidelines',
        receiptFooterNotes: 'Gold redemption strictly within 90 days. Thank you for your business.',
        createdAt: now,
        updatedAt: now,
      );

      expect(profile.businessAddress, equals('123 Galle Road, Colombo 03, Sri Lanka'));
      expect(profile.contactPhone, equals('+94 11 234 5678'));
      expect(profile.contactEmail, equals('info@citycredit.lk'));
      expect(profile.registrationNumber, equals('PV-123456'));
      expect(profile.logoUri, contains('shop_logo.png'));
      expect(profile.receiptHeaderNotes, contains('Licensed Pawnbroker'));
      expect(profile.receiptFooterNotes, contains('90 days'));
    });

    test('rejects empty id or empty name', () {
      expect(
        () => ShopProfile(id: '', name: 'Valid Name'),
        throwsA(isA<ShopProfileValidationException>().having(
          (e) => e.message,
          'message',
          contains('Shop ID cannot be empty'),
        )),
      );

      expect(
        () => ShopProfile(id: 'uuid-1', name: '   '),
        throwsA(isA<ShopProfileValidationException>().having(
          (e) => e.message,
          'message',
          contains('Shop name cannot be empty'),
        )),
      );
    });

    test('rejects name exceeding 255 characters', () {
      final longName = 'A' * 256;
      expect(
        () => ShopProfile(id: 'uuid-1', name: longName),
        throwsA(isA<ShopProfileValidationException>().having(
          (e) => e.message,
          'message',
          contains('cannot exceed 255 characters'),
        )),
      );
    });

    test('rejects invalid currency code (must be uppercase 3 letters)', () {
      expect(
        () => ShopProfile(id: 'uuid-1', name: 'Shop', currencyCode: 'lkr'),
        throwsA(isA<ShopProfileValidationException>().having(
          (e) => e.message,
          'message',
          contains('uppercase 3-letter ISO 4217 code'),
        )),
      );

      expect(
        () => ShopProfile(id: 'uuid-1', name: 'Shop', currencyCode: 'LK'),
        throwsA(isA<ShopProfileValidationException>().having(
          (e) => e.message,
          'message',
          contains('uppercase 3-letter ISO 4217 code'),
        )),
      );
    });

    group('IANA Timezone Validation (Standard structural validation)', () {
      test('accepts valid IANA timezones across global regions', () {
        expect(ShopProfile.isValidIanaTimezone('Asia/Colombo'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('Asia/Kolkata'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('America/New_York'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('Europe/London'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('Australia/Sydney'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('Africa/Johannesburg'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('Pacific/Auckland'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('UTC'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('GMT'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('America/Argentina/Buenos_Aires'), isTrue);
        expect(ShopProfile.isValidIanaTimezone('America/Indiana/Indianapolis'), isTrue);
      });

      test('rejects invalid IANA timezone identifiers', () {
        expect(ShopProfile.isValidIanaTimezone(''), isFalse);
        expect(ShopProfile.isValidIanaTimezone('   '), isFalse);
        expect(ShopProfile.isValidIanaTimezone('InvalidCity'), isFalse);
        expect(ShopProfile.isValidIanaTimezone('Colombo'), isFalse);
        expect(ShopProfile.isValidIanaTimezone('Mars/Olympus'), isFalse);
        expect(ShopProfile.isValidIanaTimezone('Asia/'), isFalse);
        expect(ShopProfile.isValidIanaTimezone('/Colombo'), isFalse);
        expect(ShopProfile.isValidIanaTimezone('Asia/Colombo/Extra/TooManyLevels'), isFalse);
      });

      test('throws ShopProfileValidationException on invalid timezone', () {
        expect(
          () => ShopProfile(id: 'uuid-1', name: 'Shop', timezone: 'Colombo/InvalidRegion'),
          throwsA(isA<ShopProfileValidationException>().having(
            (e) => e.message,
            'message',
            contains('Invalid IANA timezone identifier'),
          )),
        );
      });
    });

    test('rejects invalid email format when provided', () {
      expect(
        () => ShopProfile(id: 'uuid-1', name: 'Shop', contactEmail: 'not-an-email'),
        throwsA(isA<ShopProfileValidationException>().having(
          (e) => e.message,
          'message',
          contains('Invalid email address format'),
        )),
      );
    });

    test('formats currency displays using integer-cents Money value object (no double)', () {
      final amount = Money.fromCents(150050, currency: 'LKR');
      expect(amount.format(), equals('Rs. 1,500.50'));

      final largeAmount = Money.fromCents(250000000, currency: 'LKR');
      expect(largeAmount.format(), equals('Rs. 2,500,000.00'));
    });
  });
}
