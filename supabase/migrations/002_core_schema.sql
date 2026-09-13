-- 002_core_schema.sql
-- Tenancy + identity: showrooms, application users, roles and permissions.
-- Every business table added later carries showroom_id and points here.

create table if not exists public.showrooms (
  id              uuid primary key default public.new_id(),
  name            text        not null,
  code            text        not null unique,
  address         text        not null default '',
  city            text        not null default '',
  state           text        not null default '',
  pincode         text        not null default '',
  phone           text        not null default '',
  email           text        not null default '',
  gst_number      text        not null default '',
  pan_number      text        not null default '',
  invoice_prefix  text        not null default 'INV',
  logo_url        text,
  status          text        not null default 'active'
                    check (status in ('active', 'inactive', 'closed')),
  settings        jsonb       not null default '{}'::jsonb,
  is_deleted      boolean     not null default false,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.showrooms is
  'Tenant root. A user may be assigned to one or more showrooms.';

create table if not exists public.users (
  id              uuid primary key default public.new_id(),
  auth_user_id    uuid        not null unique
                    references auth.users (id) on delete cascade,
  showroom_id     uuid
                    references public.showrooms (id) on delete set null,
  name            text        not null default '',
  email           text        not null,
  phone           text        not null default '',
  status          text        not null default 'active'
                    check (status in ('active', 'inactive', 'suspended')),
  avatar_url      text,
  last_login_at   timestamptz,
  is_deleted      boolean     not null default false,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.users is
  'Application profile for an auth.users row. Role + showroom assignment is '
  'what grants access; the profile alone grants nothing.';

create index if not exists users_email_idx on public.users (lower(email));
create index if not exists users_showroom_idx on public.users (showroom_id);

create table if not exists public.roles (
  id              uuid primary key default public.new_id(),
  name            text        not null unique,
  description     text        not null default '',
  is_system_role  boolean     not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.roles is
  'RBAC roles. SUPER ADMIN implicitly holds every permission (see '
  'public.is_super_admin()).';

create table if not exists public.permissions (
  id              uuid primary key default public.new_id(),
  module          text        not null,
  action          text        not null,
  description     text        not null default '',
  created_at      timestamptz not null default now(),
  unique (module, action)
);

comment on table public.permissions is
  'Atomic module.action grants, e.g. (sales, create) -> ''sales.create''.';

create table if not exists public.user_roles (
  id              uuid primary key default public.new_id(),
  user_id         uuid        not null
                    references public.users (id) on delete cascade,
  role_id         uuid        not null
                    references public.roles (id) on delete cascade,
  created_at      timestamptz not null default now(),
  unique (user_id, role_id)
);

create table if not exists public.role_permissions (
  id              uuid primary key default public.new_id(),
  role_id         uuid        not null
                    references public.roles (id) on delete cascade,
  permission_id   uuid        not null
                    references public.permissions (id) on delete cascade,
  created_at      timestamptz not null default now(),
  unique (role_id, permission_id)
);

create table if not exists public.brands (
  id              uuid primary key default public.new_id(),
  name            text        not null unique,
  status          text        not null default 'active'
                    check (status in ('active', 'inactive')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
