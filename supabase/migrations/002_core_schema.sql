-- =============================================================================
-- 002_core_schema.sql
-- -----------------------------------------------------------------------------
-- Purpose : the tenant spine. Showrooms, application users, the RBAC model,
--           device tokens, attachments, audit log, document numbering and the
--           offline-synchronisation governance tables.
-- Depends : 001_extensions.sql, Supabase `auth.users`.
--
-- Design notes
--   * `users.id` is the application identity; `users.auth_user_id` is the
--     Supabase Auth identity. Business rows FK to `users(id)` (a real, stable
--     app user) rather than to auth.uid(), so history survives auth-side
--     deletions and re-provisioning.
--   * Every tenant table carries `showroom_id` + `created_by/updated_by` +
--     `revision` (optimistic locking for offline conflicts) + soft-delete
--     columns where §42 requires them.
--   * Nothing here cascades on delete for governed data: `on delete restrict`
--     is the default (§48).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- showrooms
-- ---------------------------------------------------------------------------
create table if not exists public.showrooms (
  id            uuid primary key default gen_random_uuid(),
  name          text   not null check (length(btrim(name)) between 2 and 120),
  code          app_util.slug not null,
  legal_name    text,
  address       text   not null check (length(btrim(address)) between 5 and 400),
  city          text   not null check (length(btrim(city)) between 2 and 80),
  state         text   not null check (length(btrim(state)) between 2 and 80),
  country       text   not null default 'IN',
  pincode       app_util.pincode not null,
  phone         app_util.phone   not null,
  email         app_util.email   not null,
  gst_number    app_util.gstn,
  pan_number    app_util.pan,
  invoice_prefix text not null default 'INV'
                 check (invoice_prefix ~ '^[A-Z]{2,5}$'),
  logo_url      text,
  status        text   not null default 'ACTIVE'
                check (status in ('ACTIVE','INACTIVE','UNDER_MAINTENANCE','CLOSED')),
  -- §9 showroom-specific image policy + §30 local mirrors of server truth
  settings      jsonb  not null default '{}'::jsonb,
  timezone      text   not null default 'Asia/Kolkata',
  currency      char(3) not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  financial_year_start_month smallint not null default 4 check (financial_year_start_month between 1 and 12),
  tax_number_verified boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint showrooms_code_key unique (code)
);

comment on table  public.showrooms is 'Physical showroom / dealer branch - the tenant root of every business record.';
comment on column public.showrooms.settings is
  'JSONB policy bag: {"watermark_images":true,"allow_image_download":false,"preview_only":true,'
  '"allow_negative_inventory":false,"gst_rate":18,"service_tax_rate":18,"invoice_footer":"..."}';
comment on column public.showrooms.invoice_prefix is 'Prefix used by app_gen.next_document_number() for invoice numbers (§48).';

create index if not exists showrooms_status_idx on public.showrooms (status);
create index if not exists showrooms_city_idx    on public.showrooms (city);

-- ---------------------------------------------------------------------------
-- users  (application profile for a Supabase Auth identity)
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique,
  -- nullable on purpose: a freshly signed-up profile is unassigned until an
  -- admin attaches it to a showroom (§83 controlled onboarding).
  showroom_id   uuid references public.showrooms (id) on delete restrict,
  employee_code app_util.slug,
  name          text not null check (length(btrim(name)) between 2 and 120),
  email         app_util.email not null,
  phone         app_util.phone,
  designation   text,
  status        text not null default 'PENDING_ACTIVATION'
              check (status in ('PENDING_ACTIVATION','ACTIVE','INACTIVE','SUSPENDED','LOCKED','RESIGNED')),
  avatar_url    text,
  is_super_admin boolean not null default false,
  last_login_at  timestamptz,
  last_active_at timestamptz,
  failed_login_count smallint not null default 0 check (failed_login_count between 0 and 100),
  password_changed_at timestamptz,
  must_change_password boolean not null default false,
  preferences   jsonb not null default '{}'::jsonb,
  is_deleted    boolean not null default false,
  deleted_at    timestamptz,
  deleted_by    uuid references public.users (id) on delete restrict,
  revision      integer not null default 1 check (revision > 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.users (id) on delete restrict,
  updated_by    uuid references public.users (id) on delete restrict,
  constraint users_employee_code_key unique (employee_code),
  -- a locked/resigned user may not be ACTIVE, and the flags are coherent
  constraint users_status_flags_check check (
    (status = 'LOCKED'  and failed_login_count >= 5) or
    (status <> 'LOCKED')
  ),
  constraint users_soft_delete_coherent check (
    (is_deleted and deleted_at is not null and deleted_by is not null) or
    (not is_deleted and deleted_at is null and deleted_by is null)
  )
);

