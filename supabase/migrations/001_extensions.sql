-- =============================================================================
-- 001_extensions.sql
-- -----------------------------------------------------------------------------
-- Purpose : extensions, internal schemas, shared domains (database-side
--           validation primitives) and the tiny utility functions every later
--           migration depends on.
-- Depends : none (runs first).  Must be safe to re-run.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Extensions (only what the server actually ships with; Supabase ships all)
-- -----------------------------------------------------------------------------
create schema if not exists extensions;

do $$
declare
  ext text;
begin
  foreach ext in array array['pgcrypto', 'uuid_ossp', 'citext', 'unaccent', 'pg_trgm'] loop
    if exists (select 1 from pg_available_extensions where name = ext) then
      execute format('create extension if not exists %I with schema extensions', ext);
    else
      raise notice '001_extensions: % is not available on this server, skipping', ext;
    end if;
  end loop;
end
$$;

-- -----------------------------------------------------------------------------
-- Internal schemas
--   app_util : pure helpers (norm, validation, audit plumbing)
--   app_sec  : SECURITY DEFINER authorisation primitives used by RLS
--   app_gen  : document numbering (invoice / sale / payment numbers)
--   app_acc  : double-entry bookkeeping primitives
-- They are deliberately NOT `public` so PostgREST never exposes them directly;
-- the client only ever calls the documented RPCs in `public`.
-- -----------------------------------------------------------------------------
create schema if not exists app_util;
create schema if not exists app_sec;
create schema if not exists app_gen;
create schema if not exists app_acc;

comment on schema app_util is 'Internal utilities: normalisation, validation, audit helpers.';
comment on schema app_sec  is 'Authorisation primitives consumed by RLS policies. Never exposed to the API.';
comment on schema app_gen  is 'Business document numbering (per showroom, per document type).';
comment on schema app_acc  is 'Double-entry accounting engine.';

-- -----------------------------------------------------------------------------
-- Domains = single source of truth for column-level validation (§39, §67)
-- The Flutter form validators mirror these regexes 1:1 - keep both in sync.
-- -----------------------------------------------------------------------------
create domain app_util.money
  as numeric(14, 2)
  check (value >= 0 and value < 100000000000);

create domain app_util.signed_money
  as numeric(14, 2)
  check (value > -100000000000 and value < 100000000000);

create domain app_util.percentage
  as numeric(6, 3)
  check (value >= 0 and value <= 100);

create domain app_util.rate
  as numeric(7, 4)
  check (value >= 0 and value <= 100);

create domain app_util.positive_qty
  as numeric(12, 3)
  check (value > 0);

create domain app_util.signed_qty
  as numeric(12, 3)
  check (value <> 0);

create domain app_util.odometer
  as integer
  check (value >= 0 and value <= 9999999);

create domain app_util.year
  as integer
  check (value between 1980 and extract(year from now())::int + 20);

