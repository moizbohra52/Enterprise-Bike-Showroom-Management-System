-- =============================================================================
-- 011_reporting_views.sql  (SS25, SS51)
-- -----------------------------------------------------------------------------
-- Read-optimised SQL views.  Every view is created WITH (security_invoker =
-- true) so the base tables' RLS still applies - a view must never become a
-- hole in tenant isolation.
--
-- Rule from SS51: these aggregate over transactional tables; nothing here is
-- materialised twice, so a report can never disagree with its source document.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Sales
-- ---------------------------------------------------------------------------
create or replace view public.daily_sales_summary
with (security_invoker = true) as
select s.showroom_id,
       sh.name as showroom_name,
       s.sale_date as day,
       count(*)                                   as sale_count,
       count(*) filter (where s.status = 'DELIVERED')  as delivered_count,
       count(*) filter (where s.status = 'CANCELLED')  as cancelled_count,
       round(coalesce(sum(s.subtotal), 0), 2)          as subtotal,
       round(coalesce(sum(s.discount), 0), 2)          as discount,
       round(coalesce(sum(s.tax_amount), 0), 2)        as tax_amount,
       round(coalesce(sum(s.other_charges), 0), 2)     as other_charges,
       round(coalesce(sum(s.total_amount), 0), 2)      as gross_amount,
       round(coalesce(sum(s.paid_amount), 0), 2)       as collected_amount,
       round(coalesce(sum(s.outstanding_amount), 0), 2) as outstanding_amount,
       jsonb_object_agg(s.sale_type, s.total_amount) filter (where s.sale_type is not null)
         as by_sale_type
  from public.sales s
  join public.showrooms sh on sh.id = s.showroom_id
 where s.status <> 'RETURNED'
 group by s.showroom_id, sh.name, s.sale_date;

create or replace view public.monthly_sales_summary
with (security_invoker = true) as
select s.showroom_id,
       sh.name as showroom_name,
       date_trunc('month', s.sale_date)::date as month,
       to_char(date_trunc('month', s.sale_date), 'YYYY-MM') as month_key,
       count(*) as sale_count,
       round(coalesce(sum(s.total_amount), 0), 2) as gross_amount,
       round(coalesce(sum(s.paid_amount), 0), 2)  as collected_amount,
       round(coalesce(sum(s.outstanding_amount), 0), 2) as outstanding_amount,
       round(coalesce(sum(s.discount), 0), 2)     as discount,
       round(coalesce(sum(s.tax_amount), 0), 2)   as tax_amount,
       count(distinct s.customer_id) as customers,
       count(distinct s.salesperson_id) as salespeople,
       round(coalesce(avg(s.total_amount), 0), 2) as average_ticket
  from public.sales s
  join public.showrooms sh on sh.id = s.showroom_id
 where s.status not in ('CANCELLED','RETURNED')
 group by 1, 2, 3, 4;

-- Units sold per product: the stock-vs-demand chart on the dashboard
create or replace view public.sales_trend_by_product
with (security_invoker = true) as
select si.product_id, p.name as product_name, b.name as brand_name,
       date_trunc('month', s.sale_date)::date as month,
       sum(si.quantity) as units_sold,
       round(coalesce(sum(si.total_amount), 0), 2) as revenue,
       round(coalesce(sum(si.discount), 0), 2)      as discount_given
  from public.sale_items si
  join public.sales s on s.id = si.sale_id and s.status not in ('CANCELLED','RETURNED')
  join public.products p on p.id = si.product_id
  join public.brands b on b.id = p.brand_id
 group by 1, 2, 3, 4;

-- ---------------------------------------------------------------------------
-- Payments / collections
-- ---------------------------------------------------------------------------
create or replace view public.payment_method_distribution
with (security_invoker = true) as
select p.showroom_id, p.payment_method,
       date_trunc('month', p.payment_date)::date as month,
       count(*) as txn_count,
       round(coalesce(sum(p.amount), 0), 2) as amount,
       round(coalesce(sum(p.allocated_amount), 0), 2) as applied_amount,
       round(coalesce(sum(p.amount - p.allocated_amount), 0), 2) as credit_balance
  from public.payments p
 where p.status = 'COMPLETED'
 group by 1, 2, 3;

