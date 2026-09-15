-- =============================================================================
-- 014_seed_data.sql  (SS81, SS82)
-- -----------------------------------------------------------------------------
-- Production-safe reference seed: the vocabulary the application cannot start
-- without.  It contains NO customer, sales or financial data.
--
--   * application settings (single source of truth for a fresh install)
--   * one default showroom so the very first admin has something to attach to
--   * brands + a starter catalogue + colours
--   * expense categories wired to the chart of accounts
--   * free-service plans derived from the catalogue
--   * finance companies and suppliers (B2B reference data)
--
-- Roles/permissions are seeded by 008 and the chart of accounts is created per
-- showroom by the 013 trigger.  Everything here is idempotent.
--
-- Demo business data (customers, stock, sales) lives in supabase/seed.sql,
-- which `supabase db reset` loads for local development only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Application settings
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, value, scope, description) values
  ('app.version_supported',        '{"min": "1.0.0"}', 'GLOBAL', 'Lowest client version the API accepts'),
  ('feature.offline_enabled',      'true',  'GLOBAL', 'Offline queue + sync master switch'),
  ('feature.sync_interval_seconds','60',    'GLOBAL', 'Background sync cadence when online'),
  ('feature.realtime_enabled',     'true',  'GLOBAL', 'Supabase Realtime subscriptions'),
  ('feature.allow_advance_payment','true',  'GLOBAL', 'Payments above the outstanding balance create a credit'),
  ('documents.signed_url_ttl',     '900',   'GLOBAL', 'Signed URL lifetime in seconds (SS53)'),
  ('invoices.footer_text',
   '{"en":"Goods once sold are subject to manufacturer warranty terms. Prices inclusive of applicable taxes."}',
   'GLOBAL', 'Printed on every invoice PDF'),
  ('invoices.terms_text',
   '{"en":"Payment due before delivery. Cancellations after finalisation are subject to approval."}',
   'GLOBAL', 'Default invoice terms'),
  ('notifications.templates',
   '{"emi":"Dear {customer}, your EMI of {amount} for {loanNumber} is due on {dueDate}.","service":"Hi {customer}, your {product} is due for service on {dueDate}.","insurance":"{customer}, your insurance {policyNumber} expires on {expiryDate}."}',
   'GLOBAL', 'Reminder message templates; Flutter and SQL both render these'),
  ('localisation.default_locale',  '"en-IN"', 'GLOBAL', 'Initial locale (SS75); Hindi ships as a translation pack'),
  ('pagination.default_page_size', '20',      'GLOBAL', 'SS73 default page size'),
  ('pagination.allowed_page_sizes','[20,50,100]', 'GLOBAL', 'SS73'),
  ('security.max_discount_percent_without_approval','5', 'GLOBAL', 'Mirrors the check in create_sale_transaction (SS6)'),
  ('security.password_min_length', '10', 'GLOBAL', 'Advertised to the client; enforced by Supabase Auth')
on conflict (key) do update
   set value = excluded.value, description = excluded.description, updated_at = now();

-- ---------------------------------------------------------------------------
-- A single default showroom so a fresh install is operable. Rename/expand it
-- from Showroom Management; multi-showroom data starts from here.
-- ---------------------------------------------------------------------------
insert into public.showrooms (name, code, legal_name, address, city, state, pincode, phone, email,
                              gst_number, invoice_prefix, status, settings)
values ('Enterprise Motors - Main Showroom', 'DEFAULT', 'Enterprise Motors Pvt Ltd',
        'No. 12, Showroom Road, Industrial Layout', 'Bengaluru', 'Karnataka', '560001',
        '08040001234', 'headoffice@example-motors.in', '29ABCDE1234F1Z5', 'INV', 'ACTIVE',
        '{"watermark_images": true,"allow_image_download": false,"preview_only": false,
          "allow_negative_inventory": false,"gst_rate": 18,"service_tax_rate": 18,
          "low_stock_threshold": 2,"sale_approval_threshold": 500000,
          "invoice_footer":"Thank you for choosing us. Ride safe, service on time."}'::jsonb)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Brands
-- ---------------------------------------------------------------------------
insert into public.brands (name, code, country, status)
select b.name, b.code, b.country, 'ACTIVE'
  from (values
    ('Royal Enfield','ROYAL-ENFIELD','IN'),('Honda','HONDA','JP'),('Yamaha','YAMAHA','JP'),
    ('Bajaj','BAJAJ','IN'),('TVS','TVS','IN'),('Hero MotoCorp','HERO','IN'),
    ('Suzuki','SUZUKI','JP'),('KTM','KTM','AT'),('Ather Energy','ATHER','IN'),
    ('Ola Electric','OLA','IN'),('UM Renegade','UMRENEGADE','IN'),('Aprilia','APRILIA','IT')
  ) as b(name, code, country)
