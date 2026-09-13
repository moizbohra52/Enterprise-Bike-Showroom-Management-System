# Engineering notes — state of the app layer

Audited on 2026-09-13 against `main` after PR #2 (app layer + Supabase
migrations) and PR #3 (compile errors / API misuse across services).

## Fixed in this branch

1. **Nested classes (Dart does not allow them) — `lib/` did not compile.**
   * `SupabaseConfig` contained `class StorageBuckets` → hoisted to a
     top-level `StorageBuckets`; the three `SupabaseConfig.StorageBuckets.*`
     call sites (`image_service`, `document_list_view`, `expense_form_view`)
     updated.
   * `ProductFormView` contained `class FileRef` → hoisted as
     `_ProductImageRef`.
2. **`SearchController` name clash with Flutter.** The app's search controller
   and `SearchController` from `material.dart` were both in scope in `TopBar`,
   which makes that reference ambiguous (hard error, not a lint). Renamed to
   `GlobalSearchController` (controller, `top_bar`, `initial_binding`).
3. **Missing global registrations.** `PdfService`, `ExportService` and
   `ImageService` are `Get.find`-ed from the invoice/payment/service views
   (PDF print), the report screen (CSV/Excel/PDF export) and the
   document/expense upload sheets, but `InitialBinding` never registered them →
   those screens threw as soon as they were opened.
4. **Offline customer writes never replayed.** `CustomerController` enqueues
   `customer` operations, while only a `user` handler was registered, so every
   queued write ended up as a
   `"No sync handler registered."` conflict. `CustomerRepository` is now
   registered globally and wired as the `customer` handler; `EntityType.*`
   constants replace the string literals.
5. **Push-token failure could abort sign-in.** `NotificationService.registerToken`
   rethrows on any `device_tokens` error (missing table, RLS), which bubbled out
   of the auth-state listener and skipped `_loadProfile()`. Now logged and
   ignored, so a broken FCM setup cannot lock a user out.
6. **`NotificationService` cold start + web import** (on top of PR #3's
   `kIsWeb`/`TargetPlatform` rewrite): `messaging.getInitialMessage()` is now
   delivered so a tap on a notification when the app was killed still navigates,
   `init()` short-circuits on unsupported platforms, and the leftover `dart:io`
   import is dropped (it is a hard error for `flutter build web`).

## Known gaps (next PRs)

* **Boot assumes a Supabase client exists.** `main()` logs and swallows a
  `Supabase.initialize` failure, but `InitialBinding` then calls
  `AuthService.init()` and `session.bootstrap()`, both of which reach
  `Supabase.instance` → `StateError` → the app dies before the first frame.
  Setting a flag in `main` (e.g. `EnvironmentConfig.backendReady`) and
  returning early from `AuthService.init()` makes the placeholder/offline path
  actually usable.
* **Accent colour changes need a restart.** `AppStateController.lightTheme` /
  `darkTheme` are plain fields (lines 30-31) while `main.dart` only watches
  `themeMode` and `language`, so Settings > Appearance > accent does not
  repaint. Making the two fields `Rx<ThemeData>` and reading `.value` in
  `main.dart` is the whole fix.
* **Dashboard aggregation is client-side.** Counts are exact
  (`CountOption.exact`) but money figures are summed over a bounded 1000-row
  window (`_sumWindow`), so busy showrooms under-report. Replace with a
  `dashboard_summary(p_showroom_id, p_from, p_to)` SQL function in a migration;
  the controller keeps its current shape.
* **Web build.** `ImageService` and `ExportService` still import `dart:io` for
  `File`; those paths need `kIsWeb` branches or conditional imports before
  `flutter build web` succeeds.
* **Sync coverage.** `ShowroomRepository`, `ProductRepository` and
  `InventoryRepository` implement `applySyncOp`, but no flow enqueues those
  entity types yet — register their handlers together with the first offline
  draft screen for each module.
* **No tests.** `mocktail` and `integration_test` are declared, there is no
  `test/` directory. Highest value first: `SessionController.can` /
  `PermissionService` matrix, `SyncService` queue + conflict paths,
  `EmiCalculator`, and a widget smoke test that boots `AppPages.pages` with a
  mocked `SupabaseService`.
* **Push notifications** additionally need per-platform Firebase config
  (`google-services.json`, `GoogleService-Info.plist`) and the
  `device_tokens` table before `NotificationService.registerToken` stores
  anything.

## Verification done here

No Dart/Flutter SDK is available in the environment these changes were made in,
so `flutter analyze` / `flutter test` were **not** run. Checks performed
instead, scripted over the whole tree: every `import` path resolves; every
referenced project symbol is declared in the imported files; every
`Get.find<T>()` / `GetView<T>` target is registered by `InitialBinding` or a
module binding; no nested class declarations and no references to removed APIs
remain. A real toolchain run (`flutter pub get && flutter analyze`) should be
the first CI step.
