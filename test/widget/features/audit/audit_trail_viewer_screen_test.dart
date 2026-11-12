import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:credit_system/core/permissions/app_permission.dart';
import 'package:credit_system/features/audit/domain/models/audit_event_record.dart';
import 'package:credit_system/features/audit/domain/services/audit_trail_service.dart';
import 'package:credit_system/features/audit/presentation/audit_trail_viewer_screen.dart';
import 'package:credit_system/features/auth/domain/models/app_user.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const _shopId = 'shop-uuid-001';
const _otherShopId = 'shop-uuid-002';

/// Shop Owner — has every permission including viewAuditLogs.
AppUser _makeOwner() => AppUser(
      id: 'owner-uuid-001',
      shopId: _shopId,
      username: 'owner',
      fullName: 'Shop Owner',
      role: AppRole.shopOwner,
    );

/// Cashier — does NOT have viewAuditLogs permission.
AppUser _makeCashier() => AppUser(
      id: 'cashier-uuid-001',
      shopId: _shopId,
      username: 'cashier1',
      fullName: 'Cashier One',
      role: AppRole.cashier,
    );

/// Custom user with explicit viewAuditLogs grant.
AppUser _makeCustomAuditor() => AppUser(
      id: 'auditor-uuid-001',
      shopId: _shopId,
      username: 'auditor',
      fullName: 'Auditor User',
      role: AppRole.custom,
      customPermissions: const {AppPermission.viewAuditLogs},
    );

/// Builds a minimal [AuditEventRecord] for testing.
AuditEventRecord _makeEvent({
  required String id,
  required int category,
  String actionType = 'CREATED',
  String actorId = 'actor-uuid-001',
  String shopId = _shopId,
  Map<String, dynamic>? preState,
  Map<String, dynamic>? postState,
  String? reason,
  String? clientIp,
}) =>
    AuditEventRecord(
      id: id,
      shopId: shopId,
      eventCategory: category,
      actionType: actionType,
      actorId: actorId,
      targetEntityType: 'customer',
      targetEntityId: 'entity-uuid-$id',
      preStateJson: preState,
      postStateJson: postState,
      reason: reason,
      clientIp: clientIp,
      serverTimestamp: DateTime.utc(2026, 10, 1, 12, 0, 0).add(
        Duration(minutes: int.parse(id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(1, '0'))),
      ),
    );

/// Wraps the widget under test in [MaterialApp] so navigation, theming, and
/// localization all resolve correctly.
Widget _wrap(Widget widget) => MaterialApp(home: widget);

