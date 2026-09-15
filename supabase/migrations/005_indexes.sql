-- =============================================================================
-- 005_indexes.sql
-- -----------------------------------------------------------------------------
-- Purpose : the index set required by SS47 - every filter, sort and join path
--           the UI exposes is backed, plus covering indexes for the report and
--           dashboard queries in 011_reporting_views.sql.
-- Depends : 002, 003, 004 (all tables exist).
-- Note    : single-column indexes that live next to their table definition are
--           not repeated here; this file is only the *cross-cutting* set.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Tenant + status (the single hottest filter pair in the app)
-- ---------------------------------------------------------------------------
create index if not exists idx_customers_shr_status     on public.customers (showroom_id, status, created_at desc);
create index if not exists idx_sales_shr_status         on public.sales (showroom_id, status, sale_date desc);
create index if not exists idx_invoices_shr_status      on public.invoices (showroom_id, status, invoice_date desc);
create index if not exists idx_payments_shr_status      on public.payments (showroom_id, status, payment_date desc);
create index if not exists idx_purchases_shr_status     on public.purchases (showroom_id, status, purchase_date desc);
create index if not exists idx_expenses_shr_status      on public.expenses (showroom_id, status, expense_date desc);
create index if not exists idx_services_shr_status      on public.service_records (showroom_id, service_status, service_date desc);
create index if not exists idx_loans_shr_status         on public.loans (showroom_id, status, start_date);
create index if not exists idx_emis_shr_due_status      on public.emi_schedules (showroom_id, status, due_date);
create index if not exists idx_reminders_shr_status     on public.reminders (showroom_id, status, reminder_date, reminder_time);
create index if not exists idx_notif_shr_read           on public.notifications (showroom_id, is_read, created_at desc);

-- ---------------------------------------------------------------------------
-- Date-range scans used by every report (SS25, SS26)
-- ---------------------------------------------------------------------------
create index if not exists idx_sales_date_brin          on public.sales using brin (sale_date);
create index if not exists idx_invoices_date_brin       on public.invoices using brin (invoice_date);
create index if not exists idx_payments_date_brin       on public.payments using brin (payment_date);
create index if not exists idx_expenses_date_brin       on public.expenses using brin (expense_date);
create index if not exists idx_services_date_brin       on public.service_records using brin (service_date);
create index if not exists idx_purchases_date_brin      on public.purchases using brin (purchase_date);

-- covering indexes so the list screens never touch the heap
create index if not exists idx_sales_list_cover         on public.sales (showroom_id, sale_date desc)
  include (customer_id, total_amount, paid_amount, outstanding_amount, status, sale_type);
create index if not exists idx_invoices_list_cover      on public.invoices (showroom_id, invoice_date desc)
  include (customer_id, total_amount, paid_amount, outstanding_amount, status, invoice_type);
create index if not exists idx_payments_list_cover      on public.payments (showroom_id, payment_date desc)
  include (customer_id, amount, payment_method, status, payment_type);
create index if not exists idx_customers_list_cover     on public.customers (showroom_id, created_at desc)
  include (name, phone, customer_code, city, status, customer_type);
create index if not exists idx_inventory_list_cover     on public.inventory (showroom_id, status, created_at desc)
  include (product_id, color_id, stock_code, chassis_number, engine_number);

-- ---------------------------------------------------------------------------
-- Join-path indexes (FK -> parent) for the 360 views and the timeline
-- ---------------------------------------------------------------------------
create index if not exists idx_saleitems_sale           on public.sale_items (sale_id);
create index if not exists idx_invoiceitems_invoice     on public.invoice_items (invoice_id);
create index if not exists idx_emis_loan                on public.emi_schedules (loan_id);
create index if not exists idx_serviceitems_service     on public.service_items (service_id);
create index if not exists idx_purchaseitems_purchase   on public.purchase_items (purchase_id);
create index if not exists idx_accentries_tx            on public.accounting_entries (transaction_id);
create index if not exists idx_accentries_account       on public.accounting_entries (account_id);
create index if not exists idx_acc_tx_shr_date          on public.accounting_transactions (showroom_id, transaction_date desc);
create index if not exists idx_veh_customer_active      on public.customer_vehicles (customer_id, status) where is_deleted = false;

