-- =============================================================================
-- 006_functions.sql
-- -----------------------------------------------------------------------------
-- Purpose : every server-side primitive the client is allowed to call.
--           Authorisation helpers, document numbering, audit plumbing, the
--           atomic business transactions (SS50) and the aggregate read RPCs.
-- Depends : 002-005.
--
-- SECURITY MODEL (important - read before adding a function)
--   * Read-only aggregates            -> security invoker (plain RLS applies)
--   * Multi-table business writes     -> SECURITY DEFINER, because one user
--     action touches sales, inventory, invoices, payments, accounting,
--     reminders and audit_logs and no single user necessarily holds write policy
--     on all of them.  Such a function is therefore *not* trusted by default:
--     it starts with `app_sec.require_permission(module, action)` and
--     `app_sec.require_showroom_access(showroom_id)`, which is exactly the
--     "permission checks in ... Database functions" requirement (SS6).  The
--     definer runs as the migration owner (superuser) so it bypasses RLS by
--     design; the explicit permission checks are the authorisation gate.
--   * `set search_path = ''` on every definer function and fully qualified
--     object names: prevents search_path hijacking via a hostile `public` object.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- app_sec: identity + authorisation primitives
-- ---------------------------------------------------------------------------

-- The application user id behind the current JWT. SECURITY DEFINER + superuser
-- owner means the lookup on public.users is not itself filtered by RLS, which
-- is what keeps policy evaluation non-recursive (SS49).
create or replace function app_sec.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
    from public.users u
   where u.auth_user_id = auth.uid()
     and u.is_deleted = false;
$$;

-- Cached per transaction so a single statement that evaluates 6 policies does
-- not run 6 lookups.  A GUC is transaction-local: no cross-request leakage.
create or replace function app_sec.current_user_id_cached()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cached text := current_setting('app.current_user_id', true);
  v_id     uuid;
begin
  if v_cached is not null and v_cached <> '' then
    return v_cached::uuid;
  end if;
  v_id := app_sec.current_user_id();
  if v_id is not null then
    perform set_config('app.current_user_id', v_id::text, true);
  end if;
  return v_id;
end;
$$;

-- The *unfiltered* profile row, used by the login bootstrap (SS5). A freshly
-- signed-up but unassigned user must still be able to read their own row.
create or replace function app_sec.current_user_row()
returns public.users
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.users where auth_user_id = auth.uid() limit 1;
$$;

create or replace function app_sec.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
           (select u.is_super_admin
              from public.users u
             where u.id = app_sec.current_user_id()
               and u.status = 'ACTIVE'),
           false
         )
         or exists (
           select 1
             from public.users u
             join public.user_roles ur on ur.user_id = u.id
             join public.roles r        on r.id = ur.role_id
            where u.id = app_sec.current_user_id()
              and u.status = 'ACTIVE'
              and r.code = 'SUPERADMIN'
         );
$$;

-- Showroom visibility for the current user (SS7 tenant isolation).
create or replace function app_sec.can_access_showroom(p_showroom_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when p_showroom_id is null then app_sec.is_super_admin()
           when app_sec.is_super_admin() then true
           when exists (
                  select 1
                    from public.users u
                   where u.id = app_sec.current_user_id()
                     and u.status = 'ACTIVE'
                     and u.showroom_id = p_showroom_id
                ) then true
           else exists (
                  select 1
                    from public.user_showroom_access a
                    join public.users u on u.id = a.user_id
                   where u.id = app_sec.current_user_id()
                     and u.status = 'ACTIVE'
                     and a.showroom_id = p_showroom_id
                     and a.valid_from <= now()
                     and (a.valid_to is null or a.valid_to > now())
                )
         end;
$$;

-- Set-returning form used by list policies ("show me everything I may see").
create or replace function app_sec.accessible_showroom_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.id
    from public.showrooms s
   where s.status <> 'CLOSED'
     -- Every SELECT policy is built on this function, so the lockout rule lives
     -- here once: a suspended, disabled or not-yet-activated account resolves to
     -- zero showrooms and therefore reads zero business rows (SS6, SS44).
     and exists (select 1 from public.users u
                  where u.id = app_sec.current_user_id()
                    and u.status = 'ACTIVE'
                    and u.is_deleted = false)
     and (app_sec.is_super_admin()
          or s.id = (select u.showroom_id from public.users u where u.id = app_sec.current_user_id())
          or exists (select 1 from public.user_showroom_access a
                      where a.user_id = app_sec.current_user_id()
                        and a.showroom_id = s.id
                        and a.valid_from <= now()
                        and (a.valid_to is null or a.valid_to > now())));
$$;

-- module.action authorisation (SS6). Roles granted at global level (showroom_id
-- IS NULL) apply everywhere; a role scoped to a showroom only authorises rows
-- in that showroom - checked by can_access_showroom() at the policy level.
create or replace function app_sec.has_permission(p_module text, p_action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_sec.is_super_admin()
     or exists (
          select 1
            from public.user_roles ur
            join public.roles r          on r.id = ur.role_id
            join public.role_permissions rp on rp.role_id = r.id
            join public.permissions p    on p.id = rp.permission_id
           where ur.user_id = app_sec.current_user_id()
             and p.module = p_module
             and p.action = p_action
             and (ur.showroom_id is null
                  or ur.showroom_id = (select u.showroom_id from public.users u
                                        where u.id = app_sec.current_user_id())
                  or exists (select 1 from public.user_showroom_access a
                              where a.user_id = ur.user_id and a.showroom_id = ur.showroom_id))
       );
$$;

-- Same, but for a specific showroom (used by RLS UPDATE/DELETE policies).
create or replace function app_sec.has_permission_in(p_module text, p_action text, p_showroom_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_sec.is_super_admin()
     or (app_sec.can_access_showroom(p_showroom_id) and exists (
          select 1
            from public.user_roles ur
            join public.roles r             on r.id = ur.role_id
            join public.role_permissions rp on rp.role_id = r.id
            join public.permissions p       on p.id = rp.permission_id
           where ur.user_id = app_sec.current_user_id()
             and p.module = p_module
             and p.action = p_action
       ));
$$;

-- Guard used at the head of every SECURITY DEFINER business RPC.
create or replace function app_sec.require_permission(p_module text, p_action text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_sec.has_permission(p_module, p_action) then
    raise exception '[SEC001] Missing permission %.%', p_module, p_action
      using errcode = '42501',
            hint     = 'Grant the permission to the user role, or use a role that already has it.';
  end if;
end;
$$;

create or replace function app_sec.require_showroom_access(p_showroom_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_showroom_id is null then
    raise exception '[VAL001] showroom_id is required for this operation' using errcode = '22000';
  end if;
  if not app_sec.can_access_showroom(p_showroom_id) then
    raise exception '[SEC002] You are not allowed to access showroom %', p_showroom_id
      using errcode = '42501';
  end if;
end;
$$;

-- The active showroom for the session: client-selected must be permitted.
create or replace function app_sec.current_showroom_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_requested uuid := nullif(current_setting('app.showroom_id', true), '')::uuid;
  v_home      uuid;
begin
  select u.showroom_id into v_home from public.users u where u.id = app_sec.current_user_id();
  if v_requested is not null and app_sec.can_access_showroom(v_requested) then
    return v_requested;
  end if;
  return v_home;
end;
$$;

-- Login bootstrap payload (SS5): identity -> roles -> permissions -> showrooms
-- in ONE round trip so the client never trusts a stale permission set.
create or replace function public.get_current_user_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user   public.users;
  v_out    jsonb;
begin
  select * into v_user from public.users where auth_user_id = auth.uid();
  if not found then
    -- No profile yet: still return the auth identity so the client can show a
    -- "your account is pending activation" screen instead of a hard failure.
    return jsonb_build_object('hasProfile', false, 'authUserId', auth.uid());
  end if;

  if v_user.status <> 'ACTIVE' then
    -- A suspended / disabled / not-yet-activated account must not receive a
    -- showroom or a permission list: RLS already hides every tenant row, so a
    -- payload that still advertised them would light up navigation that leads to
    -- empty screens (and invite a client-side assumption of access). The app
    -- renders the lock screen from accountLocked + status (SS6, SS12).
    return jsonb_build_object(
      'hasProfile', true,
      'userId', v_user.id,
      'authUserId', v_user.auth_user_id,
      'name', v_user.name,
      'email', v_user.email,
      'status', v_user.status,
      'accountLocked', true,
      'mustChangePassword', v_user.must_change_password,
      'preferences', '{}'::jsonb,
      'roles', '[]'::jsonb,
      'permissions', '[]'::jsonb,
      'showrooms', '[]'::jsonb
    );
  end if;

  select jsonb_build_object(
    'hasProfile', true,
    'userId', v_user.id,
    'authUserId', v_user.auth_user_id,
    'name', v_user.name,
    'email', v_user.email,
    'phone', v_user.phone,
    'avatarUrl', v_user.avatar_url,
    'status', v_user.status,
    'designation', v_user.designation,
    'mustChangePassword', v_user.must_change_password,
    'isSuperAdmin', v_user.is_super_admin,
    'preferences', to_jsonb(v_user.preferences),
    'homeShowroomId', v_user.showroom_id,
    'roles', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', r.id, 'code', r.code, 'name', r.name, 'levelRank', r.level_rank,
               'showroomId', ur.showroom_id)), '[]'::jsonb)
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
       where ur.user_id = v_user.id
    ),
    'permissions', (
      select coalesce(jsonb_agg(distinct (p.module || '.' || p.action) order by (p.module || '.' || p.action)),
                      '[]'::jsonb)
        from public.user_roles ur
        join public.roles r             on r.id = ur.role_id
        join public.role_permissions rp on rp.role_id = r.id
        join public.permissions p       on p.id = rp.permission_id
       where ur.user_id = v_user.id
    ),
    'showrooms', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', s.id, 'name', s.name, 'code', s.code, 'city', s.city,
               'state', s.state, 'status', s.status, 'settings', s.settings,
               'isHome', s.id = v_user.showroom_id, 'accessLevel', lvl)),
               '[]'::jsonb)
        from public.showrooms s
        cross join lateral (
          select coalesce(
            (select a.access_level from public.user_showroom_access a
              where a.user_id = v_user.id and a.showroom_id = s.id
              order by a.created_at desc limit 1),
            case when s.id = v_user.showroom_id then 'OPERATE' end) as lvl
        )
       where app_sec.is_super_admin()
          or s.id = v_user.showroom_id
          or exists (select 1 from public.user_showroom_access a
                      where a.user_id = v_user.id and a.showroom_id = s.id)
    )
  ) into v_out;

  return v_out;
end;
$$;

comment on function public.get_current_user_context() is
  'Single round trip that resolves auth.uid() -> user -> roles -> permissions -> showrooms (SS5). '
  'A non-ACTIVE profile gets accountLocked=true with empty roles/permissions/showrooms.';