create or replace view public.collection_summary
with (security_invoker = true) as
select p.showroom_id, p.payment_date as day,
       round(coalesce(sum(p.amount) filter (where p.payment_type = 'RECEIPT'), 0), 2) as receipts,
       round(coalesce(sum(p.amount) filter (where p.payment_type = 'REFUND'), 0), 2)  as refunds,
       round(coalesce(sum(p.amount) filter (where p.payment_type = 'RECEIPT'), 0)
           - coalesce(sum(p.amount) filter (where p.payment_type = 'REFUND'), 0), 2)  as net_collection,
       count(*) as txn_count
  from public.payments p
 where p.status in ('COMPLETED','REFUNDED')
 group by 1, 2;

-- ---------------------------------------------------------------------------
-- Receivables
-- ---------------------------------------------------------------------------
create or replace view public.customer_outstanding_summary
with (security_invoker = true) as
select c.id as customer_id, c.showroom_id, c.customer_code, c.name, c.phone, c.city,
       c.customer_type,
       round(coalesce(sum(i.outstanding_amount) filter
             (where i.status in ('FINALIZED','PARTIALLY_PAID','OVERDUE')), 0), 2) as invoice_outstanding,
       round(coalesce(sum(e.remaining_amount) filter
             (where e.status in ('OVERDUE','DUE','PARTIAL')), 0), 2)               as emi_outstanding,
       round(coalesce(sum(s.outstanding_amount) filter
             (where s.status not in ('CANCELLED','RETURNED')), 0), 2)              as sale_outstanding,
       round(coalesce(sum(sr.outstanding_amount) filter
             (where sr.service_status in ('COMPLETED','DELIVERED')), 0), 2)       as service_outstanding,
       round(coalesce(sum(p.amount - p.allocated_amount) filter
             (where p.status = 'COMPLETED' and p.payment_type in ('RECEIPT','ADVANCE')), 0), 2)
                                                                                   as advance_balance,
       max(i.due_date) filter (where i.outstanding_amount > 0)                     as oldest_due_date,
       count(i.id) filter (where i.outstanding_amount > 0)                         as open_invoice_count,
       greatest(
         round(coalesce(sum(i.outstanding_amount) filter
               (where i.status in ('FINALIZED','PARTIALLY_PAID','OVERDUE')), 0), 2), 0)
         + round(coalesce(sum(sr.outstanding_amount) filter
               (where sr.service_status in ('COMPLETED','DELIVERED')), 0), 2)      as total_receivable
  from public.customers c
  left join public.invoices i        on i.customer_id = c.id
  left join public.emi_schedules e   on e.customer_id = c.id
  left join public.sales s           on s.customer_id = c.id
  left join public.service_records sr on sr.customer_id = c.id
  left join public.payments p        on p.customer_id = c.id
 where c.is_deleted = false
 group by 1, 2, 3, 4, 5, 6, 7;

-- ---------------------------------------------------------------------------
-- EMI
-- ---------------------------------------------------------------------------
create or replace view public.emi_due_summary
with (security_invoker = true) as
select e.id as emi_id, e.showroom_id, e.customer_id, c.name as customer_name, c.phone,
       e.loan_id, l.loan_number, fc.name as finance_company, e.emi_number,
       e.due_date, e.emi_amount, e.paid_amount, e.remaining_amount, e.status,
       greatest(0, (current_date - e.due_date)) as days_past_due,
       e.due_date < current_date as is_overdue
  from public.emi_schedules e
  join public.customers c on c.id = e.customer_id
  join public.loans l on l.id = e.loan_id
  left join public.finance_companies fc on fc.id = l.finance_company_id
 where e.status in ('UPCOMING','DUE','PARTIAL','OVERDUE');

create or replace view public.emi_overdue_summary
with (security_invoker = true) as
select * from public.emi_due_summary d where d.is_overdue;

create or replace view public.emi_collection_summary
with (security_invoker = true) as
select e.showroom_id,
       date_trunc('month', e.paid_date)::date as month,
       count(*) as instalments_collected,
       round(coalesce(sum(e.paid_amount), 0), 2) as collected,
       round(coalesce(sum((p.metadata ->> 'interestPart')::numeric), 0), 2) as interest_component
  from public.emi_schedules e
  left join public.payments p on p.id = e.paid_via_payment_id
 where e.status = 'PAID' and e.paid_date is not null
 group by 1, 2;

