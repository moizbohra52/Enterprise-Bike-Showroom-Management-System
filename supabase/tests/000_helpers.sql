-- =============================================================================
-- 000_helpers.sql  -  test harness (local / CI only, never a migration)
-- -----------------------------------------------------------------------------
-- Tiny assertion library plus the identity switch the RLS tests need. Kept in
-- its own `test` schema so nothing here is reachable through PostgREST.
--
-- The helpers are SECURITY INVOKER on purpose: they must run the SQL under the
-- same role the test switched to, otherwise an RLS test would silently pass by
-- testing the privileges of the table owner.
-- =============================================================================

create schema if not exists test;
grant usage on schema test to public;
-- the helpers are called while the session is `set role authenticated`, so a
-- security-invoker helper reading test state needs the same rights as the caller
alter default privileges in schema test grant all on tables    to public;
alter default privileges in schema test grant all on functions to public;

create or replace function test.ok(p_cond boolean, p_label text)
returns void
language plpgsql
as $$
begin
  if p_cond is distinct from true then
    raise exception 'TEST FAILED: %  (condition evaluated to %)', p_label, coalesce(p_cond::text, 'null')
      using errcode = 'P0001';
  end if;
  raise notice '  ok - %', p_label;
end;
$$;

-- anycompatible* so a domain (app_util.money) compares against a plain numeric
create or replace function test.eq(p_actual anycompatible, p_expected anycompatible, p_label text)
returns void
language plpgsql
as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'TEST FAILED: % - expected %, got %', p_label, p_expected, p_actual
      using errcode = 'P0001';
  end if;
  raise notice '  ok - % (= %)', p_label, coalesce(p_actual::text, 'null');
end;
$$;

create or replace function test.eq_num(p_actual numeric, p_expected numeric, p_label text)
returns void
language plpgsql
as $$
begin
  if round(coalesce(p_actual, -9.99), 2) <> round(coalesce(p_expected, -9.99), 2) then
    raise exception 'TEST FAILED: % - expected %, got %', p_label, p_expected, p_actual
      using errcode = 'P0001';
  end if;
  raise notice '  ok - % (= %)', p_label, p_actual;
end;
$$;

-- Runs p_sql and requires it to fail with the given app error code (the
-- `[ABC123]` prefix produced by app_util.fail / the RAISEs in the RPCs).
create or replace function test.raises(p_sql text, p_code text default null, p_label text default null)
returns text
language plpgsql
as $$
declare
  v_code text;
begin
  execute p_sql;
  raise exception 'TEST FAILED: % - expected an error% but the statement succeeded',
    coalesce(p_label, p_sql), case when p_code is null then '' else ' ' || p_code end
    using errcode = 'P0001';
exception
  when others then
    if sqlerrm like 'TEST FAILED%' then
      raise;   -- an assertion inside the tested block failed: that is a real failure
    end if;
    v_code := (regexp_match(sqlerrm, '^\[([A-Z]{3}[0-9]{3})\]'))[1];
    if p_code is not null and v_code is distinct from p_code then
      raise exception 'TEST FAILED: % - expected [%] but got %: %',
        coalesce(p_label, p_sql), p_code, coalesce(v_code, sqlstate), sqlerrm
        using errcode = 'P0001';
    end if;
    raise notice '  ok - % rejected (%)', coalesce(p_label, 'statement'), coalesce(v_code, sqlstate);
  return coalesce(v_code, sqlstate);
end;
$$;

-- Identity switch. The role itself is changed by the test file with a top-level
-- `set role authenticated;` so the switch is visible to every statement that
-- follows; this only plants the JWT claims Supabase would have planted.
create or replace function test.as(p_auth uuid default null, p_showroom uuid default null)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub',  coalesce(p_auth::text, ''), false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  perform set_config('request.jwt.claims',
                     coalesce(json_build_object('sub', p_auth, 'role', 'authenticated')::text, '{}'),
                     false);
  perform set_config('app.showroom_id', coalesce(p_showroom::text, ''), false);