on conflict (name) do update set code = excluded.code, country = excluded.country;

-- ---------------------------------------------------------------------------
-- Starter catalogue. selling_price >= base_price is a table constraint, so the
-- seed respects the same rule the UI enforces (SS67).
-- ---------------------------------------------------------------------------
insert into public.products
      (brand_id, name, model, variant, category, engine_cc, fuel_type, transmission, mileage,
       description, base_price, selling_price, ex_showroom_price, on_road_price, tax_rate,
       warranty_months, warranty_km, free_service_count, service_interval_km,
       service_interval_days, hsn_code, status)
-- `model` is the customer-facing family name; for these entries it is the same
-- string as `name`, which keeps the catalogue search box predictable (SS13/SS9).
select b.id, v.name, v.name, v.variant, v.category, v.engine_cc, v.fuel_type, v.transmission,
       v.mileage, v.description, v.base_price, v.selling_price, v.base_price, v.on_road_price,
       v.tax_rate, v.warranty_months, v.warranty_km, v.free_service_count,
       v.service_interval_km, v.service_interval_days, v.hsn_code, 'ACTIVE'
  from (values
    ('Royal Enfield','Classic 350','Fireball','CRUISER',349,'PETROL','MANUAL',37,
     'The modern classic: long-trip comfort, cast wheel Fireball finish.',192000,215000,255000,18,24,30000,3,5000,180,'8711'),
    ('Royal Enfield','Meteor 350','Supernova','CRUISER',349,'PETROL','MANUAL',36,
     'Luxury tourer with a relaxed riding triangle and full LED lighting.',200000,224000,265000,18,24,30000,3,5000,180,'8711'),
    ('Royal Enfield','Himalayan 450','Khangri','ADVENTURE',450,'PETROL','MANUAL',30,
     'Liquid-cooled 450 adventure platform with long-travel suspension.',242000,270000,315000,18,24,24000,3,5000,180,'8711'),
    ('Honda','Shine 125','DX Smart','COMMUTER',124,'PETROL','MANUAL',65,
     'The dependable commuter: low maintenance cost and excellent mileage.',78000,86000,99000,18,36,36000,3,6000,180,'8711'),
    ('Honda','Activa 6G','H-Smart','SCOOTER',110,'PETROL','AUTOMATIC',48,
     'India''s most trusted scooter with silent start and external fuel.',72000,80000,93000,18,36,36000,3,6000,180,'8711'),
    ('Honda','unicorn','STD','COMMUTER',163,'PETROL','MANUAL',50,
     'All-rounder with a smooth 163cc engine and upright ergonomics.',95000,105000,122000,18,36,36000,3,6000,180,'8711'),
    ('Yamaha','FZ-S','V3','COMMUTER',149,'PETROL','MANUAL',50,
     'Neo-retro street fighter with ABS and TFT instrumentation.',112000,124000,144000,18,24,30000,3,5000,180,'8711'),
    ('Yamaha','R15','V4','SPORTS',155,'PETROL','MANUAL',45,
     'Track-derived 155cc VVA engine with quickshifter.',155000,172000,200000,18,24,24000,3,5000,180,'8711'),
    ('Bajaj','Pulsar NS200','Streetfire','SPORTS',199,'PETROL','MANUAL',35,
     'Liquid-cooled naked sportsbike with a double-spar frame.',132000,146000,172000,18,24,24000,3,4000,150,'8711'),
    ('Bajaj','CT110','XCross','MOPED',110,'PETROL','AUTOMATIC',65,
     'Rugged moped built for load-carrying and city errands.',58000,64000,75000,18,36,36000,2,6000,180,'8711'),
    ('TVS','Apache RTR 160','4V','SPORTS',160,'PETROL','MANUAL',45,
     'Best-in-class 160cc with smartxonnect and glide through tech.',118000,131000,153000,18,25,25000,3,5000,180,'8711'),
    ('TVS','Jupiter','ZX','SCOOTER',125,'PETROL','AUTOMATIC',50,
     'Family scooter with dual-channel ABS and iTPMS.',76000,84000,98000,18,36,36000,3,6000,180,'8711'),
    ('Hero','Glamour','XTEC125','COMMUTER',125,'PETROL','MANUAL',57,
     'i3 stop-start commuter with the best fuel economy in class.',82000,90000,105000,18,36,40000,3,6000,180,'8711'),
    ('Hero','Destituto125','Disc','SCOOTER',125,'PETROL','AUTOMATIC',50,
     'Urban scooter with 12-inch wheels and LED projector headlamp.',78000,86000,100000,18,36,40000,3,6000,180,'8711'),
    ('Suzuki','Gixxar SF','400','SPORTS',399,'PETROL','MANUAL',32,
     'Parallel-twin 400 with inline four character. Full fairing.',228000,252000,295000,18,24,24000,3,5000,180,'8711'),
    ('KTM','390 Duke','BS6','SPORTS',399,'PETROL','MANUAL',28,
     'The ready-to-race naked with WP suspension and TFT dash.',295000,325000,380000,18,24,24000,2,3000,120,'8711'),
    ('Ather','450S','Gen3','ELECTRIC',0,'ELECTRIC','SINGLE_SPEED',105,
     'Smart electric scooter: 121 km IDC range, boost mode, OTA updates.',128000,142000,155000,18,36,0,3,8000,365,'8711'),
    ('Ola','S1 Pro','X','ELECTRIC',0,'ELECTRIC','SINGLE_SPEED',123,
     'Performance electric scooter with 470 km ARAI range pack.',115000,128000,141000,18,36,0,3,8000,365,'8711'),
    ('UM Renegade','Storm','400','CRUISER',395,'PETROL','MANUAL',30,
     'Indian cruiser with a V-twin soundtrack and low-slung seat.',150000,166000,196000,18,24,24000,2,4000,150,'8711')
  ) as v(brand, name, variant, category, engine_cc, fuel_type, transmission, mileage,
         description, base_price, selling_price, on_road_price, tax_rate, warranty_months,
         warranty_km, free_service_count, service_interval_km, service_interval_days, hsn_code)
  join public.brands b on b.name = v.brand
