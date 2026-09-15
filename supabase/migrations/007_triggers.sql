-- =============================================================================
-- 007_triggers.sql
-- -----------------------------------------------------------------------------
-- Purpose : automation that is *safe* to hide from the client:
--             1. updated_at + revision maintenance (all tables)
--             2. search vector maintenance
--             3. audit trail for master data
--             4. financial immutability guards (invoice/payment/journal/audit)
--             5. derived aggregates (line items -> document header)
--             6. small consistency enforcements that must never be forgotten
--
-- Per SS52 complex business flow is NOT here: sales/purchases/services/expenses
-- are executed by the explicit RPCs in 006. Triggers below only guard invariants.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. updated_at (and revision bump) on every table that has an updated_at column
-- ---------------------------------------------------------------------------
do $$
declare
  rec record;
begin
  for rec in
    select table_schema, table_name
      from information_schema.columns
     where column_name = 'updated_at'
       and table_schema in ('public','storage')
       and table_name not in ('buckets')            -- storage.buckets is platform-owned
     group by 1, 2
     order by 1, 2
  loop
    execute format('drop trigger if exists trg_touch_%I on %I.%I', rec.table_name, rec.table_schema, rec.table_name);
    execute format($f$
      create trigger trg_touch_%1$I before update on %2$I.%1$I
        for each row execute function app_util.touch_updated_at()$f$,
      rec.table_name, rec.table_schema);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Catalogue search vector (SS71)
-- ---------------------------------------------------------------------------
create or replace function app_util.products_search_vector()
returns trigger
language plpgsql
as $$
begin
  new.search_vector :=
      setweight(to_tsvector('simple', coalesce(new.name, '')),        'A')
   || setweight(to_tsvector('simple', coalesce(new.model, '')),       'A')
   || setweight(to_tsvector('simple', coalesce(new.variant, '')),     'B')
   || setweight(to_tsvector('simple', coalesce(new.category, '')),    'B')
   || setweight(to_tsvector('simple', coalesce(new.description, '')), 'C')
   || setweight(to_tsvector('simple', coalesce(
        (select b.name from public.brands b where b.id = new.brand_id), '')), 'A');
  new.name    := app_util.nullif_blank(new.name);
  new.model   := app_util.nullif_blank(new.model);
  new.variant := app_util.nullif_blank(new.variant);
  return new;
end;
$$;

drop trigger if exists trg_products_search on public.products;
create trigger trg_products_search
  before insert or update of name, model, variant, description, brand_id, category
  on public.products
  for each row execute function app_util.products_search_vector();

-- ---------------------------------------------------------------------------
-- 3. Audit trail for master/reference data.
--    Transactional documents (sales, invoices, payments, journals, job cards)
--    are audited by the RPC that performs the *semantic* action, so the log
--    reads like the business did, not like an ORM flushed.
-- ---------------------------------------------------------------------------
create or replace function app_util.audit_generic()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_module text := coalesce(tg_argv[0], tg_table_name);
  v_new    jsonb;
  v_old    jsonb;
  v_id     uuid;
  v_shr    uuid;
  v_action text;
  v_label  text;
begin
  -- NEW is only valid for INSERT/UPDATE, OLD only for UPDATE/DELETE: build the
  -- payloads separately or plpgsql raises "record is not assigned yet".
  if tg_op in ('INSERT','UPDATE') then
    v_new := to_jsonb(new);
  end if;
  if tg_op in ('UPDATE','DELETE') then
    v_old := to_jsonb(old);
  end if;

  if tg_op = 'INSERT' then
    v_action := 'CREATE';
  elsif tg_op = 'DELETE' then
    v_action := 'DELETE';
  else
    if v_old = v_new then
      return new;                       -- nothing actually changed: skip the noise
    end if;
    v_action := 'UPDATE';
    -- a soft delete is a DELETE from the business point of view
    if coalesce((v_new ->> 'is_deleted')::boolean, false)
       and not coalesce((v_old ->> 'is_deleted')::boolean, false) then
      v_action := 'DELETE';
    end if;
  end if;

  v_id  := coalesce((v_new ->> 'id')::uuid, (v_old ->> 'id')::uuid);
  v_shr := coalesce((v_new ->> 'showroom_id')::uuid, (v_old ->> 'showroom_id')::uuid);
  v_label := coalesce(v_new ->> 'name', v_new ->> 'code', v_new ->> 'title',
                      v_new ->> 'stock_code', v_new ->> 'account_name',
                      v_old ->> 'name', v_old ->> 'code', v_old ->> 'stock_code');

  perform app_util.audit_row(v_module, v_action, tg_table_name, v_id, v_old, v_new,
                             v_shr, null, v_label,
                             case when v_action = 'DELETE' then 'WARNING' else 'INFO' end);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $$
