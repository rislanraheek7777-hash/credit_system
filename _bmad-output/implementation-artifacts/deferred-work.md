- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: Mixed-state v19→v20 migration path (INTEGER customers with TEXT referencing columns) is untested.
  evidence: The `else if` branch in `lib/core/data/local/app_database.dart` remaps referencing tables through the live customer rows; no test seeds that intermediate state. Would need an exotic fixture; deferred per verification-gap review.

- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: `customer_search_screen.dart` and `settings_screen.dart` instantiate `AppDatabase()`/`LoanDao` without closing, risking resource leaks.
  evidence: Lines `lib/features/customers/presentation/customer_search_screen.dart:79,141-142` and `lib/features/settings/presentation/settings_screen.dart:59-60`. Pre-existing; not caused by this story's customer-ID change.

- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: `shop_creation_screen.dart` truncates the shop id to 8 characters (`Uuid().v4().substring(0, 8)`), increasing collision risk.
  evidence: Pre-existing; not caused by this story's customer-ID change.

- source_spec: `spec-fix-customer-id-type-mismatch.md`
  summary: `app_users` table documents email/phone as unique within shop but `uniqueKeys` only declares `{shopId, username}`; `getUserByLoginIdentifierGlobal` resolves across all shops, so colliding identifiers can attribute a login to the wrong shop.
  evidence: `lib/core/data/local/tables/app_users_table.dart:63` and `lib/features/auth/data/daos/user_dao.dart:73-80`. Pre-existing design gap; flagged by verification-gap review.