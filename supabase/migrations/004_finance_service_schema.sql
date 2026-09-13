-- 004_finance_service_schema.sql
-- EMI/finance, purchases & suppliers, expenses, service jobs, warranty,
-- insurance, reminders, notifications, attachments and audit logs.

-- ---------------------------------------------------------------- finance

create table if not exists public.finance_companies (
  id              uuid primary key default public.new_id(),
  name            text not null unique,
  code            text not null default '',
  contact_person  text not null default '',
  phone           text not null default '',
  email           text not null default '',
  address         text not null default '',
  status          text not null default 'active'
                    check (status in ('active', 'inactive')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table if not exists public.loans (
  id                  uuid primary key default public.new_id(),
  showroom_id         uuid not null references public.showrooms (id),
  customer_id         uuid not null references public.customers (id),
  vehicle_id          uuid references public.customer_vehicles (id) on delete set null,
  sale_id             uuid references public.sales (id) on delete set null,
  finance_company_id  uuid references public.finance_companies (id) on delete set null,
  loan_number         text not null unique,
  loan_amount         numeric(14,2) not null check (loan_amount > 0),
  down_payment        numeric(14,2) not null default 0,
  interest_rate       numeric(6,3) not null default 0,
  tenure_months       integer not null check (tenure_months > 0),
  monthly_emi         numeric(14,2) not null default 0,
  total_interest      numeric(14,2) not null default 0,
  outstanding_amount  numeric(14,2) not null default 0,
  processing_fee      numeric(14,2) not null default 0,
  start_date          date not null default current_date,
  end_date            date,
  status              text not null default 'active'
                        check (status in ('applied', 'active', 'closed',
                                          'rejected', 'defaulted')),
  closed_at           timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists public.emi_schedules (
  id                uuid primary key default public.new_id(),
  loan_id           uuid not null references public.loans (id) on delete cascade,
  installment_no    integer not null check (installment_no > 0),
  due_date          date not null,
  principal_amount  numeric(14,2) not null default 0,
  interest_amount   numeric(14,2) not null default 0,
  emi_amount        numeric(14,2) not null default 0,
  paid_amount       numeric(14,2) not null default 0,
  balance_after     numeric(14,2) not null default 0,
  paid_at           date,
  status            text not null default 'pending'
                      check (status in ('pending', 'paid', 'partial',
                                        'overdue')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (loan_id, installment_no)
);

-- -------------------------------------------------------------- purchases

create table if not exists public.suppliers (
  id                   uuid primary key default public.new_id(),
  name                 text not null,
  contact_person       text not null default '',
  phone                text not null default '',
  alternate_phone      text not null default '',
  email                text not null default '',
  address              text not null default '',
  city                 text not null default '',
  state                text not null default '',
  pincode              text not null default '',
  gstin                text not null default '',
  payment_terms_days   integer not null default 0,
  status               text not null default 'active'
                         check (status in ('active', 'inactive')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create table if not exists public.purchases (
  id                uuid primary key default public.new_id(),
  showroom_id       uuid not null references public.showrooms (id),
  supplier_id       uuid not null references public.suppliers (id),
  purchase_number   text not null unique,
  order_date        date not null default current_date,
  expected_date     date,
  received_date     date,
  subtotal_amount   numeric(14,2) not null default 0,
  discount_amount   numeric(14,2) not null default 0,
  tax_amount        numeric(14,2) not null default 0,
  tax_rate          numeric(5,2) not null default 18,
  other_charges     numeric(14,2) not null default 0,
  total_amount      numeric(14,2) not null default 0,
  paid_amount       numeric(14,2) not null default 0,
  outstanding_amount numeric(14,2) not null default 0,
  payment_status    text not null default 'unpaid'
                      check (payment_status in ('unpaid', 'partial', 'paid')),
  status            text not null default 'ordered'
                      check (status in ('ordered', 'partially_received',
                                        'received', 'cancelled')),
  notes             text not null default '',
  created_by        uuid references public.users (id) on delete set null,
  is_deleted        boolean not null default false,
  deleted_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table if not exists public.purchase_items (
  id             uuid primary key default public.new_id(),
  purchase_id    uuid not null references public.purchases (id) on delete cascade,
  line_number    integer not null default 1,
  product_id     uuid not null references public.products (id),
  inventory_id   uuid references public.inventory (id) on delete set null,
  product_name   text not null default '',
  qty            numeric(12,3) not null default 1,
  received_qty   numeric(12,3) not null default 0,
  unit_cost      numeric(14,2) not null default 0,
  tax_amount     numeric(14,2) not null default 0,
  total_amount   numeric(14,2) not null default 0,
  unique (purchase_id, line_number)
);

-- --------------------------------------------------------------- expenses

create table if not exists public.expense_categories (
  id                uuid primary key default public.new_id(),
  name              text not null unique,
  description       text not null default '',
  icon              text not null default 'receipt_long',
  is_system         boolean not null default false,
  requires_approval boolean not null default false,
  created_at        timestamptz not null default now()
);

create table if not exists public.expenses (
  id                 uuid primary key default public.new_id(),
  showroom_id        uuid not null references public.showrooms (id),
  category_id        uuid not null references public.expense_categories (id),
  expense_number     text not null unique,
  date               date not null default current_date,
  amount             numeric(14,2) not null check (amount > 0),
  payment_mode       text not null default 'cash'
                       check (payment_mode in ('cash', 'card', 'upi', 'cheque',
                                               'neft', 'bank', 'credit')),
  description        text not null default '',
  reference_number   text,
  voucher_number     text,
  attachment_path    text,
  notes              text not null default '',
  requires_approval  boolean not null default false,
  status             text not null default 'pending'
                       check (status in ('pending', 'approved', 'rejected',
                                         'cancelled')),
  created_by         uuid references public.users (id) on delete set null,
  approved_by        uuid references public.users (id) on delete set null,
  approved_at        timestamptz,
  rejected_by        uuid references public.users (id) on delete set null,
  rejection_reason   text,
  is_deleted         boolean not null default false,
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------- service

create table if not exists public.service_records (
  id                  uuid primary key default public.new_id(),
  showroom_id         uuid not null references public.showrooms (id),
  customer_id         uuid not null references public.customers (id),
  vehicle_id          uuid not null references public.customer_vehicles (id),
  service_number      text not null unique,
  job_type            text not null default 'paid'
                        check (job_type in ('paid', 'free', 'warranty',
                                            'insurance', 'recall')),
  booking_date        date not null default current_date,
  service_date        date,
  completed_at        timestamptz,
  odometer_in         numeric(10,1) not null default 0,
  odometer_out        numeric(10,1),
  status              text not null default 'open'
                        check (status in ('open', 'in_progress', 'completed',
                                          'delivered', 'cancelled')),
  service_advisor_id  uuid references public.users (id) on delete set null,
  technician_id       uuid references public.users (id) on delete set null,
  problem_description text not null default '',
  inspection_notes    text not null default '',
  work_done           text not null default '',
  next_service_date   date,
  next_service_km     numeric(10,1),
  subtotal_amount     numeric(14,2) not null default 0,
  discount_amount     numeric(14,2) not null default 0,
  tax_amount          numeric(14,2) not null default 0,
  total_amount        numeric(14,2) not null default 0,
  paid_amount         numeric(14,2) not null default 0,
  outstanding_amount  numeric(14,2) not null default 0,
  is_deleted          boolean not null default false,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table if not exists public.service_items (
  id               uuid primary key default public.new_id(),
  service_id       uuid not null references public.service_records (id) on delete cascade,
  line_number      integer not null default 1,
  item_type        text not null default 'labour'
                     check (item_type in ('labour', 'part', 'oil', 'other')),
  product_id       uuid references public.products (id) on delete set null,
  name             text not null default '',
  qty              numeric(12,3) not null default 1,
  unit_price       numeric(14,2) not null default 0,
  discount_amount  numeric(14,2) not null default 0,
  tax_amount       numeric(14,2) not null default 0,
  total_amount     numeric(14,2) not null default 0,
  unique (service_id, line_number)
);

create table if not exists public.free_service_plans (
  id                 uuid primary key default public.new_id(),
  product_id         uuid not null references public.products (id) on delete cascade,
  service_number     integer not null check (service_number > 0),
  service_days       integer not null default 365,
  service_km         numeric(10,1) not null default 5000,
  free_labour        boolean not null default true,
  included_services  jsonb not null default '[]'::jsonb,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (product_id, service_number)
);

-- One free service granted to a sold vehicle.
-- Named/columned to match FreeServiceGrantModel in the Flutter client.
create table if not exists public.free_service_grants (
  id                uuid primary key default public.new_id(),
  vehicle_id        uuid not null references public.customer_vehicles (id) on delete cascade,
  plan_id           uuid not null references public.free_service_plans (id),
  showroom_id       uuid references public.showrooms (id),
  grant_number      text not null unique,
  plan_name         text not null default '',
  service_number    integer not null default 1,
  start_date        date,
  end_date          date,
  mileage_limit     numeric(10,1),
  used_mileage      numeric(10,1),
  used_service_id   uuid references public.service_records (id) on delete set null,
  used_date         date,
  status            text not null default 'active'
                      check (status in ('active', 'used', 'expired',
                                        'cancelled')),
  created_at        timestamptz not null default now()
);

-- Finance-company EMI plans offered on the sale form.
create table if not exists public.emi_plans (
  id                    uuid primary key default public.new_id(),
  product_id            uuid not null references public.products (id) on delete cascade,
  finance_company_id    uuid references public.finance_companies (id) on delete set null,
  name                  text not null,
  interest_rate         numeric(6,3) not null default 0,
  tenure_months         integer not null default 12,
  down_payment_percent  numeric(5,2) not null default 20,
  processing_fee        numeric(14,2) not null default 0,
  is_active             boolean not null default true,
  sort_order            integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists free_service_grants_vehicle_idx
  on public.free_service_grants (vehicle_id);
create index if not exists emi_plans_product_idx
  on public.emi_plans (product_id) where is_active;

-- ------------------------------------------------- warranty and insurance

create table if not exists public.warranties (
  id               uuid primary key default public.new_id(),
  showroom_id      uuid references public.showrooms (id),
  vehicle_id       uuid not null references public.customer_vehicles (id) on delete cascade,
  sale_id          uuid references public.sales (id) on delete set null,
  warranty_number  text not null unique,
  type             text not null default 'manufacturer'
                     check (type in ('manufacturer', 'extended', 'battery',
                                     'third_party')),
  start_date       date not null,
  end_date         date not null,
  mileage_limit    numeric(10,1),
  coverage         jsonb not null default '[]'::jsonb,
  exclusions       jsonb not null default '[]'::jsonb,
  terms            text not null default '',
  activated_at     timestamptz,
  status           text not null default 'active'
                     check (status in ('active', 'expired', 'claimed',
                                       'cancelled')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.warranty_claims (
  id               uuid primary key default public.new_id(),
  warranty_id      uuid not null references public.warranties (id) on delete cascade,
  service_id       uuid references public.service_records (id) on delete set null,
  claim_number     text not null unique,
  claim_date       date not null default current_date,
  description      text not null default '',
  estimated_cost   numeric(14,2) not null default 0,
  claim_amount     numeric(14,2) not null default 0,
  status           text not null default 'submitted'
                     check (status in ('submitted', 'approved', 'rejected',
                                       'settled')),
  decision_notes   text not null default '',
  resolution       text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.insurance_policies (
  id                     uuid primary key default public.new_id(),
  showroom_id            uuid references public.showrooms (id),
  vehicle_id             uuid not null references public.customer_vehicles (id) on delete cascade,
  insurer                text not null,
  policy_number          text not null,
  policy_type            text not null default 'third_party'
                           check (policy_type in ('third_party',
                                                  'comprehensive', 'zero_dep')),
  coverage_amount        numeric(14,2) not null default 0,
  premium                numeric(14,2) not null default 0,
  start_date             date not null,
  end_date               date not null,
  document_path          text,
  renewal_reminder_sent  boolean not null default false,
  status                 text not null default 'active'
                           check (status in ('active', 'expired', 'cancelled')),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (vehicle_id, policy_number)
);

-- ------------------------------------------- reminders and notifications

create table if not exists public.reminders (
  id               uuid primary key default public.new_id(),
  showroom_id      uuid not null references public.showrooms (id),
  customer_id      uuid references public.customers (id) on delete cascade,
  vehicle_id       uuid references public.customer_vehicles (id) on delete cascade,
  loan_id          uuid references public.loans (id) on delete cascade,
  type             text not null
                     check (type in ('emi_due', 'service_due', 'insurance_expiry',
                                     'warranty_expiry', 'free_service',
                                     'payment_followup', 'custom')),
  title            text not null,
  message          text not null default '',
  reminder_date    date not null,
  priority         text not null default 'normal'
                     check (priority in ('low', 'normal', 'high', 'urgent')),
  status           text not null default 'pending'
                     check (status in ('pending', 'sent', 'completed',
                                       'cancelled')),
  reference_id     uuid,
  reference_type   text,
  push_sent        boolean not null default false,
  completed_at     timestamptz,
  created_by       uuid references public.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.notifications (
  id                 uuid primary key default public.new_id(),
  showroom_id        uuid references public.showrooms (id),
  user_id            uuid references public.users (id) on delete cascade,
  customer_id        uuid references public.customers (id) on delete cascade,
  title              text not null,
  message            text not null default '',
  notification_type  text not null default 'info'
                       check (notification_type in ('info', 'success',
                                                    'warning', 'alert')),
  reference_id       uuid,
  reference_type     text,
  is_read            boolean not null default false,
  sent_at            timestamptz,
  created_at         timestamptz not null default now()
);

-- Push tokens. `user_id` is the Supabase auth user id (the client registers
-- tokens from the auth session, before the profile is necessarily loaded).
create table if not exists public.device_tokens (
  id            uuid primary key default public.new_id(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  device_token  text not null,
  platform      text not null default 'android',
  device_name   text not null default '',
  is_active     boolean not null default true,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  unique (user_id, device_token)
);

-- ------------------------------------------------------- documents/audit

create table if not exists public.attachments (
  id            uuid primary key default public.new_id(),
  showroom_id   uuid references public.showrooms (id),
  entity_type   text not null,
  entity_id     uuid not null,
  file_name     text not null,
  storage_path  text not null,
  mime_type     text not null default '',
  file_size     bigint not null default 0,
  notes         text not null default '',
  uploaded_by   uuid references public.users (id) on delete set null,
  created_at    timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id           uuid primary key default public.new_id(),
  showroom_id  uuid references public.showrooms (id) on delete set null,
  user_id      uuid references public.users (id) on delete set null,
  user_name    text not null default '',
  module       text not null default '',
  action       text not null,
  entity_type  text not null default '',
  entity_id    uuid,
  old_values   jsonb,
  new_values   jsonb,
  ip_address   text,
  user_agent   text,
  notes        text not null default '',
  created_at   timestamptz not null default now()
);

-- Foreign keys that could not be declared in 003 (their target tables are
-- created above). Guarded so the migration stays idempotent.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_service_id_fkey') then
    alter table public.invoices
      add constraint invoices_service_id_fkey
      foreign key (service_id) references public.service_records (id)
      on delete set null;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'payments_service_id_fkey') then
    alter table public.payments
      add constraint payments_service_id_fkey
      foreign key (service_id) references public.service_records (id)
      on delete set null;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'payments_loan_id_fkey') then
    alter table public.payments
      add constraint payments_loan_id_fkey
      foreign key (loan_id) references public.loans (id)
      on delete set null;
  end if;
end
$$;