on conflict (brand_id, name, variant) do nothing;

-- Model is generated from the name in the UI; keep the column meaningful here.
update public.products set model = name where model is null or model = '';

-- ---------------------------------------------------------------------------
-- Colours (SS9) - two or three per model so the picker is never empty
-- ---------------------------------------------------------------------------
insert into public.product_colors (product_id, color_name, hex_code, sort_order)
select p.id, c.color_name, c.hex_code, row_number() over (partition by p.id order by c.ord)
  from public.products p
  cross join lateral (
    select * from (values
      ('Micro Dust Grey', '#8C8F93', 1),
      ('Signal Black',    '#1C1C1E', 2),
      ('Fireball Blue',   '#1F4E79', 3)
    ) as t(color_name, hex_code, ord)
    where p.category in ('CRUISER','ADVENTURE')
    union all
    select * from (values
      ('Pearl Igneo White','#ECEFF1',1),
      ('Matte Axis Grey',  '#78909C',2),
      ('Candy Blaze Red',  '#B71C1C',3)
    ) as t(color_name, hex_code, ord)
    where p.category not in ('CRUISER','ADVENTURE')
  ) c
on conflict (product_id, color_name) do nothing;

-- ---------------------------------------------------------------------------
-- Expense categories mapped to the chart of accounts (SS23, SS82)
-- ---------------------------------------------------------------------------
insert into public.expense_categories (name, code, description, account_code, is_system, requires_approval)
select v.name, v.code, v.description, v.account_code, true, v.requires_approval
  from (values
    ('Rent',        'RENT',        'Showroom and warehouse rent',           '5310', false),
    ('Electricity', 'ELECTRICITY', 'Power and utility bills',               '5320', false),
    ('Salary',      'SALARY',      'Staff payroll and incentives',          '5300', true),
    ('Transport',   'TRANSPORT',   'Vehicle movement, logistics, travel',   '5330', false),
    ('Marketing',   'MARKETING',   'Campaigns, events, dealer promotions',  '5340', true),
    ('Maintenance', 'MAINTENANCE', 'Facility and equipment upkeep',         '5350', true),
    ('Office',      'OFFICE',      'Stationery, software, subscriptions',    '5360', false),
    ('Fuel',        'FUEL',        'Test ride and staff fuel',              '5370', false),
    ('Other',       'OTHER',       'Anything not covered above',            '5900', true)
  ) as v(name, code, description, account_code, requires_approval)
on conflict (name) do update
   set description = excluded.description,
       account_code = coalesce(excluded.account_code, expense_categories.account_code),
       is_system = excluded.is_system,
       requires_approval = excluded.requires_approval;