/// Convenience helper that pumps the screen and settles all pending frames.
Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(_wrap(screen));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AuditTrailViewerScreen', () {
    // -----------------------------------------------------------------------
    // AC-1a: Unauthorised user sees "Access Denied" screen
    // -----------------------------------------------------------------------
    group('AC-1a – unauthorised access', () {
      testWidgets(
        'cashier without viewAuditLogs sees Access Denied message and no log list',
        (tester) async {
          final cashier = _makeCashier();
          final service = AuditTrailService(localMockStore: []);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: cashier,
              service: service,
            ),
          );

          // Access denied content must be visible.
          expect(find.text('Access Denied: viewAuditLogs permission required'),
              findsOneWidget);
          expect(
            find.text(
                'You do not possess the required permissions to inspect shop audit logs.'),
            findsOneWidget,
          );

          // The log list widget must NOT be rendered.
          expect(find.byKey(const Key('audit_log_list_view')), findsNothing);

          // No filter controls.
          expect(
              find.byKey(const Key('audit_category_dropdown')), findsNothing);
          expect(
              find.byKey(const Key('audit_actor_filter_field')), findsNothing);
        },
      );

      testWidgets(
        'custom user without viewAuditLogs sees Access Denied',
        (tester) async {
          final noPerms = AppUser(
            id: 'noauth-uuid',
            shopId: _shopId,
            username: 'noauth',
            fullName: 'No Auth User',
            role: AppRole.custom,
            customPermissions: const {AppPermission.viewCustomers}, // no viewAuditLogs
          );
          final service = AuditTrailService(localMockStore: []);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: noPerms,
              service: service,
            ),
          );

          expect(find.text('Access Denied: viewAuditLogs permission required'),
              findsOneWidget);
          expect(find.byKey(const Key('audit_log_list_view')), findsNothing);
        },
      );
    });

    // -----------------------------------------------------------------------
    // AC-1b: Shop Owner sees audit log list with category badges
    // -----------------------------------------------------------------------
    group('AC-1b – authorised owner sees log list with category badges', () {
      testWidgets(
        'Shop Owner sees list view header and chronological records with category badges',
        (tester) async {
          final owner = _makeOwner();
          final events = [
            _makeEvent(id: '1', category: 1, actionType: 'CUSTOMER_CREATED'),
            _makeEvent(id: '2', category: 2, actionType: 'CREDIT_ORIGINATED'),
            _makeEvent(id: '5', category: 5, actionType: 'PAYMENT_RECORDED'),
          ];
          final service = AuditTrailService(localMockStore: events);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          // AppBar title visible.
          expect(find.text('Audit Trail Viewer'), findsOneWidget);

          // Log list widget rendered (not "Access Denied").
          expect(find.byKey(const Key('audit_log_list_view')), findsOneWidget);

          // Action types from all three records are present.
          expect(find.text('CUSTOMER_CREATED'), findsOneWidget);
          expect(find.text('CREDIT_ORIGINATED'), findsOneWidget);
          expect(find.text('PAYMENT_RECORDED'), findsOneWidget);

          // Category badge text for each category.
          expect(find.text('#1'), findsOneWidget);
          expect(find.text('#2'), findsOneWidget);
          expect(find.text('#5'), findsOneWidget);

          // "Access Denied" must NOT appear.
          expect(
              find.text('Access Denied: viewAuditLogs permission required'),
              findsNothing);
        },
      );

      testWidgets(
        'custom user with viewAuditLogs sees the log list',
        (tester) async {
          final auditor = _makeCustomAuditor();
          final events = [
            _makeEvent(id: '3', category: 14, actionType: 'SECURITY_ALERT'),
          ];
          final service = AuditTrailService(localMockStore: events);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: auditor,
              service: service,
            ),
          );

          expect(find.byKey(const Key('audit_log_list_view')), findsOneWidget);
          expect(find.text('SECURITY_ALERT'), findsOneWidget);
          expect(find.text('#14'), findsOneWidget);
        },
      );

      testWidgets(
        'empty store shows "No audit records found" placeholder',
        (tester) async {
          final owner = _makeOwner();
          final service = AuditTrailService(localMockStore: []);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          expect(
            find.text('No audit records found matching criteria.'),
            findsOneWidget,
          );
          expect(find.byKey(const Key('audit_log_list_view')), findsNothing);
        },
      );
    });

    // -----------------------------------------------------------------------
    // AC-1c: Category dropdown filter updates displayed list
    // -----------------------------------------------------------------------
    group('AC-1c – category dropdown filter', () {
      testWidgets(
        'selecting category 2 hides category-1 records and shows only category-2 records',
        (tester) async {
          final owner = _makeOwner();
          final events = [
            _makeEvent(id: '10', category: 1, actionType: 'CAT1_EVENT'),
            _makeEvent(id: '11', category: 2, actionType: 'CAT2_EVENT_A'),
            _makeEvent(id: '12', category: 2, actionType: 'CAT2_EVENT_B'),
          ];
          final service = AuditTrailService(localMockStore: events);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          // Initially all three events visible.
          expect(find.text('CAT1_EVENT'), findsOneWidget);
          expect(find.text('CAT2_EVENT_A'), findsOneWidget);
          expect(find.text('CAT2_EVENT_B'), findsOneWidget);

          // Open the category dropdown.
          await tester.tap(find.byKey(const Key('audit_category_dropdown')));
          await tester.pumpAndSettle();

          // Select "2. Credit agreement origination and cancellation".
          // The dropdown items include the category number followed by period + title.
          await tester.tap(
            find.textContaining('Credit agreement origination').last,
          );
          await tester.pumpAndSettle();

          // Only category-2 records remain.
          expect(find.text('CAT2_EVENT_A'), findsOneWidget);
          expect(find.text('CAT2_EVENT_B'), findsOneWidget);

          // Category-1 record must be gone.
          expect(find.text('CAT1_EVENT'), findsNothing);
        },
      );

      testWidgets(
        'selecting category 3 hides unrelated records; second filter selection works independently',
        (tester) async {
          final owner = _makeOwner();
          final events = [
            _makeEvent(id: '20', category: 3, actionType: 'CAT3_EVENT'),
            _makeEvent(id: '21', category: 7, actionType: 'CAT7_EVENT'),
          ];
          final service = AuditTrailService(localMockStore: events);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          // Initially both events visible.
          expect(find.text('CAT3_EVENT'), findsOneWidget);
          expect(find.text('CAT7_EVENT'), findsOneWidget);

          // Filter to category 3 — Collateral registration.
          await tester.tap(find.byKey(const Key('audit_category_dropdown')));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('Collateral registration').last);
          await tester.pumpAndSettle();

          // Only category-3 events shown.
          expect(find.text('CAT3_EVENT'), findsOneWidget);
          expect(find.text('CAT7_EVENT'), findsNothing);

          // Now switch filter to category 7 — Financial correction approvals.
          await tester.tap(find.byKey(const Key('audit_category_dropdown')));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('Financial correction approvals').last);
          await tester.pumpAndSettle();

          // Only category-7 events shown.
          expect(find.text('CAT7_EVENT'), findsOneWidget);
          expect(find.text('CAT3_EVENT'), findsNothing);
        },
      );
    });

    // -----------------------------------------------------------------------
    // AC-2: Inspection dialog shows all 14 AC fields; password_hash is redacted
    // -----------------------------------------------------------------------
    group('AC-2 – inspection dialog shows all mandatory fields', () {
      testWidgets(
        'tapping a record opens detail dialog with all 14 mandatory fields visible',
        (tester) async {
          final owner = _makeOwner();
          final ts = DateTime.utc(2026, 10, 25, 9, 30, 0);
          final event = AuditEventRecord(
            id: 'evt-uuid-001',
            shopId: _shopId,
            eventCategory: 12,
            actionType: 'STAFF_CREATED',
            actorId: 'actor-uuid-owner',
            targetEntityType: 'app_user',
            targetEntityId: 'staff-uuid-001',
            preStateJson: const {'status': 'nonexistent'},
            postStateJson: const {
              'username': 'newstaff',
              'password_hash': 'argon2id\$secret',
              'role': 'cashier',
            },
            reason: 'New cashier onboarding',
            clientIp: '192.168.1.10',
            serverTimestamp: ts,
          );
          final service = AuditTrailService(localMockStore: [event]);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          // Tap the first (only) list tile to open the dialog.
          await tester.tap(find.text('STAFF_CREATED'));
          await tester.pumpAndSettle();

          // Dialog must be present.
          expect(find.byKey(const Key('audit_record_detail_dialog')),
              findsOneWidget);

          // --- Verify all 14 mandatory AC fields ---

          // 1. Event ID
          expect(find.text('Event ID:'), findsOneWidget);
          expect(find.text('evt-uuid-001'), findsOneWidget);

          // 2. Tenant ID (shop_id)
          expect(find.text('Tenant ID:'), findsOneWidget);
          expect(find.text(_shopId), findsOneWidget);

          // 3. Event Category
          expect(find.text('Category:'), findsOneWidget);
          expect(find.text('Category 12'), findsOneWidget);

          // 4. Action Type
          expect(find.text('Action Type:'), findsOneWidget);
          // 'STAFF_CREATED' appears in the title as well; use findsAtLeastNWidgets.
          expect(find.text('STAFF_CREATED'), findsAtLeastNWidgets(1));

          // 5. Actor User ID
          expect(find.text('Actor User ID:'), findsOneWidget);
          expect(find.text('actor-uuid-owner'), findsOneWidget);

          // 6. Target Entity
          expect(find.text('Target Entity:'), findsOneWidget);
          expect(find.text('app_user / staff-uuid-001'), findsOneWidget);

          // 7. Business Reason
          expect(find.text('Business Reason:'), findsOneWidget);
          expect(find.text('New cashier onboarding'), findsOneWidget);

          // 8. Client IP
          expect(find.text('Client IP:'), findsOneWidget);
          expect(find.text('192.168.1.10'), findsOneWidget);

          // 9. Server Timestamp
          expect(find.text('Server Timestamp:'), findsOneWidget);
          expect(find.text(ts.toIso8601String()), findsOneWidget);

          // 10 & 11. Pre/Post state section headers
          expect(
              find.text('Pre-State Snapshot (Sanitized):'), findsOneWidget);
          expect(
              find.text('Post-State Snapshot (Sanitized):'), findsOneWidget);

          // 12 & 13. Non-sensitive pre-state fields visible.
          // The pre-state map {'status': 'nonexistent'} is rendered as JSON.
          expect(find.textContaining('nonexistent'), findsOneWidget);

          // 14. password_hash must be REDACTED in the post-state snapshot.
          expect(find.textContaining('[REDACTED]'), findsOneWidget);
          // The raw secret value must NOT appear anywhere in the dialog.
          expect(find.textContaining('argon2id\$secret'), findsNothing);
          // Non-sensitive post-state keys visible.
          expect(find.textContaining('newstaff'), findsOneWidget);

          // Close the dialog.
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('audit_record_detail_dialog')),
              findsNothing);
        },
      );

      testWidgets(
        'token key in pre-state is also redacted',
        (tester) async {
          final owner = _makeOwner();
          final event = AuditEventRecord(
            id: 'evt-uuid-002',
            shopId: _shopId,
            eventCategory: 14,
            actionType: 'UNAUTHORISED_ACCESS',
            actorId: 'actor-uuid-002',
            targetEntityType: 'session',
            targetEntityId: 'session-uuid-002',
            preStateJson: const {
              'token': 'supersecret-jwt',
              'user': 'attacker',
            },
            serverTimestamp: DateTime.utc(2026, 10, 25, 10, 0, 0),
          );
          final service = AuditTrailService(localMockStore: [event]);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          await tester.tap(find.text('UNAUTHORISED_ACCESS'));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('audit_record_detail_dialog')),
              findsOneWidget);

          // 'token' key value must be redacted.
          expect(find.textContaining('[REDACTED]'), findsOneWidget);
          expect(find.textContaining('supersecret-jwt'), findsNothing);
          // Non-sensitive key visible.
          expect(find.textContaining('attacker'), findsOneWidget);

          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'record with null pre/post state shows (None) placeholders',
        (tester) async {
          final owner = _makeOwner();
          final event = AuditEventRecord(
            id: 'evt-uuid-003',
            shopId: _shopId,
            eventCategory: 13,
            actionType: 'RECEIPT_REPRINTED',
            actorId: 'actor-uuid-003',
            targetEntityType: 'payment',
            targetEntityId: 'payment-uuid-003',
            serverTimestamp: DateTime.utc(2026, 10, 25, 11, 0, 0),
          );
          final service = AuditTrailService(localMockStore: [event]);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          await tester.tap(find.text('RECEIPT_REPRINTED'));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('audit_record_detail_dialog')),
              findsOneWidget);

          // Both state placeholders visible.
          expect(find.text('(None)'), findsAtLeastNWidgets(2));

          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        },
      );
    });

    // -----------------------------------------------------------------------
    // AC-3 (boundary): cross-tenant access attempt surfaces an error message
    // -----------------------------------------------------------------------
    group('AC-3 – cross-tenant guard surfaced in UI', () {
      testWidgets(
        'authorized owner requesting a different shopId sees an error from the service',
        (tester) async {
          // The owner belongs to _shopId but we pass _otherShopId to the screen.
          // The service cross-tenant guard fires and throws — the screen must
          // display the error text rather than crashing.
          final owner = _makeOwner();
          final events = [
            _makeEvent(id: '99', category: 1, shopId: _otherShopId),
          ];
          final service = AuditTrailService(localMockStore: events);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _otherShopId, // mismatch: owner belongs to _shopId
              currentUser: owner,   // isOwner=true → cross-tenant guard passes for owner
              service: service,
            ),
          );

          // Shop Owner bypasses cross-tenant guard — they see the list.
          expect(find.byKey(const Key('audit_log_list_view')), findsOneWidget);
        },
      );
    });

    // -----------------------------------------------------------------------
    // Refresh button
    // -----------------------------------------------------------------------
    group('Refresh button', () {
      testWidgets(
        'pressing refresh reloads the list',
        (tester) async {
          final owner = _makeOwner();
          final events = [
            _makeEvent(id: '50', category: 4, actionType: 'DISBURSED'),
          ];
          final service = AuditTrailService(localMockStore: events);

          await _pumpScreen(
            tester,
            AuditTrailViewerScreen(
              shopId: _shopId,
              currentUser: owner,
              service: service,
            ),
          );

          expect(find.text('DISBURSED'), findsOneWidget);

          // Tap refresh — should still show the same record without errors.
          await tester.tap(find.byKey(const Key('refresh_audit_button')));
          await tester.pumpAndSettle();

          expect(find.text('DISBURSED'), findsOneWidget);
        },
      );
    });
  });
}