-- Open exposure per loan: what the dealership is still on the hook to collect
create or replace view public.loan_exposure_summary
with (security_invoker = true) as
select l.id as loan_id, l.showroom_id, l.loan_number, l.customer_id, c.name as customer_name,
       l.finance_company_id, fc.name as finance_company, l.loan_amount, l.emi_amount,
       l.tenure_months, l.interest_rate, l.status, l.start_date, l.end_date,
       count(e.id) filter (where e.status <> 'PAID') as pending_instalments,
       round(coalesce(sum(e.remaining_amount) filter (where e.status <> 'PAID'), 0), 2) as balance_outstanding,
       round(coalesce(sum(e.remaining_amount) filter (where e.status = 'OVERDUE'), 0), 2) as overdue_amount,
       min(e.due_date) filter (where e.status in ('DUE','PARTIAL','OVERDUE')) as next_due_date
  from public.loans l
  join public.customers c on c.id = l.customer_id
  left join public.finance_companies fc on fc.id = l.finance_company_id
  left join public.emi_schedules e on e.loan_id = l.id
 group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14;

-- ---------------------------------------------------------------------------
-- Workshop
-- ---------------------------------------------------------------------------
create or replace view public.service_revenue_summary
with (security_invoker = true) as
select r.showroom_id, r.service_date as day,
       count(*) as job_count,
       count(*) filter (where r.service_type = 'FREE')    as free_jobs,
       count(*) filter (where r.service_type = 'PAID')     as paid_jobs,
       count(*) filter (where r.service_type = 'WARRANTY') as warranty_jobs,
       round(coalesce(sum(r.total_amount), 0), 2)          as billed_amount,
       round(coalesce(sum(r.paid_amount), 0), 2)           as collected_amount,
       round(coalesce(sum(r.outstanding_amount), 0), 2)    as outstanding_amount,
       round(coalesce(sum(r.parts_charges), 0), 2)         as parts_revenue,
       round(coalesce(sum(r.labour_charges), 0), 2)        as labour_revenue,
       round(coalesce(sum(r.discount), 0), 2)              as discount_given
  from public.service_records r
 where r.service_status in ('COMPLETED','DELIVERED')
 group by 1, 2;

create or replace view public.free_service_status
with (security_invoker = true) as
select f.id, f.vehicle_id, cv.registration_number, cv.chassis_number,
       c.name as customer_name, c.phone, f.showroom_id, f.service_number,
       f.due_date, f.due_km, f.status, f.used_date, f.odometer_at_use,
       coalesce(cv.current_odometer, 0) as current_odometer,
       greatest(f.due_km - coalesce(cv.current_odometer, 0), 0) as km_remaining,
       (f.due_date - current_date) as days_remaining,
       (f.due_date < current_date or coalesce(cv.current_odometer,0) > f.due_km) as is_lapsed
  from public.vehicle_free_services f
  join public.customer_vehicles cv on cv.id = f.vehicle_id
  join public.customers c on c.id = f.customer_id;

-- ---------------------------------------------------------------------------
-- Stock
-- ---------------------------------------------------------------------------
create or replace view public.inventory_summary
with (security_invoker = true) as
select i.showroom_id, sh.name as showroom_name, i.product_id,
       b.name as brand_name, p.name as product_name, p.variant,
       count(*) as total_units,
       count(*) filter (where i.status = 'AVAILABLE')  as available_units,
       count(*) filter (where i.status = 'RESERVED')   as reserved_units,
       count(*) filter (where i.status = 'SOLD')       as sold_units,
       count(*) filter (where i.status = 'IN_TRANSIT') as in_transit_units,
       count(*) filter (where i.status = 'DEMO')       as demo_units,
       count(*) filter (where i.status = 'DAMAGED')    as damaged_units,
       count(*) filter (where i.status = 'PENDING_RC') as pending_rc_units,
       round(coalesce(sum(i.purchase_price) filter (where i.status <> 'SOLD'), 0), 2) as stock_value,
       round(coalesce(sum(i.mrp) filter (where i.status = 'AVAILABLE'), 0), 2)        as stock_mrp_value,
       min(i.purchase_date) as oldest_stock_date,
       max(i.created_at) as last_received_at
  from public.inventory i
  join public.showrooms sh on sh.id = i.showroom_id
  join public.products p on p.id = i.product_id
  join public.brands b on b.id = p.brand_id
 where i.is_deleted = false
 group by 1, 2, 3, 4, 5, 6;