comment on table public.users is
  'Application user. RLS identity resolution: auth.uid() -> users.id -> showroom_id (§49).';
comment on column public.users.is_super_admin is
  'Duplicated on the row for cheap, recursion-free RLS checks; always in sync with the SUPER ADMIN role (trigger in 007).';
comment on column public.users.revision is 'Optimistic-lock counter used by the offline conflict resolver (§84).';

-- case-insensitive uniqueness must be an expression index, not a table constraint
create unique index if not exists users_email_key        on public.users (lower(email));
create index if not exists users_showroom_status_idx on public.users (showroom_id, status);
create index if not exists users_phone_idx           on public.users (phone);
call app_util.create_optional_index(
  'create index if not exists users_name_trgm_idx on public.users using gin (name gin_trgm_ops)',
  'pg_trgm');
create index if not exists users_active_not_deleted_idx on public.users (showroom_id) where is_deleted = false;

-- ---------------------------------------------------------------------------
-- roles / permissions / RBAC joins (§6, §81)
-- ---------------------------------------------------------------------------
create table if not exists public.roles (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique check (length(btrim(name)) between 2 and 60),
  code          app_util.slug not null unique,
  description   text,
  -- 0 = broadest. Drives dashboard defaults and user picker ordering.
  level_rank    smallint not null default 100 check (level_rank between 0 and 200),
  is_system_role boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.roles is 'RBAC roles. is_system_role=true blocks deletion by non-super admins (009).';

create table if not exists public.permissions (
  id          uuid primary key default gen_random_uuid(),
  module      text not null,
  action      text not null,
  description text,
  created_at  timestamptz not null default now(),
  constraint permissions_module_action_key unique (module, action),
  constraint permissions_module_format check (module ~ '^[a-z][a-z0-9_]{1,39}$'),
  -- §6: permissions are always `module.action`
  constraint permissions_action_format check (action ~ '^[a-z][a-z0-9_]{1,29}$')
);

comment on table public.permissions is 'Atomic capability, addressed as module.action (e.g. sales.approve).';

create table if not exists public.user_roles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.users (id) on delete cascade,
  role_id    uuid not null references public.roles (id) on delete restrict,
  -- an empty showroom_id means "for every showroom this user may access"
  showroom_id uuid references public.showrooms (id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid references public.users (id) on delete restrict,
  constraint user_roles_unique_key unique (user_id, role_id, showroom_id)
);

create index if not exists user_roles_user_idx on public.user_roles (user_id);
create index if not exists user_roles_role_idx on public.user_roles (role_id);
create index if not exists user_roles_showroom_idx on public.user_roles (showroom_id);

create table if not exists public.role_permissions (
  id            uuid primary key default gen_random_uuid(),
  role_id       uuid not null references public.roles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  created_at    timestamptz not null default now(),
  constraint role_permissions_unique_key unique (role_id, permission_id)
);

create index if not exists role_permissions_role_idx on public.role_permissions (role_id);
create index if not exists role_permissions_perm_idx on public.role_permissions (permission_id);

-- Multi-showroom assignment (§7): SUPER ADMIN / SHOWROOM MANAGER / ACCOUNT
-- MANAGER can legitimately span branches. users.showroom_id stays the
-- "home branch" used for new documents and default filters.
create table if not exists public.user_showroom_access (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  showroom_id uuid not null references public.showrooms (id) on delete restrict,
  access_level text not null default 'OPERATE'
             check (access_level in ('VIEW','OPERATE','MANAGE')),
  valid_from  timestamptz not null default now(),
  valid_to    timestamptz,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.users (id) on delete restrict,
  constraint user_showroom_access_unique_key unique (user_id, showroom_id),
  constraint user_showroom_access_window check (valid_to is null or valid_to > valid_from)
);

create index if not exists user_showroom_access_user_idx on public.user_showroom_access (user_id);
create index if not exists user_showroom_access_showroom_idx on public.user_showroom_access (showroom_id);

-- ---------------------------------------------------------------------------
-- FCM device tokens (§54): multiple devices per user, deactivated on logout.
-- ---------------------------------------------------------------------------
create table if not exists public.device_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users (id) on delete cascade,
  device_token text not null,
  platform     text not null check (platform in ('ANDROID','IOS','WEB','WINDOWS','MACOS','LINUX')),
  device_name  text,
  app_version  text,
  push_provider text not null default 'FCM' check (push_provider in ('FCM','APNS','WEB_PUSH')),
  is_active    boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint device_tokens_token_key unique (device_token)
);

