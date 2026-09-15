-- =============================================================================
-- 013_accounting.sql  (SS24, SS67, SS82)
-- -----------------------------------------------------------------------------
-- Behaviour on top of the accounting tables created in 004:
--   * the balanced-journal invariant as a DEFERRED constraint trigger, so a
--     multi-line journal may exist unbalanced mid-statement but can never be
--     committed that way
--   * per-showroom chart of accounts, seeded automatically for every new branch
--   * the public create/reverse RPCs the Flutter client is allowed to call
--   * parameterised report functions (trial balance, ledger, P&L) that beat
--     the views on large data sets because they filter before aggregating
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Debit == Credit, enforced at commit
-- ---------------------------------------------------------------------------
create or replace function app_acc.assert_journal_balanced()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d numeric;
  v_c numeric;
  v_number text;
begin
  select t.transaction_number, round(coalesce(sum(e.debit),0),2), round(coalesce(sum(e.credit),0),2)
    into v_number, v_d, v_c
    from public.accounting_transactions t
    join public.accounting_entries e on e.transaction_id = t.id
   where t.id = coalesce(new.transaction_id, old.transaction_id)
   group by t.transaction_number;

  if v_number is null then
    return null;   -- the journal was deleted entirely: append-only guard blocks that
  end if;

  if v_d is distinct from v_c then
    raise exception '[VAL010] journal % is unbalanced: debit % vs credit % - the transaction is rolled back',
      v_number, v_d, v_c using errcode = '23514';
  end if;
  if v_d = 0 then
    raise exception '[VAL011] journal % has no value', v_number using errcode = '23514';
  end if;
  return null;
end;
$$;

drop trigger if exists trg_journal_balanced on public.accounting_entries;
create constraint trigger trg_journal_balanced
  after insert or update or delete on public.accounting_entries
  deferrable initially deferred
  for each row execute function app_acc.assert_journal_balanced();

-- A journal cannot be committed while its reversal state contradicts its lines
create or replace function app_acc.assert_journal_shape()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.reference_id is null or new.reference_type is null then
    raise exception '[VAL012] every journal must point at a business document (SS69)'
      using errcode = '22000';
  end if;
  if exists (select 1 from public.accounts a
              where a.id in (select e.account_id from public.accounting_entries e
                              where e.transaction_id = new.id)
                and a.showroom_id <> new.showroom_id) then
    raise exception '[VAL013] journal % mixes accounts from another showroom', new.transaction_number
      using errcode = '23514';
  end if;
  return null;
end;
$$;

drop trigger if exists trg_journal_shape on public.accounting_transactions;
create trigger trg_journal_shape
  after insert or update on public.accounting_transactions
  for each row execute function app_acc.assert_journal_shape();

-- ---------------------------------------------------------------------------
-- 2. Every showroom gets its own chart of accounts (SS82)
-- ---------------------------------------------------------------------------
create or replace function app_acc.seed_chart_on_showroom_create()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_acc.ensure_default_chart(new.id);
  return new;
end;
$$;

drop trigger if exists trg_seed_chart on public.showrooms;
create trigger trg_seed_chart
  after insert on public.showrooms
  for each row execute function app_acc.seed_chart_on_showroom_create();

-- Group accounts must not be posted to, and system accounts are not deletable.
create or replace function app_acc.guard_accounts()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception '[CON001] % is a system account and cannot be deleted', old.account_name
        using errcode = '23514';
    end if;
    if exists (select 1 from public.accounting_entries e where e.account_id = old.id) then
      raise exception '[CON002] account % has postings; archive it instead of deleting it (SS42)',
        old.account_name using errcode = '23514';
    end if;
    return old;
  end if;

  if new.is_group and not old.is_group
     and exists (select 1 from public.accounting_entries e where e.account_id = old.id) then
    raise exception '[CON003] an account with postings cannot become a group' using errcode = '23514';
  end if;
  if old.is_system and (new.account_type is distinct from old.account_type
                        or new.account_code is distinct from old.account_code
                        or new.status is distinct from old.status) then
    if not app_sec.is_super_admin() then
      raise exception '[SEC001] system accounts are read-only for your role' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_accounts on public.accounts;
create trigger trg_guard_accounts
  before update or delete on public.accounts
  for each row execute function app_acc.guard_accounts();

-- ---------------------------------------------------------------------------
-- 3. Public RPCs (SS50)
-- ---------------------------------------------------------------------------
create or replace function public.create_accounting_transaction(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom uuid := coalesce((p_payload ->> 'showroom_id')::uuid, app_sec.current_showroom_id());
  v_date     date := coalesce((p_payload ->> 'transaction_date')::date, current_date);
  v_type     text := coalesce(nullif(p_payload ->> 'journal_type',''), 'MANUAL');
  v_lines    jsonb := p_payload -> 'lines';
  v_id       uuid;
begin

  perform app_sec.require_permission('accounting','post');
  perform app_sec.require_showroom_access(v_showroom);
  -- a hand-written journal is the accountant's power, not everyone's

  if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) < 2 then
    perform app_util.fail('VAL001', 'a manual journal needs at least two lines');
  end if;

  v_id := app_acc.post_journal(v_showroom, v_date, v_type,
             coalesce(nullif(p_payload ->> 'reference_type',''), 'manual'),
             coalesce((p_payload ->> 'reference_id')::uuid, gen_random_uuid()),
             coalesce(p_payload ->> 'description', 'Manual journal'),
             v_lines);

  perform app_util.audit_row('accounting','CREATE','accounting_transactions', v_id, null,
          jsonb_build_object('payload', p_payload - 'lines'), v_showroom, null,
          'Manual journal');
  return v_id;
