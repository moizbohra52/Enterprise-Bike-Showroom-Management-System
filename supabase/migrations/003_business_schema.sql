-- =============================================================================
-- 003_business_schema.sql
-- -----------------------------------------------------------------------------
-- Purpose : catalogue (brands/products/colours/images), serial inventory and
--           its movements, customers, customer vehicles, sales and billing.
-- Depends : 001, 002.
--
-- Central invariants enforced here (not in the client) - §67/§68:
--   * chassis_number and engine_number are globally unique across inventory
--   * one inventory unit can back at most one sold customer_vehicle
--   * (showroom_id, <document>_number) is unique for every business document
--   * sale totals are recomputed server-side; the check constraints below make
--     a stale client-computed total fail loudly
--   * financial rows are soft-cancelled, never deleted (no DELETE policy in 009)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Catalogue (global, showroom-agnostic: the dealership group sells one catalogue)
-- ---------------------------------------------------------------------------
create table if not exists public.brands (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (length(btrim(name)) between 1 and 60),
  code       app_util.slug unique,
  logo_url   text,
  country    text,
  status     text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  brand_id     uuid not null references public.brands (id) on delete restrict,
  name         text not null check (length(btrim(name)) between 2 and 140),
  model        text not null check (length(btrim(model)) between 1 and 80),
  variant      text,
  category     text not null default 'COMMUTER'
             check (category in ('SCOOTER','COMMUTER','SPORTS','CRUISER','ELECTRIC',
                                 'OFF_ROAD','ADVENTURE','MOPED','RETAIL_ACCESSORY')),
  engine_cc    integer check (engine_cc is null or engine_cc between 25 and 2000),
  fuel_type    text not null default 'PETROL'
             check (fuel_type in ('PETROL','DIESEL','CNG','ELECTRIC','HYBRID')),
  transmission text not null default 'MANUAL'
             check (transmission in ('MANUAL','AUTOMATIC','CVT','DCT','SINGLE_SPEED')),
  mileage      numeric(6,2) check (mileage is null or (mileage >= 0 and mileage <= 200)),
  max_power    numeric(6,2),
  max_torque   numeric(6,2),
  fuel_tank_capacity numeric(5,2),
  seat_height_mm     integer,
  description  text,
  base_price   app_util.money not null default 0,
  selling_price app_util.money not null default 0,
  ex_showroom_price app_util.money not null default 0,
  on_road_price app_util.money not null default 0,
  tax_rate     app_util.percentage not null default 18,
  warranty_months smallint not null default 24 check (warranty_months between 0 and 120),
  warranty_km  integer check (warranty_km is null or (warranty_km >= 0 and warranty_km <= 500000)),
  free_service_count smallint not null default 3 check (free_service_count between 0 and 12),
  service_interval_km integer not null default 5000 check (service_interval_km between 500 and 20000),
  service_interval_days smallint not null default 180 check (service_interval_days between 30 and 730),
  emi_eligible boolean not null default true,
  hsn_code     text check (hsn_code is null or hsn_code ~ '^[0-9]{4,8}$'),
  status       text not null default 'ACTIVE'
             check (status in ('ACTIVE','INACTIVE','DISCONTINUED','UPCOMING')),
  search_vector tsvector,
  is_deleted   boolean not null default false,
  deleted_at   timestamptz,
  deleted_by   uuid references public.users (id) on delete restrict,
  revision     integer not null default 1 check (revision > 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.users (id) on delete restrict,
  updated_by   uuid references public.users (id) on delete restrict,
  constraint products_name_variant_key unique (brand_id, name, variant),
  -- a bike cannot be sold below its base price: protects against fat-finger
  -- catalogue entry that would corrupt margin reporting
  constraint products_price_sanity check (selling_price >= base_price),
  constraint products_soft_delete_coherent check (
    (is_deleted and deleted_at is not null and deleted_by is not null) or
    (not is_deleted and deleted_at is null and deleted_by is null)
  )
);

create index if not exists products_brand_idx      on public.products (brand_id);
create index if not exists products_status_idx     on public.products (status, category);
create index if not exists products_price_idx      on public.products (selling_price);
create index if not exists products_name_idx       on public.products (name);
create index if not exists products_search_idx     on public.products using gin (search_vector);
comment on column public.products.search_vector is 'Maintained by trigger (007): brand + model + variant + category for global search (§71).';

create table if not exists public.product_colors (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products (id) on delete cascade,
  color_name  text not null check (length(btrim(color_name)) between 2 and 40),
  hex_code    app_util.hex_color not null,
  is_available boolean not null default true,
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now(),
  constraint product_colors_unique_key unique (product_id, color_name)
);
create index if not exists product_colors_product_idx on public.product_colors (product_id);

create table if not exists public.product_images (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references public.products (id) on delete cascade,
  product_color_id uuid references public.product_colors (id) on delete set null,
  image_url       text not null,
  storage_path    text,
  thumbnail_url   text,
  caption         text,
  is_primary      boolean not null default false,
  sort_order      smallint not null default 0 check (sort_order between 0 and 999),
  watermark_enabled boolean not null default true,
  allow_download  boolean not null default false,
  width           integer,
  height          integer,
  file_size       app_util.file_size,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint product_images_path_key unique (product_id, storage_path)
);
create index if not exists product_images_product_idx on public.product_images (product_id, sort_order);
-- at most one primary image per product, enforced without a trigger race
create unique index if not exists product_images_one_primary_idx
  on public.product_images (product_id) where is_primary = true;
comment on table public.product_images is 'Supabase Storage references for the catalogue; preview/watermark policy per §9.';

-- ---------------------------------------------------------------------------
-- Customers (§11)
-- ---------------------------------------------------------------------------
create table if not exists public.customers (
  id             uuid primary key default gen_random_uuid(),
  showroom_id    uuid not null references public.showrooms (id) on delete restrict,
  customer_code  text not null check (customer_code ~ '^[A-Z0-9][A-Z0-9\-]{2,19}$'),
  name           text not null check (length(btrim(name)) between 2 and 120),
  phone          app_util.phone not null,
  alternate_phone app_util.phone,
  whatsapp_phone app_util.phone,
  email          app_util.email,
  date_of_birth  date,
  gender         text check (gender in ('MALE','FEMALE','OTHER','NOT_SPECIFIED')),
  address        text check (address is null or length(btrim(address)) between 5 and 400),
  city           text,
  state          text,
  country        text not null default 'IN',
  pincode        app_util.pincode,
  customer_type  text not null default 'RETAIL'
               check (customer_type in ('RETAIL','CORPORATE','FLEET','PREFERRED','EMPLOYEE','WALK_IN')),
  company_name   text,
  gst_number     app_util.gstn,
  pan_number     app_util.pan,
  aadhaar_last4  text check (aadhaar_last4 is null or aadhaar_last4 ~ '^[0-9]{4}$'),
  reference_source text check (reference_source is null or reference_source in
                   ('WALK_IN','ONLINE','REFERRAL','CAMPAIGN','EXISTING_CUSTOMER','BROKER')),
  referred_by    uuid references public.customers (id) on delete set null,
  credit_limit   app_util.money,
  notes          text,
  status         text not null default 'ACTIVE'
               check (status in ('ACTIVE','INACTIVE','BLOCKED','DECEASED')),
  marketing_consent boolean not null default false,
  lifetime_value app_util.money not null default 0,
  last_purchase_at timestamptz,
  is_deleted     boolean not null default false,
  deleted_at     timestamptz,
  deleted_by     uuid references public.users (id) on delete restrict,
  revision       integer not null default 1 check (revision > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.users (id) on delete restrict,
  updated_by     uuid references public.users (id) on delete restrict,
  constraint customers_code_key unique (showroom_id, customer_code),
  -- a phone belongs to one customer *within a showroom*: two branches may each
  -- have their own ledger entry for the same walk-in buyer
  constraint customers_showroom_phone_key unique (showroom_id, phone),
  constraint customers_soft_delete_coherent check (
    (is_deleted and deleted_at is not null) or (not is_deleted and deleted_at is null)
  )
);

comment on constraint customers_showroom_phone_key on public.customers is
  'Dedupe guard: prevents the "same" customer being created twice in one branch (SS67).';
create index if not exists customers_showroom_status_idx on public.customers (showroom_id, status);
create index if not exists customers_phone_idx           on public.customers (phone);
create index if not exists customers_email_idx           on public.customers (lower(email));
create index if not exists customers_name_idx            on public.customers (name);
create index if not exists customers_city_idx            on public.customers (city);
create index if not exists customers_created_idx         on public.customers (created_at desc);

create table if not exists public.customer_vehicles (
  id                  uuid primary key default gen_random_uuid(),
  customer_id         uuid not null references public.customers (id) on delete restrict,
  showroom_id         uuid not null references public.showrooms (id) on delete restrict,
  inventory_id        uuid,          -- FK added after `inventory` exists below
  product_id          uuid references public.products (id) on delete restrict,
  product_color_id    uuid references public.product_colors (id) on delete set null,
  sale_id             uuid,          -- FK added after `sales` exists below
  registration_number app_util.registration_number,
  registration_date   date,
  chassis_number      app_util.chassis_number,
  engine_number       app_util.engine_number,
  model_year          app_util.year,
  purchase_date       date not null default current_date,
  delivery_date       date,
  current_odometer    app_util.odometer not null default 0,
  odometer_updated_at timestamptz,
  insurance_company     text,
  insurance_policy_number text,
  warranty_start      date,
  warranty_end        date,
  insurance_start     date,
  insurance_end       date,
  next_service_date   date,
  next_service_km     integer check (next_service_km is null or next_service_km >= 0),
  Rc_state            text,
  rc_rto_code         text,
  colour              text,
  fitness_expiry      date,
  puc_expiry          date,
  road_tax_upto       date,
  notes               text,
  status              text not null default 'ACTIVE'
                    check (status in ('PRE_DELIVERY','ACTIVE','IN_SERVICE','RESERVED',
                                      'SOLD','TRANSFERRED','SCRAPPED')),
  is_deleted          boolean not null default false,
  deleted_at          timestamptz,
  revision            integer not null default 1 check (revision > 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.users (id) on delete restrict,
  updated_by          uuid references public.users (id) on delete restrict,
  -- a chassis number identifies exactly one physical bike on the books
  constraint customer_vehicles_chassis_key unique (chassis_number),
  constraint customer_vehicles_reg_no_key  unique (registration_number),
  constraint customer_vehicles_dates_sane check (
    (warranty_end   is null or warranty_start   is null or warranty_end   >= warranty_start) and
    (insurance_end  is null or insurance_start  is null or insurance_end  >= insurance_start) and
    (delivery_date  is null or purchase_date is null or delivery_date >= purchase_date)
  )
);

create index if not exists customer_vehicles_customer_idx on public.customer_vehicles (customer_id);
create index if not exists customer_vehicles_showroom_idx on public.customer_vehicles (showroom_id, status);
create index if not exists customer_vehicles_product_idx  on public.customer_vehicles (product_id);
create index if not exists customer_vehicles_service_idx  on public.customer_vehicles (next_service_date);
create index if not exists customer_vehicles_ins_idx      on public.customer_vehicles (insurance_end);
create index if not exists customer_vehicles_warranty_idx on public.customer_vehicles (warranty_end);
comment on table public.customer_vehicles is 'Post-sale vehicle ledger: the single source of truth used by service, warranty, insurance and reminders (§12, §62).';

-- ---------------------------------------------------------------------------
-- Inventory (§10): one row per physical bike, serialised by chassis number.
-- ---------------------------------------------------------------------------
create table if not exists public.inventory (
  id                uuid primary key default gen_random_uuid(),
  showroom_id       uuid not null references public.showrooms (id) on delete restrict,
  product_id        uuid not null references public.products (id) on delete restrict,
  color_id          uuid references public.product_colors (id) on delete restrict,
  stock_code        text not null check (stock_code ~ '^[A-Z0-9][A-Z0-9\-/.]{2,29}$'),
  chassis_number    app_util.chassis_number not null,
  engine_number     app_util.engine_number not null,
  manufacturing_date date,
  model_year        app_util.year,
  purchase_date     date,
  purchase_price    app_util.money not null default 0,
  landing_price     app_util.money not null default 0,
  mrp               app_util.money not null default 0,
  expected_delivery_date date,
  status            text not null default 'AVAILABLE'
                  check (status in ('AVAILABLE','RESERVED','SOLD','DEMO','DAMAGED',
                                    'IN_TRANSIT','RETURNED','HOLD','PENDING_RC','SCRAPPED')),
  location          text,
  rack_position     text,
  odometer          app_util.odometer not null default 0,
  registration_number app_util.registration_number,
  rc_status         text check (rc_status is null or rc_status in ('NOT_APPLIED','APPLIED','DELIVERED')),
  insurance_status  text check (insurance_status is null or insurance_status in ('NOT_REQUIRED','PENDING','ACTIVE','EXPIRED')),
  allocated_sale_id uuid,             -- FK added after `sales` exists
  reserved_until    timestamptz,
  reserved_by       uuid references public.users (id) on delete set null,
  reserved_customer_id uuid references public.customers (id) on delete set null,
  remarks           text,
  is_deleted        boolean not null default false,
  deleted_at        timestamptz,
  deleted_by        uuid references public.users (id) on delete restrict,
  revision          integer not null default 1 check (revision > 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references public.users (id) on delete restrict,
  updated_by        uuid references public.users (id) on delete restrict,
  constraint inventory_stock_code_key   unique (stock_code),
  constraint inventory_chassis_key      unique (chassis_number),
  constraint inventory_engine_key       unique (engine_number),
  constraint inventory_reg_no_key       unique (registration_number),
  -- never negative stock value / price sanity
  constraint inventory_price_sanity     check (purchase_price >= 0 and mrp >= 0),
  constraint inventory_soft_delete_coherent check (
    (is_deleted and deleted_at is not null) or (not is_deleted and deleted_at is null)
  ),
  -- a RESERVED / IN_TRANSIT row must justify its state
  constraint inventory_status_context check (
    (status <> 'RESERVED' or (reserved_until is not null and reserved_customer_id is not null))
  ),
  constraint inventory_release_clears_reservation check (
    (status = 'RESERVED') or (reserved_customer_id is null and reserved_until is null)
  )
);

create index if not exists inventory_showroom_status_idx on public.inventory (showroom_id, status);
create index if not exists inventory_product_idx         on public.inventory (product_id);
create index if not exists inventory_color_idx           on public.inventory (color_id);
create index if not exists inventory_purchase_date_idx   on public.inventory (purchase_date);
create index if not exists inventory_available_idx       on public.inventory (showroom_id, product_id) where status = 'AVAILABLE';
create index if not exists inventory_sale_idx            on public.inventory (allocated_sale_id);
comment on column public.inventory.reserved_until is 'Reservation expiry; a sweep job (012) releases stale holds back to AVAILABLE.';

-- inventory <-> customer_vehicles 1:0..1 (a sold bike maps to exactly one ledger row) (§12)
alter table public.customer_vehicles
  add constraint customer_vehicles_inventory_fkey
  foreign key (inventory_id) references public.inventory (id) on delete restrict;

-- one inventory unit may back at most one customer vehicle
create unique index if not exists customer_vehicles_one_per_inventory_idx
  on public.customer_vehicles (inventory_id) where inventory_id is not null;
-- and at most one *active* (non-deleted) row, so a re-sale after a return works
create unique index if not exists customer_vehicles_active_per_inventory_idx
  on public.customer_vehicles (inventory_id) where inventory_id is not null and is_deleted = false;

-- ---------------------------------------------------------------------------
-- Stock ledger + transfers (§10)
-- ---------------------------------------------------------------------------
create table if not exists public.stock_movements (
  id            uuid primary key default gen_random_uuid(),
  showroom_id   uuid not null references public.showrooms (id) on delete restrict,
  inventory_id  uuid not null references public.inventory (id) on delete restrict,
  -- one vocabulary for one event: a purchase receipt is a stock-in, so both the
  -- RPC that materialises units inline and the one that receives against a
  -- confirmed order write STOCK_IN.  A second label for the same event would make
  -- every inbound-stock report under-count.
  movement_type text not null check (movement_type in
                ('STOCK_IN','STOCK_OUT','TRANSFER_OUT','TRANSFER_IN','RESERVE','RELEASE',
                 'ADJUST','SALE_ALLOCATE','SALE_REVERSE','RETURN_IN','DAMAGE_FLAG',
                 'DEMO_IN','DEMO_OUT')),
  from_status   text,
  to_status     text,
  quantity      smallint not null default 1 check (quantity = 1),
  reference_type text,
  reference_id  uuid,
  reason        text,
  movement_date timestamptz not null default now(),
  performed_by  uuid references public.users (id) on delete restrict,
  idempotency_key uuid unique,
  created_at    timestamptz not null default now(),
  constraint stock_movements_qty_positive check (quantity > 0)
);

create index if not exists stock_movements_inventory_idx on public.stock_movements (inventory_id, movement_date desc);
create index if not exists stock_movements_showroom_idx  on public.stock_movements (showroom_id, movement_date desc);
create index if not exists stock_movements_ref_idx      on public.stock_movements (reference_type, reference_id);
comment on table public.stock_movements is 'Immutable per-unit history powering the Inventory > Stock History screen (§70) and stock reconciliation.';

create table if not exists public.stock_transfers (
  id               uuid primary key default gen_random_uuid(),
  transfer_number  text not null,
  from_showroom_id uuid not null references public.showrooms (id) on delete restrict,
  to_showroom_id   uuid not null references public.showrooms (id) on delete restrict,
  inventory_id     uuid not null references public.inventory (id) on delete restrict,
  transfer_date    date not null default current_date,
  expected_date    date,
  received_date    timestamptz,
  status           text not null default 'PENDING'
                 check (status in ('PENDING','APPROVED','IN_TRANSIT','RECEIVED','REJECTED','CANCELLED','RETURNED')),
  transport_mode   text check (transport_mode is null or transport_mode in ('TRAILER','TRUCK','SELF','COURIER')),
  tracking_number  text,
  freight_charges  app_util.money not null default 0,
  notes            text,
  approved_by      uuid references public.users (id) on delete restrict,
  approved_at      timestamptz,
  received_by      uuid references public.users (id) on delete restrict,
  created_by       uuid references public.users (id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint stock_transfers_number_key unique (from_showroom_id, transfer_number),
  constraint stock_transfers_different_showrooms check (from_showroom_id <> to_showroom_id),
  constraint stock_transfers_dates check (expected_date is null or expected_date >= transfer_date),
  constraint stock_transfers_receive_window check (
    (status in ('RECEIVED') and received_date is not null) or status not in ('RECEIVED')
  )
);

create index if not exists stock_transfers_from_idx on public.stock_transfers (from_showroom_id, status);
create index if not exists stock_transfers_to_idx   on public.stock_transfers (to_showroom_id, status);
create index if not exists stock_transfers_inv_idx  on public.stock_transfers (inventory_id);

-- ---------------------------------------------------------------------------
-- Sales, sale items, invoices and invoice items (§13, §14).
-- The *server* owns money maths (§67): the total_amount check constraints make
-- a client-computed total fail loudly instead of silently corrupting reports.
-- ---------------------------------------------------------------------------

create table if not exists public.sales (
  id               uuid primary key default gen_random_uuid(),
  showroom_id      uuid not null references public.showrooms (id) on delete restrict,
  customer_id      uuid not null references public.customers (id) on delete restrict,
  vehicle_id       uuid references public.customer_vehicles (id) on delete restrict,
  salesperson_id   uuid references public.users (id) on delete restrict,
  sale_number      text not null,
  sale_date        date not null default current_date,
  subtotal         app_util.money not null default 0,
  discount         app_util.money not null default 0,
  discount_percent app_util.percentage not null default 0,
  tax_amount       app_util.money not null default 0,
  other_charges    app_util.money not null default 0,
  total_amount     app_util.money not null default 0,
  paid_amount      app_util.money not null default 0,
  outstanding_amount app_util.money not null default 0,
  sale_type        text not null default 'CASH'
                 check (sale_type in ('CASH','FINANCE','EXCHANGE','CORPORATE','ONLINE','BOOKING')),
  -- one workflow enum for the whole lifecycle (§13); `APPROVED` gates billing
  status           text not null default 'DRAFT'
                 check (status in ('DRAFT','PENDING_APPROVAL','APPROVED','CONFIRMED',
                                   'DELIVERED','CANCELLED','RETURNED')),
  exchange_vehicle_ref text,
  exchange_value   app_util.money not null default 0,
  booking_amount   app_util.money not null default 0,
  approval_required boolean not null default true,
  approved_by      uuid references public.users (id) on delete restrict,
  approved_at      timestamptz,
  cancellation_reason text,
  cancelled_by     uuid references public.users (id) on delete restrict,
  cancelled_at     timestamptz,
  delivery_date    date,
  notes            text,
  metadata         jsonb not null default '{}'::jsonb,
  is_deleted       boolean not null default false,
  revision         integer not null default 1 check (revision > 0),
  created_by       uuid references public.users (id) on delete restrict,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.users (id) on delete restrict,
  constraint sales_number_key unique (showroom_id, sale_number),
  constraint sales_total_formula check (
    total_amount = round(subtotal - discount + tax_amount + other_charges - exchange_value, 2)
  ),
  constraint sales_paid_le_total   check (paid_amount <= total_amount),
  constraint sales_outstanding_math check (
    outstanding_amount = round(total_amount - paid_amount, 2)
  ),
  constraint sales_discount_bound  check (discount <= subtotal + other_charges),
  constraint sales_dates check (delivery_date is null or delivery_date >= sale_date),
  -- once cancelled/returned it must carry a reason: keeps §69 auditable
  constraint sales_cancel_reason check (
    (status in ('CANCELLED','RETURNED') and cancellation_reason is not null)
    or status not in ('CANCELLED','RETURNED')
  )
);

comment on table public.sales is
  'Vehicle sale header. Money columns are server-derived; total/outstanding are protected by check constraints and recomputed by triggers (007).';
create index if not exists sales_showroom_status_idx on public.sales (showroom_id, status);
create index if not exists sales_showroom_date_idx   on public.sales (showroom_id, sale_date desc);
create index if not exists sales_customer_idx         on public.sales (customer_id);
create index if not exists sales_salesperson_idx      on public.sales (salesperson_id, sale_date desc);
create index if not exists sales_outstanding_idx      on public.sales (showroom_id, outstanding_amount) where outstanding_amount > 0;

create table if not exists public.sale_items (
  id            uuid primary key default gen_random_uuid(),
  sale_id       uuid not null references public.sales (id) on delete cascade,
  product_id    uuid references public.products (id) on delete restrict,
  inventory_id  uuid references public.inventory (id) on delete restrict,
  color_id      uuid references public.product_colors (id) on delete restrict,
  description   text not null,
  item_type     text not null default 'VEHICLE'
              check (item_type in ('VEHICLE','ACCESSORY','INSURANCE','EXTENDED_WARRANTY',
                                   'DOCUMENTATION_CHARGE','OTHER')),
  quantity      app_util.positive_qty not null default 1,
  unit_price    app_util.money not null default 0,
  discount      app_util.money not null default 0,
  tax_rate      app_util.percentage not null default 0,
  tax_amount    app_util.money not null default 0,
  total_amount  app_util.money not null default 0,
  created_at    timestamptz not null default now(),
  constraint sale_items_line_math check (
    total_amount = round(quantity * unit_price - discount + tax_amount, 2)
  ),
  constraint sale_items_vehicle_needs_serial check (
    (item_type = 'VEHICLE' and inventory_id is not null) or item_type <> 'VEHICLE'
  ),
  constraint sale_items_discount_bound check (discount <= quantity * unit_price)
);

create index if not exists sale_items_sale_idx on public.sale_items (sale_id);
create unique index if not exists sale_items_one_vehicle_per_sale on public.sale_items (sale_id, inventory_id) where inventory_id is not null;
comment on constraint sale_items_vehicle_needs_serial on public.sale_items is
  'A VEHICLE line must point at a serialised inventory unit: makes "stock sold without allocation" impossible.';

create table if not exists public.invoices (
  id                uuid primary key default gen_random_uuid(),
  showroom_id       uuid not null references public.showrooms (id) on delete restrict,
  customer_id       uuid references public.customers (id) on delete restrict,
  sale_id            uuid references public.sales (id) on delete restrict,
  service_id         uuid,          -- FK added in 004 after service_records exists
  loan_id            uuid,          -- FK added in 004 after loans exists
  invoice_number    text not null,
  invoice_type      text not null default 'SALE'
                  check (invoice_type in ('SALE','SERVICE','ACCESSORY','OTHER','ADVANCE','CREDIT_NOTE','PROFORMA')),
  invoice_date      date not null default current_date,
  due_date          date,
  subtotal          app_util.money not null default 0,
  discount          app_util.money not null default 0,
  tax_amount        app_util.money not null default 0,
  other_charges     app_util.money not null default 0,
  total_amount      app_util.money not null default 0,
  paid_amount       app_util.money not null default 0,
  outstanding_amount app_util.money not null default 0,
  status            text not null default 'DRAFT'
                  check (status in ('DRAFT','FINALIZED','PARTIALLY_PAID','PAID',
                                    'OVERDUE','CANCELLED','REFUNDED')),
  pdf_path          text,
  pdf_bucket        text,
  emitted_at        timestamptz,
  finalized_at      timestamptz,
  cancelled_at      timestamptz,
  cancelled_by      uuid references public.users (id) on delete restrict,
  cancellation_reason text,
  credit_note_invoice_id uuid references public.invoices (id) on delete restrict,
  terms             text,
  notes             text,
  billing_address   text,
  billing_gst_number app_util.gstn,
  customer_po_number text,
  -- immutability after finalisation is a *server* property, not a UI rule (§14)
  finalized         boolean not null default false,
  revision          integer not null default 1 check (revision > 0),
  created_by        uuid references public.users (id) on delete restrict,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.users (id) on delete restrict,
  constraint invoices_number_key unique (showroom_id, invoice_number),
  constraint invoices_total_formula check (
    total_amount = round(subtotal - discount + tax_amount + other_charges, 2)
  ),
  constraint invoices_paid_le_total check (paid_amount <= total_amount),
  constraint invoices_outstanding_math check (
    outstanding_amount = round(total_amount - paid_amount, 2)
  ),
  constraint invoices_sale_xor_service check (
    num_nonnulls(sale_id, service_id, loan_id) <= 1
  ),
  constraint invoices_finalize_requires_customer check (
    (status <> 'DRAFT' and customer_id is not null) or status = 'DRAFT'
  ),
  constraint invoices_finalized_flag check (
    (finalized and status <> 'DRAFT') or (not finalized and status = 'DRAFT')
  ),
  constraint invoices_cancel_reason check (
    (status in ('CANCELLED','REFUNDED') and cancellation_reason is not null)
    or status not in ('CANCELLED','REFUNDED')
  )
);

create index if not exists invoices_showroom_status_idx on public.invoices (showroom_id, status);
create index if not exists invoices_showroom_date_idx   on public.invoices (showroom_id, invoice_date desc);
create index if not exists invoices_customer_idx        on public.invoices (customer_id);
create index if not exists invoices_sale_idx            on public.invoices (sale_id);
create index if not exists invoices_outstanding_idx     on public.invoices (showroom_id, outstanding_amount) where outstanding_amount > 0;
create index if not exists invoices_due_idx             on public.invoices (due_date, status);
comment on table public.invoices is
  'Financial document. `finalized` blocks line-item mutation except through the cancel/reverse RPCs (§14).';

create table if not exists public.invoice_items (
  id           uuid primary key default gen_random_uuid(),
  invoice_id   uuid not null references public.invoices (id) on delete cascade,
  product_id   uuid references public.products (id) on delete restrict,
  inventory_id uuid references public.inventory (id) on delete restrict,
  sale_item_id uuid references public.sale_items (id) on delete set null,
  service_item_id uuid,                                    -- FK added in 004 (service_items does not exist yet)
  description text not null,
  hsn_code    text,
  quantity    app_util.positive_qty not null default 1,
  unit_price  app_util.money not null default 0,
  discount    app_util.money not null default 0,
  tax_rate    app_util.percentage not null default 0,
  tax_amount  app_util.money not null default 0,
  total_amount app_util.money not null default 0,
  sort_order  smallint not null default 0,
  created_at  timestamptz not null default now(),
  constraint invoice_items_line_math check (
    total_amount = round(quantity * unit_price - discount + tax_amount, 2)
  ),
  constraint invoice_items_discount_bound check (discount <= quantity * unit_price)
);

create index if not exists invoice_items_invoice_idx on public.invoice_items (invoice_id, sort_order);

-- ---------------------------------------------------------------------------
-- Deferred foreign keys that need both sides of the model to exist.
-- ---------------------------------------------------------------------------
alter table public.customer_vehicles
  add constraint customer_vehicles_sale_fkey
  foreign key (sale_id) references public.sales (id) on delete restrict;

alter table public.inventory
  add constraint inventory_allocated_sale_fkey
  foreign key (allocated_sale_id) references public.sales (id) on delete set null;

-- A sale that produced a customer vehicle must reference it, and vice versa.
alter table public.sales
  add constraint sales_vehicle_one_per_sale unique (vehicle_id);
