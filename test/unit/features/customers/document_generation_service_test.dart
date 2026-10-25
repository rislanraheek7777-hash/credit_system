import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:credit_system/core/data/local/app_database.dart';
import 'package:credit_system/core/data/local/connection/database_connection.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/core/permissions/authorization_guard.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';
import 'package:credit_system/features/collateral/domain/models/collateral_item.dart';
import 'package:credit_system/features/customers/data/services/document_generation_service_impl.dart';
import 'package:credit_system/features/customers/domain/models/customer.dart';
import 'package:credit_system/features/customers/domain/models/loan.dart';
import 'package:credit_system/features/customers/domain/models/loan_document_content.dart';
import 'package:credit_system/features/customers/domain/models/loan_term.dart';

/// The shop zone used throughout these tests; the approved default
/// (`Asia/Colombo`) is the zone that exposed the UTC-date defect.
final ShopTimeZone shopZone = ShopTimeZone.defaultTimeZone();

const String shopId = '11111111-1111-1111-1111-111111111101';
const String otherShopId = '11111111-1111-1111-1111-111111111102';
const String customerId = '22222222-2222-2222-2222-222222222201';
const String loanId = '33333333-3333-3333-3333-333333333301';
const String otherLoanId = '33333333-3333-3333-3333-333333333302';
const String snapshotId = '44444444-4444-4444-4444-444444444401';

/// Test actor with createLoans permission (cashier role).
final AppUser managerActor = AppUser(
  id: 'user-1',
  shopId: shopId,
  username: 'staff1',
  fullName: 'Staff One',
  role: AppRole.manager,
  isActive: true,
);

/// Test actor with viewAndReprintReceipts but NOT createLoans.
final AppUser cashierActor = AppUser(
  id: 'user-2',
  shopId: shopId,
  username: 'cashier1',
  fullName: 'Cashier One',
  role: AppRole.cashier,
  isActive: true,
);

/// Test actor from another shop (cross-tenant).
final AppUser otherShopActor = AppUser(
  id: 'user-3',
  shopId: otherShopId,
  username: 'staff3',
  fullName: 'Staff Three',
  role: AppRole.manager,
  isActive: true,
);

/// Deactivated actor.
final AppUser deactivatedActor = AppUser(
  id: 'user-4',
  shopId: shopId,
  username: 'deactivated',
  fullName: 'Deactivated User',
  role: AppRole.manager,
  isActive: false,
);

