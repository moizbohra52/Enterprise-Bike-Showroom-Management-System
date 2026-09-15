-- =============================================================================
-- 008_roles_permissions.sql  (SS6, SS81)
-- -----------------------------------------------------------------------------
-- Seeds the 13 roles, the complete `module.action` permission matrix and the
-- role -> permission grants.  Written as *data*, not as 900 hand-typed rows:
-- the module/action grid and the role patterns are the specification, and
-- re-running the migration reconciles the table instead of duplicating rows.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
insert into public.roles (name, code, description, level_rank, is_system_role)
values
  ('SUPER ADMIN',      'SUPERADMIN',       'Unrestricted owner access across every showroom.', 0,  true),
  ('ADMIN',            'ADMIN',            'Full control of a showroom group, except role surgery.', 10, true),
  ('SHOWROOM MANAGER', 'SHOWROOM_MANAGER', 'Runs one showroom end to end.',                       20, true),
  ('ACCOUNT MANAGER',  'ACCOUNT_MANAGER',  'Owns billing, payments, finance and accounting.',     30, true),
  ('SALES MANAGER',    'SALES_MANAGER',     'Sales floor lead: approvals, targets, stock requests.',40, true),
  ('SALES STAFF',      'SALES_STAFF',      'Sells bikes and books customers.',                     50, true),
  ('SERVICE MANAGER',  'SERVICE_MANAGER',  'Workshop head: job cards, parts, bay planning.',       40, true),
  ('SERVICE ADVISOR',  'SERVICE_ADVISOR',  'Receives vehicles, raises job cards, delivers.',       60, true),
  ('TECHNICIAN',       'TECHNICIAN',       'Works assigned job cards and records findings.',       70, true),
  ('INVENTORY MANAGER','INVENTORY_MANAGER', 'Stock in/out, transfers, adjustments, reservations.',  40, true),
  ('PURCHASE MANAGER', 'PURCHASE_MANAGER',  'Purchases and supplier management.',                  40, true),
  ('ACCOUNTANT',       'ACCOUNTANT',        'Journals, ledgers, expense approval, reports.',       35, true),
  ('VIEWER',         'VIEWER',            'Read-only across the modules it can see.',            150, true)
on conflict (code) do update
   set name = excluded.name,
       description = excluded.description,
       level_rank = excluded.level_rank,
       is_system_role = excluded.is_system_role,
       updated_at = now();

-- ---------------------------------------------------------------------------
-- Permissions: module x action grid
-- ---------------------------------------------------------------------------
do $$
declare
  m record;
  a text;
begin
  for m in
    select * from (values
      -- module,          actions available for that module
      ('dashboard',   array['view','export']),
      ('showroom',    array['view','create','edit','delete','settings']),
      ('users',       array['view','create','edit','delete','reset_password','impersonate']),
      ('roles',       array['view','manage','assign']),
      ('brands',      array['view','create','edit','delete']),
      ('products',    array['view','create','edit','delete','export','images']),
      ('inventory',   array['view','create','edit','delete','transfer','adjust','reserve','history']),
      ('customers',   array['view','create','edit','delete','export','documents']),
      ('vehicles',    array['view','create','edit','delete','odometer','documents']),
      ('sales',       array['view','create','edit','delete','cancel','discount','approve','deliver','export']),
      ('billing',     array['view','create','edit','cancel','print','export','refund']),
      ('payments',    array['view','create','edit','cancel','refund','export']),
      ('finance',     array['view','create','edit','delete','approve']),
      ('emi',         array['view','create','edit','payment','foreclose','export']),
      ('suppliers',   array['view','create','edit','delete']),
      ('purchases',   array['view','create','edit','delete','receive','approve','export']),
      ('expenses',    array['view','create','edit','delete','approve','export']),
      ('accounting',  array['view','create','edit','post','reverse','export','settings']),
      ('service',     array['view','create','edit','complete','bill','cancel','discount','assign','parts']),
      ('warranty',    array['view','create','edit','approve','claim','export']),
      ('insurance',   array['view','create','edit','delete','renew','export']),
      ('reminders',   array['view','create','edit','delete','complete','send']),
      ('notifications',array['view','send','manage']),
      ('reports',     array['view','export','schedule']),
      ('documents',   array['view','create','edit','delete','download','sign']),
      ('audit',       array['view','export']),
      ('settings',    array['view','edit','dangerous'])
    ) as x(module, actions)
  loop
    foreach a in array m.actions loop
      insert into public.permissions (module, action, description)
      values (m.module, a, initcap(m.module) || ' - ' || replace(initcap(a), '_', ' '))
      on conflict (module, action) do update
        set description = excluded.description;
    end loop;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Role -> permission patterns.  `module.*` grants every action of the module.
