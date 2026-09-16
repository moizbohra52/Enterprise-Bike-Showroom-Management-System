# Engineering notes — state of the app layer

Audited on 2026-09-13 against `main` after PR #2 (app layer + Supabase
migrations) and PR #3 (compile errors / API misuse across services).

## Fixed 2026-09-15 — `flutter build apk` (`assembleDebug` exit code 1)

Reported from Android Studio on Windows; the toolchain itself was fine, the
tree did not compile. Two independent causes were fixed.

### 1. Dart compile errors (these fail `:app:compileFlutterBuildDebug`)

| Where | Error | Fix |
| --- | --- | --- |
| `services/image_service.dart` | `typedef StorageServiceRef = StorageService;` — `StorageService` was never imported (`Type 'StorageService' not found`) | import `services/storage_service.dart` |
| `features/expenses/views/expense_details_view.dart`, `features/payments/views/payment_details_view.dart`, `features/sales/views/sale_details_view.dart` | `AppButtonVariant.error` — the enum declares `filled, outlined, text, danger, tonal` | `AppButtonVariant.danger` |
| `common/models/permission_model.dart`, `features/notifications/models/notification_model.dart` | `fromJson` / `copyWith` pass `updatedAt:` but the constructors only forwarded `super.id, super.createdAt` (`No named parameter with the name 'updatedAt'`) | add `super.updatedAt` (the pattern every other `BaseModel` subclass already uses) |
| `core/errors/error_mapper.dart` (2×) | `UnknownException(details: error)` — `details` is an *optional positional*, not a named parameter | new `UnknownException.withDetails(dynamic)` constructor |
| `features/accounting/models/accounting_models.dart` | `required this.amount = 0` and `required this.narration = ''` — a required parameter cannot have a default value (`default_value_on_required_parameter`) | drop `required`, keep the default |
| `features/accounting/controllers/accounting_controller.dart` | `addLine()` built `JournalLineModel(side:, amount:)` without the `required accountId` | `accountId` now defaults to `''`, which is exactly what `manual_entry_view` already expects (`line.accountId.isEmpty ? null : ...`) |
| `common/widgets/app_filter_bar.dart` | `const AppFilterBar({this.children})` with a non-nullable `List<Widget> children` and no default (`missing_default_value_for_parameter`) | `this.children = const <Widget>[]` |
| `features/users/bindings/users_binding.dart` | `UserFormController(Get.find(), Get.find())` — the controller takes three positional parameters (`repository, session, authService`) (`Too few positional arguments`) | pass `Get.find<SessionController>()` and `Get.find<AuthService>()` too; both are global, and the imports were reordered to match the other bindings |

Also de-duplicated two classes that the package exported twice under the same
name — an ambiguous-import error waiting for the first file that imports both
paths:

* `core/helpers/id_generator.dart` and `core/utils/id_generator.dart` both
  declared `IdGenerator` (with different members). `core/utils` is now the only
  implementation (`uuid`, `localUuid`, `shortId`, `token`); the helpers file is
  an `export` shim.
* `core/helpers/emi_calculator.dart` and `core/utils/emi_calculator.dart` both
  declared `EmiCalculator` (one with `monthlyEmi`/`totalEmi` + `method:`, the
  other with `calculateEmi`/`buildSchedule` + `interestType:`). Everything lives
  in `core/utils` now — `monthlyEmi`, `totalEmi` and `installment` were added
  there — and the helpers file is an `export` shim, so
  `sale_controller.dart` keeps working unchanged.

### 2. Android build configuration (`android/`)

* **`compileSdk` floor of 35.** `compileSdk = flutter.compileSdkVersion` is 34
  on Flutter 3.22–3.24, while the AndroidX/Firebase/plugin artifacts that pub
  resolves now ship `minCompileSdk = 35` in their AAR metadata →
  `Execution failed for task ':app:checkDebugAarMetadata'`. Now
  `maxOf(flutter.compileSdkVersion, 35)`, so a newer Flutter SDK still wins.
  `android.suppressUnsupportedCompileSdk=35` silences AGP 8.6's "tested up to 34"
  warning.
