-- 009_rls.sql
-- Row Level Security. This is the real authorization boundary; the Flutter
-- permission checks are UX only.
--
-- Design:
--   * Tables with showroom_id are gated by public.can_access_showroom().
--   * Child tables are gated through their parent row.
--   * Helper functions are `security definer` and RLS is *not* forced, so
--     those functions (and the audit trigger) never recurse into RLS.
--   * audit_logs has no write policy: rows are only written by the
--     security-definer trigger in 007_triggers.sql.

do $$
declare
  t text;
  tenant_tables constant text[] := array[
    'inventory', 'customers', 'customer_vehicles', 'sales', 'invoices',
    'payments', 'loans', 'purchases', 'expenses', 'service_records',
    'reminders', 'notifications', 'attachments', 'audit_logs', 'warranties',
    'insurance_policies', 'users'
  ];
begin
  foreach t in array tenant_tables loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end;
$$;

alter table public.showrooms enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.brands enable row level security;
alter table public.products enable row level security;
alter table public.product_colors enable row level security;
alter table public.product_images enable row level security;
alter table public.sale_items enable row level security;
alter table public.invoice_items enable row level security;
alter table public.purchase_items enable row level security;
alter table public.service_items enable row level security;
alter table public.emi_schedules enable row level security;
alter table public.finance_companies enable row level security;
alter table public.suppliers enable row level security;
alter table public.expense_categories enable row level security;
alter table public.free_service_plans enable row level security;
alter table public.emi_plans enable row level security;
alter table public.product_accessories enable row level security;
alter table public.stock_history enable row level security;
alter table public.stock_transfers enable row level security;
alter table public.free_service_grants enable row level security;
alter table public.warranty_claims enable row level security;
alter table public.device_tokens enable row level security;
alter table public.document_sequences enable row level security;
-- Accounting tables are created in 013_accounting.sql and enable RLS there.

-- ------------------------------------------------------------ showrooms

drop policy if exists showrooms_select on public.showrooms;
create policy showrooms_select on public.showrooms
  for select to authenticated
  using (public.can_access_showroom(id));

drop policy if exists showrooms_write on public.showrooms;
create policy showrooms_write on public.showrooms
  for all to authenticated
  using (public.has_permission('showroom', 'edit'))
  with check (public.has_permission('showroom', 'create'));

-- ---------------------------------------------------------------- users

drop policy if exists users_select on public.users;
create policy users_select on public.users
  for select to authenticated
  using (auth_user_id = auth.uid() or public.has_permission('users', 'view'));

drop policy if exists users_insert on public.users;
create policy users_insert on public.users
  for insert to authenticated
  with check (
    auth_user_id = auth.uid() or public.has_permission('users', 'create')
  );

drop policy if exists users_update on public.users;
create policy users_update on public.users
  for update to authenticated
  using (auth_user_id = auth.uid() or public.has_permission('users', 'edit'))
  with check (auth_user_id = auth.uid() or public.has_permission('users', 'edit'));

-- ------------------------------------------------- tenant-scoped tables

do $$
declare
  t text;
  tenant_tables constant text[] := array[
    'inventory', 'customers', 'customer_vehicles', 'sales', 'invoices',
    'payments', 'loans', 'purchases', 'expenses', 'service_records',
    'reminders', 'notifications', 'attachments', 'warranties',
    'insurance_policies'
  ];
begin
  foreach t in array tenant_tables loop
    execute format('drop policy if exists %I on public.%I', t || '_tenant', t);
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (public.can_access_showroom(showroom_id))
         with check (public.can_access_showroom(showroom_id))',
      t || '_tenant', t
    );
  end loop;
end;
$$;

-- ------------------------------------------------------ audit trail read

drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using (public.has_permission('audit', 'view')
         and public.can_access_showroom(showroom_id));

-- ------------------------------------------------------------ RBAC data

drop policy if exists roles_select on public.roles;
create policy roles_select on public.roles
  for select to authenticated using (true);

drop policy if exists roles_write on public.roles;
create policy roles_write on public.roles
  for all to authenticated
  using (public.has_permission('roles', 'manage'))
  with check (public.has_permission('roles', 'manage'));

drop policy if exists permissions_select on public.permissions;
create policy permissions_select on public.permissions
  for select to authenticated using (true);

drop policy if exists permissions_write on public.permissions;
create policy permissions_write on public.permissions
  for all to authenticated
  using (public.has_permission('roles', 'manage'))
  with check (public.has_permission('roles', 'manage'));

drop policy if exists user_roles_all on public.user_roles;
create policy user_roles_all on public.user_roles
  for all to authenticated
  using (public.has_permission('users', 'edit')
         or exists (select 1 from public.users u
                     where u.id = user_id and u.auth_user_id = auth.uid()))
  with check (public.has_permission('users', 'edit'));

drop policy if exists role_permissions_all on public.role_permissions;
create policy role_permissions_all on public.role_permissions
  for all to authenticated
  using (public.has_permission('roles', 'manage'))
  with check (public.has_permission('roles', 'manage'));

-- -------------------------------------------------------------- catalog

drop policy if exists brands_select on public.brands;
create policy brands_select on public.brands
  for select to authenticated using (true);

drop policy if exists brands_write on public.brands;
create policy brands_write on public.brands
  for all to authenticated
  using (public.has_permission('products', 'edit'))
  with check (public.has_permission('products', 'create'));

drop policy if exists products_select on public.products;
create policy products_select on public.products
  for select to authenticated using (true);

drop policy if exists products_write on public.products;
create policy products_write on public.products
  for all to authenticated
  using (public.has_permission('products', 'edit'))
  with check (public.has_permission('products', 'create'));