create domain app_util.email
  as text
  check (value ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' and length(value) <= 255);

-- Indian mobile/landline tolerant: 10 digits, optional +91 and optional separators.
create domain app_util.phone
  as text
  check (value ~ '^\+?[0-9][0-9 \-]{7,14}$' and length(replace(replace(value, ' ', ''), '-', '')) between 8 and 15);

create domain app_util.pincode
  as text
  check (value ~ '^[1-9][0-9]{5}$');

-- GSTIN: 15 characters = 2 state digits + 5 letters + 4 digits + entity type
-- letter + check digit + the fixed 'Z' + station code (SS67).
create domain app_util.gstn
  as text
  check (value ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z][Z][1-9A-Z]$');

-- Permanent Account Number (10 chars)
create domain app_util.pan
  as text
  check (value ~ '^[A-Z]{5}[0-9]{4}[A-Z]$');

-- Chassis / VIN: 11-17 alphanumerics, no I/O/Q, excludes dash used in short form
create domain app_util.chassis_number
  as text
  check (value ~ '^[A-HJ-NPR-Z0-9]{11,17}$');

create domain app_util.engine_number
  as text
  check (value ~ '^[A-Z0-9][A-Z0-9\-\/]{3,29}$');

-- Registration number: MH12AB1234 / MH-12-AB-1234 / DL10VC2024
create domain app_util.registration_number
  as text
  check (value ~ '^[A-Z]{2}[0-9]{2}[A-Z]{0,3}[0-9]{3,4}$|^[A-Z]{2}-[0-9]{2}-[A-Z]{1,3}-[0-9]{3,4}$|^[A-Z]{2}[0-9]{1,2}[A-Z]{1,4}[0-9]{1,4}[A-Z]{0,2}$');

create domain app_util.hex_color
  as text
  check (value ~ '^#[0-9A-Fa-f]{6}$');

-- Business codes (showroom/role/brand/supplier) are case-insensitive identifiers
-- that users read in upper case, so both cases are accepted; the seeds store the
-- canonical UPPER_SNAKE form and every lookup that must be case-insensitive uses
-- lower() with its own index.
create domain app_util.slug
  as text
  check (value ~ '^[A-Za-z0-9][A-Za-z0-9._-]{1,47}$');

create domain app_util.file_size
  as bigint
  check (value >= 0 and value <= 268435456);  -- 256 MiB hard ceiling

-- -----------------------------------------------------------------------------
-- Status vocabulary. Text + CHECK (instead of ENUM types) is intentional:
-- adding a state later is a constraint swap, not a global type migration, and
-- PostgREST clients receive plain strings that map 1:1 onto Dart enums.
-- -----------------------------------------------------------------------------
create table if not exists app_util.status_vocab (
  table_name text    not null,
  column_name text   not null,
  value      text    not null,
  display    text    not null,
  sort_order smallint not null default 0,
  primary key (table_name, column_name, value)
);
comment on table app_util.status_vocab is
  'Documentation/lookup mirror of the CHECK constraints below; also drives Dart codegen (tool/status_vocab.dart).';

-- -----------------------------------------------------------------------------
-- Generic helpers
-- -----------------------------------------------------------------------------

-- updated_at maintenance (used by 007_triggers.sql on every mutable table).
create or replace function app_util.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  -- bump the optimistic-concurrency revision when the table carries one
  if to_jsonb(new) ? 'revision' then
    new.revision := coalesce(old.revision, 0) + 1;
  end if;
  return new;
end;
$$;

-- Trim + collapse inner whitespace, nullify empty strings.
create or replace function app_util.nullif_blank(in_value text)
returns text
language sql
immutable
as $$
  select nullif(btrim(regexp_replace(coalesce(in_value, ''), '\s+', ' ', 'g')), '');
$$;

-- Normalise a phone number to digits with an optional leading '+'.
create or replace function app_util.normalise_phone(in_value text)
returns text
language sql
immutable
as $$
  select nullif(btrim(regexp_replace(coalesce(in_value, ''), '[^0-9+]', '', 'g')), '');
$$;

-- Uppercase-free storage of emails is avoided on purpose: only the *lookup*
-- index is lower() based so the original spelling stays visible to users.
create or replace function app_util.normalise_email(in_value text)
returns text
language sql
immutable
as $$
  select nullif(lower(btrim(coalesce(in_value, ''))), '');
$$;

-- GSTIN / PAN / registration / chassis / engine are business identifiers:
-- always stored upper-case without separators where safe.
create or replace function app_util.upper_no_space(in_value text)
returns text
language sql
immutable
as $$
  select upper(nullif(btrim(regexp_replace(coalesce(in_value, ''), '\s+', '', 'g')), ''));
$$;

-- A compact money rounder shared by every calculation path so the client and
-- server always agree on half-up, two decimals.
create or replace function app_util.round_money(in_value numeric)
returns numeric
language sql
immutable
as $$
  select round(coalesce(in_value, 0)::numeric, 2);
$$;

-- Derive a machine code from a human name: 'Royal Enfield' -> 'ROYAL-ENFIELD'.
create or replace function app_util.code_from_name(in_value text)
returns text
language sql
immutable
as $$
  select upper(
           nullif(
             regexp_replace(
               regexp_replace(coalesce(in_value, ''), '[^A-Za-z0-9]+', '-', 'g'),
               '^-+|-+$', '', 'g'),
             '')
         );
$$;

-- ISO-8601 date key used by the daily reporting roll-ups.
create or replace function app_util.day_key(in_value date)
returns text
language sql
immutable
as $$
  select to_char(in_value, 'YYYY-MM-DD');
$$;

-- -----------------------------------------------------------------------------
-- Row-level error surface used by the RPC layer: raises P0001 with a stable
-- SQLSTATE so Flutter can map codes onto friendly messages.
-- -----------------------------------------------------------------------------
create or replace function app_util.fail(in_code text, in_message text)
returns void
language plpgsql
as $$
begin
  raise exception using
    errcode = case
                when in_code in ('AUTH001','AUTH002')      then 'P0001'
                when in_code = 'SEC001'                    then '42501'
                when in_code = 'VAL001'                    then '22000'
                when in_code = 'NOT001'                    then 'P0002'
                when in_code = 'CON001'                    then '23505'
                else 'P0001'
              end,
    message = format('[%s] %s', in_code, in_message),
    hint    = 'See lib/core/errors/app_exception.dart for the client mapping.';
end;
$$;

-- Extracts the machine code out of an app_util.fail() message.
create or replace function app_util.error_code(in_message text)
returns text
language sql
immutable
as $$
  select coalesce((regexp_match(in_message, '^\[([A-Z]{3}[0-9]{3})\]'))[1], 'ERR000');
$$;

-- NOTE: RLS safety net lives in the verifier (scripts/db_verify.py fails if any
-- public table is created without RLS) plus the explicit ALTERs in
-- 009_rls.sql; that is preferable to an event trigger the API role cannot own.

-- ---------------------------------------------------------------------------
-- Extension-aware index creation.
-- Full-text / trigram indexes are a *performance* nicety: they must never be a
-- hard dependency for a database that lacks the contrib module. Every
-- gin_trgm_ops index in this project is created through this procedure, so the
-- migrations apply identically on Supabase (pg_trgm present) and on a stripped
-- PostgreSQL (skipped with a notice).
-- ---------------------------------------------------------------------------
-- (dropped first so the object type can never be stale on a re-run)
drop function if exists app_util.create_optional_index(text, text);
create or replace procedure app_util.create_optional_index(
  in_ddl       text,
  in_extension text default null
)
language plpgsql
as $$
begin
  if in_extension is not null
     and not exists (select 1 from pg_available_extensions where name = in_extension) then
    raise notice 'optional index skipped, extension % unavailable', in_extension;
    return;
  end if;
  execute in_ddl;
exception when others then
  -- A malformed index DDL is a real bug: surface it instead of swallowing it.
  raise exception 'app_util.create_optional_index failed for [%]: %', in_ddl, sqlerrm;
end;
$$;