* **`minSdk` floor of 23** (`maxOf(flutter.minSdkVersion, 23)`) for the same
  reason: transitive `uses-sdk` minimums keep creeping up and fail the manifest
  merger.
* **Java/Kotlin target 11 → 17.** AGP 8 already requires JDK 17 to run and
  AndroidX publishes Java 17 bytecode; Java and Kotlin targets must match or
  Gradle fails with "Inconsistent JVM-target compatibility detected".
* **Gradle heap 8G → 4G** (`MaxMetaspaceSize` 4G → 1G). 8G makes the daemon swap
  on a 16 GB dev machine next to Android Studio + an emulator, which shows up as
  an absurdly slow build or a daemon that disappears mid-build.
* `pubspec.yaml`: `intl: 0.19.0` → `intl: '>=0.19.0 <0.21.0'`.
  `flutter_localizations` pins `intl` to an exact version per Flutter SDK
  (0.19.0 through 3.24, 0.20.x from 3.27), so the hard pin made
  `flutter pub get` unsolvable on any newer SDK.
* `.github/workflows/ci.yml` (new): `flutter pub get` → `flutter analyze`
  (errors only) → `flutter test` (once a `test/` directory exists) →
  `flutter build apk --debug` with placeholder credentials, APK uploaded as an
  artifact. This is the "real toolchain run" the previous audit called for.

### Still unverified

No Dart/Flutter SDK exists in the environment these fixes were made in, so
`flutter analyze` has still not been run. The errors above were found with
`scripts/dart_verify.py` (new, no SDK required — the Dart equivalent of
`scripts/db_verify.py`): it parses all 246 libraries and reports unresolved
imports, duplicate top-level declarations, unknown members/enum values, wrong
or missing arguments, `required` parameters with defaults, optional parameters
of non-nullable type without a default, non-nullable fields no constructor
initialises, `const` calls to non-const constructors and `super.x` formals the
super-class does not accept. It is deliberately conservative — anything needing
real type inference (type mismatches, override compatibility) is skipped — so a
clean run is necessary, not sufficient:

```bash
python3 scripts/dart_verify.py          # exit code 1 when it finds something
```

If `assembleDebug` still fails, the interesting part of the log is the
`* What went wrong:` block (and, for Dart, the first `Error:` line above it) —
that is what pins the remaining cause.

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
remain.

The 2026-09-15 pass extended that to the classes of error a symbol check cannot
see, and the checks now live in the repo as `scripts/dart_verify.py` (one
command, no SDK, exit code 1 on findings) instead of being throw-away scripts:

* **members** — every `Type.member`, `Enum.value`, `Type.named(...)` reference
  resolves against the declaration's own body plus its project super-type chain
  and the `extension X on Type` members in scope;
* **call signatures** — every constructor/method call is checked against the
  parsed parameter list (unknown named parameter, missing `required` named
  parameter, too many / too few positional arguments);
* **declaration legality** — `required` + default value, optional parameters of
  non-nullable type without a default, non-nullable non-`late` fields no
  constructor initialises, top-level names declared in two libraries;
* **const / super formals** — `const Foo(...)` against a non-const constructor,
  and `super.x` formals against the project super-class constructor.

`scripts/dart_verify.py` reports clean on the current tree (it was validated
against a fixture with one planted error of each kind first).

`flutter analyze` is now wired into CI (`.github/workflows/ci.yml`), which is
the real check.


## Fixed 2026-09-16 — second compile-error sweep (same failure, deeper causes)

The classes below are all `:app:compileFlutterBuildDebug` failures that the
first sweep's symbol/signature checks could not see, because they are about
*types* and about *external* APIs rather than about names.

### 1. `Obx(child: …)` — GetX's `Obx` has no `child` parameter