create or replace view public.low_stock_alerts
with (security_invoker = true) as
with thresholds as (
  select coalesce(
           nullif((s.settings ->> 'low_stock_threshold')::int, 0),
           2) as min_available, s.id as showroom_id
    from public.showrooms s
)
select s.showroom_id, sh.name as showroom_name, s.product_id,
       b.name || ' ' || p.name as product_label, s.available_units, t.min_available
  from public.inventory_summary s
  join thresholds t on t.showroom_id = s.showroom_id
  join public.showrooms sh on sh.id = s.showroom_id
  join public.products p on p.id = s.product_id
  join public.brands b on b.id = p.brand_id
 where s.available_units <= t.min_available
 order by s.available_units, product_label;

create or replace view public.stock_valuation_by_showroom
with (security_invoker = true) as
select i.showroom_id, sh.name as showroom_name,
       count(*) as units_on_ground,
       round(coalesce(sum(i.purchase_price) filter (where i.status in ('AVAILABLE','RESERVED','DEMO','PENDING_RC')), 0), 2) as held_at_cost,
       round(coalesce(sum(i.landing_price), 0), 2) as landed_value,
       round(coalesce(sum(p.selling_price - i.purchase_price) filter
             (where i.status in ('AVAILABLE','RESERVED')), 0), 2) as unrealised_margin
  from public.inventory i
  join public.showrooms sh on sh.id = i.showroom_id
  join public.products p on p.id = i.product_id
 where i.is_deleted = false and i.status <> 'SOLD'
 group by 1, 2;

-- ---------------------------------------------------------------------------
-- Purchases / expenses
-- ---------------------------------------------------------------------------
create or replace view public.purchase_summary
with (security_invoker = true) as
select pu.showroom_id, sh.name as showroom_name, pu.supplier_id, s.name as supplier_name,
       date_trunc('month', pu.purchase_date)::date as month,
       count(*) as purchase_count,
       round(coalesce(sum(pu.total_amount), 0), 2)     as purchase_value,
       round(coalesce(sum(pu.paid_amount), 0), 2)       as paid_value,
       round(coalesce(sum(pu.outstanding_amount), 0), 2) as supplier_payable,
       round(coalesce(sum(pu.tax_amount), 0), 2)        as input_tax,
       sum(pi.quantity) filter (where pu.status in ('RECEIVED','PARTIAL_RECEIVED')) as units_ordered,
       coalesce(sum(pi.received_quantity), 0) as units_received
  from public.purchases pu
  join public.showrooms sh on sh.id = pu.showroom_id
  join public.suppliers s on s.id = pu.supplier_id
  left join public.purchase_items pi on pi.purchase_id = pu.id
 where pu.status <> 'CANCELLED'
 group by 1, 2, 3, 4, 5;

create or replace view public.expense_summary
with (security_invoker = true) as
select e.showroom_id, sh.name as showroom_name, e.category_id, ec.name as category_name,
       e.financial_year,
       date_trunc('month', e.expense_date)::date as month,
       count(*) as expense_count,
       round(coalesce(sum(e.amount), 0), 2)      as net_amount,
       round(coalesce(sum(e.tax_amount), 0), 2)  as tax_amount,
       round(coalesce(sum(e.total_amount), 0), 2) as gross_amount,
       round(coalesce(sum(e.total_amount) filter (where e.status = 'PENDING'), 0), 2) as pending_amount,
       round(coalesce(sum(e.total_amount) filter (where e.status in ('APPROVED','PAID')), 0), 2) as approved_amount
  from public.expenses e
  join public.showrooms sh on sh.id = e.showroom_id
  join public.expense_categories ec on ec.id = e.category_id
 where e.status <> 'CANCELLED'
 group by 1, 2, 3, 4, 5, 6;

-- ---------------------------------------------------------------------------
-- Profit & loss, financial summary (SS25)
-- ---------------------------------------------------------------------------
create or replace view public.account_balances
with (security_invoker = true) as
select a.showroom_id, sh.name as showroom_name, a.id as account_id, a.account_code,
       a.account_name, a.account_type, a.normal_balance,
       round(coalesce(sum(e.debit), 0), 2)  as total_debit,
       round(coalesce(sum(e.credit), 0), 2) as total_credit,
       round(max(a.opening_balance)
             + coalesce(sum(case when a.normal_balance = 'DEBIT'
                                 then e.debit - e.credit else e.credit - e.debit end), 0), 2)
         as net_balance_signed,
       count(distinct t.id) as journal_count
  from public.accounts a
  join public.showrooms sh on sh.id = a.showroom_id
  -- The status test has to sit on the join that brings the ENTRIES in.  Filtering
  -- it on the outer join to transactions instead leaves every draft and every
  -- reversed journal in the sums, and a "balance" that silently ignores its own
  -- where clause is worse than no balance at all.
  left join (public.accounting_entries e
             join public.accounting_transactions t
               on t.id = e.transaction_id
              and t.status in ('POSTED','REVERSED'))   -- booked entries, reversals included
         on e.account_id = a.id
 where a.is_group = false
 group by 1, 2, 3, 4, 5, 6, 7;

