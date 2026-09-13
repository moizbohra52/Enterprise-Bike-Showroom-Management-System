-- 014_seed_data.sql
-- Reference data the app expects to find on a clean project.

insert into public.expense_categories (name, description, icon, is_system,
                                       requires_approval)
values
  ('Rent',          'Showroom and workshop rent',        'home',           true, false),
  ('Salaries',      'Staff salaries and wages',          'payments',       true, true),
  ('Electricity',   'Power and utilities',               'bolt',           true, false),
  ('Marketing',     'Advertising, campaigns and events', 'campaign',       true, true),
  ('Office Supplies','Stationery and consumables',       'inventory_2',    true, false),
  ('Travel',        'Staff travel and conveyance',       'directions_car', true, false),
  ('Repairs',       'Premises and equipment repairs',    'build',          true, true),
  ('Bank Charges',  'Gateway, POS and bank fees',        'account_balance',true, false),
  ('Insurance',     'Premises and asset insurance',      'shield',         true, true),
  ('Miscellaneous', 'Uncategorised expenses',            'more_horiz',     true, true)
on conflict (name) do nothing;

insert into public.brands (name, status)
values
  ('Honda', 'active'),
  ('Hero', 'active'),
  ('Bajaj', 'active'),
  ('TVS', 'active'),
  ('Yamaha', 'active'),
  ('Suzuki', 'active'),
  ('Royal Enfield', 'active'),
  ('KTM', 'active'),
  ('Benelli', 'active'),
  ('Jawa', 'active'),
  ('Ather', 'active'),
  ('Ola Electric', 'active'),
  ('TVS iQube', 'active'),
  ('Revolt', 'active')
on conflict (name) do nothing;

insert into public.finance_companies (name, code, status)
values
  ('Bajaj Finance',        'BAJAJ',  'active'),
  ('HDFC Bank',            'HDFC',   'active'),
  ('ICICI Bank',           'ICICI',  'active'),
  ('Shriram Finance',      'SHRIRAM','active'),
  ('Cholamandalam',        'CHOLA',  'active'),
  ('Muthoot Finance',      'MUTHOOT','active'),
  ('IDFC First Bank',      'IDFC',   'active')
on conflict (name) do nothing;

-- Default free-service plan shape for new products: four services inside the
-- first year (AppConfig.freeServiceDefaultCount).
insert into public.free_service_plans
  (product_id, service_number, service_days, service_km, free_labour,
   included_services, is_active)
select p.id, n.service_number,
       case n.service_number
         when 1 then 45   when 2 then 150  when 3 then 270  else 365
       end,
       case n.service_number
         when 1 then 1000 when 2 then 5000 when 3 then 10000 else 15000
       end,
       true,
       '["general_checkup", "oil_top_up", "chain_lube"]'::jsonb,
       true
  from public.products p
  cross join (values (1), (2), (3), (4)) as n(service_number)
 where not exists (
   select 1 from public.free_service_plans f
    where f.product_id = p.id and f.service_number = n.service_number
 );