`Obx` takes one **positional** builder: `Obx(() => …)`. Forty call sites in
34 views were written as `Obx(child: …)`, which is
`No named parameter with the name 'child'`. All rewritten to `Obx(() => …)`.

### 2. Rx values used where plain Dart values are required (26 sites)

`RxBool` is not a `bool` and `RxList<T>` is not a `List<T>`, so these are
argument-type errors:

```dart
AppButton(isLoading: controller.saving, …)          // RxBool -> bool
AppButton(onPressed: _saving ? null : _submit, …)   // RxBool in a condition
AppTable<UserModel>(items: controller.items, …)     // RxList -> List
```

Every one now reads `.value`, which also keeps the `Obx` rebuild dependency
that the raw field access would have lost. Because this class of error is
invisible to a name-based check, it is now a repo script:

```bash
python3 scripts/dart_rx_check.py    # exit code 1 when it finds something
```

It resolves Rx-typed fields/getters per class, `controller.<field>` inside
`GetView<T>` / `GetWidget<T>` / `GetX<T>`, Rx-typed locals, and the declared
type of each named-parameter label in the project; reads with `.value` and
element access (`x[i].y`) are skipped as correct. Validated with a planted
regression before being trusted.

### 3. `const` constructors on widgets that own mutable state (8 views)

A const constructor cannot live in a class with initialised instance fields,
and `false.obs` / `TextEditingController()` are not const expressions anyway.
`CustomerFormView`, `StockAdjustView`, `StockInView`, `StockTransferView`,
`PaymentFormView`, `ProductFormView`, `SupplierFormView` and `ShowroomFormView`
all hold Rx/`TextEditingController`/`GlobalKey`/map state, so `const` was
dropped from those constructors and from their `GetPage` entries in
`lib/routes/app_pages.dart`.

### 4. `GetMiddleware.priority` changed nullability between get 4.6 and 4.7

`pubspec.yaml` allows `get: ^4.6.6`, which resolves to **4.7.3** today. In
4.6.x `priority` is `final int? priority`; in 4.7.x it is a non-nullable
`final int priority` (verified against upstream
`lib/get_navigation/src/routes/route_middleware.dart`). `int? get priority`
therefore compiles on one and fails on the other, while `int get priority` is a
legal override of **both** (covariant return). Both middlewares now use the
non-nullable form. `redirect(String? route)` and the `GetPage` parameters the
router uses (`name`, `page`, `binding`, `middlewares`) are unchanged upstream.

### Also audited in this pass

* `image_picker` (`ImagePicker().pickImage(source:, imageQuality:)`,
  `pickMultiImage`), `hive` (`initFlutter`, `isBoxOpen`, `openBox<dynamic>`),
  `connectivity_plus` 6.x (`checkConnectivity()` /
  `onConnectivityChanged` both yield `List<ConnectivityResult>`),
  `excel` 4.x (`Excel.createExcel()`, `Sheet.appendRow(List<CellValue>)`,
  `TextCellValue`/`IntCellValue`/`DoubleCellValue`/`BoolCellValue`),
  `csv` 6.x (`Csv().encode`), `dio` (`BaseOptions`, `Options`, `CancelToken`,
  `FormData`), `device_info_plus`, `firebase_messaging`, `permission_handler`,
  `supabase_flutter` (`FileOptions`, `FileObject`, `SearchOptions`,
  `AuthResponse`, `UserAttributes`).
* `Get.*` surface used by the app: `find`, `put`, `lazyPut`, `toNamed`,
  `offAllNamed`, `back`, `until`, `isRegistered`, `parameters`, `currentRoute`,
  `context`, plus `GetMaterialApp`'s parameters — all present upstream.
* Unimplemented abstract members and incompatible `@override` signatures across
  all 432 project types: scanned, **zero** findings (the scan was validated
  against planted abstract method/getter/`abstract` declarations first). This
  one is not shipped as a script because it needs the type lattice that
  `flutter analyze` already has.
