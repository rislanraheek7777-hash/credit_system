import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';

void main() {
  group('Customer Domain Model & NIC Validation', () {
    test('Customer.normalizeNic normalizes whitespace and lowercase suffixes', () {
      expect(Customer.normalizeNic(' 851234567v '), equals('851234567V'));
      expect(Customer.normalizeNic('915001234x\t'), equals('915001234X'));
      expect(Customer.normalizeNic('  198512345678  '), equals('198512345678'));
    });

    test('Customer.isValidNicFormat correctly identifies valid Sri Lankan NICs', () {
      // Old format: 9 digits + V or X (case-insensitive)
      expect(Customer.isValidNicFormat('851234567V'), isTrue);
      expect(Customer.isValidNicFormat('851234567v'), isTrue);
      expect(Customer.isValidNicFormat('915001234X'), isTrue);
      expect(Customer.isValidNicFormat('915001234x'), isTrue);

      // New format: exactly 12 digits
      expect(Customer.isValidNicFormat('198512345678'), isTrue);
      expect(Customer.isValidNicFormat('200112345678'), isTrue);

      // Whitespace around valid NIC should still be considered valid
      expect(Customer.isValidNicFormat(' 851234567V '), isTrue);
    });

    test('Customer.isValidNicFormat rejects invalid NIC formats', () {
      expect(Customer.isValidNicFormat(''), isFalse);
      expect(Customer.isValidNicFormat('   '), isFalse);
      expect(Customer.isValidNicFormat('12345678'), isFalse); // 8 digits
      expect(Customer.isValidNicFormat('123456789'), isFalse); // 9 digits without letter
      expect(Customer.isValidNicFormat('851234567A'), isFalse); // Invalid suffix letter
      expect(Customer.isValidNicFormat('85123A567V'), isFalse); // Letter in digit portion
      expect(Customer.isValidNicFormat('19851234567'), isFalse); // 11 digits
      expect(Customer.isValidNicFormat('1985123456789'), isFalse); // 13 digits
      expect(Customer.isValidNicFormat('19851234567V'), isFalse); // 11 digits + V
      expect(Customer.isValidNicFormat('NIC-851234567V'), isFalse); // Extra prefix
    });

    group('Customer phone normalization', () {
      test('Customer.normalizePhone converts local format to itself', () {
        expect(Customer.normalizePhone('0771234567'), equals('0771234567'));
        expect(Customer.normalizePhone('0712345678'), equals('0712345678'));
      });

      test('Customer.normalizePhone converts international +94 format to local', () {
        expect(Customer.normalizePhone('+94771234567'), equals('0771234567'));
        expect(Customer.normalizePhone('+94 77 123 4567'), equals('0771234567'));
        expect(Customer.normalizePhone('+94712345678'), equals('0712345678'));
      });

      test('Customer.normalizePhone converts international 0094 format to local', () {
        expect(Customer.normalizePhone('0094771234567'), equals('0771234567'));
        expect(Customer.normalizePhone('0094 77 123 4567'), equals('0771234567'));
      });

      test('Customer.normalizePhone strips whitespace and formatting', () {
        expect(Customer.normalizePhone('077 123 4567'), equals('0771234567'));
        expect(Customer.normalizePhone('077-123-4567'), equals('0771234567'));
        expect(Customer.normalizePhone('(077) 123 4567'), equals('0771234567'));
        expect(Customer.normalizePhone('  0771234567  '), equals('0771234567'));
      });

      test('Customer.normalizePhone treats equivalent formats as equal', () {
        final local = Customer.normalizePhone('0771234567');
        final international = Customer.normalizePhone('+94771234567');
        final spaced = Customer.normalizePhone('077 123 4567');
        expect(local, equals(international));
        expect(local, equals(spaced));
      });

      test('Customer.normalizePhone throws on empty input', () {
        expect(() => Customer.normalizePhone(''), throwsArgumentError);
        expect(() => Customer.normalizePhone('   '), throwsArgumentError);
      });

      test('Customer.isValidPhoneFormat accepts valid Sri Lankan mobile numbers', () {
        expect(Customer.isValidPhoneFormat('0771234567'), isTrue);
        expect(Customer.isValidPhoneFormat('+94771234567'), isTrue);
        expect(Customer.isValidPhoneFormat('077 123 4567'), isTrue);
        expect(Customer.isValidPhoneFormat('0712345678'), isTrue);
      });

      test('Customer.isValidPhoneFormat accepts valid Sri Lankan landline numbers', () {
        expect(Customer.isValidPhoneFormat('0112345678'), isTrue); // Colombo
        expect(Customer.isValidPhoneFormat('0812345678'), isTrue); // Kandy
        expect(Customer.isValidPhoneFormat('0912345678'), isTrue); // Galle
      });

      test('Customer.isValidPhoneFormat rejects invalid phone numbers', () {
        expect(Customer.isValidPhoneFormat(''), isFalse);
        expect(Customer.isValidPhoneFormat('   '), isFalse);
        expect(Customer.isValidPhoneFormat('12345'), isFalse); // Too short
        expect(Customer.isValidPhoneFormat('abcdefghij'), isFalse); // Non-numeric
        expect(Customer.isValidPhoneFormat('077123456'), isFalse); // 9 digits (mobile needs 10)
        expect(Customer.isValidPhoneFormat('07712345678'), isFalse); // 11 digits
        expect(Customer.isValidPhoneFormat('+1234567890'), isFalse); // Non-Sri Lankan country code
      });
    });

    test('Customer constructor normalizes NIC and enforces invariants', () {
      final now = DateTime.now().toUtc();
      final customer = Customer(
        id: 1,
        shopId: 'shop-1',
        fullName: 'Sunil Shantha',
        nic: ' 851234567v ',
        phone: '+94 77 123 4567',
        address: '12 Temple Road, Colombo 10',
        createdAt: now,
        updatedAt: now,
      );

      expect(customer.nic, equals('851234567V'));
      expect(customer.fullName, equals('Sunil Shantha'));
      expect(customer.phone, equals('+94 77 123 4567'));
      expect(customer.address, equals('12 Temple Road, Colombo 10'));
      expect(customer.photoUri, isNull);
      expect(customer.photoHash, isNull);
    });

    test('Customer constructor throws ArgumentError on invalid parameters', () {
      final now = DateTime.now().toUtc();

      // Negative ID (an empty id is not representable for an int)
      expect(
        () => Customer(
          id: -1,
          shopId: 'shop-1',
          fullName: 'Name',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty shopId
      expect(
        () => Customer(
          id: 1,
          shopId: '  ',
          fullName: 'Name',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty fullName
      expect(
        () => Customer(
          id: 1,
          shopId: 'shop-1',
          fullName: '   ',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Invalid NIC format
      expect(
        () => Customer(
          id: 1,
          shopId: 'shop-1',
          fullName: 'Name',
          nic: 'invalid-nic',
          phone: '+94 77 123 4567',
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty phone
      expect(
        () => Customer(
          id: 1,
          shopId: 'shop-1',
          fullName: 'Name',
          nic: '851234567V',
          phone: '   ',
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Empty address
      expect(
        () => Customer(
          id: 1,
          shopId: 'shop-1',
          fullName: 'Name',
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: '   ',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Full name exceeding 255 characters
      expect(
        () => Customer(
          id: 1,
          shopId: 'shop-1',
          fullName: 'A' * 256,
          nic: '851234567V',
          phone: '+94 77 123 4567',
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      // Phone exceeding 50 characters
      expect(
        () => Customer(
          id: 1,
          shopId: 'shop-1',
          fullName: 'Name',
          nic: '851234567V',
          phone: '+94 77 ${'1' * 45}', // 52 characters total
          address: 'Address',
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('Customer.copyWith returns updated instance and validates new NIC', () {
      final now = DateTime.now().toUtc();
      final original = Customer(
        id: 2,
        shopId: 'shop-1',
        fullName: 'Original Name',
        nic: '851234567V',
        phone: '+94 77 111 2222',
        address: 'Original Address',
        createdAt: now,
        updatedAt: now,
      );

      final updated = original.copyWith(
        fullName: 'Updated Name',
        phone: '+94 71 999 8888',
        nic: '199012345678',
      );

      expect(updated.id, equals(original.id));
      expect(updated.fullName, equals('Updated Name'));
      expect(updated.phone, equals('+94 71 999 8888'));
      expect(updated.nic, equals('199012345678'));

      // copyWith with invalid NIC format throws ArgumentError
      expect(
        () => original.copyWith(nic: 'bad-nic'),
        throwsArgumentError,
      );
    });

    test('Customer equality and hashCode', () {
      final now = DateTime.now().toUtc();
      final c1 = Customer(
        id: 1,
        shopId: 'shop-1',
        fullName: 'A',
        nic: '851234567V',
        phone: '+94 77 000 0000',
        address: 'Addr',
        createdAt: now,
        updatedAt: now,
      );
      final c2 = Customer(
        id: 1,
        shopId: 'shop-1',
        fullName: 'A',
        nic: '851234567V',
        phone: '+94 77 000 0000',
        address: 'Addr',
        createdAt: now,
        updatedAt: now,
      );
      final c3 = Customer(
        id: 2,
        shopId: 'shop-1',
        fullName: 'A',
        nic: '851234567V',
        phone: '+94 77 000 0000',
        address: 'Addr',
        createdAt: now,
        updatedAt: now,
      );

      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1, isNot(equals(c3)));
    });
  });
}