-- Colors/images belong to a product row (no showroom column of their own).
drop policy if exists product_colors_all on public.product_colors;
create policy product_colors_all on public.product_colors
  for all to authenticated
  using (public.has_permission('products', 'edit'))
  with check (public.has_permission('products', 'create'));

drop policy if exists product_images_all on public.product_images;
create policy product_images_all on public.product_images
  for all to authenticated
  using (public.has_permission('products', 'edit'))
  with check (public.has_permission('products', 'create'));

-- -------------------------------------------------------- child tables

drop policy if exists sale_items_all on public.sale_items;
create policy sale_items_all on public.sale_items
  for all to authenticated
  using (exists (select 1 from public.sales s
                  where s.id = sale_id
                    and public.can_access_showroom(s.showroom_id)))
  with check (exists (select 1 from public.sales s
                       where s.id = sale_id
                         and public.can_access_showroom(s.showroom_id)));

drop policy if exists invoice_items_all on public.invoice_items;
create policy invoice_items_all on public.invoice_items
  for all to authenticated
  using (exists (select 1 from public.invoices i
                  where i.id = invoice_id
                    and public.can_access_showroom(i.showroom_id)))
  with check (exists (select 1 from public.invoices i
                       where i.id = invoice_id
                         and public.can_access_showroom(i.showroom_id)));

drop policy if exists purchase_items_all on public.purchase_items;
create policy purchase_items_all on public.purchase_items
  for all to authenticated
  using (exists (select 1 from public.purchases p
                  where p.id = purchase_id
                    and public.can_access_showroom(p.showroom_id)))
  with check (exists (select 1 from public.purchases p
                       where p.id = purchase_id
                         and public.can_access_showroom(p.showroom_id)));

drop policy if exists service_items_all on public.service_items;
create policy service_items_all on public.service_items
  for all to authenticated
  using (exists (select 1 from public.service_records r
                  where r.id = service_id
                    and public.can_access_showroom(r.showroom_id)))
  with check (exists (select 1 from public.service_records r
                       where r.id = service_id
                         and public.can_access_showroom(r.showroom_id)));

drop policy if exists emi_schedules_all on public.emi_schedules;
create policy emi_schedules_all on public.emi_schedules
  for all to authenticated
  using (exists (select 1 from public.loans l
                  where l.id = loan_id
                    and public.can_access_showroom(l.showroom_id)))
  with check (exists (select 1 from public.loans l
                       where l.id = loan_id
                         and public.can_access_showroom(l.showroom_id)));

drop policy if exists warranty_claims_all on public.warranty_claims;
create policy warranty_claims_all on public.warranty_claims
  for all to authenticated
  using (exists (select 1 from public.warranties w
                  where w.id = warranty_id
                    and public.can_access_showroom(w.showroom_id)))
  with check (public.has_permission('warranty', 'edit'));

drop policy if exists free_service_grants_all on public.free_service_grants;
create policy free_service_grants_all on public.free_service_grants
  for all to authenticated
  using (exists (select 1 from public.customer_vehicles v
                  where v.id = vehicle_id
                    and public.can_access_showroom(v.showroom_id)))
  with check (public.has_permission('service', 'edit'));

drop policy if exists emi_plans_all on public.emi_plans;
create policy emi_plans_all on public.emi_plans
  for all to authenticated
  using (public.has_permission('products', 'view'))
  with check (public.has_permission('products', 'create'));

drop policy if exists product_accessories_all on public.product_accessories;
create policy product_accessories_all on public.product_accessories
  for all to authenticated
  using (public.has_permission('products', 'view'))
  with check (public.has_permission('products', 'edit'));

drop policy if exists stock_history_select on public.stock_history;
create policy stock_history_select on public.stock_history
  for select to authenticated
  using (public.has_permission('inventory', 'view'));

drop policy if exists stock_transfers_all on public.stock_transfers;
create policy stock_transfers_all on public.stock_transfers
  for all to authenticated
  using (public.has_permission('inventory', 'view'))
  with check (public.has_permission('inventory', 'transfer'));

-- Reference data: readable by every signed-in user.
drop policy if exists finance_companies_select on public.finance_companies;
create policy finance_companies_select on public.finance_companies
  for select to authenticated using (true);

drop policy if exists finance_companies_write on public.finance_companies;
create policy finance_companies_write on public.finance_companies
  for all to authenticated
  using (public.has_permission('finance', 'edit'))
  with check (public.has_permission('finance', 'create'));

drop policy if exists suppliers_select on public.suppliers;
create policy suppliers_select on public.suppliers
  for select to authenticated using (true);

drop policy if exists suppliers_write on public.suppliers;
create policy suppliers_write on public.suppliers
  for all to authenticated
  using (public.has_permission('purchases', 'edit'))
  with check (public.has_permission('purchases', 'create'));

drop policy if exists expense_categories_select on public.expense_categories;
create policy expense_categories_select on public.expense_categories
  for select to authenticated using (true);

drop policy if exists expense_categories_write on public.expense_categories;
create policy expense_categories_write on public.expense_categories
  for all to authenticated
  using (public.has_permission('expenses', 'edit'))
  with check (public.has_permission('expenses', 'create'));

drop policy if exists free_service_plans_all on public.free_service_plans;
create policy free_service_plans_all on public.free_service_plans
  for all to authenticated
  using (public.has_permission('service', 'edit'))
  with check (public.has_permission('service', 'create'));

-- --------------------------------------------------------------- devices

drop policy if exists device_tokens_all on public.device_tokens;
create policy device_tokens_all on public.device_tokens
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- document_sequences is internal to next_document_number() (security
-- definer); no policy means no direct client access.