-- ---------------------------------------------------------------------------
create table if not exists app_sec.role_permission_pattern (
  role_code text not null,
  pattern   text not null,          -- 'sales.*' | 'inventory.transfer'
  primary key (role_code, pattern)
);

-- Patterns are additive, which is exactly what makes a read-only role dangerous
-- next to an accountability record: ('VIEWER','%.view') would silently hand every
-- signed-up user the audit trail of their showroom.  Denials are subtracted after
-- expansion, so the intent stays readable and the grants stay auditable.
create table if not exists app_sec.role_permission_deny (
  role_code text not null,
  pattern   text not null,
  reason    text not null,
  constraint role_permission_deny_pkey primary key (role_code, pattern)
);

insert into app_sec.role_permission_deny (role_code, pattern, reason) values
  ('VIEWER', 'audit.view',
   'the audit trail is an accountability record for managers; VIEWER stays read-only on business data (SS25)'),
  ('VIEWER', 'settings.edit',
   'a read-only role must never reach a settings mutation, whatever pattern it carries')
on conflict (role_code, pattern) do update set reason = excluded.reason;

insert into app_sec.role_permission_pattern (role_code, pattern) values
  -- SUPER ADMIN: everything, present and future
  ('SUPERADMIN', '%.%'),

  ('ADMIN', 'dashboard.%'), ('ADMIN', 'showroom.%'), ('ADMIN', 'users.%'),
  ('ADMIN', 'roles.view'), ('ADMIN', 'roles.assign'),
  ('ADMIN', 'brands.%'), ('ADMIN', 'products.%'), ('ADMIN', 'inventory.%'),
  ('ADMIN', 'customers.%'), ('ADMIN', 'vehicles.%'), ('ADMIN', 'sales.%'),
  ('ADMIN', 'billing.%'), ('ADMIN', 'payments.%'), ('ADMIN', 'finance.%'),
  ('ADMIN', 'emi.%'), ('ADMIN', 'suppliers.%'), ('ADMIN', 'purchases.%'),
  ('ADMIN', 'expenses.%'), ('ADMIN', 'accounting.%'), ('ADMIN', 'service.%'),
  ('ADMIN', 'warranty.%'), ('ADMIN', 'insurance.%'), ('ADMIN', 'reminders.%'),
  ('ADMIN', 'notifications.%'), ('ADMIN', 'reports.%'), ('ADMIN', 'documents.%'),
  ('ADMIN', 'audit.%'), ('ADMIN', 'settings.view'), ('ADMIN', 'settings.edit'),

  ('SHOWROOM_MANAGER', 'dashboard.view'),
  ('SHOWROOM_MANAGER', 'showroom.view'), ('SHOWROOM_MANAGER', 'showroom.edit'),
  ('SHOWROOM_MANAGER', 'users.view'), ('SHOWROOM_MANAGER', 'users.create'), ('SHOWROOM_MANAGER', 'users.edit'),
  ('SHOWROOM_MANAGER', 'roles.view'), ('SHOWROOM_MANAGER', 'roles.assign'),
  ('SHOWROOM_MANAGER', 'products.%'), ('SHOWROOM_MANAGER', 'inventory.%'),
  ('SHOWROOM_MANAGER', 'customers.%'), ('SHOWROOM_MANAGER', 'vehicles.%'),
  ('SHOWROOM_MANAGER', 'sales.%'), ('SHOWROOM_MANAGER', 'billing.%'),
  ('SHOWROOM_MANAGER', 'payments.%'), ('SHOWROOM_MANAGER', 'finance.view'),
  ('SHOWROOM_MANAGER', 'emi.view'), ('SHOWROOM_MANAGER', 'emi.payment'),
  ('SHOWROOM_MANAGER', 'suppliers.%'), ('SHOWROOM_MANAGER', 'purchases.%'),
  ('SHOWROOM_MANAGER', 'expenses.view'), ('SHOWROOM_MANAGER', 'expenses.create'),
  ('SHOWROOM_MANAGER', 'expenses.approve'),
  ('SHOWROOM_MANAGER', 'accounting.view'), ('SHOWROOM_MANAGER', 'accounting.export'),
  ('SHOWROOM_MANAGER', 'service.%'), ('SHOWROOM_MANAGER', 'warranty.%'),
  ('SHOWROOM_MANAGER', 'insurance.%'), ('SHOWROOM_MANAGER', 'reminders.%'),
  ('SHOWROOM_MANAGER', 'notifications.%'), ('SHOWROOM_MANAGER', 'reports.%'),
  ('SHOWROOM_MANAGER', 'documents.%'), ('SHOWROOM_MANAGER', 'audit.view'),
  ('SHOWROOM_MANAGER', 'settings.view'),

  ('ACCOUNT_MANAGER', 'dashboard.view'), ('ACCOUNT_MANAGER', 'billing.%'),
  ('ACCOUNT_MANAGER', 'payments.%'), ('ACCOUNT_MANAGER', 'finance.%'),
  ('ACCOUNT_MANAGER', 'emi.%'), ('ACCOUNT_MANAGER', 'accounting.%'),
  ('ACCOUNT_MANAGER', 'expenses.%'), ('ACCOUNT_MANAGER', 'purchases.view'),
  ('ACCOUNT_MANAGER', 'purchases.approve'), ('ACCOUNT_MANAGER', 'customers.view'),
  ('ACCOUNT_MANAGER', 'customers.edit'), ('ACCOUNT_MANAGER', 'sales.view'),
  ('ACCOUNT_MANAGER', 'invoices.view'), ('ACCOUNT_MANAGER', 'reports.%'),
  ('ACCOUNT_MANAGER', 'documents.%'), ('ACCOUNT_MANAGER', 'reminders.view'),
  ('ACCOUNT_MANAGER', 'reminders.create'),

  ('SALES_MANAGER', 'dashboard.view'), ('SALES_MANAGER', 'products.view'),
  ('SALES_MANAGER', 'inventory.view'), ('SALES_MANAGER', 'inventory.reserve'),
  ('SALES_MANAGER', 'customers.%'), ('SALES_MANAGER', 'vehicles.%'),
  ('SALES_MANAGER', 'sales.%'), ('SALES_MANAGER', 'billing.view'),
  ('SALES_MANAGER', 'billing.create'), ('SALES_MANAGER', 'billing.print'),
  ('SALES_MANAGER', 'billing.export'), ('SALES_MANAGER', 'payments.view'),
  ('SALES_MANAGER', 'payments.create'), ('SALES_MANAGER', 'finance.view'),
  ('SALES_MANAGER', 'finance.create'), ('SALES_MANAGER', 'finance.approve'),
  ('SALES_MANAGER', 'emi.%'), ('SALES_MANAGER', 'reminders.%'),
  ('SALES_MANAGER', 'reports.view'), ('SALES_MANAGER', 'reports.export'),
  ('SALES_MANAGER', 'documents.%'), ('SALES_MANAGER', 'users.view'),

  ('SALES_STAFF', 'dashboard.view'), ('SALES_STAFF', 'products.view'),
  ('SALES_STAFF', 'inventory.view'), ('SALES_STAFF', 'customers.view'),
  ('SALES_STAFF', 'customers.create'), ('SALES_STAFF', 'customers.edit'),
  ('SALES_STAFF', 'vehicles.view'), ('SALES_STAFF', 'sales.view'),
  ('SALES_STAFF', 'sales.create'), ('SALES_STAFF', 'sales.edit'),
  ('SALES_STAFF', 'billing.view'), ('SALES_STAFF', 'payments.view'),
  ('SALES_STAFF', 'payments.create'), ('SALES_STAFF', 'finance.view'),
  ('SALES_STAFF', 'finance.create'), ('SALES_STAFF', 'emi.view'),
  ('SALES_STAFF', 'reminders.view'), ('SALES_STAFF', 'reminders.create'),
  ('SALES_STAFF', 'documents.view'), ('SALES_STAFF', 'documents.create'),
  -- printing the tax invoice at delivery is part of selling the bike (SS14/SS15),
  -- and printing is what gates the private invoice bucket (SS53).
  ('SALES_STAFF', 'billing.print'),

  ('SERVICE_MANAGER', 'dashboard.view'), ('SERVICE_MANAGER', 'customers.view'),
  ('SERVICE_MANAGER', 'vehicles.%'), ('SERVICE_MANAGER', 'inventory.view'),
  ('SERVICE_MANAGER', 'service.%'), ('SERVICE_MANAGER', 'warranty.%'),
  ('SERVICE_MANAGER', 'insurance.view'), ('SERVICE_MANAGER', 'billing.view'),
  ('SERVICE_MANAGER', 'billing.create'), ('SERVICE_MANAGER', 'billing.print'),
  ('SERVICE_MANAGER', 'payments.view'), ('SERVICE_MANAGER', 'payments.create'),
  ('SERVICE_MANAGER', 'reminders.%'), ('SERVICE_MANAGER', 'reports.view'),
  ('SERVICE_MANAGER', 'reports.export'), ('SERVICE_MANAGER', 'users.view'),
  ('SERVICE_MANAGER', 'documents.%'),

  ('SERVICE_ADVISOR', 'dashboard.view'), ('SERVICE_ADVISOR', 'customers.view'),
  ('SERVICE_ADVISOR', 'customers.create'), ('SERVICE_ADVISOR', 'vehicles.view'),
  ('SERVICE_ADVISOR', 'vehicles.create'), ('SERVICE_ADVISOR', 'vehicles.edit'),
  ('SERVICE_ADVISOR', 'vehicles.odometer'), ('SERVICE_ADVISOR', 'service.view'),
  ('SERVICE_ADVISOR', 'service.create'), ('SERVICE_ADVISOR', 'service.edit'),
  ('SERVICE_ADVISOR', 'service.parts'), ('SERVICE_ADVISOR', 'service.complete'),
  ('SERVICE_ADVISOR', 'billing.view'), ('SERVICE_ADVISOR', 'billing.create'),
  ('SERVICE_ADVISOR', 'billing.print'), ('SERVICE_ADVISOR', 'payments.view'),
  ('SERVICE_ADVISOR', 'payments.create'), ('SERVICE_ADVISOR', 'reminders.view'),
  ('SERVICE_ADVISOR', 'reminders.create'), ('SERVICE_ADVISOR', 'warranty.view'),
  ('SERVICE_ADVISOR', 'warranty.claim'), ('SERVICE_ADVISOR', 'documents.view'),
  ('SERVICE_ADVISOR', 'documents.create'),

  ('TECHNICIAN', 'service.view'), ('TECHNICIAN', 'service.edit'),
  ('TECHNICIAN', 'service.complete'), ('TECHNICIAN', 'service.parts'),
  ('TECHNICIAN', 'vehicles.view'), ('TECHNICIAN', 'vehicles.odometer'),
  ('TECHNICIAN', 'customers.view'), ('TECHNICIAN', 'warranty.view'),
  ('TECHNICIAN', 'inventory.view'), ('TECHNICIAN', 'notifications.view'),
  ('TECHNICIAN', 'documents.view'),

  ('INVENTORY_MANAGER', 'dashboard.view'), ('INVENTORY_MANAGER', 'products.%'),
  ('INVENTORY_MANAGER', 'inventory.%'), ('INVENTORY_MANAGER', 'brands.view'),
  ('INVENTORY_MANAGER', 'vehicles.view'), ('INVENTORY_MANAGER', 'vehicles.edit'),
  ('INVENTORY_MANAGER', 'purchases.view'), ('INVENTORY_MANAGER', 'purchases.receive'),
  ('INVENTORY_MANAGER', 'sales.view'), ('INVENTORY_MANAGER', 'customers.view'),
  ('INVENTORY_MANAGER', 'reports.view'), ('INVENTORY_MANAGER', 'reports.export'),
  ('INVENTORY_MANAGER', 'documents.%'),

  ('PURCHASE_MANAGER', 'dashboard.view'), ('PURCHASE_MANAGER', 'suppliers.%'),
  ('PURCHASE_MANAGER', 'purchases.%'), ('PURCHASE_MANAGER', 'products.view'),
  ('PURCHASE_MANAGER', 'inventory.view'), ('INVENTORY_MANAGER', 'inventory.create'),
  ('PURCHASE_MANAGER', 'inventory.view'), ('PURCHASE_MANAGER', 'inventory.create'),
  ('PURCHASE_MANAGER', 'billing.view'), ('PURCHASE_MANAGER', 'accounting.view'),
  ('PURCHASE_MANAGER', 'reports.view'), ('PURCHASE_MANAGER', 'reports.export'),
  ('PURCHASE_MANAGER', 'expenses.view'), ('PURCHASE_MANAGER', 'expenses.create'),
  ('PURCHASE_MANAGER', 'documents.%'),

  ('ACCOUNTANT', 'dashboard.view'), ('ACCOUNTANT', 'billing.view'),
  ('ACCOUNTANT', 'billing.create'), ('ACCOUNTANT', 'billing.export'),
  ('ACCOUNTANT', 'payments.view'), ('ACCOUNTANT', 'payments.create'),
  ('ACCOUNTANT', 'payments.refund'), ('ACCOUNTANT', 'finance.view'),
  ('ACCOUNTANT', 'emi.view'), ('ACCOUNTANT', 'emi.payment'),
  ('ACCOUNTANT', 'accounting.%'), ('ACCOUNTANT', 'expenses.%'),
  ('ACCOUNTANT', 'sales.view'), ('ACCOUNTANT', 'purchases.view'),
  ('ACCOUNTANT', 'customers.view'), ('ACCOUNTANT', 'reports.%'),
  ('ACCOUNTANT', 'service.view'), ('ACCOUNTANT', 'documents.view'),

  ('VIEWER', '%.view')