declare
  t record;
begin
  for t in select * from (values
      ('showrooms'), ('users'), ('roles'), ('permissions'), ('brands'),
      ('products'), ('product_colors'), ('inventory'), ('customers'),
      ('customer_vehicles'), ('finance_companies'), ('suppliers'),
      ('expense_categories'), ('free_service_plans'), ('accounts')
  ) as x(name)
  loop
    execute format('drop trigger if exists trg_audit_%1$s on public.%1$I', t.name);
    execute format(
      'create trigger trg_audit_%1$s
         after insert or update or delete on public.%1$I
         for each row execute function app_util.audit_generic(%2$L)',
      t.name,
      case t.name
        when 'showrooms'         then 'showroom'
        when 'users'             then 'users'
        when 'roles'             then 'roles'
        when 'permissions'       then 'roles'
        when 'product_colors'    then 'products'
        when 'customer_vehicles' then 'customers'
        when 'expense_categories'then 'expenses'
        when 'free_service_plans'then 'service'
        else regexp_replace(t.name, 's$', '')
      end);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Immutability guards
-- ---------------------------------------------------------------------------

-- 4a. A finalized invoice can only be touched by the RPCs that know what they
--     are doing (payment allocation, cancellation). Any other write to the
--     priced columns is refused.
create or replace function app_util.guard_finalized_invoice()
returns trigger
language plpgsql
as $$
declare
  v_bypass boolean := coalesce(current_setting('app.bypass_finalized_check', true) = 'on', false);
begin
  if v_bypass then
    return new;
  end if;
  if old.finalized then
    if new.invoice_number   is distinct from old.invoice_number
       or new.invoice_type  is distinct from old.invoice_type
       or new.invoice_date  is distinct from old.invoice_date
       or new.subtotal      is distinct from old.subtotal
       or new.discount      is distinct from old.discount
       or new.tax_amount    is distinct from old.tax_amount
       or new.other_charges is distinct from old.other_charges
       or new.total_amount  is distinct from old.total_amount
       or new.customer_id   is distinct from old.customer_id
       or new.showroom_id   is distinct from old.showroom_id
       or new.sale_id       is distinct from old.sale_id
       or new.service_id    is distinct from old.service_id
       or new.finalized     is distinct from old.finalized
    then
      raise exception '[CON001] invoice % is finalized; use the cancel/reverse flow instead',
        old.invoice_number using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_invoices_finalized on public.invoices;
create trigger trg_guard_invoices_finalized
  before update on public.invoices
  for each row execute function app_util.guard_finalized_invoice();

create or replace function app_util.guard_finalized_invoice_items()
returns trigger
language plpgsql
as $$
declare
  v_finalized boolean;
  v_invoice   uuid;
  v_bypass boolean := coalesce(current_setting('app.bypass_finalized_check', true) = 'on', false);
begin
  v_invoice := case when tg_op = 'DELETE' then old.invoice_id else new.invoice_id end;

  select finalized into v_finalized from public.invoices where id = v_invoice;
  if v_finalized and not v_bypass then
    raise exception '[CON002] invoice % is finalized; its line items are read-only',
      (select invoice_number from public.invoices where id = v_invoice)
      using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_invoice_items on public.invoice_items;
create trigger trg_guard_invoice_items
  before insert or update or delete on public.invoice_items
  for each row execute function app_util.guard_finalized_invoice_items();