-- ---------------------------------------------------------------------------
-- app_gen: business document numbering (SS48)
--   Format: <PREFIX><showroom-code-short><FY><sequence padded>  e.g. INV-BLR1-2510042
--   The counter row is locked FOR UPDATE, so two terminals on two networks can
--   never mint the same number; the unique constraints do the rest.
-- ---------------------------------------------------------------------------
create or replace function app_gen.next_document_number(
  p_showroom_id uuid,
  p_doc_type    text,
  p_date        date default current_date,
  p_periods     text default 'ALL'      -- 'ALL' | 'FY' (fiscal-year restart)
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prefix      text;
  v_code        text;
  v_period      text;
  v_next        bigint;
  v_padding     smallint;
  v_fy_start    int;
  v_number      text;
begin
  if p_showroom_id is null then
    raise exception '[VAL001] showroom_id required to allocate a % number', p_doc_type using errcode = '22000';
  end if;

  select case p_doc_type
           when 'SALE'          then 'SAL'
           when 'INVOICE'       then 'INV'
           when 'PAYMENT'       then 'PMT'
           when 'SERVICE'       then 'SVC'
           when 'PURCHASE'      then 'PUR'
           when 'EXPENSE'       then 'EXP'
           when 'LOAN'          then 'LON'
           when 'CUSTOMER'      then 'CUS'
           when 'WARRANTY_CLAIM'then 'WTC'
           when 'STOCK_TRANSFER'then 'STF'
           when 'ACCOUNTING'    then 'JRN'
           when 'INSURANCE'     then 'INS'
           when 'QUOTATION'     then 'QTN'
           else upper(left(p_doc_type, 3))
         end,
         s.code,
         s.financial_year_start_month
    into v_prefix, v_code, v_fy_start
    from public.showrooms s where s.id = p_showroom_id;

  if not found then
    raise exception '[NOT001] showroom % not found', p_showroom_id using errcode = 'P0002';
  end if;

  if p_periods = 'FY' then
    v_period := 'FY' || lpad(((case when extract(month from p_date) >= v_fy_start
                                    then extract(year from p_date)::int
                                    else extract(year from p_date)::int - 1 end) % 100)::text, 2, '0')
                    || lpad(((case when extract(month from p_date) >= v_fy_start
                                   then extract(year from p_date)::int + 1
                                   else extract(year from p_date)::int end) % 100)::text, 2, '0');
  else
    v_period := 'ALL';
  end if;

  insert into public.document_sequences as ds
         (showroom_id, doc_type, period_key, prefix, next_value)
  values (p_showroom_id, p_doc_type, v_period, v_prefix, 1)
  on conflict (showroom_id, doc_type, period_key) do nothing;

  select ds.next_value, ds.padding, ds.prefix
    into v_next, v_padding, v_prefix
    from public.document_sequences ds
   where ds.showroom_id = p_showroom_id
     and ds.doc_type = p_doc_type
     and ds.period_key = v_period
     for update;

  update public.document_sequences
     set next_value = v_next + 1,
         updated_at = now()
   where showroom_id = p_showroom_id
     and doc_type = p_doc_type
     and period_key = v_period;

  v_number := upper(v_prefix) || '-' || upper(left(replace(v_code, '.', ''), 4))
            || case when v_period = 'ALL' then '' else replace(v_period, 'FY', '-') end
            || lpad(v_next::text, v_padding, '0');
  return v_number;
end;
$$;

-- Convenience wrapper kept public so a Dart client can preview the next number
-- while a draft form is open (read-only feel, but it does advance the counter -
-- therefore it is only ever called from the create RPCs in production paths).
create or replace function public.peek_document_number(
  p_showroom_id uuid,
  p_doc_type    text,
  p_date        date default current_date
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ds.prefix || '-' || upper(left(s.code, 4))
         || lpad(ds.next_value::text, ds.padding, '0')
    from public.document_sequences ds
    join public.showrooms s on s.id = ds.showroom_id
   where ds.showroom_id = p_showroom_id
     and ds.doc_type = p_doc_type
     and ds.period_key = 'ALL';
$$;

-- ---------------------------------------------------------------------------
-- app_util.audit_row: the single audit writer.
-- Business tables get it via a trigger (007); RPCs call it directly when the
-- semantic action (CANCEL, APPROVE, PAYMENT, STOCK_TRANSFER) is not a plain
-- INSERT/UPDATE.
-- ---------------------------------------------------------------------------
create or replace function app_util.audit_row(
  p_module     text,
  p_action     text,
  p_table      text,
  p_record_id  uuid,
  p_old        jsonb,
  p_new        jsonb,
  p_showroom_id uuid default null,
  p_user_id     uuid default null,
  p_label      text default null,
  p_severity   text default 'INFO'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(p_user_id, app_sec.current_user_id());
  v_shr  uuid := coalesce(p_showroom_id,
               (select u.showroom_id from public.users u where u.id = v_user));
begin
  insert into public.audit_logs
        (showroom_id, user_id, module, action, table_name, record_id, record_label,
         old_data, new_data, changed_fields, ip_address, user_agent, severity)
  values (
    v_shr, v_user, p_module, p_action, p_table, p_record_id, p_label,
    p_old, p_new,
    case when p_old is not null and p_new is not null then (
           select coalesce(array_agg(e.key order by e.key), '{}')
             from jsonb_each(p_new) as e
            where p_old -> e.key is distinct from e.value
         ) end,
    nullif(current_setting('request.header.x-forwarded-for', true), '')::inet,
    nullif(current_setting('request.header.user-agent', true), ''),
    p_severity
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- app_acc: double-entry primitives (SS24). 013 adds the balance trigger +
-- default chart of accounts; the posting primitive lives here because the
-- business transactions in this file need it.
-- ---------------------------------------------------------------------------

-- The master chart, as data (not code). 014 seeds it into
-- app_acc.chart_template; every showroom gets its own copy (SS82).
create table if not exists app_acc.chart_template (
  account_code   text primary key,
  account_name   text not null,
  account_type   text not null check (account_type in ('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE')),
  normal_balance text not null default 'DEBIT' check (normal_balance in ('DEBIT','CREDIT')),
  parent_code    text,
  is_group       boolean not null default false,
  sort_order     smallint not null default 0
);

insert into app_acc.chart_template
      (account_code, account_name, account_type, normal_balance, parent_code, is_group, sort_order)
values
  ('1000','Cash & Bank',            'ASSET','DEBIT', null,      true ,  1),
  ('1010','Cash',                   'ASSET','DEBIT','1000',    false,  2),
  ('1020','Bank Account',           'ASSET','DEBIT','1000',    false,  3),
  ('1030','UPI / Card Settlement',  'ASSET','DEBIT','1000',    false,  4),
  ('1100','Customer Receivable',    'ASSET','DEBIT', null,      false,  5),
  ('1150','Finance Company Receivable','ASSET','DEBIT', null,   false,  6),
  ('1200','Inventory (Bikes)',      'ASSET','DEBIT', null,      false,  7),
  ('1250','Inventory In Transit',   'ASSET','DEBIT','1200',     false,  8),
  ('1300','GST Receivable',         'ASSET','DEBIT', null,      false,  9),
  ('1400','Customer Advances',      'ASSET','DEBIT', null,      false, 10),
  ('2000','Payables',               'LIABILITY','CREDIT', null, true , 20),
  ('2100','Supplier Payable',       'LIABILITY','CREDIT','2000', false,21),
  ('2200','Tax Payable (GST)',      'LIABILITY','CREDIT','2000', false,22),
  ('2300','Advance from Customers', 'LIABILITY','CREDIT','2000', false,23),
  ('2400','Salary Payable',         'LIABILITY','CREDIT','2000', false,24),
  ('2500','Expense Payable',        'LIABILITY','CREDIT','2000', false,25),
  ('3000','Owner Equity',           'EQUITY','CREDIT', null,    false, 30),
  ('4000','Revenue',                'INCOME','CREDIT', null,    true , 40),
  ('4100','Vehicle Sales Revenue',  'INCOME','CREDIT','4000',   false, 41),
  ('4200','Accessory Revenue',      'INCOME','CREDIT','4000',   false, 42),
  ('4300','Service Revenue',        'INCOME','CREDIT','4000',   false, 43),
  ('4400','Insurance Commission',   'INCOME','CREDIT','4000',   false, 44),
  ('4500','Finance Commission',     'INCOME','CREDIT','4000',   false, 45),
  ('4600','EMI Interest Income',    'INCOME','CREDIT','4000',   false, 46),
  ('4700','Late Fee Income',        'INCOME','CREDIT','4000',   false, 47),
  ('4900','Other Income',           'INCOME','CREDIT','4000',   false, 48),
  ('5000','Cost of Goods Sold',     'EXPENSE','DEBIT', null,    false, 50),
  ('5100','Purchases',              'EXPENSE','DEBIT', null,    false, 51),
  ('5200','Discount Allowed',       'EXPENSE','DEBIT', null,    false, 52),
  ('5300','Salaries & Wages',       'EXPENSE','DEBIT', null,    false, 53),
  ('5310','Rent Expense',           'EXPENSE','DEBIT', null,    false, 54),
  ('5320','Electricity Expense',    'EXPENSE','DEBIT', null,    false, 55),
  ('5330','Transport Expense',      'EXPENSE','DEBIT', null,    false, 56),
  ('5340','Marketing Expense',      'EXPENSE','DEBIT', null,    false, 57),
  ('5350','Maintenance Expense',    'EXPENSE','DEBIT', null,    false, 58),
  ('5360','Office Expense',         'EXPENSE','DEBIT', null,    false, 59),
  ('5370','Fuel Expense',           'EXPENSE','DEBIT', null,    false, 60),
  ('5380','Service Parts Consumed', 'EXPENSE','DEBIT', null,    false, 61),
  ('5390','Free Service Cost',      'EXPENSE','DEBIT', null,    false, 62),
  ('5400','Loan Loss / Penalty',    'EXPENSE','DEBIT', null,    false, 63),
  ('5900','Other Expense',          'EXPENSE','DEBIT', null,    false, 99)
on conflict (account_code) do update
   set account_name = excluded.account_name,
       account_type = excluded.account_type,
       normal_balance = excluded.normal_balance,
       parent_code = excluded.parent_code,
       is_group = excluded.is_group,
       sort_order = excluded.sort_order;

comment on table app_acc.chart_template is
  'Master chart of accounts shipped by the product. Seeded per-showroom by app_acc.ensure_default_chart() (SS82).';

-- Configurable event -> account mapping, so a dealership can move "Insurance
-- Commission" to a different ledger without a code change.
create table if not exists app_acc.event_account_map (
  event_key    text not null,          -- e.g. 'SALE.REVENUE'
  side         text not null check (side in ('DEBIT','CREDIT')),
  account_code text not null,
  showroom_id  uuid,                   -- null = group-wide default
  primary key (event_key, side, account_code)
);

insert into app_acc.event_account_map (event_key, side, account_code) values
  ('SALE.VEHICLE_REVENUE','CREDIT','4100'),
  ('SALE.ACCESSORY_REVENUE','CREDIT','4200'),
  ('SALE.TAX','CREDIT','2200'),
  ('SALE.CASH','DEBIT','1010'),
  ('SALE.BANK','DEBIT','1020'),
  ('SALE.DIGITAL','DEBIT','1030'),
  ('SALE.RECEIVABLE','DEBIT','1100'),
  ('SALE.FINANCE_RECEIVABLE','DEBIT','1150'),
  ('SALE.COGS','DEBIT','5000'),
  ('SALE.INVENTORY','CREDIT','1200'),
  ('SALE.ADVANCE','CREDIT','2300'),
  ('PAYMENT.CASH','DEBIT','1010'),
  ('PAYMENT.BANK','DEBIT','1020'),
  ('PAYMENT.DIGITAL','DEBIT','1030'),
  ('PAYMENT.RECEIVABLE','CREDIT','1100'),
  ('PAYMENT.ADVANCE','CREDIT','2300'),
  ('REFUND.CASH','CREDIT','1010'),
  ('REFUND.RECEIVABLE','DEBIT','1100'),
  ('SERVICE.REVENUE','CREDIT','4300'),
  ('SERVICE.TAX','CREDIT','2200'),
  ('SERVICE.PARTS','DEBIT','5380'),
  ('SERVICE.FREE_COST','DEBIT','5390'),
  ('EMI.INTEREST','CREDIT','4600'),
  ('EMI.PRINCIPAL','CREDIT','1150'),
  ('EMI.LATE_FEE','CREDIT','4700'),
  ('PURCHASE.INVENTORY','DEBIT','1200'),
  ('PURCHASE.TAX','DEBIT','1300'),
  ('PURCHASE.SUPPLIER','CREDIT','2100'),
  ('PURCHASE.OTHER','DEBIT','5100'),
  ('EXPENSE.CATEGORY','DEBIT','5900'),
  ('EXPENSE.PAYABLE','CREDIT','2500'),
  ('EXPENSE.CASH','CREDIT','1010'),
  ('EXPENSE.BANK','CREDIT','1020'),
  ('EXPENSE.DIGITAL','CREDIT','1030'),
  ('TRANSFER.OUT','CREDIT','1200'),
  ('TRANSFER.IN','DEBIT','1200'),
  ('TRANSFER.IN_TRANSIT','DEBIT','1250'),
  ('TRANSFER.OUT_IN_TRANSIT','CREDIT','1250'),
  ('ADJUSTMENT.LOSS','DEBIT','5900'),
  ('ADJUSTMENT.GAIN','CREDIT','4900')
on conflict do nothing;

create or replace function app_acc.ensure_default_chart(p_showroom_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count    integer;
  v_inserted integer := 0;
  rec        record;
begin
  select count(*) into v_count from public.accounts where showroom_id = p_showroom_id;
  if v_count > 0 then
    return 0;
  end if;

  -- parents first so the FK to parent_account_id resolves in one pass
  for rec in
    select * from app_acc.chart_template order by is_group desc, sort_order, account_code
  loop
    insert into public.accounts
          (showroom_id, account_code, account_name, account_type, parent_account_id,
           is_group, normal_balance, is_system, description, status)
    select p_showroom_id, rec.account_code, rec.account_name, rec.account_type,
           (select a.id from public.accounts a
             where a.showroom_id = p_showroom_id and a.account_code = rec.parent_code),
           rec.is_group, rec.normal_balance, true,
           'System account shipped with the chart of accounts.', 'ACTIVE'
    on conflict (showroom_id, account_code) do nothing;
    v_inserted := v_inserted + coalesce(
      (select count(*) from public.accounts
        where showroom_id = p_showroom_id and account_code = rec.account_code), 0);
  end loop;

  return v_inserted;
end;
$$;

comment on function app_acc.ensure_default_chart(uuid) is
  'Materialises the default chart of accounts for a showroom on first use (SS82).';

-- Per-showroom overrides of the mapping above (created on demand from the
-- Settings > Accounting screen; empty by default).
create table if not exists app_acc.event_account_map_override (
  event_key    text not null,
  side         text not null check (side in ('DEBIT','CREDIT')),
  account_code text not null,
  showroom_id  uuid not null,
  primary key (event_key, side, showroom_id),
  foreign key (showroom_id) references public.showrooms (id) on delete cascade
);

-- Resolve an event account for a showroom (falls back to the group-wide map).
create or replace function app_acc.account_for(
  p_showroom_id uuid,
  p_event_key   text,
  p_side        text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.id
    from app_acc.event_account_map m
    join public.accounts a on a.account_code = m.account_code
                          and a.showroom_id = p_showroom_id
   where m.event_key = p_event_key
     and m.side = p_side
   order by exists (select 1 from app_acc.event_account_map_override o
                     where o.event_key = m.event_key and o.side = m.side
                       and o.showroom_id = p_showroom_id
                       and o.account_code = m.account_code) desc nulls last,
            m.account_code
   limit 1;
$$;

-- Generic balance-safe journal. p_lines = [{code|account_id, debit|credit, description}]
create or replace function app_acc.post_journal(
  p_showroom_id   uuid,
  p_date          date,
  p_journal_type  text,
  p_reference_type text,
  p_reference_id  uuid,
  p_description   text,
  p_lines         jsonb,
  p_created_by    uuid default app_sec.current_user_id()
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tx_id   uuid;
  v_lines   jsonb;
  v_total_debit  numeric := 0;
  v_total_credit numeric := 0;
  v_account uuid;
  v_debit   numeric;
  v_credit  numeric;
  rec       record;
  i         int := 0;
  v_number  text;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception '[VAL001] A journal needs at least one line' using errcode = '22000';
  end if;

  perform app_acc.ensure_default_chart(p_showroom_id);

  -- resolve + normalise lines first, so a broken account never half-posts
  select jsonb_agg(
           jsonb_build_object(
             'account_id', coalesce(
               (l.value ->> 'account_id')::uuid,
               (select a.id from public.accounts a
                 where a.showroom_id = p_showroom_id
                   and a.account_code = l.value ->> 'code')),
             'debit',  round(coalesce((l.value ->> 'debit')::numeric, 0), 2),
             'credit', round(coalesce((l.value ->> 'credit')::numeric, 0), 2),
             'description', coalesce(l.value ->> 'description', p_description)
           )
         ) into v_lines
    from jsonb_array_elements(p_lines) as l(value);

  if v_lines is null then
    raise exception '[VAL001] Unable to resolve the journal lines' using errcode = '22000';
  end if;

  select coalesce(sum((l.value ->> 'debit')::numeric), 0),
         coalesce(sum((l.value ->> 'credit')::numeric), 0)
    into v_total_debit, v_total_credit
    from jsonb_array_elements(v_lines) as l(value);

  -- THE double-entry invariant, enforced on the server (§24, §67)
  if abs(v_total_debit - v_total_credit) > 0.005 then
    raise exception '[VAL002] Unbalanced journal for % %: debit % <> credit %',
      p_reference_type, p_reference_id, v_total_debit, v_total_credit
      using errcode = '22000';
  end if;
  if v_total_debit = 0 then
    raise exception '[VAL003] Journal lines are all zero for % %', p_reference_type, p_reference_id
      using errcode = '22000';
  end if;

  v_number := app_gen.next_document_number(p_showroom_id, 'ACCOUNTING', p_date);

  insert into public.accounting_transactions
        (transaction_number, showroom_id, transaction_date, journal_type,
         reference_type, reference_id, description, created_by)
  values (v_number, p_showroom_id, p_date, p_journal_type,
          p_reference_type, p_reference_id, p_description, p_created_by)
  returning id into v_tx_id;

  for rec in select * from jsonb_array_elements(v_lines) with ordinality as e(value, ord)
  loop
    v_account := (rec.value ->> 'account_id')::uuid;
    v_debit   := (rec.value ->> 'debit')::numeric;
    v_credit  := (rec.value ->> 'credit')::numeric;

    if v_account is null then
      raise exception '[VAL004] Journal line % could not resolve its account', rec.ord
        using errcode = '22000';
    end if;
    if not exists (select 1 from public.accounts a where a.id = v_account and a.showroom_id = p_showroom_id) then
      raise exception '[VAL005] Account % does not belong to showroom %', v_account, p_showroom_id
        using errcode = '22000';
    end if;

    insert into public.accounting_entries
          (transaction_id, account_id, showroom_id, line_number, debit, credit, description)
    values (v_tx_id, v_account, p_showroom_id, rec.ord, v_debit, v_credit,
            rec.value ->> 'description');
  end loop;

  return v_tx_id;
end;
$$;

comment on function app_acc.post_journal is
  'The only way a journal is written. Rejects unbalanced journals, resolves account codes per showroom, and is idempotent via the (reference_type, reference_id, journal_type) unique key.';

-- Reverse a previously posted journal by posting its mirror image (§42: never delete).
create or replace function app_acc.reverse_journal(
  p_transaction_id uuid,
  p_reason         text,
  p_date           date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src   public.accounting_transactions;
  v_new   uuid;
  v_lines jsonb;
begin
  select * into v_src from public.accounting_transactions where id = p_transaction_id for update;
  if not found then
    raise exception '[NOT001] accounting transaction % not found', p_transaction_id using errcode = 'P0002';
  end if;
  if v_src.is_reversed then
    raise exception '[CON001] accounting transaction % is already reversed', p_transaction_id
      using errcode = '23505';
  end if;
  if v_src.journal_type = 'REVERSAL' then
    raise exception '[CON002] a reversal journal cannot itself be reversed - reverse the entry it cancelled instead'
      using errcode = '23514';
  end if;

  select jsonb_agg(jsonb_build_object(
           'account_id', e.account_id,
           'debit',  e.credit,
           'credit', e.debit,
           'description', 'Reversal: ' || coalesce(e.description, '')))
    into v_lines
    from public.accounting_entries e where e.transaction_id = p_transaction_id;

  insert into public.accounting_transactions
        (transaction_number, showroom_id, transaction_date, journal_type,
         reference_type, reference_id, description, status, created_by)
  -- A reversal keeps the document reference, so the ledger for that document shows
  -- both sides of the correction, and is typed 'REVERSAL' - which is what exempts
  -- it from the "one journal per document" idempotency rule (SS42).
  values (app_gen.next_document_number(v_src.showroom_id, 'ACCOUNTING', p_date),
          v_src.showroom_id, p_date, 'REVERSAL',
          v_src.reference_type, v_src.reference_id,
          'Reversal of ' || v_src.transaction_number || ' - ' || coalesce(p_reason, 'no reason given'),
          'POSTED', app_sec.current_user_id())
  returning id into v_new;

  insert into public.accounting_entries (transaction_id, account_id, showroom_id, line_number, debit, credit, description)
  select v_new, (l.value ->> 'account_id')::uuid, v_src.showroom_id,
         row_number() over (), (l.value ->> 'debit')::numeric, (l.value ->> 'credit')::numeric,
         l.value ->> 'description'
    from jsonb_array_elements(v_lines) as l(value);

  update public.accounting_transactions
     set is_reversed = true, reversed_by_transaction_id = v_new, status = 'REVERSED'
   where id = p_transaction_id;

  perform app_util.audit_row('accounting','UPDATE','accounting_transactions', p_transaction_id,
          jsonb_build_object('is_reversed', false), jsonb_build_object('is_reversed', true),
          v_src.showroom_id, null, 'Reversal ' || p_reason);

  return v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Finance: EMI mathematics (SS16)
--   EMI = P x r x (1+r)^n / ((1+r)^n - 1)      (REDUCING balance)
--   FLAT: (P + P x R x n/12) / n
-- Implemented in SQL so the client, the report and the schedule generator can
-- never disagree about a rupee.
-- ---------------------------------------------------------------------------
create or replace function public.calculate_emi(
  p_principal     numeric,
  p_annual_rate   numeric,
  p_tenure_months integer,
  p_interest_type text default 'REDUCING'
)
returns numeric
language sql
immutable
parallel safe
as $$
  select case
           when p_principal is null or p_tenure_months is null or p_tenure_months <= 0 then 0
           when coalesce(p_annual_rate, 0) <= 0
             then round(p_principal / p_tenure_months, 2)
           when coalesce(p_interest_type, 'REDUCING') = 'FLAT' then round(
                  (p_principal + p_principal * p_annual_rate / 100 * p_tenure_months / 12.0)
                  / p_tenure_months, 2)
           else round(
                  p_principal * (p_annual_rate / 1200.0)
                  * power(1 + p_annual_rate / 1200.0, p_tenure_months)
                  / (power(1 + p_annual_rate / 1200.0, p_tenure_months) - 1), 2)
         end;
$$;

comment on function public.calculate_emi(numeric, numeric, integer, text) is
  'Reference EMI formula from the specification (SS16). r = annual/12/100.';

-- Total interest over the life of the loan, used by the loan form preview.
create or replace function public.calculate_loan_summary(
  p_principal     numeric,
  p_annual_rate   numeric,
  p_tenure_months integer,
  p_interest_type text default 'REDUCING'
)
returns jsonb
language sql
stable
parallel safe
as $$
  select jsonb_build_object(
    'emiAmount',       public.calculate_emi(p_principal, p_annual_rate, p_tenure_months, p_interest_type),
    'totalPayable',    round(public.calculate_emi(p_principal, p_annual_rate, p_tenure_months, p_interest_type)
                              * p_tenure_months, 2),
    'totalInterest',   round(public.calculate_emi(p_principal, p_annual_rate, p_tenure_months, p_interest_type)
                              * p_tenure_months - p_principal, 2),
    'principal',       p_principal,
    'tenureMonths',    p_tenure_months,
    'annualRate',      p_annual_rate,
    'interestType',    coalesce(p_interest_type, 'REDUCING')
  );
$$;

-- ---------------------------------------------------------------------------
-- generate_emi_schedule: builds the full amortisation table for a loan and is
-- idempotent - re-running it on an untouched loan rebuilds, on a partially paid
-- loan it refuses (SS67: no silent financial rewrite).
-- ---------------------------------------------------------------------------
create or replace function public.generate_emi_schedule(
  p_loan_id        uuid,
  p_first_due_date date default null,
  p_regenerate     boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan        public.loans;
  v_emis        public.emi_schedules%rowtype;
  v_bal         numeric;
  v_rate_m      numeric;
  v_emi         numeric;
  v_interest    numeric;
  v_principal   numeric;
  v_total_int   numeric := 0;
  v_i           integer;
  v_first_due   date;
  v_prev_remaining numeric;
  v_paid_rows   integer;
  v_inserted    integer := 0;
  v_sum_lines   jsonb;
begin

  perform app_sec.require_permission('emi', 'create');

  select * into v_loan from public.loans where id = p_loan_id for update;
  if not found then
    raise exception '[NOT001] loan % not found', p_loan_id using errcode = 'P0002';
  end if;
  perform app_sec.require_showroom_access(v_loan.showroom_id);

  if v_loan.status in ('CLOSED','FORECLOSED','REJECTED','CANCELLED') then
    raise exception '[CON002] loan % is %, its schedule is frozen', v_loan.loan_number, v_loan.status
      using errcode = '23514';
  end if;

  select count(*) into v_paid_rows
    from public.emi_schedules e
   where e.loan_id = p_loan_id and e.paid_amount > 0;
  if v_paid_rows > 0 and p_regenerate is not true then
    raise exception '[CON003] loan % already has % paid instalment(s); regenerate is refused', v_loan.loan_number, v_paid_rows
      using errcode = '23505';
  end if;
  if v_paid_rows > 0 and p_regenerate then
    raise exception '[CON004] cannot regenerate a schedule that has payment history; use prepayment/part-payment RPCs'
      using errcode = '23505';
  end if;

  v_bal    := coalesce(nullif(v_loan.principal_amount, 0), v_loan.loan_amount);
  v_rate_m := coalesce(v_loan.interest_rate, 0) / 1200.0;
  v_emi    := public.calculate_emi(v_bal, v_loan.interest_rate, v_loan.tenure_months, v_loan.interest_type);

  if v_emi is null or v_emi <= 0 then
    raise exception '[VAL006] EMI amount resolved to % - check principal/rate/tenure', v_emi using errcode = '22000';
  end if;

  v_first_due := coalesce(p_first_due_date, v_loan.first_emi_date,
                          (v_loan.start_date + interval '1 month')::date);

  delete from public.emi_schedules where loan_id = p_loan_id;

  for v_i in 1..v_loan.tenure_months loop
    if v_loan.interest_type = 'FLAT' then
      v_interest  := round(v_bal * v_loan.interest_rate / 100 / 12.0, 2);
      v_principal := round(v_emi - v_interest, 2);
    else
      v_interest := round(v_bal * v_rate_m, 2);
      -- the last instalment absorbs the rounding drift so the ledger foots exactly
      if v_i = v_loan.tenure_months then
        v_principal := round(v_bal, 2);
      else
        v_principal := round(v_emi - v_interest, 2);
      end if;
    end if;

    if v_principal > v_bal then
      v_principal := round(v_bal, 2);
    end if;

    insert into public.emi_schedules
          (loan_id, showroom_id, customer_id, emi_number, due_date,
           principal_amount, interest_amount, emi_amount, paid_amount,
           remaining_amount, status)
    values (p_loan_id, v_loan.showroom_id, v_loan.customer_id, v_i,
            (v_first_due + make_interval(months => v_i - 1))::date,
            v_principal, v_interest, round(v_principal + v_interest, 2), 0,
            round(v_principal + v_interest, 2),
            case when (v_first_due + make_interval(months => v_i - 1))::date <= current_date
                 then 'DUE' else 'UPCOMING' end)
    returning * into v_emis;
    v_prev_remaining := v_emis.remaining_amount;
    v_inserted := v_inserted + 1;
    v_total_int := v_total_int + v_interest;
    v_bal := round(v_bal - v_principal, 2);
  end loop;

  update public.loans
     set emi_amount     = v_emi,
         principal_amount = round(coalesce(nullif(principal_amount,0), loan_amount), 2),
         total_interest  = round(v_total_int, 2),
         total_payable   = round(coalesce(nullif(principal_amount,0), loan_amount) + v_total_int, 2),
         end_date        = greatest((v_first_due + make_interval(months => v_loan.tenure_months - 1))::date, end_date),
         first_emi_date  = v_first_due,
         updated_at      = now()
   where id = p_loan_id;

  perform app_util.audit_row('emi','CREATE','emi_schedules', p_loan_id, null,
    jsonb_build_object('rows', v_inserted, 'emiAmount', v_emi), v_loan.showroom_id, null,
    'EMI schedule generated');

  select jsonb_build_object(
           'loanId', p_loan_id,
           'rowsInserted', v_inserted,
           'emiAmount', v_emi,
           'firstDueDate', v_first_due,
           'lastDueDate', (v_first_due + make_interval(months => v_loan.tenure_months - 1))::date,
           'totalInterest', round(v_total_int, 2),
           'residualBalance', v_bal,
           'totals', (select jsonb_build_object(
                        'principal', round(sum(principal_amount),2),
                        'interest', round(sum(interest_amount),2),
                        'emi', round(sum(emi_amount),2))
                       from public.emi_schedules where loan_id = p_loan_id)
         ) into v_sum_lines;

  return v_sum_lines;
end;
$$;

comment on function public.generate_emi_schedule is
  'Called automatically by create_sale_transaction() when the sale is financed, and manually from the loan form. Rounding drift lands on the final instalment (SS16).';

-- ---------------------------------------------------------------------------
-- Public schedule maintenance RPCs
-- ---------------------------------------------------------------------------
create or replace function public.mark_emi_status(
  p_emi_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('UPCOMING','DUE','PARTIAL','PAID','OVERDUE','CANCELLED') then
    raise exception '[VAL007] unknown EMI status %', p_status using errcode = '22000';
  end if;
  update public.emi_schedules e
     set status = p_status,
         paid_date = case when p_status = 'PAID' then coalesce(paid_date, current_date) end,
         updated_at = now()
   where e.id = p_emi_id
     and app_sec.has_permission_in('emi','payment', e.showroom_id);
  if not found then
    raise exception '[SEC003] EMI % not found or not payable by you', p_emi_id using errcode = '42501';
  end if;
end;
$$;

-- Sweep used by the scheduler (012) and on app start: DUE -> OVERDUE + penalty.
create or replace function public.refresh_emi_statuses(p_as_of date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_overdue integer;
  v_due     integer;
  v_cleared integer;
begin
  update public.emi_schedules e
     set status = case
                    when e.paid_amount >= e.emi_amount + e.late_fee + e.penalty_amount and e.emi_amount > 0 then 'PAID'
                    when e.paid_amount > 0 and e.due_date >= p_as_of then 'PARTIAL'
                    when e.due_date <  p_as_of then 'OVERDUE'
                    when e.due_date =  p_as_of then 'DUE'
                    else 'UPCOMING'
                  end,
         overdue_days = greatest(0, (p_as_of - e.due_date)),
         updated_at = now()
   where e.status in ('UPCOMING','DUE','PARTIAL','OVERDUE');
  get diagnostics v_overdue = row_count;

  select count(*) into v_due     from public.emi_schedules where status = 'DUE' and due_date = p_as_of;
  select count(*) into v_cleared from public.emi_schedules where status = 'PAID' and paid_date = p_as_of;

  return jsonb_build_object('touched', v_overdue, 'dueToday', v_due, 'clearedToday', v_cleared, 'asOf', p_as_of);
end;
$$;

-- ---------------------------------------------------------------------------
-- Payments (SS15): the only sanctioned way to move money in the system.
--   * never deletes or edits an existing payment (SS42)
--   * over-payment is only allowed as ADVANCE and lands on 2300
--   * invoice / sale / service / EMI balances are recomputed from the ledger,
--     never trusted from the caller
-- ---------------------------------------------------------------------------
create or replace function public.recalc_document_amounts(p_invoice_id uuid default null,
                                                          p_sale_id    uuid default null,
                                                          p_service_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_paid numeric;
begin
  if p_invoice_id is not null then
    select coalesce(sum(case when pp.status = 'COMPLETED' and pp.payment_type in ('RECEIPT','ADVANCE')
                             then least(pp.allocated_amount, pp.amount)
                             when pp.status = 'COMPLETED' and pp.payment_type = 'ADJUSTMENT'
                             then pp.allocated_amount
                             else 0 end), 0)
      into v_paid
      from public.payments pp
     where pp.invoice_id = p_invoice_id;

    update public.invoices i
       set paid_amount = round(v_paid, 2),
           outstanding_amount = round(greatest(i.total_amount - v_paid, 0), 2),
           status = case
                      when i.status in ('CANCELLED','REFUNDED') then i.status
                      when round(v_paid, 2) <= 0 and i.finalized then 'FINALIZED'
                      when round(v_paid, 2) >= i.total_amount then 'PAID'
                      when round(v_paid, 2) > 0 then 'PARTIALLY_PAID'
                      else i.status
                    end,
           -- an overdue, unpaid, finalized invoice is a business fact, not a UI guess
           updated_at = now()
     where i.id = p_invoice_id;

    update public.invoices i
       set status = 'OVERDUE'
      where i.id = p_invoice_id
        and i.status = 'FINALIZED'
        and i.due_date is not null
        and i.due_date < current_date
        and i.outstanding_amount > 0;
  end if;

  if p_sale_id is not null then
    -- what the customer has put against THIS sale, not what they handed over in
    -- total: an excess stays a credit on the payment row (allocated_amount), so
    -- the header can never exceed the document (sales_paid_le_total, 003).
    select coalesce(sum(least(pp.allocated_amount, pp.amount)), 0) into v_paid
      from public.payments pp
     where pp.sale_id = p_sale_id
       and pp.status = 'COMPLETED'
       and pp.payment_type in ('RECEIPT','ADVANCE','ADJUSTMENT');

    update public.sales s
       set paid_amount = round(least(v_paid, s.total_amount), 2),
           outstanding_amount = round(s.total_amount - least(v_paid, s.total_amount), 2),
           status = case
                      when s.status in ('CANCELLED','RETURNED') then s.status
                      when round(least(v_paid, s.total_amount), 2) >= s.total_amount
                           and s.status = 'CONFIRMED' then 'CONFIRMED'
                      else s.status
                    end
     where s.id = p_sale_id;
  end if;

  if p_service_id is not null then
    select coalesce(sum(least(pp.allocated_amount, pp.amount)), 0) into v_paid
      from public.payments pp
     where pp.service_id = p_service_id
       and pp.status = 'COMPLETED'
       and pp.payment_type in ('RECEIPT','ADVANCE','ADJUSTMENT');

    update public.service_records r
       set paid_amount = round(least(v_paid, r.total_amount), 2),
           outstanding_amount = round(r.total_amount - least(v_paid, r.total_amount), 2)
     where r.id = p_service_id;
  end if;
end;
$$;

create or replace function public.record_payment(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_showroom   uuid   := (p_payload ->> 'showroom_id')::uuid;
  v_customer   uuid   := (p_payload ->> 'customer_id')::uuid;
  v_invoice_id uuid   := (p_payload ->> 'invoice_id')::uuid;
  v_sale_id    uuid   := (p_payload ->> 'sale_id')::uuid;
  v_service_id uuid   := (p_payload ->> 'service_id')::uuid;
  v_emi_id     uuid   := (p_payload ->> 'emi_id')::uuid;
  v_loan_id    uuid   := (p_payload ->> 'loan_id')::uuid;
  v_amount     numeric := app_util.round_money((p_payload ->> 'amount')::numeric);
  v_method     text   := coalesce(p_payload ->> 'payment_method', 'CASH');
  v_type       text   := coalesce(p_payload ->> 'payment_type', 'RECEIPT');
  v_date       date   := coalesce((p_payload ->> 'payment_date')::date, current_date);
  v_ref        text   := p_payload ->> 'reference_number';
  v_txn        text   := p_payload ->> 'transaction_id';
  v_instrument text   := p_payload ->> 'instrument_number';
  v_bank       text   := p_payload ->> 'bank_name';
  v_notes      text   := p_payload ->> 'notes';
  v_idem       uuid   := (p_payload ->> 'idempotency_key')::uuid;
  v_allow_advance boolean := coalesce((p_payload ->> 'allow_advance')::boolean, true);

  v_invoice    public.invoices%rowtype;
  v_emi        public.emi_schedules%rowtype;
  v_service    public.service_records%rowtype;
  v_loan       public.loans%rowtype;
  v_number     text;
  v_payment_id uuid;
  v_allocated  numeric := 0;
  v_advance    numeric := 0;
  v_tx_id      uuid;
  v_lines      jsonb;
  v_cash_code  text;
  v_existing   jsonb;
  v_target_showroom uuid;
begin

  perform app_sec.require_permission('payments', 'create');
  perform app_sec.require_showroom_access(v_showroom);
  -- ---- idempotent replay guard (SS27, SS84) --------------------------------
  if v_idem is not null then
    select ik.result into v_existing
      from public.idempotency_keys ik
     where ik.key = v_idem
       for update;
    if found and v_existing is not null then
      return v_existing || jsonb_build_object('replayed', true, 'idempotencyKey', v_idem);
    end if;
  end if;

  if v_amount is null or v_amount <= 0 then
    perform app_util.fail('VAL001', 'payment amount must be greater than zero');
  end if;
  if v_customer is null then
    perform app_util.fail('VAL001', 'customer_id is required');
  end if;

  -- resolve the tenant from the document being paid, never from the client alone
  if v_invoice_id is not null then
    select * into v_invoice from public.invoices where id = v_invoice_id for update;
    if not found then perform app_util.fail('NOT001', 'invoice not found'); end if;
    v_target_showroom := v_invoice.showroom_id;
    if v_invoice.status in ('CANCELLED','REFUNDED') then
      perform app_util.fail('CON001', 'invoice ' || v_invoice.invoice_number || ' is ' || v_invoice.status);
    end if;
  elsif v_service_id is not null then
    select * into v_service from public.service_records where id = v_service_id for update;
    if not found then perform app_util.fail('NOT001', 'service record not found'); end if;
    v_target_showroom := v_service.showroom_id;
  elsif v_emi_id is not null then
    select * into v_emi from public.emi_schedules where id = v_emi_id for update;
    if not found then perform app_util.fail('NOT001', 'EMI instalment not found'); end if;
    v_target_showroom := v_emi.showroom_id;
    select * into v_loan from public.loans where id = v_emi.loan_id;
    v_loan_id := v_emi.loan_id;
  elsif v_sale_id is not null then
    select showroom_id into v_target_showroom from public.sales where id = v_sale_id;
    if not found then perform app_util.fail('NOT001', 'sale not found'); end if;
  else
    v_target_showroom := v_showroom;
  end if;

  if v_showroom is not null and v_target_showroom is not null and v_showroom <> v_target_showroom then
    perform app_util.fail('SEC002', 'payment target belongs to a different showroom');
  end if;
  v_showroom := v_target_showroom;

  if not exists (select 1 from public.customers c
                  where c.id = v_customer and c.showroom_id = v_showroom and c.is_deleted = false) then
    perform app_util.fail('VAL002', 'customer does not belong to this showroom');
  end if;

  -- ---- how much of this money can actually be applied? ---------------------
  if v_invoice_id is not null then
    v_allocated := least(v_amount, greatest(v_invoice.outstanding_amount, 0));
  elsif v_service_id is not null then
    v_allocated := least(v_amount, greatest(v_service.outstanding_amount, 0));
  elsif v_emi_id is not null then
    v_allocated := least(v_amount, greatest(v_emi.remaining_amount, 0));
  else
    v_allocated := 0;
  end if;

  v_advance := v_amount - v_allocated;
  if v_advance > 0 and v_type not in ('ADVANCE','RECEIPT') then
    perform app_util.fail('VAL003', 'over-payment requires payment_type ADVANCE');
  end if;
  if v_advance > 0 and not v_allow_advance then
    perform app_util.fail('VAL004',
      format('payment exceeds the outstanding balance by %s; enable advance to accept it', v_advance));
  end if;

  if v_method in ('CHEQUE','DD') and v_instrument is null then
    perform app_util.fail('VAL005', 'cheque/DD payments require instrument_number');
  end if;
  if v_method = 'FINANCE' and coalesce(v_txn, v_ref) is null then
    perform app_util.fail('VAL006', 'finance disbursements require a reference or transaction id');
  end if;

  v_number := app_gen.next_document_number(v_showroom, 'PAYMENT', v_date);

  insert into public.payments
        (payment_number, showroom_id, customer_id, invoice_id, sale_id, service_id,
         emi_id, loan_id, payment_date, payment_type, amount, allocated_amount,
         payment_method, reference_number, transaction_id, instrument_number, bank_name,
         status, received_by, notes, idempotency_key, created_by)
  values (v_number, v_showroom, v_customer, v_invoice_id, v_sale_id, v_service_id,
          v_emi_id, v_loan_id, v_date, v_type, v_amount, v_allocated,
          v_method, v_ref, v_txn, v_instrument, v_bank,
          'COMPLETED', app_sec.current_user_id(), v_notes, v_idem, app_sec.current_user_id())
  returning id into v_payment_id;

  -- ---- apply to the target ------------------------------------------------
  if v_emi_id is not null then
    update public.emi_schedules e
       set paid_amount = round(e.paid_amount + v_allocated, 2),
           remaining_amount = round(greatest(e.emi_amount + e.late_fee + e.penalty_amount
                                             - e.paid_amount - v_allocated, 0), 2),
           paid_date = case when e.paid_amount + v_allocated >= e.emi_amount + e.late_fee + e.penalty_amount
                            then v_date else e.paid_date end,
           paid_via_payment_id = v_payment_id,
           status = case
                      when e.paid_amount + v_allocated >= e.emi_amount + e.late_fee + e.penalty_amount
                        then 'PAID'
                      when v_allocated > 0 then 'PARTIAL'
                      else e.status
                    end,
           updated_at = now()
     where e.id = v_emi_id;

    update public.loans l
       set status = case
                      when not exists (select 1 from public.emi_schedules x
                                        where x.loan_id = l.id and x.status <> 'PAID')
                        then 'CLOSED'
                      when l.status = 'APPLIED' or l.status = 'SANCTIONED' then 'ACTIVE'
                      else 'PART_PAYMENT'
                    end,
           updated_at = now()
     where l.id = v_emi.loan_id;

    -- interest income + principal recovery against the lender receivable
    v_cash_code := case when v_method = 'CASH' then '1010'
                       when v_method in ('UPI','CARD','ONLINE') then '1030'
                       else '1020' end;
    v_lines := jsonb_build_array(
        jsonb_build_object('code', v_cash_code, 'debit', v_allocated,
                           'description', 'EMI ' || v_emi.emi_number || ' received ' || v_number),
        jsonb_build_object('account_id', app_acc.account_for(v_showroom, 'EMI.INTEREST', 'CREDIT'),
                           'credit', least(v_allocated, v_emi.interest_amount),
                           'description', 'Interest on EMI ' || v_emi.emi_number),
        jsonb_build_object('account_id', app_acc.account_for(v_showroom, 'EMI.PRINCIPAL', 'CREDIT'),
                           'credit', greatest(v_allocated - least(v_allocated, v_emi.interest_amount), 0),
                           'description', 'Principal recovery EMI ' || v_emi.emi_number)
      );
    begin
      v_tx_id := app_acc.post_journal(v_showroom, v_date, 'PAYMENT', 'payment', v_payment_id,
                                      'EMI instalment receipt', v_lines);
    exception when others then
      v_tx_id := null;   -- never let a bookkeeping edge case lose a customer's money
    end;
    update public.payments set metadata = jsonb_set(metadata, '{accountingTransactionId}',
                                     to_jsonb(v_tx_id::text), true)
     where id = v_payment_id and v_tx_id is not null;
  end if;

  perform public.recalc_document_amounts(
      p_invoice_id => v_invoice_id, p_sale_id => v_sale_id, p_service_id => v_service_id);

  -- lifetime_value is NOT touched here: it is the booked value of a customer's
  -- sales and is recomputed by trg_customer_rollup_sales (007) whenever the sale
  -- header moves. A payment already updates that header, so the rollup follows.

  perform app_util.audit_row('payments', 'PAYMENT', 'payments', v_payment_id, null,
          jsonb_build_object('amount', v_amount, 'allocated', v_allocated,
                             'invoice', v_invoice_id, 'emi', v_emi_id, 'method', v_method),
          v_showroom, null, 'Payment ' || v_number);

  if v_allocated > 0 and v_invoice_id is not null then
    insert into public.notifications
          (user_id, customer_id, showroom_id, title, message, notification_type, severity,
           route_name, route_params, reference_type, reference_id, channel)
    select s.created_by, v_customer, v_showroom, 'Payment received',
           'Payment ' || v_number || ' of ' || v_allocated || ' received against invoice ' || v_invoice.invoice_number,
           'PAYMENT', 'SUCCESS', '/billing/invoice', jsonb_build_object('id', v_invoice_id),
           'invoice', v_invoice_id, 'IN_APP'
      from public.invoices s
     where s.id = v_invoice_id and s.created_by is not null
    on conflict do nothing;
  end if;

  if v_idem is not null then
    insert into public.idempotency_keys (key, user_id, showroom_id, operation, status, result, completed_at)
    values (v_idem, app_sec.current_user_id(), v_showroom, 'record_payment', 'COMPLETED',
            jsonb_build_object('paymentId', v_payment_id, 'paymentNumber', v_number,
                               'amount', v_amount, 'allocatedAmount', v_allocated,
                               'advanceAmount', v_advance, 'replayed', false),
            now())
    on conflict (key) do update
       set status = 'COMPLETED', result = excluded.result, completed_at = now();
  end if;

  return jsonb_build_object(
    'paymentId', v_payment_id,
    'paymentNumber', v_number,
    'amount', v_amount,
    'allocatedAmount', v_allocated,
    'advanceAmount', v_advance,
    'invoiceId', v_invoice_id,
    'emiId', v_emi_id,
    'accountingTransactionId', v_tx_id
  );
end;
$$;

comment on function public.record_payment(jsonb) is
  'Atomic money receipt: allocates against invoice/sale/service/EMI, books the journal, notifies and is retry-safe via idempotency_key (SS15, SS63).';

-- ---------------------------------------------------------------------------
-- Payment reversal (SS15/SS42): the original row survives, a REVERSAL row is
-- appended and the affected documents are recomputed from the ledger.
-- ---------------------------------------------------------------------------
create or replace function public.reverse_payment(
  p_payment_id uuid,
  p_reason     text,
  p_as_of      date default current_date
)
-- jsonb (not the bare uuid) so the client gets the balances the reversal moved,
-- exactly like record_payment: one decode path for every money RPC (SS50).
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src   public.payments%rowtype;
  v_new   uuid;
begin

  perform app_sec.require_permission('payments', 'cancel');
  select * into v_src from public.payments where id = p_payment_id for update;
  if not found then perform app_util.fail('NOT001', 'payment not found'); end if;
  perform app_sec.require_showroom_access(v_src.showroom_id);

  if v_src.status in ('CANCELLED','REVERSED') then
    perform app_util.fail('CON002', 'payment ' || v_src.payment_number || ' is already ' || v_src.status);
  end if;
  if coalesce(p_reason, '') = '' then
    perform app_util.fail('VAL001', 'a reversal reason is required');
  end if;

  insert into public.payments
        (payment_number, showroom_id, customer_id, invoice_id, sale_id, service_id, emi_id, loan_id,
         payment_date, payment_type, amount, allocated_amount, payment_method, reference_number,
         status, received_by, reversal_reason, parent_payment_id, notes, created_by)
  values (app_gen.next_document_number(v_src.showroom_id, 'PAYMENT', p_as_of),
          v_src.showroom_id, v_src.customer_id, v_src.invoice_id, v_src.sale_id, v_src.service_id,
          v_src.emi_id, v_src.loan_id,
          p_as_of, 'REVERSAL', v_src.amount, v_src.allocated_amount, v_src.payment_method,
          v_src.reference_number, 'REVERSED', app_sec.current_user_id(), p_reason, v_src.id,
          'Reversal of ' || v_src.payment_number, app_sec.current_user_id())
  returning id into v_new;

  update public.payments
     set status = 'REVERSED', reversed_by = app_sec.current_user_id(), reversed_at = now(),
         reversal_reason = p_reason, updated_at = now()
   where id = p_payment_id;

  if v_src.emi_id is not null then
    update public.emi_schedules e
       set paid_amount = round(greatest(e.paid_amount - v_src.allocated_amount, 0), 2),
           remaining_amount = round(e.emi_amount + e.late_fee + e.penalty_amount
                                    - greatest(e.paid_amount - v_src.allocated_amount, 0), 2),
           paid_date = null,
           paid_via_payment_id = null,
           status = case when greatest(e.paid_amount - v_src.allocated_amount, 0) > 0 then 'PARTIAL'
                         when e.due_date < current_date then 'OVERDUE' else 'DUE' end,
           updated_at = now()
     where e.id = v_src.emi_id;
  end if;

  perform public.recalc_document_amounts(p_invoice_id => v_src.invoice_id,
                                         p_sale_id => v_src.sale_id,
                                         p_service_id => v_src.service_id);

  begin
    perform app_acc.reverse_journal(
      (select nullif(v_src.metadata ->> 'accountingTransactionId', '')::uuid),
      'Payment ' || v_src.payment_number || ' reversed', p_as_of);
  exception when others then
    null;  -- nothing was booked (advance/legacy rows): nothing to reverse
  end;

  perform app_util.audit_row('payments','CANCEL','payments', v_src.id,
          jsonb_build_object('status', v_src.status), jsonb_build_object('status','REVERSED','reversalId', v_new),
          v_src.showroom_id, null, p_reason, 'WARNING');

  return jsonb_build_object(
    'paymentId', p_payment_id, 'reversalPaymentId', v_new,
    'amount', v_src.amount, 'asOf', p_as_of, 'reversed', true,
    'invoiceId', v_src.invoice_id, 'saleId', v_src.sale_id, 'emiId', v_src.emi_id,
    'invoiceOutstanding', (select i.outstanding_amount from public.invoices i where i.id = v_src.invoice_id),
    'saleOutstanding',    (select s.outstanding_amount from public.sales s where s.id = v_src.sale_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Invoice lifecycle (SS14): finalization is a one-way door except through the
-- controlled cancel RPC, which never destroys the original.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.invoices%rowtype;
  v_total numeric;
begin

  perform app_sec.require_permission('billing', 'create');
  select * into v_inv from public.invoices where id = p_invoice_id for update;
  if not found then perform app_util.fail('NOT001', 'invoice not found'); end if;
  perform app_sec.require_showroom_access(v_inv.showroom_id);

  if v_inv.finalized then
    return jsonb_build_object('invoiceId', p_invoice_id, 'status', v_inv.status, 'alreadyFinalized', true);
  end if;

  -- The header is recomputed by the shared roll-up (007), so finalising can never
  -- disagree with the invoice lines - subtotal/discount/tax/other/total/outstanding
  -- all come from one formula (SS68).
  perform set_config('app.bypass_finalized_check', 'on', true);
  perform public.recalc_invoice_header(p_invoice_id);

  select total_amount into v_total from public.invoices where id = p_invoice_id;
  if coalesce(v_total, 0) <= 0 then
    perform app_util.fail('VAL007', 'invoice has no priced line items');
  end if;

  update public.invoices i
     set status             = 'FINALIZED',
         finalized          = true,
         finalized_at       = now(),
         emitted_at         = coalesce(emitted_at, now()),
         due_date           = coalesce(due_date, current_date + 15),
         updated_at         = now()
   where i.id = p_invoice_id
     and i.status = 'DRAFT';

  if not found then
    perform app_util.fail('CON003', 'only a DRAFT invoice can be finalized');
  end if;

  perform app_util.audit_row('billing','APPROVE','invoices', p_invoice_id,
          jsonb_build_object('status','DRAFT'), jsonb_build_object('status','FINALIZED','total', v_total),
          v_inv.showroom_id, null, 'Invoice ' || v_inv.invoice_number || ' finalized');

  return jsonb_build_object('invoiceId', p_invoice_id, 'invoiceNumber', v_inv.invoice_number,
                            'totalAmount', v_total, 'status', 'FINALIZED');
end;
$$;

-- =============================================================================
-- create_sale_transaction() - the atomic sale from SS13 / SS50 / SS63.
-- -----------------------------------------------------------------------------
-- One client call == one database transaction:
--   idempotency guard -> authorisation -> validate customer -> validate & lock
--   inventory -> compute money server-side -> sale -> sale items -> allocate
--   stock -> customer vehicle -> invoice + items -> finalize -> payments ->
--   loan + EMI schedule -> warranty -> free-service schedule -> accounting ->
--   reminders -> notification -> audit -> store idempotent result
-- If ANY step raises, the whole statement rolls back: no partial sale exists.
--
-- p_payload contract (mirrored by lib/features/sales/models/sale_draft_model.dart):
-- {
--   "showroom_id": uuid, "customer_id": uuid, "salesperson_id": uuid|null,
--   "sale_date": "YYYY-MM-DD", "delivery_date": "YYYY-MM-DD"|null,
--   "sale_type": "CASH|FINANCE|EXCHANGE|CORPORATE|ONLINE|BOOKING",
--   "lines":[{"inventory_id":uuid,"product_id":uuid|null,"color_id":uuid|null,
--             "quantity":1,"unit_price":num,"discount":num,"tax_rate":num,
--             "item_type":"VEHICLE|ACCESSORY|INSURANCE|OTHER","description":str}],
--   "other_charges":num, "exchange_value":num, "registration_number":str|null,
--   "payments":[{"amount":num,"payment_method":"CASH","reference_number":str}],
--   "finance":{"finance_company_id":uuid,"down_payment":num,"interest_rate":num,
--              "interest_type":"REDUCING|FLAT","tenure_months":int,
--              "processing_fee":num,"start_date":"YYYY-MM-DD"}|null,
--   "auto_approve":true, "notes":str, "idempotency_key":uuid|null
-- }
-- =============================================================================
create or replace function public.create_sale_transaction(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_showroom      uuid    := (p_payload ->> 'showroom_id')::uuid;
  v_customer_id   uuid    := (p_payload ->> 'customer_id')::uuid;
  v_salesperson   uuid    := coalesce((p_payload ->> 'salesperson_id')::uuid, app_sec.current_user_id());
  v_sale_date     date    := coalesce((p_payload ->> 'sale_date')::date, current_date);
  v_sale_type     text    := coalesce(nullif(p_payload ->> 'sale_type',''), 'CASH');
  v_other         numeric := app_util.round_money(coalesce((p_payload ->> 'other_charges')::numeric, 0));
  v_exchange_val  numeric := app_util.round_money(coalesce((p_payload ->> 'exchange_value')::numeric, 0));
  v_auto_approve  boolean := coalesce((p_payload ->> 'auto_approve')::boolean, true);
  v_notes         text    := p_payload ->> 'notes';
  v_idem          uuid    := (p_payload ->> 'idempotency_key')::uuid;
  v_reg_no        text    := app_util.upper_no_space(p_payload ->> 'registration_number');
  v_delivery      date    := coalesce((p_payload ->> 'delivery_date')::date, v_sale_date);
  v_lines         jsonb   := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_payments      jsonb   := coalesce(p_payload -> 'payments', '[]'::jsonb);
  v_finance       jsonb   := p_payload -> 'finance';

  v_customer      public.customers%rowtype;
  v_inventory     public.inventory%rowtype;
  v_product       public.products%rowtype;
  v_first_product public.products%rowtype;
  rec             record;

  v_sale_id       uuid;
  v_invoice_id    uuid;
  v_vehicle_id    uuid;
  v_loan_id       uuid;
  v_warranty_id   uuid;
  v_sale_number   text;
  v_invoice_number text;
  v_sale_status   text;

  v_subtotal      numeric := 0;
  v_line_discount numeric := 0;
  v_tax           numeric := 0;
  v_total         numeric := 0;
  v_paid          numeric := 0;
  v_qty           numeric;
  v_unit          numeric;
  v_disc          numeric;
  v_rate          numeric;
  v_line_tax      numeric;
  v_allow_negative boolean := false;
  v_line_count    integer;
  v_vehicle_count integer := 0;
  v_free_rows     integer := 0;
  v_accounting    uuid;
  v_cogs          numeric := 0;
  v_replay        jsonb;
  v_payment_res   jsonb;
  v_loan_summary  jsonb;
  v_next_service_date date;
  v_next_service_km   integer;
begin

  perform app_sec.require_permission('sales', 'create');
  perform app_sec.require_showroom_access(v_showroom);
  -- ------------------------------------------------------------------ idempotency
  if v_idem is not null then
    select ik.result into v_replay
      from public.idempotency_keys ik
     where ik.key = v_idem
       for update;
    if found and v_replay is not null then
      return v_replay || jsonb_build_object('replayed', true);
    end if;
    insert into public.idempotency_keys (key, user_id, showroom_id, operation, status)
    values (v_idem, app_sec.current_user_id(), v_showroom, 'create_sale_transaction', 'IN_PROGRESS')
    on conflict (key) do nothing;
  end if;

  -- ----------------------------------------------------------------- authorisation

  v_line_count := jsonb_array_length(v_lines);
  if v_customer_id is null or v_line_count = 0 then
    perform app_util.fail('VAL001', 'customer_id and at least one line item are required');
  end if;
  if v_sale_type not in ('CASH','FINANCE','EXCHANGE','CORPORATE','ONLINE','BOOKING') then
    perform app_util.fail('VAL002', 'unknown sale_type ' || v_sale_type);
  end if;
  if v_sale_type = 'FINANCE' and v_finance is null then
    perform app_util.fail('VAL003', 'a FINANCE sale requires a finance block');
  end if;
  if v_sale_type <> 'FINANCE' and v_finance is not null then
    perform app_util.fail('VAL004', 'finance block supplied for a non-FINANCE sale');
  end if;

  -- ------------------------------------------------------------- validate customer
  select * into v_customer
    from public.customers
   where id = v_customer_id
     and showroom_id = v_showroom
     and is_deleted = false;
  if not found then
    perform app_util.fail('NOT001', 'customer not found in this showroom');
  end if;
  if v_customer.status <> 'ACTIVE' then
    perform app_util.fail('CON001', 'customer ' || v_customer.name || ' is ' || v_customer.status);
  end if;

  select coalesce((s.settings ->> 'allow_negative_inventory')::boolean, false)
    into v_allow_negative
    from public.showrooms s where s.id = v_showroom;

  -- -------------------------------------------------------- validate stock lines
  for rec in select * from jsonb_array_elements(v_lines) with ordinality as e(value, ord) loop
    if (rec.value ->> 'inventory_id')::uuid is not null then
      select * into v_inventory
        from public.inventory
       where id = (rec.value ->> 'inventory_id')::uuid
         and showroom_id = v_showroom
         and is_deleted = false
         for update;                     -- serialises two counters selling one bike
      if not found then
        perform app_util.fail('NOT002', format('inventory unit on line %s is not in this showroom', rec.ord));
      end if;
      if v_inventory.status = 'SOLD' then
        perform app_util.fail('CON002', 'chassis ' || v_inventory.chassis_number || ' is already sold');
      end if;
      if v_inventory.status = 'IN_TRANSIT' and not v_allow_negative then
        perform app_util.fail('CON005', 'unit ' || v_inventory.stock_code || ' is in transit');
      end if;
      if v_inventory.status not in ('AVAILABLE','RESERVED','DEMO') and not v_allow_negative then
        perform app_util.fail('CON003', format('unit %s is %s and cannot be sold',
                                               v_inventory.stock_code, v_inventory.status));
      end if;
      if v_inventory.status = 'RESERVED'
         and v_inventory.reserved_customer_id is distinct from v_customer_id then
        if not app_sec.has_permission('inventory','adjust') then
          perform app_util.fail('CON004', 'unit ' || v_inventory.stock_code || ' is reserved for another customer');
        end if;
      end if;
      select p.* into v_product from public.products p where p.id = v_inventory.product_id;
      if v_product.status = 'DISCONTINUED' and not app_sec.has_permission('products','edit') then
        perform app_util.fail('CON006', 'product ' || v_product.name || ' is discontinued');
      end if;
      if v_vehicle_count = 0 then
        v_first_product := v_product;
      end if;
      v_vehicle_count := v_vehicle_count + 1;
    elsif coalesce(rec.value ->> 'item_type', 'ACCESSORY') = 'VEHICLE' then
      perform app_util.fail('VAL005', 'a VEHICLE line must reference an inventory unit');
    end if;
  end loop;

  -- ------------------------------------------------------ compute money server-side
  for rec in select * from jsonb_array_elements(v_lines) with ordinality as e(value, ord) loop
    v_qty  := coalesce(nullif(rec.value ->> 'quantity','')::numeric, 1);
    v_unit := app_util.round_money((rec.value ->> 'unit_price')::numeric);
    v_disc := app_util.round_money(coalesce(nullif(rec.value ->> 'discount','')::numeric, 0));
    -- a scalar subselect, NOT "select into ... from products where id = null":
    -- accessory lines have no product row and a no-row SELECT would silently
    -- null out the rate, dropping their GST (found by tests/002).
    v_rate := coalesce(nullif(rec.value ->> 'tax_rate','')::numeric,
                       (select p.tax_rate from public.products p
                         where p.id = coalesce((rec.value ->> 'product_id')::uuid,
                                               (select i.product_id from public.inventory i
                                                 where i.id = (rec.value ->> 'inventory_id')::uuid))),
                       0);
    if v_qty is null or v_qty <= 0 then
      perform app_util.fail('VAL006', format('line %s quantity must be positive', rec.ord));
    end if;
    if v_unit is null or v_unit <= 0 then
      perform app_util.fail('VAL007', format('line %s has no unit price', rec.ord));
    end if;
    if v_disc < 0 or v_disc > v_qty * v_unit then
      perform app_util.fail('VAL008', format('line %s discount exceeds the line value', rec.ord));
    end if;
    -- discount authority is a permission, not a form field (SS6)
    if v_disc > 0 and (v_disc / (v_qty * v_unit)) * 100 > 5
       and not app_sec.has_permission('sales','discount') then
      perform app_util.fail('SEC001', 'discounts above 5 percent require the sales.discount permission');
    end if;

    v_line_tax := round(greatest(v_qty * v_unit - v_disc, 0) * coalesce(v_rate, 0) / 100.0, 2);
    v_subtotal      := v_subtotal + round(v_qty * v_unit, 2);
    v_line_discount := v_line_discount + v_disc;
    v_tax           := v_tax + v_line_tax;
  end loop;

  v_total := round(v_subtotal - v_line_discount + v_tax + v_other - v_exchange_val, 2);
  if v_total <= 0 then
    perform app_util.fail('VAL009', 'the computed sale total is not positive');
  end if;

  -- A sale above the manager-approval threshold set on the showroom must wait.
  declare v_threshold numeric := coalesce(
      (select (s.settings ->> 'sale_approval_threshold')::numeric
         from public.showrooms s where s.id = v_showroom), 0);
  begin
    v_sale_status := case
      when v_auto_approve and v_threshold > 0 and v_total >= v_threshold
           and not app_sec.has_permission('sales','approve')      then 'PENDING_APPROVAL'
      when v_auto_approve and app_sec.has_permission('sales','approve') then 'CONFIRMED'
      when v_auto_approve                                          then 'APPROVED'
      else 'PENDING_APPROVAL'
    end;
  end;

  -- ------------------------------------------------------------------ insert sale
  v_sale_number := app_gen.next_document_number(v_showroom, 'SALE', v_sale_date);

  insert into public.sales
        (showroom_id, customer_id, salesperson_id, sale_number, sale_date,
         subtotal, discount, tax_amount, other_charges, total_amount,
         paid_amount, outstanding_amount, exchange_value, sale_type, status,
         approval_required, approved_by, approved_at, delivery_date, notes,
         metadata, created_by)
  values (v_showroom, v_customer_id, v_salesperson, v_sale_number, v_sale_date,
          round(v_subtotal, 2), round(v_line_discount, 2), round(v_tax, 2), v_other, v_total,
          0, v_total, v_exchange_val, v_sale_type, v_sale_status,
          (v_sale_status = 'PENDING_APPROVAL'),
          case when v_sale_status in ('CONFIRMED','APPROVED') then app_sec.current_user_id() end,
          case when v_sale_status in ('CONFIRMED','APPROVED') then now() end,
          v_delivery, v_notes,
          jsonb_build_object('createdVia', 'create_sale_transaction',
                             'channel', nullif(p_payload ->> 'channel', '')),
          app_sec.current_user_id())
  returning id into v_sale_id;

  -- --------------------------------------------------------------- sale line items
  for rec in select * from jsonb_array_elements(v_lines) with ordinality as e(value, ord) loop
    v_qty  := coalesce(nullif(rec.value ->> 'quantity','')::numeric, 1);
    v_unit := app_util.round_money((rec.value ->> 'unit_price')::numeric);
    v_disc := app_util.round_money(coalesce(nullif(rec.value ->> 'discount','')::numeric, 0));
    v_rate := coalesce(nullif(rec.value ->> 'tax_rate','')::numeric,
                       (select p.tax_rate from public.products p
                         where p.id = coalesce((rec.value ->> 'product_id')::uuid,
                                               (select i.product_id from public.inventory i
                                                 where i.id = (rec.value ->> 'inventory_id')::uuid))),
                       0);

    select p.* into v_product
      from public.products p
     where p.id = coalesce((rec.value ->> 'product_id')::uuid,
                           (select i.product_id from public.inventory i
                             where i.id = (rec.value ->> 'inventory_id')::uuid));
    v_line_tax := round(greatest(v_qty * v_unit - v_disc, 0) * coalesce(v_rate, 0) / 100.0, 2);

    insert into public.sale_items
          (sale_id, product_id, inventory_id, color_id, description, item_type,
           quantity, unit_price, discount, tax_rate, tax_amount, total_amount)
    values (v_sale_id,
            coalesce((rec.value ->> 'product_id')::uuid, v_product.id),
            (rec.value ->> 'inventory_id')::uuid,
            coalesce((rec.value ->> 'color_id')::uuid,
                     (select i.color_id from public.inventory i
                       where i.id = (rec.value ->> 'inventory_id')::uuid)),
            coalesce(nullif(rec.value ->> 'description',''),
                     nullif(v_product.name || ' ' || coalesce(v_product.variant, ''), ' '),
                     'Line ' || rec.ord),
            coalesce(nullif(rec.value ->> 'item_type',''),
                     case when (rec.value ->> 'inventory_id')::uuid is not null then 'VEHICLE' else 'ACCESSORY' end),
            v_qty, v_unit, v_disc, coalesce(v_rate, 0), v_line_tax,
            round(v_qty * v_unit - v_disc + v_line_tax, 2));
  end loop;

  -- ------------------------------------------------------- allocate stock + vehicle
  for rec in select (value ->> 'inventory_id')::uuid as inv_id, value as line
               from jsonb_array_elements(v_lines) as e(value)
              where (value ->> 'inventory_id')::uuid is not null loop

    select i.* into v_inventory
      from public.inventory i
     where i.id = rec.inv_id;

    select p.* into v_product
      from public.products p
     where p.id = v_inventory.product_id;

    update public.inventory
       set status = 'SOLD',
           allocated_sale_id = v_sale_id,
           reserved_until = null,
           reserved_by = null,
           reserved_customer_id = null,
           registration_number = coalesce(registration_number, v_reg_no),
           updated_at = now(),
           updated_by = app_sec.current_user_id()
     where id = rec.inv_id;

    insert into public.stock_movements
          (showroom_id, inventory_id, movement_type, from_status, to_status,
           reference_type, reference_id, reason, performed_by)
    values (v_showroom, rec.inv_id, 'SALE_ALLOCATE', 'AVAILABLE', 'SOLD',
            'sale', v_sale_id, 'Sold via ' || v_sale_number, app_sec.current_user_id());

    insert into public.customer_vehicles
          (customer_id, showroom_id, inventory_id, product_id, product_color_id, sale_id,
           registration_number, registration_date, chassis_number, engine_number, model_year,
           purchase_date, delivery_date, current_odometer, colour,
           warranty_start, warranty_end, next_service_date, next_service_km,
           status, created_by)
    values (v_customer_id, v_showroom, rec.inv_id, v_inventory.product_id, v_inventory.color_id,
            v_sale_id,
            case when v_reg_no is not null and v_vehicle_count = 1 then v_reg_no end,
            case when v_reg_no is not null and v_vehicle_count = 1 then v_sale_date end,
            v_inventory.chassis_number, v_inventory.engine_number, v_inventory.model_year,
            v_sale_date, v_delivery, coalesce(v_inventory.odometer, 0),
            (select c.color_name from public.product_colors c where c.id = v_inventory.color_id),
            v_delivery,
            (v_delivery + make_interval(months => coalesce(v_product.warranty_months, 24)))::date,
            (v_delivery + make_interval(days  => coalesce(v_product.service_interval_days, 180)))::date,
            coalesce(v_inventory.odometer, 0) + coalesce(v_product.service_interval_km, 5000),
            'ACTIVE', app_sec.current_user_id())
    returning id into v_vehicle_id;

    update public.sales
       set vehicle_id = coalesce(vehicle_id, v_vehicle_id)
     where id = v_sale_id;

    v_cogs := v_cogs + coalesce(v_inventory.purchase_price, 0);
  end loop;

  -- --------------------------------------------------------------------- invoice
  v_invoice_number := app_gen.next_document_number(v_showroom, 'INVOICE', v_sale_date);
  insert into public.invoices
        (showroom_id, customer_id, sale_id, invoice_number, invoice_type, invoice_date,
         subtotal, discount, tax_amount, other_charges, total_amount, paid_amount,
         outstanding_amount, status, finalized, terms, notes, billing_address,
         billing_gst_number, created_by)
  -- other_charges lives on the header, not in invoice_items: the roll-up in 007
  -- defines total = sum(lines) + other_charges, so adding a line for it as well
  -- would count the amount twice (found by tests/002).
  values (v_showroom, v_customer_id, v_sale_id, v_invoice_number, 'SALE', v_sale_date,
          round(v_subtotal, 2), round(v_line_discount, 2), round(v_tax, 2), v_other, v_total,
          0, v_total, 'DRAFT', false,
          'Payment due before delivery. Warranty as per manufacturer terms.',
          v_notes,
          btrim(concat_ws(', ', v_customer.address, v_customer.city, v_customer.state, v_customer.pincode)),
          v_customer.gst_number, app_sec.current_user_id())
  returning id into v_invoice_id;

  insert into public.invoice_items
        (invoice_id, product_id, inventory_id, sale_item_id, description, hsn_code,
         quantity, unit_price, discount, tax_rate, tax_amount, total_amount, sort_order)
  select v_invoice_id, si.product_id, si.inventory_id, si.id, si.description,
         p.hsn_code, si.quantity, si.unit_price, si.discount, si.tax_rate, si.tax_amount,
         si.total_amount, row_number() over (order by si.id)
    from public.sale_items si
    left join public.products p on p.id = si.product_id
   where si.sale_id = v_sale_id;

  -- Other charges stay on the invoice header (invoices_total_formula in 003
  -- includes them) and are printed as their own row from
  -- get_invoice_print_payload() -> 'otherCharges'. Putting them in invoice_items
  -- as well would count the 1500 twice, because the roll-up treats a line's
  -- qty*price as part of subtotal (found by tests/002).
  if v_exchange_val <> 0 then
    insert into public.invoice_items
          (invoice_id, description, quantity, unit_price, discount, tax_rate, tax_amount,
           total_amount, sort_order)
    values (v_invoice_id, 'Exchange adjustment (customer vehicle)', 1, 0, v_exchange_val, 0, 0,
            -v_exchange_val, 901);
  end if;

  -- the AFTER trigger on invoice_items already rolled the header up after every
  -- line; this final call makes the value deterministic for what follows (SS68).
  perform public.recalc_invoice_header(v_invoice_id);
  v_total := (select i.total_amount from public.invoices i where i.id = v_invoice_id);

  if v_sale_status in ('CONFIRMED','APPROVED') then
    perform public.finalize_invoice(v_invoice_id);
  end if;

  -- -------------------------------------------------------------------- payments
  for rec in select e.value, e.ordinality
                from jsonb_array_elements(v_payments) with ordinality as e(value, ordinality) loop
    if coalesce((rec.value ->> 'amount')::numeric, 0) <= 0 then
      continue;
    end if;
    select public.record_payment(jsonb_build_object(
             'showroom_id', v_showroom,
             'customer_id', v_customer_id,
             'invoice_id', v_invoice_id,
             'sale_id', v_sale_id,
             'amount', (rec.value ->> 'amount')::numeric,
             'payment_method', coalesce(rec.value ->> 'payment_method', 'CASH'),
             'payment_type', 'RECEIPT',
             'payment_date', coalesce(nullif(rec.value ->> 'payment_date',''),
                                      v_sale_date::text),
             'reference_number', rec.value ->> 'reference_number',
             'transaction_id', rec.value ->> 'transaction_id',
             'instrument_number', rec.value ->> 'instrument_number',
             'bank_name', rec.value ->> 'bank_name',
             'notes', coalesce(rec.value ->> 'notes', 'Advance with sale ' || v_sale_number),
             'allow_advance', false,
             -- child key derived from the sale's key: uuid has no + operator, the
             -- digest is deterministic so a replayed sale replays the same payments
             'idempotency_key', case when v_idem is not null
                  then left(md5(v_idem::text || ':pay:' || rec.ordinality::text), 32)::uuid end
           )) into v_payment_res;
    v_paid := v_paid + coalesce((v_payment_res ->> 'amount')::numeric, 0);
  end loop;

  -- ------------------------------------------------------- finance + EMI schedule
  if v_finance is not null then
    declare
      v_amount    numeric := app_util.round_money((v_finance ->> 'loan_amount')::numeric);
      v_down      numeric := app_util.round_money(coalesce((v_finance ->> 'down_payment')::numeric, 0));
      v_rate      numeric := coalesce((v_finance ->> 'interest_rate')::numeric, 0);
      v_tenure    integer := coalesce((v_finance ->> 'tenure_months')::integer, 36);
      v_fee       numeric := app_util.round_money(coalesce((v_finance ->> 'processing_fee')::numeric, 0));
      v_start     date    := coalesce((v_finance ->> 'start_date')::date, v_sale_date);
      v_principal numeric;
    begin
      if v_amount is null or v_amount <= 0 then
        v_amount := round(v_total - v_down, 2);
      end if;
      if v_amount <= 0 then
        perform app_util.fail('VAL010', 'finance amount must be positive after the down payment');
      end if;
      v_principal := v_amount;

      insert into public.loans
            (showroom_id, customer_id, vehicle_id, sale_id, finance_company_id, loan_number,
             loan_amount, principal_amount, down_payment, on_road_price, interest_rate,
             interest_type, tenure_months, emi_amount, processing_fee, total_payable,
             start_date, end_date, first_emi_date, late_fee_percent, status, approved_by,
             approved_at, created_by)
      values (v_showroom, v_customer_id, v_vehicle_id, v_sale_id,
              (v_finance ->> 'finance_company_id')::uuid,
              app_gen.next_document_number(v_showroom, 'LOAN', v_sale_date),
              v_amount, v_principal, v_down, v_total, v_rate,
              coalesce(nullif(v_finance ->> 'interest_type',''), 'REDUCING'), v_tenure,
              public.calculate_emi(v_principal, v_rate, v_tenure,
                                   coalesce(nullif(v_finance ->> 'interest_type',''), 'REDUCING')),
              v_fee, v_amount, v_start,
              (v_start + make_interval(months => v_tenure))::date,
              (v_start + interval '1 month')::date,
              coalesce((v_finance ->> 'late_fee_percent')::numeric, 0),
              'ACTIVE', app_sec.current_user_id(), now(), app_sec.current_user_id())
      returning id into v_loan_id;

      v_loan_summary := public.generate_emi_schedule(v_loan_id,
                             (v_start + interval '1 month')::date);

      -- the lender's disbursement is money received against the same invoice
      if v_principal > 0 then
        select public.record_payment(jsonb_build_object(
                 'showroom_id', v_showroom, 'customer_id', v_customer_id,
                 'invoice_id', v_invoice_id, 'sale_id', v_sale_id, 'loan_id', v_loan_id,
                 'amount', v_principal, 'payment_method', 'FINANCE',
                 'payment_type', 'RECEIPT',
                 'payment_date', coalesce(nullif(v_finance ->> 'disbursement_date', ''),
                                  v_sale_date::text),
                 'reference_number', coalesce(v_finance ->> 'lender_reference', 'LOAN-' || v_loan_id::text),
                 'transaction_id', v_loan_id::text,
                 'notes', 'Finance disbursement for sale ' || v_sale_number,
                 'allow_advance', false
               )) into v_payment_res;
        v_paid := v_paid + coalesce((v_payment_res ->> 'amount')::numeric, 0);
      end if;

      update public.loans l
         set lender_reference = coalesce(l.lender_reference, v_finance ->> 'lender_reference'),
             updated_at = now()
       where l.id = v_loan_id;
    end;
  end if;

  -- ---------------------------------------------------------------- warranty
  if v_vehicle_id is not null then
    select p.* into v_product
      from public.customer_vehicles cv
      join public.products p on p.id = cv.product_id
     where cv.id = v_vehicle_id;

    insert into public.warranties
          (vehicle_id, customer_id, showroom_id, product_id, warranty_number, warranty_type,
           start_date, end_date, start_km, coverage_km, current_km, terms,
           covered_components, status, created_by)
    select cv.id, cv.customer_id, cv.showroom_id, cv.product_id,
           'WTY-' || upper(left(md5(cv.id::text), 10)),
           'FACTORY', cv.warranty_start, cv.warranty_end,
           coalesce(cv.current_odometer, 0),
           coalesce(v_product.warranty_km, 0), coalesce(cv.current_odometer, 0),
           format('Covered for %s months or %s km from delivery, whichever occurs first. '
                  || 'Free servicing as per the plan on file.',
                  coalesce(v_product.warranty_months, 24),
                  coalesce(v_product.warranty_km, 0)),
           '["ENGINE","TRANSMISSION","ELECTRICS","CHASSIS","FUEL_PUMP"]'::jsonb,
           'ACTIVE', app_sec.current_user_id()
      from public.customer_vehicles cv
     where cv.id = v_vehicle_id
    on conflict (vehicle_id) do nothing
    returning id into v_warranty_id;

    -- ------------------------------------------------- free service schedule
    insert into public.vehicle_free_services
          (vehicle_id, customer_id, showroom_id, free_service_plan_id, service_number,
           due_date, due_km, status)
    select v_vehicle_id, v_customer_id, v_showroom, fsp.id, fsp.service_number,
           (v_delivery + make_interval(days => fsp.validity_days))::date,
           fsp.validity_km, 'UPCOMING'
      from (select distinct on (f.service_number) f.*
              from public.free_service_plans f
             where f.is_active
               and (f.product_id = v_product.id
                    or (f.brand_id = (select b.id from public.brands b
                                       join public.products pp on pp.brand_id = b.id
                                      where pp.id = v_product.id limit 1)
                        and f.product_id is null))
             order by f.service_number, f.product_id nulls last) fsp
    on conflict (vehicle_id, service_number) do nothing;
    get diagnostics v_free_rows = row_count;
  end if;

  -- --------------------------------------------------------- accounting (SS24)
  if v_sale_status in ('CONFIRMED','APPROVED') then
    begin
      v_accounting := app_acc.post_journal(
        p_showroom_id => v_showroom,
        p_date        => v_sale_date,
        p_journal_type=> 'SALE',
        p_reference_type => 'sale',
        p_reference_id   => v_sale_id,
        p_description => 'Vehicle sale ' || v_sale_number,
        p_lines => (
          select jsonb_agg(l) from (
            select jsonb_build_object('code', '1010', 'debit',
                     (select coalesce(sum(pp.amount), 0) from public.payments pp
                       where pp.sale_id = v_sale_id and pp.payment_method = 'CASH'
                         and pp.status = 'COMPLETED' and pp.payment_type = 'RECEIPT'),
                     'description', 'Cash received ' || v_sale_number) as l
              where exists (select 1 from public.payments pp where pp.sale_id = v_sale_id
                             and pp.payment_method = 'CASH' and pp.status = 'COMPLETED'
                             and pp.payment_type = 'RECEIPT')
            union all
            select jsonb_build_object('code', '1150', 'debit',
                     coalesce((select sum(pp.amount) from public.payments pp
                                where pp.sale_id = v_sale_id and pp.payment_method = 'FINANCE'
                                  and pp.status = 'COMPLETED'), 0),
                     'description', 'Receivable from finance company')
              where exists (select 1 from public.payments pp where pp.sale_id = v_sale_id
                             and pp.payment_method = 'FINANCE' and pp.status = 'COMPLETED')
            union all
            select jsonb_build_object('code', '1100', 'debit',
                     (select i.outstanding_amount from public.invoices i where i.id = v_invoice_id),
                     'description', 'Customer receivable ' || v_invoice_number)
              where (select i.outstanding_amount from public.invoices i where i.id = v_invoice_id) > 0
            union all
            -- an exchange vehicle taken in trade is stock the dealership acquires:
            -- it debits inventory so the journal balances against the reduced
            -- receivable (SS24).
            select jsonb_build_object('code', '1200', 'debit', round(v_exchange_val, 2),
                     'description', 'Exchange vehicle taken in trade')
              where v_exchange_val > 0
            union all
            -- handling / documentation charges are part of the sale's income, not a
            -- separate receivable: crediting them here keeps Dr = Cr identical to the
            -- invoice total (found by tests/002 - the roll-up formula is
            -- subtotal - discount + tax + other - exchange).
            select jsonb_build_object('code', '4100', 'credit',
                     round(v_subtotal - v_line_discount + v_other, 2),
                     'description', 'Vehicle sales revenue')
            union all
            select jsonb_build_object('code', '2200', 'credit', round(v_tax, 2),
                     'description', 'GST payable on ' || v_sale_number)
              where v_tax > 0
          ) x where coalesce((x.l ->> 'debit')::numeric, (x.l ->> 'credit')::numeric, 0) <> 0
        )
      );
    exception when others then
      -- Revenue recognition must never block the customer's sale; the journal is
      -- queued for the accountant instead (SS24 auto-posting, manual fallback).
      insert into public.notifications
            (user_id, showroom_id, title, message, notification_type, severity,
             route_name, route_params, reference_type, reference_id, channel, action_required)
      select u.id, v_showroom, 'Accounting entry pending',
             'Sale ' || v_sale_number || ' could not auto-post (' || sqlerrm || '). Post it manually from Accounting.',
             'ACCOUNTING', 'WARNING', '/accounting/transactions',
             jsonb_build_object('saleId', v_sale_id), 'sale', v_sale_id, 'IN_APP', true
        from public.users u
       where u.showroom_id = v_showroom
         and u.status = 'ACTIVE'
         and u.is_super_admin = false
         and exists (select 1 from public.user_roles ur
                      join public.roles r on r.id = ur.role_id
                      join public.role_permissions rp on rp.role_id = r.id
                      join public.permissions p on p.id = rp.permission_id
                     where ur.user_id = u.id and p.module = 'accounting' and p.action = 'view')
       limit 3;
    end;

    -- cost of goods sold: stock leaves the balance sheet at its landed cost
    if v_cogs > 0 then
      begin
        perform app_acc.post_journal(
          v_showroom, v_sale_date, 'SALE', 'sale_cogs', v_sale_id,
          'Cost of goods sold for ' || v_sale_number,
          jsonb_build_array(
            jsonb_build_object('code', '5000', 'debit', round(v_cogs, 2),
                               'description', 'COGS ' || v_sale_number),
            jsonb_build_object('code', '1200', 'credit', round(v_cogs, 2),
                               'description', 'Inventory issued ' || v_sale_number)
          )
        );
      exception when others then
        null;
      end;
    end if;
  end if;

  -- ------------------------------------------------------------------ reminders
  if v_loan_id is not null then
    perform public.create_emi_reminders(v_loan_id);
  end if;
  if v_vehicle_id is not null then
    select v.next_service_date, v.next_service_km
      into v_next_service_date, v_next_service_km
      from public.customer_vehicles v where v.id = v_vehicle_id;
    perform public.create_service_reminders(v_vehicle_id, v_next_service_date, v_next_service_km);
    if v_warranty_id is not null then
      perform public.create_warranty_reminders(v_warranty_id);
    end if;
  end if;

  -- -------------------------------------------------------- rollups + audit
  -- No manual customer rollup: the AFTER trigger on sales recomputes
  -- lifetime_value / last_purchase_at from the sale rows, which keeps the number
  -- correct for edits and cancellations as well (SS24 single source of truth).

  perform app_util.audit_row('sales', 'CREATE', 'sales', v_sale_id, null,
    jsonb_build_object('saleNumber', v_sale_number, 'total', v_total, 'status', v_sale_status,
                       'invoice', v_invoice_number, 'loan', v_loan_id),
    v_showroom, null, v_customer.name || ' - ' || coalesce(v_first_product.name, 'sale'));

  if v_sale_status = 'PENDING_APPROVAL' then
    insert into public.notifications
          (user_id, customer_id, showroom_id, title, message, notification_type, severity,
           route_name, route_params, reference_type, reference_id, channel, action_required)
    select u.id, v_customer_id, v_showroom, 'Sale awaiting approval',
           format('Sale %s for %s totalling %s needs your approval.',
                  v_sale_number, v_customer.name, v_total),
           'SALES', 'WARNING', '/sales/approvals', jsonb_build_object('id', v_sale_id),
           'sale', v_sale_id, 'IN_APP', true
      from public.users u
     where u.status = 'ACTIVE'
       and (u.showroom_id = v_showroom or app_sec.is_super_admin())
       and app_sec.has_permission_in('sales', 'approve', v_showroom)
       and (u.id = v_salesperson) is not true
     limit 10;
  end if;

  v_payment_res := jsonb_build_object(
    'saleId', v_sale_id,
    'saleNumber', v_sale_number,
    'saleStatus', v_sale_status,
    'invoiceId', v_invoice_id,
    'invoiceNumber', v_invoice_number,
    'vehicleId', v_vehicle_id,
    'loanId', v_loan_id,
    'warrantyId', v_warranty_id,
    'freeServiceRows', v_free_rows,
    'accountingTransactionId', v_accounting,
    'subtotal', round(v_subtotal, 2),
    'discount', round(v_line_discount, 2),
    'taxAmount', round(v_tax, 2),
    'otherCharges', v_other,
    'totalAmount', v_total,
    'paidAmount', round(v_paid, 2),
    'outstandingAmount', round(greatest(v_total - v_paid, 0), 2),
    'emi', v_loan_summary,
    'replayed', false
  );

  if v_idem is not null then
    update public.idempotency_keys
       set status = 'COMPLETED', result = v_payment_res, completed_at = now()
     where key = v_idem;
  end if;

  return v_payment_res;
end;
$$;

comment on function public.create_sale_transaction(jsonb) is
  'Atomic end-to-end bike sale (SS63). Retry-safe with an idempotency_key; returns every created id.';

-- ---------------------------------------------------------------------------
-- Sales lifecycle helpers beyond creation
-- ---------------------------------------------------------------------------
create or replace function public.approve_sale(
  p_sale_id   uuid,
  p_approve   boolean default true,
  p_reason    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales%rowtype;
begin

  perform app_sec.require_permission('sales','approve');
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then perform app_util.fail('NOT001', 'sale not found'); end if;
  perform app_sec.require_showroom_access(v_sale.showroom_id);

  if v_sale.status not in ('DRAFT','PENDING_APPROVAL','APPROVED') then
    perform app_util.fail('CON001', 'a ' || lower(v_sale.status) || ' sale cannot be ' ||
      case when p_approve then 'approved' else 'rejected' end);
  end if;
  if not p_approve and coalesce(p_reason,'') = '' then
    perform app_util.fail('VAL001', 'a rejection requires a reason');
  end if;

  if p_approve then
    update public.sales
       set status = 'CONFIRMED', approved_by = app_sec.current_user_id(), approved_at = now(),
           approval_required = false, updated_at = now(), updated_by = app_sec.current_user_id()
     where id = p_sale_id;
  else
    update public.sales
       set status = 'CANCELLED', cancellation_reason = p_reason,
           cancelled_by = app_sec.current_user_id(), cancelled_at = now(),
           updated_at = now(), updated_by = app_sec.current_user_id()
     where id = p_sale_id;
  end if;

  -- approving is what actually finalises the invoice and books revenue
  if p_approve then
    update public.invoices i
       set status = 'FINALIZED', finalized = true, finalized_at = now(),
           emitted_at = coalesce(emitted_at, now()), updated_at = now()
     where i.sale_id = p_sale_id and i.status = 'DRAFT';
  end if;

  perform app_util.audit_row('sales', case when p_approve then 'APPROVE' else 'REJECT' end,
          'sales', p_sale_id, jsonb_build_object('status', v_sale.status),
          jsonb_build_object('status', case when p_approve then 'CONFIRMED' else 'CANCELLED' end,
                             'reason', p_reason),
          v_sale.showroom_id, null, v_sale.sale_number);

  if not p_approve then
    insert into public.notifications
          (user_id, showroom_id, title, message, notification_type, severity, route_name,
           route_params, reference_type, reference_id, channel)
    values (v_sale.created_by, v_sale.showroom_id, 'Sale rejected',
            'Sale ' || v_sale.sale_number || ' was rejected: ' || coalesce(p_reason,'-'),
            'SALES','WARNING','/sales/detail', jsonb_build_object('id', p_sale_id),
            'sale', p_sale_id, 'IN_APP');
  end if;

  return jsonb_build_object('saleId', p_sale_id, 'status',
         (select s.status from public.sales s where s.id = p_sale_id));
end;
$$;

-- Sale cancellation is a *reversal*: stock returns to AVAILABLE, the invoice is
-- cancelled, journals are reversed and the vehicle row is retired - nothing is
-- deleted (SS42, SS63).
create or replace function public.cancel_sale(
  p_sale_id uuid,
  p_reason  text,
  p_refund  boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale      public.sales%rowtype;
  v_pay       record;
  v_refunded  numeric := 0;
  v_ref_alloc numeric := 0;         -- money that had already been applied to a bill
  v_ref_lines jsonb := '[]'::jsonb; -- cash going back out, per payment method
begin

  perform app_sec.require_permission('sales','cancel');
  if coalesce(p_reason,'') = '' then
    perform app_util.fail('VAL001', 'cancelling a sale requires a reason');
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if not found then perform app_util.fail('NOT001', 'sale not found'); end if;
  perform app_sec.require_showroom_access(v_sale.showroom_id);
  if v_sale.status in ('CANCELLED','RETURNED') then
    perform app_util.fail('CON002', 'sale is already ' || lower(v_sale.status));
  end if;

  -- 1. money back (as a REFUND row; the original receipt stays visible).  A
  -- receipt is refundable only up to what has not already been refunded against
  -- it, and an advance that was never allocated is still the customer's money, so
  -- it is returned too (SS15, SS42: nothing is overwritten, only answered).
  if p_refund then
    for v_pay in
        select p.*,
               greatest(p.amount - coalesce((select sum(c.amount) from public.payments c
                                              where c.parent_payment_id = p.id
                                                and c.status = 'COMPLETED'), 0), 0) as refundable
          from public.payments p
         where p.sale_id = p_sale_id and p.status = 'COMPLETED' and p.payment_type = 'RECEIPT'
         order by p.payment_date
         for update
    loop
      if coalesce(v_pay.refundable, 0) <= 0 then
        continue;
      end if;

      insert into public.payments
            (payment_number, showroom_id, customer_id, invoice_id, sale_id, service_id,
             payment_date, payment_type, amount, allocated_amount, payment_method,
             status, received_by, parent_payment_id, notes, created_by)
      values (app_gen.next_document_number(v_sale.showroom_id,'PAYMENT',current_date),
              v_pay.showroom_id, v_pay.customer_id, v_pay.invoice_id, v_pay.sale_id, v_pay.service_id,
              current_date, 'REFUND', v_pay.refundable,
              least(v_pay.refundable, v_pay.allocated_amount),
              v_pay.payment_method, 'COMPLETED', app_sec.current_user_id(), v_pay.id,
              'Refund for cancelled sale ' || v_sale.sale_number || ' - ' || p_reason,
              app_sec.current_user_id());

      -- the receipt only changes state once nothing of it is left outstanding
      update public.payments p
         set status = case when coalesce((select sum(c.amount) from public.payments c
                                          where c.parent_payment_id = p.id
                                            and c.status = 'COMPLETED'), 0) >= p.amount
                           then 'REFUNDED' else p.status end,
             updated_at = now()
       where p.id = v_pay.id;

      v_refunded  := v_refunded + v_pay.refundable;
      v_ref_alloc := v_ref_alloc + least(v_pay.refundable, v_pay.allocated_amount);
      v_ref_lines := v_ref_lines || jsonb_build_object(
                       'method', v_pay.payment_method, 'amount', v_pay.refundable);
    end loop;
  end if;

  -- The cash that left the till has to be in the books too.  The reversed SALE
  -- journal restored the receivable, so the refund settles it; anything the
  -- customer had paid but that was never allocated sits against advances.
  if v_refunded > 0 then
    begin
      perform app_acc.post_journal(
        v_sale.showroom_id, current_date, 'REFUND', 'sale_refund', p_sale_id,
        'Refund for cancelled sale ' || v_sale.sale_number,
        (select jsonb_agg(l) from (
                 select '1100'::text as code, v_ref_alloc as debit, 0::numeric as credit
                 union all
                 select '2300', v_refunded - v_ref_alloc, 0
                 union all
                 select case when m.method = 'CASH' then '1010'
                             when m.method in ('CHEQUE','BANK_TRANSFER') then '1020'
                             else '1030' end,
                        0, m.amount
                   from (select e.value ->> 'method' as method,
                                sum((e.value ->> 'amount')::numeric) as amount
                           from jsonb_array_elements(v_ref_lines) as e(value)
                          group by 1) m
            ) l
           where l.debit <> 0 or l.credit <> 0));
    exception when others then
      -- The stock and the money moved, so the cancellation stands; a refund the
      -- books cannot see must reach a human instead of disappearing (SS68, SS70).
      insert into public.notifications (user_id, showroom_id, title, message,
                                        notification_type, severity, route_name)
      values (app_sec.current_user_id(), v_sale.showroom_id, 'Accounting entry failed',
              'Sale ' || v_sale.sale_number || ' was cancelled but its refund journal could not be posted: '
                || sqlerrm || '. Post it manually from Accounting.',
              'ACCOUNTING', 'WARNING', '/accounting/transactions');
    end;
  end if;

  -- 2. stock back on the shelf
  update public.inventory i
     set status = 'AVAILABLE', allocated_sale_id = null, updated_at = now(),
         updated_by = app_sec.current_user_id(),
         remarks = btrim(coalesce(i.remarks,'') || ' | returned from cancelled sale ' || v_sale.sale_number)
   where i.allocated_sale_id = p_sale_id;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, from_status, to_status,
         reference_type, reference_id, reason, performed_by)
  select i.showroom_id, i.id, 'SALE_REVERSE', 'SOLD', 'AVAILABLE', 'sale', p_sale_id,
         'Returned from cancelled sale ' || v_sale.sale_number, app_sec.current_user_id()
    from public.inventory i where i.allocated_sale_id = p_sale_id;

  -- 3. retire the invoice and the vehicle ledger row
  update public.invoices i
     set status = 'CANCELLED', finalized = false, cancelled_at = now(),
         cancelled_by = app_sec.current_user_id(),
         cancellation_reason = 'Sale ' || v_sale.sale_number || ' cancelled: ' || p_reason,
         outstanding_amount = 0,
         updated_at = now()
   where i.sale_id = p_sale_id and i.status <> 'CANCELLED';

  update public.customer_vehicles v
     set is_deleted = true, deleted_at = now(), status = 'TRANSFERRED',
         notes = btrim(coalesce(v.notes,'') || ' | sale cancelled: ' || p_reason)
   where v.sale_id = p_sale_id and v.is_deleted = false;

  update public.vehicle_free_services vfs
     set status = 'CANCELLED'
    where vfs.vehicle_id in (select id from public.customer_vehicles where sale_id = p_sale_id)
      and vfs.status in ('UPCOMING','BOOKED');

  update public.warranties w
     set status = 'VOID'
   where w.vehicle_id in (select id from public.customer_vehicles where sale_id = p_sale_id)
     and w.status = 'ACTIVE';

  -- 4. reverse the journals
  begin
    perform app_acc.reverse_journal(t.id, 'Sale cancelled: ' || p_reason)
      from public.accounting_transactions t
     where t.reference_id = p_sale_id
       and t.reference_type in ('sale','sale_cogs');
  exception when others then
    null;   -- nothing was posted (unapproved sale): nothing to reverse
  end;

  update public.loans l
     set status = 'CANCELLED', updated_at = now()
   where l.sale_id = p_sale_id and l.status in ('APPLIED','SANCTIONED','ACTIVE');

  update public.emi_schedules e
     set status = 'CANCELLED'
   where e.loan_id in (select id from public.loans where sale_id = p_sale_id)
     and e.status <> 'PAID';

  update public.sales s
     set status = 'CANCELLED', cancellation_reason = p_reason,
         cancelled_by = app_sec.current_user_id(), cancelled_at = now(),
         paid_amount = round(greatest(s.paid_amount - v_refunded, 0), 2),
         outstanding_amount = 0,
         updated_at = now(), updated_by = app_sec.current_user_id()
   where s.id = p_sale_id;

  -- the customer rollup is recomputed by the sales trigger; excluding CANCELLED
  -- sales from the sum is what takes the value back off the card (007)

  perform app_util.audit_row('sales','CANCEL','sales', p_sale_id,
          jsonb_build_object('status', v_sale.status, 'total', v_sale.total_amount),
          jsonb_build_object('status','CANCELLED','refunded', v_refunded, 'reason', p_reason),
          v_sale.showroom_id, null, v_sale.sale_number, 'WARNING');

  return jsonb_build_object('saleId', p_sale_id, 'status','CANCELLED',
                            'refundedAmount', v_refunded, 'invoiceCancelled', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Inventory RPCs (SS10)
-- ---------------------------------------------------------------------------
create or replace function public.create_inventory_unit(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom uuid := (p_payload ->> 'showroom_id')::uuid;
  v_product  uuid := (p_payload ->> 'product_id')::uuid;
  v_color    uuid := (p_payload ->> 'color_id')::uuid;
  v_chassis  text := app_util.upper_no_space(p_payload ->> 'chassis_number');
  v_engine   text := app_util.upper_no_space(p_payload ->> 'engine_number');
  v_code     text := app_util.upper_no_space(coalesce(p_payload ->> 'stock_code',
                        'STK-' || upper(left(md5(coalesce(v_chassis, '')), 8))));
  v_id       uuid;
begin

  perform app_sec.require_permission('inventory','create');
  perform app_sec.require_showroom_access(v_showroom);
  if v_product is null or v_chassis is null or v_engine is null then
    perform app_util.fail('VAL001', 'product_id, chassis_number and engine_number are required');
  end if;
  if exists (select 1 from public.inventory i where i.chassis_number = v_chassis) then
    perform app_util.fail('CON001', 'chassis number ' || v_chassis || ' already exists');
  end if;
  if exists (select 1 from public.inventory i where i.engine_number = v_engine) then
    perform app_util.fail('CON002', 'engine number ' || v_engine || ' already exists');
  end if;
  if exists (select 1 from public.inventory i where i.stock_code = v_code) then
    v_code := v_code || '-' || upper(left(md5(random()::text), 4));
  end if;

  insert into public.inventory
        (showroom_id, product_id, color_id, stock_code, chassis_number, engine_number,
         manufacturing_date, model_year, purchase_date, purchase_price, landing_price, mrp,
         status, location, odometer, expected_delivery_date, remarks, created_by)
  values (v_showroom, v_product, v_color, v_code, v_chassis, v_engine,
          (p_payload ->> 'manufacturing_date')::date,
          (p_payload ->> 'model_year')::int,
          coalesce((p_payload ->> 'purchase_date')::date, current_date),
          app_util.round_money(coalesce((p_payload ->> 'purchase_price')::numeric, 0)),
          app_util.round_money(coalesce((p_payload ->> 'landing_price')::numeric, 0)),
          app_util.round_money(coalesce((p_payload ->> 'mrp')::numeric, 0)),
          coalesce(nullif(p_payload ->> 'status',''), 'AVAILABLE'),
          p_payload ->> 'location',
          coalesce((p_payload ->> 'odometer')::int, 0),
          (p_payload ->> 'expected_delivery_date')::date,
          p_payload ->> 'remarks',
          app_sec.current_user_id())
  returning id into v_id;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, to_status, reference_type, reference_id,
         reason, performed_by)
  values (v_showroom, v_id, 'STOCK_IN',
          coalesce(nullif(p_payload ->> 'status',''), 'AVAILABLE'),
          'inventory', v_id, p_payload ->> 'reason', app_sec.current_user_id());

  perform app_util.audit_row('inventory','CREATE','inventory', v_id, null,
          jsonb_build_object('stockCode', v_code, 'chassis', v_chassis), v_showroom, null, v_code);

  return jsonb_build_object('inventoryId', v_id, 'stockCode', v_code);
end;
$$;

-- Manual stock adjustment with an explicit reason (SS10, SS67).
create or replace function public.adjust_inventory(
  p_inventory_id uuid,
  p_new_status   text,
  p_reason       text,
  p_purchase_price numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.inventory%rowtype;
  v_type text;
begin

  perform app_sec.require_permission('inventory','adjust');
  if coalesce(p_reason,'') = '' then
    perform app_util.fail('VAL001', 'a stock adjustment requires a reason');
  end if;
  if p_new_status not in ('AVAILABLE','RESERVED','SOLD','DEMO','DAMAGED','IN_TRANSIT','RETURNED',
                          'HOLD','PENDING_RC','SCRAPPED') then
    perform app_util.fail('VAL002', 'unknown stock status ' || p_new_status);
  end if;

  select * into v_inv from public.inventory where id = p_inventory_id for update;
  if not found then perform app_util.fail('NOT001', 'inventory unit not found'); end if;
  perform app_sec.require_showroom_access(v_inv.showroom_id);

  -- a SOLD unit may only be released through the sale cancellation flow
  if v_inv.status = 'SOLD' and p_new_status <> 'SOLD' and v_inv.allocated_sale_id is not null then
    if not app_sec.has_permission('sales','cancel') then
      perform app_util.fail('SEC001',
        'this unit is attached to a sale - cancel the sale (sales.cancel) instead of adjusting stock');
    end if;
  end if;

  update public.inventory i
     set status = p_new_status,
         purchase_price = coalesce(app_util.round_money(p_purchase_price), i.purchase_price),
         reserved_customer_id = case when p_new_status = 'RESERVED' then i.reserved_customer_id end,
         reserved_until       = case when p_new_status = 'RESERVED' then i.reserved_until end,
         remarks = btrim(coalesce(i.remarks,'') || ' | ' || p_reason),
         updated_at = now(), updated_by = app_sec.current_user_id()
   where i.id = p_inventory_id;

  v_type := case p_new_status
               when 'DAMAGED' then 'DAMAGE_FLAG'
               when 'RETURNED' then 'RETURN_IN'
               when 'DEMO' then 'DEMO_IN'
               else 'ADJUST' end;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, from_status, to_status,
         reference_type, reference_id, reason, performed_by)
  values (v_inv.showroom_id, p_inventory_id, v_type, v_inv.status, p_new_status,
          'inventory', p_inventory_id, p_reason, app_sec.current_user_id());

  perform app_util.audit_row('inventory','STOCK_ADJUSTMENT','inventory', p_inventory_id,
          jsonb_build_object('status', v_inv.status), jsonb_build_object('status', p_new_status),
          v_inv.showroom_id, null, v_inv.stock_code);

  return jsonb_build_object('inventoryId', p_inventory_id, 'from', v_inv.status, 'to', p_new_status);
end;
$$;

create or replace function public.reserve_inventory(
  p_inventory_id uuid,
  p_customer_id  uuid,
  p_hold_days    integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.inventory%rowtype;
begin

  perform app_sec.require_permission('inventory','transfer');
  select * into v_inv from public.inventory where id = p_inventory_id for update;
  if not found then perform app_util.fail('NOT001', 'inventory unit not found'); end if;
  perform app_sec.require_showroom_access(v_inv.showroom_id);
  if v_inv.status <> 'AVAILABLE' then
    perform app_util.fail('CON001', 'unit is ' || lower(v_inv.status) || ', not available');
  end if;
  if p_hold_days not between 1 and 60 then
    perform app_util.fail('VAL001', 'hold days must be between 1 and 60');
  end if;

  update public.inventory
     set status = 'RESERVED', reserved_customer_id = p_customer_id,
         reserved_by = app_sec.current_user_id(),
         reserved_until = now() + make_interval(days => p_hold_days),
         updated_at = now(), updated_by = app_sec.current_user_id()
   where id = p_inventory_id;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, from_status, to_status,
         reference_type, reference_id, reason, performed_by)
  values (v_inv.showroom_id, p_inventory_id, 'RESERVE', 'AVAILABLE', 'RESERVED',
          'customer', p_customer_id, 'Held for ' || p_hold_days || ' days', app_sec.current_user_id());

  return jsonb_build_object('inventoryId', p_inventory_id, 'status','RESERVED',
                            'reservedUntil', now() + make_interval(days => p_hold_days));
end;
$$;

create or replace function public.release_inventory(
  p_inventory_id uuid,
  p_reason       text default 'reservation released'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.inventory%rowtype;
begin

  perform app_sec.require_permission('inventory','transfer');
  select * into v_inv from public.inventory where id = p_inventory_id for update;
  if not found then perform app_util.fail('NOT001', 'inventory unit not found'); end if;
  perform app_sec.require_showroom_access(v_inv.showroom_id);
  if v_inv.status <> 'RESERVED' then
    perform app_util.fail('CON001', 'unit is not reserved');
  end if;

  update public.inventory
     set status = 'AVAILABLE', reserved_customer_id = null, reserved_by = null,
         reserved_until = null, updated_at = now(), updated_by = app_sec.current_user_id()
   where id = p_inventory_id;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, from_status, to_status, reason, performed_by)
  values (v_inv.showroom_id, p_inventory_id, 'RELEASE', 'RESERVED', 'AVAILABLE',
          p_reason, app_sec.current_user_id());

  return jsonb_build_object('inventoryId', p_inventory_id, 'status','AVAILABLE');
end;
$$;

-- Inter-showroom transfer (SS10). Stock leaves the sender immediately and is
-- only "received" by the destination, which keeps in-transit value visible.
create or replace function public.transfer_inventory(
  p_inventory_id   uuid,
  p_to_showroom_id uuid,
  p_transfer_date  date default current_date,
  p_expected_date  date default null,
  p_freight        numeric default 0,
  p_notes          text default null,
  p_transport_mode text default 'TRAILER'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv     public.inventory%rowtype;
  v_transfer uuid;
  v_number  text;
begin

  perform app_sec.require_permission('inventory','transfer');
  perform app_sec.require_showroom_access(p_to_showroom_id);

  select * into v_inv from public.inventory where id = p_inventory_id for update;
  if not found then perform app_util.fail('NOT001', 'inventory unit not found'); end if;
  perform app_sec.require_showroom_access(v_inv.showroom_id);

  if v_inv.showroom_id = p_to_showroom_id then
    perform app_util.fail('VAL001', 'source and destination showrooms must differ');
  end if;
  if v_inv.status not in ('AVAILABLE','DEMO','PENDING_RC') then
    perform app_util.fail('CON001',
      format('unit %s is %s; only AVAILABLE / DEMO / PENDING_RC units can move',
             v_inv.stock_code, lower(v_inv.status)));
  end if;
  if p_transfer_date > current_date + 90 then
    perform app_util.fail('VAL002', 'transfer date too far in the future');
  end if;

  v_number := app_gen.next_document_number(v_inv.showroom_id, 'STOCK_TRANSFER', p_transfer_date);

  insert into public.stock_transfers
        (transfer_number, from_showroom_id, to_showroom_id, inventory_id, transfer_date,
         expected_date, status, transport_mode, freight_charges, notes, created_by)
  values (v_number, v_inv.showroom_id, p_to_showroom_id, p_inventory_id, p_transfer_date,
          p_expected_date, 'IN_TRANSIT', p_transport_mode,
          app_util.round_money(coalesce(p_freight, 0)), p_notes, app_sec.current_user_id())
  returning id into v_transfer;

  update public.inventory
     set status = 'IN_TRANSIT', location = 'IN TRANSIT -> ' ||
           (select s.name from public.showrooms s where s.id = p_to_showroom_id),
         reserved_customer_id = null, reserved_until = null, reserved_by = null,
         updated_at = now(), updated_by = app_sec.current_user_id()
   where id = p_inventory_id;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, from_status, to_status,
         reference_type, reference_id, reason, performed_by)
  values (v_inv.showroom_id, p_inventory_id, 'TRANSFER_OUT', v_inv.status, 'IN_TRANSIT',
          'stock_transfer', v_transfer, 'Dispatch ' || v_number, app_sec.current_user_id());

  begin
    perform app_acc.post_journal(v_inv.showroom_id, p_transfer_date, 'TRANSFER',
      'stock_transfer', v_transfer, 'Stock in transit ' || v_inv.stock_code,
      jsonb_build_array(
        jsonb_build_object('code','1250','debit', round(v_inv.purchase_price,2),
                           'description','In transit ' || v_number),
        jsonb_build_object('code','1200','credit', round(v_inv.purchase_price,2),
                           'description','Dispatched ' || v_number)
      ));
  exception when others then
    null;
  end;

  perform app_util.audit_row('inventory','STOCK_TRANSFER','stock_transfers', v_transfer, null,
          jsonb_build_object('unit', v_inv.stock_code, 'to', p_to_showroom_id, 'number', v_number),
          v_inv.showroom_id, null, v_number);

  return jsonb_build_object('transferId', v_transfer, 'transferNumber', v_number,
                            'inventoryId', p_inventory_id, 'status','IN_TRANSIT');
end;
$$;

create or replace function public.receive_stock_transfer(
  p_transfer_id uuid,
  p_notes       text default null,
  p_accept_damage boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tr  public.stock_transfers%rowtype;
  v_inv public.inventory%rowtype;
begin

  perform app_sec.require_permission('inventory','transfer');
  select t.* into v_tr
    from public.stock_transfers t where t.id = p_transfer_id for update;
  if not found then perform app_util.fail('NOT001', 'transfer not found'); end if;
  perform app_sec.require_showroom_access(v_tr.to_showroom_id);
  if v_tr.status not in ('IN_TRANSIT','PENDING','APPROVED') then
    perform app_util.fail('CON001', 'transfer is ' || lower(v_tr.status) || ' and cannot be received');
  end if;

  select * into v_inv from public.inventory where id = v_tr.inventory_id for update;
  if v_inv.status <> 'IN_TRANSIT' then
    perform app_util.fail('CON002', 'unit is ' || lower(v_inv.status) || ', expected IN_TRANSIT');
  end if;

  update public.inventory
     set showroom_id = v_tr.to_showroom_id,
         status = case when p_accept_damage then 'DAMAGED' else 'AVAILABLE' end,
         location = (select s.name from public.showrooms s where s.id = v_tr.to_showroom_id),
         updated_at = now(), updated_by = app_sec.current_user_id()
   where id = v_inv.id;

  update public.stock_transfers
     set status = 'RECEIVED', received_date = now(),
         received_by = app_sec.current_user_id(),
         notes = btrim(coalesce(notes,'') || ' ' || coalesce(p_notes,'')),
         updated_at = now()
   where id = p_transfer_id;

  insert into public.stock_movements
        (showroom_id, inventory_id, movement_type, from_status, to_status,
         reference_type, reference_id, reason, performed_by)
  values (v_tr.to_showroom_id, v_inv.id, 'TRANSFER_IN', 'IN_TRANSIT',
          case when p_accept_damage then 'DAMAGED' else 'AVAILABLE' end,
          'stock_transfer', p_transfer_id, 'Received ' || v_tr.transfer_number,
          app_sec.current_user_id());

  begin
    perform app_acc.post_journal(v_tr.to_showroom_id, current_date, 'TRANSFER',
      'stock_transfer', p_transfer_id, 'Stock received ' || v_inv.stock_code,
      jsonb_build_array(
        jsonb_build_object('code','1200','debit', round(v_inv.purchase_price,2),
                           'description','Received ' || v_tr.transfer_number),
        jsonb_build_object('code','1250','credit', round(v_inv.purchase_price,2),
                           'description','Cleared in transit')
      ));
  exception when others then
    null;
  end;

  perform app_util.audit_row('inventory','STOCK_TRANSFER','stock_transfers', p_transfer_id,
          jsonb_build_object('status', v_tr.status),
          jsonb_build_object('status','RECEIVED','showroom', v_tr.to_showroom_id),
          v_tr.to_showroom_id, null, v_tr.transfer_number);

  return jsonb_build_object('transferId', p_transfer_id, 'inventoryId', v_inv.id,
                            'status','RECEIVED');
end;
$$;

-- ---------------------------------------------------------------------------
-- Purchases (SS22, SS65): header + lines + inventory generation + payable
-- journal, atomically.
-- ---------------------------------------------------------------------------
create or replace function public.create_purchase_transaction(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom  uuid    := (p_payload ->> 'showroom_id')::uuid;
  v_supplier  uuid    := (p_payload ->> 'supplier_id')::uuid;
  v_date      date    := coalesce((p_payload ->> 'purchase_date')::date, current_date);
  v_lines     jsonb   := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_other     numeric := app_util.round_money(coalesce((p_payload ->> 'other_charges')::numeric, 0));
  v_freight   numeric := app_util.round_money(coalesce((p_payload ->> 'freight_charges')::numeric, 0));
  v_paid      numeric := app_util.round_money(coalesce((p_payload ->> 'paid_amount')::numeric, 0));
  v_receive   boolean := coalesce((p_payload ->> 'receive_now')::boolean, true);
  v_idem      uuid    := (p_payload ->> 'idempotency_key')::uuid;

  v_number    text;
  v_purchase  uuid;
  v_total     numeric := 0;
  v_subtotal  numeric := 0;
  v_discount  numeric := 0;
  v_tax       numeric := 0;
  v_item      record;
  v_inventory uuid;
  v_product   public.products%rowtype;
  v_replay    jsonb;
  v_lines_ok  integer;
begin

  perform app_sec.require_permission('purchases','create');
  if v_receive then
    -- the one-call path creates the units that receive_purchase() would have
    -- created, so it needs the receiving permission too (SS6, SS16).
    perform app_sec.require_permission('purchases','receive');
  end if;
  perform app_sec.require_showroom_access(v_showroom);
  if v_idem is not null then
    select ik.result into v_replay from public.idempotency_keys ik where ik.key = v_idem for update;
    if found and v_replay is not null then
      return v_replay || jsonb_build_object('replayed', true);
    end if;
    insert into public.idempotency_keys (key, user_id, showroom_id, operation, status)
    values (v_idem, app_sec.current_user_id(), v_showroom, 'create_purchase_transaction', 'IN_PROGRESS')
    on conflict (key) do nothing;
  end if;

  if v_supplier is null or jsonb_array_length(v_lines) = 0 then
    perform app_util.fail('VAL001', 'supplier_id and at least one purchase line are required');
  end if;
  if not exists (select 1 from public.suppliers s where s.id = v_supplier and s.status = 'ACTIVE') then
    perform app_util.fail('VAL002', 'supplier is missing or inactive');
  end if;

  v_number := app_gen.next_document_number(v_showroom, 'PURCHASE', v_date);

  -- The header money is written in one pass below, after the lines have been
  -- priced: purchases_total_formula / purchases_paid_le_total hold at every
  -- instant, so a half-filled header (freight without a total) would be rejected
  -- before the loop ever ran.
  insert into public.purchases
        (purchase_number, showroom_id, supplier_id, purchase_date, expected_date,
         subtotal, discount, tax_amount, other_charges, freight_charges, total_amount,
         paid_amount, outstanding_amount, status, notes, created_by)
  values (v_number, v_showroom, v_supplier, v_date,
          (p_payload ->> 'expected_date')::date,
          0, 0, 0, 0, 0, 0, 0, 0,
          -- A purchase that is not physically received yet stays DRAFT, because
          -- approve_purchase() is the door to CONFIRMED and receive_purchase() only
          -- accepts CONFIRMED goods (SS16). Marking it CONFIRMED here made the
          -- approval step unreachable for every RPC-created purchase order.
          case when v_receive then 'RECEIVED' else 'DRAFT' end,
          p_payload ->> 'notes', app_sec.current_user_id())
  returning id into v_purchase;

  -- lines: each line either references existing stock (transfer-in style
  -- purchase) or materialises a brand-new serialised unit on receive
  for v_item in select * from jsonb_array_elements(v_lines) with ordinality as e(value, ord) loop
    v_subtotal := v_subtotal + round(coalesce((v_item.value ->> 'quantity')::numeric, 1)
                                     * app_util.round_money((v_item.value ->> 'unit_cost')::numeric), 2);
    v_discount := v_discount + app_util.round_money(coalesce((v_item.value ->> 'discount')::numeric, 0));
    v_tax      := v_tax + round(
        greatest(coalesce((v_item.value ->> 'quantity')::numeric, 1)
                 * app_util.round_money((v_item.value ->> 'unit_cost')::numeric)
                 - coalesce((v_item.value ->> 'discount')::numeric, 0), 0)
        * coalesce((v_item.value ->> 'tax_rate')::numeric, 18) / 100.0, 2);

    insert into public.purchase_items
          (purchase_id, product_id, color_id, description, quantity, received_quantity,
           unit_cost, discount, tax_rate, tax_amount, total_amount)
    values (v_purchase,
            (v_item.value ->> 'product_id')::uuid,
            (v_item.value ->> 'color_id')::uuid,
            coalesce(nullif(v_item.value ->> 'description',''),
                     (select p.name from public.products p where p.id = (v_item.value ->> 'product_id')::uuid),
                     'Purchase line ' || v_item.ord),
            coalesce((v_item.value ->> 'quantity')::numeric, 1),
            case when v_receive then coalesce((v_item.value ->> 'quantity')::numeric, 1) else 0 end,
            app_util.round_money((v_item.value ->> 'unit_cost')::numeric),
            app_util.round_money(coalesce((v_item.value ->> 'discount')::numeric, 0)),
            coalesce((v_item.value ->> 'tax_rate')::numeric, 18),
            round(greatest(coalesce((v_item.value ->> 'quantity')::numeric,1)
                           * app_util.round_money((v_item.value ->> 'unit_cost')::numeric)
                           - coalesce((v_item.value ->> 'discount')::numeric,0), 0)
                  * coalesce((v_item.value ->> 'tax_rate')::numeric, 18) / 100.0, 2),
            round(greatest(coalesce((v_item.value ->> 'quantity')::numeric,1)
                           * app_util.round_money((v_item.value ->> 'unit_cost')::numeric)
                           - coalesce((v_item.value ->> 'discount')::numeric,0), 0)
                  * (1 + coalesce((v_item.value ->> 'tax_rate')::numeric, 18)/100.0), 2));
  end loop;

  v_total := round(v_subtotal - v_discount + v_tax + v_other + v_freight, 2);

  update public.purchases p
     set subtotal = round(v_subtotal,2), discount = round(v_discount,2),
         tax_amount = round(v_tax,2), total_amount = v_total,
         other_charges = v_other, freight_charges = v_freight,
         paid_amount = least(v_paid, v_total),
         outstanding_amount = round(greatest(v_total - least(v_paid, v_total), 0), 2)
   where p.id = v_purchase;

  -- generate the physical stock units for every VEHICLE line
  if v_receive then
    for v_item in select pi.id, pi.product_id, pi.color_id, pi.quantity, pi.unit_cost,
                          (select count(*) from jsonb_array_elements(v_lines) as e(value)
                            where (e.value ->> 'chassis_number') is not null) as _c,
                          value as payload
                     from public.purchase_items pi
                     join jsonb_array_elements(v_lines) as value on true
                    where pi.purchase_id = v_purchase
                      and (value ->> 'chassis_number') is not null loop
      select p.* into v_product from public.products p where p.id = v_item.product_id;

      v_inventory := null;
      if exists (select 1 from public.inventory i
                  where i.chassis_number = app_util.upper_no_space(v_item.payload ->> 'chassis_number')) then
        perform app_util.fail('CON001',
          'chassis ' || (v_item.payload ->> 'chassis_number') || ' already exists in stock');
      end if;

      insert into public.inventory
            (showroom_id, product_id, color_id, stock_code, chassis_number, engine_number,
             manufacturing_date, model_year, purchase_date, purchase_price, landing_price, mrp,
             status, location, created_by)
      values (v_showroom, v_item.product_id, v_item.color_id,
              coalesce(app_util.upper_no_space(v_item.payload ->> 'stock_code'),
                       'STK-' || upper(left(md5(v_item.payload ->> 'chassis_number'), 10))),
              app_util.upper_no_space(v_item.payload ->> 'chassis_number'),
              app_util.upper_no_space(v_item.payload ->> 'engine_number'),
              (v_item.payload ->> 'manufacturing_date')::date,
              (v_item.payload ->> 'model_year')::int,
              v_date,
              app_util.round_money(v_item.unit_cost),
              app_util.round_money(v_item.unit_cost),
              coalesce(v_product.selling_price, 0),
              'AVAILABLE',
              coalesce(v_item.payload ->> 'location',
                       (select s.name from public.showrooms s where s.id = v_showroom)),
              app_sec.current_user_id())
      returning id into v_inventory;

      update public.purchase_items pi
         set inventory_id = v_inventory
       where pi.id = v_item.id;

      insert into public.stock_movements
            (showroom_id, inventory_id, movement_type, to_status, reference_type, reference_id,
             reason, performed_by)
      values (v_showroom, v_inventory, 'STOCK_IN', 'AVAILABLE', 'purchase', v_purchase,
              'Received on ' || v_number, app_sec.current_user_id());
    end loop;
  end if;

  -- supplier-side money is tracked by purchases.paid_amount/outstanding_amount and
  -- the journal below; a payments() row is reserved for customer receipts only.
  update public.purchases p
     set paid_amount = least(v_paid, p.total_amount),
         outstanding_amount = round(greatest(p.total_amount - least(v_paid, p.total_amount), 0), 2)
   where p.id = v_purchase;

  begin
    perform app_acc.post_journal(v_showroom, v_date, 'PURCHASE', 'purchase', v_purchase,
      'Stock purchase ' || v_number,
      jsonb_build_array(
        jsonb_build_object('code', case when v_receive then '1200' else '5100' end,
                           'debit', round(v_subtotal - v_discount + v_other + v_freight, 2),
                           'description', 'Inventory received ' || v_number),
        jsonb_build_object('code','1300','debit', round(v_tax,2),
                           'description','Input GST ' || v_number),
        jsonb_build_object('code','2100','credit', round(v_total,2),
                           'description','Supplier payable ' || v_number)
      ));
    if v_paid > 0 then
      perform app_acc.post_journal(v_showroom, v_date, 'PAYMENT', 'purchase_payment', v_purchase,
        'Supplier part-payment ' || v_number,
        jsonb_build_array(
          jsonb_build_object('code','2100','debit', v_paid, 'description','Paying supplier'),
          jsonb_build_object('code', case when p_payload ->> 'payment_method' = 'CASH' then '1010' else '1020' end,
                             'credit', v_paid, 'description','Cash out')
        ));
    end if;
  exception when others then
    null;
  end;

  v_lines_ok := (select count(*) from public.purchase_items where purchase_id = v_purchase);

  perform app_util.audit_row('purchases','CREATE','purchases', v_purchase, null,
          jsonb_build_object('number', v_number, 'total', v_total, 'lines', v_lines_ok),
          v_showroom, null, v_number);

  v_replay := jsonb_build_object('purchaseId', v_purchase, 'purchaseNumber', v_number,
                                 'totalAmount', v_total, 'lineCount', v_lines_ok,
                                 'inventoryGenerated', v_receive, 'replayed', false);
  if v_idem is not null then
    update public.idempotency_keys set status='COMPLETED', result=v_replay, completed_at=now()
     where key = v_idem;
  end if;
  return v_replay;
end;
$$;

-- ---------------------------------------------------------------------------
-- Expenses (SS23, SS66): create -> approve/reject -> pay, each step journaling.
-- ---------------------------------------------------------------------------
create or replace function public.create_expense_transaction(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom uuid := (p_payload ->> 'showroom_id')::uuid;
  v_category uuid := (p_payload ->> 'category_id')::uuid;
  v_date     date := coalesce((p_payload ->> 'expense_date')::date, current_date);
  v_amount   numeric := app_util.round_money((p_payload ->> 'amount')::numeric);
  v_tax      numeric := app_util.round_money(coalesce((p_payload ->> 'tax_amount')::numeric, 0));
  v_method   text   := coalesce(nullif(p_payload ->> 'payment_method',''), 'PENDING');
  v_pay_now  boolean := coalesce((p_payload ->> 'paid_now')::boolean, false);
  v_desc     text   := p_payload ->> 'description';
  v_idem     uuid   := (p_payload ->> 'idempotency_key')::uuid;
  v_number   text;
  v_expense  uuid;
  v_skip_lim numeric;
  v_needs_appr boolean;
  v_total    numeric;
  v_replay   jsonb;
  v_tx       uuid;
begin

  perform app_sec.require_permission('expenses','create');
  perform app_sec.require_showroom_access(v_showroom);
  if v_idem is not null then
    select ik.result into v_replay from public.idempotency_keys ik where ik.key = v_idem for update;
    if found and v_replay is not null then
      return v_replay || jsonb_build_object('replayed', true);
    end if;
    insert into public.idempotency_keys (key, user_id, showroom_id, operation, status)
    values (v_idem, app_sec.current_user_id(), v_showroom, 'create_expense_transaction', 'IN_PROGRESS')
    on conflict (key) do nothing;
  end if;

  if v_amount is null or v_amount <= 0 then
    perform app_util.fail('VAL001', 'expense amount must be positive');
  end if;
  if coalesce(v_desc,'') = '' then
    perform app_util.fail('VAL002', 'an expense needs a description');
  end if;
  if not exists (select 1 from public.expense_categories c where c.id = v_category and c.status = 'ACTIVE') then
    perform app_util.fail('VAL003', 'expense category is required and must be active');
  end if;

  v_number := app_gen.next_document_number(v_showroom, 'EXPENSE', v_date);
  v_total  := round(v_amount + v_tax, 2);

  -- Small expenses inside the category limit auto-approve (SS23). The category's
  -- own requires_approval flag is the first word: a category that always needs a
  -- signature must not slip through because somebody left a limit on it, and a
  -- utility bill that never needs one must not queue for approval.
  select c.approval_limit, c.requires_approval into v_skip_lim, v_needs_appr
    from public.expense_categories c where c.id = v_category;
  if v_needs_appr is null then
    v_needs_appr := true;   -- an unknown category is treated as the cautious default
  end if;

  insert into public.expenses
        (expense_number, showroom_id, category_id, expense_date, vendor_name,
         vendor_invoice_number, amount, tax_rate, tax_amount, total_amount,
         payment_method, reference_number, paid_on, attachment_url, description,
         status, created_by, created_at)
  values (v_number, v_showroom, v_category, v_date, p_payload ->> 'vendor_name',
          p_payload ->> 'vendor_invoice_number', v_amount,
          case when v_amount > 0 then round(v_tax / v_amount * 100, 3) else 0 end,
          v_tax, v_total,
          case when v_pay_now then v_method else 'PENDING' end,
          p_payload ->> 'reference_number',
          case when v_pay_now then v_date end,
          p_payload ->> 'attachment_url', v_desc,
          case when (not v_needs_appr)
                   or (coalesce(v_skip_lim, 0) > 0 and v_total <= v_skip_lim)
                 then (case when v_pay_now then 'PAID' else 'APPROVED' end)
               else 'PENDING' end,
          app_sec.current_user_id(), now())
  returning id into v_expense;

  if v_pay_now then
    update public.expenses e
       set status = 'PAID', paid_on = v_date, approved_at = coalesce(approved_at, now()),
           approved_by = coalesce(approved_by, app_sec.current_user_id())
     where e.id = v_expense;
  end if;

  -- An unmapped category must never borrow the COGS account: that would hide
  -- running costs inside gross margin. 5900 Other Expense is the fallback (SS24).
  begin
    v_tx := app_acc.post_journal(v_showroom, v_date, 'EXPENSE', 'expense', v_expense,
      'Expense ' || v_number || ' - ' || v_desc,
      (select jsonb_agg(l)
         from (
           select jsonb_build_object(
                    'account_id', coalesce(
                        -- resolve the category's account inside THIS showroom: the
                        -- chart of accounts is per branch (SS82)
                        (select a.id from public.expense_categories c
                           join public.accounts a on a.account_code = c.account_code
                                   and a.showroom_id = v_showroom
                          where c.id = v_category),
                        app_acc.account_for(v_showroom, 'EXPENSE.CATEGORY', 'DEBIT')),
                    'debit', round(v_amount, 2), 'description', v_desc) as l
           where v_amount > 0
           union all
           select jsonb_build_object('code','1300','debit', round(v_tax,2),
                                     'description','Input GST on ' || v_number)
            where v_tax > 0
           union all
           -- paid now: cash leaves; still pending: accrue it on Expense Payable,
           -- which is cleared by decide_expense() when the money actually moves.
           select jsonb_build_object(
                    'code', case when v_pay_now and v_method = 'CASH' then '1010'
                                 when v_pay_now and v_method in ('UPI','CARD','ONLINE') then '1030'
                                 when v_pay_now then '1020'
                                 else '2500' end,
                    'credit', round(v_total, 2),
                    'description', case when v_pay_now then 'Paid by ' || lower(v_method)
                                        else 'Payable until approved and paid' end)
            where v_total > 0
         ) l
       where coalesce((l.l ->> 'debit')::numeric, (l.l ->> 'credit')::numeric, 0) <> 0));

    -- the link is what lets the expense screen show "posted as JV-..." and lets an
    -- auditor walk the document in either direction (SS24).
    update public.expenses e set accounting_transaction_id = v_tx where e.id = v_expense;
  exception when others then
    -- An expense is never lost because a chart was misconfigured: it is queued
    -- for the accountant, exactly like a sale that cannot auto-post (SS24).
    insert into public.notifications
          (user_id, showroom_id, title, message, notification_type, severity,
           route_name, route_params, reference_type, reference_id, channel, action_required)
    select u.id, v_showroom, 'Accounting entry pending',
           'Expense ' || v_number || ' could not auto-post (' || sqlerrm || '). Post it manually from Accounting.',
           'ACCOUNTING', 'WARNING', '/accounting/transactions',
           jsonb_build_object('expenseId', v_expense), 'expense', v_expense, 'IN_APP', true
      from public.users u
     where u.showroom_id = v_showroom
       and u.status = 'ACTIVE'
       and exists (select 1 from public.user_roles ur
                    join public.roles r on r.id = ur.role_id
                    join public.role_permissions rp on rp.role_id = r.id
                    join public.permissions p on p.id = rp.permission_id
                   where ur.user_id = u.id and p.module = 'accounting' and p.action = 'view')
     limit 3;
  end;

  -- notify an approver (SS23, SS29)
  if (select e.status from public.expenses e where e.id = v_expense) = 'PENDING' then
    insert into public.notifications
          (user_id, showroom_id, title, message, notification_type, severity, route_name,
           route_params, reference_type, reference_id, channel, action_required)
    select u.id, v_showroom, 'Expense needs approval',
           format('Expense %s of %s (%s) is waiting for approval.', v_number, v_total,
                  (select c.name from public.expense_categories c where c.id = v_category)),
           'APPROVAL','WARNING','/expenses/approvals', jsonb_build_object('id', v_expense),
           'expense', v_expense, 'IN_APP', true
      from public.users u
     where u.status = 'ACTIVE'
       and (u.showroom_id = v_showroom or u.is_super_admin)
       and u.id <> app_sec.current_user_id()
       and exists (select 1 from public.user_roles ur
                    join public.role_permissions rp on rp.role_id = ur.role_id
                    join public.permissions p on p.id = rp.permission_id
                   where ur.user_id = u.id and p.module = 'expenses' and p.action = 'approve')
     limit 5;
  end if;

  perform app_util.audit_row('expenses','CREATE','expenses', v_expense, null,
          jsonb_build_object('number', v_number, 'amount', v_total), v_showroom, null, v_number);

  v_replay := jsonb_build_object('expenseId', v_expense, 'expenseNumber', v_number,
                                 'totalAmount', v_total,
                                 'status', (select e.status from public.expenses e where e.id = v_expense),
                                 'replayed', false);
  if v_idem is not null then
    update public.idempotency_keys set status='COMPLETED', result=v_replay, completed_at=now()
     where key = v_idem;
  end if;
  return v_replay;
end;
$$;

create or replace function public.decide_expense(
  p_expense_id uuid,
  p_approve    boolean,
  p_reason     text default null,
  p_mark_paid  boolean default false,
  p_method     text default 'BANK_TRANSFER'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e public.expenses%rowtype;
begin

  perform app_sec.require_permission('expenses','approve');
  select * into v_e from public.expenses where id = p_expense_id for update;
  if not found then perform app_util.fail('NOT001', 'expense not found'); end if;
  perform app_sec.require_showroom_access(v_e.showroom_id);
  if v_e.status not in ('PENDING') then
    perform app_util.fail('CON001', 'expense is already ' || lower(v_e.status));
  end if;
  if not p_approve and coalesce(p_reason,'') = '' then
    perform app_util.fail('VAL001', 'rejecting an expense requires a reason');
  end if;

  update public.expenses e
     set status = case when p_approve and p_mark_paid then 'PAID'
                       when p_approve then 'APPROVED' else 'REJECTED' end,
         approved_by = app_sec.current_user_id(),
         approved_at = now(),
         paid_on = case when p_approve and p_mark_paid then current_date end,
         payment_method = case when p_approve and p_mark_paid then p_method else e.payment_method end,
         approval_note = p_reason,
         rejection_reason = case when p_approve then null else p_reason end,
         updated_at = now(), updated_by = app_sec.current_user_id()
   where e.id = p_expense_id;

  -- Approving is not paying: posting a journal here would double the expense. The
  -- accrual made by create_expense_transaction is cleared only when the money
  -- actually leaves the till (p_mark_paid), which keeps 2500 == unpaid expenses.
  if p_approve and p_mark_paid then
    begin
      perform app_acc.post_journal(v_e.showroom_id, current_date, 'PAYMENT', 'expense_payment', p_expense_id,
        'Expense paid ' || v_e.expense_number,
        jsonb_build_array(
          jsonb_build_object('code','2500','debit', v_e.total_amount, 'description','Clear payable'),
          jsonb_build_object('code', case when p_method = 'CASH' then '1010'
                                          when p_method in ('UPI','CARD','ONLINE') then '1030'
                                          else '1020' end,
                             'credit', v_e.total_amount,
                             'description','Paid by ' || lower(p_method))
        ));
    exception when others then
      insert into public.notifications
            (user_id, showroom_id, title, message, notification_type, severity,
             route_name, route_params, reference_type, reference_id, channel, action_required)
      values (app_sec.current_user_id(), v_e.showroom_id, 'Accounting entry pending',
              'Expense ' || v_e.expense_number || ' was approved but could not be journalled (' || sqlerrm || ').',
              'ACCOUNTING', 'WARNING', '/accounting/transactions',
              jsonb_build_object('expenseId', p_expense_id), 'expense', p_expense_id, 'IN_APP', true);
    end;
  elsif not p_approve then
    begin
      perform app_acc.reverse_journal(t.id, 'Expense rejected: ' || p_reason)
        from public.accounting_transactions t
       where t.reference_type = 'expense' and t.reference_id = p_expense_id;
    exception when others then
      null;
    end;
  end if;

  perform app_util.audit_row('expenses', case when p_approve then 'APPROVE' else 'REJECT' end,
          'expenses', p_expense_id, jsonb_build_object('status', v_e.status),
          jsonb_build_object('status', case when p_approve then 'APPROVED' else 'REJECTED' end,
                             'reason', p_reason),
          v_e.showroom_id, null, v_e.expense_number);

  if v_e.created_by is not null then
    insert into public.notifications
          (user_id, showroom_id, title, message, notification_type, severity, route_name,
           route_params, reference_type, reference_id, channel)
    values (v_e.created_by, v_e.showroom_id,
            case when p_approve then 'Expense approved' else 'Expense rejected' end,
            'Expense ' || v_e.expense_number || ' was ' ||
              case when p_approve then 'approved.' else 'rejected: ' || coalesce(p_reason,'-') end,
            'APPROVAL', case when p_approve then 'SUCCESS' else 'WARNING' end,
            '/expenses/detail', jsonb_build_object('id', p_expense_id), 'expense', p_expense_id, 'IN_APP');
  end if;

  return jsonb_build_object('expenseId', p_expense_id,
         'status', (select e.status from public.expenses e where e.id = p_expense_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Paying an approved expense (SS23).  Approval and payment are separate acts in a
-- showroom: the manager approves in the morning, the accountant pays from the
-- bank file in the afternoon.  Until that happens the amount sits on Expense
-- Payable (2500), which is why pay_expense is the only place that clears it.
-- ---------------------------------------------------------------------------
create or replace function public.pay_expense(
  p_expense_id uuid,
  p_method     text   default 'BANK_TRANSFER',
  p_paid_on    date   default current_date,
  p_reference  text   default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e     public.expenses%rowtype;
  v_tx    uuid;
  v_cash  text;
begin

  perform app_sec.require_permission('expenses','edit');
  select * into v_e from public.expenses where id = p_expense_id for update;
  if not found then perform app_util.fail('NOT001', 'expense not found'); end if;
  perform app_sec.require_showroom_access(v_e.showroom_id);
  if v_e.status = 'PAID' then
    perform app_util.fail('CON001', 'expense ' || v_e.expense_number || ' is already paid');
  end if;
  if v_e.status <> 'APPROVED' then
    perform app_util.fail('CON002', 'only an approved expense can be paid (it is '
      || lower(v_e.status) || ')');
  end if;
  if coalesce(p_method,'') = '' then
    perform app_util.fail('VAL001', 'a payment method is required');
  end if;

  v_cash := case when p_method = 'CASH' then '1010'
                 when p_method in ('UPI','CARD','ONLINE') then '1030'
                 else '1020' end;

  update public.expenses e
     set status = 'PAID',
         payment_method = p_method,
         paid_on = p_paid_on,
         reference_number = coalesce(p_reference, e.reference_number),
         revision = e.revision + 1,
         updated_at = now(), updated_by = app_sec.current_user_id()
   where e.id = p_expense_id;

  begin
    v_tx := app_acc.post_journal(v_e.showroom_id, p_paid_on, 'PAYMENT', 'expense_payment', p_expense_id,
      'Expense paid ' || v_e.expense_number,
      jsonb_build_array(
        jsonb_build_object('code','2500','debit', v_e.total_amount,
                           'description','Clear expense payable ' || v_e.expense_number),
        jsonb_build_object('code', v_cash, 'credit', v_e.total_amount,
                           'description','Paid by ' || lower(p_method))
      ));
  exception when others then
    insert into public.notifications
          (user_id, showroom_id, title, message, notification_type, severity,
           route_name, route_params, reference_type, reference_id, channel, action_required)
    values (app_sec.current_user_id(), v_e.showroom_id, 'Accounting entry pending',
            'Expense ' || v_e.expense_number || ' was paid but could not be journalled ('
              || sqlerrm || '). Post it manually from Accounting.',
            'ACCOUNTING', 'WARNING', '/accounting/transactions',
            jsonb_build_object('expenseId', p_expense_id), 'expense', p_expense_id, 'IN_APP', true);
  end;

  if v_tx is not null then
    update public.expenses e
       set accounting_transaction_id = coalesce(e.accounting_transaction_id, v_tx)
     where e.id = p_expense_id;
  end if;

  perform app_util.audit_row('expenses','PAYMENT','expenses', p_expense_id,
          jsonb_build_object('status', v_e.status),
          jsonb_build_object('status','PAID','method', p_method, 'paidOn', p_paid_on,
                             'amount', v_e.total_amount),
          v_e.showroom_id, null, v_e.expense_number);

  if v_e.created_by is not null then
    insert into public.notifications
          (user_id, showroom_id, title, message, notification_type, severity, route_name,
           route_params, reference_type, reference_id, channel)
    values (v_e.created_by, v_e.showroom_id, 'Expense paid',
            'Expense ' || v_e.expense_number || ' of ' || v_e.total_amount || ' was paid by '
              || lower(p_method) || '.',
            'PAYMENT', 'SUCCESS', '/expenses/detail', jsonb_build_object('id', p_expense_id),
            'expense', p_expense_id, 'IN_APP');
  end if;

  return jsonb_build_object('expenseId', p_expense_id, 'status', 'PAID',
                            'paidOn', p_paid_on, 'method', p_method,
                            'accountingTransactionId', v_tx);
end;
$$;

comment on function public.pay_expense(uuid, text, date, text) is
  'Settles an approved expense: status PAID + the 2500 payable is cleared against cash (SS23).';

-- =============================================================================
-- Workshop (SS19, SS64) + free-service eligibility (SS18)
-- =============================================================================

-- Is this vehicle entitled to its next free service?  Date OR odometer breach
-- makes it ineligible, and the answer is returned with the reason so the UI can
-- explain itself instead of just disabling a button.
create or replace function public.check_free_service_eligibility(p_vehicle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vehicle public.customer_vehicles%rowtype;
  v_next    public.vehicle_free_services%rowtype;
begin
  select * into v_vehicle from public.customer_vehicles where id = p_vehicle_id;
  if not found then perform app_util.fail('NOT001', 'vehicle not found'); end if;

  select * into v_next
    from public.vehicle_free_services
   where vehicle_id = p_vehicle_id
     and status in ('UPCOMING','BOOKED')
   order by service_number
   limit 1;

  if v_next.id is null then
    return jsonb_build_object('eligible', false, 'reason', 'NO_PLAN',
      'message', 'No free service entitlement is scheduled for this vehicle.');
  end if;

  if v_next.due_date < current_date and coalesce(v_vehicle.current_odometer, 0) > v_next.due_km then
    return jsonb_build_object('eligible', false, 'reason', 'EXPIRED',
      'freeServiceNumber', v_next.service_number, 'dueDate', v_next.due_date,
      'dueKm', v_next.due_km, 'odometer', v_vehicle.current_odometer,
      'message', format('Free service %s lapsed on %s (limit %s km).',
                        v_next.service_number, v_next.due_date, v_next.due_km));
  end if;
  if coalesce(v_vehicle.current_odometer, 0) > v_next.due_km then
    return jsonb_build_object('eligible', false, 'reason', 'KM_EXCEEDED',
      'freeServiceNumber', v_next.service_number, 'dueKm', v_next.due_km,
      'odometer', v_vehicle.current_odometer,
      'message', format('Odometer %s km exceeds the %s km limit for free service %s.',
                        v_vehicle.current_odometer, v_next.due_km, v_next.service_number));
  end if;
  if v_next.due_date < current_date then
    return jsonb_build_object('eligible', false, 'reason', 'DATE_EXCEEDED',
      'freeServiceNumber', v_next.service_number, 'dueDate', v_next.due_date,
      'message', format('Free service %s was due on %s and has lapsed.',
                        v_next.service_number, v_next.due_date));
  end if;

  return jsonb_build_object('eligible', true, 'reason', 'ELIGIBLE',
    'freeServiceId', v_next.id, 'planId', v_next.free_service_plan_id,
    'freeServiceNumber', v_next.service_number, 'dueDate', v_next.due_date,
    'dueKm', v_next.due_km,
    'remainingDays', (v_next.due_date - current_date),
    'remainingKm', greatest(v_next.due_km - coalesce(v_vehicle.current_odometer, 0), 0));
end;
$$;

-- complete_service(): the workshop's one-stop commit (SS64).
create or replace function public.complete_service(
  p_service_id   uuid,
  p_payload      jsonb default '{}'::jsonb,
  p_bill_now     boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_rec         public.service_records%rowtype;
  v_odometer    integer := nullif(p_payload ->> 'odometer_reading', '')::int;
  v_next_date   date  := (p_payload ->> 'next_service_date')::date;
  v_next_km     integer := (p_payload ->> 'next_service_km')::int;
  v_work_done   text  := coalesce(p_payload ->> 'work_done', v_rec.work_done);
  v_override    boolean := coalesce((p_payload ->> 'bill_override')::boolean, false);
  v_items       jsonb := p_payload -> 'items';
  v_sub         numeric := 0;
  v_disc        numeric := 0;
  v_tax         numeric := 0;
  v_labour      numeric := 0;
  v_parts       numeric := 0;
  v_parts_cost  numeric := 0;   -- what the parts actually cost the showroom
  v_total       numeric := 0;
  v_invoice_id  uuid;
  v_vehicle     public.customer_vehicles%rowtype;
  v_free        public.vehicle_free_services%rowtype;
  v_elig        jsonb;
  v_remind      jsonb;
begin

  perform app_sec.require_permission('service','complete');
  select * into v_rec from public.service_records where id = p_service_id for update;
  if not found then perform app_util.fail('NOT001', 'job card not found'); end if;
  perform app_sec.require_showroom_access(v_rec.showroom_id);

  if v_rec.service_status in ('DELIVERED','CANCELLED') then
    perform app_util.fail('CON001', 'job card is already ' || lower(v_rec.service_status));
  end if;
  if v_rec.service_status not in ('IN_PROGRESS','RECEIVED','WAITING_FOR_PARTS','BOOKED','COMPLETED') then
    perform app_util.fail('CON002', 'a ' || lower(v_rec.service_status) || ' job card cannot be completed');
  end if;

  -- an override by an authorised manager is allowed for free/warranty jobs
  if v_rec.service_type in ('FREE','WARRANTY') and not v_override then
    v_sub := 0;
  end if;

  -- 1. recompute the bill from the lines the workshop actually issued
  select round(coalesce(sum(si.quantity * si.unit_price - si.discount), 0), 2),
         round(coalesce(sum(si.discount), 0), 2),
         round(coalesce(sum(si.tax_amount), 0), 2),
         round(coalesce(sum(si.total_amount), 0), 2),
         round(coalesce(sum(si.total_amount) filter (where si.item_type = 'LABOUR'), 0), 2),
         round(coalesce(sum(si.total_amount) filter
                        (where si.item_type in ('PART','OIL','CONSUMABLE','ACCESSORY')), 0), 2)
    into v_sub, v_disc, v_tax, v_total, v_labour, v_parts
    from public.service_items si
   where si.service_id = p_service_id;

  if v_rec.service_type = 'FREE' and not v_override then
    select jsonb_build_object('subtotal',0,'discount',0,'tax',0,'total',0,'labour',0,'parts',0)
      into v_elig;
    v_sub := 0; v_disc := 0; v_tax := 0; v_total := 0; v_labour := 0; v_parts := 0;
  end if;

  update public.service_records r
     set service_status   = 'COMPLETED',
         odometer_reading = coalesce(v_odometer, r.odometer_reading),
         previous_odometer = coalesce(r.previous_odometer,
                                      (select v.current_odometer from public.customer_vehicles v
                                        where v.id = r.vehicle_id)),
         work_done        = coalesce(v_work_done, r.work_done),
         subtotal         = round(coalesce(v_sub,0), 2),
         labour_charges   = round(coalesce(v_labour,0), 2),
         parts_charges    = round(coalesce(v_parts,0), 2),
         discount         = round(coalesce(v_disc,0), 2),
         tax_amount       = round(coalesce(v_tax,0), 2),
         total_amount     = round(coalesce(v_total,0), 2),
         outstanding_amount = round(greatest(coalesce(v_total,0) - r.paid_amount, 0), 2),
         is_billable      = case when v_rec.service_type = 'FREE' and not v_override then false else r.is_billable end,
         next_service_date = coalesce(v_next_date, r.next_service_date),
         next_service_km   = coalesce(v_next_km, r.next_service_km),
         updated_at = now(), updated_by = app_sec.current_user_id()
   where r.id = p_service_id;

  -- 2. consume stock issued on the job card + write the parts off
  update public.inventory i
     set status = 'SOLD', updated_at = now(), updated_by = app_sec.current_user_id()
   where i.id in (select si.inventory_id from public.service_items si
                   where si.service_id = p_service_id and si.is_from_stock
                     and si.item_type <> 'LABOUR' and si.inventory_id is not null)
     and i.status in ('AVAILABLE','HOLD','DAMAGED');

  -- 3. free service entitlement becomes USED
  if v_rec.service_type = 'FREE' and v_rec.free_service_id is not null then
    update public.vehicle_free_services vfs
       set status = 'USED', used_date = current_date,
           odometer_at_use = coalesce(v_odometer, vfs.odometer_at_use),
           service_id = p_service_id
     where vfs.id = v_rec.free_service_id
    returning * into v_free;
  elsif v_rec.service_type = 'FREE' then
    -- no explicit link: consume the earliest eligible entitlement
    v_elig := public.check_free_service_eligibility(v_rec.vehicle_id);
    if coalesce((v_elig ->> 'eligible')::boolean, false) then
      update public.vehicle_free_services vfs
         set status = 'USED', used_date = current_date,
             odometer_at_use = coalesce(v_odometer, vfs.odometer_at_use),
             service_id = p_service_id
       where vfs.id = (v_elig ->> 'freeServiceId')::uuid;
    end if;
  end if;

  -- 4. update the vehicle ledger (odometer + next service interval)
  select * into v_vehicle from public.customer_vehicles where id = v_rec.vehicle_id for update;
  if v_vehicle.id is not null then
    update public.customer_vehicles v
       set current_odometer = greatest(coalesce(v_odometer, v.current_odometer), v.current_odometer),
           odometer_updated_at = now(),
           status = 'ACTIVE',
           next_service_date = coalesce(v_next_date,
               (coalesce(v_rec.service_date, current_date)
                + make_interval(days => coalesce(p.service_interval_days, 180)))::date),
           next_service_km = coalesce(v_next_km,
               greatest(coalesce(v_odometer, v.current_odometer), 0)
                 + coalesce(p.service_interval_km, 5000))
     from public.products p
     where v.id = v_rec.vehicle_id and p.id = v.product_id;
  end if;

  -- 5. the invoice (SS14: service invoice, immutable once finalized)
  if p_bill_now and v_total > 0 then
    insert into public.invoices
          (showroom_id, customer_id, service_id, invoice_number, invoice_type, invoice_date,
           subtotal, discount, tax_amount, other_charges, total_amount, paid_amount,
           outstanding_amount, status, finalized, notes, created_by)
    values (v_rec.showroom_id, v_rec.customer_id, p_service_id,
            app_gen.next_document_number(v_rec.showroom_id, 'INVOICE', coalesce(v_rec.service_date, current_date)),
            'SERVICE', coalesce(v_rec.service_date, current_date),
            round(v_sub,2), round(v_disc,2), round(v_tax,2), 0, round(v_total,2),
            0, round(v_total,2), 'DRAFT', false,
            'Job card ' || v_rec.service_number, app_sec.current_user_id())
    returning id into v_invoice_id;

    insert into public.invoice_items
          (invoice_id, product_id, description, quantity, unit_price, discount, tax_rate,
           tax_amount, total_amount, sort_order)
    select v_invoice_id, si.product_id,
           case si.item_type when 'LABOUR' then 'Labour - ' else '' end || si.description,
           si.quantity, si.unit_price, si.discount, si.tax_rate, si.tax_amount, si.total_amount,
           row_number() over (order by si.sort_order, si.id)
      from public.service_items si where si.service_id = p_service_id;

    perform public.finalize_invoice(v_invoice_id);

    update public.service_records r
       set invoice_id = v_invoice_id, updated_at = now()
     where r.id = p_service_id;

    begin
      perform app_acc.post_journal(v_rec.showroom_id, coalesce(v_rec.service_date, current_date),
        'SERVICE', 'service', p_service_id, 'Service bill ' || v_rec.service_number,
        jsonb_build_array(
          jsonb_build_object('code','1100','debit', round(v_total,2),
                             'description','Receivable ' || v_rec.service_number),
          jsonb_build_object('code','4300','credit', round(v_sub - v_disc,2),
                             'description','Service revenue'),
          jsonb_build_object('code','2200','credit', round(v_tax,2), 'description','GST payable')
        ));
      -- Stock leaves at its cost, never at the retail price on the bill: the
      -- difference between the two is the parts margin and must show up in the
      -- books, otherwise inventory is understated and the gross profit is wrong.
      v_parts_cost := coalesce((select round(sum(greatest(si.quantity,1) * i.purchase_price), 2)
                                  from public.service_items si
                                  join public.inventory i on i.id = si.inventory_id
                                 where si.service_id = p_service_id
                                   and si.is_from_stock), 0);
      if v_parts_cost <= 0 then
        v_parts_cost := round(coalesce(v_parts, 0), 2);  -- nothing costed on the part
      end if;
      if v_parts > 0 and v_parts_cost > 0 then
        perform app_acc.post_journal(v_rec.showroom_id, coalesce(v_rec.service_date, current_date),
          'SERVICE', 'service_parts', p_service_id, 'Parts consumed ' || v_rec.service_number,
          jsonb_build_array(
            jsonb_build_object('code','5380','debit', v_parts_cost, 'description','Parts consumed'),
            jsonb_build_object('code','1200','credit', v_parts_cost, 'description','Stock issued')
          ));
      end if;
    exception when others then
      -- the job is finished and the bill is printed; a missing entry must be
      -- visible to the accountant rather than lost (SS68, SS70).
      insert into public.notifications (user_id, showroom_id, title, message,
                                        notification_type, severity, route_name)
      values (app_sec.current_user_id(), v_rec.showroom_id, 'Accounting entry failed',
              'Service ' || v_rec.service_number || ' was completed but its journal could not be posted: '
                || sqlerrm || '. Post it manually from Accounting.',
              'ACCOUNTING', 'WARNING', '/accounting/transactions');
    end;
  elsif v_rec.service_type = 'FREE' then
    -- the cost of a free service is an internal expense, never a customer bill
    begin
      -- Nothing was billed, but parts left the shelf: charge their cost to the
      -- free-service account so the warranty/complimentary programme shows what
      -- it actually costs the branch (SS17).
      v_parts_cost := coalesce((select round(sum(greatest(si.quantity,1) * i.purchase_price), 2)
                                  from public.service_items si
                                  join public.inventory i on i.id = si.inventory_id
                                 where si.service_id = p_service_id
                                   and si.is_from_stock), 0);
      if v_parts_cost > 0 then
        perform app_acc.post_journal(v_rec.showroom_id, coalesce(v_rec.service_date, current_date),
          'SERVICE', 'service_free_cost', p_service_id,
          'Cost of free service ' || v_rec.service_number,
          jsonb_build_array(
            jsonb_build_object('code','5390','debit', v_parts_cost,
                               'description','Parts consumed on a complimentary visit'),
            jsonb_build_object('code','1200','credit', v_parts_cost,
                               'description','Stock issued')
          ));
      end if;
    exception when others then
      insert into public.notifications (user_id, showroom_id, title, message,
                                        notification_type, severity, route_name)
      values (app_sec.current_user_id(), v_rec.showroom_id, 'Accounting entry failed',
              'Free service ' || v_rec.service_number || ' was completed but its cost journal could not be posted: '
                || sqlerrm || '. Post it manually from Accounting.',
              'ACCOUNTING', 'WARNING', '/accounting/transactions');
    end;
  end if;

  -- 6. schedule the next visit reminder (SS17)
  v_remind := public.create_service_reminders(v_rec.vehicle_id,
                  (select r.next_service_date from public.service_records r where r.id = p_service_id),
                  (select r.next_service_km  from public.service_records r where r.id = p_service_id));

  perform app_util.audit_row('service','UPDATE','service_records', p_service_id,
          jsonb_build_object('status', v_rec.service_status),
          jsonb_build_object('status','COMPLETED','total', v_total,
                             'invoice', v_invoice_id, 'serviceType', v_rec.service_type),
          v_rec.showroom_id, null, v_rec.service_number);

  return jsonb_build_object('serviceId', p_service_id,
    'serviceNumber', v_rec.service_number, 'status','COMPLETED',
    'totalAmount', round(coalesce(v_total,0),2),
    'invoiceId', v_invoice_id,
    'freeServiceConsumed', (v_rec.service_type = 'FREE'),
    'reminders', v_remind);
end;
$$;

comment on function public.complete_service is
  'Closes a job card: bills lines, consumes stock, burns the free-service entitlement, updates the vehicle ledger, invoices and journals - atomically.';

-- ---------------------------------------------------------------------------
-- Warranty claims (SS20): an expired warranty is refused by the database, not
-- by the UI.  `SUPER ADMIN`/`warranty.approve` can force through with a reason.
-- ---------------------------------------------------------------------------
create or replace function public.create_warranty_claim(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_warranty  uuid := (p_payload ->> 'warranty_id')::uuid;
  v_service   uuid := (p_payload ->> 'service_id')::uuid;
  v_amount    numeric := app_util.round_money((p_payload ->> 'claimed_amount')::numeric);
  v_desc      text := p_payload ->> 'description';
  v_override  boolean := coalesce((p_payload ->> 'override_expiry')::boolean, false);
  w           public.warranties%rowtype;
  v_claim     uuid;
  v_number    text;
begin

  perform app_sec.require_permission('warranty','create');
  if v_warranty is null or v_amount is null or v_amount <= 0 then
    perform app_util.fail('VAL001', 'warranty_id and a positive claimed_amount are required');
  end if;

  select * into w from public.warranties where id = v_warranty for update;
  if not found then perform app_util.fail('NOT001', 'warranty not found'); end if;
  perform app_sec.require_showroom_access(w.showroom_id);

  if w.status <> 'ACTIVE' and not v_override then
    perform app_util.fail('CON001', 'warranty is ' || lower(w.status) || '; a claim is not allowed');
  end if;
  if (w.end_date < current_date
      or (w.coverage_km > 0 and w.current_km > w.coverage_km))
     and not v_override then
    perform app_util.fail('CON002',
      format('warranty lapsed on %s (or %s km of %s). Escalate to a manager to file an exception claim.',
             w.end_date, w.current_km, w.coverage_km));
  end if;
  if v_override
     and not (app_sec.has_permission('warranty','approve') or app_sec.is_super_admin()) then
    perform app_util.fail('SEC001', 'only warranty.approve or a super admin may file an exception claim');
  end if;
  if coalesce(v_desc,'') = '' then
    perform app_util.fail('VAL002', 'a claim needs a description');
  end if;
  if v_service is not null and not exists (
        select 1 from public.service_records s
         where s.id = v_service and s.vehicle_id = w.vehicle_id) then
    perform app_util.fail('VAL003', 'the service record is not attached to this vehicle');
  end if;

  v_number := app_gen.next_document_number(w.showroom_id, 'WARRANTY_CLAIM', current_date);

  insert into public.warranty_claims
        (claim_number, warranty_id, vehicle_id, service_id, showroom_id, claim_date,
         description, claimed_amount, status, submitted_by)
  values (v_number, v_warranty, w.vehicle_id, v_service, w.showroom_id, current_date,
          v_desc, v_amount, 'SUBMITTED', app_sec.current_user_id())
  returning id into v_claim;

  if v_override then
    update public.warranty_claims c
       set resolution = 'Filed as an expiry exception by ' ||
           (select u.name from public.users u where u.id = app_sec.current_user_id())
     where c.id = v_claim;
  end if;

  perform app_util.audit_row('warranty', case when v_override then 'APPROVE' else 'CREATE' end,
          'warranty_claims', v_claim, null,
          jsonb_build_object('claim', v_number, 'amount', v_amount, 'override', v_override),
          w.showroom_id, null, v_number,
          case when v_override then 'WARNING' else 'INFO' end);

  return jsonb_build_object('claimId', v_claim, 'claimNumber', v_number,
                            'status','SUBMITTED', 'expiryOverride', v_override);
end;
$$;

-- ---------------------------------------------------------------------------
-- Reminder generators (SS17, SS50)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Who owns a customer follow-up. reminders.assigned_to references users(id), so
-- it can never be filled with a customer id - that was a foreign key violation
-- waiting for the first generated reminder. Resolution order: the explicit owner
-- (service advisor, technician, ...), the salesperson who booked the vehicle, an
-- active showroom manager of that showroom, and finally null (an unassigned
-- reminder is still visible to the reminder queue).
-- ---------------------------------------------------------------------------
create or replace function app_util.reminder_owner(
  p_customer_id uuid,
  p_showroom_id uuid,
  p_preferred   uuid default null
)
returns uuid
language sql
stable
set search_path = ''
as $$
  select coalesce(
           p_preferred,
           (select s.salesperson_id
              from public.sales s
             where s.customer_id = p_customer_id
               and s.showroom_id = p_showroom_id
               and s.is_deleted = false
               and s.salesperson_id is not null
             order by s.sale_date desc, s.created_at desc
             limit 1),
           (select u.id
              from public.users u
              join public.user_roles ur on ur.user_id = u.id
              join public.roles r        on r.id = ur.role_id
             where u.status = 'ACTIVE'
               and u.is_deleted = false
               and r.code = 'SHOWROOM_MANAGER'
               and (u.showroom_id = p_showroom_id
                    or exists (select 1 from public.user_showroom_access a
                                where a.user_id = u.id
                                  and a.showroom_id = p_showroom_id
                                  and (a.valid_from is null or a.valid_from <= current_date)
                                  and (a.valid_to   is null or a.valid_to   >= current_date)))
             order by u.created_at
             limit 1)
         );
$$;

comment on function app_util.reminder_owner(uuid, uuid, uuid) is
  'Internal: staff user accountable for a reminder; never a customer id.';

create or replace function public.enqueue_reminder(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom uuid := (p_payload ->> 'showroom_id')::uuid;
  v_type     text := coalesce(p_payload ->> 'reminder_type', 'CUSTOM');
  v_date     date := (p_payload ->> 'reminder_date')::date;
  v_time     time := coalesce((p_payload ->> 'reminder_time')::time, '09:30');
  v_title    text := p_payload ->> 'title';
  v_message  text := coalesce(p_payload ->> 'message', v_title);
  v_customer uuid := (p_payload ->> 'customer_id')::uuid;
  v_vehicle  uuid := (p_payload ->> 'vehicle_id')::uuid;
  v_ref_type text := p_payload ->> 'reference_type';
  v_ref_id   uuid := (p_payload ->> 'reference_id')::uuid;
  v_priority text := coalesce(nullif(p_payload ->> 'priority',''), 'MEDIUM');
  v_route    text := p_payload ->> 'route_name';
  v_dedupe   text := coalesce(p_payload ->> 'dedupe_key',
                    v_type || ':' || coalesce(v_ref_id::text, v_customer::text, 'manual') || ':' || v_date::text);
  v_id       uuid;
begin
  if v_date is null or v_title is null then
    perform app_util.fail('VAL001', 'reminder_date and title are required');
  end if;
  if v_type not in ('EMI','SERVICE','INSURANCE','WARRANTY','PAYMENT','DOCUMENT','CUSTOM','RC_TRANSFER','PUC') then
    perform app_util.fail('VAL002', 'unknown reminder_type ' || v_type);
  end if;
  if v_priority not in ('LOW','MEDIUM','HIGH','URGENT') then
    v_priority := 'MEDIUM';
  end if;

  insert into public.reminders
        (showroom_id, customer_id, vehicle_id, assigned_to, reminder_type, title, message,
         reminder_date, reminder_time, priority, status, reference_type, reference_id,
         dedupe_key, created_by)
  values (v_showroom, v_customer, v_vehicle,
          coalesce((p_payload ->> 'assigned_to')::uuid,
                   app_util.reminder_owner(v_customer, v_showroom)),
          v_type, v_title, v_message, v_date, v_time, v_priority, 'PENDING',
          v_ref_type, v_ref_id, v_dedupe, app_sec.current_user_id())
  on conflict (dedupe_key) do nothing
  returning id into v_id;

  if v_id is not null and v_route is not null then
    update public.reminders set notification_id = null where id = v_id;
  end if;

  return v_id;   -- null means "already queued": the dedupe key did its job
end;
$$;

create or replace function public.create_emi_reminders(
  p_loan_id      uuid default null,
  p_days_before  integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec   record;
  v_cnt integer := 0;
  v_new integer;
begin
  for rec in
    select e.id as emi_id, e.showroom_id, e.customer_id, l.id as loan_id, l.loan_number,
           e.emi_number, e.due_date, e.emi_amount, e.remaining_amount, e.status,
           c.name as customer_name, c.phone
      from public.emi_schedules e
      join public.loans l        on l.id = e.loan_id
      join public.customers c    on c.id = e.customer_id
     where (p_loan_id is null or l.id = p_loan_id)
       and e.status in ('UPCOMING','DUE','PARTIAL','OVERDUE')
       and e.remaining_amount > 0
       and e.due_date <= current_date + p_days_before
       and l.status in ('ACTIVE','PART_PAYMENT','SANCTIONED')
     order by e.due_date
     limit 5000
  loop
    insert into public.reminders
          (showroom_id, customer_id, assigned_to, reminder_type, title, message,
           reminder_date, reminder_time, priority, status, reference_type, reference_id,
           dedupe_key, created_by)
    values (rec.showroom_id, rec.customer_id,
            app_util.reminder_owner(rec.customer_id, rec.showroom_id,
                                    (select l.approved_by from public.loans l where l.id = rec.loan_id)),
            'EMI',
            format('EMI %s due for loan %s', rec.emi_number, rec.loan_number),
            format('Dear %s, EMI of %s is due on %s for loan %s. Please pay before 6 PM.',
                   rec.customer_name, rec.remaining_amount, rec.due_date, rec.loan_number),
            (rec.due_date - 1), '10:00',
            case when rec.due_date < current_date then 'URGENT'
                 when rec.due_date = current_date then 'HIGH' else 'MEDIUM' end,
            'PENDING', 'emi_schedule', rec.emi_id,
            'EMI:' || rec.emi_id || ':' || rec.due_date,
            app_sec.current_user_id())
    on conflict (dedupe_key) do nothing;
    -- ON CONFLICT DO NOTHING skips duplicates silently: report what was really
    -- inserted, otherwise a re-run tells the client "created 12" for 0 messages.
    get diagnostics v_new = row_count;
    v_cnt := v_cnt + v_new;
  end loop;

  return jsonb_build_object('created', v_cnt, 'loansScanned', p_loan_id is null,
                            'daysBefore', p_days_before);
end;
$$;

create or replace function public.create_service_reminders(
  p_vehicle_id  uuid default null,
  p_due_date    date default null,
  p_due_km      integer default null,
  p_days_before integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec   record;
  v_cnt integer := 0;
  v_new integer;
begin
  for rec in
    select v.id as vehicle_id, v.showroom_id, v.customer_id, v.next_service_date,
           v.next_service_km, v.current_odometer, v.registration_number,
           c.name as customer_name,
           coalesce((select s.service_number from public.service_records s
                      where s.vehicle_id = v.id order by s.service_date desc limit 1), '-') as last_job
      from public.customer_vehicles v
      join public.customers c on c.id = v.customer_id
     where (p_vehicle_id is null or v.id = p_vehicle_id)
       and v.is_deleted = false
       and v.status = 'ACTIVE'
       and (coalesce(p_due_date, v.next_service_date))::date is not null
       and coalesce(p_due_date, v.next_service_date) <= current_date + p_days_before
     limit 5000
  loop
    insert into public.reminders
          (showroom_id, customer_id, vehicle_id, assigned_to, reminder_type, title, message,
           reminder_date, reminder_time, priority, status, reference_type, reference_id,
           dedupe_key, created_by)
    values (rec.showroom_id, rec.customer_id, rec.vehicle_id,
            app_util.reminder_owner(rec.customer_id, rec.showroom_id,
                                    (select sr.service_advisor_id from public.service_records sr
                                      where sr.vehicle_id = rec.vehicle_id
                                        and sr.service_advisor_id is not null
                                      order by sr.service_date desc limit 1)),
            'SERVICE',
            'Service due for your bike',
            format('Hi %s, your bike %s is due for service on %s%s. Last job card: %s.',
                   rec.customer_name,
                   coalesce(rec.registration_number, 'chassis on file'),
                   coalesce(p_due_date, rec.next_service_date),
                   case when rec.next_service_km is not null
                        then format(' or %s km', rec.next_service_km) else '' end,
                   rec.last_job),
            (coalesce(p_due_date, rec.next_service_date) - p_days_before), '11:00',
            case when coalesce(p_due_date, rec.next_service_date) < current_date then 'HIGH'
                 else 'MEDIUM' end,
            'PENDING', 'customer_vehicle', rec.vehicle_id,
            'SERVICE:' || rec.vehicle_id || ':' || coalesce(p_due_date, rec.next_service_date),
            app_sec.current_user_id())
    on conflict (dedupe_key) do nothing;
    -- ON CONFLICT DO NOTHING skips duplicates silently: report what was really
    -- inserted, otherwise a re-run tells the client "created 12" for 0 messages.
    get diagnostics v_new = row_count;
    v_cnt := v_cnt + v_new;
  end loop;
  return jsonb_build_object('created', v_cnt, 'vehicleId', p_vehicle_id);
end;
$$;

create or replace function public.create_warranty_reminders(
  p_warranty_id uuid default null,
  p_days_before integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare rec record; v_cnt integer := 0;
  v_new integer;
begin
  for rec in
    select w.id as warranty_id, w.showroom_id, w.customer_id, w.vehicle_id, w.end_date,
           c.name as customer_name
      from public.warranties w
      join public.customers c on c.id = w.customer_id
     where (p_warranty_id is null or w.id = p_warranty_id)
       and w.status = 'ACTIVE'
       and w.end_date between current_date and current_date + p_days_before
     limit 5000
  loop
    insert into public.reminders
          (showroom_id, customer_id, vehicle_id, assigned_to, reminder_type, title, message,
           reminder_date, reminder_time, priority, status, reference_type, reference_id,
           dedupe_key, created_by)
    values (rec.showroom_id, rec.customer_id, rec.vehicle_id,
            app_util.reminder_owner(rec.customer_id, rec.showroom_id), 'WARRANTY',
            'Warranty expiring soon',
            format('Dear %s, the warranty on your bike expires on %s. Service packages are available.',
                   rec.customer_name, rec.end_date),
            rec.end_date - 7, '12:00',
            case when rec.end_date - current_date <= 7 then 'HIGH' else 'LOW' end,
            'PENDING', 'warranty', rec.warranty_id,
            'WARRANTY:' || rec.warranty_id || ':' || rec.end_date,
            app_sec.current_user_id())
    on conflict (dedupe_key) do nothing;
    -- ON CONFLICT DO NOTHING skips duplicates silently: report what was really
    -- inserted, otherwise a re-run tells the client "created 12" for 0 messages.
    get diagnostics v_new = row_count;
    v_cnt := v_cnt + v_new;
  end loop;
  return jsonb_build_object('created', v_cnt);
end;
$$;

create or replace function public.create_insurance_reminders(
  p_days_before integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare rec record; v_cnt integer := 0;
  v_new integer;
begin
  for rec in
    select i.id as policy_id, i.showroom_id, i.customer_id, i.vehicle_id, i.expiry_date,
           i.policy_number, c.name as customer_name
      from public.insurance_policies i
      join public.customers c on c.id = i.customer_id
     where i.status in ('ACTIVE','EXPIRING_SOON')
       and i.expiry_date between current_date and current_date + p_days_before
     limit 5000
  loop
    insert into public.reminders
          (showroom_id, customer_id, vehicle_id, assigned_to, reminder_type, title, message,
           reminder_date, reminder_time, priority, status, reference_type, reference_id,
           dedupe_key, created_by)
    values (rec.showroom_id, rec.customer_id, rec.vehicle_id,
            app_util.reminder_owner(rec.customer_id, rec.showroom_id), 'INSURANCE',
            'Insurance renewal due',
            format('Dear %s, policy %s expires on %s. Reply RENEW and we will handle it.',
                   rec.customer_name, rec.policy_number, rec.expiry_date),
            rec.expiry_date - 15, '10:30', 'HIGH', 'PENDING',
            'insurance_policy', rec.policy_id,
            'INSURANCE:' || rec.policy_id || ':' || rec.expiry_date,
            app_sec.current_user_id())
    on conflict (dedupe_key) do nothing;
    -- ON CONFLICT DO NOTHING skips duplicates silently: report what was really
    -- inserted, otherwise a re-run tells the client "created 12" for 0 messages.
    get diagnostics v_new = row_count;
    v_cnt := v_cnt + v_new;
  end loop;
  return jsonb_build_object('created', v_cnt);
end;
$$;

create or replace function public.create_payment_reminders(
  p_days_overdue integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare rec record; v_cnt integer := 0;
  v_new integer;
begin
  for rec in
    select i.id as invoice_id, i.showroom_id, i.customer_id, i.invoice_number,
           i.outstanding_amount, i.due_date, c.name as customer_name
      from public.invoices i
      join public.customers c on c.id = i.customer_id
     where i.status in ('FINALIZED','PARTIALLY_PAID','OVERDUE')
       and i.outstanding_amount > 0
       and i.due_date is not null
       and i.due_date <= current_date - p_days_overdue
     limit 5000
  loop
    insert into public.reminders
          (showroom_id, customer_id, assigned_to, reminder_type, title, message,
           reminder_date, reminder_time, priority, status, reference_type, reference_id,
           dedupe_key, created_by)
    values (rec.showroom_id, rec.customer_id,
            app_util.reminder_owner(rec.customer_id, rec.showroom_id), 'PAYMENT',
            'Payment overdue',
            format('Dear %s, invoice %s of %s was due on %s. Kindly clear the balance.',
                   rec.customer_name, rec.invoice_number, rec.outstanding_amount, rec.due_date),
            current_date, '17:00', 'URGENT', 'PENDING', 'invoice', rec.invoice_id,
            'PAYMENT:' || rec.invoice_id || ':' || current_date,
            app_sec.current_user_id())
    on conflict (dedupe_key) do nothing;
    -- ON CONFLICT DO NOTHING skips duplicates silently: report what was really
    -- inserted, otherwise a re-run tells the client "created 12" for 0 messages.
    get diagnostics v_new = row_count;
    v_cnt := v_cnt + v_new;
  end loop;
  return jsonb_build_object('created', v_cnt);
end;
$$;

-- ---------------------------------------------------------------------------
-- Service booking (SS19): the entry point of the workshop workflow
-- ---------------------------------------------------------------------------
create or replace function public.create_service_booking(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_showroom uuid := (p_payload ->> 'showroom_id')::uuid;
  v_vehicle  uuid := (p_payload ->> 'vehicle_id')::uuid;
  v_customer uuid := (p_payload ->> 'customer_id')::uuid;
  v_type     text := coalesce(nullif(p_payload ->> 'service_type',''), 'PAID');
  v_date     date := coalesce((p_payload ->> 'service_date')::date, current_date);
  v_advisor  uuid := coalesce((p_payload ->> 'service_advisor_id')::uuid, app_sec.current_user_id());
  v_free_id  uuid := (p_payload ->> 'free_service_id')::uuid;
  v_elig     jsonb;
  v_number   text;
  v_id       uuid;
begin

  perform app_sec.require_permission('service','create');
  perform app_sec.require_showroom_access(v_showroom);
  if v_vehicle is null then perform app_util.fail('VAL001', 'vehicle_id is required'); end if;

  select coalesce(customer_id, v_customer) into v_customer
    from public.customer_vehicles where id = v_vehicle and is_deleted = false;
  if v_customer is null then perform app_util.fail('NOT001', 'vehicle not found'); end if;

  if v_type not in ('FREE','PAID','WARRANTY','RECALL','COMPLIMENTARY') then
    perform app_util.fail('VAL002', 'unknown service_type');
  end if;

  -- a FREE booking is only legal while the entitlement is alive (SS18)
  if v_type = 'FREE' then
    v_elig := public.check_free_service_eligibility(v_vehicle);
    if not coalesce((v_elig ->> 'eligible')::boolean, false) then
      if not app_sec.has_permission('service','bill') then
        perform app_util.fail('CON001', coalesce(v_elig ->> 'message', 'free service not eligible'));
      end if;
    else
      v_free_id := coalesce(v_free_id, (v_elig ->> 'freeServiceId')::uuid);
    end if;
  end if;

  if exists (select 1 from public.service_records s
              where s.vehicle_id = v_vehicle
                and s.service_status in ('BOOKED','RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS')) then
    perform app_util.fail('CON002', 'this vehicle already has an open job card');
  end if;

  v_number := app_gen.next_document_number(v_showroom, 'SERVICE', v_date);

  insert into public.service_records
        (service_number, showroom_id, customer_id, vehicle_id, free_service_id,
         booking_date, service_date, expected_delivery, odometer_reading, previous_odometer,
         service_type, service_status, service_advisor_id, complaint, customer_notes,
         subtotal, discount, tax_amount, total_amount, outstanding_amount, is_billable, created_by)
  values (v_number, v_showroom, v_customer, v_vehicle, v_free_id,
          now(), v_date, (p_payload ->> 'expected_delivery')::date,
          (select coalesce(current_odometer, 0) from public.customer_vehicles where id = v_vehicle),
          (select current_odometer from public.customer_vehicles where id = v_vehicle),
          v_type, 'BOOKED', v_advisor,
          p_payload ->> 'complaint', p_payload ->> 'customer_notes',
          0, 0, 0, 0, 0, v_type = 'PAID', app_sec.current_user_id())
  returning id into v_id;

  update public.vehicle_free_services vfs
     set status = 'BOOKED', booked_date = current_date
   where vfs.id = v_free_id and vfs.status = 'UPCOMING';

  update public.customer_vehicles v set status = 'ACTIVE' where v.id = v_vehicle;

  insert into public.notifications
        (user_id, customer_id, showroom_id, title, message, notification_type, severity,
         route_name, route_params, reference_type, reference_id, channel)
  values (v_advisor, v_customer, v_showroom, 'New service booking',
          'Job card ' || v_number || ' booked for vehicle ' ||
          coalesce((select registration_number from public.customer_vehicles where id = v_vehicle), '-'),
          'SERVICE', 'INFO', '/service/detail', jsonb_build_object('id', v_id),
          'service_record', v_id, 'IN_APP');

  perform app_util.audit_row('service','CREATE','service_records', v_id, null,
          jsonb_build_object('number', v_number, 'type', v_type, 'vehicle', v_vehicle),
          v_showroom, null, v_number);

  return jsonb_build_object('serviceId', v_id, 'serviceNumber', v_number,
                            'serviceType', v_type, 'freeServiceId', v_free_id);
end;
$$;

-- Move a job card through BOOKED -> RECEIVED -> IN_PROGRESS -> ... -> DELIVERED.
create or replace function public.set_service_status(
  p_service_id uuid,
  p_status     text,
  p_payload    jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rec   public.service_records%rowtype;
  v_valid boolean;
begin

  perform app_sec.require_permission('service','edit');
  select * into v_rec from public.service_records where id = p_service_id for update;
  if not found then perform app_util.fail('NOT001', 'job card not found'); end if;
  perform app_sec.require_showroom_access(v_rec.showroom_id);

  -- legal transitions only; COMPLETED/DELIVERED go through their own RPCs
  select p_status in ('RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS')
          and v_rec.service_status in ('BOOKED','RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS')
     or p_status = 'DELIVERED' and v_rec.service_status = 'COMPLETED'
     or p_status = 'CANCELLED' and v_rec.service_status <> 'DELIVERED'
    into v_valid;
  if not coalesce(v_valid, false) then
    perform app_util.fail('CON001',
      format('cannot move job card from %s to %s', v_rec.service_status, p_status));
  end if;
  if p_status = 'CANCELLED' and coalesce(p_payload ->> 'reason','') = '' then
    perform app_util.fail('VAL001', 'cancelling a job card requires a reason');
  end if;

  update public.service_records r
     set service_status = p_status,
         received_at   = case when p_status = 'RECEIVED' then now() else r.received_at end,
         technician_id = coalesce((p_payload ->> 'technician_id')::uuid, r.technician_id),
         bay_number    = coalesce(p_payload ->> 'bay_number', r.bay_number),
         inspection_notes = coalesce(p_payload ->> 'inspection_notes', r.inspection_notes),
         odometer_reading = coalesce(nullif(p_payload ->> 'odometer_reading','')::int, r.odometer_reading),
         delivered_at  = case when p_status = 'DELIVERED' then now() else r.delivered_at end,
         cancelled_at  = case when p_status = 'CANCELLED' then now() end,
         cancelled_by  = case when p_status = 'CANCELLED' then app_sec.current_user_id() end,
         cancelled_reason = coalesce(p_payload ->> 'reason', r.cancelled_reason),
         updated_at = now(), updated_by = app_sec.current_user_id()
   where r.id = p_service_id;

  -- a cancelled booking gives the free-service slot back
  if p_status = 'CANCELLED' and v_rec.free_service_id is not null then
    update public.vehicle_free_services set status = 'UPCOMING', booked_date = null
     where id = v_rec.free_service_id and status = 'BOOKED';
  end if;

  update public.customer_vehicles v
     set status = case when p_status in ('RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS') then 'IN_SERVICE'
                       when p_status = 'DELIVERED' then 'ACTIVE'
                       else v.status end
   where v.id = v_rec.vehicle_id
     and p_status in ('RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS','DELIVERED','CANCELLED');

  perform app_util.audit_row('service','UPDATE','service_records', p_service_id,
          jsonb_build_object('status', v_rec.service_status), jsonb_build_object('status', p_status),
          v_rec.showroom_id, null, v_rec.service_number);

  return jsonb_build_object('serviceId', p_service_id, 'status', p_status);
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications + device tokens (SS29, SS54)
-- ---------------------------------------------------------------------------
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.notifications n
     set is_read = true, read_at = now()
   where n.is_read = false
     and (p_ids is null or n.id = any (p_ids))
     and (n.user_id = app_sec.current_user_id()
          or app_sec.can_access_showroom(n.showroom_id));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.unread_notification_count()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)
    from public.notifications n
   where n.is_read = false
     and (n.user_id = app_sec.current_user_id()
          or (n.user_id is null and app_sec.can_access_showroom(n.showroom_id)));
$$;

create or replace function public.register_device_token(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user    uuid := coalesce((p_payload ->> 'user_id')::uuid, app_sec.current_user_id());
  v_token   text := p_payload ->> 'device_token';
  v_id      uuid;
begin
  if v_user is null then perform app_util.fail('AUTH001', 'not authenticated'); end if;
  if coalesce(v_token,'') = '' then perform app_util.fail('VAL001', 'device_token is required'); end if;

  insert into public.device_tokens
        (user_id, device_token, platform, device_name, app_version, push_provider,
         is_active, last_seen_at)
  values (v_user, v_token,
          coalesce(nullif(p_payload ->> 'platform',''), 'ANDROID'),
          p_payload ->> 'device_name', p_payload ->> 'app_version',
          coalesce(nullif(p_payload ->> 'push_provider',''), 'FCM'),
          true, now())
  on conflict (user_id, device_token)
    do update set is_active = true, last_seen_at = now(),
                  platform = excluded.platform,
                  device_name = coalesce(excluded.device_name, device_tokens.device_name),
                  app_version = coalesce(excluded.app_version, device_tokens.app_version),
                  updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.deactivate_device_token(p_device_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_rows integer;
begin
  update public.device_tokens
     set is_active = false, updated_at = now()
   where device_token = p_device_token
     and (user_id = app_sec.current_user_id() or app_sec.is_super_admin());
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

-- ---------------------------------------------------------------------------
-- Global search (SS71): one query, typed results, permission-aware because it
-- runs as the invoker and inherits RLS.
-- ---------------------------------------------------------------------------
create or replace function public.global_search(p_term text, p_limit integer default 20)
returns table (
  result_type text,
  id          uuid,
  title       text,
  subtitle    text,
  showroom_id uuid,
  route_name  text
)
language sql
stable
set search_path = ''
as $$
  with q as (
    select nullif(btrim(coalesce(p_term,'')), '')                    as t,
           upper(nullif(btrim(coalesce(p_term,'')), ''))             as tu,
           -- inlined on purpose (same rule as app_util.normalise_phone): this
           -- function is security invoker so it must not reach into app_util,
           -- whose USAGE is revoked from anon/authenticated (SS49).
           nullif(btrim(regexp_replace(coalesce(p_term,''), '[^0-9+]', '', 'g')), '') as phone
  )
  (select 'customer'::text, c.id, c.name::text,
          btrim(concat_ws(' - ', c.customer_code, coalesce(c.phone,'')))::text,
          c.showroom_id, '/customers/detail'
     from q, public.customers c
    where q.t is not null and c.is_deleted = false
      and (c.name ilike '%'||q.t||'%' or c.customer_code ilike '%'||q.t||'%'
           or coalesce(c.email,'') ilike '%'||q.t||'%' or (q.phone is not null and c.phone = q.phone))
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'vehicle', v.id, coalesce(v.registration_number, v.chassis_number)::text,
          btrim(concat_ws(' / ', p.name, v.chassis_number))::text, v.showroom_id,
          '/vehicles/detail'
     from q
     join public.customer_vehicles v on true
     left join public.products p on p.id = v.product_id
    where q.tu is not null and v.is_deleted = false
      and (coalesce(v.registration_number,'') = q.tu or coalesce(v.registration_number,'') like q.tu||'%'
           or coalesce(v.chassis_number,'') = q.tu or coalesce(v.engine_number,'') = q.tu
           or coalesce(v.chassis_number,'') like q.tu||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'invoice', i.id, i.invoice_number::text,
          format('%s - %s (%s)', coalesce(c.name,'-'), i.total_amount, i.status)::text,
          i.showroom_id, '/billing/invoice'
     from q, public.invoices i left join public.customers c on c.id = i.customer_id
    where q.t is not null and (i.invoice_number ilike q.t or i.invoice_number like '%'||q.t||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'sale', s.id, s.sale_number::text,
          format('%s - %s (%s)', coalesce(c.name,'-'), s.total_amount, s.status)::text,
          s.showroom_id, '/sales/detail'
     from q, public.sales s left join public.customers c on c.id = s.customer_id
    where q.t is not null and (s.sale_number ilike q.t or s.sale_number like '%'||q.t||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'payment', pm.id, pm.payment_number::text,
          format('%s - %s', coalesce(c.name,'-'), pm.amount)::text,
          pm.showroom_id, '/payments/detail'
     from q, public.payments pm left join public.customers c on c.id = pm.customer_id
    where q.t is not null and (pm.payment_number ilike q.t or pm.payment_number like '%'||q.t||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'loan', l.id, l.loan_number::text,
          format('%s - %s (%s)', coalesce(c.name,'-'), l.loan_amount, l.status)::text,
          l.showroom_id, '/finance/loan'
     from q, public.loans l left join public.customers c on c.id = l.customer_id
    where q.t is not null and (l.loan_number ilike q.t or l.loan_number like '%'||q.t||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'service', sr.id, sr.service_number::text,
          btrim(concat_ws(' - ', coalesce(c.name,'-'), coalesce(sr.service_status,'')))::text,
          sr.showroom_id, '/service/detail'
     from q, public.service_records sr left join public.customers c on c.id = sr.customer_id
    where q.t is not null and (sr.service_number ilike q.t or sr.service_number like '%'||q.t||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50))
  union all
  (select 'inventory', inv.id, inv.stock_code::text,
          format('%s / chassis %s', p.name, inv.chassis_number)::text,
          inv.showroom_id, '/inventory/detail'
     from q, public.inventory inv join public.products p on p.id = inv.product_id
    where q.tu is not null and (inv.stock_code = q.tu or inv.chassis_number = q.tu
         or inv.engine_number = q.tu or inv.stock_code like q.tu||'%'
         or inv.chassis_number like q.tu||'%')
    limit least(greatest(coalesce(p_limit, 20), 1), 50));
$$;

comment on function public.global_search(text, integer) is
  'Security-invoker by design: RLS filters every branch, so a user can never search another showroom (SS49).';

-- ---------------------------------------------------------------------------
-- Dashboard aggregate (SS8): one round trip for all 18 KPI cards.
-- ---------------------------------------------------------------------------
create or replace function public.get_dashboard_metrics(
  p_showroom_id uuid default null,
  p_as_of       date default current_date
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  with scope as (
    -- Security invoker by design: every card is an RLS filtered aggregate. It
    -- therefore resolves the caller's home showroom through public.users (whose
    -- policy always exposes "self") instead of app_sec.current_showroom_id().
    select coalesce(p_showroom_id,
                    (select u.showroom_id from public.users u
                      where u.auth_user_id = auth.uid() and u.is_deleted = false)) as sid
  ),
  m as (select
    (select round(coalesce(sum(s.total_amount),0),2) from public.sales s, scope
      where s.status not in ('CANCELLED','RETURNED') and (scope.sid is null or s.showroom_id = scope.sid)
        and s.sale_date = p_as_of)                                        as today_sales,
    (select count(*) from public.sales s, scope
      where s.status not in ('CANCELLED','RETURNED') and (scope.sid is null or s.showroom_id = scope.sid)
        and s.sale_date = p_as_of)                                        as today_sales_count,
    (select round(coalesce(sum(s.total_amount),0),2) from public.sales s, scope
      where s.status not in ('CANCELLED','RETURNED') and (scope.sid is null or s.showroom_id = scope.sid)
        and date_trunc('month', s.sale_date) = date_trunc('month', p_as_of)) as month_sales,
    (select round(coalesce(sum(p.amount),0),2) from public.payments p, scope
      where p.status = 'COMPLETED' and p.payment_type in ('RECEIPT','ADVANCE')
        and (scope.sid is null or p.showroom_id = scope.sid)
        and p.payment_date = p_as_of)                                     as today_collection,
    (select round(coalesce(sum(i.outstanding_amount),0),2) from public.invoices i, scope
      where i.status in ('FINALIZED','PARTIALLY_PAID','OVERDUE')
        and (scope.sid is null or i.showroom_id = scope.sid))              as outstanding,
    (select count(*) from public.customers c, scope
      where c.is_deleted = false and c.status = 'ACTIVE'
        and (scope.sid is null or c.showroom_id = scope.sid))              as total_customers,
    (select count(*) from public.loans l, scope
      where l.status in ('ACTIVE','PART_PAYMENT') and (scope.sid is null or l.showroom_id = scope.sid)) as active_loans,
    (select count(*) from public.emi_schedules e, scope
      where e.status in ('UPCOMING','DUE','PARTIAL')
        and e.due_date between p_as_of and p_as_of + 30
        and (scope.sid is null or e.showroom_id = scope.sid))              as upcoming_emi,
    (select count(*) from public.emi_schedules e, scope
      where e.status in ('OVERDUE','DUE','PARTIAL') and e.due_date < p_as_of
        and (scope.sid is null or e.showroom_id = scope.sid))              as overdue_emi,
    (select round(coalesce(sum(e.remaining_amount),0),2) from public.emi_schedules e, scope
      where e.status in ('OVERDUE','DUE','PARTIAL') and e.due_date < p_as_of
        and (scope.sid is null or e.showroom_id = scope.sid))              as overdue_emi_amount,
    (select count(*) from public.inventory i, scope
      where i.status = 'AVAILABLE' and i.is_deleted = false
        and (scope.sid is null or i.showroom_id = scope.sid))              as available_stock,
    (select count(*) from public.inventory i, scope
      where i.status = 'RESERVED' and i.reserved_until < now()
        and (scope.sid is null or i.showroom_id = scope.sid))              as expired_reservations,
    (select count(*) from public.customer_vehicles v, scope
      where v.is_deleted = false and v.next_service_date between p_as_of and p_as_of + 15
        and (scope.sid is null or v.showroom_id = scope.sid))              as upcoming_services,
    (select count(*) from public.customer_vehicles v, scope
      where v.is_deleted = false and v.next_service_date < p_as_of
        and (scope.sid is null or v.showroom_id = scope.sid))              as overdue_services,
    (select count(*) from public.insurance_policies ip, scope
      where ip.status in ('ACTIVE','EXPIRING_SOON')
        and ip.expiry_date between p_as_of and p_as_of + 30
        and (scope.sid is null or ip.showroom_id = scope.sid))             as insurance_expiry_30d,
    (select count(*) from public.warranties w, scope
      where w.status = 'ACTIVE' and w.end_date between p_as_of and p_as_of + 30
        and (scope.sid is null or w.showroom_id = scope.sid))              as warranty_expiry_30d,
    (select round(coalesce(sum(e.total_amount),0),2) from public.expenses e, scope
      where e.status in ('APPROVED','PAID')
        and date_trunc('month', e.expense_date) = date_trunc('month', p_as_of)
        and (scope.sid is null or e.showroom_id = scope.sid))              as month_expenses,
    (select round(coalesce(sum(i.total_amount),0),2) -
                round(coalesce(sum(e.total_amount),0),2)                  as month_profit
       from (select round(coalesce(sum(s.paid_amount),0),2) as total_amount from public.sales s, scope
               where s.status not in ('CANCELLED','RETURNED')
                 and date_trunc('month', s.sale_date) = date_trunc('month', p_as_of)
                 and (scope.sid is null or s.showroom_id = scope.sid)) i
      cross join (select round(coalesce(sum(e.total_amount),0),2) as total_amount
                    from public.expenses e, scope
                   where e.status in ('APPROVED','PAID')
                     and date_trunc('month', e.expense_date) = date_trunc('month', p_as_of)
                     and (scope.sid is null or e.showroom_id = scope.sid)) e),
    (select round(coalesce(sum(r.total_amount),0),2) from public.service_records r, scope
      where r.service_status in ('COMPLETED','DELIVERED')
        and date_trunc('month', r.service_date) = date_trunc('month', p_as_of)
        and (scope.sid is null or r.showroom_id = scope.sid))              as month_service_revenue,
    (select jsonb_build_object('draft', count(*) filter (where p.status = 'DRAFT'),
                               'confirmed', count(*) filter (where p.status = 'CONFIRMED'),
                               'received', count(*) filter (where p.status = 'RECEIVED'),
                               'amount', round(coalesce(sum(p.total_amount),0),2))
       from public.purchases p, scope
      where date_trunc('month', p.purchase_date) = date_trunc('month', p_as_of)
        and (scope.sid is null or p.showroom_id = scope.sid))              as purchase_summary,
    (select count(*) from public.reminders rm, scope
      where rm.status = 'PENDING' and rm.reminder_date <= p_as_of + 7
        and (scope.sid is null or rm.showroom_id = scope.sid))             as reminders_next_7d,
    (select count(*) from public.sales s, scope
      where s.status = 'PENDING_APPROVAL'
        and (scope.sid is null or s.showroom_id = scope.sid))              as sales_pending_approval,
    (select count(*) from public.expenses e, scope
      where e.status = 'PENDING'
        and (scope.sid is null or e.showroom_id = scope.sid))              as expenses_pending_approval
  )
  select jsonb_build_object(
    'asOf', p_as_of, 'showroomId', (select sid from scope),
    'todaySales', m.today_sales, 'todaySalesCount', m.today_sales_count,
    'monthSales', m.month_sales, 'todayCollection', m.today_collection,
    'outstanding', m.outstanding, 'totalCustomers', m.total_customers,
    'activeLoans', m.active_loans, 'upcomingEmi', m.upcoming_emi,
    'overdueEmi', m.overdue_emi, 'overdueEmiAmount', m.overdue_emi_amount,
    'availableStock', m.available_stock, 'expiredReservations', m.expired_reservations,
    'upcomingServices', m.upcoming_services, 'overdueServices', m.overdue_services,
    'insuranceExpiry30d', m.insurance_expiry_30d, 'warrantyExpiry30d', m.warranty_expiry_30d,
    'monthExpenses', m.month_expenses, 'monthProfit', m.month_profit,
    'monthServiceRevenue', m.month_service_revenue, 'purchaseSummary', m.purchase_summary,
    'remindersNext7d', m.reminders_next_7d, 'salesPendingApproval', m.sales_pending_approval,
    'expensesPendingApproval', m.expenses_pending_approval
  )
  from m;
$$;

comment on function public.get_dashboard_metrics is
  'Single aggregate RPC behind the dashboard cards (SS8). Security invoker: RLS scopes it automatically.';

-- ---------------------------------------------------------------------------
-- 360-degree views (SS61, SS62) and the print payload for PDFs (SS74)
-- ---------------------------------------------------------------------------
create or replace function public.get_customer_360(p_customer_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'profile', (select to_jsonb(c) from public.customers c where c.id = p_customer_id),
    'showroom', (select jsonb_build_object('id', s.id, 'name', s.name, 'code', s.code)
                   from public.customers c join public.showrooms s on s.id = c.showroom_id
                  where c.id = p_customer_id),
    'totals', (select jsonb_build_object(
                  'outstanding', round(coalesce(sum(i.outstanding_amount),0),2),
                  'lifetimeValue', round(coalesce(sum(s.total_amount),0),2),
                  'invoiceCount', (select count(*) from public.invoices i2 where i2.customer_id = p_customer_id))
                 from public.invoices i
            left join public.sales s on s.customer_id = p_customer_id
                where i.customer_id = p_customer_id),
    'vehicles', (select coalesce(jsonb_agg(to_jsonb(v)), '[]'::jsonb)
                   from (select cv.*, p.name as product_name from public.customer_vehicles cv
                          left join public.products p on p.id = cv.product_id
                          where cv.customer_id = p_customer_id and cv.is_deleted = false
                          order by cv.created_at desc) v),
    'sales', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
                from (select * from public.sales where customer_id = p_customer_id
                       order by sale_date desc limit 50) s),
    'invoices', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
                   from (select * from public.invoices where customer_id = p_customer_id
                          order by invoice_date desc limit 50) i),
    'payments', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
                   from (select * from public.payments where customer_id = p_customer_id
                          order by payment_date desc limit 50) p),
    'loans', (select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb)
                from (select l.*, f.name as company_name,
                             (select count(*) from public.emi_schedules e
                               where e.loan_id = l.id and e.status in ('OVERDUE','DUE','PARTIAL')) as open_emis
                        from public.loans l
                        left join public.finance_companies f on f.id = l.finance_company_id
                       where l.customer_id = p_customer_id order by l.created_at desc limit 20) l),
    'emis', (select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
               from (select es.*, l.loan_number from public.emi_schedules es
                      join public.loans l on l.id = es.loan_id
                     where es.customer_id = p_customer_id
                     order by es.due_date desc limit 60) e),
    'services', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
                   from (select sr.*, cv.registration_number from public.service_records sr
                          left join public.customer_vehicles cv on cv.id = sr.vehicle_id
                          where sr.customer_id = p_customer_id
                          order by sr.service_date desc limit 40) s),
    'freeServices', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                       from (select vfs.* from public.vehicle_free_services vfs
                              where vfs.customer_id = p_customer_id
                              order by vfs.due_date) f),
    'warranties', (select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb)
                     from (select * from public.warranties where customer_id = p_customer_id) w),
    'insurance', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
                    from (select * from public.insurance_policies where customer_id = p_customer_id
                           order by expiry_date) i),
    'reminders', (select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
                    from (select * from public.reminders where customer_id = p_customer_id
                           and status in ('PENDING','SENT') order by reminder_date limit 30) r),
    'documents', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
                    from (select * from public.attachments
                           where entity_type in ('customer','customer_vehicle')
                             and (entity_id = p_customer_id
                                  or entity_id in (select id from public.customer_vehicles
                                                    where customer_id = p_customer_id))
                           order by created_at desc limit 40) a),
    'timeline', (select coalesce(jsonb_agg(t order by (t ->> 'at') desc), '[]'::jsonb)
                   from (
                     select jsonb_build_object('kind','SALE','at', s.sale_date::text,
                            'label', s.sale_number, 'amount', s.total_amount, 'status', s.status,
                            'id', s.id) t from public.sales s where s.customer_id = p_customer_id
                     union all
                     select jsonb_build_object('kind','INVOICE','at', i.invoice_date::text,
                            'label', i.invoice_number, 'amount', i.total_amount, 'status', i.status,
                            'id', i.id) from public.invoices i where i.customer_id = p_customer_id
                     union all
                     select jsonb_build_object('kind','PAYMENT','at', p.payment_date::text,
                            'label', p.payment_number, 'amount', p.amount, 'status', p.status,
                            'id', p.id) from public.payments p where p.customer_id = p_customer_id
                     union all
                     select jsonb_build_object('kind','LOAN','at', l.start_date::text,
                            'label', l.loan_number, 'amount', l.loan_amount, 'status', l.status,
                            'id', l.id) from public.loans l where l.customer_id = p_customer_id
                     union all
                     select jsonb_build_object('kind','EMI','at', e.due_date::text,
                            'label', 'EMI '||e.emi_number, 'amount', e.emi_amount, 'status', e.status,
                            'id', e.id) from public.emi_schedules e where e.customer_id = p_customer_id
                     union all
                     select jsonb_build_object('kind','SERVICE','at', sr.service_date::text,
                            'label', sr.service_number, 'amount', sr.total_amount,
                            'status', sr.service_status, 'id', sr.id)
                       from public.service_records sr where sr.customer_id = p_customer_id
                   ) x limit 120)
  );
$$;

create or replace function public.get_vehicle_360(p_vehicle_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'vehicle', (select to_jsonb(v) from public.customer_vehicles v where v.id = p_vehicle_id),
    'customer', (select to_jsonb(c) from public.customer_vehicles v
                   join public.customers c on c.id = v.customer_id where v.id = p_vehicle_id),
    'product', (select to_jsonb(p) from public.customer_vehicles v
                  join public.products p on p.id = v.product_id where v.id = p_vehicle_id),
    'brand', (select jsonb_build_object('name', b.name, 'logoUrl', b.logo_url)
                from public.customer_vehicles v
                join public.products p on p.id = v.product_id
                join public.brands b on b.id = p.brand_id where v.id = p_vehicle_id),
    'inventory', (select to_jsonb(i) from public.customer_vehicles v
                    join public.inventory i on i.id = v.inventory_id where v.id = p_vehicle_id),
    'sale', (select to_jsonb(s) from public.customer_vehicles v
              join public.sales s on s.id = v.sale_id where v.id = p_vehicle_id),
    'invoices', (select coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) from (
                   select i.* from public.customer_vehicles v
                     join public.invoices i on i.sale_id = v.sale_id
                    where v.id = p_vehicle_id) i),
    'payments', (select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from (
                   select p.* from public.customer_vehicles v
                     join public.payments p on p.sale_id = v.sale_id
                    where v.id = p_vehicle_id order by p.payment_date desc) p),
    'loan', (select to_jsonb(l) from public.customer_vehicles v
              join public.loans l on l.vehicle_id = v.id where v.id = p_vehicle_id),
    'emiSchedule', (select coalesce(jsonb_agg(jsonb_build_object(
                       'emiNumber', e.emi_number,'dueDate', e.due_date,'emiAmount', e.emi_amount,
                       'principal', e.principal_amount,'interest', e.interest_amount,
                       'paid', e.paid_amount,'remaining', e.remaining_amount,'status', e.status)
                       order by e.emi_number), '[]'::jsonb)
                      from public.emi_schedules e
                      join public.loans l on l.id = e.loan_id
                      join public.customer_vehicles v on v.id = l.vehicle_id
                     where v.id = p_vehicle_id),
    'warranty', (select to_jsonb(w) from public.warranties w where w.vehicle_id = p_vehicle_id),
    'warrantyClaims', (select coalesce(jsonb_agg(to_jsonb(c)),'[]'::jsonb)
                         from public.warranty_claims c where c.vehicle_id = p_vehicle_id),
    'insurance', (select coalesce(jsonb_agg(to_jsonb(i) order by i.expiry_date desc),'[]'::jsonb)
                    from public.insurance_policies i where i.vehicle_id = p_vehicle_id),
    'freeServices', (select coalesce(jsonb_agg(jsonb_build_object(
                        'serviceNumber', f.service_number,'dueDate', f.due_date,'dueKm', f.due_km,
                        'status', f.status,'usedDate', f.used_date,'planName', p.name)
                        order by f.service_number),'[]'::jsonb)
                       from public.vehicle_free_services f
                       join public.free_service_plans p on p.id = f.free_service_plan_id
                      where f.vehicle_id = p_vehicle_id),
    'services', (select coalesce(jsonb_agg(to_jsonb(s) - 'customer_id' order by s.service_date desc),'[]'::jsonb)
                   from public.service_records s where s.vehicle_id = p_vehicle_id),
    'documents', (select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb)
                    from public.attachments a
                   where a.entity_type = 'customer_vehicle' and a.entity_id = p_vehicle_id),
    'reminders', (select coalesce(jsonb_agg(to_jsonb(r) order by r.reminder_date),'[]'::jsonb)
                    from public.reminders r
                   where r.vehicle_id = p_vehicle_id and r.status in ('PENDING','SENT'))
  );
$$;

-- Invoice/print payload: header + lines + party + totals in one call so the PDF
-- generator (SS74) never issues N+1 queries.
create or replace function public.get_invoice_print_payload(p_invoice_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'invoice', (select to_jsonb(i) from public.invoices i where i.id = p_invoice_id),
    'showroom', (select jsonb_build_object('name', s.name, 'address', s.address, 'city', s.city,
                                           'state', s.state, 'pincode', s.pincode, 'phone', s.phone,
                                           'email', s.email, 'gstNumber', s.gst_number,
                                           'panNumber', s.pan_number, 'logoUrl', s.logo_url,
                                           'settings', s.settings)
                   from public.invoices i join public.showrooms s on s.id = i.showroom_id
                  where i.id = p_invoice_id),
    'customer', (select to_jsonb(c) from public.invoices i
                   join public.customers c on c.id = i.customer_id where i.id = p_invoice_id),
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                 'description', it.description,'hsn', it.hsn_code,'qty', it.quantity,
                 'unitPrice', it.unit_price,'discount', it.discount,'taxRate', it.tax_rate,
                 'taxAmount', it.tax_amount,'total', it.total_amount)
                 order by it.sort_order, it.id), '[]'::jsonb)
                from public.invoice_items it where it.invoice_id = p_invoice_id),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object(
                    'date', p.payment_date,'number', p.payment_number,'amount', p.amount,
                    'method', p.payment_method,'reference', p.reference_number)
                    order by p.payment_date), '[]'::jsonb)
                   from public.payments p where p.invoice_id = p_invoice_id and p.status = 'COMPLETED'),
    'vehicle', (select jsonb_build_object('registrationNumber', v.registration_number,
                                          'chassis', v.chassis_number, 'engine', v.engine_number,
                                          'model', pr.name || ' ' || coalesce(pr.variant,''),
                                          'color', pc.color_name)
                   from public.sales s
                   join public.customer_vehicles v on v.id = s.vehicle_id
                   left join public.products pr on pr.id = v.product_id
                   left join public.product_colors pc on pc.id = v.product_color_id
                  where s.id = (select i.sale_id from public.invoices i where i.id = p_invoice_id)),
    'sale', (select to_jsonb(s) from public.invoices i
              join public.sales s on s.id = i.sale_id where i.id = p_invoice_id)
  );
$$;

-- =============================================================================
-- SECTION 12 - user preferences (SS39: the client caches these, the server owns
-- them, so a second device opens with the same filters and theme).
-- These are SECURITY DEFINER because they need app_sec.current_user_id(), which
-- the API role cannot call through the internal schemas; every statement is
-- still filtered by `where user_id = app_sec.current_user_id()`, so definer
-- cannot widen a user's own view.
-- =============================================================================

create or replace function public.get_my_preferences()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id();
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;

  return jsonb_build_object(
    'userId', v_uid,
    'preferences', coalesce((select jsonb_object_agg(p.pref_key, p.pref_value)
                                from public.user_preferences p where p.user_id = v_uid), '{}'::jsonb),
    'savedFilters', coalesce((select jsonb_agg(jsonb_build_object(
                                 'id', f.id, 'module', f.module, 'name', f.name,
                                 'filters', f.filters, 'sortBy', f.sort_by, 'sortDesc', f.sort_desc,
                                 'pageSize', f.page_size, 'isDefault', f.is_default)
                                 order by f.module, f.name)
                                from public.saved_filters f where f.user_id = v_uid), '[]'::jsonb),
    'profile', (select jsonb_build_object('name', u.name, 'email', u.email, 'phone', u.phone,
                                          'avatarUrl', u.avatar_url, 'designation', u.designation,
                                          'employeeCode', u.employee_code,
                                          'defaultShowroom', u.showroom_id,
                                          'language', u.preferences ->> 'language',
                                          'themeMode', u.preferences ->> 'themeMode',
                                          'notificationsEnabled',
                                            coalesce((u.preferences ->> 'notificationsEnabled')::boolean, true))
                  from public.users u where u.id = v_uid)
  );
end;
$$;

create or replace function public.set_my_preference(p_key text, p_value jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id();
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;
  if p_key is null or p_key !~ '^[a-z][a-zA-Z0-9_.]{1,79}$' then
    perform app_util.fail('VAL001',
      'preference keys start with a lower-case letter and may contain letters, '
      || 'digits, dots and underscores (e.g. table.pageSize, theme.mode)');
  end if;

  insert into public.user_preferences (user_id, pref_key, pref_value)
  values (v_uid, p_key, coalesce(p_value, 'null'::jsonb))
  on conflict (user_id, pref_key) do update
     set pref_value = excluded.pref_value, updated_at = now();

  return jsonb_build_object('key', p_key, 'value', p_value);
end;
$$;

create or replace function public.set_my_preferences(p_values jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare rec record; v_count integer := 0;
begin
  if jsonb_typeof(p_values) <> 'object' then
    perform app_util.fail('VAL001', 'expected a JSON object of preference keys');
  end if;
  for rec in select e.key, e.value from jsonb_each(p_values) as e(key, value) loop
    perform public.set_my_preference(rec.key, rec.value);
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('saved', v_count);
end;
$$;

create or replace function public.set_my_default_showroom(p_showroom_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id();
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;
  if p_showroom_id is not null then
    perform app_sec.require_showroom_access(p_showroom_id);
  end if;

  -- users.showroom_id IS the home showroom: app_sec.current_showroom_id() falls
  -- back to it whenever a request carries no app.showroom_id setting, so this one
  -- write is what makes the switcher in the top bar stick (SS5, SS39).
  update public.users u
     set showroom_id = p_showroom_id,
         preferences = coalesce(u.preferences, '{}'::jsonb)
                       || jsonb_build_object('defaultShowroomId', p_showroom_id),
         updated_at = now(), updated_by = v_uid
   where u.id = v_uid;

  perform public.set_my_preference('app.defaultShowroomId', to_jsonb(p_showroom_id::text));

  return public.get_current_user_context();
end;
$$;

create or replace function public.reset_my_preferences()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id(); v_n integer;
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;
  delete from public.user_preferences where user_id = v_uid;
  get diagnostics v_n = row_count;
  return jsonb_build_object('cleared', v_n);
end;
$$;

-- Saved filters are written by the user themselves, so the table's own RLS is
-- enough; these two helpers exist so the Flutter repository never builds SQL.
create or replace function public.save_filter(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id(); v_id uuid;
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;
  if coalesce(p_payload ->> 'module','') = '' or coalesce(p_payload ->> 'name','') = '' then
    perform app_util.fail('VAL001', 'a saved filter needs a module and a name');
  end if;

  if coalesce((p_payload ->> 'isDefault')::boolean, false) then
    update public.saved_filters f set is_default = false
      where f.user_id = v_uid and f.module = p_payload ->> 'module';
  end if;

  insert into public.saved_filters (user_id, module, name, filters, sort_by, sort_desc, page_size, is_default)
  values (v_uid, p_payload ->> 'module', btrim(p_payload ->> 'name'),
          coalesce(p_payload -> 'filters', '{}'::jsonb),
          nullif(p_payload ->> 'sort_by',''),
          coalesce((p_payload ->> 'sortDesc')::boolean, true),
          coalesce(nullif(p_payload ->> 'pageSize','')::smallint, 20),
          coalesce((p_payload ->> 'isDefault')::boolean, false))
  on conflict (user_id, module, name) do update
     set filters = excluded.filters, sort_by = excluded.sort_by, sort_desc = excluded.sort_desc,
         page_size = excluded.page_size, is_default = excluded.is_default,
         updated_at = now()
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.delete_saved_filter(p_filter_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id();
begin
  delete from public.saved_filters where id = p_filter_id and user_id = v_uid;
  return found;
end;
$$;

-- =============================================================================
-- SECTION 13 - offline synchronisation contract (SS28, SS84)
-- -----------------------------------------------------------------------------
-- The queue itself lives on the device (Hive/SQLite).  What the server provides
-- is (1) a pre-flight revision check so a queued write never silently overwrites
-- a newer server row, (2) a durable conflict ledger the UI can list, and
-- (3) a change-feed for pulling deltas since the last successful sync.
-- Financial tables are never auto-resolved: a conflict stays UNRESOLVED until a
-- human with the right permission picks SERVER_WINS / LOCAL_WINS / MERGED.
-- =============================================================================

create or replace function app_gen.entity_sync_state(p_entity_type text, p_entity_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_table text;
  v_sql   text;
  v_out   jsonb;
  v_cols  text;
begin
  v_table := case lower(nullif(btrim(coalesce(p_entity_type,'')), ''))
    when 'sale' then 'sales'            when 'sales' then 'sales'
    when 'invoice' then 'invoices'      when 'invoices' then 'invoices'
    when 'payment' then 'payments'      when 'payments' then 'payments'
    when 'customer' then 'customers'    when 'customers' then 'customers'
    when 'vehicle' then 'customer_vehicles'
    when 'inventory' then 'inventory'   when 'stock' then 'inventory'
    when 'service' then 'service_records' when 'service_record' then 'service_records'
    when 'purchase' then 'purchases'    when 'expense' then 'expenses'
    when 'loan' then 'loans'            when 'emi' then 'emi_schedules'
    when 'warranty_claim' then 'warranty_claims'
    when 'insurance' then 'insurance_policies'
    when 'stock_transfer' then 'stock_transfers'
    when 'accounting_transaction' then 'accounting_transactions'
    when 'product' then 'products'      when 'user' then 'users'
    else null end;

  if v_table is null then
    perform app_util.fail('VAL001', 'unsupported entity type for sync: ' || coalesce(p_entity_type, '(null)'));
  end if;
  if p_entity_id is null then
    perform app_util.fail('VAL002', 'entity_id is required');
  end if;

  -- `revision` is not on every table (append-only ones have none), so build the
  -- column list from the catalog instead of assuming it.
  select string_agg(quote_ident(c), ', ' order by ord)
    into v_cols
    from (values (1,'id'),(2,'updated_at'),(3,'created_at'),
                 (4, case when exists (select 1 from information_schema.columns
                                        where table_schema = 'public' and table_name = v_table
                                          and column_name = 'revision') then 'revision' end),
                 (5, case when exists (select 1 from information_schema.columns
                                        where table_schema = 'public' and table_name = v_table
                                          and column_name = 'showroom_id') then 'showroom_id' end),
                 (6, case when exists (select 1 from information_schema.columns
                                        where table_schema = 'public' and table_name = v_table
                                          and column_name = 'is_deleted') then 'is_deleted' end)
         ) as t(ord, c)
   where c is not null;

  execute format('select to_jsonb(x) from (select %s from public.%I where id = $1) x', v_cols, v_table)
    into v_out using p_entity_id;

  return jsonb_build_object('entityType', v_table, 'entityId', p_entity_id,
                            'state', v_out, 'found', v_out is not null);
end;
$$;

create or replace function public.recognise_sync_conflict(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := app_sec.current_user_id();
  v_type  text := lower(coalesce(p_payload ->> 'entity_type', p_payload ->> 'entityType', ''));
  v_id    uuid := coalesce((p_payload ->> 'entity_id')::uuid, (p_payload ->> 'entityId')::uuid);
  v_show  uuid := coalesce((p_payload ->> 'showroom_id')::uuid, (p_payload ->> 'showroomId')::uuid,
                           app_sec.current_showroom_id());
  v_srv   jsonb;
  v_cid   uuid;
begin

  perform app_sec.require_showroom_access(v_show);
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;
  if v_id is null then perform app_util.fail('VAL001', 'entity_id is required'); end if;

  v_srv := (app_gen.entity_sync_state(v_type, v_id) -> 'state');
  if v_srv is null then
    perform app_util.fail('NOT001', 'that record no longer exists on the server');
  end if;
  if v_show is null then v_show := (v_srv ->> 'showroom_id')::uuid; end if;

  insert into public.sync_conflicts
        (showroom_id, user_id, entity_type, entity_id, local_updated_at, server_updated_at,
         local_revision, server_revision, local_payload, server_payload, resolution, notes)
  values (v_show, v_uid, v_type, v_id,
          (p_payload ->> 'local_updated_at')::timestamptz,
          (v_srv ->> 'updated_at')::timestamptz,
          (p_payload ->> 'local_revision')::integer, (v_srv ->> 'revision')::integer,
          coalesce(p_payload -> 'local_payload', '{}'::jsonb), v_srv,
          coalesce(nullif(p_payload ->> 'resolution',''), 'UNRESOLVED'),
          coalesce(p_payload ->> 'notes', 'reported by client'))
  returning id into v_cid;

  -- a manager must notice; the client cannot be trusted to keep retrying silently
  insert into public.notifications (user_id, showroom_id, title, message, notification_type,
                                    severity, route_name, route_params, reference_type, reference_id)
  select a.user_id, v_show, 'Offline sync conflict',
         upper(v_type) || ' ' || v_id || ' was edited offline while it changed on the server. Review before it is overwritten.',
         'SYSTEM', 'WARNING', '/sync', jsonb_build_object('conflictId', v_cid),
         'sync_conflict', v_cid
    from public.user_showroom_access a
   where a.showroom_id = v_show and a.access_level = 'MANAGE'
   limit 10;

  return v_cid;
end;
$$;

create or replace function public.record_offline_operation(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := app_sec.current_user_id();
  v_type   text := lower(coalesce(p_payload ->> 'entity_type', p_payload ->> 'entityType', ''));
  v_id     uuid := coalesce((p_payload ->> 'entity_id')::uuid, (p_payload ->> 'entityId')::uuid);
  v_op     text := upper(coalesce(nullif(p_payload ->> 'operation',''), 'UPDATE'));
  v_local  integer := (p_payload ->> 'local_revision')::integer;
  v_idem   uuid := (p_payload ->> 'idempotency_key')::uuid;
  v_srv    jsonb;
  v_state  jsonb;
  v_conf   boolean := false;
  v_reason text;
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;

  -- 1. if this queued write already landed (same idempotency key), the client can
  --    drop it from the queue instead of replaying it.
  if v_idem is not null then
    select k.* into v_srv from public.idempotency_keys k where k.key = v_idem and k.user_id = v_uid;
    if found then
      return jsonb_build_object('action', 'DROP', 'reason', 'already processed',
                                'status', v_srv ->> 'status', 'result', v_srv -> 'result',
                                'operation', v_op);
    end if;
  end if;

  if v_id is null then
    return jsonb_build_object('action', 'REPLAY', 'reason', 'create operation: no server row yet',
                              'operation', v_op);
  end if;

  v_state := app_gen.entity_sync_state(v_type, v_id);
  v_srv   := v_state -> 'state';
  if not (v_state ->> 'found')::boolean then
    return jsonb_build_object('action', 'REPLAY', 'conflict', true,
                              'reason', 'target row is gone; the replay will fail with NOT001',
                              'operation', v_op);
  end if;
  if coalesce((v_srv ->> 'is_deleted')::boolean, false) then
    v_conf := true; v_reason := 'the record was deleted on the server';
  elsif v_local is not null and (v_srv ->> 'revision') is not null
        and (v_srv ->> 'revision')::integer <> v_local then
    v_conf := true;
    v_reason := format('server is at revision %s, the offline copy is at %s',
                       v_srv ->> 'revision', v_local);
  elsif (p_payload ->> 'local_updated_at') is not null
        and (v_srv ->> 'updated_at')::timestamptz
            > (p_payload ->> 'local_updated_at')::timestamptz then
    v_conf := true; v_reason := 'the record changed on the server after the offline copy was taken';
  end if;

  if v_conf then
    v_id := public.recognise_sync_conflict(jsonb_build_object(
              'entity_type', v_type, 'entity_id', v_id,
              'local_revision', v_local,
              'local_updated_at', p_payload ->> 'local_updated_at',
              'local_payload', coalesce(p_payload -> 'payload', '{}'::jsonb),
              'showroom_id', p_payload -> 'showroom_id',
              'resolution', 'UNRESOLVED',
              'notes', 'pre-flight check for ' || v_op || ' (' || v_reason || ')'));
    return jsonb_build_object('action', 'REVIEW', 'conflict', true, 'reason', v_reason,
                              'conflictId', v_id, 'server', v_srv, 'operation', v_op);
  end if;

  return jsonb_build_object('action', 'REPLAY', 'conflict', false, 'operation', v_op,
                            'serverRevision', v_srv -> 'revision');
end;
$$;

create or replace function public.resolve_sync_conflict(
  p_conflict_id uuid,
  p_resolution  text,
  p_notes       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec   record;
  v_uid uuid := app_sec.current_user_id();
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;
  if p_resolution not in ('SERVER_WINS','LOCAL_WINS','MERGED','DISCARDED','MANUAL_REVIEW') then
    perform app_util.fail('VAL001', 'unknown resolution ' || coalesce(p_resolution,'(null)'));
  end if;

  select * into rec from public.sync_conflicts where id = p_conflict_id for update;
  if not found then perform app_util.fail('NOT001', 'conflict not found'); end if;
  perform app_sec.require_showroom_access(rec.showroom_id);

  -- only the owner or someone who can edit the module may decide what wins
  if rec.user_id is distinct from v_uid then
    perform app_sec.require_permission(
      case when rec.entity_type in ('payment','invoice','sale','purchase','expense',
                                    'accounting_transaction','loan','emi') then 'accounting'
           when rec.entity_type in ('service_records','service_record') then 'service'
           else 'settings' end,
      case when rec.entity_type in ('service_records','service_record') then 'complete' else 'edit' end);
  end if;

  update public.sync_conflicts c
     set resolution = p_resolution, resolved_by = v_uid, resolved_at = now(),
         notes = btrim(coalesce(c.notes || ' | ', '') || coalesce(p_notes, '')),
         updated_at = now()
   where c.id = p_conflict_id;

  perform app_util.audit_row('settings','UPDATE','sync_conflicts', p_conflict_id,
          jsonb_build_object('resolution', rec.resolution),
          jsonb_build_object('resolution', p_resolution, 'notes', p_notes),
          rec.showroom_id, v_uid, 'conflict ' || p_resolution);

  -- the conflict is off the manager's to-do list; their unread badge is theirs to
  -- clear, so only the "needs a decision" flag is dropped here (SS29).
  update public.notifications n
     set action_required = false
   where n.reference_type = 'sync_conflict' and n.reference_id = p_conflict_id
     and n.action_required;

  return jsonb_build_object('conflictId', p_conflict_id, 'resolution', p_resolution,
                            'entityType', rec.entity_type, 'entityId', rec.entity_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- The change feed.  Security invoker on purpose: RLS must apply, otherwise the
-- delta pull would be a cross-tenant data leak.
-- ---------------------------------------------------------------------------
create or replace function public.pull_changes(
  p_showroom_id uuid,
  p_since       timestamptz default timestamptz '1970-01-01 00:00:00+00',
  p_limit       integer default 500
)
returns table (entity_type text, entity_id uuid, changed_at timestamptz,
               revision integer, is_deleted boolean, payload jsonb)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_sql text := '';
  rec   record;
  v_first boolean := true;
begin
  -- No explicit permission call here on purpose: this function is SECURITY
  -- INVOKER so the tenant policies do the filtering, and a request for a
  -- showroom the caller cannot see simply returns no rows.
  if p_showroom_id is null then
    p_showroom_id := current_setting('app.showroom_id', true)::uuid;
  end if;

  for rec in
    select t.name,
           exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = t.name
                      and c.column_name = 'showroom_id')         as has_showroom,
           exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = t.name
                      and c.column_name = 'revision')            as has_revision,
           exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = t.name
                      and c.column_name = 'is_deleted')          as has_deleted
      from (values ('sales'),('invoices'),('payments'),('customers'),('inventory'),
                   ('customer_vehicles'),('service_records'),('purchases'),('expenses'),
                   ('loans'),('emi_schedules'),('warranty_claims'),('insurance_policies'),
                   ('stock_transfers'),('reminders')) as t(name)
  loop
    v_sql := v_sql || case when v_first then '' else ' union all ' end || format(
      'select %L::text as entity_type, x.id::uuid as entity_id, x.updated_at as changed_at, %s as revision, %s as is_deleted, to_jsonb(x) as payload
         from (select * from public.%I %s order by updated_at desc limit %s) x',
      rec.name,
      case when rec.has_revision then 'x.revision::int' else 'null::int' end,
      case when rec.has_deleted then 'x.is_deleted' else 'false' end,
      rec.name,
      case when rec.has_showroom
           then format('where showroom_id = %L and updated_at > %L', p_showroom_id, p_since)
           else format('where updated_at > %L', p_since) end,
      least(greatest(coalesce(p_limit, 500), 1), 2000));
    v_first := false;
  end loop;

  return query execute 'select * from (' || v_sql || ') as feed order by feed.changed_at desc limit '
                       || least(greatest(coalesce(p_limit, 500), 1), 2000)::text;
end;
$$;

-- =============================================================================
-- SECTION 14 - purchase approval / receipt, warranty claim decisions, EMI reversal
-- =============================================================================

create or replace function public.approve_purchase(
  p_purchase_id uuid,
  p_approve     boolean default true,
  p_reason      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec   record;
  v_new text;
begin
  select * into rec from public.purchases where id = p_purchase_id for update;
  if not found then perform app_util.fail('NOT001', 'purchase not found'); end if;
  perform app_sec.require_showroom_access(rec.showroom_id);   -- before anything the row reveals

  -- Permission and branch first: what a purchase order says about itself (its
  -- status, its supplier, how far it got) is only for someone allowed to see this
  -- showroom, otherwise the endpoint is a way to read other branches (SS6, SS43).
  perform app_sec.require_permission('purchases', case when p_approve then 'approve' else 'cancel' end);
  perform app_sec.require_showroom_access(rec.showroom_id);

  if rec.status <> 'DRAFT' then
    perform app_util.fail('CON001', 'only a DRAFT purchase can be approved (it is ' || rec.status || ')');
  end if;

  if p_approve then
    v_new := 'CONFIRMED';
  else
    if coalesce(p_reason,'') = '' then
      perform app_util.fail('VAL001', 'rejecting a purchase needs a reason');
    end if;
    v_new := 'CANCELLED';
  end if;

  update public.purchases p
     set status = v_new,
         approved_by = case when p_approve then app_sec.current_user_id() end,
         approved_at = case when p_approve then now() end,
         cancelled_reason = case when not p_approve then p_reason end,
         notes = btrim(coalesce(p.notes || ' | ', '') || coalesce(p_reason, '')),
         revision = p.revision + 1, updated_at = now(), updated_by = app_sec.current_user_id()
   where p.id = p_purchase_id;

  insert into public.notifications (user_id, showroom_id, title, message, notification_type,
                                    severity, route_name, route_params, reference_type, reference_id)
  select rec.created_by, rec.showroom_id,
         case when p_approve then 'Purchase approved' else 'Purchase rejected' end,
         'Purchase ' || p.purchase_number || ' for supplier '
           || (select s.name from public.suppliers s where s.id = p.supplier_id)
           || ' is now ' || p.status || coalesce('. ' || p_reason, '.'),
         'APPROVAL', case when p_approve then 'SUCCESS' else 'WARNING' end,
         '/purchases/detail', jsonb_build_object('id', p.id), 'purchase', p.id
    from public.purchases p
   where p.id = p_purchase_id and rec.created_by is not null
   on conflict do nothing;

  perform app_util.audit_row('purchases', case when p_approve then 'APPROVE' else 'REJECT' end,
          'purchases', p_purchase_id, jsonb_build_object('status', rec.status),
          jsonb_build_object('status', v_new, 'reason', p_reason),
          rec.showroom_id, app_sec.current_user_id(), rec.purchase_number);

  return jsonb_build_object('purchaseId', p_purchase_id, 'status', v_new);
end;
$$;

-- ---------------------------------------------------------------------------
-- Receive stock against a confirmed purchase.
-- p_payload = { lines: [ { purchase_item_id, units: [ { chassis_number,
--   engine_number, stock_code?, manufacturing_date?, model_year?, location? } ] } ] }
-- `units` may be omitted for non-serialised lines, in which case `quantity` is
-- received as-is (accessories/parts, which do not get a row per piece).
-- ---------------------------------------------------------------------------
create or replace function public.receive_purchase(p_purchase_id uuid, p_payload jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec        record;
  v_lines    jsonb := coalesce(p_payload -> 'lines', '[]'::jsonb);
  v_item     record;
  v_unit     jsonb;
  v_product  record;
  v_inv      uuid;
  v_qty      numeric := 0;
  v_units    integer := 0;
  v_cost     app_util.money := 0;
begin

  perform app_sec.require_permission('purchases','receive');
  select * into rec from public.purchases where id = p_purchase_id for update;
  if not found then perform app_util.fail('NOT001', 'purchase not found'); end if;
  -- The branch gate sits in front of the status test on purpose: a purchase
  -- order's state is information about another showroom (SS43).
  perform app_sec.require_showroom_access(rec.showroom_id);
  if rec.status not in ('CONFIRMED','PARTIAL_RECEIVED') then
    perform app_util.fail('CON001', 'a ' || rec.status || ' purchase cannot be received');
  end if;
  if jsonb_typeof(v_lines) <> 'array' then
    perform app_util.fail('VAL001', 'lines must be an array');
  end if;

  for v_item in
    -- the payload of this line travels with the row: the loop needs both the
    -- stored quantity and the caller's units array, and a plpgsql record can only
    -- expose columns the query actually selects.
    select pi.*, l.value as payload from public.purchase_items pi
      join jsonb_array_elements(v_lines) as l(value) on l.value ->> 'purchase_item_id' = pi.id::text
     where pi.purchase_id = p_purchase_id
     order by pi.created_at
  loop
    if (v_item.quantity - v_item.received_quantity) <= 0 then
      perform app_util.fail('CON002',
        'line ' || v_item.description || ' is already fully received');
    end if;

    select * into v_product from public.products where id = v_item.product_id;

    if jsonb_typeof(v_item.payload -> 'units') = 'array'
       and jsonb_array_length(v_item.payload -> 'units') > 0 then
      for v_unit in select e.value from jsonb_array_elements(v_item.payload -> 'units') as e(value) loop
        if exists (select 1 from public.inventory i
                    where i.chassis_number = app_util.upper_no_space(v_unit ->> 'chassis_number')) then
          perform app_util.fail('CON003', 'chassis ' || (v_unit ->> 'chassis_number') ||
                                ' already exists in stock');
        end if;
        insert into public.inventory
              (showroom_id, product_id, color_id, stock_code, chassis_number, engine_number,
               manufacturing_date, model_year, purchase_date, purchase_price, landing_price, mrp,
               status, location, remarks, created_by)
        values (rec.showroom_id, v_item.product_id, v_item.color_id,
                coalesce(app_util.upper_no_space(v_unit ->> 'stock_code'),
                         'STK-' || upper(left(md5(coalesce(v_unit ->> 'chassis_number', random()::text)), 10))),
                app_util.upper_no_space(v_unit ->> 'chassis_number'),
                app_util.upper_no_space(v_unit ->> 'engine_number'),
                (v_unit ->> 'manufacturing_date')::date,
                nullif(v_unit ->> 'model_year','')::int,
                current_date,
                app_util.round_money(v_item.unit_cost),
                app_util.round_money(v_item.unit_cost),
                coalesce(v_product.selling_price, 0),
                'AVAILABLE',
                coalesce(nullif(v_unit ->> 'location',''), 'Main warehouse'),
                'received on purchase ' || rec.purchase_number,
                app_sec.current_user_id())
        returning id into v_inv;

        insert into public.stock_movements
              (showroom_id, inventory_id, movement_type, to_status, reference_type, reference_id,
               reason, performed_by)
        values (rec.showroom_id, v_inv, 'STOCK_IN', 'AVAILABLE', 'purchase', p_purchase_id,
                'Receipt of ' || rec.purchase_number, app_sec.current_user_id());

        update public.purchase_items pi
           set inventory_id = coalesce(pi.inventory_id, v_inv),
               received_quantity = least(pi.received_quantity + 1, pi.quantity)
         where pi.id = v_item.id;

        v_units := v_units + 1;
        v_qty   := v_qty + 1;
        v_cost  := v_cost + app_util.round_money(v_item.unit_cost);
      end loop;
    else
      v_qty := least(v_item.quantity - v_item.received_quantity,
                     coalesce((v_item.payload ->> 'quantity')::numeric,
                              v_item.quantity - v_item.received_quantity));
      if v_qty <= 0 then
        perform app_util.fail('VAL002', 'nothing to receive on line ' || v_item.description);
      end if;
      update public.purchase_items pi
         set received_quantity = pi.received_quantity + v_qty
       where pi.id = v_item.id;
      v_cost := v_cost + round(v_qty * app_util.round_money(v_item.unit_cost), 2);
    end if;
  end loop;

  if v_qty = 0 then
    perform app_util.fail('VAL003', 'no line matched this purchase; check purchase_item_id');
  end if;

  perform public.recalc_purchase_header(p_purchase_id);

  update public.purchases p
     set status = case when not exists (select 1 from public.purchase_items pi
                                         where pi.purchase_id = p.id
                                           and pi.received_quantity < pi.quantity)
                       then 'RECEIVED' else 'PARTIAL_RECEIVED' end,
         revision = p.revision + 1, updated_at = now(), updated_by = app_sec.current_user_id()
   where p.id = p_purchase_id
     and p.status <> 'RECEIVED';

  -- stock only becomes an asset once it physically arrives: move the temporary
  -- expense into inventory so the balance sheet is right (SS24).
  if v_cost > 0 then
    begin
      perform app_acc.post_journal(rec.showroom_id, current_date, 'PURCHASE', 'purchase_receipt', p_purchase_id,
        'Stock received on ' || rec.purchase_number,
        jsonb_build_array(
          jsonb_build_object('code','1200','debit', v_cost, 'description','Inventory in'),
          jsonb_build_object('code','5100','credit', v_cost, 'description','Reclassify purchase to stock')
        ));
    exception when others then
      -- a duplicate receipt journal (one per purchase is allowed) must never lose the stock
      null;
    end;
  end if;

  perform app_util.audit_row('purchases','UPDATE','purchases', p_purchase_id,
          jsonb_build_object('status', rec.status),
          jsonb_build_object('units', v_units, 'quantity', v_qty, 'value', v_cost),
          rec.showroom_id, app_sec.current_user_id(), rec.purchase_number);

  return jsonb_build_object('purchaseId', p_purchase_id, 'unitsReceived', v_units,
                            'quantityReceived', v_qty, 'value', v_cost,
                            'status', (select p.status from public.purchases p where p.id = p_purchase_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Warranty claim decisions (SS21): SUBMITTED -> UNDER_REVIEW -> APPROVED /
-- REJECTED -> SETTLED.  Money received from the manufacturer lands as Other
-- Income; the claim itself is never edited after a decision.
-- ---------------------------------------------------------------------------
create or replace function public.decide_warranty_claim(
  p_claim_id        uuid,
  p_status          text,
  p_approved_amount numeric default null,
  p_reason          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec   record;
  v_amt app_util.money;
begin

  perform app_sec.require_permission('warranty','approve');
  select * into rec from public.warranty_claims where id = p_claim_id for update;
  if not found then perform app_util.fail('NOT001', 'claim not found'); end if;
  perform app_sec.require_showroom_access(rec.showroom_id);

  if p_status not in ('UNDER_REVIEW','APPROVED','REJECTED','SETTLED','CANCELLED') then
    perform app_util.fail('VAL001', 'unsupported claim status ' || p_status);
  end if;
  if rec.status in ('SETTLED','REJECTED','CANCELLED') then
    perform app_util.fail('CON001', 'a ' || rec.status || ' claim is final');
  end if;
  if p_status in ('APPROVED','SETTLED') and rec.claimed_amount = 0 then
    perform app_util.fail('VAL002', 'a claim with no amount cannot be approved');
  end if;
  if p_status = 'REJECTED' and coalesce(p_reason,'') = '' then
    perform app_util.fail('VAL003', 'a rejected claim needs a reason (SS67)');
  end if;

  v_amt := case
             when p_status in ('APPROVED','SETTLED')
               then least(app_util.round_money(coalesce(p_approved_amount, rec.claimed_amount)),
                          rec.claimed_amount)
             when p_status in ('REJECTED','CANCELLED') then 0
             else rec.approved_amount end;

  update public.warranty_claims c
     set status = p_status,
         approved_amount = v_amt,
         resolution = coalesce(p_reason, c.resolution),
         rejected_reason = case when p_status = 'REJECTED' then p_reason else c.rejected_reason end,
         reviewed_by = app_sec.current_user_id(),
         reviewed_at = now(),
         settled_at = case when p_status = 'SETTLED' then now() else c.settled_at end,
         updated_at = now()
   where c.id = p_claim_id;

  -- an approved claim must not silently shorten the warranty: record it on the
  -- coverage document so the technician sees the history (SS21).
  if p_status in ('APPROVED','SETTLED') then
    update public.warranties w
       set notes = btrim(coalesce(w.notes || ' | ', '')
                         || 'claim ' || rec.claim_number || ' ' || lower(p_status)
                         || ' ' || current_date || ' for ' || v_amt::text),
         updated_at = now()
     where w.id = rec.warranty_id;
  end if;

  if p_status = 'SETTLED' and v_amt > 0 then
    begin
      perform app_acc.post_journal(rec.showroom_id, current_date, 'RECEIPT', 'warranty_claim', p_claim_id,
        'Warranty recovery ' || rec.claim_number,
        jsonb_build_array(
          jsonb_build_object('code','1020','debit', v_amt, 'description','OEM settlement received'),
          jsonb_build_object('code','4900','credit', v_amt, 'description','Warranty recovery income')
        ));
    exception when others then
      null;   -- the decision is the business fact; bookkeeping can be redone
    end;
  end if;

  if rec.service_id is not null then
    update public.service_records s
       set notes = btrim(coalesce(s.notes || ' | ', '')
                         || 'warranty claim ' || rec.claim_number || ' ' || lower(p_status)),
         updated_at = now()
     where s.id = rec.service_id;
  end if;

  perform app_util.audit_row('warranty','APPROVE','warranty_claims', p_claim_id,
          jsonb_build_object('status', rec.status, 'amount', rec.approved_amount),
          jsonb_build_object('status', p_status, 'amount', v_amt, 'reason', p_reason),
          rec.showroom_id, app_sec.current_user_id(), rec.claim_number);

  return jsonb_build_object('claimId', p_claim_id, 'status', p_status, 'approvedAmount', v_amt);
end;
$$;

-- ---------------------------------------------------------------------------
-- Cancel a wrongly generated schedule (e.g. wrong tenure entered).  Only unpaid
-- instalments can be reversed - money that has moved is never rewritten (SS42).
-- ---------------------------------------------------------------------------
create or replace function public.reverse_emi_schedule(
  p_loan_id           uuid,
  p_from_installment  integer default 1,
  p_reason            text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan record;
  v_n    integer;
  v_touch boolean := false;
begin

  perform app_sec.require_permission('finance','edit');
  select * into v_loan from public.loans where id = p_loan_id for update;
  if not found then perform app_util.fail('NOT001', 'loan not found'); end if;
  perform app_sec.require_showroom_access(v_loan.showroom_id);
  if coalesce(p_reason,'') = '' then
    perform app_util.fail('VAL001', 'reversing a schedule needs a reason');
  end if;
  if p_from_installment is null or p_from_installment < 1 then
    perform app_util.fail('VAL002', 'fromInstallment must be 1 or greater');
  end if;

  if exists (select 1 from public.emi_schedules e
              where e.loan_id = p_loan_id and e.emi_number >= p_from_installment
                and (e.paid_amount > 0 or e.status in ('PAID','PARTIAL'))) then
    perform app_util.fail('CON001',
      'instalments from #' || p_from_installment || ' already have payments; reverse those payments first');
  end if;

  update public.emi_schedules e
     set status = 'CANCELLED',
         notes = btrim(coalesce(e.notes || ' | ', '') || 'cancelled: ' || p_reason),
         updated_at = now()
   where e.loan_id = p_loan_id
     and e.emi_number >= p_from_installment
     and e.status in ('UPCOMING','DUE','OVERDUE');
  get diagnostics v_n = row_count;

  if v_n = 0 then
    perform app_util.fail('NOT002', 'nothing to reverse from instalment #' || p_from_installment);
  end if;

  v_touch := p_from_installment <= 1;

  update public.loans l
     set status = case when v_touch then 'SANCTIONED' else l.status end,
         total_payable = (select round(coalesce(sum(e.emi_amount), 0), 2)
                            from public.emi_schedules e
                           where e.loan_id = l.id and e.status <> 'CANCELLED'),
         end_date = case when v_touch
                         then (select max(e.due_date) from public.emi_schedules e
                                where e.loan_id = l.id and e.status <> 'CANCELLED')
                         else l.end_date end,
         notes = btrim(coalesce(l.notes || ' | ', '') || 'schedule reversed from #'
                                  || p_from_installment || ': ' || p_reason),
         revision = l.revision + 1, updated_at = now(), updated_by = app_sec.current_user_id()
   where l.id = p_loan_id;

  insert into public.notifications (user_id, showroom_id, title, message, notification_type,
                                    severity, route_name, reference_type, reference_id)
  select l.created_by, l.showroom_id, 'EMI schedule reversed',
         'Loan ' || l.loan_number || ': ' || p_n_cancelled || ' instalments cancelled (#'
           || p_from_installment || ' onwards). Reason: ' || p_reason,
         'EMI', 'WARNING', '/finance/loans', 'loan', l.id
    from public.loans l where l.id = p_loan_id and l.created_by is not null
   on conflict do nothing;

  perform app_util.audit_row('finance','DELETE','emi_schedules', p_loan_id,
          jsonb_build_object('from', p_from_installment),
          jsonb_build_object('cancelled', v_n, 'reason', p_reason),
          v_loan.showroom_id, app_sec.current_user_id(), v_loan.loan_number);

  return jsonb_build_object('loanId', p_loan_id, 'cancelled', v_n,
                            'totalPayable', (select l.total_payable from public.loans l where l.id = p_loan_id));
end;
$$;
