# Engineering notes — state of the app layer

Audited on 2026-09-12, against `main` after PR #2 (`runnable app layer +
Supabase migrations`).

## Fixed here

1. **Nested classes (Dart does not allow them).**
   * `SupabaseConfig` contained `class StorageBuckets` → hoisted to a
     top-level `StorageBuckets`; the three `SupabaseConfig.StorageBuckets.*`
     call sites (`image_service`, `document_list_view`, `expense_form_view`)
     updated.
   * `ProductFormView` contained `class FileRef` → hoisted as
     `_ProductImageRef`.
   Both were hard compile errors, so `lib/` did not compile before this.
2. **`NotificationService` used APIs that do not exist**:
   `defaultTargetPlatformValue.*`, `FirebasePlatform.isAvailable`,
   `Firebase.appExists(...)`, `messaging.onIosActivate` / `onIosRefresh`.
   Replaced with `kIsWeb` + `TargetPlatform.*`, `Firebase.apps.isEmpty` and
   `getInitialMessage()`. The unused `dart:io` import was dropped (it breaks
   `flutter_build_web`-style web compiles).
3. **`SearchController` name clash** with Flutter's own `SearchController`
   (`material.dart`), which made the reference in `TopBar` ambiguous → the app
   class is now `GlobalSearchController` (controller, `top_bar`,
   `initial_binding`).
4. **Missing global registrations.** `PdfService`, `ExportService` and
   `ImageService` are `Get.find`-ed from the invoice/payment/service views,
   the report screen and the upload sheets, but `InitialBinding` never
   registered them → those screens threw at open time. Registered permanently
   in `lib/routes/initial_binding.dart`.
5. **Offline customer writes never replayed.** `CustomerController` enqueues
   `customer` operations, but only a `user` handler was registered, so every
   queued customer write ended up as
   `"No sync handler registered."` conflicts. `CustomerRepository` is now
   registered globally and wired as the `customer` handler (`EntityType.*`
   constants used instead of string literals).
6. **Push-token failure could abort the sign-in flow** — `registerToken`
   rethrows on any `device_tokens` error (missing table, RLS), which used to
   bubble out of the auth-state listener and skip `_loadProfile()`. Now
   logged and ignored, so a broken FCM setup cannot lock a user out.

## Known gaps (next PRs)

* **Boot assumes a Supabase client.** `InitialBinding` calls `AuthService.init()`
  and `session.bootstrap()`; `main()` swallows a `Supabase.initialize` failure.
  If initialization ever fails (malformed URL, blocked network at startup),
  the binding throws and the app dies before the first frame. A
  `EnvironmentConfig.backendReady` flag (set in `main`) plus an early return in
  `AuthService.init()` would make the placeholder path airtight.
* **Accent colour changes need a restart.** `AppStateController.lightTheme` /
  `darkTheme` are plain fields, while `main.dart` only watches `themeMode` and
  `language` — Settings > Appearance > accent therefore applies after a
  restart. Making the two themes `Rx<ThemeData>` (and reading `.value` in
  `main.dart`) fixes it without touching the rest of the state.
* **Dashboard aggregation is client-side.** KPIs count rows exactly but sum
  money over a bounded 1000-row window (`_sumWindow`); busy showrooms will
  under-report. Replace with a `dashboard_summary(p_showroom_id, p_from, p_to)`
  SQL function in a migration and keep the controller shape unchanged.
* **Web build.** `ImageService` and `ExportService` import `dart:io` for
  `File`; on web those need `kIsWeb` branches or conditional imports.
* **Sync coverage.** `ShowroomRepository`, `ProductRepository` and
  `InventoryRepository` already implement `applySyncOp`, but no flow enqueues
  those entity types yet — handlers should be registered together with the
  first offline draft screen for each module.
* **No tests.** `mocktail` and `integration_test` are declared but there is no
  `test/` directory. Highest value first: `SessionController.can` / permission
  matrix, `SyncService` queue + conflict paths, `EmiCalculator`, and a widget
  smoke test that boots `AppPages.pages` with a mocked `SupabaseService`.
* **Push notifications** additionally need per-platform Firebase config and the
  `device_tokens` table (see `supabase/migrations`) before
  `NotificationService.registerToken` stores anything.

## Verification done for this PR

No Dart/Flutter SDK is available in the environment used for these changes, so
`flutter analyze` / `flutter test` were **not** run. Checks performed instead:
every `import` path resolves; every referenced project symbol is declared in
the file that imports it; `Get.find<T>()` / `GetView<T>` targets are all
registered by either `InitialBinding` or a module binding; nested class
declarations and the non-existent Firebase/`defaultTargetPlatform` APIs are
gone. A `flutter analyze` on a real toolchain should be the first CI step.