-- 4b. Money never changes after the fact: only status/reversal bookkeeping.
create or replace function app_util.guard_payments_immutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception '[CON003] payments can never be deleted; reverse them with public.reverse_payment()'
      using errcode = '23514';
  end if;

  if new.amount           is distinct from old.amount
     or new.payment_date   is distinct from old.payment_date
     or new.customer_id    is distinct from old.customer_id
     or new.showroom_id    is distinct from old.showroom_id
     or new.invoice_id     is distinct from old.invoice_id
     or new.sale_id        is distinct from old.sale_id
     or new.emi_id         is distinct from old.emi_id
     or new.service_id     is distinct from old.service_id
     or new.payment_method is distinct from old.payment_method
     or new.payment_number is distinct from old.payment_number
     or new.allocated_amount is distinct from old.allocated_amount
  then
    raise exception '[CON004] payment % is immutable; reverse and re-record it', old.payment_number
      using errcode = '23514';
  end if;

  -- status may only move forward on the documented paths
  if new.status is distinct from old.status
     and not ((old.status = 'PENDING'    and new.status in ('COMPLETED','FAILED','CANCELLED'))
          or (old.status = 'COMPLETED'   and new.status in ('REVERSED','REFUNDED','CANCELLED'))
          or (old.status = 'CANCELLED'   and new.status = 'REVERSED')) then
    raise exception '[CON005] illegal payment status transition % -> %', old.status, new.status
      using errcode = '23514';
  end if;

  if new.status in ('REVERSED','REFUNDED','CANCELLED') and coalesce(new.reversal_reason, old.reversal_reason) is null then
    raise exception '[VAL001] a reversal or refund requires reversal_reason' using errcode = '22000';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_payments on public.payments;
create trigger trg_guard_payments
  before update or delete on public.payments
  for each row execute function app_util.guard_payments_immutable();

-- 4c. Journals: entries are append-only, and the header only allows reversal flags.
create or replace function app_util.guard_accounting_immutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception '[CON006] accounting entries are append-only' using errcode = '23514';
  end if;
  raise exception '[CON007] accounting entries are append-only; post a reversing journal'
    using errcode = '23514';
end;
$$;

drop trigger if exists trg_guard_accounting_entries on public.accounting_entries;
create trigger trg_guard_accounting_entries
  before update or delete on public.accounting_entries
  for each row execute function app_util.guard_accounting_immutable();

create or replace function app_util.guard_accounting_tx()
returns trigger
language plpgsql
as $$
declare
  v_changed text;
begin
  if tg_op = 'DELETE' then
    raise exception '[CON008] accounting transactions can never be deleted' using errcode = '23514';
  end if;

  -- Everything on a journal is frozen except its reversal state: money is answered
  -- with an opposite entry, never with an edit (SS42).  The comparison is written
  -- as "every column except these" so that a column added later is immutable by
  -- default instead of silently editable.
  select string_agg(c.key, ', ' order by c.key) into v_changed
    from jsonb_each(to_jsonb(old) - 'is_reversed' - 'reversed_by_transaction_id'
                                  - 'status'
                                  -- financial_year is GENERATED ALWAYS. Postgres has not
                                  -- recomputed generated columns while a BEFORE trigger runs,
                                  -- so it reads as NULL in NEW and would look like an edit.
                                  - 'financial_year') as c(key, value)
   where (to_jsonb(new) -> c.key) is distinct from (to_jsonb(old) -> c.key);

  if v_changed is not null then
    raise exception '[CON009] journal % is immutable apart from its reversal state (protected columns: %)'
      , old.transaction_number, v_changed using errcode = '23514';
  end if;

  -- the only status a posted journal may take is REVERSED, and only together with
  -- the two reversal links, which is what app_acc.reverse_journal writes.
  if new.status is distinct from old.status then
    if old.status <> 'POSTED' or new.status <> 'REVERSED'
       or new.is_reversed is not true or new.reversed_by_transaction_id is null then
      raise exception '[CON009] journal % may only move from POSTED to REVERSED, through a reversal entry'
        , old.transaction_number using errcode = '23514';
    end if;
  end if;
  if new.is_reversed is distinct from old.is_reversed
     and (new.is_reversed is not true or old.is_reversed or new.reversed_by_transaction_id is null) then
    raise exception '[CON009] journal % cannot be marked reversed without a reversal entry'
      , old.transaction_number using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_accounting_tx on public.accounting_transactions;
