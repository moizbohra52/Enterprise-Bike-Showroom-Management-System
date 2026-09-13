-- 001_extensions.sql
-- Extensions required by the Enterprise Bike Showroom schema.
-- Idempotent: safe to re-run.
--
-- pgcrypto   -> gen_random_uuid() for primary keys
-- pg_trgm    -> trigram indexes for the global search (customers, products)
-- btree_gist -> exclusion-friendly indexes for date-range overlaps (warranty)

create schema if not exists extensions;

create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pg_trgm" with schema extensions;
create extension if not exists "btree_gist" with schema extensions;

-- Single source of truth for new primary keys.
create or replace function public.new_id()
returns uuid
language sql
volatile
as $$
  select gen_random_uuid();
$$;

comment on function public.new_id() is
  'Primary key generator (uuid v4) used as the default for every table.';