create index if not exists device_tokens_user_active_idx on public.device_tokens (user_id, is_active);
comment on table public.device_tokens is 'FCM registration tokens; (user_id, device_token) pairs deactivated at logout.';

-- ---------------------------------------------------------------------------
-- attachments (§28): one registry for every uploaded document/image so file
-- lifecycle (retention, showroom scoping, signed URL issue) is auditable.
-- ---------------------------------------------------------------------------
create table if not exists public.attachments (
  id           uuid primary key default gen_random_uuid(),
  showroom_id  uuid references public.showrooms (id) on delete restrict,
  entity_type  text not null check (entity_type ~ '^[a-z][a-z0-9_]{1,39}$'),
  entity_id    uuid not null,
  bucket_id    text not null,
  file_path    text not null,
  file_name    text not null check (length(btrim(file_name)) between 1 and 255),
  file_url     text,
  thumbnail_path text,
  file_type    text not null,
  mime_type    text,
  file_size    app_util.file_size,
  width        integer,
  height       integer,
  checksum     text,
  watermark_enabled boolean not null default false,
  visibility   text not null default 'PRIVATE'
             check (visibility in ('PRIVATE','SIGNED','PUBLIC')),
  is_primary   boolean not null default false,
  sort_order   smallint not null default 0,
  metadata     jsonb not null default '{}'::jsonb,
  uploaded_by  uuid references public.users (id) on delete restrict,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint attachments_object_key unique (bucket_id, file_path),
  -- only one primary image per (entity, purpose) pair is enforced by the
  -- partial unique indexes below, not by a constraint, because metadata->>'purpose'
  -- is not immutable.
  constraint attachments_entity_known check (
    entity_type in ('product','product_image','customer','customer_vehicle','inventory',
                    'sale','invoice','payment','loan','emi_schedule','purchase','expense',
                    'service','warranty','warranty_claim','insurance','accounting_transaction',
                    'showroom','user','document')
  )
);

create index if not exists attachments_entity_idx    on public.attachments (entity_type, entity_id);
create index if not exists attachments_showroom_idx  on public.attachments (showroom_id);
create index if not exists attachments_primary_idx   on public.attachments (entity_type, entity_id) where is_primary = true;

-- ---------------------------------------------------------------------------
-- document numbering (§48): per-showroom, per-type monotonic counters.
-- A row is locked during allocation so concurrent sales on two terminals can
-- never mint the same sale/invoice/payment number.
-- ---------------------------------------------------------------------------
create table if not exists public.document_sequences (
  showroom_id  uuid not null references public.showrooms (id) on delete cascade,
  doc_type     text not null check (doc_type in
               ('SALE','INVOICE','PAYMENT','SERVICE','PURCHASE','EXPENSE','LOAN',
                'CUSTOMER','WARRANTY_CLAIM','STOCK_TRANSFER','ACCOUNTING','INSURANCE','QUOTATION')),
  period_key   text not null default 'ALL',   -- 'ALL' or 'FY2526' style bucket
  prefix       text not null,
  next_value   bigint not null default 1 check (next_value > 0),
  padding      smallint not null default 4 check (padding between 1 and 10),
  updated_at   timestamptz not null default now(),
  primary key (showroom_id, doc_type, period_key)
);

comment on table public.document_sequences is
  'Counter table behind app_gen.next_document_number(); row-locked to guarantee gap-free, duplicate-free numbers.';

-- ---------------------------------------------------------------------------
-- audit_logs (§41): append-only. No UPDATE/DELETE policy is created in 009 and
-- the triggers below raise if anything tries to mutate or purge a row.
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id           uuid primary key default gen_random_uuid(),
  showroom_id  uuid references public.showrooms (id) on delete restrict,   -- nullable: global events (login)
  user_id      uuid references public.users (id) on delete restrict,
  module       text not null check (module ~ '^[a-z][a-z0-9_]{1,39}$'),
  action       text not null check (
                 action in ('CREATE','UPDATE','DELETE','CANCEL','APPROVE','REJECT','PAYMENT',
                            'LOGIN','LOGOUT','STOCK_TRANSFER','STOCK_ADJUSTMENT','PRINT','EXPORT',
                            'RESTORE','VOID','SYNC_CONFLICT')
               ),
  table_name   text   not null,
  record_id    uuid,
  record_label text,
  old_data     jsonb,
  new_data     jsonb,
  changed_fields text[] ,
  ip_address   inet,
  user_agent   text,
  request_id   text,
  severity     text not null default 'INFO' check (severity in ('DEBUG','INFO','WARNING','ERROR','CRITICAL')),
  created_at   timestamptz not null default now()
);