create trigger trg_guard_accounting_tx
  before update or delete on public.accounting_transactions
  for each row execute function app_util.guard_accounting_tx();

-- 4d. Audit + stock ledgers are append-only for every role, superuser included.
create or replace function app_util.guard_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception '[CON010] %.% is append-only (SS41)', tg_table_name, tg_op
    using errcode = '23514';
end;
$$;

drop trigger if exists trg_append_audit_logs on public.audit_logs;
create trigger trg_append_audit_logs
  before update or delete on public.audit_logs
  for each row execute function app_util.guard_append_only();

drop trigger if exists trg_append_stock_movements on public.stock_movements;
create trigger trg_append_stock_movements
  before update or delete on public.stock_movements
  for each row execute function app_util.guard_append_only();

-- ---------------------------------------------------------------------------
-- 5. Derived aggregates: a document header always equals the sum of its lines
--    (SS68 - the header is a roll-up, never an independent truth).
--    Each trigger resolves its parent through TG_OP because OLD is invalid on
--    INSERT and NEW is invalid on DELETE in plpgsql row triggers.
-- ---------------------------------------------------------------------------
create or replace function public.recalc_invoice_header(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_invoice_id is null then
    return;
  end if;
  update public.invoices i
     set subtotal     = s.subtotal,
         discount     = s.discount,
         tax_amount   = s.tax,
         total_amount = round(s.subtotal - s.discount + s.tax + i.other_charges, 2),
         outstanding_amount = round(greatest(s.subtotal - s.discount + s.tax + i.other_charges
                                             - i.paid_amount, 0), 2)
    from (select round(coalesce(sum(ii.quantity * ii.unit_price), 0), 2) as subtotal,
                 round(coalesce(sum(ii.discount), 0), 2)                 as discount,
                 round(coalesce(sum(ii.tax_amount), 0), 2)               as tax
            from public.invoice_items ii
           where ii.invoice_id = p_invoice_id) as s
   where i.id = p_invoice_id;
end;
$$;

create or replace function public.recalc_sale_header(p_sale_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_sale_id is null then
    return;
  end if;
  update public.sales s
     set subtotal     = x.subtotal,
         discount     = x.discount,
         tax_amount   = x.tax,
         total_amount = round(x.subtotal - x.discount + x.tax + s.other_charges - s.exchange_value, 2),
         outstanding_amount = round(greatest(x.subtotal - x.discount + x.tax + s.other_charges
                                             - s.exchange_value - s.paid_amount, 0), 2)
    from (select round(coalesce(sum(si.quantity * si.unit_price), 0), 2) as subtotal,
                 round(coalesce(sum(si.discount), 0), 2)                 as discount,
                 round(coalesce(sum(si.tax_amount), 0), 2)               as tax
            from public.sale_items si where si.sale_id = p_sale_id) x
   where s.id = p_sale_id and s.status not in ('CANCELLED','RETURNED');
end;
$$;

create or replace function public.recalc_service_header(p_service_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_service_id is null then
    return;
  end if;
  update public.service_records r
     set subtotal       = x.subtotal,
         discount       = x.discount,
         tax_amount     = x.tax,
         labour_charges = x.labour,
         parts_charges  = x.parts,
         total_amount   = round(x.subtotal - x.discount + x.tax + r.other_charges, 2),
         outstanding_amount = round(greatest(x.subtotal - x.discount + x.tax + r.other_charges
                                             - r.paid_amount, 0), 2)
    from (select round(coalesce(sum(si.quantity * si.unit_price - si.discount), 0), 2) as subtotal,
                 round(coalesce(sum(si.discount), 0), 2)   as discount,
                 round(coalesce(sum(si.tax_amount), 0), 2) as tax,
                 round(coalesce(sum(si.total_amount) filter (where si.item_type = 'LABOUR'), 0), 2) as labour,
                 round(coalesce(sum(si.total_amount) filter
                       (where si.item_type in ('PART','OIL','CONSUMABLE','ACCESSORY')), 0), 2)      as parts
            from public.service_items si where si.service_id = p_service_id) x
   where r.id = p_service_id and r.service_status <> 'CANCELLED';
end;
$$;

create or replace function public.recalc_purchase_header(p_purchase_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_purchase_id is null then
    return;
  end if;
  update public.purchases p
     set subtotal     = x.subtotal,
         discount     = x.discount,
         tax_amount   = x.tax,
         total_amount = round(x.subtotal - x.discount + x.tax + p.other_charges + p.freight_charges, 2),
         outstanding_amount = round(greatest(x.subtotal - x.discount + x.tax + p.other_charges
                                             + p.freight_charges - p.paid_amount, 0), 2)
    from (select round(coalesce(sum(pi.quantity * pi.unit_cost), 0), 2) as subtotal,
                 round(coalesce(sum(pi.discount), 0), 2)                as discount,
                 round(coalesce(sum(pi.tax_amount), 0), 2)              as tax
            from public.purchase_items pi where pi.purchase_id = p_purchase_id) x
   where p.id = p_purchase_id and p.status <> 'CANCELLED';
end;
$$;

create or replace function app_util.rollup_line_header()
returns trigger
language plpgsql
as $$
declare
  v_bypass boolean := coalesce(current_setting('app.bypass_finalized_check', true) = 'on', false);
begin
  -- invoice lines belong to a finalized document: only the owning RPC may move
  -- the header, the rollup stays out of the way
  if tg_table_name = 'invoice_items' and v_bypass then
    return coalesce(new, old);
  end if;

  case tg_table_name
    when 'invoice_items' then
      if tg_op = 'DELETE' then
        perform public.recalc_invoice_header(old.invoice_id);
      else
        perform public.recalc_invoice_header(new.invoice_id);
      end if;
    when 'sale_items' then
      perform public.recalc_sale_header(case when tg_op = 'DELETE' then old.sale_id else new.sale_id end);
    when 'service_items' then
      perform public.recalc_service_header(case when tg_op = 'DELETE' then old.service_id else new.service_id end);
    when 'purchase_items' then
      perform public.recalc_purchase_header(case when tg_op = 'DELETE' then old.purchase_id else new.purchase_id end);
  end case;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rollup_invoice_items on public.invoice_items;
create trigger trg_rollup_invoice_items
  after insert or update or delete on public.invoice_items
  for each row execute function app_util.rollup_line_header();

drop trigger if exists trg_rollup_sale_items on public.sale_items;
create trigger trg_rollup_sale_items
  after insert or update or delete on public.sale_items
  for each row execute function app_util.rollup_line_header();

drop trigger if exists trg_rollup_service_items on public.service_items;
create trigger trg_rollup_service_items
  after insert or update or delete on public.service_items
  for each row execute function app_util.rollup_line_header();

drop trigger if exists trg_rollup_purchase_items on public.purchase_items;
create trigger trg_rollup_purchase_items
  after insert or update or delete on public.purchase_items
  for each row execute function app_util.rollup_line_header();


-- ---------------------------------------------------------------------------
-- 6. Consistency guards that must never depend on the client behaving
-- ---------------------------------------------------------------------------

-- 6a. SOLD stock always points at the sale that consumed it (SS10, SS67).
create or replace function app_util.guard_inventory_allocation()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'SOLD' and new.allocated_sale_id is null and old.allocated_sale_id is null then
    raise exception '[VAL001] a SOLD unit must be allocated to a sale; use create_sale_transaction()'
      using errcode = '22000';
  end if;
  if new.status <> 'SOLD' and new.allocated_sale_id is null and old.allocated_sale_id is not null
     and not app_sec.has_permission('sales','cancel') then
    raise exception '[SEC001] releasing sold stock requires sales.cancel; use cancel_sale()'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_inventory_alloc on public.inventory;
create trigger trg_guard_inventory_alloc
  before update on public.inventory
  for each row execute function app_util.guard_inventory_allocation();

-- 6b. Chassis/engine changes after a sale would break the vehicle ledger.
create or replace function app_util.guard_inventory_serials()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'SOLD'
     and (new.chassis_number is distinct from old.chassis_number
          or new.engine_number is distinct from old.engine_number
          or new.product_id    is distinct from old.product_id) then
    raise exception '[CON001] a sold unit''s serials and product are frozen (SS67)'
      using errcode = '23514';
  end if;
  if new.status = 'SOLD'
     and exists (select 1 from public.customer_vehicles v
                  where v.inventory_id = new.id and v.is_deleted = false
                    and v.chassis_number is distinct from new.chassis_number) then
    raise exception '[CON002] chassis number disagrees with the vehicle ledger for this unit'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_inventory_serials on public.inventory;
create trigger trg_guard_inventory_serials
  before update of chassis_number, engine_number, product_id, status on public.inventory
  for each row execute function app_util.guard_inventory_serials();

-- 6c. Vehicle odometer only ever moves forward; service jobs feed it (SS12).
create or replace function app_util.vehicle_sync_from_service()
returns trigger
language plpgsql
as $$
begin
  if new.service_status in ('COMPLETED','DELIVERED')
     and old.service_status is distinct from new.service_status
     and new.odometer_reading is not null then
    update public.customer_vehicles v
       set current_odometer = greatest(coalesce(v.current_odometer,0), new.odometer_reading),
           odometer_updated_at = now(),
           status = case when new.service_status = 'DELIVERED' then 'ACTIVE' else v.status end
     where v.id = new.vehicle_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_vehicle_from_service on public.service_records;
create trigger trg_vehicle_from_service
  after update of service_status, odometer_reading on public.service_records
  for each row execute function app_util.vehicle_sync_from_service();

-- 6d. A customer's lifetime value / last purchase stays true without a batch job.
create or replace function app_util.customer_rollup_refresh()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- OLD is unassigned on INSERT and NEW on DELETE, so the row reference has to
  -- be picked per TG_OP rather than coalesced.
  v_id uuid := case when tg_op = 'DELETE' then old.customer_id else new.customer_id end;
begin
  if v_id is null then
    return coalesce(new, old);
  end if;

  update public.customers c
     set lifetime_value = round(coalesce((
             select sum(s.total_amount) from public.sales s
              where s.customer_id = v_id and s.status not in ('CANCELLED','RETURNED')), 0), 2),
         last_purchase_at = (select max(s.created_at) from public.sales s
                              where s.customer_id = v_id and s.status not in ('CANCELLED','RETURNED')),
         updated_at = now()
   where c.id = v_id;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_customer_rollup_sales on public.sales;
create trigger trg_customer_rollup_sales
  after insert or update or delete on public.sales
  for each row execute function app_util.customer_rollup_refresh();

-- 6e. is_super_admin must agree with the SUPERADMIN role membership (SS6).
create or replace function app_util.sync_super_admin_flag()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
begin
  update public.users u
     set is_super_admin = exists (
           select 1 from public.user_roles x
           join public.roles r on r.id = x.role_id
          where x.user_id = v_user and r.code = 'SUPERADMIN')
   where u.id = v_user;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_sync_super_admin on public.user_roles;
create trigger trg_sync_super_admin
  after insert or update or delete on public.user_roles
  for each row execute function app_util.sync_super_admin_flag();

-- 6f. Payments may never allocate more than a document owes (SS67).
create or replace function app_util.guard_payment_allocation()
returns trigger
language plpgsql
as $$
declare
  v_total_alloc numeric;
  v_owed        numeric;
begin
  if new.invoice_id is null or new.status <> 'COMPLETED' then
    return new;
  end if;
  select round(coalesce(sum(allocated_amount), 0), 2) into v_total_alloc
    from public.payments where invoice_id = new.invoice_id and status = 'COMPLETED';
  select total_amount into v_owed from public.invoices where id = new.invoice_id;
  if v_total_alloc > coalesce(v_owed, 0) + 0.005 then
    raise exception '[CON001] over-allocation on invoice %: % applied against % owed (SS67)',
      new.invoice_id, v_total_alloc, v_owed using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_payment_alloc on public.payments;
create trigger trg_guard_payment_alloc
  before insert or update on public.payments
  for each row execute function app_util.guard_payment_allocation();

-- 6g. New EMI rows can never arrive already-paid by accident; the schedule is
--     generated, then paid through record_payment (SS16).
create or replace function app_util.guard_emi_line()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception '[CON001] EMI instalments are never deleted; cancel the loan instead'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_emi on public.emi_schedules;
create trigger trg_guard_emi
  before insert or update or delete on public.emi_schedules
  for each row execute function app_util.guard_emi_line();
