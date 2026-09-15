-- =============================================================================
-- 004_finance_service_schema.sql
-- -----------------------------------------------------------------------------
-- Purpose : money in/out (payments), finance & EMI, purchasing, expenses, the
--           workshop (job cards, free-service plans), warranty, insurance and
--           in-app notifications.
-- Depends : 001, 002, 003.
--
-- Financial-integrity rules implemented as constraints (never as app logic):
--   * a payment can only allocate what it holds: allocated_amount <= amount
--   * refunds/reversals are new rows; no financial row is deleted or re-pointed
--   * an EMI line foots to principal + interest exactly
--   * inventory-linked lines keep stock, billing and finance in lock-step
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Payments (SS15)
--   amount          = money physically received (or refunded)
--   allocated_amount = money applied against invoices/EMIs; the difference is
--                      the customer's advance/credit balance - that is how
--                      advance payments are modelled without a second table.
-- ---------------------------------------------------------------------------
create table if not exists public.payments (
  id              uuid primary key default gen_random_uuid(),
  showroom_id     uuid not null references public.showrooms (id) on delete restrict,
  customer_id     uuid not null references public.customers (id) on delete restrict,
  invoice_id      uuid references public.invoices (id) on delete restrict,
  sale_id         uuid references public.sales (id) on delete restrict,
  service_id      uuid,                              -- FK added at the end of this file
  emi_id          uuid,                              -- FK added at the end of this file
  loan_id         uuid,                              -- FK added at the end of this file
  payment_number  text not null,
  payment_date    date not null default current_date,
  payment_type    text not null default 'RECEIPT'
                check (payment_type in ('RECEIPT','ADVANCE','REFUND','ADJUSTMENT','REVERSAL')),
  amount          app_util.money not null check (amount > 0),
  allocated_amount app_util.money not null default 0,
  payment_method  text not null
                check (payment_method in ('CASH','UPI','CARD','BANK_TRANSFER','CHEQUE',
                                         'FINANCE','ONLINE','NEFT','RTGS','DD','ADJUSTMENT')),
  reference_number text,
  transaction_id  text,
  instrument_number text,          -- cheque / DD number
  bank_name       text,
  cheque_status   text check (cheque_status is null or cheque_status in
                    ('CLEARED','BOUNCE','PENDING','HOLD')),
  status          text not null default 'COMPLETED'
                check (status in ('PENDING','COMPLETED','FAILED','CANCELLED','REFUNDED','REVERSED')),
  received_by     uuid references public.users (id) on delete restrict,
  reversed_by     uuid references public.users (id) on delete restrict,
  reversed_at     timestamptz,
  reversal_reason text,
  parent_payment_id uuid references public.payments (id) on delete restrict,
  notes           text,
  metadata        jsonb not null default '{}'::jsonb,
  receipt_pdf_path text,
  idempotency_key uuid unique,
  revision        integer not null default 1 check (revision > 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references public.users (id) on delete restrict,
  updated_by      uuid references public.users (id) on delete restrict,
  constraint payments_number_key unique (showroom_id, payment_number),
  -- SS67: never allocate more than was received
  constraint payments_allocation_bound check (allocated_amount <= amount),
  -- a REFUND must point back at the money it refunds, so the pair is traceable
  constraint payments_refund_parent check (
    (payment_type in ('REFUND','REVERSAL') and parent_payment_id is not null)
    or payment_type not in ('REFUND','REVERSAL')
  ),
  -- finance disbursements always carry the finance reference
  constraint payments_finance_ref check (
    (payment_method = 'FINANCE' and (transaction_id is not null or reference_number is not null))
    or payment_method <> 'FINANCE'
  ),
  constraint payments_cheque_ref check (
    (payment_method in ('CHEQUE','DD') and instrument_number is not null)
    or payment_method not in ('CHEQUE','DD')
  ),
  -- cancelled money must explain itself (SS69)
  constraint payments_cancel_reason check (
    (status in ('CANCELLED','FAILED') and reversal_reason is not null)
    or status not in ('CANCELLED','FAILED')
  )
);

comment on table public.payments is
  'Immutable money ledger. Cancellation/reversal creates a new row; the original is only status-flipped (SS42, SS67).';
create index if not exists payments_showroom_date_idx on public.payments (showroom_id, payment_date desc);
create index if not exists payments_customer_idx      on public.payments (customer_id);
create index if not exists payments_invoice_idx       on public.payments (invoice_id);
create index if not exists payments_sale_idx          on public.payments (sale_id);
create index if not exists payments_status_idx        on public.payments (status);
create index if not exists payments_method_idx        on public.payments (payment_method);

-- ---------------------------------------------------------------------------
-- Finance companies / loans / EMI schedule (SS16)
-- ---------------------------------------------------------------------------
create table if not exists public.finance_companies (
  id             uuid primary key default gen_random_uuid(),
  name           text not null unique check (length(btrim(name)) between 2 and 120),
  code           app_util.slug not null unique,
  contact_person text,
  phone          app_util.phone,
  alt_phone      app_util.phone,
  email          app_util.email,
  website        text,
  address        text,
  city           text,
  state          text,
  pincode        app_util.pincode,
  interest_rate_min app_util.rate,
  interest_rate_max app_util.rate,
  processing_fee_percent app_util.percentage,
  status         text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','SUSPENDED')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table if not exists public.loans (
  id                  uuid primary key default gen_random_uuid(),
  showroom_id         uuid not null references public.showrooms (id) on delete restrict,
  customer_id         uuid not null references public.customers (id) on delete restrict,
  vehicle_id          uuid references public.customer_vehicles (id) on delete restrict,
  sale_id             uuid references public.sales (id) on delete restrict,
  finance_company_id  uuid not null references public.finance_companies (id) on delete restrict,
  loan_number         text not null unique,
  lender_reference    text,
  loan_amount         app_util.money not null check (loan_amount > 0),
  principal_amount    app_util.money not null default 0,
  down_payment        app_util.money not null default 0,
  on_road_price       app_util.money not null default 0,
  interest_rate       app_util.rate not null check (interest_rate > 0 and interest_rate < 100),
  interest_type       text not null default 'REDUCING'
                    check (interest_type in ('REDUCING','FLAT')),
  tenure_months       smallint not null check (tenure_months between 1 and 120),
  emi_amount          app_util.money not null default 0,
  processing_fee      app_util.money not null default 0,
  insurance_charges   app_util.money not null default 0,
  other_charges       app_util.money not null default 0,
  total_interest      app_util.money not null default 0,
  total_payable       app_util.money not null default 0,
  start_date          date not null,
  end_date            date not null,
  first_emi_date      date,
  foreclosure_amount  app_util.money,
  foreclosure_date    date,
  late_fee_percent    app_util.percentage not null default 0,
  status              text not null default 'APPLIED'
                    check (status in ('APPLIED','SANCTIONED','ACTIVE','PART_PAYMENT',
                                      'CLOSED','FORECLOSED','REJECTED','CANCELLED')),
  approved_by         uuid references public.users (id) on delete restrict,
  approved_at         timestamptz,
  notes               text,
  revision            integer not null default 1 check (revision > 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.users (id) on delete restrict,
  updated_by          uuid references public.users (id) on delete restrict,
  constraint loans_dates_sane check (end_date > start_date),
  -- principal is the financed amount; stored explicitly so reporting never re-derives it
  constraint loans_principal_math check (
    principal_amount = 0 or principal_amount = round(loan_amount, 2)
  ),
  -- tenure (months) must match the sanctioned start/end window
  constraint loans_tenure_matches_window check (
    (extract(year from age(end_date, start_date)) * 12
     + extract(month from age(end_date, start_date)))::int between tenure_months - 1 and tenure_months + 1
  )
);

comment on column public.loans.principal_amount is 'P used by calculate_emi(); defaults to loan_amount (SS16).';
create index if not exists loans_showroom_status_idx on public.loans (showroom_id, status);
create index if not exists loans_customer_idx        on public.loans (customer_id);
create index if not exists loans_company_idx          on public.loans (finance_company_id);
create index if not exists loans_vehicle_idx          on public.loans (vehicle_id);
create index if not exists loans_start_idx            on public.loans (start_date);

create table if not exists public.emi_schedules (
  id               uuid primary key default gen_random_uuid(),
  loan_id          uuid not null references public.loans (id) on delete restrict,
  showroom_id      uuid not null references public.showrooms (id) on delete restrict,
  customer_id      uuid not null references public.customers (id) on delete restrict,
  emi_number       smallint not null check (emi_number between 1 and 480),
  due_date         date not null,
  principal_amount app_util.money not null default 0,
  interest_amount  app_util.money not null default 0,
  emi_amount       app_util.money not null default 0,
  paid_amount      app_util.money not null default 0,
  remaining_amount app_util.money not null default 0,
  late_fee         app_util.money not null default 0,
  penalty_amount   app_util.money not null default 0,
  paid_date        date,
  paid_via_payment_id uuid references public.payments (id) on delete restrict,
  status           text not null default 'UPCOMING'
                 check (status in ('UPCOMING','DUE','PARTIAL','PAID','OVERDUE','CANCELLED')),
  reminder_sent_at timestamptz,
  overdue_days     integer not null default 0 check (overdue_days >= 0),
  notes           text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint emi_schedules_number_key unique (loan_id, emi_number),
  constraint emi_line_math check (
    emi_amount = round(principal_amount + interest_amount, 2)
    and remaining_amount = round(emi_amount + late_fee + penalty_amount - paid_amount, 2)
  ),
  -- you cannot pay more than is owed on an instalment (SS67)
  constraint emi_paid_bound check (paid_amount <= emi_amount + late_fee + penalty_amount),
  constraint emi_paid_date_check check (
    (status = 'PAID' and paid_date is not null) or status <> 'PAID'
  ),
  constraint emi_due_date_positive check (due_date >= date '2000-01-01')
);

create index if not exists emi_schedules_loan_idx         on public.emi_schedules (loan_id, emi_number);
create index if not exists emi_schedules_due_idx          on public.emi_schedules (due_date, status);
create index if not exists emi_schedules_showroom_due_idx on public.emi_schedules (showroom_id, due_date);
create index if not exists emi_schedules_customer_idx     on public.emi_schedules (customer_id);
create index if not exists emi_schedules_open_idx         on public.emi_schedules (status, due_date)
  where status in ('UPCOMING','DUE','PARTIAL','OVERDUE');
comment on table public.emi_schedules is 'Generated by generate_emi_schedule(); amortisation is server-owned so the ledger always foots.';

-- ---------------------------------------------------------------------------
-- Purchasing (SS22)
-- ---------------------------------------------------------------------------
create table if not exists public.suppliers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (length(btrim(name)) between 2 and 120),
  code        app_util.slug unique,
  contact_person text,
  phone       app_util.phone,
  alt_phone   app_util.phone,
  email       app_util.email,
  address     text,
  city        text,
  state       text,
  pincode     app_util.pincode,
  gst_number  app_util.gstn,
  pan_number  app_util.pan,
  bank_account_number text,
  bank_ifsc   text,
  credit_limit app_util.money,
  payment_terms_days smallint not null default 30 check (payment_terms_days between 0 and 365),
  status      text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','BLACKLISTED')),
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.purchases (
  id               uuid primary key default gen_random_uuid(),
  purchase_number  text not null,
  showroom_id      uuid not null references public.showrooms (id) on delete restrict,
  supplier_id      uuid not null references public.suppliers (id) on delete restrict,
  purchase_date    date not null default current_date,
  expected_date    date,
  invoice_reference text,
  subtotal         app_util.money not null default 0,
  discount         app_util.money not null default 0,
  tax_amount       app_util.money not null default 0,
  other_charges    app_util.money not null default 0,
  freight_charges  app_util.money not null default 0,
  total_amount     app_util.money not null default 0,
  paid_amount      app_util.money not null default 0,
  outstanding_amount app_util.money not null default 0,
  status           text not null default 'DRAFT'
                 check (status in ('DRAFT','CONFIRMED','PARTIAL_RECEIVED','RECEIVED','CANCELLED','RETURNED')),
  payment_due_date date,
  notes            text,
  approved_by      uuid references public.users (id) on delete restrict,
  approved_at      timestamptz,
  cancelled_reason text,
  revision         integer not null default 1 check (revision > 0),
  created_by       uuid references public.users (id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.users (id) on delete restrict,
  constraint purchases_number_key unique (showroom_id, purchase_number),
  constraint purchases_total_formula check (
    total_amount = round(subtotal - discount + tax_amount + other_charges + freight_charges, 2)
  ),
  constraint purchases_outstanding_math check (
    outstanding_amount = round(total_amount - paid_amount, 2)
  ),
  constraint purchases_paid_le_total check (paid_amount <= total_amount)
);

create index if not exists purchases_showroom_date_idx on public.purchases (showroom_id, purchase_date desc);
create index if not exists purchases_supplier_idx       on public.purchases (supplier_id);
create index if not exists purchases_status_idx         on public.purchases (showroom_id, status);

create table if not exists public.purchase_items (
  id            uuid primary key default gen_random_uuid(),
  purchase_id   uuid not null references public.purchases (id) on delete cascade,
  product_id    uuid not null references public.products (id) on delete restrict,
  inventory_id  uuid references public.inventory (id) on delete set null,
  color_id      uuid references public.product_colors (id) on delete restrict,
  description   text not null,
  quantity      app_util.positive_qty not null default 1,
  received_quantity numeric(12,3) not null default 0 check (received_quantity >= 0),
  unit_cost     app_util.money not null default 0,
  discount      app_util.money not null default 0,
  tax_rate      app_util.percentage not null default 0,
  tax_amount    app_util.money not null default 0,
  total_amount  app_util.money not null default 0,
  created_at    timestamptz not null default now(),
  constraint purchase_items_line_math check (
    total_amount = round(quantity * unit_cost - discount + tax_amount, 2)
  ),
  constraint purchase_items_received_bound check (received_quantity <= quantity)
);

create index if not exists purchase_items_purchase_idx on public.purchase_items (purchase_id);
create index if not exists purchase_items_product_idx  on public.purchase_items (product_id);
comment on table public.purchase_items is
  'Purchase lines. On RECEIVED, create_purchase_transaction() materialises inventory rows and links them back here (SS65).';

-- ---------------------------------------------------------------------------
-- Chart of accounts + double-entry journals (SS24)
-- Table *structure* lives here because payments, purchases and expenses all
-- reference it; 013_accounting.sql adds the behaviour (balance enforcement,
-- posting primitives, the default chart-of-accounts generator, trial balance).
-- ---------------------------------------------------------------------------
create table if not exists public.accounts (
  id                uuid primary key default gen_random_uuid(),
  showroom_id       uuid not null references public.showrooms (id) on delete restrict,
  account_code      text not null check (account_code ~ '^[0-9]{1,4}(\.[0-9]{1,4})*$'),
  account_name      text not null check (length(btrim(account_name)) between 2 and 120),
  account_type      text not null check (account_type in ('ASSET','LIABILITY','EQUITY','INCOME','EXPENSE')),
  parent_account_id uuid references public.accounts (id) on delete restrict,
  is_group          boolean not null default false,
  is_system         boolean not null default false,
  -- the posting side normally used by the automatic engine (SS24 examples)
  normal_balance    text not null default 'DEBIT' check (normal_balance in ('DEBIT','CREDIT')),
  opening_balance   app_util.signed_money not null default 0,
  description       text,
  status            text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','ARCHIVED')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint accounts_code_key unique (showroom_id, account_code),
  constraint accounts_no_self_parent check (parent_account_id is null or parent_account_id <> id)
);
comment on table public.accounts is 'Per-showroom chart of accounts (SS82). is_system accounts cannot be edited or deleted by non-super admins.';
create index if not exists accounts_showroom_type_idx on public.accounts (showroom_id, account_type, status);
create index if not exists accounts_parent_idx        on public.accounts (parent_account_id);

create table if not exists public.accounting_transactions (
  id             uuid primary key default gen_random_uuid(),
  transaction_number text,
  showroom_id    uuid not null references public.showrooms (id) on delete restrict,
  transaction_date date not null default current_date,
  financial_year text generated always as (
                   'FY'
                   || lpad(((case when extract(month from transaction_date) >= 4
                                  then extract(year from transaction_date)::int
                                  else extract(year from transaction_date)::int - 1 end) % 100)::text, 2, '0')
                   || lpad(((case when extract(month from transaction_date) >= 4
                                  then extract(year from transaction_date)::int + 1
                                  else extract(year from transaction_date)::int end) % 100)::text, 2, '0')
                 ) stored,
  journal_type   text not null default 'GENERIC'
               check (journal_type in ('SALE','SALE_CANCEL','PURCHASE','PURCHASE_CANCEL','PAYMENT',
                                       'REFUND','RECEIPT','EXPENSE','SERVICE','EMI_INTEREST',
                                       'EMI_PRINCIPAL','FORECLOSURE','STOCK_ADJUSTMENT','OPENING',
                                       'MANUAL','TRANSFER','REVERSAL')),
  reference_type text not null,
  reference_id   uuid not null,
  description    text,
  is_reversed    boolean not null default false,
  reversed_by_transaction_id uuid references public.accounting_transactions (id) on delete restrict,
  status         text not null default 'POSTED' check (status in ('POSTED','REVERSED','DRAFT')),
  created_by     uuid references public.users (id) on delete restrict,
  created_at     timestamptz not null default now(),
  constraint accounting_tx_number_key unique (showroom_id, transaction_number),
  -- one journal per source document per journal_type keeps reposting impossible
  constraint accounting_tx_one_per_ref_key unique (reference_type, reference_id, journal_type),
  constraint accounting_reversal_pair check (
    (is_reversed and reversed_by_transaction_id is not null) or not is_reversed
  )
);
comment on table public.accounting_transactions is 'Journal header; (reference_type, reference_id, journal_type) is unique so reposting a document is impossible (SS24, SS67).';
create index if not exists acc_tx_showroom_date_idx on public.accounting_transactions (showroom_id, transaction_date desc);
create index if not exists acc_tx_ref_idx           on public.accounting_transactions (reference_type, reference_id);

create table if not exists public.accounting_entries (
  id            uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.accounting_transactions (id) on delete cascade,
  account_id    uuid not null references public.accounts (id) on delete restrict,
  showroom_id   uuid not null references public.showrooms (id) on delete restrict,
  line_number   smallint not null default 1 check (line_number between 1 and 500),
  debit         app_util.money not null default 0,
  credit        app_util.money not null default 0,
  amount        app_util.signed_money generated always as (debit - credit) stored,
  description   text,
  cost_center   text,
  created_at    timestamptz not null default now(),
  constraint accounting_entries_line_key unique (transaction_id, line_number),
  -- a line is either a debit or a credit, never both (classic journal rule)
  constraint accounting_entries_single_side check (
    (debit > 0 and credit = 0) or (credit > 0 and debit = 0)
  )
);
comment on column public.accounting_entries.amount is 'Generated debit-credit helper so trial balance is a single sum (SS24).';
create index if not exists acc_entries_tx_idx      on public.accounting_entries (transaction_id);
create index if not exists acc_entries_account_idx on public.accounting_entries (account_id, showroom_id);

-- ---------------------------------------------------------------------------
-- Expenses (SS23)
-- ---------------------------------------------------------------------------
create table if not exists public.expense_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique check (length(btrim(name)) between 2 and 60),
  code        app_util.slug unique,
  description text,
  -- Every expense posts to a P&L account, and each showroom owns its own chart
  -- (SS82), so the category carries the account *code* and the booking RPC
  -- resolves it inside the showroom that raises the expense. A uuid here would
  -- silently point at one branch's account from every other branch.
  account_code text check (account_code is null or account_code ~ '^[0-9]{4}$'),
  is_system   boolean not null default false,
  requires_approval boolean not null default true,
  approval_limit app_util.money,   -- expenses at/below this amount skip approval
  status      text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.expenses (
  id              uuid primary key default gen_random_uuid(),
  expense_number  text not null,
  showroom_id     uuid not null references public.showrooms (id) on delete restrict,
  category_id     uuid not null references public.expense_categories (id) on delete restrict,
  expense_date    date not null default current_date,
  -- Indian financial year (April-March). Built from integer extraction so the
  -- expression stays IMMUTABLE, which a generated column requires.
  financial_year  text generated always as (
                    'FY'
                    || lpad(((case when extract(month from expense_date) >= 4
                                   then extract(year from expense_date)::int
                                   else extract(year from expense_date)::int - 1
                              end) % 100)::text, 2, '0')
                    || lpad(((case when extract(month from expense_date) >= 4
                                   then extract(year from expense_date)::int + 1
                                   else extract(year from expense_date)::int
                              end) % 100)::text, 2, '0')
                  ) stored,
  vendor_name     text,
  vendor_invoice_number text,
  amount          app_util.money not null check (amount > 0),
  tax_rate        app_util.percentage not null default 0,
  tax_amount      app_util.money not null default 0,
  total_amount    app_util.money not null default 0,
  payment_method  text check (payment_method is null or payment_method in
                    ('CASH','UPI','CARD','BANK_TRANSFER','CHEQUE','ADJUSTMENT','PENDING')),
  reference_number text,
  paid_on         date,
  attachment_url  text,
  description     text not null check (length(btrim(description)) >= 3),
  status          text not null default 'PENDING'
                check (status in ('PENDING','APPROVED','REJECTED','PAID','CANCELLED')),
  approval_note   text,
  rejection_reason text,
  created_by      uuid references public.users (id) on delete restrict,
  approved_by     uuid references public.users (id) on delete restrict,
  approved_at     timestamptz,
  accounting_transaction_id uuid references public.accounting_transactions (id) on delete set null,
  revision        integer not null default 1 check (revision > 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.users (id) on delete restrict,
  constraint expenses_number_key unique (showroom_id, expense_number),
  constraint expenses_total_math check (total_amount = 0 or total_amount = round(amount + tax_amount, 2)),
  constraint expenses_reject_reason check (
    (status = 'REJECTED' and rejection_reason is not null) or status <> 'REJECTED'
  )
);

create index if not exists expenses_showroom_date_idx on public.expenses (showroom_id, expense_date desc);
create index if not exists expenses_category_idx      on public.expenses (category_id);
create index if not exists expenses_status_idx        on public.expenses (showroom_id, status);
create index if not exists expenses_fy_idx            on public.expenses (financial_year);
comment on column public.expenses.financial_year is
  'Generated column (Indian FY, April-March) so P&L grouping is index-friendly and never drifts (SS25).';

-- ---------------------------------------------------------------------------
-- Free-service plans (SS18) - catalogue-driven entitlement definition
-- ---------------------------------------------------------------------------
create table if not exists public.free_service_plans (
  id             uuid primary key default gen_random_uuid(),
  plan_code      app_util.slug not null unique,
  name           text not null,
  product_id     uuid references public.products (id) on delete cascade,
  brand_id       uuid references public.brands (id) on delete cascade,
  service_number smallint not null check (service_number between 1 and 12),
  validity_days  smallint not null check (validity_days between 1 and 1095),
  validity_km    integer not null check (validity_km between 100 and 100000),
  free_labour    boolean not null default true,
  covered_items  jsonb not null default '["GENERAL_CHECKUP","OIL_CHANGE","BRAKE_INSPECTION","TYRE_CHECK","CHAIN_ADJUSTMENT","AIR_FILTER_CLEAN"]'::jsonb,
  labour_hours   numeric(5,2) not null default 1 check (labour_hours > 0),
  estimated_value app_util.money not null default 0,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint free_service_plan_scope check (product_id is not null or brand_id is not null),
  constraint free_service_plan_product_slot unique (product_id, service_number)
);
comment on constraint free_service_plan_scope on public.free_service_plans is
  'A plan is bound to a product (typical) or, as a fallback, to a whole brand.';
create index if not exists free_service_plans_lookup_idx on public.free_service_plans (product_id, service_number) where is_active;

-- ---------------------------------------------------------------------------
-- Service records / job cards (§19, §64)
-- ---------------------------------------------------------------------------
create table if not exists public.service_records (
  id                 uuid primary key default gen_random_uuid(),
  service_number     text not null,
  showroom_id        uuid not null references public.showrooms (id) on delete restrict,
  customer_id        uuid not null references public.customers (id) on delete restrict,
  vehicle_id         uuid not null references public.customer_vehicles (id) on delete restrict,
  sale_id            uuid references public.sales (id) on delete restrict,
  free_service_id    uuid,                       -- FK added below
  booking_date       timestamptz,
  booking_slot       text,
  service_date       date not null default current_date,
  expected_delivery  date,
  received_at        timestamptz,
  delivered_at       timestamptz,
  pickup_date        date,
  drop_date          date,
  odometer_reading   app_util.odometer,
  previous_odometer  app_util.odometer,
  service_type       text not null default 'PAID'
                   check (service_type in ('FREE','PAID','WARRANTY','RECALL','COMPLIMENTARY')),
  service_status     text not null default 'BOOKED'
                   check (service_status in ('BOOKED','RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS',
                                             'COMPLETED','DELIVERED','CANCELLED')),
  service_advisor_id uuid references public.users (id) on delete restrict,
  technician_id      uuid references public.users (id) on delete restrict,
  bay_number         text,
  complaint          text,
  customer_notes     text,
  inspection_notes   text,
  work_done          text,
  recommendations    text,
  next_service_date  date,
  next_service_km    integer check (next_service_km is null or next_service_km >= 0),
  subtotal           app_util.money not null default 0,
  labour_charges     app_util.money not null default 0,
  parts_charges      app_util.money not null default 0,
  discount           app_util.money not null default 0,
  discount_percent   app_util.percentage not null default 0,
  tax_amount         app_util.money not null default 0,
  other_charges      app_util.money not null default 0,
  total_amount       app_util.money not null default 0,
  paid_amount        app_util.money not null default 0,
  outstanding_amount app_util.money not null default 0,
  invoice_id         uuid references public.invoices (id) on delete restrict,
  warranty_claim_id  uuid,                        -- FK added below
  is_billable        boolean not null default true,
  cancelled_reason   text,
  cancelled_by       uuid references public.users (id) on delete restrict,
  cancelled_at       timestamptz,
  feedback_rating    smallint check (feedback_rating is null or feedback_rating between 1 and 5),
  feedback_comments  text,
  notes              text,
  revision           integer not null default 1 check (revision > 0),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.users (id) on delete restrict,
  updated_by         uuid references public.users (id) on delete restrict,
  constraint service_records_number_key unique (showroom_id, service_number),
  constraint service_total_formula check (
    total_amount = round(subtotal - discount + tax_amount + other_charges, 2)
  ),
  constraint service_outstanding_math check (
    outstanding_amount = round(total_amount - paid_amount, 2)
  ),
  constraint service_paid_le_total check (paid_amount <= total_amount),
  -- a FREE/WARRANTY job must never carry a bill unless explicitly overridden
  constraint service_free_zero_bill check (
    (service_type in ('FREE','WARRANTY') and (total_amount = 0 or is_billable))
    or service_type = 'PAID'
  ),
  constraint service_cancel_reason check (
    (service_status = 'CANCELLED' and cancelled_reason is not null) or service_status <> 'CANCELLED'
  ),
  constraint service_delivered_consistency check (
    (service_status = 'DELIVERED' and delivered_at is not null) or service_status <> 'DELIVERED'
  ),
  -- odometer can only move forward: catches typos that would corrupt service
  -- intervals and free-service eligibility (SS18)
  constraint service_odometer_monotonic check (
    previous_odometer is null or odometer_reading is null or odometer_reading >= previous_odometer
  )
);

create index if not exists service_records_showroom_status_idx on public.service_records (showroom_id, service_status);
create index if not exists service_records_showroom_date_idx   on public.service_records (showroom_id, service_date desc);
create index if not exists service_records_customer_idx       on public.service_records (customer_id);
create index if not exists service_records_vehicle_idx        on public.service_records (vehicle_id, service_date desc);
create index if not exists service_records_advisor_idx        on public.service_records (service_advisor_id);
create index if not exists service_records_technician_idx     on public.service_records (technician_id, service_status);
create index if not exists service_records_outstanding_idx    on public.service_records (showroom_id, outstanding_amount) where outstanding_amount > 0;

create table if not exists public.service_items (
  id           uuid primary key default gen_random_uuid(),
  service_id   uuid not null references public.service_records (id) on delete cascade,
  item_type    text not null check (item_type in
               ('PART','LABOUR','OIL','CONSUMABLE','ACCESSORY','OTHER')),
  product_id   uuid references public.products (id) on delete restrict,
  inventory_id uuid references public.inventory (id) on delete restrict,
  part_number  text,
  description  text not null,
  quantity     app_util.positive_qty not null default 1,
  unit_price   app_util.money not null default 0,
  labour_hours numeric(5,2) check (labour_hours is null or labour_hours >= 0),
  discount     app_util.money not null default 0,
  tax_rate     app_util.percentage not null default 0,
  tax_amount   app_util.money not null default 0,
  total_amount app_util.money not null default 0,
  is_warranty_covered boolean not null default false,
  is_from_stock boolean not null default false,
  sort_order   smallint not null default 0,
  created_at   timestamptz not null default now(),
  constraint service_items_line_math check (
    total_amount = round(quantity * unit_price - discount + tax_amount, 2)
  ),
  constraint service_items_stock_needs_serial check (
    (is_from_stock and inventory_id is not null) or not is_from_stock
  )
);

create index if not exists service_items_service_idx on public.service_items (service_id, sort_order);
create index if not exists service_items_product_idx on public.service_items (product_id);

-- ---------------------------------------------------------------------------
-- Free-service entitlement per sold vehicle (§18)
-- ---------------------------------------------------------------------------
create table if not exists public.vehicle_free_services (
  id                   uuid primary key default gen_random_uuid(),
  vehicle_id           uuid not null references public.customer_vehicles (id) on delete restrict,
  customer_id          uuid not null references public.customers (id) on delete restrict,
  showroom_id          uuid not null references public.showrooms (id) on delete restrict,
  free_service_plan_id uuid not null references public.free_service_plans (id) on delete restrict,
  service_number       smallint not null check (service_number between 1 and 12),
  due_date             date not null,
  due_km             integer not null default 0 check (due_km >= 0),
  booked_date          date,
  used_date            date,
  odometer_at_use      app_util.odometer,
  service_id           uuid references public.service_records (id) on delete restrict,
  status               text not null default 'UPCOMING'
                     check (status in ('UPCOMING','BOOKED','USED','EXPIRED','SKIPPED','CANCELLED')),
  eligibility_notes    text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint vehicle_free_services_slot unique (vehicle_id, service_number)
);

create index if not exists vehicle_free_services_vehicle_idx on public.vehicle_free_services (vehicle_id, service_number);
create index if not exists vehicle_free_services_due_idx     on public.vehicle_free_services (showroom_id, due_date, status);
comment on table public.vehicle_free_services is
  'Generated at sale time by create_sale_transaction(); marked USED by complete_service() (SS18, SS63).';

-- ---------------------------------------------------------------------------
-- Warranty + claims (§20)
-- ---------------------------------------------------------------------------
create table if not exists public.warranties (
  id                 uuid primary key default gen_random_uuid(),
  vehicle_id         uuid not null unique references public.customer_vehicles (id) on delete restrict,
  customer_id        uuid not null references public.customers (id) on delete restrict,
  showroom_id        uuid not null references public.showrooms (id) on delete restrict,
  product_id         uuid references public.products (id) on delete restrict,
  warranty_number    text not null unique,
  warranty_type      text not null default 'FACTORY'
                   check (warranty_type in ('FACTORY','EXTENDED','ACCESSORY','BATTERY','CORROSION','CAMPAIN')),
  start_date         date not null,
  end_date           date not null,
  start_km           app_util.odometer not null default 0,
  coverage_km        integer not null default 0 check (coverage_km >= 0),
  current_km         app_util.odometer not null default 0,
  terms              text,
  covered_components jsonb not null default '["ENGINE","TRANSMISSION","ELECTRICS","CHASSIS","FUEL_PUMP"]'::jsonb,
  excluded_components jsonb not null default '["WEAR_AND_TEAR","TYRES","BATTERY_12V","ACCIDENT_DAMAGE"]'::jsonb,
  status             text not null default 'ACTIVE'
                   check (status in ('ACTIVE','EXPIRED','VOID','EXTENDED','TRANSFERRABLE','CANCELLED')),
  extended_by        uuid references public.users (id) on delete restrict,
  extension_notes    text,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.users (id) on delete restrict,
  constraint warranty_dates check (end_date > start_date)
);

create index if not exists warranties_customer_idx on public.warranties (customer_id);
create index if not exists warranties_expiry_idx   on public.warranties (end_date, status);
create index if not exists warranties_showroom_idx on public.warranties (showroom_id, status);

create table if not exists public.warranty_claims (
  id             uuid primary key default gen_random_uuid(),
  claim_number   text not null,
  warranty_id    uuid not null references public.warranties (id) on delete restrict,
  vehicle_id     uuid not null references public.customer_vehicles (id) on delete restrict,
  service_id     uuid references public.service_records (id) on delete restrict,
  showroom_id    uuid not null references public.showrooms (id) on delete restrict,
  claim_date     date not null default current_date,
  description    text not null check (length(btrim(description)) >= 10),
  claimed_amount app_util.money not null default 0,
  approved_amount app_util.money not null default 0,
  status         text not null default 'SUBMITTED'
               check (status in ('SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','SETTLED','CANCELLED')),
  resolution     text,
  rejected_reason text,
  manufacturer_reference text,
  submitted_by   uuid references public.users (id) on delete restrict,
  reviewed_by    uuid references public.users (id) on delete restrict,
  reviewed_at    timestamptz,
  settled_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint warranty_claims_number_key unique (showroom_id, claim_number),
  constraint warranty_claims_amount_bound check (approved_amount <= claimed_amount),
  constraint warranty_claims_reject_reason check (
    (status = 'REJECTED' and rejected_reason is not null) or status <> 'REJECTED'
  )
);

create index if not exists warranty_claims_warranty_idx on public.warranty_claims (warranty_id);
create index if not exists warranty_claims_status_idx   on public.warranty_claims (showroom_id, status);
create index if not exists warranty_claims_service_idx    on public.warranty_claims (service_id);

-- ---------------------------------------------------------------------------
-- Insurance (§21)
-- ---------------------------------------------------------------------------
create table if not exists public.insurance_policies (
  id                uuid primary key default gen_random_uuid(),
  vehicle_id        uuid not null references public.customer_vehicles (id) on delete restrict,
  customer_id       uuid not null references public.customers (id) on delete restrict,
  showroom_id       uuid not null references public.showrooms (id) on delete restrict,
  insurance_company text not null,
  policy_number     text not null,
  policy_type       text not null default 'COMPREHENSIVE'
                  check (policy_type in ('COMPREHENSIVE','THIRD_PARTY','HI_EXP','PACKAGE','RIDER')),
  start_date        date not null,
  expiry_date       date not null,
  sum_insured       app_util.money not null default 0,
  premium           app_util.money not null default 0,
  idv               app_util.money,
  ncg_percent       app_util.percentage,
  -- zero-depreciation / engine-protect riders and any other free-form add-ons
  riders            jsonb not null default '[]'::jsonb,
  document_path     text,
  company_reference text,
  issued_by_agent   text,
  status            text not null default 'ACTIVE'
                  check (status in ('ACTIVE','EXPIRING_SOON','EXPIRED','CANCELLED','RENEWED','LAPSED')),
  renewed_policy_id uuid references public.insurance_policies (id) on delete restrict,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references public.users (id) on delete restrict,
  constraint insurance_policy_number_key unique (policy_number),
  constraint insurance_dates check (expiry_date > start_date)
);

create index if not exists insurance_vehicle_idx on public.insurance_policies (vehicle_id);
create index if not exists insurance_expiry_idx  on public.insurance_policies (expiry_date, status);
create index if not exists insurance_showroom_idx on public.insurance_policies (showroom_id, status);
comment on table public.insurance_policies is 'One row per policy; renewals chain via renewed_policy_id so history never disappears (SS42).';

-- ---------------------------------------------------------------------------
-- In-app notifications (§29)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references public.users (id) on delete cascade,
  customer_id      uuid references public.customers (id) on delete cascade,
  showroom_id      uuid references public.showrooms (id) on delete cascade,
  title            text not null check (length(btrim(title)) between 2 and 200),
  message          text not null,
  notification_type text not null default 'SYSTEM'
                   check (notification_type in ('EMI','SERVICE','INSURANCE','WARRANTY','PAYMENT',
                                                 'APPROVAL','STOCK','SYSTEM','SALES','ACCOUNTING',
                                                 'DOCUMENT','PUSH')),
  severity         text not null default 'INFO'
                   check (severity in ('INFO','SUCCESS','WARNING','CRITICAL')),
  -- deep link the Flutter router can consume directly (route name + params)
  route_name       text,
  route_params     jsonb not null default '{}'::jsonb,
  reference_type   text,
  reference_id     uuid,
  is_read          boolean not null default false,
  read_at          timestamptz,
  channel          text not null default 'IN_APP'
                   check (channel in ('IN_APP','FCM','EMAIL','SMS','WHATSAPP')),
  push_sent_at     timestamptz,
  push_error       text,
  action_required    boolean not null default false,
  action_route     text,
  created_at       timestamptz not null default now(),
  sent_at          timestamptz,
  constraint notifications_read_consistency check (
    (is_read and read_at is not null) or (not is_read and read_at is null)
  )
);

create index if not exists notifications_user_unread_idx on public.notifications (user_id, is_read, created_at desc);
create index if not exists notifications_showroom_idx     on public.notifications (showroom_id, created_at desc);
create index if not exists notifications_ref_idx          on public.notifications (reference_type, reference_id);
comment on table public.notifications is 'Stored notification feed (badge count + realtime); FCM is the transport, this is the record of truth.';

-- ---------------------------------------------------------------------------
-- Deferred foreign keys
-- ---------------------------------------------------------------------------
alter table public.payments
  add constraint payments_service_fkey foreign key (service_id)
  references public.service_records (id) on delete restrict;
alter table public.payments
  add constraint payments_emischedule_fkey foreign key (emi_id)
  references public.emi_schedules (id) on delete restrict;
alter table public.payments
  add constraint payments_loan_fkey foreign key (loan_id)
  references public.loans (id) on delete restrict;

alter table public.invoices
  add constraint invoices_service_fkey foreign key (service_id)
  references public.service_records (id) on delete restrict;
alter table public.invoices
  add constraint invoices_loan_fkey foreign key (loan_id)
  references public.loans (id) on delete restrict;

alter table public.invoice_items
  add constraint invoice_items_service_item_fkey foreign key (service_item_id)
  references public.service_items (id) on delete set null;

alter table public.service_records
  add constraint service_records_free_service_fkey foreign key (free_service_id)
  references public.vehicle_free_services (id) on delete set null;
alter table public.service_records
  add constraint service_records_warranty_claim_fkey foreign key (warranty_claim_id)
  references public.warranty_claims (id) on delete set null;

-- A sold bike must not be consumed by a second job card before delivery? -> no:
-- service needs an ACTIVE vehicle; enforced by app logic + partial index here.
create unique index if not exists service_records_open_per_vehicle_idx
  on public.service_records (vehicle_id)
  where service_status in ('RECEIVED','IN_PROGRESS','WAITING_FOR_PARTS');
comment on index public.service_records_open_per_vehicle_idx is
  'One live job card per vehicle: prevents two technicians working the same bike (§19).';

-- Payment allocation to EMIs must be idempotent per instalment
create index if not exists payments_emis_paid_idx on public.payments (emi_id) where emi_id is not null and status = 'COMPLETED';

-- ---------------------------------------------------------------------------
-- Reminders (SS17). 012_reminders.sql only adds the automatic generators and
-- the scheduler wiring; the table itself belongs to the business model.
-- ---------------------------------------------------------------------------
create table if not exists public.reminders (
  id            uuid primary key default gen_random_uuid(),
  showroom_id   uuid not null references public.showrooms (id) on delete restrict,
  customer_id   uuid not null references public.customers (id) on delete cascade,
  vehicle_id    uuid references public.customer_vehicles (id) on delete cascade,
  inventory_id  uuid references public.inventory (id) on delete set null,
  assigned_to   uuid references public.users (id) on delete set null,
  reminder_type text not null check (reminder_type in
                ('EMI','SERVICE','INSURANCE','WARRANTY','PAYMENT','DOCUMENT','CUSTOM','RC_TRANSFER','PUC')),
  title         text not null check (length(btrim(title)) between 3 and 160),
  message       text not null,
  reminder_date date not null,
  -- TIME is stored separately from the date so the Flutter scheduler and the
  -- SQL sweep both work with plain local-time semantics (showrooms.timezone).
  reminder_time time not null default '09:30',
  channel       text not null default 'PUSH'
              check (channel in ('PUSH','IN_APP','SMS','WHATSAPP','EMAIL','CALL')),
  priority      text not null default 'MEDIUM'
              check (priority in ('LOW','MEDIUM','HIGH','URGENT')),
  status        text not null default 'PENDING'
              check (status in ('PENDING','SENT','COMPLETED','CANCELLED','FAILED','SKIPPED')),
  reference_type text,
  reference_id   uuid,
  attempts       smallint not null default 0 check (attempts between 0 and 20),
  sent_at        timestamptz,
  completed_at   timestamptz,
  completed_by   uuid references public.users (id) on delete restrict,
  cancel_reason  text,
  dedupe_key     text unique,   -- stops the scheduler creating the same reminder twice
  notification_id uuid references public.notifications (id) on delete set null,
  created_by     uuid references public.users (id) on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.users (id) on delete restrict,
  constraint reminders_completed_consistency check (
    (status = 'COMPLETED' and completed_at is not null) or status <> 'COMPLETED'
  ),
  constraint reminders_cancel_reason check (
    (status = 'CANCELLED' and cancel_reason is not null) or status <> 'CANCELLED'
  ),
  constraint reminders_sent_consistency check (
    (status in ('SENT','COMPLETED') and sent_at is not null) or status not in ('SENT','COMPLETED')
  )
);
comment on column public.reminders.dedupe_key is
  'sha1-ish business key (type:reference_id:due_date) enforced unique so a re-run of the scheduler never double-notifies (SS17).';
create index if not exists reminders_pending_idx   on public.reminders (status, reminder_date, reminder_time);
create index if not exists reminders_shr_date_idx  on public.reminders (showroom_id, reminder_date desc);
create index if not exists reminders_customer_idx  on public.reminders (customer_id, status);
create index if not exists reminders_assigned_idx  on public.reminders (assigned_to, status, reminder_date);