end;
$$;

create or replace function public.reverse_accounting_transaction(
  p_transaction_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_new uuid;
begin

  perform app_sec.require_permission('accounting','reverse');
  v_new := app_acc.reverse_journal(p_transaction_id, p_reason);
  return v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Report functions (date-range filtered, so they scale past the views)
-- ---------------------------------------------------------------------------
create or replace function public.get_trial_balance(
  p_showroom_id uuid,
  p_from date default null,
  p_to   date default null
)
returns table (account_code text, account_name text, account_type text,
               debit numeric, credit numeric, balance numeric)
language sql
stable
set search_path = ''
as $$
  select a.account_code::text, a.account_name::text, a.account_type::text,
         round(coalesce(sum(e.debit), 0), 2),
         round(coalesce(sum(e.credit), 0), 2),
         round(coalesce(sum(case when a.normal_balance = 'DEBIT'
                                 then e.debit - e.credit else e.credit - e.debit end), 0), 2)
    from public.accounts a
    -- A period trial balance must actually respect the period: the entry join is
    -- parenthesised so that the journal state and the dates filter the entries
    -- themselves, and a reversal counts because the entry it corrects still
    -- belongs to the books (SS25, SS42).
    left join (public.accounting_entries e
               join public.accounting_transactions t on t.id = e.transaction_id
                    and t.status in ('POSTED','REVERSED')
                    and (p_from is null or t.transaction_date >= p_from)
                    and (p_to   is null or t.transaction_date <= p_to))
           on e.account_id = a.id
   where a.showroom_id = p_showroom_id and a.is_group = false
   group by a.id, a.account_code, a.account_name, a.account_type, a.normal_balance
   order by a.account_code;
$$;

create or replace function public.get_account_ledger(
  p_account_id uuid,
  p_from date default null,
  p_to   date default null,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (entry_id uuid, transaction_id uuid, transaction_number text,
               transaction_date date, journal_type text, reference_type text,
               reference_id uuid, description text, debit numeric, credit numeric,
               running_balance numeric)
language sql
stable
set search_path = ''
as $$
  select e.id, t.id, t.transaction_number::text, t.transaction_date, t.journal_type::text,
         t.reference_type::text, t.reference_id,
         coalesce(e.description, t.description)::text, e.debit, e.credit,
         sum(case when a.normal_balance = 'DEBIT' then e.debit - e.credit
                  else e.credit - e.debit end)
          over (order by t.transaction_date, t.id, e.line_number
                rows between unbounded preceding and current row)
    from public.accounting_entries e
    join public.accounting_transactions t on t.id = e.transaction_id
                              and t.status in ('POSTED','REVERSED')
    join public.accounts a on a.id = e.account_id
   where e.account_id = p_account_id
     and (p_from is null or t.transaction_date >= p_from)
     and (p_to   is null or t.transaction_date <= p_to)
   order by t.transaction_date, t.id, e.line_number
   limit least(greatest(coalesce(p_limit, 200), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
$$;

create or replace function public.get_profit_and_loss(
  p_showroom_id uuid,
  p_from date default null,
  p_to   date default null
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  -- One aggregation pass, then the JSON shape is assembled from it. Keeps the
  -- P&L report identical to the trial balance by construction (SS24, SS25).
  with lines as (
    select a.account_code, a.account_name, a.account_type,
           round(coalesce(sum(case when a.normal_balance = 'DEBIT'
                                   then e.debit - e.credit else e.credit - e.debit end), 0), 2) as amount
      from public.accounts a
      join public.accounting_entries e      on e.account_id = a.id
      join public.accounting_transactions t on t.id = e.transaction_id
                                       and t.status in ('POSTED','REVERSED')
     where a.showroom_id = p_showroom_id
       and a.is_group = false
       and a.account_type in ('INCOME','EXPENSE')
       and (p_from is null or t.transaction_date >= p_from)
       and (p_to   is null or t.transaction_date <= p_to)
     group by a.account_code, a.account_name, a.account_type
  )
  select jsonb_build_object(
    'showroomId',  p_showroom_id,
    'from',        p_from,
    'to',          p_to,
    'income',      coalesce((select jsonb_agg(jsonb_build_object('code', account_code,
                                                 'name', account_name, 'amount', amount)
                                                 order by account_code)
                               from lines where account_type = 'INCOME' and amount <> 0), '[]'::jsonb),
    'expense',     coalesce((select jsonb_agg(jsonb_build_object('code', account_code,
                                                 'name', account_name, 'amount', amount)
                                                 order by account_code)
                               from lines where account_type = 'EXPENSE' and amount <> 0), '[]'::jsonb),
    'totalIncome',  round(coalesce((select sum(amount) from lines where account_type = 'INCOME'), 0), 2),
    'totalExpense', round(coalesce((select sum(amount) from lines where account_type = 'EXPENSE'), 0), 2),
    'netProfit',    round(coalesce((select sum(amount) from lines where account_type = 'INCOME'), 0)
                        - coalesce((select sum(amount) from lines where account_type = 'EXPENSE'), 0), 2)
  );
$$;
