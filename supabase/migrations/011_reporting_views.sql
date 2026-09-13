-- 011_reporting_views.sql
-- Reporting views consumed by ReportCatalog (lib/features/reports). The
-- repository selects from any source ending in `_summary` or `_view`, so
-- every view exposes showroom_id for the showroom filter.

create or replace view public.daily_sales_summary as
select
  s.sale_date,
  s.showroom_id,
  sr.name                                   as showroom_name,
  count(*)::int                             as sales_count,
  sum(s.total_amount)                       as total_amount,
  sum(s.paid_amount)                        as paid_amount,
  sum(s.balance_amount)                     as balance_amount
from public.sales s
join public.showrooms sr on sr.id = s.showroom_id
where s.status <> 'cancelled'
group by s.sale_date, s.showroom_id, sr.name;

create or replace view public.monthly_sales_summary as
select
  date_trunc('month', s.sale_date)::date    as month,
  s.showroom_id,
  sr.name                                   as showroom_name,
  count(*)::int                             as sales_count,
  sum(s.total_amount)                       as total_amount
from public.sales s
join public.showrooms sr on sr.id = s.showroom_id
where s.status <> 'cancelled'
group by 1, s.showroom_id, sr.name;

create or replace view public.showroom_profit_summary as
select
  sr.id                                     as showroom_id,
  sr.name                                   as showroom_name,
  coalesce(rev.revenue, 0)                  as revenue,
  coalesce(cogs.cost_of_goods, 0)           as cost_of_goods,
  coalesce(exp.expenses, 0)                 as expenses,
  coalesce(rev.revenue, 0)
    - coalesce(cogs.cost_of_goods, 0)
    - coalesce(exp.expenses, 0)             as profit
from public.showrooms sr
left join (
  select showroom_id, sum(total_amount) as revenue
    from public.sales where status <> 'cancelled' group by showroom_id
) rev on rev.showroom_id = sr.id
left join (
  select s.showroom_id,
         sum(si.qty * coalesce(inv.purchase_price, 0)) as cost_of_goods
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    left join public.inventory inv on inv.id = si.inventory_id
   where s.status <> 'cancelled'
   group by s.showroom_id
) cogs on cogs.showroom_id = sr.id
left join (
  select showroom_id, sum(amount) as expenses
    from public.expenses where status = 'approved' group by showroom_id
) exp on exp.showroom_id = sr.id;

create or replace view public.customer_outstanding_summary as
select
  c.id                                      as customer_id,
  c.showroom_id,
  c.name                                    as customer_name,
  c.phone,
  coalesce(sum(i.outstanding_amount), 0)    as outstanding_amount,
  count(i.id)::int                          as open_invoices
from public.customers c
left join public.invoices i
  on i.customer_id = c.id and i.status in ('unpaid', 'partial', 'overdue')
group by c.id, c.showroom_id, c.name, c.phone;

create or replace view public.emi_due_summary as
select
  l.showroom_id,
  l.id                                      as loan_id,
  l.loan_number,
  c.name                                    as customer_name,
  c.phone,
  e.installment_no,
  e.due_date,
  e.emi_amount,
  e.emi_amount - coalesce(e.paid_amount, 0) as due_amount
from public.emi_schedules e
join public.loans l on l.id = e.loan_id
join public.customers c on c.id = l.customer_id
where e.status in ('pending', 'partial')
  and e.due_date <= current_date + 7;

create or replace view public.emi_overdue_summary as
select
  l.showroom_id,
  l.id                                      as loan_id,
  l.loan_number,
  c.name                                    as customer_name,
  c.phone,
  e.installment_no,
  e.due_date,
  (current_date - e.due_date)::int          as days_overdue,
  e.emi_amount - coalesce(e.paid_amount, 0) as overdue_amount
from public.emi_schedules e
join public.loans l on l.id = e.loan_id
join public.customers c on c.id = l.customer_id
where e.status in ('pending', 'partial', 'overdue')
  and e.due_date < current_date;

create or replace view public.service_revenue_summary as
select
  r.showroom_id,
  date_trunc('month', coalesce(r.service_date, r.booking_date))::date as month,
  r.job_type,
  count(*)::int                             as jobs,
  sum(r.total_amount)                       as total_amount,
  sum(r.paid_amount)                        as paid_amount
from public.service_records r
where r.status in ('completed', 'delivered')
group by 1, 2, r.job_type;

