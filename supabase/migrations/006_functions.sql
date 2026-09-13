-- 006_functions.sql
-- Server-side business logic. Every money-moving operation is a single
-- transactional function so the Flutter client can never leave the database
-- half-updated. Parameter names match the Dart call sites exactly
-- (grep `supabase.rpc(` in lib/features/*/repositories).

-- ------------------------------------------------- authorization helpers

create or replace function public.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.users where auth_user_id = auth.uid();
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
     where ur.user_id = public.current_user_id()
       and r.name = 'SUPER ADMIN'
  );
$$;

create or replace function public.can_access_showroom(p_showroom_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
      or exists (
        select 1
          from public.users u
         where u.id = public.current_user_id()
           and u.showroom_id = p_showroom_id
      );
$$;

-- Mirrors lib/common/services/permission_service.dart.
create or replace function public.has_permission(p_module text, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin()
      or exists (
        select 1
          from public.user_roles ur
          join public.role_permissions rp on rp.role_id = ur.role_id
          join public.permissions p on p.id = rp.permission_id
         where ur.user_id = public.current_user_id()
           and p.module = p_module
           and p.action = p_action
      );
$$;

-- ------------------------------------------------------ document numbers

create table if not exists public.document_sequences (
  sequence_key  text primary key,
  last_value    bigint not null default 0,
  updated_at    timestamptz not null default now()
);

-- Per-showroom, per-entity sequential numbers (INV-2026-0001).
create or replace function public.next_document_number(
  p_showroom_id uuid,
  p_prefix text
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  seq      bigint;
  key_name text := p_prefix || ':' || coalesce(p_showroom_id::text, 'global');
begin
  insert into public.document_sequences (sequence_key, last_value)
  values (key_name, 1)
  on conflict (sequence_key)
  do update set last_value = public.document_sequences.last_value + 1
  returning last_value into seq;

  return format('%s-%s-%s',
                upper(p_prefix),
                to_char(now(), 'YYYY'),
                lpad(seq::text, 4, '0'));
end;
$$;

-- ------------------------------------------------------------------- EMI

create or replace function public.calculate_emi(
  p_principal numeric,
  p_annual_rate numeric,
  p_tenure_months integer
)
returns numeric
language plpgsql
immutable
as $$
declare
  monthly_rate numeric := p_annual_rate / 12.0 / 100.0;
begin
  if p_principal <= 0 or p_tenure_months <= 0 then
    return 0;
  end if;
  if monthly_rate = 0 then
    return round(p_principal / p_tenure_months, 2);
  end if;
  return round(
    p_principal * monthly_rate * power(1 + monthly_rate, p_tenure_months)
      / (power(1 + monthly_rate, p_tenure_months) - 1),
    2
  );
end;
$$;

create or replace function public.generate_emi_schedule(
  p_loan_id uuid,
  p_principal numeric,
  p_annual_rate numeric,
  p_tenure_months integer,
  p_start_date date default current_date
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  monthly_rate numeric := coalesce(p_annual_rate, 0) / 12.0 / 100.0;
  emi          numeric := public.calculate_emi(p_principal, p_annual_rate,
                                               p_tenure_months);
  balance      numeric := p_principal;
  interest     numeric;
  principal    numeric;
  i            integer;
begin
  delete from public.emi_schedules where loan_id = p_loan_id;

  for i in 1 .. p_tenure_months loop
    interest := round(balance * monthly_rate, 2);
    if i = p_tenure_months then
      principal := balance;                     -- clear rounding residue
    else
      principal := emi - interest;
    end if;
    balance := greatest(balance - principal, 0);

    insert into public.emi_schedules
      (loan_id, installment_no, due_date, principal_amount, interest_amount,
       emi_amount, balance_after, status)
    values
      (p_loan_id, i,
       (p_start_date + (i || ' months')::interval)::date,
       principal, interest, principal + interest, balance, 'pending');
  end loop;

  return p_tenure_months;
end;
$$;

-- ------------------------------------------------------------------ sale

-- Atomically: validate -> sale + lines -> mark inventory sold -> vehicle ->
-- warranty -> free services -> optional loan + EMI schedule.
create or replace function public.create_sale_transaction(
  customer_id uuid,
  showroom_id uuid,
  lines jsonb,
  sale_type text default 'retail',
  payment_mode text default 'cash',
  is_emi boolean default false,
  discount_amount numeric default 0,
  tax_rate numeric default 18,
  sale_date date default current_date,
  emi jsonb default null,
  delivery jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  line           jsonb;
  sale_id        uuid;
  new_vehicle_id uuid;
  warranty_id    uuid;
  line_no       integer := 0;
  subtotal      numeric := 0;
  line_total    numeric;
  line_tax      numeric;
  grand_total   numeric;
  product_row   public.products%rowtype;
  plan_row      public.free_service_plans%rowtype;
  inv_row       public.inventory%rowtype;
begin
  if not public.can_access_showroom(showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom %', showroom_id
      using errcode = '42501';
  end if;
  if not public.has_permission('sales', 'create') then
    raise exception 'FORBIDDEN: sales.create required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.customers c
                  where c.id = customer_id and c.is_deleted = false) then
    raise exception 'VALIDATION: customer % not found', customer_id
      using errcode = '22023';
  end if;
  if lines is null or jsonb_array_length(lines) = 0 then
    raise exception 'VALIDATION: at least one sale line is required'
      using errcode = '22023';
  end if;

  insert into public.sales
    (showroom_id, customer_id, sale_number, sale_type, payment_mode, is_emi,
     discount_amount, sale_date, status, created_by)
  values
    (showroom_id, customer_id,
     public.next_document_number(showroom_id, 'SAL'),
     sale_type, payment_mode, is_emi,
     coalesce(discount_amount, 0), coalesce(sale_date, current_date),
     'completed', public.current_user_id())
  returning id into sale_id;

  for line in select * from jsonb_array_elements(lines) loop
    line_no := line_no + 1;
    line_total := coalesce((line ->> 'qty')::numeric, 1)
                * coalesce((line ->> 'unit_price')::numeric, 0);
    line_tax := round(line_total * coalesce(tax_rate, 0) / 100.0, 2);
    subtotal := subtotal + line_total;

    insert into public.sale_items
      (sale_id, line_number, item_type, product_id, inventory_id, name,
       description, chassis_number, qty, unit_price, discount_amount,
       tax_amount, total_amount)
    values
      (sale_id, line_no,
       coalesce(line ->> 'item_type', 'vehicle'),
       nullif(line ->> 'product_id', '')::uuid,
       nullif(line ->> 'inventory_id', '')::uuid,
       coalesce(line ->> 'name', ''),
       coalesce(line ->> 'description', ''),
       line ->> 'chassis_number',
       coalesce((line ->> 'qty')::numeric, 1),
       coalesce((line ->> 'unit_price')::numeric, 0),
       coalesce((line ->> 'discount_amount')::numeric, 0),
       line_tax,
       line_total + line_tax);

    -- Reserve/sell the physical unit and create the customer's vehicle.
    if (line ->> 'inventory_id') is not null then
      select * into inv_row from public.inventory i
       where i.id = (line ->> 'inventory_id')::uuid
       for update;

      if not found then
        raise exception 'VALIDATION: inventory unit not found'
          using errcode = '22023';
      end if;
      if inv_row.status not in ('available', 'reserved') then
        raise exception 'CONFLICT: unit % is %', inv_row.chassis_number,
                        inv_row.status
          using errcode = '40001';
      end if;

      update public.inventory
         set status = 'sold', updated_at = now()
       where id = inv_row.id;

      insert into public.customer_vehicles
        (customer_id, showroom_id, inventory_id, product_id,
         registration_number, chassis_number, engine_number,
         purchase_date, delivery_date, warranty_start, warranty_end, status)
      values
        (customer_id, showroom_id, inv_row.id, inv_row.product_id,
         delivery ->> 'registration_number',
         inv_row.chassis_number, inv_row.engine_number,
         coalesce(sale_date, current_date),
         nullif(delivery ->> 'delivery_date', '')::date,
         coalesce(sale_date, current_date),
         null,
         'active')
      returning id into new_vehicle_id;

      -- Manufacturer warranty + free service schedule for the sold unit.
      select * into product_row from public.products p
       where p.id = inv_row.product_id;

      if found and coalesce(product_row.warranty_months, 0) > 0 then
        insert into public.warranties
          (showroom_id, vehicle_id, sale_id, warranty_number, type,
           start_date, end_date, activated_at, status)
        values
          (showroom_id, new_vehicle_id, sale_id,
           public.next_document_number(showroom_id, 'WTY'),
           'manufacturer',
           coalesce(sale_date, current_date),
           (coalesce(sale_date, current_date)
             + (product_row.warranty_months || ' months')::interval)::date,
           now(), 'active')
        returning id into warranty_id;

        update public.customer_vehicles
           set warranty_end = (coalesce(sale_date, current_date)
                 + (product_row.warranty_months || ' months')::interval)::date,
               updated_at = now()
         where id = new_vehicle_id;
      end if;

      for plan_row in
        select * from public.free_service_plans f
         where f.product_id = inv_row.product_id and f.is_active
         order by f.service_number
      loop
        insert into public.free_service_grants
          (vehicle_id, plan_id, showroom_id, grant_number, plan_name,
           service_number, start_date, end_date, mileage_limit, status)
        values
          (new_vehicle_id, plan_row.id, showroom_id,
           public.next_document_number(showroom_id, 'FSG'),
           'Free service #' || plan_row.service_number,
           plan_row.service_number,
           coalesce(sale_date, current_date),
           (coalesce(sale_date, current_date)
             + (plan_row.service_days || ' days')::interval)::date,
           plan_row.service_km, 'active');
      end loop;
    end if;
  end loop;

  grand_total := round(subtotal - coalesce(discount_amount, 0)
                       + round(subtotal * coalesce(tax_rate, 0) / 100.0, 2), 2);

  update public.sales
     set subtotal_amount = round(subtotal, 2),
         tax_amount      = round(subtotal * coalesce(tax_rate, 0) / 100.0, 2),
         total_amount    = grand_total,
         paid_amount     = 0,
         balance_amount  = grand_total,
         vehicle_id      = new_vehicle_id,
         updated_at      = now()
   where id = sale_id;

  -- EMI: create the loan + schedule; the down payment arrives through
  -- record_payment().
  if is_emi and emi is not null then
    perform public._create_loan_for_sale(
      p_sale_id        => sale_id,
      p_showroom_id    => showroom_id,
      p_customer_id    => customer_id,
      p_vehicle_id     => new_vehicle_id,
      p_down_payment   => coalesce((emi ->> 'down_payment')::numeric, 0),
      p_loan_amount    => coalesce((emi ->> 'loan_amount')::numeric, 0),
      p_interest_rate  => coalesce((emi ->> 'interest_rate')::numeric, 0),
      p_tenure_months  => coalesce((emi ->> 'tenure_months')::integer, 12),
      p_company_id     => nullif(emi ->> 'finance_company_id', '')::uuid
    );
  end if;

  return jsonb_build_object(
    'id', sale_id,
    'sale_number', (select sale_number from public.sales where id = sale_id),
    'total_amount', grand_total,
    'vehicle_id', new_vehicle_id
  );
end;
$$;

-- Loan + EMI schedule for a financed sale (internal).
create or replace function public._create_loan_for_sale(
  p_sale_id uuid,
  p_showroom_id uuid,
  p_customer_id uuid,
  p_vehicle_id uuid,
  p_down_payment numeric,
  p_loan_amount numeric,
  p_interest_rate numeric,
  p_tenure_months integer,
  p_company_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  loan_id uuid;
  emi     numeric;
  total_interest numeric;
begin
  if p_loan_amount <= 0 then
    raise exception 'VALIDATION: loan amount must be positive'
      using errcode = '22023';
  end if;

  emi := public.calculate_emi(p_loan_amount, p_interest_rate, p_tenure_months);
  total_interest := round((emi * p_tenure_months) - p_loan_amount, 2);

  insert into public.loans
    (showroom_id, customer_id, vehicle_id, sale_id, finance_company_id,
     loan_number, loan_amount, down_payment, interest_rate, tenure_months,
     monthly_emi, total_interest, outstanding_amount, start_date, end_date,
     status)
  values
    (p_showroom_id, p_customer_id, p_vehicle_id, p_sale_id, p_company_id,
     public.next_document_number(p_showroom_id, 'LN'),
     p_loan_amount, p_down_payment, p_interest_rate, p_tenure_months,
     emi, total_interest, p_loan_amount, current_date,
     (current_date + (p_tenure_months || ' months')::interval)::date,
     'active')
  returning id into loan_id;

  perform public.generate_emi_schedule(
    loan_id, p_loan_amount, p_interest_rate, p_tenure_months, current_date
  );
  return loan_id;
end;
$$;

-- Cancellation restores stock and voids the derived documents.
create or replace function public.cancel_sale(p_sale_id uuid, p_reason text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  sale_row public.sales%rowtype;
begin
  select * into sale_row from public.sales s
   where s.id = p_sale_id for update;
  if not found then
    raise exception 'NOT_FOUND: sale %', p_sale_id using errcode = 'P0002';
  end if;
  if not public.has_permission('sales', 'cancel') then
    raise exception 'FORBIDDEN: sales.cancel required' using errcode = '42501';
  end if;
  if sale_row.status = 'cancelled' then
    raise exception 'CONFLICT: sale is already cancelled' using errcode = '40001';
  end if;
  if sale_row.paid_amount > 0 then
    raise exception 'CONFLICT: refund the % received before cancelling',
                    sale_row.paid_amount
      using errcode = '40001';
  end if;

  update public.inventory i
     set status = 'in_stock', updated_at = now()
    from public.sale_items si
   where si.sale_id = p_sale_id
     and si.inventory_id is not null
     and i.id = si.inventory_id;

  update public.customer_vehicles
     set status = 'sold', updated_at = now()
   where id = sale_row.vehicle_id;

  update public.warranties
     set status = 'cancelled', updated_at = now()
   where sale_id = p_sale_id;

  update public.free_service_grants
     set status = 'cancelled'
   where vehicle_id = sale_row.vehicle_id;

  update public.invoices
     set status = 'void', void_reason = p_reason, voided_at = now(),
         updated_at = now()
   where sale_id = p_sale_id and status <> 'void';

  update public.sales
     set status = 'cancelled', cancel_reason = p_reason, updated_at = now()
   where id = p_sale_id;

  return jsonb_build_object('id', p_sale_id, 'status', 'cancelled');
end;
$$;

-- ---------------------------------------------------------------- invoice

create or replace function public.create_invoice(
  p_sale_id uuid,
  p_invoice_date date default current_date,
  p_tax_rate numeric default 18,
  p_discount_amount numeric default 0,
  p_invoice_number text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  sale_row   public.sales%rowtype;
  invoice_id uuid;
  number     text;
begin
  select * into sale_row from public.sales s where s.id = p_sale_id;
  if not found then
    raise exception 'NOT_FOUND: sale %', p_sale_id using errcode = 'P0002';
  end if;
  if not public.can_access_showroom(sale_row.showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;
  if not public.has_permission('billing', 'create') then
    raise exception 'FORBIDDEN: billing.create required' using errcode = '42501';
  end if;

  number := coalesce(p_invoice_number,
                     public.next_document_number(sale_row.showroom_id, 'INV'));

  insert into public.invoices
    (showroom_id, customer_id, sale_id, invoice_number, invoice_type,
     invoice_date, due_date, subtotal_amount, discount_amount, tax_amount,
     total_amount, paid_amount, outstanding_amount, payment_mode, status,
     created_by)
  values
    (sale_row.showroom_id, sale_row.customer_id, sale_row.id, number, 'sale',
     coalesce(p_invoice_date, current_date),
     coalesce(p_invoice_date, current_date) + 15,
     sale_row.subtotal_amount, sale_row.discount_amount, sale_row.tax_amount,
     sale_row.total_amount, sale_row.paid_amount, sale_row.balance_amount,
     sale_row.payment_mode,
     case when sale_row.balance_amount <= 0 then 'paid' else 'unpaid' end,
     public.current_user_id())
  returning id into invoice_id;

  insert into public.invoice_items
    (invoice_id, line_number, item_type, product_id, description, qty,
     unit_price, discount_amount, tax_rate, tax_amount, total_amount)
  select invoice_id, si.line_number, si.item_type, si.product_id,
         case when si.name <> '' then si.name else si.description end,
         si.qty, si.unit_price, si.discount_amount, coalesce(p_tax_rate, 0),
         si.tax_amount, si.total_amount
    from public.sale_items si
   where si.sale_id = p_sale_id;

  return (select to_jsonb(i) from public.invoices i where i.id = invoice_id);
end;
$$;

-- --------------------------------------------------------------- payments

create or replace function public.record_payment(
  p_amount numeric,
  p_payment_mode text,
  p_invoice_id uuid default null,
  p_payment_date date default current_date,
  p_customer_id uuid default null,
  p_sale_id uuid default null,
  p_reference_number text default null,
  p_is_down_payment boolean default false,
  p_notes text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  payment_id  uuid;
  invoice_row public.invoices%rowtype;
  sale_row    public.sales%rowtype;
  room_id     uuid;
  cust_id     uuid := p_customer_id;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'VALIDATION: amount must be positive' using errcode = '22023';
  end if;

  if p_invoice_id is not null then
    select * into invoice_row from public.invoices i
     where i.id = p_invoice_id for update;
    if not found then
      raise exception 'NOT_FOUND: invoice %', p_invoice_id using errcode = 'P0002';
    end if;
    room_id := invoice_row.showroom_id;
    cust_id := coalesce(cust_id, invoice_row.customer_id);
  elsif p_sale_id is not null then
    select * into sale_row from public.sales s
     where s.id = p_sale_id for update;
    if not found then
      raise exception 'NOT_FOUND: sale %', p_sale_id using errcode = 'P0002';
    end if;
    room_id := sale_row.showroom_id;
    cust_id := coalesce(cust_id, sale_row.customer_id);
  else
    raise exception 'VALIDATION: invoice_id or sale_id is required'
      using errcode = '22023';
  end if;

  if not public.can_access_showroom(room_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;
  if not public.has_permission('payments', 'create') then
    raise exception 'FORBIDDEN: payments.create required' using errcode = '42501';
  end if;
  if p_invoice_id is not null and p_amount > invoice_row.outstanding_amount then
    raise exception 'VALIDATION: % exceeds the outstanding balance %',
                    p_amount, invoice_row.outstanding_amount
      using errcode = '22023';
  end if;

  insert into public.payments
    (showroom_id, customer_id, invoice_id, sale_id, payment_number,
     payment_date, amount, payment_mode, reference_number, status,
     is_down_payment, is_emi, notes, received_by)
  values
    (room_id, cust_id, p_invoice_id, p_sale_id,
     public.next_document_number(room_id, 'PAY'),
     coalesce(p_payment_date, current_date), p_amount,
     coalesce(p_payment_mode, 'cash'), p_reference_number, 'completed',
     coalesce(p_is_down_payment, false),
     coalesce(p_payment_mode, '') = 'emi',
     coalesce(p_notes, ''), public.current_user_id())
  returning id into payment_id;

  if p_invoice_id is not null then
    update public.invoices
       set paid_amount        = paid_amount + p_amount,
           outstanding_amount = total_amount - (paid_amount + p_amount),
           status = case
                      when total_amount - (paid_amount + p_amount) <= 0
                        then 'paid'
                      when paid_amount + p_amount > 0 then 'partial'
                      else 'unpaid'
                    end,
           updated_at = now()
     where id = p_invoice_id;
  end if;

  if p_sale_id is not null then
    update public.sales
       set paid_amount    = paid_amount + p_amount,
           balance_amount = total_amount - (paid_amount + p_amount),
           updated_at     = now()
     where id = p_sale_id;
  end if;

  return (select to_jsonb(p) from public.payments p where p.id = payment_id);
end;
$$;

create or replace function public.refund_payment(
  p_payment_id uuid,
  p_reason text,
  p_reference_number text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  pay_row public.payments%rowtype;
begin
  select * into pay_row from public.payments p
   where p.id = p_payment_id for update;
  if not found then
    raise exception 'NOT_FOUND: payment %', p_payment_id using errcode = 'P0002';
  end if;
  if not public.has_permission('payments', 'cancel') then
    raise exception 'FORBIDDEN: payments.cancel required' using errcode = '42501';
  end if;
  if pay_row.is_refunded then
    raise exception 'CONFLICT: payment already refunded' using errcode = '40001';
  end if;

  update public.payments
     set is_refunded = true, refund_reason = p_reason, refunded_at = now(),
         reference_number = coalesce(p_reference_number, reference_number),
         status = 'refunded', updated_at = now()
   where id = p_payment_id;

  if pay_row.invoice_id is not null then
    update public.invoices
       set paid_amount = greatest(paid_amount - pay_row.amount, 0),
           outstanding_amount = total_amount - greatest(paid_amount - pay_row.amount, 0),
           status = case
                      when greatest(paid_amount - pay_row.amount, 0) <= 0
                        then 'unpaid'
                      else 'partial'
                    end,
           updated_at = now()
     where id = pay_row.invoice_id;
  end if;

  if pay_row.sale_id is not null then
    update public.sales
       set paid_amount = greatest(paid_amount - pay_row.amount, 0),
           balance_amount = total_amount - greatest(paid_amount - pay_row.amount, 0),
           updated_at = now()
     where id = pay_row.sale_id;
  end if;

  return (select to_jsonb(p) from public.payments p where p.id = p_payment_id);
end;
$$;

-- -------------------------------------------------------------------- EMI

create or replace function public.pay_emi(
  p_loan_id uuid,
  p_installment_no integer,
  p_payment_mode text,
  p_payment_date date default current_date,
  p_reference_number text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  loan_row public.loans%rowtype;
  emi_row  public.emi_schedules%rowtype;
  pay_id   uuid;
  amount   numeric;
begin
  select * into loan_row from public.loans l
   where l.id = p_loan_id for update;
  if not found then
    raise exception 'NOT_FOUND: loan %', p_loan_id using errcode = 'P0002';
  end if;
  if not public.has_permission('emi', 'payment') then
    raise exception 'FORBIDDEN: emi.payment required' using errcode = '42501';
  end if;

  select * into emi_row from public.emi_schedules e
   where e.loan_id = p_loan_id and e.installment_no = p_installment_no
   for update;
  if not found then
    raise exception 'NOT_FOUND: installment % of loan %',
                    p_installment_no, p_loan_id
      using errcode = 'P0002';
  end if;
  if emi_row.status = 'paid' then
    raise exception 'CONFLICT: installment % is already paid', p_installment_no
      using errcode = '40001';
  end if;

  amount := emi_row.emi_amount - coalesce(emi_row.paid_amount, 0);

  insert into public.payments
    (showroom_id, customer_id, loan_id, emi_installment_no, payment_number,
     payment_date, amount, payment_mode, reference_number, status, is_emi,
     notes, received_by)
  values
    (loan_row.showroom_id, loan_row.customer_id, p_loan_id, p_installment_no,
     public.next_document_number(loan_row.showroom_id, 'PAY'),
     coalesce(p_payment_date, current_date), amount,
     coalesce(p_payment_mode, 'cash'), p_reference_number, 'completed', true,
     coalesce(p_notes, ''), public.current_user_id())
  returning id into pay_id;

  update public.emi_schedules
     set paid_amount = emi_amount,
         balance_after = greatest(balance_after, 0),
         paid_at = coalesce(p_payment_date, current_date),
         status = 'paid',
         updated_at = now()
   where id = emi_row.id;

  update public.loans
     set outstanding_amount = greatest(outstanding_amount - emi_row.principal_amount, 0),
         status = case
                    when not exists (
                      select 1 from public.emi_schedules e
                       where e.loan_id = p_loan_id and e.status <> 'paid'
                    ) then 'closed'
                    else 'active'
                  end,
         closed_at = case
                       when not exists (
                         select 1 from public.emi_schedules e
                          where e.loan_id = p_loan_id and e.status <> 'paid'
                       ) then now()
                       else closed_at
                     end,
         updated_at = now()
   where id = p_loan_id;

  update public.reminders
     set status = 'completed', completed_at = now(), updated_at = now()
   where loan_id = p_loan_id
     and type = 'emi_due'
     and status = 'pending'
     and (reference_id = emi_row.id
          or reminder_date <= emi_row.due_date);

  return jsonb_build_object(
    'id', pay_id,
    'installment_no', p_installment_no,
    'amount', amount,
    'loan_status', (select status from public.loans where id = p_loan_id)
  );
end;
$$;

-- -------------------------------------------------------------- inventory

-- Bulk transfer between showrooms. Returns one row per moved unit so the
-- offline queue can reconcile local ids.
create or replace function public.transfer_inventory(p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  target_room uuid := nullif(p_payload ->> 'to_showroom_id', '')::uuid;
  moved_on    date := coalesce(
                       nullif(p_payload ->> 'transfer_date', '')::date,
                       current_date);
  note        text := coalesce(p_payload ->> 'notes', '');
  unit_id     uuid;
  unit        public.inventory%rowtype;
  result      jsonb := '[]'::jsonb;
begin
  if target_room is null then
    raise exception 'VALIDATION: to_showroom_id is required' using errcode = '22023';
  end if;
  if not public.has_permission('inventory', 'transfer') then
    raise exception 'FORBIDDEN: inventory.transfer required' using errcode = '42501';
  end if;

  for unit_id in
    select jsonb_array_elements_text(p_payload -> 'inventory_ids')::uuid
  loop
    select * into unit from public.inventory i where i.id = unit_id for update;
    if not found then
      raise exception 'NOT_FOUND: inventory %', unit_id using errcode = 'P0002';
    end if;
    if unit.status not in ('available', 'demo') then
      raise exception 'CONFLICT: unit % is % and cannot be transferred',
                      unit.chassis_number, unit.status
        using errcode = '40001';
    end if;
    if not public.can_access_showroom(unit.showroom_id) then
      raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
    end if;

    insert into public.audit_logs
      (showroom_id, user_id, user_name, module, action, entity_type, entity_id,
       old_values, new_values, notes)
    values
      (unit.showroom_id, public.current_user_id(),
       coalesce((select name from public.users where id = public.current_user_id()), ''),
       'inventory', 'transfer', 'inventory', unit.id,
       jsonb_build_object('showroom_id', unit.showroom_id),
       jsonb_build_object('showroom_id', target_room),
       note);

    update public.inventory
       set showroom_id = target_room,
           status = 'available',
           location = coalesce(nullif(p_payload ->> 'location', ''), location),
           updated_at = now()
     where id = unit_id;

    insert into public.stock_transfers
      (from_showroom_id, to_showroom_id, transfer_date, unit_count, status,
       notes, created_by)
    values
      (unit.showroom_id, target_room, moved_on, 1, 'completed', note,
       public.current_user_id());

    insert into public.stock_history
      (inventory_id, showroom_id, action, from_status, to_status, notes,
       created_by)
    values
      (unit_id, target_room, 'transfer', unit.status, 'available', note,
       public.current_user_id());

    result := result || jsonb_build_object(
      'id', unit_id,
      'from_showroom_id', unit.showroom_id,
      'to_showroom_id', target_room,
      'transfer_date', moved_on
    );
  end loop;

  return result;
end;
$$;

-- Status/location correction with a mandatory reason (audit trail).
create or replace function public.adjust_stock(p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  unit_id    uuid := nullif(p_payload ->> 'inventory_id', '')::uuid;
  new_status text := nullif(p_payload ->> 'new_status', '');
  reason     text := coalesce(p_payload ->> 'reason', '');
  unit       public.inventory%rowtype;
begin
  if unit_id is null then
    raise exception 'VALIDATION: inventory_id is required' using errcode = '22023';
  end if;
  if reason = '' then
    raise exception 'VALIDATION: a reason is required for stock adjustments'
      using errcode = '22023';
  end if;
  if not public.has_permission('inventory', 'adjust') then
    raise exception 'FORBIDDEN: inventory.adjust required' using errcode = '42501';
  end if;

  select * into unit from public.inventory i where i.id = unit_id for update;
  if not found then
    raise exception 'NOT_FOUND: inventory %', unit_id using errcode = 'P0002';
  end if;
  if unit.status = 'sold' then
    raise exception 'CONFLICT: sold units cannot be adjusted' using errcode = '40001';
  end if;

  insert into public.audit_logs
    (showroom_id, user_id, user_name, module, action, entity_type, entity_id,
     old_values, new_values, notes)
  values
    (unit.showroom_id, public.current_user_id(),
     coalesce((select name from public.users where id = public.current_user_id()), ''),
     'inventory', 'adjust', 'inventory', unit.id,
     jsonb_build_object('status', unit.status, 'location', unit.location),
     jsonb_build_object('status', coalesce(new_status, unit.status),
                        'location', coalesce(nullif(p_payload ->> 'location', ''),
                                              unit.location)),
     reason);

  update public.inventory
     set status   = coalesce(new_status, status),
         location = coalesce(nullif(p_payload ->> 'location', ''), location),
         updated_at = now()
   where id = unit_id;

  insert into public.stock_history
    (inventory_id, showroom_id, action, from_status, to_status, notes,
     created_by)
  values
    (unit_id, unit.showroom_id, 'adjust', unit.status,
     coalesce(new_status, unit.status), reason, public.current_user_id());

  return jsonb_build_array(jsonb_build_object(
    'id', unit_id,
    'from_status', unit.status,
    'to_status', coalesce(new_status, unit.status),
    'reason', reason
  ));
end;
$$;

-- ---------------------------------------------------------------- service

create or replace function public.open_service_job(
  p_vehicle_id uuid,
  p_customer_id uuid,
  p_showroom_id uuid,
  p_job_type text default 'paid',
  p_odometer_in numeric default 0,
  p_problem_description text default '',
  p_service_date date default current_date,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  service_id uuid;
  line       jsonb;
  line_no    integer := 0;
  subtotal   numeric := 0;
  line_total numeric;
begin
  if not public.can_access_showroom(p_showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;
  if not public.has_permission('service', 'create') then
    raise exception 'FORBIDDEN: service.create required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.customer_vehicles v
                  where v.id = p_vehicle_id) then
    raise exception 'NOT_FOUND: vehicle %', p_vehicle_id using errcode = 'P0002';
  end if;

  insert into public.service_records
    (showroom_id, customer_id, vehicle_id, service_number, job_type,
     booking_date, service_date, odometer_in, status, problem_description,
     service_advisor_id)
  values
    (p_showroom_id, p_customer_id, p_vehicle_id,
     public.next_document_number(p_showroom_id, 'JOB'),
     coalesce(p_job_type, 'paid'), current_date,
     coalesce(p_service_date, current_date), coalesce(p_odometer_in, 0),
     'open', coalesce(p_problem_description, ''), public.current_user_id())
  returning id into service_id;

  if p_items is not null then
    for line in select * from jsonb_array_elements(p_items) loop
      line_no := line_no + 1;
      line_total := coalesce((line ->> 'qty')::numeric, 1)
                  * coalesce((line ->> 'unit_price')::numeric, 0)
                  - coalesce((line ->> 'discount_amount')::numeric, 0);
      subtotal := subtotal + line_total;

      insert into public.service_items
        (service_id, line_number, item_type, product_id, name, qty,
         unit_price, discount_amount, tax_amount, total_amount)
      values
        (service_id, line_no,
         coalesce(line ->> 'item_type', 'labour'),
         nullif(line ->> 'product_id', '')::uuid,
         coalesce(line ->> 'name', ''),
         coalesce((line ->> 'qty')::numeric, 1),
         coalesce((line ->> 'unit_price')::numeric, 0),
         coalesce((line ->> 'discount_amount')::numeric, 0),
         0,
         line_total);
    end loop;
  end if;

  update public.service_records
     set subtotal_amount = round(subtotal, 2),
         total_amount    = round(subtotal, 2),
         outstanding_amount = round(subtotal, 2),
         updated_at = now()
   where id = service_id;

  return (
    select jsonb_build_object(
             'id', s.id,
             'service_number', s.service_number,
             'status', s.status,
             'total_amount', s.total_amount,
             'service_items', coalesce(
               (select jsonb_agg(to_jsonb(si) order by si.line_number)
                  from public.service_items si
                 where si.service_id = s.id), '[]'::jsonb)
           )
      from public.service_records s
     where s.id = service_id
  );
end;
$$;

create or replace function public.complete_service(
  p_service_id uuid,
  p_odometer_out numeric default null,
  p_work_done text default '',
  p_total_override numeric default null,
  p_collect_on_delivery boolean default false,
  p_payment_mode text default 'cash',
  p_completed_at timestamptz default now()
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  job       public.service_records%rowtype;
  invoice_id uuid;
  total     numeric;
begin
  select * into job from public.service_records s
   where s.id = p_service_id for update;
  if not found then
    raise exception 'NOT_FOUND: service %', p_service_id using errcode = 'P0002';
  end if;
  if not public.has_permission('service', 'complete') then
    raise exception 'FORBIDDEN: service.complete required' using errcode = '42501';
  end if;
  if job.status in ('completed', 'delivered', 'cancelled') then
    raise exception 'CONFLICT: job is already %', job.status using errcode = '40001';
  end if;

  total := coalesce(p_total_override, job.total_amount);

  update public.service_records
     set status = 'completed',
         completed_at = coalesce(p_completed_at, now()),
         odometer_out = coalesce(p_odometer_out, odometer_out),
         work_done = coalesce(nullif(p_work_done, ''), work_done),
         total_amount = total,
         outstanding_amount = total - paid_amount,
         updated_at = now()
   where id = p_service_id;

  -- Consume a matching free service when this is a free job card.
  if job.job_type = 'free' then
    update public.free_service_grants
       set status = 'used',
           used_date = current_date,
           used_service_id = p_service_id,
           used_mileage = coalesce(p_odometer_out, job.odometer_in)
     where id = (
       select g.id from public.free_service_grants g
        where g.vehicle_id = job.vehicle_id and g.status = 'active'
        order by g.end_date nulls last
        limit 1
     );
  end if;

  -- Invoice the job; payment is collected through record_payment().
  insert into public.invoices
    (showroom_id, customer_id, service_id, invoice_number, invoice_type,
     invoice_date, subtotal_amount, discount_amount, tax_amount, total_amount,
     paid_amount, outstanding_amount, payment_mode, status, created_by)
  values
    (job.showroom_id, job.customer_id, p_service_id,
     public.next_document_number(job.showroom_id, 'INV'), 'service',
     current_date, job.subtotal_amount, job.discount_amount, job.tax_amount,
     total, job.paid_amount, total - job.paid_amount, p_payment_mode,
     case when total - job.paid_amount <= 0 then 'paid' else 'unpaid' end,
     public.current_user_id())
  returning id into invoice_id;

  insert into public.invoice_items
    (invoice_id, line_number, item_type, product_id, description, qty,
     unit_price, discount_amount, tax_rate, tax_amount, total_amount)
  select invoice_id, si.line_number, si.item_type, si.product_id, si.name,
         si.qty, si.unit_price, si.discount_amount, 0, si.tax_amount,
         si.total_amount
    from public.service_items si
   where si.service_id = p_service_id;

  return (
    select jsonb_build_object(
             'id', s.id,
             'status', s.status,
             'total_amount', s.total_amount,
             'outstanding_amount', s.outstanding_amount,
             'invoice_id', invoice_id,
             'collect_on_delivery', coalesce(p_collect_on_delivery, false)
           )
      from public.service_records s
     where s.id = p_service_id
  );
end;
$$;

-- -------------------------------------------------------------- purchases

create or replace function public.create_purchase_transaction(
  supplier_id uuid,
  showroom_id uuid,
  lines jsonb,
  order_date date default current_date,
  expected_date date default null,
  discount_amount numeric default 0,
  tax_rate numeric default 18,
  notes text default ''
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  purchase_id uuid;
  line        jsonb;
  line_no     integer := 0;
  subtotal    numeric := 0;
  line_total  numeric;
  line_tax    numeric;
  qty         numeric;
  unit_cost   numeric;
  -- Parameter names must match the Dart call site, and several of them
  -- collide with purchases columns; alias them so SQL statements are not
  -- ambiguous.
  v_supplier_id    uuid        := supplier_id;
  v_showroom_id    uuid        := showroom_id;
  v_order_date     date        := coalesce(order_date, current_date);
  v_expected_date  date        := expected_date;
  v_discount       numeric     := coalesce(discount_amount, 0);
  v_tax_rate       numeric     := coalesce(tax_rate, 0);
  v_notes          text        := coalesce(notes, '');
begin
  if not public.can_access_showroom(v_showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;
  if not public.has_permission('purchases', 'create') then
    raise exception 'FORBIDDEN: purchases.create required' using errcode = '42501';
  end if;
  if lines is null or jsonb_array_length(lines) = 0 then
    raise exception 'VALIDATION: at least one purchase line is required'
      using errcode = '22023';
  end if;

  insert into public.purchases
    (showroom_id, supplier_id, purchase_number, order_date, expected_date,
     discount_amount, tax_rate, status, notes, created_by)
  values
    (v_showroom_id, v_supplier_id,
     public.next_document_number(v_showroom_id, 'PO'),
     v_order_date, v_expected_date,
     v_discount, v_tax_rate, 'ordered',
     v_notes, public.current_user_id())
  returning id into purchase_id;

  for line in select * from jsonb_array_elements(lines) loop
    line_no := line_no + 1;
    qty := coalesce((line ->> 'qty')::numeric, 1);
    unit_cost := coalesce(
      nullif(line ->> 'unit_cost', '')::numeric,
      nullif(line ->> 'unit_price', '')::numeric,
      0
    );
    line_total := qty * unit_cost;
    line_tax := round(line_total * v_tax_rate / 100.0, 2);
    subtotal := subtotal + line_total;

    insert into public.purchase_items
      (purchase_id, line_number, product_id, product_name, qty, received_qty,
       unit_cost, tax_amount, total_amount)
    values
      (purchase_id, line_no,
       nullif(line ->> 'product_id', '')::uuid,
       coalesce(line ->> 'product_name', line ->> 'name', ''),
       qty, 0, unit_cost, line_tax, line_total + line_tax);
  end loop;

  update public.purchases
     set subtotal_amount    = round(subtotal, 2),
         tax_amount         = round(subtotal * v_tax_rate / 100.0, 2),
         total_amount       = round(subtotal - v_discount
                                    + subtotal * v_tax_rate / 100.0, 2),
         outstanding_amount = round(subtotal - v_discount
                                    + subtotal * v_tax_rate / 100.0, 2),
         updated_at = now()
   where id = purchase_id;

  return (
    select jsonb_build_object(
             'id', p.id,
             'purchase_number', p.purchase_number,
             'status', p.status,
             'total_amount', p.total_amount,
             'outstanding_amount', p.outstanding_amount,
             'supplier', coalesce((select to_jsonb(s) from public.suppliers s
                                    where s.id = p.supplier_id), null),
             'purchase_items', coalesce(
               (select jsonb_agg(to_jsonb(pi) order by pi.line_number)
                  from public.purchase_items pi
                 where pi.purchase_id = p.id), '[]'::jsonb)
           )
      from public.purchases p
     where p.id = purchase_id
  );
end;
$$;

-- Goods receipt: creates one inventory unit per received line.
create or replace function public.receive_purchase(
  p_purchase_id uuid,
  p_received_date date default current_date,
  p_chassis_numbers jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  po        public.purchases%rowtype;
  item      public.purchase_items%rowtype;
  chassis   text;
  n         integer;
  received  integer := 0;
  units     jsonb := '[]'::jsonb;
  new_id    uuid;
begin
  select * into po from public.purchases p
   where p.id = p_purchase_id for update;
  if not found then
    raise exception 'NOT_FOUND: purchase %', p_purchase_id using errcode = 'P0002';
  end if;
  if not public.has_permission('purchases', 'edit') then
    raise exception 'FORBIDDEN: purchases.edit required' using errcode = '42501';
  end if;

  for item in select * from public.purchase_items pi
               where pi.purchase_id = p_purchase_id loop
    for n in 1 .. floor(item.qty - item.received_qty)::int loop
      chassis := nullif(
        coalesce(p_chassis_numbers ->> item.line_number::text, ''), ''
      );
      if chassis is null then
        chassis := upper(po.purchase_number || '-' || item.line_number
                         || '-' || (item.received_qty + n)::text);
      end if;

      insert into public.inventory
        (showroom_id, product_id, chassis_number, purchase_date,
         purchase_price, status)
      values
        (po.showroom_id, item.product_id, chassis,
         coalesce(p_received_date, current_date), item.unit_cost, 'available')
      on conflict (chassis_number) do nothing
      returning id into new_id;

      if new_id is not null then
        received := received + 1;
        units := units || jsonb_build_object(
          'id', new_id,
          'chassis_number', chassis,
          'product_id', item.product_id
        );
        new_id := null;
      end if;
    end loop;

    update public.purchase_items
       set received_qty = qty
     where id = item.id;
  end loop;

  update public.purchases
     set received_date = coalesce(p_received_date, current_date),
         status = 'received',
         updated_at = now()
   where id = p_purchase_id;

  return jsonb_build_object(
    'id', p_purchase_id,
    'status', 'received',
    'received_units', received,
    'inventory', units
  );
end;
$$;

create or replace function public.pay_supplier(
  p_purchase_id uuid,
  p_amount numeric,
  p_payment_mode text,
  p_payment_date date default current_date,
  p_reference_number text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  po       public.purchases%rowtype;
  payment_id uuid;
begin
  select * into po from public.purchases p
   where p.id = p_purchase_id for update;
  if not found then
    raise exception 'NOT_FOUND: purchase %', p_purchase_id using errcode = 'P0002';
  end if;
  if not public.has_permission('purchases', 'edit') then
    raise exception 'FORBIDDEN: purchases.edit required' using errcode = '42501';
  end if;
  if p_amount <= 0 or p_amount > po.outstanding_amount then
    raise exception 'VALIDATION: amount must be between 0 and %',
                    po.outstanding_amount
      using errcode = '22023';
  end if;

  insert into public.payments
    (showroom_id, payment_number, payment_date, amount, payment_mode,
     reference_number, status, notes, received_by)
  values
    (po.showroom_id, public.next_document_number(po.showroom_id, 'SPAY'),
     coalesce(p_payment_date, current_date), p_amount,
     coalesce(p_payment_mode, 'neft'), p_reference_number, 'completed',
     'Supplier payment for ' || po.purchase_number, public.current_user_id())
  returning id into payment_id;

  update public.purchases
     set paid_amount = paid_amount + p_amount,
         outstanding_amount = total_amount - (paid_amount + p_amount),
         payment_status = case
                            when total_amount - (paid_amount + p_amount) <= 0
                              then 'paid'
                            else 'partial'
                          end,
         updated_at = now()
   where id = p_purchase_id;

  return (select to_jsonb(p) from public.payments p where p.id = payment_id);
end;
$$;

-- --------------------------------------------------------------- expenses

create or replace function public.create_expense_transaction(
  category_id uuid,
  showroom_id uuid,
  amount numeric,
  date date default current_date,
  description text default '',
  payment_mode text default 'cash',
  reference_number text default null,
  voucher_number text default null,
  attachment_path text default null,
  notes text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  expense_id  uuid;
  needs_approval boolean;
  v_category_id   uuid    := category_id;
  v_showroom_id   uuid    := showroom_id;
  v_amount        numeric := amount;
  v_date          date    := coalesce(date, current_date);
  v_description   text    := coalesce(description, '');
  v_payment_mode  text    := coalesce(payment_mode, 'cash');
begin
  if not public.can_access_showroom(v_showroom_id) then
    raise exception 'FORBIDDEN: no access to showroom' using errcode = '42501';
  end if;
  if not public.has_permission('expenses', 'create') then
    raise exception 'FORBIDDEN: expenses.create required' using errcode = '42501';
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'VALIDATION: amount must be positive' using errcode = '22023';
  end if;

  select c.requires_approval into needs_approval
    from public.expense_categories c
   where c.id = v_category_id;
  if not found then
    raise exception 'NOT_FOUND: expense category %', v_category_id
      using errcode = 'P0002';
  end if;

  insert into public.expenses
    (showroom_id, category_id, expense_number, date, amount, payment_mode,
     description, reference_number, voucher_number, attachment_path, notes,
     requires_approval, status, created_by)
  values
    (v_showroom_id, v_category_id,
     public.next_document_number(v_showroom_id, 'EXP'),
     v_date, v_amount, v_payment_mode,
     v_description, reference_number, voucher_number,
     attachment_path, coalesce(notes, ''),
     coalesce(needs_approval, false),
     case when coalesce(needs_approval, false) then 'pending'
          else 'approved' end,
     public.current_user_id())
  returning id into expense_id;

  return (
    select jsonb_build_object(
             'id', e.id,
             'expense_number', e.expense_number,
             'amount', e.amount,
             'status', e.status,
             'date', e.date,
             'category', coalesce(
               (select jsonb_build_object('id', c.id, 'name', c.name,
                                          'icon', c.icon)
                  from public.expense_categories c
                 where c.id = e.category_id), null)
           )
      from public.expenses e
     where e.id = expense_id
  );
end;
$$;

create or replace function public.approve_expense(
  p_expense_id uuid,
  p_approved_by uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not public.has_permission('expenses', 'approve') then
    raise exception 'FORBIDDEN: expenses.approve required' using errcode = '42501';
  end if;

  update public.expenses
     set status = 'approved',
         approved_by = coalesce(p_approved_by, public.current_user_id()),
         approved_at = now(),
         rejection_reason = null,
         updated_at = now()
   where id = p_expense_id
     and status <> 'approved';

  if not found then
    raise exception 'CONFLICT: expense % is not approvable', p_expense_id
      using errcode = '40001';
  end if;

  return (select to_jsonb(e) from public.expenses e where e.id = p_expense_id);
end;
$$;

create or replace function public.reject_expense(
  p_expense_id uuid,
  p_rejected_by uuid default null,
  p_reason text default ''
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if not public.has_permission('expenses', 'approve') then
    raise exception 'FORBIDDEN: expenses.approve required' using errcode = '42501';
  end if;

  update public.expenses
     set status = 'rejected',
         rejected_by = coalesce(p_rejected_by, public.current_user_id()),
         rejection_reason = p_reason,
         updated_at = now()
   where id = p_expense_id
     and status = 'pending';

  if not found then
    raise exception 'CONFLICT: expense % is not pending', p_expense_id
      using errcode = '40001';
  end if;

  return (select to_jsonb(e) from public.expenses e where e.id = p_expense_id);
end;
$$;

-- PostgREST exposure: the RPCs are callable by any authenticated user; the
-- bodies above perform the real permission checks (has_permission /
-- can_access_showroom) and RLS still applies to every table they touch.
grant usage on schema public to authenticated;
grant execute on all functions in schema public to authenticated;
alter default privileges in schema public
  grant execute on functions to authenticated;
