-- 003_business_schema.sql
-- Catalog, stock, customers/vehicles, sales, invoicing and payments.
--
-- Column names follow the Dart models (lib/features/*/models), which are the
-- contract the Flutter app actually reads; docs/SPECIFICATION.md lists the
-- same tables with abbreviated field names.

-- ---------------------------------------------------------------- catalog

create table if not exists public.products (
  id               uuid primary key default public.new_id(),
  brand_id         uuid references public.brands (id) on delete set null,
  name             text        not null,
  model            text        not null default '',
  variant          text        not null default '',
  category         text        not null default 'bike',
  engine_cc        integer,
  fuel_type        text        not null default 'petrol',
  transmission     text        not null default 'manual',
  mileage          numeric(6,2),
  description      text        not null default '',
  base_price       numeric(14,2) not null default 0,
  -- `mrp_price` is what the sale form quotes (SaleRepository.accessoriesForProduct).
  mrp_price        numeric(14,2) not null default 0,
  selling_price    numeric(14,2) not null default 0,
  tax_rate         numeric(5,2)  not null default 18,
  warranty_months  integer     not null default 24,
  status           text        not null default 'active'
                     check (status in ('active', 'inactive', 'discontinued')),
  is_deleted       boolean     not null default false,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.product_colors (
  id            uuid primary key default public.new_id(),
  product_id    uuid not null references public.products (id) on delete cascade,
  color_name    text not null,
  hex_code      text not null default '',
  created_at    timestamptz not null default now(),
  unique (product_id, color_name)
);

create table if not exists public.product_images (
  id                 uuid primary key default public.new_id(),
  product_id         uuid not null references public.products (id) on delete cascade,
  image_url          text not null,
  thumbnail_url      text,
  is_primary         boolean not null default false,
  sort_order         integer not null default 0,
  watermark_enabled  boolean not null default true,
  created_at         timestamptz not null default now()
);

-- -------------------------------------------------------------- inventory

-- One row per physical unit (chassis number is the natural key).
create table if not exists public.inventory (
  id                  uuid primary key default public.new_id(),
  showroom_id         uuid not null references public.showrooms (id),
  product_id          uuid not null references public.products (id),
  color_id            uuid references public.product_colors (id) on delete set null,
  stock_code          text not null default '',
  chassis_number      text not null unique,
  engine_number       text unique,
  manufacturing_date  date,
  model_year          integer,
  purchase_date       date,
  purchase_price      numeric(14,2) not null default 0,
  -- Values match lib/core/enums/inventory_enums.dart (InventoryStatus).
  status              text not null default 'available'
                        check (status in ('available', 'reserved', 'sold',
                                          'demo', 'damaged', 'in_transit',
                                          'returned')),
  location            text not null default '',
  is_deleted          boolean not null default false,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- -------------------------------------------------------------- customers

create table if not exists public.customers (
  id               uuid primary key default public.new_id(),
  showroom_id      uuid not null references public.showrooms (id),
  customer_code    text not null default '',
  name             text not null,
  phone            text not null,
  alternate_phone  text not null default '',
  email            text not null default '',
  address          text not null default '',
  city             text not null default '',
  state            text not null default '',
  pincode          text not null default '',
  customer_type    text not null default 'retail'
                     check (customer_type in ('retail', 'corporate',
                                              'government', 'dealer')),
  notes            text not null default '',
  status           text not null default 'active'
                     check (status in ('active', 'inactive', 'blacklisted')),
  is_deleted       boolean not null default false,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.customer_vehicles (
  id                  uuid primary key default public.new_id(),
  customer_id         uuid not null references public.customers (id) on delete cascade,
  showroom_id         uuid references public.showrooms (id),
  inventory_id        uuid references public.inventory (id) on delete set null,
  product_id          uuid references public.products (id) on delete set null,
  registration_number text unique,
  registration_date   date,
  chassis_number      text,
  engine_number       text,
  purchase_date       date,
  delivery_date       date,
  current_odometer    numeric(10,1) not null default 0,
  warranty_start      date,
  warranty_end        date,
  insurance_start     date,
  insurance_end       date,
  next_service_date   date,
  next_service_km     numeric(10,1),
  status              text not null default 'active'
                        check (status in ('active', 'sold', 'scrapped')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ------------------------------------------------------------------ sales

create table if not exists public.sales (
  id                uuid primary key default public.new_id(),
  showroom_id       uuid not null references public.showrooms (id),
  customer_id       uuid not null references public.customers (id),
  vehicle_id        uuid references public.customer_vehicles (id) on delete set null,
  salesperson_id    uuid references public.users (id) on delete set null,
  sale_number       text not null unique,
  sale_date         date not null default current_date,
  subtotal_amount   numeric(14,2) not null default 0,
  discount_amount   numeric(14,2) not null default 0,
  tax_amount        numeric(14,2) not null default 0,
  other_charges     numeric(14,2) not null default 0,
  total_amount      numeric(14,2) not null default 0,
  paid_amount       numeric(14,2) not null default 0,
  balance_amount    numeric(14,2) not null default 0,
  sale_type         text not null default 'retail'
                      check (sale_type in ('retail', 'corporate', 'exchange',
                                           'staff', 'test_ride_conversion')),
  payment_mode      text not null default 'cash'
                      check (payment_mode in ('cash', 'card', 'upi', 'cheque',
                                              'neft', 'emi', 'credit')),
  is_emi            boolean not null default false,
  status            text not null default 'completed'
                      check (status in ('draft', 'completed', 'delivered',
                                        'cancelled')),
  cancel_reason     text,
  notes             text not null default '',
  created_by        uuid references public.users (id) on delete set null,
  is_deleted        boolean not null default false,
  deleted_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (balance_amount = total_amount - paid_amount)
);

create table if not exists public.sale_items (
  id               uuid primary key default public.new_id(),
  sale_id          uuid not null references public.sales (id) on delete cascade,
  line_number      integer not null default 1,
  item_type        text not null default 'vehicle'
                     check (item_type in ('vehicle', 'accessory', 'exchange',
                                          'service', 'other')),
  product_id       uuid references public.products (id) on delete set null,
  inventory_id     uuid references public.inventory (id) on delete set null,
  name             text not null default '',
  description      text not null default '',
  chassis_number   text,
  qty              numeric(12,3) not null default 1,
  unit_price       numeric(14,2) not null default 0,
  discount_amount  numeric(14,2) not null default 0,
  tax_amount       numeric(14,2) not null default 0,
  total_amount     numeric(14,2) not null default 0,
  unique (sale_id, line_number)
);

-- --------------------------------------------------------------- invoicing

create table if not exists public.invoices (
  id                  uuid primary key default public.new_id(),
  showroom_id         uuid not null references public.showrooms (id),
  customer_id         uuid not null references public.customers (id),
  sale_id             uuid references public.sales (id) on delete set null,
  service_id          uuid,
  invoice_number      text not null unique,
  invoice_type        text not null default 'sale'
                        check (invoice_type in ('sale', 'service', 'advance',
                                                'credit_note', 'down_payment')),
  invoice_date        date not null default current_date,
  due_date            date,
  subtotal_amount     numeric(14,2) not null default 0,
  discount_amount     numeric(14,2) not null default 0,
  tax_amount          numeric(14,2) not null default 0,
  total_amount        numeric(14,2) not null default 0,
  paid_amount         numeric(14,2) not null default 0,
  outstanding_amount  numeric(14,2) not null default 0,
  payment_mode        text,
  status              text not null default 'unpaid'
                        check (status in ('unpaid', 'partial', 'paid',
                                          'overdue', 'void')),
  pdf_url             text,
  void_reason         text,
  voided_at           timestamptz,
  notes               text not null default '',
  created_by          uuid references public.users (id) on delete set null,
  is_deleted          boolean not null default false,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (outstanding_amount = total_amount - paid_amount)
);

create table if not exists public.invoice_items (
  id               uuid primary key default public.new_id(),
  invoice_id       uuid not null references public.invoices (id) on delete cascade,
  line_number      integer not null default 1,
  item_type        text not null default 'vehicle',
  product_id       uuid references public.products (id) on delete set null,
  description      text not null default '',
  qty              numeric(12,3) not null default 1,
  unit_price       numeric(14,2) not null default 0,
  discount_amount  numeric(14,2) not null default 0,
  tax_rate         numeric(5,2) not null default 0,
  tax_amount       numeric(14,2) not null default 0,
  total_amount     numeric(14,2) not null default 0,
  unique (invoice_id, line_number)
);

-- --------------------------------------------------------------- payments

create table if not exists public.payments (
  id                  uuid primary key default public.new_id(),
  showroom_id         uuid not null references public.showrooms (id),
  customer_id         uuid references public.customers (id) on delete set null,
  invoice_id          uuid references public.invoices (id) on delete set null,
  sale_id             uuid references public.sales (id) on delete set null,
  service_id          uuid,
  loan_id             uuid,
  emi_installment_no  integer,
  payment_number      text not null unique,
  payment_date        date not null default current_date,
  amount              numeric(14,2) not null check (amount <> 0),
  payment_mode        text not null default 'cash'
                        check (payment_mode in ('cash', 'card', 'upi', 'cheque',
                                                'neft', 'wallet', 'bank',
                                                'credit', 'refund')),
  reference_number    text,
  transaction_id      text,
  status              text not null default 'completed'
                        check (status in ('pending', 'completed', 'failed',
                                          'refunded', 'cancelled')),
  is_down_payment     boolean not null default false,
  is_emi              boolean not null default false,
  is_refunded         boolean not null default false,
  refund_reason       text,
  refunded_at         timestamptz,
  notes               text not null default '',
  received_by         uuid references public.users (id) on delete set null,
  is_deleted          boolean not null default false,
  deleted_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Accessories offered with a product (SaleRepository.accessoriesForProduct).
create table if not exists public.product_accessories (
  id            uuid primary key default public.new_id(),
  product_id    uuid not null references public.products (id) on delete cascade,
  accessory_id  uuid not null references public.products (id) on delete cascade,
  is_active     boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  unique (product_id, accessory_id)
);

-- Per-unit stock movement log (InventoryRepository.history).
create table if not exists public.stock_history (
  id            uuid primary key default public.new_id(),
  inventory_id  uuid not null references public.inventory (id) on delete cascade,
  showroom_id   uuid references public.showrooms (id) on delete set null,
  action        text not null,
  from_status   text,
  to_status     text,
  notes         text not null default '',
  created_by    uuid references public.users (id) on delete set null,
  created_at    timestamptz not null default now()
);

-- Inter-showroom transfer requests (InventoryRepository.transfers).
create table if not exists public.stock_transfers (
  id                uuid primary key default public.new_id(),
  from_showroom_id  uuid not null references public.showrooms (id),
  to_showroom_id    uuid not null references public.showrooms (id),
  transfer_date     date not null default current_date,
  unit_count        integer not null default 0,
  status            text not null default 'completed'
                      check (status in ('pending', 'in_transit', 'completed',
                                        'cancelled')),
  notes             text not null default '',
  created_by        uuid references public.users (id) on delete set null,
  created_at        timestamptz not null default now()
);

create index if not exists stock_history_inventory_idx
  on public.stock_history (inventory_id, created_at desc);
create index if not exists product_accessories_product_idx
  on public.product_accessories (product_id);