end;
$$;

create or replace function test.anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', 'anon', false);
  perform set_config('request.jwt.claims', '{"role":"anon"}', false);
  perform set_config('app.showroom_id', '', false);
end;
$$;

-- The ids every later test file needs. Stored in a one-row table because a test
-- file is a fresh transaction and cannot hold session variables.
create table if not exists test.env (
  k text primary key,
  v text
);

create or replace function test.remember(p_key text, p_value text)
returns void language sql as $$
  insert into test.env (k, v) values (p_key, p_value)
  on conflict (k) do update set v = excluded.v;
$$;

create or replace function test.uuid_of(p_key text)
returns uuid language sql as $$
  select v::uuid from test.env where k = p_key;
$$;

create or replace function test.num_of(p_key text)
returns numeric language sql as $$
  select v::numeric from test.env where k = p_key;
$$;

create or replace function test.txt_of(p_key text)
returns text language sql as $$
  select v from test.env where k = p_key;
$$;

-- The money invariant every flow must leave behind: no journal may be unbalanced
-- and no document header may disagree with its lines. Called at the end of the
-- business-flow tests so a regression anywhere fails loudly.
create or replace function test.assert_ledger_is_sane()
returns void
language plpgsql
security invoker
as $$
declare
  v_bad integer;
begin
  select count(*) into v_bad
    from public.accounting_transactions t
    join public.accounting_entries e on e.transaction_id = t.id
   group by t.id
  having round(coalesce(sum(e.debit), 0), 2) <> round(coalesce(sum(e.credit), 0), 2);
  perform test.ok(coalesce(v_bad, 0) = 0, 'every posted journal balances debit = credit');

  -- Freight/insurance style charges live on the header only (they are never a
  -- line), so the footing rule is: sum(lines) + other_charges = total.
  select count(*) into v_bad
    from public.invoices i
    join public.invoice_items ii on ii.invoice_id = i.id
   group by i.id, i.total_amount, i.other_charges
  having round(sum(ii.total_amount), 2) + i.other_charges <> i.total_amount;
  perform test.ok(coalesce(v_bad, 0) = 0, 'every invoice header foots against its lines');

  select count(*) into v_bad
    from public.sales s
    join public.sale_items si on si.sale_id = s.id
   group by s.id, s.total_amount
  having round(sum(si.total_amount), 2) + s.other_charges - s.exchange_value <> s.total_amount;
  perform test.ok(coalesce(v_bad, 0) = 0, 'every sale header foots against its lines');

  select count(*) into v_bad
    from public.inventory i
    join public.sales s on s.id = i.allocated_sale_id
   where i.status = 'SOLD' and s.status not in ('CONFIRMED','DELIVERED');
  perform test.ok(coalesce(v_bad, 0) = 0, 'no unit is SOLD without a confirmed sale');

  select count(*) into v_bad
    from public.payments p
    where p.status = 'COMPLETED'
      and p.invoice_id is not null
      and p.allocated_amount > p.amount;
  perform test.ok(coalesce(v_bad, 0) = 0, 'no payment allocates more than it received');

  select count(*) into v_bad
    from public.customers c
    where c.lifetime_value < 0;
  perform test.ok(coalesce(v_bad, 0) = 0, 'customer lifetime value is never negative');
end;
$$;

-- A readable "what does the API see" helper used by the RLS tests.
create or replace function test.visible_count(p_table text)
returns bigint
language plpgsql
security invoker
as $$
declare v bigint;
begin
  execute format('select count(*) from public.%I', p_table) into v;
  return v;
end;
$$;

-- End-of-file grants: everything created above must be callable under the
-- switched roles the tests use.
grant all on all tables    in schema test to public;
grant all on all sequences in schema test to public;
grant execute on all functions in schema test to public;
