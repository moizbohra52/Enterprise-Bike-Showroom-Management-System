# Enterprise Bike Showroom Management System

Multi-showroom bike dealership ERP — **Flutter + GetX + Supabase** (Android,
iOS, Windows and web from one codebase). Product and architecture spec:
[`docs/SPECIFICATION.md`](docs/SPECIFICATION.md); engineering status and
follow-ups: [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Modules

Auth & session · showrooms · users, roles & permissions · products & brands ·
inventory (stock-in, transfer, adjust) · customers & vehicles (360 views) ·
sales with EMI · billing/invoices · payments & receipts · finance & loans ·
purchases & suppliers · expenses with approvals · double-entry accounting ·
service job cards · free service · warranty & claims · insurance · reminders ·
notifications · global search · reports (CSV/Excel/PDF) · documents · audit
log · settings.

## Requirements

* Flutter **3.22+** (Dart 3.4+)
* A Supabase project (Postgres + Auth + Storage + Realtime)
* Optional: a Firebase app per platform for push notifications
  (`google-services.json`, `GoogleService-Info.plist`)

## Setup

```bash
flutter pub get

# 1. database: apply the migrations in order (CLI or psql)
supabase db push                # or: psql "$DB_URL" -f supabase/migrations/001_extensions.sql ...

# 2. app: inject the project credentials at build time (never commit them)
flutter run \
  --dart-define=ENV=development \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<public anon key>
```

Without `SUPABASE_URL`/`SUPABASE_ANON_KEY` the app still boots and the UI is
fully navigable: development builds fall back to placeholder credentials, and
every remote call fails with a mapped `AppException` instead of crashing.
Staging/production builds refuse to start without real values. See
`.env.example` for the full variable list.

Release builds: `flutter build apk|web|windows --release` with
`--dart-define=ENV=production`.

## Android build notes

* AGP 8 runs on **JDK 17** — Android Studio's embedded JDK is fine; a plain
  `JAVA_HOME` pointing at JDK 8/11 is not. Java and Kotlin targets are both 17
  in `android/app/build.gradle.kts`.
* `compileSdk` is `maxOf(flutter.compileSdkVersion, 35)` and `minSdk` is
  `maxOf(flutter.minSdkVersion, 23)`: the AndroidX/Firebase/plugin artifacts
  pub resolves today declare `minCompileSdk`/`minSdkVersion` above what Flutter
  3.22–3.24 defaults to, which otherwise fails
  `:app:checkDebugAarMetadata` or the manifest merger. A newer Flutter SDK still
  wins (the `maxOf` only raises the floor).
* Building against API 35 for the first time needs that platform installed:
  `sdkmanager "platforms;android-35"` or `flutter doctor --android-licenses`.
* `intl` is a range, not a pin — `flutter_localizations` pins it to an exact
  version per Flutter SDK, so pinning it in `pubspec.yaml` breaks `pub get` on
  every other SDK.
* CI (`.github/workflows/ci.yml`) runs `flutter pub get`, `flutter analyze`
  (errors fail, lints do not yet) and `flutter build apk --debug` on every push
  and pull request. Run those locally before pushing.
* `python3 scripts/dart_verify.py` is the no-toolchain fallback: it statically
  checks imports, members, call signatures and declaration legality across
  `lib/` and exits non-zero on findings. `flutter analyze` is still the real
  check; this one runs where no Flutter SDK exists.

When a build fails, the interesting part of the log is the `* What went wrong:`
block (for Dart errors, the first `Error:` line above it). Get it with
`flutter build apk --debug --stacktrace` rather than reading the Gradle summary.

## Layout

```
lib/
  main.dart            boot: prefs -> Hive -> Supabase -> Firebase -> state
  routes/              app_routes (names) · app_pages (route table) ·
                       app_middleware (auth + permission guards) ·
                       initial_binding (global services, session, sync)
  config/              theme, environment, Supabase/storage config
  core/                enums, constants, utils, validators, errors, network
  services/            supabase, local db, connectivity, sync, auth, push,
                       images, pdf, export, api, storage
  common/              shared widgets, app shell/layouts, models
  features/<module>/   bindings · controllers · models · repositories · views
supabase/migrations/   ordered SQL: schema, indexes, functions, triggers,
                       roles/permissions, RLS, storage, reporting views
```

Navigation uses `AppRoutes` constants only. Protected pages declare their
`*.view` permission in `app_pages.dart`; inside a page, per-action visibility
uses `AppPermissionView` or `SessionController.can`. Offline writes go through
`SyncService` (Hive queue) and are replayed by the repository that owns each
entity table.