-- ---------------------------------------------------------------------------
-- Lookup / search paths (SS71 global search)
-- ---------------------------------------------------------------------------
create index if not exists idx_customers_phone_digits   on public.customers (app_util.normalise_phone(phone));
create index if not exists idx_customers_email_lower    on public.customers (lower(email));
create index if not exists idx_vehicles_reg_upper       on public.customer_vehicles (registration_number);
create index if not exists idx_inventory_chassis        on public.inventory (chassis_number);
create index if not exists idx_inventory_engine         on public.inventory (engine_number);
create index if not exists idx_invoices_number_trgm     on public.invoices (invoice_number);
create index if not exists idx_sales_number_idx         on public.sales (sale_number);
create index if not exists idx_payments_number_idx      on public.payments (payment_number);
create index if not exists idx_loans_number_idx         on public.loans (loan_number);
create index if not exists idx_services_number_idx      on public.service_records (service_number);

call app_util.create_optional_index(
  'create index if not exists idx_customers_name_trgm  on public.customers using gin (name gin_trgm_ops)', 'pg_trgm');
call app_util.create_optional_index(
  'create index if not exists idx_vehicles_reg_trgm    on public.customer_vehicles using gin (registration_number gin_trgm_ops)', 'pg_trgm');
call app_util.create_optional_index(
  'create index if not exists idx_products_name_trgm  on public.products using gin (name gin_trgm_ops)', 'pg_trgm');
call app_util.create_optional_index(
  'create index if not exists idx_inventory_codes_trgm on public.inventory using gin (stock_code gin_trgm_ops)', 'pg_trgm');

-- ---------------------------------------------------------------------------
-- Reminder / EMI sweeps: the schedulers in 012 scan these daily.
-- ---------------------------------------------------------------------------
create index if not exists idx_reminders_pending_due
  on public.reminders (reminder_date, reminder_time)
  where status = 'PENDING';
create index if not exists idx_reminders_ref
  on public.reminders (reference_type, reference_id, reminder_type);
create index if not exists idx_emis_overdue
  on public.emi_schedules (due_date)
  where status in ('DUE','PARTIAL','OVERDUE');
create index if not exists idx_invoices_overdue
  on public.invoices (due_date)
  where outstanding_amount > 0 and status in ('FINALIZED','PARTIALLY_PAID','OVERDUE');
create index if not exists idx_warranties_expiring
  on public.warranties (end_date) where status = 'ACTIVE';
create index if not exists idx_insurance_expiring
  on public.insurance_policies (expiry_date) where status in ('ACTIVE','EXPIRING_SOON');
create index if not exists idx_free_services_due
  on public.vehicle_free_services (due_date, status) where status in ('UPCOMING','BOOKED');
create index if not exists idx_inventory_stale_reservation
  on public.inventory (reserved_until) where status = 'RESERVED';

-- ---------------------------------------------------------------------------
-- Uniqueness that must survive concurrent inserts (SS48, SS67)
-- ---------------------------------------------------------------------------
-- exactly one invoice may be attached to a sale
create unique index if not exists idx_invoices_one_per_sale
  on public.invoices (sale_id) where sale_id is not null and invoice_type = 'SALE';
-- exactly one accounting journal per business document + type.  A REVERSAL is the
-- deliberate second entry for the same document (money is answered with money), so
-- it is exempt here and is instead protected by the links on it.
create unique index if not exists idx_acctx_one_per_doc
  on public.accounting_transactions (reference_type, reference_id)
  where journal_type <> 'REVERSAL';
-- a customer may not have two live rows for the same registration number
create unique index if not exists idx_vehicles_one_active_reg
  on public.customer_vehicles (registration_number) where is_deleted = false and registration_number is not null;
-- device token per user/device pair (SS54)
create unique index if not exists idx_device_tokens_user_token
  on public.device_tokens (user_id, device_token);

-- ---------------------------------------------------------------------------
-- Audit: "what happened to this record" must be O(log n) even at millions of rows
-- ---------------------------------------------------------------------------
create index if not exists idx_audit_module_created on public.audit_logs (module, action, created_at desc);
create index if not exists idx_audit_record_latest  on public.audit_logs (table_name, record_id, created_at desc);