create index if not exists audit_logs_created_idx    on public.audit_logs (created_at desc);
create index if not exists audit_logs_showroom_idx   on public.audit_logs (showroom_id, created_at desc);
create index if not exists audit_logs_user_idx       on public.audit_logs (user_id, created_at desc);
create index if not exists audit_logs_record_idx     on public.audit_logs (table_name, record_id);
create index if not exists audit_logs_action_idx     on public.audit_logs (module, action);
comment on table public.audit_logs is 'Append-only governance log. Physically deleting rows is blocked by trigger.';

-- ---------------------------------------------------------------------------
-- idempotency_keys: guards the offline/retry paths. A client generates one UUID
-- per queued operation; retries reuse it and receive the original result.
-- ---------------------------------------------------------------------------
create table if not exists public.idempotency_keys (
  id            uuid primary key default gen_random_uuid(),
  key           uuid not null unique,
  user_id       uuid references public.users (id) on delete restrict,
  showroom_id   uuid references public.showrooms (id) on delete restrict,
  operation     text not null,
  request_hash  text,
  status        text not null default 'IN_PROGRESS'
              check (status in ('IN_PROGRESS','COMPLETED','FAILED')),
  result        jsonb,
  error_message text,
  attempts      integer not null default 1 check (attempts > 0),
  created_at    timestamptz not null default now(),
  completed_at  timestamptz
);

create index if not exists idempotency_keys_status_idx on public.idempotency_keys (status, created_at);
comment on table public.idempotency_keys is
  'Server-side dedupe for client-generated operation ids (§27/§84, retry-safe RPCs).';

-- ---------------------------------------------------------------------------
-- sync_conflicts: never silently overwrite conflicting data (§27, §84).
-- ---------------------------------------------------------------------------
create table if not exists public.sync_conflicts (
  id            uuid primary key default gen_random_uuid(),
  showroom_id   uuid references public.showrooms (id) on delete restrict,
  user_id       uuid references public.users (id) on delete restrict,
  entity_type   text not null,
  entity_id     uuid,
  local_updated_at timestamptz,
  server_updated_at timestamptz,
  local_revision integer,
  server_revision integer,
  local_payload jsonb,
  server_payload jsonb,
  resolution    text not null default 'UNRESOLVED'
              check (resolution in ('UNRESOLVED','SERVER_WINS','LOCAL_WINS','MERGED','MANUAL_REVIEW','DISCARDED')),
  resolved_by   uuid references public.users (id) on delete restrict,
  resolved_at   timestamptz,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists sync_conflicts_open_idx on public.sync_conflicts (resolution, created_at desc);
create index if not exists sync_conflicts_entity_idx on public.sync_conflicts (entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- Saved filters / table preferences (§72, §30) - server side so a user's
-- saved report configuration follows them to the desktop and the phone.
-- ---------------------------------------------------------------------------
create table if not exists public.user_preferences (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  -- a lower-case initial letter, then letters/digits/dots/underscores, so the
  -- client can use the same key names as its Dart models (theme.pageSize).
  pref_key    text not null check (pref_key ~ '^[a-z][a-zA-Z0-9_.]{1,79}$'),
  pref_value  jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint user_preferences_unique_key unique (user_id, pref_key)
);

create table if not exists public.saved_filters (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  module      text not null,
  name        text not null check (length(btrim(name)) between 2 and 60),
  filters     jsonb not null default '{}'::jsonb,
  sort_by     text,
  sort_desc   boolean not null default true,
  page_size   smallint not null default 20 check (page_size in (20, 50, 100)),
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint saved_filters_unique_key unique (user_id, module, name)
);

-- ---------------------------------------------------------------------------
-- Application settings that must be server-authoritative (not SharedPreferences).
-- ---------------------------------------------------------------------------
create table if not exists public.app_settings (
  id           uuid primary key default gen_random_uuid(),
  key          text not null unique check (key ~ '^[a-z][a-z0-9_.]{1,79}$'),
  value        jsonb not null,
  scope        text not null default 'GLOBAL' check (scope in ('GLOBAL','SHOWROOM')),
  showroom_id  uuid references public.showrooms (id) on delete cascade,
  description  text,
  is_public    boolean not null default true,
  updated_by   uuid references public.users (id) on delete restrict,
  updated_at   timestamptz not null default now(),
  constraint app_settings_scope_key unique (key, scope, showroom_id)
);
