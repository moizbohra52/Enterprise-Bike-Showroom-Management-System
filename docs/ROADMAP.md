# Roadmap — what is wired, what is still open

Audited: 2026-09-12 (after the app bootstrap landed).

## Now wired (runnable)

| Piece | File |
| --- | --- |
| Entry point (prefs → Hive → Supabase → Firebase → global DI) | `lib/main.dart`, `lib/routes/app_bootstrap.dart` |
| Root widget (theme, locale, routing) | `lib/app.dart` |
| Route table: 49 pages, module bindings, `:id?` params | `lib/routes/app_pages.dart` |
| Session + permission gate for protected pages | `lib/common/routing/route_guard.dart` |
| Splash / login / forgot password / reset password | `lib/features/auth/views/*` |
| Dashboard (KPIs, revenue trend, recent sales, follow-ups) | `lib/features/dashboard/*` |
| Global search screen (top-bar search) | `lib/features/search/views/global_search_view.dart` |
| Forbidden / unknown-route fallbacks | `lib/features/auth/views/forbidden_view.dart`, `lib/common/views/not_found_view.dart` |

Bootstrap registers every cross-cutting singleton that `Get.find` is called on
anywhere in the app (`SupabaseService`, `LocalDatabaseService`,
`ConnectivityService`, `AuthService`, `ApiService`, `PdfService`,
`ImageService`, `StorageService`, `ExportService`, `NotificationService`,
`AppStateController`, `SyncService`, `SyncStateController`, `UserRepository`,
`SessionController`, `GlobalSearchController`, `NotificationController`) and
registers the offline sync handlers for the five entity types whose
repositories implement `applySyncOp` (showroom, user, product, inventory,
customer).

## Compile blockers fixed in the same pass

* `SupabaseConfig` declared a nested `class StorageBuckets` (illegal in Dart) —
  hoisted to top level; call sites use `StorageBuckets.*`.
* `ProductFormView` declared a nested `class FileRef` — hoisted as
  `_ProductImageRef`.
* `NotificationService` used non-existent `defaultTargetPlatformValue.*`,
  `FirebasePlatform.isAvailable`, `Firebase.appExists` and
  `messaging.onIosActivate/onIosRefresh` — rewritten with `kIsWeb`,
  `TargetPlatform.*`, `Firebase.apps.isEmpty`, `getInitialMessage`.
* `SessionController` fed a raw `Stream<AuthState>` into GetX `ever` — now a
  plain subscription; push-token registration can no longer abort profile load.
* The app's `SearchController` clashed with Flutter's `SearchController`
  (ambiguous import in `top_bar.dart`) — renamed to `GlobalSearchController`.
* `AppStateController.lightTheme/darkTheme` are now `Rx<ThemeData>` so accent
  changes from Settings repaint the app.
* `AuthController` gained `resetPassword()` and disposes its text editing
  controllers in `onClose`.

## Still open (next PRs)

1. **Unwired routes.** `AppRoutes` declares pages whose views do not exist yet,
   so these menu entries have no page (GetX shows the unknown-route screen):
   `users` (list/form/details), `roles` (+ `rolePermissions`), `vehicleForm`,
   `invoiceForm`, `financeCompanyForm`, `loanForm`, `emi` (dashboard/schedule/
   payment), `freeServicePlans`. `UserRepository` already exposes everything the
   user/role screens need (`list`, `createProfile`, `update`, `deactivate`,
   `setRoles`, `listRoles`, `listPermissions`, `setRolePermissions`), so they are
   mostly view work.
2. **Dashboard aggregation.** `DashboardRepository` counts/sums client-side over
   capped (1000-row) scans. Replace with a `dashboard_summary(p_showroom_id,
   p_from, p_to)` SQL function when the schema PR lands; the snapshot shape in
   `DashboardRepository` is already what the view consumes.
3. **Password-reset deep link.** `ResetPasswordView` expects the recovery
   session created by the Supabase redirect. Add `app_links`/deep-link handling
   to consume `#access_token` (web) and the universal link (iOS/Android).
4. **Backend artefacts are not in this repo.** Supabase migrations/RLS/RPCs
   (`create_sale_transaction`, `record_payment`, `pay_emi`, `open_service_job`,
   `ensure_showroom_accounts`, …) and `google-services.json` /
   `GoogleService-Info.plist` must be supplied per environment; without a
   Firebase config, push stays disabled by design (`NotificationService` logs
   and no-ops).
5. **Tests.** `test/` does not exist; `mocktail` is already a dev dependency.
   Highest-value first: `AuthController` + `SessionController` (permission
   matrix), `SyncService` (queue/conflict), `EmiCalculator`, `AppMenu.visibleFor`.
6. **Web build.** `dart:io` is still imported by `ImageService`/`ExportService`
   (`File`), so `flutter build web` needs those paths guarded (`kIsWeb`) or
   moved behind conditional imports.