create or replace view public.profit_and_loss
with (security_invoker = true) as
select ab.showroom_id, ab.showroom_name, ab.account_type, ab.account_code, ab.account_name,
       case ab.account_type
         when 'INCOME' then ab.total_credit - ab.total_debit
         else ab.total_debit - ab.total_credit
       end as amount
  from public.account_balances ab
 where ab.account_type in ('INCOME','EXPENSE');

create or replace view public.financial_summary
with (security_invoker = true) as
select ab.showroom_id, ab.showroom_name,
       round(coalesce(sum(ab.amount) filter (where ab.account_type = 'INCOME'), 0), 2)  as total_income,
       round(coalesce(sum(ab.amount) filter (where ab.account_type = 'EXPENSE'), 0), 2) as total_expense,
       round(coalesce(sum(ab.amount) filter (where ab.account_type = 'INCOME'), 0)
           - coalesce(sum(ab.amount) filter (where ab.account_type = 'EXPENSE'), 0), 2) as net_profit,
       round(coalesce(sum(case ab.account_type when 'ASSET' then ab.amount else -ab.amount end)
             filter (where ab.account_type in ('ASSET','LIABILITY')), 0), 2) as equity_estimate
  from public.profit_and_loss ab
 group by 1, 2;

-- ---------------------------------------------------------------------------
-- Showroom summary: one row per branch for the group-level dashboard
-- ---------------------------------------------------------------------------
create or replace view public.showroom_summary
with (security_invoker = true) as
select sh.id as showroom_id, sh.name, sh.code, sh.city, sh.state, sh.status,
       (select count(*) from public.users u where u.showroom_id = sh.id and u.is_deleted = false) as user_count,
       (select count(*) from public.customers c where c.showroom_id = sh.id and c.is_deleted = false) as customer_count,
       (select count(*) from public.inventory i where i.showroom_id = sh.id and i.status = 'AVAILABLE') as available_stock,
       (select round(coalesce(sum(s.total_amount),0),2) from public.sales s
         where s.showroom_id = sh.id and s.status not in ('CANCELLED','RETURNED')) as lifetime_sales,
       (select round(coalesce(sum(s.total_amount),0),2) from public.sales s
         where s.showroom_id = sh.id and s.status not in ('CANCELLED','RETURNED')
           and s.sale_date >= date_trunc('month', current_date)) as month_sales,
       (select round(coalesce(sum(i.outstanding_amount),0),2) from public.invoices i
         where i.showroom_id = sh.id and i.status in ('FINALIZED','PARTIALLY_PAID','OVERDUE')) as outstanding,
       (select round(coalesce(sum(e.remaining_amount),0),2) from public.emi_schedules e
         where e.showroom_id = sh.id and e.status in ('DUE','PARTIAL','OVERDUE')) as emi_overdue,
       (select count(*) from public.service_records r
         where r.showroom_id = sh.id and r.service_status in ('BOOKED','RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS')) as open_jobs,
       (select round(coalesce(sum(r.total_amount),0),2) from public.service_records r
         where r.showroom_id = sh.id and r.service_status in ('COMPLETED','DELIVERED')
           and date_trunc('month', r.service_date) = date_trunc('month', current_date)) as month_service_revenue,
       (select round(coalesce(sum(x.total_amount),0),2) from public.expenses x
         where x.showroom_id = sh.id and x.status in ('APPROVED','PAID')
           and date_trunc('month', x.expense_date) = date_trunc('month', current_date)) as month_expenses
  from public.showrooms sh;