-- ---------------------------------------------------------------------------
-- Free-service plans derived from the catalogue (SS18)
-- ---------------------------------------------------------------------------
insert into public.free_service_plans
      (plan_code, name, product_id, brand_id, service_number, validity_days, validity_km,
       free_labour, covered_items, labour_hours, estimated_value, is_active)
select 'FS-' || upper(left(regexp_replace(p.name, '[^A-Za-z0-9]', '', 'g'), 8)) || '-' || g.n,
       format('Free Service %s - %s', g.n, p.name),
       p.id, null, g.n,
       case g.n when 1 then 30  when 2 then 180 when 3 then 365 when 4 then 540 else 365 * g.n end,
       case g.n when 1 then 1000 when 2 then 5000 when 3 then 10000 when 4 then 15000 else 5000 * g.n end,
       true,
       case when p.fuel_type = 'ELECTRIC'
            then '["GENERAL_CHECKUP","BRAKE_INSPECTION","TYRE_CHECK","BATTERY_DIAGNOSTIC","FASTENER_TORQUE","SOFTWARE_UPDATE"]'::jsonb
            else '["GENERAL_CHECKUP","OIL_CHANGE","BRAKE_INSPECTION","TYRE_CHECK","CHAIN_ADJUSTMENT","AIR_FILTER_CLEAN"]'::jsonb end,
       case when g.n = 1 then 0.5 else 1.0 end,
       case when g.n = 1 then 0 else 650 + 120 * g.n end,
       true
  from public.products p
  cross join generate_series(1, greatest(coalesce(p.free_service_count, 3), 1)) as g(n)
on conflict (product_id, service_number) do update
   set validity_days = excluded.validity_days,
       validity_km = excluded.validity_km,
       covered_items = excluded.covered_items,
       name = excluded.name,
       updated_at = now();

-- ---------------------------------------------------------------------------
-- Finance companies (SS16) and suppliers (SS22)
-- ---------------------------------------------------------------------------
insert into public.finance_companies (name, code, contact_person, phone, email, city,
                                      interest_rate_min, interest_rate_max, processing_fee_percent, status)
values
  ('Bajaj Finserv Ltd','BAJAJ-FINSERV','Rakesh Menon','02261010100','fe.ast@bajajfinserv.in','Mumbai',11.5,17.0,2.5,'ACTIVE'),
  ('HDFC Bank - Two Wheeler Loans','HDFC-BANK','Sunita Rao','02261650000','two.wheeler@hdfcbank.in','Mumbai',10.8,15.5,2.0,'ACTIVE'),
  ('State Bank of India - Prime','SBI-PRIME','Amit Kulkarni','02222600000','two.whl@sbi.co.in','Mumbai',9.9,14.2,1.5,'ACTIVE'),
  ('ICICI Bank Retail','ICICI-BANK','Neha Sharma','02261655000','two.whl@icicibank.in','Mumbai',11.0,16.0,2.0,'ACTIVE'),
  ('Aditya Birla Capital','ABCAPITAL','Vikram Sethi','02261176000','bikes@adityabirlacapital.com','Mumbai',12.0,18.0,2.5,'ACTIVE'),
  ('Tata Capital Limited','TATA-CAPITAL','Prakash Iyer','02266661212','two.whl@tatacapital.com','Mumbai',11.8,17.5,2.2,'ACTIVE'),
  ('Cholamandalam Investment','CHOLA','Suresh Babu','04440907171','bikes@chola.in','Chennai',12.5,19.0,3.0,'ACTIVE')
on conflict (code) do update
   set name = excluded.name, contact_person = excluded.contact_person,
       phone = excluded.phone, email = excluded.email,
       interest_rate_min = excluded.interest_rate_min,
       interest_rate_max = excluded.interest_rate_max,
       processing_fee_percent = excluded.processing_fee_percent,
       updated_at = now();

insert into public.suppliers (name, code, contact_person, phone, email, city, state,
                              gst_number, payment_terms_days, status)
values
  ('OEM India Distributors Pvt Ltd','OEM-INDIA','Supply Desk','08040221100','orders@oemindia.example','Pune','Maharashtra','27AABCU9603R1ZX',30,'ACTIVE'),
  ('Bengaluru Auto Parts Hub','BLR-PARTS','Mahesh K','08023345566','sales@blrparts.example','Bengaluru','Karnataka','29AABCB1234K1ZP',15,'ACTIVE'),
  ('National Tyre & Battery Supply','NTB-SUPPLY','Farhan Q','04066554433','orders@ntbsupply.example','Hyderabad','Telangana','36AABCN7788L1Z2',45,'ACTIVE'),
  ('Ace Accessories International','ACE-ACC','Divya N','04422331100','trade@aceacc.example','Chennai','Tamil Nadu','33AABCA4455M1Z9',30,'ACTIVE'),
  ('Karnataka Logistics Movers','KL-MOVERS','Dispatch','08022998877','ops@klmovers.example','Mysuru','Karnataka','29AABCK1122P1ZK',7,'ACTIVE')
