-- =============================================================================
-- LOCAL-DEVELOPMENT / CI SHIM  (NOT part of `supabase/migrations`)
-- -----------------------------------------------------------------------------
-- Supabase provides the `auth` / `storage` schemas, the `extensions` schema and
-- the `anon` / `authenticated` / `service_role` / `supabase_auth_admin` roles
-- out of the box. A vanilla PostgreSQL server does not, so this file recreates
-- just enough of that contract to let the production migrations be executed and
-- verified on a plain PostgreSQL instance (locally or in CI).
--
-- It is *never* applied to a real Supabase project. `scripts/db_verify.sh`
-- applies it automatically for the local test database.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin nologin noinherit createrole;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_functions_admin') then
    create role supabase_functions_admin nologin noinherit;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. extensions schema (Supabase hosts contrib extensions here)
-- ---------------------------------------------------------------------------
create schema if not exists extensions;

-- Enable only what this PostgreSQL build actually ships with. The production
-- Supabase image provides all of them; the embedded CI build omits contrib.
do $$
declare
  ext text;
begin
  foreach ext in array array['pgcrypto','uuid_ossp','citext','unaccent'] loop
    if exists (select 1 from pg_available_extensions where name = ext) then
      execute format('create extension if not exists %I with schema extensions', ext);
    else
      raise notice 'skipping unavailable extension %', ext;
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. auth schema: minimal contract used by the migrations
-- ---------------------------------------------------------------------------
create schema if not exists auth;

create table if not exists auth.users (
  id              uuid primary key default gen_random_uuid(),
  email           text unique,
  phone           text,
  raw_user_meta_data   jsonb not null default '{}'::jsonb,
  raw_app_meta_data    jsonb not null default '{}'::jsonb,
  encrypted_password   text,
  email_confirmed_at   timestamptz,
  phone_confirmed_at   timestamptz,
  banned_until         timestamptz,
  is_sso_user          boolean not null default false,
  last_sign_in_at      timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- `auth.uid()` – in Supabase this reads the JWT `sub` claim. Locally we mimic it
-- with a transaction-local GUC so tests can `set local request.jwt.claims = ...`.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
           current_setting('request.jwt.claim.sub', true),
           ''
         )::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
           nullif(current_setting('request.jwt.claims', true), ''),
           '{}'
         )::jsonb;
$$;

-- `handle_new_user` in Supabase is installed by the dashboard template; here the
-- migration owns it, so nothing to shim besides the trigger target table above.

-- ---------------------------------------------------------------------------
-- 4. storage schema: Supabase Storage buckets are `storage.buckets` rows and
--    objects are `storage.objects` rows. We recreate the columns the storage
--    policies in 010_storage.sql rely on.
-- ---------------------------------------------------------------------------
create schema if not exists storage;

create table if not exists storage.buckets (
  id                  text primary key,
  name                text not null unique,
  public              boolean not null default false,
  file_size_limit     bigint,
  allowed_mime_types  text[],
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists storage.objects (
  id            uuid primary key default gen_random_uuid(),
  bucket_id     text not null references storage.buckets (id) on delete cascade,
  name          text not null,
  owner         uuid,
  owner_id      uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  last_accessed_at timestamptz,
  metadata      jsonb not null default '{}'::jsonb,
  path_tokens   text[] generated always as (regexp_split_to_array(name, '/')) stored,
  unique (bucket_id, name)
);

alter table storage.buckets enable row level security;
alter table storage.objects enable row level security;

-- Supabase ships these grants: the API roles may reach the storage schema, and
-- the policies created in 010_storage.sql decide which rows they can see.  A
-- local cluster without them fails with "permission denied for schema storage"
-- instead of exercising those policies, which would hide real defects.
grant usage on schema storage to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;
grant all on storage.objects to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Cron shim (Supabase uses pg_cron + the `pg_net` extension for scheduled
--    functions). Provide the schema surface used by 012_reminders.sql.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- pg_cron is unavailable locally: the scheduler calls are wrapped in the
    -- migrations so they no-op instead of failing. Nothing to create here.
    null;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Role grants that Supabase performs by default.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth  to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
