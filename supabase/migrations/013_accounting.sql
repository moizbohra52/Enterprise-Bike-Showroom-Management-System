-- 013_accounting.sql
-- Double-entry ledger: chart of accounts, balanced journal entries and the
-- three RPCs the app calls (ensure_showroom_accounts,
-- create_accounting_transaction, account_ledger).

create table if not exists public.accounts (
  id            uuid primary key default public.new_id(),
  showroom_id   uuid references public.showrooms (id) on delete cascade,
  code          text not null,
  name          text not null,
  type          text not null
                  check (type in ('asset', 'liability', 'equity', 'income',
                                  'expense')),
  sub_type      text not null default '',
  parent_id     uuid references public.accounts (id) on delete set null,
  is_system     boolean not null default false,
  status        text not null default 'active'
                  check (status in ('active', 'inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- Spec naming kept as generated aliases for reports/views.
  account_code  text generated always as (code) stored,
  account_name  text generated always as (name) stored,
  unique (code, showroom_id)
);

-- Table names follow the Flutter models (JournalEntryModel reads
-- `journal_entry_id`; AccountingRepository queries `journal_entries`).
create table if not exists public.journal_entries (
  id             uuid primary key default public.new_id(),
  showroom_id    uuid not null references public.showrooms (id),
  entry_number   text not null unique,
  entry_date     date not null default current_date,
  narration      text not null default '',
  source_module  text not null default 'manual',
  source_id      uuid,
  total_debit    numeric(14,2) not null default 0,
  total_credit   numeric(14,2) not null default 0,
  status         text not null default 'posted'
                   check (status in ('draft', 'posted', 'reversed')),
  created_by     uuid references public.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (total_debit = total_credit)
);

create table if not exists public.journal_lines (
  id                uuid primary key default public.new_id(),
  journal_entry_id  uuid not null
                      references public.journal_entries (id)
                      on delete cascade,
  account_id        uuid not null references public.accounts (id),
  side              text not null check (side in ('debit', 'credit')),
  amount            numeric(14,2) not null check (amount >= 0),
  notes             text not null default '',
  created_at        timestamptz not null default now()
);

-- Spec naming (docs/SPECIFICATION.md section 46) kept as views so reports
-- written against accounting_transactions / accounting_entries keep working.
create or replace view public.accounting_transactions as
select * from public.journal_entries;

create or replace view public.accounting_entries as
select id,
       journal_entry_id as transaction_id,
       account_id,
       side,
       amount,
       notes as description,
       created_at
  from public.journal_lines;

create index if not exists journal_lines_entry_idx
  on public.journal_lines (journal_entry_id);
create index if not exists journal_lines_account_idx
  on public.journal_lines (account_id);
create index if not exists journal_entries_showroom_date_idx
  on public.journal_entries (showroom_id, entry_date desc);

alter table public.accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

drop policy if exists accounts_select on public.accounts;
create policy accounts_select on public.accounts
  for select to authenticated
  using (showroom_id is null or public.can_access_showroom(showroom_id));

drop policy if exists accounts_write on public.accounts;
create policy accounts_write on public.accounts
  for all to authenticated
  using (public.has_permission('accounting', 'edit'))
  with check (public.has_permission('accounting', 'create'));

drop policy if exists journal_entries_tenant on public.journal_entries;
create policy journal_entries_tenant on public.journal_entries
  for all to authenticated
  using (public.can_access_showroom(showroom_id))
  with check (public.can_access_showroom(showroom_id));

drop policy if exists journal_lines_all on public.journal_lines;
create policy journal_lines_all on public.journal_lines
  for all to authenticated
  using (exists (
           select 1 from public.journal_entries t
            where t.id = journal_entry_id
              and public.can_access_showroom(t.showroom_id)))
  with check (exists (
           select 1 from public.journal_entries t
            where t.id = journal_entry_id
              and public.can_access_showroom(t.showroom_id)));

-- Default chart of accounts for a showroom (spec section 82).
create or replace function public.ensure_showroom_accounts(p_showroom_id uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  created integer := 0;
  rows_added integer;
  tmpl record;
begin
  if not public.can_access_showroom(p_showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;

  for tmpl in
    select * from (values
      ('1000', 'Cash',               'asset',     'current'),
      ('1010', 'Bank',               'asset',     'current'),
      ('1100', 'Customer Receivable','asset',     'receivable'),
      ('1200', 'Inventory',          'asset',     'inventory'),
      ('2000', 'Supplier Payable',   'liability', 'payable'),
      ('2100', 'Tax Payable',        'liability', 'tax'),
      ('2200', 'Loan Payable',       'liability', 'loan'),
      ('3000', 'Owner Equity',       'equity',    'capital'),
      ('4000', 'Sales Revenue',      'income',    'sales'),
      ('4100', 'Service Revenue',    'income',    'service'),
      ('4200', 'Interest Income',    'income',    'other'),
      ('5000', 'Purchase',           'expense',   'cogs'),
      ('5100', 'Discount',           'expense',   'discount'),
      ('5200', 'Salary Expense',     'expense',   'salary'),
      ('5300', 'Rent Expense',       'expense',   'rent'),
      ('5400', 'Marketing Expense',  'expense',   'marketing'),
      ('5900', 'Other Expense',      'expense',   'other')
    ) as t(code, name, type, sub_type)
  loop
    insert into public.accounts
      (showroom_id, code, name, type, sub_type, is_system)
    values
      (p_showroom_id, tmpl.code, tmpl.name, tmpl.type, tmpl.sub_type, true)
    on conflict (code, showroom_id) do nothing;
    get diagnostics rows_added = row_count;
    created := created + rows_added;
  end loop;

  return created;
end;
$$;

-- Posts a balanced journal entry. `lines` is
-- [{account_id, side, amount, notes}, ...] (JournalLineModel.toJson()).
create or replace function public.create_accounting_transaction(
  showroom_id uuid,
  lines jsonb,
  entry_date date default current_date,
  narration text default '',
  source_module text default 'manual',
  source_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  txn_id     uuid;
  line       jsonb;
  total_debit  numeric := 0;
  total_credit numeric := 0;
  amount     numeric;
  side       text;
begin
  if not public.can_access_showroom(showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;
  if not public.has_permission('accounting', 'create') then
    raise exception 'FORBIDDEN: accounting.create required' using errcode = '42501';
  end if;
  if lines is null or jsonb_array_length(lines) < 2 then
    raise exception 'VALIDATION: a journal entry needs at least two lines'
      using errcode = '22023';
  end if;

  for line in select * from jsonb_array_elements(lines) loop
    side := lower(coalesce(line ->> 'side', ''));
    amount := coalesce((line ->> 'amount')::numeric, 0);
    if side not in ('debit', 'credit') or amount <= 0 then
      raise exception 'VALIDATION: every line needs a side and a positive amount'
        using errcode = '22023';
    end if;
    if side = 'debit' then
      total_debit := total_debit + amount;
    else
      total_credit := total_credit + amount;
    end if;
  end loop;

  if total_debit <> total_credit then
    raise exception 'VALIDATION: entry is unbalanced (% debit vs % credit)',
                    total_debit, total_credit
      using errcode = '22023';
  end if;

  insert into public.journal_entries
    (showroom_id, entry_number, entry_date, narration, source_module,
     source_id, total_debit, total_credit, status, created_by)
  values
    (showroom_id, public.next_document_number(showroom_id, 'JV'),
     coalesce(entry_date, current_date), coalesce(narration, ''),
     coalesce(source_module, 'manual'), source_id,
     total_debit, total_credit, 'posted', public.current_user_id())
  returning id into txn_id;

  for line in select * from jsonb_array_elements(lines) loop
    insert into public.journal_lines
      (journal_entry_id, account_id, side, amount, notes)
    values
      (txn_id,
       nullif(line ->> 'account_id', '')::uuid,
       lower(line ->> 'side'),
       (line ->> 'amount')::numeric,
       coalesce(line ->> 'notes', ''));
  end loop;

  return (
    select jsonb_build_object(
             'id', t.id,
             'entry_number', t.entry_number,
             'entry_date', t.entry_date,
             'narration', t.narration,
             'source_module', t.source_module,
             'status', t.status,
             'total_debit', t.total_debit,
             'total_credit', t.total_credit,
             'journal_lines', coalesce(
               (select jsonb_agg(
                         jsonb_build_object('id', e.id,
                                            'account_id', e.account_id,
                                            'account_name', a.name,
                                            'account_code', a.code,
                                            'side', e.side,
                                            'amount', e.amount,
                                            'notes', e.notes)
                         order by e.created_at)
                  from public.journal_lines e
                  join public.accounts a on a.id = e.account_id
                 where e.journal_entry_id = t.id), '[]'::jsonb)
           )
      from public.journal_entries t
     where t.id = txn_id
  );
end;
$$;

-- Account ledger with a running balance.
create or replace function public.account_ledger(
  p_account_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.has_permission('accounting', 'view') then
    raise exception 'FORBIDDEN: accounting.view required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(row_to_json(ledger)), '[]'::jsonb)
    into result
    from (
      select e.id,
             t.entry_number,
             t.entry_date,
             t.narration,
             e.side,
             e.amount,
             sum(case when e.side = 'debit' then e.amount else -e.amount end)
               over (order by t.entry_date, e.created_at) as balance
        from public.journal_lines e
        join public.journal_entries t on t.id = e.journal_entry_id
       where e.account_id = p_account_id
         and t.status = 'posted'
       order by t.entry_date desc, e.created_at desc
       limit greatest(coalesce(p_limit, 100), 1)
    ) ledger;

  return result;
end;
$$;

grant execute on function public.ensure_showroom_accounts(uuid) to authenticated;
grant execute on function public.create_accounting_transaction(
  uuid, jsonb, date, text, text, uuid) to authenticated;
grant execute on function public.account_ledger(uuid, integer) to authenticated;