on conflict (name) do update
   set phone = excluded.phone, email = excluded.email,
       gst_number = excluded.gst_number, payment_terms_days = excluded.payment_terms_days,
       updated_at = now();

-- ---------------------------------------------------------------------------
-- Document sequences so the first documents look like a going concern
-- ---------------------------------------------------------------------------
insert into public.document_sequences (showroom_id, doc_type, period_key, prefix, next_value, padding)
select s.id, d.doc_type, 'ALL',
       case d.doc_type when 'SALE' then 'SAL' when 'INVOICE' then 'INV' when 'PAYMENT' then 'PMT'
                       when 'SERVICE' then 'SVC' when 'PURCHASE' then 'PUR' when 'EXPENSE' then 'EXP'
                       when 'LOAN' then 'LON' when 'CUSTOMER' then 'CUS' when 'WARRANTY_CLAIM' then 'WTC'
                       when 'STOCK_TRANSFER' then 'STF' when 'ACCOUNTING' then 'JRN'
                       when 'INSURANCE' then 'INS' else 'DOC' end,
       1, 4
  from public.showrooms s
 cross join (values ('SALE'),('INVOICE'),('PAYMENT'),('SERVICE'),('PURCHASE'),('EXPENSE'),
                    ('LOAN'),('CUSTOMER'),('WARRANTY_CLAIM'),('STOCK_TRANSFER'),('ACCOUNTING'),
                    ('INSURANCE'),('QUOTATION')) as d(doc_type)
on conflict (showroom_id, doc_type, period_key) do nothing;

-- ---------------------------------------------------------------------------
-- First admin bootstrap (SS83): run AFTER creating the auth user in Supabase
-- (Dashboard > Authentication > Add user, or signUp from the app).
-- ---------------------------------------------------------------------------
create or replace function public.bootstrap_super_admin(
  p_email text,
  p_name text default 'Super Administrator',
  p_showroom_code text default 'DEFAULT'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth  uuid;
  v_user  uuid;
  v_shr   uuid;
  v_role  uuid;
begin
  select id into v_auth from auth.users where lower(email) = lower(p_email);
  if v_auth is null then
    raise exception '[NOT001] no auth user with email %. Create it first (Supabase dashboard or Auth.signUpByEmail), then re-run:  select public.bootstrap_super_admin(%L)',
      p_email, p_email using errcode = 'P0002';
  end if;

  select id into v_shr from public.showrooms where code = upper(p_showroom_code);
  if v_shr is null then
    raise exception '[NOT002] showroom % not found', p_showroom_code using errcode = 'P0002';
  end if;

  insert into public.users (auth_user_id, showroom_id, name, email, phone, status,
                            is_super_admin, employee_code, password_changed_at)
  values (v_auth, v_shr, p_name, lower(p_email), null, 'ACTIVE', true,
          'ADMIN-0001', now())
  on conflict (auth_user_id) do update
     set status = 'ACTIVE', is_super_admin = true, showroom_id = excluded.showroom_id,
         name = coalesce(nullif(excluded.name, ''), public.users.name),
         updated_at = now()
  returning id into v_user;

  select id into v_role from public.roles where code = 'SUPERADMIN';
  insert into public.user_roles (user_id, role_id, showroom_id)
  values (v_user, v_role, null)
  on conflict (user_id, role_id, showroom_id) do nothing;

  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  select v_user, s.id, 'MANAGE' from public.showrooms s
  on conflict (user_id, showroom_id) do update set access_level = 'MANAGE';

  perform app_util.audit_row('auth','APPROVE','users', v_user, null,
          jsonb_build_object('bootstrapSuperAdmin', true, 'email', lower(p_email)),
          v_shr, v_user, p_name, 'CRITICAL');

  return jsonb_build_object('userId', v_user, 'email', lower(p_email),
                            'showroomId', v_shr, 'role', 'SUPERADMIN');
end;
$$;

comment on function public.bootstrap_super_admin is
  'Run once from the SQL editor: select public.bootstrap_super_admin(''you@example.com'');';