-- ---------------------------------------------------------------------------
-- Reminders / warranties / insurance dashboards (SS17, SS20, SS21)
-- ---------------------------------------------------------------------------
create or replace view public.reminder_calendar
with (security_invoker = true) as
select r.id, r.showroom_id, sh.name as showroom_name, r.customer_id, c.name as customer_name,
       c.phone, r.vehicle_id, cv.registration_number, r.reminder_type, r.title, r.message,
       r.reminder_date, r.reminder_time,
       -- interpreted in the showroom's own timezone, which is what the staff mean
       -- when they say "tomorrow 9:30"
       (r.reminder_date + r.reminder_time) at time zone
         coalesce(sh.timezone, 'Asia/Kolkata')                           as due_at,
       r.priority, r.status, r.channel, r.reference_type, r.reference_id,
       (r.reminder_date - current_date) as days_to_go,
       (r.reminder_date < current_date and r.status = 'PENDING') as is_overdue
  from public.reminders r
  left join public.showrooms sh on sh.id = r.showroom_id
  left join public.customers c on c.id = r.customer_id
  left join public.customer_vehicles cv on cv.id = r.vehicle_id;

create or replace view public.expiry_watchlist
with (security_invoker = true) as
select 'INSURANCE'::text as kind, i.showroom_id, i.customer_id, c.name as customer_name,
       c.phone, i.vehicle_id, cv.registration_number, i.expiry_date as expiry,
       (i.expiry_date - current_date) as days_left, i.policy_number as reference,
       i.status
  from public.insurance_policies i
  join public.customers c on c.id = i.customer_id
  left join public.customer_vehicles cv on cv.id = i.vehicle_id
 where i.status in ('ACTIVE','EXPIRING_SOON','LAPSED')
union all
select 'WARRANTY', w.showroom_id, w.customer_id, c.name, c.phone, w.vehicle_id,
       cv.registration_number, w.end_date, (w.end_date - current_date), w.warranty_number, w.status
  from public.warranties w
  join public.customers c on c.id = w.customer_id
  left join public.customer_vehicles cv on cv.id = w.vehicle_id
 where w.status = 'ACTIVE'
union all
select 'FREE_SERVICE', f.showroom_id, f.customer_id, c.name, c.phone, f.vehicle_id,
       cv.registration_number, f.due_date, (f.due_date - current_date),
       'Free service ' || f.service_number, f.status
  from public.vehicle_free_services f
  join public.customers c on c.id = f.customer_id
  left join public.customer_vehicles cv on cv.id = f.vehicle_id
 where f.status in ('UPCOMING','BOOKED')
union all
select 'RC_TRANSFER', v.showroom_id, v.customer_id, c.name, c.phone, v.id,
       v.registration_number, (v.purchase_date + interval '730 days')::date,
       ((v.purchase_date + interval '730 days')::date - current_date),
       'RC transfer due', 'PENDING'
  from public.customer_vehicles v
  join public.customers c on c.id = v.customer_id
 where v.is_deleted = false
   and (v.purchase_date + interval '730 days')::date between current_date and current_date + 90
order by days_left;

-- ---------------------------------------------------------------------------
-- Documents: what exists where (SS70 Documents screen)
-- ---------------------------------------------------------------------------
create or replace view public.document_index
with (security_invoker = true) as
select a.id, a.showroom_id, sh.name as showroom_name, a.entity_type, a.entity_id,
       a.file_name, a.bucket_id, a.file_path, a.file_type, a.mime_type, a.file_size,
       a.visibility, a.is_primary, a.watermark_enabled, a.created_at,
       u.name as uploaded_by_name,
       case a.entity_type
         when 'customer'   then (select c.name from public.customers c where c.id = a.entity_id)
         when 'sale'       then (select s.sale_number from public.sales s where s.id = a.entity_id)
         when 'invoice'    then (select i.invoice_number from public.invoices i where i.id = a.entity_id)
         when 'service'    then (select r.service_number from public.service_records r where r.id = a.entity_id)
         when 'expense'    then (select x.expense_number from public.expenses x where x.id = a.entity_id)
         when 'purchase'   then (select p.purchase_number from public.purchases p where p.id = a.entity_id)
         when 'product'    then (select p.name from public.products p where p.id = a.entity_id)
         when 'insurance'  then (select i.policy_number from public.insurance_policies i where i.id = a.entity_id)
         when 'warranty'   then (select w.warranty_number from public.warranties w where w.id = a.entity_id)
       end as entity_label
  from public.attachments a
  left join public.showrooms sh on sh.id = a.showroom_id
  left join public.users u on u.id = a.uploaded_by;