Customer buildCustomer({
  String id = customerId,
  String shop = shopId,
  String nic = '851234567V',
  String phone = '0771234567',
  String address = '1 Main St',
  String fullName = 'Nimal Perera',
}) {
  return Customer(
    id: id,
    shopId: shop,
    fullName: fullName,
    nic: nic,
    phone: phone,
    address: address,
    createdAt: DateTime.utc(2026, 1, 2),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

Loan buildPendingLoan({
  String id = loanId,
  String shop = shopId,
  String customer = customerId,
  int principalCents = 150050,
  int? termPresetDays = 30,
  DateTime? customDueDate,
  DateTime? dueDate,
  DateTime? createdAt,
}) {
  return Loan(
    id: id,
    shopId: shop,
    customerId: customer,
    principalCents: principalCents,
    balanceCents: principalCents,
    status: LoanStatus.active,
    workflowStatus: LoanWorkflowStatus.pendingDisbursement,
    dueDate: dueDate ?? DateTime.utc(2026, 11, 15),
    createdAt: createdAt ?? DateTime.utc(2026, 10, 16, 9),
    termPresetDays: termPresetDays,
    customDueDate: customDueDate,
  );
}

Loan buildDisbursedLoan({
  String id = loanId,
  String shop = shopId,
  String customer = customerId,
  int principalCents = 150050,
  DateTime? disbursedAt,
  DateTime? dueDate,
  DateTime? createdAt,
  bool includeDisbursementTimestamp = true,
}) {
  return Loan(
    id: id,
    shopId: shop,
    customerId: customer,
    principalCents: principalCents,
    balanceCents: principalCents,
    status: LoanStatus.active,
    workflowStatus: LoanWorkflowStatus.disbursed,
    dueDate: dueDate ?? DateTime.utc(2026, 11, 19),
    createdAt: createdAt ?? DateTime.utc(2026, 10, 16, 9),
    termPresetDays: 30,
    disbursedAt: includeDisbursementTimestamp
        ? (disbursedAt ?? DateTime.utc(2026, 10, 20, 9, 30))
        : null,
    disbursedByUserId: 'user-1',
  );
}

Loan buildCancelledLoan({String id = loanId}) {
  return Loan(
    id: id,
    shopId: shopId,
    customerId: customerId,
    principalCents: 150050,
    balanceCents: 150050,
    status: LoanStatus.cancelled,
    workflowStatus: LoanWorkflowStatus.cancelled,
    dueDate: DateTime.utc(2026, 11, 15),
    createdAt: DateTime.utc(2026, 10, 16, 9),
    termPresetDays: 30,
    cancelledAt: DateTime.utc(2026, 10, 17),
    cancellationReason: 'Customer withdrew',
  );
}

CollateralItem buildCollateralItem() {
  return CollateralItem(
    id: '55555555-5555-5555-5555-555555555501',
    shopId: shopId,
    customerId: customerId,
    loanId: loanId,
    itemReferenceId: 'COLL-001',
    category: CollateralItemCategory.gold,
    description: 'Gold necklace',
    conditionGrade: 'A',
    weightMilligrams: 5500,
    estimatedValueCents: 250000,
    createdAt: DateTime.utc(2026, 10, 16),
    updatedAt: DateTime.utc(2026, 10, 16),
  );
}

Future<void> seedShopAndCustomer(AppDatabase db) async {
  final now = DateTime.utc(2026, 10, 16);
  await db
      .into(db.shops)
      .insert(
        ShopEntry(
          id: shopId,
          name: 'Alpha Jewellers',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.shops)
      .insert(
        ShopEntry(
          id: otherShopId,
          name: 'Beta Jewellers',
          currencyCode: 'LKR',
          timezone: 'Asia/Colombo',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.customers)
      .insert(
        CustomerEntry(
          id: customerId,
          shopId: shopId,
          fullName: 'Nimal Perera',
          nic: '851234567V',
          phone: '0771234567',
          address: '1 Main St',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.appUsers)
      .insert(
        AppUserEntry(
          id: 'user-1',
          shopId: shopId,
          username: 'staff1',
          fullName: 'Staff One',
          role: 'counter_staff',
          isActive: true,
          sessionVersion: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> insertLoan(AppDatabase db, Loan loan) async {
  await db
      .into(db.loans)
      .insert(
        LoansCompanion(
          id: Value(loan.id),
          shopId: Value(loan.shopId),
          customerId: Value(loan.customerId),
          principalCents: Value(loan.principalCents),
          balanceCents: Value(loan.balanceCents),
          status: Value(loan.status.value),
          workflowStatus: Value(loan.workflowStatus.value),
          termPresetDays: Value(loan.termPresetDays),
          customDueDate: Value(loan.customDueDate),
          disbursedAt: Value(loan.disbursedAt),
          disbursedByUserId: Value(loan.disbursedByUserId),
          cancelledAt: Value(loan.cancelledAt),
          cancellationReason: Value(loan.cancellationReason),
          dueDate: Value(loan.dueDate),
          createdAt: Value(loan.createdAt),
          settledAt: Value(loan.settledAt),
        ),
      );
}

String pdfRawText(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

/// Reconstructs the visible text from the uncompressed PDF content streams.
///
/// The `pdf` package emits each laid-out word as its own `[(word)]TJ` operator,
/// so a raw byte search cannot see a full sentence. This joins those operators
/// back into readable lines for mandatory-text assertions.
String pdfVisibleText(List<int> bytes) {
  final raw = pdfRawText(bytes);
  final matches = RegExp(r'\[\(((?:\\.|[^\\)])*)\)\]TJ').allMatches(raw);
  return matches
      .map(
        (match) => match
            .group(1)!
            .replaceAllMapped(RegExp(r'\\(.)'), (escaped) => escaped.group(1)!),
      )
      .join(' ');
}

void main() {
  group('mandatory Story 4.4 document text', () {
    test('constants exactly match the required wording', () {
      expect(
        kDraftWatermark,
        '*** DRAFT / PENDING DISBURSEMENT - NOT A CASH RECEIPT ***',
      );
      expect(
        kPreliminaryDueDateDisclosure,
        'Preliminary Due Date (Subject to Confirmation on Cash Handover) - '
        'Non-binding until disbursement confirmation.',
      );
      expect(
        kDraftCashNotDisbursedDisclosure,
        'Cash has NOT been disbursed. This document is not a receipt and is '
        'not binding until cash handover is confirmed.',
      );
    });

    test('draft content carries watermark twice and both disclosures', () {
      final content = buildDraftDocumentContent(
        loan: buildPendingLoan(),
        shopTimeZone: shopZone,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        showRawPII: false,
        customer: buildCustomer(),
        collateralItems: [buildCollateralItem()],
        generatedAt: DateTime.utc(2026, 10, 18, 8),
      );

      expect(
        content.footerLines.where((line) => line == kDraftWatermark).length,
        1,
      );
      expect(content.watermark, kDraftWatermark);
      expect(
        content.allLines
            .where((line) => line == kPreliminaryDueDateDisclosure)
            .length,
        2,
      );
      expect(
        content.allLines
            .where((line) => line == kDraftCashNotDisbursedDisclosure)
            .length,
        2,
      );
      expect(content.allLines, contains(kDraftSignatureLabel));
      expect(content.reference, startsWith('DRAFT-'));
      expect(
        content.allLines,
        contains('Preliminary Due Date (Pending Disbursement): 2026-11-15'),
      );
      expect(content.allLines, contains('Principal Amount: Rs. 1,500.50'));
      final joined = content.allLines.join('\n');
      expect(joined, contains('COLL-001: Gold necklace'));
      expect(joined, contains('5.500 g'));
      expect(joined, isNot(contains('OFFICIAL')));
      expect(joined, isNot(contains('CASH DISBURSED')));
      expect(joined, isNot(contains('VCH-')));
    });

    test('draft masks NIC and phone and never prints the address', () {
      final content = buildDraftDocumentContent(
        loan: buildPendingLoan(),
        shopTimeZone: shopZone,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        showRawPII: false,
        customer: buildCustomer(),
      );

      final joined = content.allLines.join('\n');
      expect(joined, contains('Customer NIC: 8512****567V'));
      expect(joined, contains('Customer Phone: 077 **** 567'));
      expect(joined, isNot(contains('851234567V')));
      expect(joined, isNot(contains('0771234567')));
      expect(joined, isNot(contains('1 Main St')));
      expect(joined, contains('Nimal Perera'));
    });

    test(
      'privileged draft can show raw NIC and phone but still no address',
      () {
        final content = buildDraftDocumentContent(
          loan: buildPendingLoan(),
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          showRawPII: true,
          customer: buildCustomer(),
        );

        final joined = content.allLines.join('\n');
        expect(joined, contains('Customer NIC: 851234567V'));
        expect(joined, contains('Customer Phone: 0771234567'));
        expect(joined, isNot(contains('1 Main St')));
      },
    );

    test('short NIC and phone fail closed rather than printing raw values', () {
      // Customer itself rejects an invalid short NIC, so the document masker is
      // exercised directly for the NIC case; a short phone is still a valid
      // customer value and is checked through the rendered content.
      expect(documentMaskNic('12345678', showRawPII: false), '****');
      expect(documentMaskPhone('123456', showRawPII: false), '****');

      final content = buildDraftDocumentContent(
        loan: buildPendingLoan(),
        shopTimeZone: shopZone,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        showRawPII: false,
        customer: buildCustomer(phone: '123456'),
      );

      final joined = content.allLines.join('\n');
      expect(joined, isNot(contains('123456')));
      expect(joined, contains('Customer NIC: 8512****567V'));
      expect(joined, contains('Customer Phone: ****'));
    });

    test(
      'official voucher contains every required field and collateral line',
      () {
        final content = buildOfficialVoucherContent(
          loan: buildDisbursedLoan(),
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          confirmedDueDate: DateTime.utc(2026, 11, 19),
          documentSnapshotId: snapshotId,
          showRawPII: false,
          customer: buildCustomer(),
          collateralItems: [buildCollateralItem()],
          shopFooterNotes: 'Goods held at owner risk.',
          generatedAt: DateTime.utc(2026, 10, 20, 9, 31),
        );

        final joined = content.allLines.join('\n');
        expect(content.title, 'LOAN AGREEMENT & CASH DISBURSEMENT VOUCHER');
        expect(content.reference, startsWith('VCH-'));
        expect(joined, contains('OFFICIAL - CASH DISBURSED'));
        expect(joined, contains('Snapshot ID: $snapshotId'));
        expect(joined, contains('LN-'));
        expect(joined, contains(loanId));
        expect(joined, contains('Nimal Perera'));
        expect(joined, contains('Customer NIC: 8512****567V'));
        expect(joined, contains('Origination Date: 2026-10-16'));
        expect(
          joined,
          contains('Confirmed Cash Disbursement: 2026-10-20 09:30 UTC'),
        );
        expect(joined, contains('Disbursing Staff ID: staff-7'));
        expect(joined, contains('Official Confirmed Due Date: 2026-11-19'));
        expect(joined, contains('Disbursed Principal Amount: Rs. 1,500.50'));
        expect(joined, contains('Initial Outstanding Balance: Rs. 1,500.50'));
        expect(joined, contains('COLL-001: Gold necklace'));
        expect(joined, contains('5.500 g'));
        expect(joined, contains('Rs. 2,500.00'));
        expect(joined, contains(kZeroInterestDisclosure));
        expect(
          joined,
          contains('Shop Footer Notes: Goods held at owner risk.'),
        );
        expect(joined, isNot(contains(kDraftWatermark)));
        expect(joined, isNot(contains('1 Main St')));
      },
    );

    test('official voucher states when no collateral items were supplied', () {
      final content = buildOfficialVoucherContent(
        loan: buildDisbursedLoan(),
        shopTimeZone: shopZone,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        confirmedDueDate: DateTime.utc(2026, 11, 19),
        documentSnapshotId: snapshotId,
        showRawPII: false,
      );

      expect(content.allLines, contains('No collateral items recorded.'));
    });
  });

  group('DocumentGenerationServiceImpl PDF generation', () {
    late DocumentGenerationServiceImpl service;

    setUp(() {
      service = DocumentGenerationServiceImpl();
    });

    test(
      'draft PDF is a real PDF containing the mandatory watermark',
      () async {
        final bytes = await service.generateDraftPdf(
          loan: buildPendingLoan(),
          actor: managerActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          customer: buildCustomer(),
        );

        expect(bytes, isNotEmpty);
        final raw = pdfRawText(bytes);
        final text = pdfVisibleText(bytes);
        expect(raw, startsWith('%PDF'));
        expect(text, contains(kDraftWatermark));
        expect(text, isNot(contains('851234567V')));
        expect(text, isNot(contains('1 Main St')));
      },
    );

    test(
      'official voucher PDF is a real PDF with the document number',
      () async {
        final bytes = await service.generateVoucherPdf(
          loan: buildDisbursedLoan(),
          actor: managerActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          confirmedDueDate: DateTime.utc(2026, 11, 19),
          documentSnapshotId: snapshotId,
          customer: buildCustomer(),
          collateralItems: [buildCollateralItem()],
          shopFooterNotes: 'Goods held at owner risk.',
        );

        expect(bytes, isNotEmpty);
        final raw = pdfRawText(bytes);
        final text = pdfVisibleText(bytes);
        expect(raw, startsWith('%PDF'));
        expect(text, contains('VCH-'));
        expect(text, contains('OFFICIAL - CASH DISBURSED'));
        expect(text, isNot(contains(kDraftWatermark)));
      },
    );

    test('draft refuses disbursed and cancelled loans', () async {
      for (final loan in [buildDisbursedLoan(), buildCancelledLoan()]) {
        await expectLater(
          service.generateDraftPdf(
            loan: loan,
            actor: managerActor,
            shopTimeZone: shopZone,
            shopName: 'Alpha Jewellers',
            shopAddress: '10 Galle Rd',
            shopPhone: '+94112223344',
            shopTaxId: 'TAX-1',
            disbursingStaffId: 'staff-7',
          ),
          throwsA(isA<LoanDisbursementStateException>()),
        );
      }
    });

    test(
      'voucher refuses pending, cancelled and timestamp-less loans',
      () async {
        final loans = <Loan>[
          buildPendingLoan(),
          buildCancelledLoan(),
          buildDisbursedLoan(includeDisbursementTimestamp: false),
        ];

        for (final loan in loans) {
          await expectLater(
            service.generateVoucherPdf(
              loan: loan,
              actor: managerActor,
              shopTimeZone: shopZone,
              shopName: 'Alpha Jewellers',
              shopAddress: '10 Galle Rd',
              shopPhone: '+94112223344',
              shopTaxId: 'TAX-1',
              disbursingStaffId: 'staff-7',
              confirmedDueDate: DateTime.utc(2026, 11, 19),
              documentSnapshotId: snapshotId,
            ),
            throwsA(isA<LoanDisbursementStateException>()),
          );
        }
      },
    );

    test('voucher refuses a blank snapshot identifier', () async {
      await expectLater(
        service.generateVoucherPdf(
          loan: buildDisbursedLoan(),
          actor: managerActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          confirmedDueDate: DateTime.utc(2026, 11, 19),
          documentSnapshotId: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('customer from another loan is rejected', () async {
      await expectLater(
        service.generateDraftPdf(
          loan: buildPendingLoan(),
          actor: managerActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          customer: buildCustomer(id: '99999999-9999-9999-9999-999999999999'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('DocumentGenerationServiceImpl authorization (PRD FR-20)', () {
    late AppDatabase db;
    late DocumentGenerationServiceImpl service;

    setUp(() async {
      db = AppDatabase.forTesting(
        AppDatabaseConnection.openInMemoryConnection(),
      );
      service = DocumentGenerationServiceImpl();
      await seedShopAndCustomer(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'draft generation requires createLoans: actor without it is denied',
      () async {
        // Cashier has createLoans; use an actor with only viewCustomers.
        final noCreateLoans = AppUser(
          id: 'user-nocl',
          shopId: shopId,
          username: 'nocl',
          fullName: 'No Create Loans',
          role: AppRole.custom,
          isActive: true,
          customPermissions: {AppPermission.viewCustomers},
        );

        await expectLater(
          service.generateDraftPdf(
            loan: buildPendingLoan(),
            actor: noCreateLoans,
            shopTimeZone: shopZone,
            shopName: 'Alpha Jewellers',
            shopAddress: '10 Galle Rd',
            shopPhone: '+94112223344',
            shopTaxId: 'TAX-1',
            disbursingStaffId: 'staff-7',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'draft generation denies a deactivated actor even with createLoans',
      () async {
        await expectLater(
          service.generateDraftPdf(
            loan: buildPendingLoan(),
            actor: deactivatedActor,
            shopTimeZone: shopZone,
            shopName: 'Alpha Jewellers',
            shopAddress: '10 Galle Rd',
            shopPhone: '+94112223344',
            shopTaxId: 'TAX-1',
            disbursingStaffId: 'staff-7',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'draft generation denies cross-tenant actor',
      () async {
        await expectLater(
          service.generateDraftPdf(
            loan: buildPendingLoan(),
            actor: otherShopActor,
            shopTimeZone: shopZone,
            shopName: 'Alpha Jewellers',
            shopAddress: '10 Galle Rd',
            shopPhone: '+94112223344',
            shopTaxId: 'TAX-1',
            disbursingStaffId: 'staff-7',
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'voucher generation allows createLoans holder (manager)',
      () async {
        await insertLoan(db, buildDisbursedLoan());
        await service.persistDocumentSnapshot(
          db: db,
          loan: buildDisbursedLoan(),
          documentSnapshotId: snapshotId,
        );

        final bytes = await service.generateVoucherPdf(
          loan: buildDisbursedLoan(),
          actor: managerActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          confirmedDueDate: DateTime.utc(2026, 11, 19),
          documentSnapshotId: snapshotId,
          customer: buildCustomer(),
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      'voucher generation allows viewAndReprintReceipts holder (cashier)',
      () async {
        await insertLoan(db, buildDisbursedLoan());
        await service.persistDocumentSnapshot(
          db: db,
          loan: buildDisbursedLoan(),
          documentSnapshotId: snapshotId,
        );

        final bytes = await service.generateVoucherPdf(
          loan: buildDisbursedLoan(),
          actor: cashierActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          confirmedDueDate: DateTime.utc(2026, 11, 19),
          documentSnapshotId: snapshotId,
          customer: buildCustomer(),
        );
        expect(bytes, isNotEmpty);
      },
    );

    test(
      'voucher generation denies actor with neither createLoans nor viewAndReprintReceipts',
      () async {
        final noVoucherPerm = AppUser(
          id: 'user-novp',
          shopId: shopId,
          username: 'novp',
          fullName: 'No Voucher Perm',
          role: AppRole.custom,
          isActive: true,
          customPermissions: {AppPermission.viewCustomers},
        );

        await expectLater(
          service.generateVoucherPdf(
            loan: buildDisbursedLoan(),
            actor: noVoucherPerm,
            shopTimeZone: shopZone,
            shopName: 'Alpha Jewellers',
            shopAddress: '10 Galle Rd',
            shopPhone: '+94112223344',
            shopTaxId: 'TAX-1',
            disbursingStaffId: 'staff-7',
            confirmedDueDate: DateTime.utc(2026, 11, 19),
            documentSnapshotId: snapshotId,
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'voucher generation denies deactivated actor even with createLoans',
      () async {
        await expectLater(
          service.generateVoucherPdf(
            loan: buildDisbursedLoan(),
            actor: deactivatedActor,
            shopTimeZone: shopZone,
            shopName: 'Alpha Jewellers',
            shopAddress: '10 Galle Rd',
            shopPhone: '+94112223344',
            shopTaxId: 'TAX-1',
            disbursingStaffId: 'staff-7',
            confirmedDueDate: DateTime.utc(2026, 11, 19),
            documentSnapshotId: snapshotId,
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      },
    );

    test(
      'showRawPII is ignored unless actor holds viewSensitiveCustomerData',
      () async {
        // Manager has viewSensitiveCustomerData; cashier does not.
        final managerBytes = await service.generateDraftPdf(
          loan: buildPendingLoan(),
          actor: managerActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          showRawPII: true,
          customer: buildCustomer(),
        );
        final managerText = pdfVisibleText(managerBytes);
        expect(managerText, contains('851234567V')); // unmasked for manager

        final cashierBytes = await service.generateDraftPdf(
          loan: buildPendingLoan(),
          actor: cashierActor,
          shopTimeZone: shopZone,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          showRawPII: true, // caller lies; cashier lacks viewSensitiveCustomerData
          customer: buildCustomer(),
        );
        final cashierText = pdfVisibleText(cashierBytes);
        expect(cashierText, isNot(contains('851234567V'))); // still masked
        expect(cashierText, contains('8512****567V'));
      },
    );
  });

  group('snapshot persistence and audit queue', () {
    late AppDatabase db;
    late DocumentGenerationServiceImpl service;

    setUp(() async {
      db = AppDatabase.forTesting(
        AppDatabaseConnection.openInMemoryConnection(),
      );
      service = DocumentGenerationServiceImpl();
      await seedShopAndCustomer(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('persists the snapshot identifier on a disbursed loan', () async {
      final loan = buildDisbursedLoan();
      await insertLoan(db, loan);

      await service.persistDocumentSnapshot(
        db: db,
        loan: loan,
        documentSnapshotId: snapshotId,
      );

      final row = await (db.select(
        db.loans,
      )..where((t) => t.id.equals(loanId))).getSingle();
      expect(row.documentSnapshotId, snapshotId);
    });

    test('persist updates only the snapshot identifier', () async {
      final loan = buildDisbursedLoan(principalCents: 987654);
      await insertLoan(db, loan);

      final before = await (db.select(
        db.loans,
      )..where((t) => t.id.equals(loanId))).getSingle();

      await service.persistDocumentSnapshot(
        db: db,
        loan: loan,
        documentSnapshotId: snapshotId,
      );

      final after = await (db.select(
        db.loans,
      )..where((t) => t.id.equals(loanId))).getSingle();

      expect(after.documentSnapshotId, snapshotId);

      // Compare every column, not just a hand-picked subset: a `replace` or an
      // unscoped companion would silently reset fields such as the disbursement
      // record, principal, or balances.
      final beforeFields = Map<String, dynamic>.of(before.toJson())
        ..remove('documentSnapshotId');
      final afterFields = Map<String, dynamic>.of(after.toJson())
        ..remove('documentSnapshotId');
      expect(afterFields, beforeFields);

      // Explicit representative assertions keep the intent readable when the
      // generated row changes shape in a future schema revision.
      expect(after.id, loanId);
      expect(after.shopId, shopId);
      expect(after.customerId, customerId);
      expect(after.principalCents, 987654);
      expect(after.balanceCents, 987654);
      expect(after.status, LoanStatus.active.value);
      expect(after.workflowStatus, LoanWorkflowStatus.disbursed.value);
      expect(after.termPresetDays, 30);
      expect(after.disbursedAt, isNotNull);
      expect(after.disbursedAt!.isAtSameMomentAs(loan.disbursedAt!), isTrue);
      expect(after.disbursedByUserId, loan.disbursedByUserId);
      expect(after.dueDate.isAtSameMomentAs(loan.dueDate), isTrue);
      expect(after.createdAt.isAtSameMomentAs(loan.createdAt), isTrue);
      expect(after.customDueDate, isNull);
      expect(after.cancelledAt, isNull);
      expect(after.cancellationReason, isNull);
      expect(after.settledAt, isNull);
    });

    test(
      'same snapshot identifier is idempotent; a different one is refused',
      () async {
        final loan = buildDisbursedLoan();
        await insertLoan(db, loan);

        await service.persistDocumentSnapshot(
          db: db,
          loan: loan,
          documentSnapshotId: snapshotId,
        );
        await service.persistDocumentSnapshot(
          db: db,
          loan: loan,
          documentSnapshotId: snapshotId,
        );

        await expectLater(
          service.persistDocumentSnapshot(
            db: db,
            loan: loan,
            documentSnapshotId: 'different-snapshot',
          ),
          throwsA(isA<StateError>()),
        );

        final row = await (db.select(
          db.loans,
        )..where((t) => t.id.equals(loanId))).getSingle();
        expect(row.documentSnapshotId, snapshotId);
      },
    );

    test('pending loan cannot persist a snapshot', () async {
      await expectLater(
        service.persistDocumentSnapshot(
          db: db,
          loan: buildPendingLoan(),
          documentSnapshotId: snapshotId,
        ),
        throwsA(isA<LoanDisbursementStateException>()),
      );

      expect(await db.select(db.loans).get(), isEmpty);
    });

    test(
      'missing loan row is reported and does not touch another loan',
      () async {
        await insertLoan(db, buildDisbursedLoan(id: otherLoanId));

        await expectLater(
          service.persistDocumentSnapshot(
            db: db,
            loan: buildDisbursedLoan(),
            documentSnapshotId: snapshotId,
          ),
          throwsA(isA<StateError>()),
        );

        final untouched = await (db.select(
          db.loans,
        )..where((t) => t.id.equals(otherLoanId))).getSingle();
        expect(untouched.documentSnapshotId, isNull);
      },
    );

    test('audit event queues JSON with category 2 and no raw PII', () async {
      await insertLoan(db, buildPendingLoan());

      await service.recordDocumentAuditEvent(
        db: db,
        shopId: shopId,
        actorId: 'user-1',
        actionType: DocumentGenerationServiceImpl.draftGeneratedActionType,
        customerId: '851234567V',
        loanId: loanId,
        isDraft: true,
      );

      final rows = await db.select(db.syncQueue).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.shopId, shopId);
      expect(row.entityType, 'loan');
      expect(row.entityId, loanId);
      expect(row.actionType, 'generate_loan_draft');
      expect(row.status, 'pending_server_ack');
      expect(row.idempotencyKey, row.id);
      expect(row.id, isNot(loanId));

      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['eventCategory'], 2);
      expect(payload['isDraft'], isTrue);
      expect(payload['piiIncluded'], isFalse);
      expect(payload['customerId'], '8512****567V');
      expect(payload['customerIdSha256'], hasLength(64));
      expect(row.payloadJson, isNot(contains('851234567V')));
      expect(payload['recordedAt'], endsWith('Z'));
    });

    test('short identifiers are fully redacted in the audit payload', () async {
      await insertLoan(db, buildPendingLoan());

      await service.recordDocumentAuditEvent(
        db: db,
        shopId: shopId,
        actorId: 'user-1',
        actionType: DocumentGenerationServiceImpl.draftGeneratedActionType,
        customerId: '12345678',
        loanId: loanId,
        isDraft: true,
      );

      final row = (await db.select(db.syncQueue).get()).single;
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      expect(payload['customerId'], '****');
      expect(row.payloadJson, isNot(contains('12345678')));
    });

    test(
      'each audit call gets a distinct collision-safe idempotency key',
      () async {
        await insertLoan(db, buildPendingLoan());

        for (var i = 0; i < 2; i++) {
          await service.recordDocumentAuditEvent(
            db: db,
            shopId: shopId,
            actorId: 'user-1',
            actionType: DocumentGenerationServiceImpl.draftGeneratedActionType,
            customerId: customerId,
            loanId: loanId,
            isDraft: true,
          );
        }

        final rows = await db.select(db.syncQueue).get();
        expect(rows, hasLength(2));
        expect(rows[0].idempotencyKey, isNot(rows[1].idempotencyKey));
      },
    );

    test('audit event refuses a loan from another shop', () async {
      await insertLoan(db, buildPendingLoan());

      await expectLater(
        service.recordDocumentAuditEvent(
          db: db,
          shopId: otherShopId,
          actorId: 'user-1',
          actionType: DocumentGenerationServiceImpl.draftGeneratedActionType,
          customerId: customerId,
          loanId: loanId,
          isDraft: true,
        ),
        throwsArgumentError,
      );

      expect(await db.select(db.syncQueue).get(), isEmpty);
    });

    test(
      'audit event defaults the action type from the document kind',
      () async {
        await insertLoan(db, buildDisbursedLoan());

        await service.recordDocumentAuditEvent(
          db: db,
          shopId: shopId,
          actorId: 'user-1',
          actionType: '   ',
          customerId: customerId,
          loanId: loanId,
          isDraft: false,
        );

        final row = (await db.select(db.syncQueue).get()).single;
        expect(row.actionType, 'generate_loan_official_ticket');
      },
    );
  });

  // Regression coverage for the Final Acceptance Review defect: loan date
  // columns persist an *instant* (local midnight in the shop zone), while the
  // document must print the shop-local *calendar* date. Formatting the UTC
  // components of `2026-11-13T18:30Z` wrongly printed `2026-11-13` in Colombo.
  group('shop-local calendar date rendering (Story 4.4 timezone fix)', () {
    final ShopTimeZone colombo = ShopTimeZone('Asia/Colombo');
    final ShopTimeZone newYork = ShopTimeZone('America/New_York');

    // The real representation produced by `ShopTimeZone.instantAtStartOfDay`.
    final DateTime colomboDue = colombo.instantAtStartOfDay(
      const LocalCalendarDate(2026, 11, 14),
    );
    final DateTime colomboOrigination = colombo.instantAtStartOfDay(
      const LocalCalendarDate(2026, 10, 15),
    );

    LoanDocumentContent draftFor(Loan loan, ShopTimeZone zone) {
      return buildDraftDocumentContent(
        loan: loan,
        shopTimeZone: zone,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        showRawPII: false,
        customer: buildCustomer(),
      );
    }

    test('fixture stores the previous UTC calendar date, not UTC midnight', () {
      // Without this guard the regression could be "fixed" by moving test
      // fixtures to UTC midnight, which would hide the real defect.
      expect(colomboDue, DateTime.utc(2026, 11, 13, 18, 30));
      expect(
        '${colomboDue.toUtc().year}-'
        '${colomboDue.toUtc().month.toString().padLeft(2, '0')}-'
        '${colomboDue.toUtc().day.toString().padLeft(2, '0')}',
        '2026-11-13',
      );
      expect(colombo.localDateOf(colomboDue).isoDate, '2026-11-14');
    });

    test('draft renders shop-local origination and preliminary due dates', () {
      final content = draftFor(
        buildPendingLoan(
          dueDate: colomboDue,
          createdAt: colomboOrigination,
        ),
        colombo,
      );
      final joined = content.allLines.join('\n');

      expect(joined, contains('Origination Date: 2026-10-15'));
      expect(
        joined,
        contains(
          'Preliminary Due Date (Pending Disbursement): 2026-11-14',
        ),
      );
      expect(
        joined,
        isNot(
          contains(
            'Preliminary Due Date (Pending Disbursement): 2026-11-13',
          ),
        ),
      );
    });

    test('draft renders a custom agreed-term date in the shop zone', () {
      final content = draftFor(
        buildPendingLoan(
          termPresetDays: null,
          customDueDate: colomboDue,
          dueDate: colomboDue,
        ),
        colombo,
      );

      expect(
        content.allLines,
        contains('Agreed Term: Custom calendar date (2026-11-14)'),
      );
    });

    test(
      'official voucher renders local due date and voucher date segment',
      () {
        // 00:15 on 14 Nov in Colombo; still 13 Nov in UTC.
        final DateTime disbursedAt = DateTime.utc(2026, 11, 13, 18, 45);
        final content = buildOfficialVoucherContent(
          loan: buildDisbursedLoan(
            dueDate: colomboDue,
            createdAt: colomboOrigination,
            disbursedAt: disbursedAt,
          ),
          shopTimeZone: colombo,
          shopName: 'Alpha Jewellers',
          shopAddress: '10 Galle Rd',
          shopPhone: '+94112223344',
          shopTaxId: 'TAX-1',
          disbursingStaffId: 'staff-7',
          confirmedDueDate: colomboDue,
          documentSnapshotId: snapshotId,
          showRawPII: false,
          customer: buildCustomer(),
        );
        final joined = content.allLines.join('\n');

        expect(joined, contains('Origination Date: 2026-10-15'));
        expect(
          joined,
          contains('Official Confirmed Due Date: 2026-11-14'),
        );
        expect(
          joined,
          isNot(contains('Official Confirmed Due Date: 2026-11-13')),
        );
        expect(content.reference, contains('-20261114-'));

        // Requirement: calendar dates are fixed, but the actual cash-handover
        // timestamp keeps its full UTC instant and must not be shifted.
        expect(
          joined,
          contains('Confirmed Cash Disbursement: 2026-11-13 18:45 UTC'),
        );
      },
    );

    test('draft PDF prints the shop-local date, never the UTC date', () async {
      final service = DocumentGenerationServiceImpl();
      final bytes = await service.generateDraftPdf(
        loan: buildPendingLoan(
          dueDate: colomboDue,
          createdAt: colomboOrigination,
        ),
        actor: managerActor,
        shopTimeZone: colombo,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        customer: buildCustomer(),
      );
      final text = pdfVisibleText(bytes);

      expect(text, contains('2026-11-14'));
      expect(text, isNot(contains('2026-11-13')));
    });

    test('official voucher PDF prints the shop-local date', () async {
      final service = DocumentGenerationServiceImpl();
      final DateTime disbursedAt = DateTime.utc(2026, 11, 13, 18, 45);
      final bytes = await service.generateVoucherPdf(
        loan: buildDisbursedLoan(
          dueDate: colomboDue,
          createdAt: colomboOrigination,
          disbursedAt: disbursedAt,
        ),
        actor: managerActor,
        shopTimeZone: colombo,
        shopName: 'Alpha Jewellers',
        shopAddress: '10 Galle Rd',
        shopPhone: '+94112223344',
        shopTaxId: 'TAX-1',
        disbursingStaffId: 'staff-7',
        confirmedDueDate: colomboDue,
        documentSnapshotId: snapshotId,
        customer: buildCustomer(),
      );
      final text = pdfVisibleText(bytes);

      expect(text, contains('2026-11-14'));
      expect(text, contains('2026-11-13 18:45 UTC'));
    });

    test('one minute before local midnight stays on the previous date', () {
      // 18:29Z is 23:59 on 13 Nov in Colombo; 18:30Z is 00:00 on 14 Nov.
      final DateTime beforeMidnight = DateTime.utc(2026, 11, 13, 18, 29);
      final content = draftFor(
        buildPendingLoan(
          dueDate: beforeMidnight,
          createdAt: colomboOrigination,
        ),
        colombo,
      );

      expect(
        content.allLines,
        contains(
          'Preliminary Due Date (Pending Disbursement): 2026-11-13',
        ),
      );
    });

    test('the same instant renders a different date in another shop zone', () {
      // 2026-11-13T18:30Z is 14 Nov in Colombo (UTC+05:30) but still 13 Nov in
      // New York (UTC-05:00), proving the formatter follows the shop zone.
      final content = draftFor(
        buildPendingLoan(
          dueDate: colomboDue,
          createdAt: colomboOrigination,
        ),
        newYork,
      );

      expect(
        content.allLines,
        contains(
          'Preliminary Due Date (Pending Disbursement): 2026-11-13',
        ),
      );
    });

    test('start-of-day conversion is stable on a DST transition day', () {
      final DateTime dstStart = newYork.instantAtStartOfDay(
        const LocalCalendarDate(2026, 3, 8),
      );
      final content = draftFor(
        buildPendingLoan(dueDate: dstStart, createdAt: dstStart),
        newYork,
      );

      expect(newYork.localDateOf(dstStart).isoDate, '2026-03-08');
      expect(
        content.allLines,
        contains(
          'Preliminary Due Date (Pending Disbursement): 2026-03-08',
        ),
      );
    });
  });
}