create or replace view public.inventory_summary as
select
  i.showroom_id,
  i.product_id,
  p.name                                    as product_name,
  count(*) filter (where i.status = 'available')::int    as in_stock,
  count(*) filter (where i.status = 'reserved')::int    as reserved,
  count(*) filter (where i.status = 'sold')::int        as sold,
  count(*)::int                             as total_units,
  sum(i.purchase_price) filter (where i.status = 'available') as stock_value
from public.inventory i
join public.products p on p.id = i.product_id
group by i.showroom_id, i.product_id, p.name;

create or replace view public.stock_valuation_view as
select
  i.showroom_id,
  sr.name                                   as showroom_name,
  count(*)::int                             as units,
  coalesce(sum(i.purchase_price), 0)        as purchase_value,
  coalesce(sum(p.selling_price), 0)         as retail_value
from public.inventory i
join public.products p on p.id = i.product_id
join public.showrooms sr on sr.id = i.showroom_id
where i.status in ('available', 'reserved')
group by i.showroom_id, sr.name;

create or replace view public.purchase_summary as
select
  p.showroom_id,
  date_trunc('month', p.order_date)::date   as month,
  s.name                                    as supplier_name,
  count(*)::int                             as purchases,
  sum(p.total_amount)                       as total_amount,
  sum(p.outstanding_amount)                 as outstanding_amount
from public.purchases p
join public.suppliers s on s.id = p.supplier_id
where p.status <> 'cancelled'
group by 1, 2, s.name;

create or replace view public.expense_summary as
select
  e.showroom_id,
  date_trunc('month', e.date)::date         as month,
  c.name                                    as category_name,
  count(*)::int                             as entries,
  sum(e.amount)                             as total_amount
from public.expenses e
join public.expense_categories c on c.id = e.category_id
where e.status in ('approved', 'pending')
group by 1, 2, c.name;

-- Profit & loss (revenue vs. cost vs. expense) per showroom and month.
create or replace view public.pnl_view as
select
  sr.id                                     as showroom_id,
  sr.name                                   as showroom_name,
  m.month,
  coalesce(sales.revenue, 0)                as revenue,
  coalesce(services.service_revenue, 0)     as service_revenue,
  coalesce(exp.expenses, 0)                 as expenses,
  coalesce(sales.revenue, 0)
    + coalesce(services.service_revenue, 0)
    - coalesce(exp.expenses, 0)             as net
from public.showrooms sr
cross join (
  select distinct date_trunc('month', sale_date)::date as month
    from public.sales
) m
left join (
  select showroom_id, date_trunc('month', sale_date)::date as month,
         sum(total_amount) as revenue
    from public.sales where status <> 'cancelled'
   group by 1, 2
) sales on sales.showroom_id = sr.id and sales.month = m.month
left join (
  select showroom_id,
         date_trunc('month', coalesce(service_date, booking_date))::date as month,
         sum(total_amount) as service_revenue
    from public.service_records
   where status in ('completed', 'delivered')
   group by 1, 2
) services on services.showroom_id = sr.id and services.month = m.month
left join (
  select showroom_id, date_trunc('month', date)::date as month,
         sum(amount) as expenses
    from public.expenses where status = 'approved'
   group by 1, 2
) exp on exp.showroom_id = sr.id and exp.month = m.month;

-- Reports are read-only; RLS on the underlying tables still applies through
-- the view owner, so expose them to authenticated users explicitly.
grant select on all tables in schema public to authenticated;
alter default privileges in schema public
  grant select on tables to authenticated;

-- Customer list source used by CustomerRepository.list: customers plus the
-- derived `outstanding` and `vehicle_count` columns the model expects.
create or replace view public.customers_with_summary as
select
  c.*,
  coalesce(inv.outstanding, 0)              as outstanding,
  coalesce(veh.vehicle_count, 0)::int       as vehicle_count
from public.customers c
left join (
  select customer_id, sum(outstanding_amount) as outstanding
    from public.invoices
   where status in ('unpaid', 'partial', 'overdue')
   group by customer_id
) inv on inv.customer_id = c.id
left join (
  select customer_id, count(*) as vehicle_count
    from public.customer_vehicles
   group by customer_id
) veh on veh.customer_id = c.id;

-- `audit_log` is the name AuditRepository queries; audit_logs holds the rows.
create or replace view public.audit_log as
select
  a.id,
  a.showroom_id,
  a.user_id,
  a.user_name,
  a.module,
  a.action,
  a.entity_type,
  a.entity_id,
  a.old_values,
  a.new_values,
  a.ip_address,
  a.user_agent,
  a.notes,
  a.created_at
from public.audit_logs a;