on conflict do nothing;

-- Expand the patterns into real grants. Re-run safe: it deletes and re-adds.
create or replace function app_sec.rebuild_role_permissions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.role_permissions
   where role_id in (select r.id from public.roles r
                      where exists (select 1 from app_sec.role_permission_pattern p
                                     where p.role_code = r.code));

  insert into public.role_permissions (role_id, permission_id)
  select distinct r.id, p.id
    from public.roles r
    join app_sec.role_permission_pattern pat on pat.role_code = r.code
    join public.permissions p
      on (p.module || '.' || p.action) like pat.pattern
   on conflict (role_id, permission_id) do nothing;

  get diagnostics v_count = row_count;

  -- subtract the denials (SS6): patterns are additive, so a read-only role must
  -- be told explicitly which reads it does not get.
  delete from public.role_permissions rp
         using public.roles r, public.permissions p, app_sec.role_permission_deny d
        where rp.role_id = r.id
          and rp.permission_id = p.id
          and d.role_code = r.code
          and (p.module || '.' || p.action) like d.pattern;

  return v_count;
end;
$$;

select app_sec.rebuild_role_permissions();

-- Keep the pattern table and the grants in step when a new permission is added.
create or replace function app_util.rebuild_permissions_on_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_sec.rebuild_role_permissions();
  return null;
