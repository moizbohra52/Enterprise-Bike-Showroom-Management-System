# Enterprise Bike Showroom Management System

Multi-showroom bike dealership ERP — **Flutter + GetX + Supabase** (mobile, web,
desktop from one codebase). Full product and architecture spec:
[`docs/SPECIFICATION.md`](docs/SPECIFICATION.md). Current wiring status:
[`docs/ROADMAP.md`](docs/ROADMAP.md).

## Modules

Auth & session · showrooms · users & roles · products & brands · inventory
(stock-in, transfer, adjust) · customers & vehicles (360 views) · sales with EMI ·
billing/invoices · payments & receipts · finance & loans · purchases & suppliers ·
expenses with approvals · double-entry accounting · service job cards · free
service · warranty & claims · insurance · reminders · notifications · global
search · reports (CSV/Excel/PDF export) · documents · audit log · settings.

## Requirements

* Flutter **3.22+** (Dart 3.4+)
* A Supabase project (Postgres + Auth + Storage + Realtime) with the schema,
  RLS policies and RPC functions described in the spec
* Optional: Firebase project for push notifications (`google-services.json` /
  `GoogleService-Info.plist`)

## Run

```bash
flutter pub get

# configure the backend per environment (never commit secrets)
flutter run \
  --dart-define=ENV=development \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<public anon key>
```

Without `SUPABASE_URL`/`SUPABASE_ANON_KEY` the app still boots: it starts in
**offline mode** (login disabled, writes would queue in Hive) — useful for
widget work and reviews. See `.env.example` for the full variable list.

Release builds: `flutter build apk|web|windows --release` with
`--dart-define=ENV=production` (placeholder values are rejected at runtime).

## Structure

```
lib/
  main.dart            entry point: AppBootstrap.init() -> runApp
  app.dart             GetMaterialApp (theme, locale, routes)
  routes/              app_routes (names), app_pages (route table),
                       app_bootstrap (infrastructure + global DI + sync handlers)
  config/              theme, environment, Supabase/storage config
  core/                enums, constants, utils, validators, errors, network
  services/            supabase, local db, connectivity, sync, auth, push,
                       images, pdf, export, api
  common/              shared widgets, layouts, RouteGuard, models
  features/<module>/   bindings · controllers · models · repositories · views
```

Navigation goes through `AppRoutes` constants; protected pages are wrapped in
`RouteGuard(permission: ...)`, and UI-level permission checks use
`AppPermissionView` / `SessionController.can`.