end;
$$;

drop trigger if exists trg_rebuild_perms on public.permissions;
create trigger trg_rebuild_perms
  after insert or update or delete on public.permissions
  for each statement execute function app_util.rebuild_permissions_on_change();

-- ---------------------------------------------------------------------------
-- Convenience views for the Role Management screen
-- ---------------------------------------------------------------------------
create or replace view public.role_permission_counts as
select r.id as role_id, r.name as role_name, r.code as role_code, r.level_rank,
       count(rp.permission_id) as permission_count,
       count(distinct p.module) as module_count
  from public.roles r
  left join public.role_permissions rp on rp.role_id = r.id
  left join public.permissions p on p.id = rp.permission_id
 group by r.id, r.name, r.code, r.level_rank;

create or replace view public.user_role_summary as
select u.id as user_id, u.name, u.email, u.showroom_id,
       coalesce(array_agg(distinct r.name) filter (where r.id is not null), '{}') as roles,
       count(distinct p.id) as permission_count,
       bool_or(r.code = 'SUPERADMIN') as is_super_admin
  from public.users u
  left join public.user_roles ur on ur.user_id = u.id
  left join public.roles r on r.id = ur.role_id
  left join public.role_permissions rp on rp.role_id = r.id
  left join public.permissions p on p.id = rp.permission_id
 group by u.id, u.name, u.email, u.showroom_id;

-- What a permission is currently worth, per module (used by the permissions UI)
create or replace view public.permission_usage as
select p.module, p.action, p.id as permission_id,
       count(rp.id) as role_count,
       coalesce(array_agg(distinct r.code) filter (where r.code is not null), '{}') as roles
  from public.permissions p
  left join public.role_permissions rp on rp.permission_id = p.id
  left join public.roles r on r.id = rp.role_id
 group by p.module, p.action, p.id
 order by p.module, p.action;
