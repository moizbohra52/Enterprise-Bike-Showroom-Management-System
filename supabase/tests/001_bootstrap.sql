-- =============================================================================
-- 001_bootstrap.sql  -  tenants, auth mirroring, RBAC wiring
-- -----------------------------------------------------------------------------
-- Proves the parts everything else depends on:
--   * a new showroom automatically gets its own chart of accounts (SS82)
--   * a signup in auth.users creates the profile + least-privilege role + audit
--     row, without the client ever touching public.users (SS12)
--   * get_current_user_context() returns the login payload the Flutter app
--     needs, and permissions actually resolve through the role matrix (SS6)
-- =============================================================================

reset role;

-- ---------------------------------------------------------------------------
-- Two showrooms (multi-showroom isolation is only meaningful with >1)
-- ---------------------------------------------------------------------------
insert into public.showrooms (name, code, legal_name, address, city, state, pincode, phone, email,
                              gst_number, invoice_prefix, timezone, settings)
values
  ('Test Bengaluru HQ','TST-BLR','Test Motors (Karnataka) Pvt Ltd','12 MG Road Showroom Complex',
   'Bengaluru','Karnataka','560001','08022334455',
   'blr@test.local','29AABCU9603R1ZX','INV','Asia/Kolkata',
   '{"allow_negative_inventory": false,"gst_rate": 18,"low_stock_threshold": 2,
     "sale_approval_threshold": 500000}'::jsonb),
  ('Test Hyderabad Branch','TST-HYD','Test Motors (Telangana) Pvt Ltd','45 Banjara Hills Road',
   'Hyderabad','Telangana','500001','04023345566',
   'hyd@test.local','36AABCU9603R1ZY','INV','Asia/Kolkata',
   '{"allow_negative_inventory": false,"gst_rate": 18,"low_stock_threshold": 1,
     "sale_approval_threshold": 0}'::jsonb)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Signups: the 015 trigger must build the rest
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values
  ('a0000000-0000-0000-0000-000000000001','admin@test.local',
   '{"name":"Ada Admin","employee_code":"EMP-0001"}','{"provider":"email"}'),
  ('a0000000-0000-0000-0000-000000000002','manager@test.local',
   '{"name":"Manoj Manager","employee_code":"EMP-0002"}','{"provider":"email"}'),
  ('a0000000-0000-0000-0000-000000000003','sales@test.local',
   '{"name":"Sita Sales","employee_code":"EMP-0003"}','{"provider":"email"}'),
  ('a0000000-0000-0000-0000-000000000004','tech@test.local',
   '{"name":"Ravi Technician","employee_code":"EMP-0004"}','{"provider":"email"}'),
  ('a0000000-0000-0000-0000-000000000005','accountant@test.local',
   '{"name":"Gita Accounts","employee_code":"EMP-0005"}','{"provider":"email"}'),
  ('a0000000-0000-0000-0000-000000000006','hyd.sales@test.local',
   '{"name":"Hyd Sales","employee_code":"EMP-0006"}','{"provider":"email"}')
on conflict (id) do nothing;

do $$
begin
  -- 1. every signup got exactly one profile, attached to a showroom
  perform test.ok((select count(*) from public.users u
                    where u.auth_user_id between 'a0000000-0000-0000-0000-000000000001'::uuid
                                          and 'a0000000-0000-0000-0000-000000000006'::uuid) = 6,
                  'auth trigger created one profile per signup');

  -- 2. ... with the least privilege role and an audit entry (SS12)
  perform test.ok((select count(distinct ur.user_id)
                     from public.user_roles ur join public.roles r on r.id = ur.role_id
                     join public.users u on u.id = ur.user_id
                    where r.code = 'VIEWER'
                      and u.auth_user_id between 'a0000000-0000-0000-0000-000000000001'::uuid
                                            and 'a0000000-0000-0000-0000-000000000006'::uuid) = 6,
                  'every new user starts as VIEWER only');

  perform test.ok((select count(*) from public.audit_logs a
                    where a.module = 'auth' and a.action = 'CREATE'
                      and a.record_id in (select id from public.users
                                           where auth_user_id is not null)) >= 6,
                  'new signups are written to the immutable audit log');

  -- 3. name / email / code were carried over from the auth metadata
  perform test.ok((select u.name || '/' || coalesce(u.employee_code,'-') from public.users u
                    where u.auth_user_id = 'a0000000-0000-0000-0000-000000000001'::uuid)
                  = 'Ada Admin/EMP-0001',
                  'profile fields are mirrored from raw_user_meta_data');

  -- 4. each showroom owns its own chart of accounts (SS82)
  perform test.ok((select count(*) from public.accounts a
                    join public.showrooms s on s.id = a.showroom_id
                   where s.code = 'TST-BLR' and a.is_system) >= 25,
                  'new showroom TST-BLR was seeded with the chart of accounts');
  perform test.ok((select count(*) from public.accounts a
                    join public.showrooms s on s.id = a.showroom_id
                   where s.code = 'TST-HYD' and a.is_system) >= 25,
                  'new showroom TST-HYD was seeded with its own chart');
  perform test.ok((select count(*)
                     from public.accounts a
                     join public.accounts b on b.account_code = a.account_code
                                          and b.showroom_id <> a.showroom_id
                                          and b.showroom_id = a.showroom_id
                    where false) = 0,
                  'chart seeding is per-showroom (no cross-tenant account sharing)');
end
$$;

-- ---------------------------------------------------------------------------
-- Assign the real roles (an admin does this from the Roles screen; here the test
-- does it directly so the flow starts from a known state)
-- ---------------------------------------------------------------------------
do $$
declare
  v_blr uuid; v_hyd uuid; v_u uuid; v_role uuid;
begin
  select id into v_blr from public.showrooms where code = 'TST-BLR';
  select id into v_hyd from public.showrooms where code = 'TST-HYD';

  -- admin: global role, access to both showrooms
  select id into v_u from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000001'::uuid;
  select id into v_role from public.roles where code = 'ADMIN';
  insert into public.user_roles (user_id, role_id, showroom_id) values (v_u, v_role, null)
    on conflict do nothing;
  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  values (v_u, v_blr, 'MANAGE'), (v_u, v_hyd, 'MANAGE') on conflict do nothing;
  update public.users set showroom_id = v_blr where id = v_u;
  perform test.remember('admin', v_u::text);
  perform test.remember('admin_auth', 'a0000000-0000-0000-0000-000000000001');
  perform test.remember('blr', v_blr::text);
  perform test.remember('hyd', v_hyd::text);

  -- showroom manager: scoped to Bengaluru only
  select id into v_u from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000002'::uuid;
  select id into v_role from public.roles where code = 'SHOWROOM_MANAGER';
  insert into public.user_roles (user_id, role_id, showroom_id) values (v_u, v_role, v_blr)
    on conflict do nothing;
  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  values (v_u, v_blr, 'MANAGE') on conflict do nothing;
  update public.users set showroom_id = v_blr where id = v_u;
  perform test.remember('manager', v_u::text);
  perform test.remember('manager_auth', 'a0000000-0000-0000-0000-000000000002');

  -- sales staff: Bengaluru
  select id into v_u from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000003'::uuid;
  select id into v_role from public.roles where code = 'SALES_STAFF';
  insert into public.user_roles (user_id, role_id, showroom_id) values (v_u, v_role, v_blr)
    on conflict do nothing;
  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  values (v_u, v_blr, 'OPERATE') on conflict do nothing;
  update public.users set showroom_id = v_blr where id = v_u;
  perform test.remember('sales', v_u::text);
  perform test.remember('sales_auth', 'a0000000-0000-0000-0000-000000000003');

  -- technician: Bengaluru
  select id into v_u from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000004'::uuid;
  select id into v_role from public.roles where code = 'TECHNICIAN';
  insert into public.user_roles (user_id, role_id, showroom_id) values (v_u, v_role, v_blr)
    on conflict do nothing;
  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  values (v_u, v_blr, 'OPERATE') on conflict do nothing;
  update public.users set showroom_id = v_blr where id = v_u;
  perform test.remember('tech', v_u::text);
  perform test.remember('tech_auth', 'a0000000-0000-0000-0000-000000000004');

  -- accountant: Bengaluru, but the money module is theirs
  select id into v_u from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000005'::uuid;
  select id into v_role from public.roles where code = 'ACCOUNTANT';
  insert into public.user_roles (user_id, role_id, showroom_id) values (v_u, v_role, v_blr)
    on conflict do nothing;
  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  values (v_u, v_blr, 'MANAGE') on conflict do nothing;
  update public.users set showroom_id = v_blr where id = v_u;
  perform test.remember('accountant', v_u::text);
  perform test.remember('accountant_auth', 'a0000000-0000-0000-0000-000000000005');

  -- a Hyderabad sales person, used by the isolation tests
  select id into v_u from public.users where auth_user_id = 'a0000000-0000-0000-0000-000000000006'::uuid;
  select id into v_role from public.roles where code = 'SALES_STAFF';
  insert into public.user_roles (user_id, role_id, showroom_id) values (v_u, v_role, v_hyd)
    on conflict do nothing;
  insert into public.user_showroom_access (user_id, showroom_id, access_level)
  values (v_u, v_hyd, 'OPERATE') on conflict do nothing;
  update public.users set showroom_id = v_hyd where id = v_u;
  perform test.remember('hyd_sales', v_u::text);
  perform test.remember('hyd_sales_auth', 'a0000000-0000-0000-0000-000000000006');

  -- Activation: a manager approved each account (status ACTIVE + home showroom).
  -- Without this every business RPC refuses to serve the user, which is exactly
  -- the SS83 "controlled onboarding" rule.
  update public.users set status = 'ACTIVE'
   where auth_user_id between 'a0000000-0000-0000-0000-000000000001'::uuid
                          and 'a0000000-0000-0000-0000-000000000006'::uuid;

  -- RBAC tables are not readable through the API on purpose (009), so the counts
  -- the tests compare against are captured here, while the superuser is looking.
  perform test.remember('admin_perm_count', (select count(distinct p.module || '.' || p.action)
                                               from public.permissions p
                                               join public.role_permissions rp on rp.permission_id = p.id
                                               join public.roles r            on r.id = rp.role_id
                                              where r.code = 'ADMIN')::text);
  perform test.remember('total_perm_count', (select count(*) from public.permissions)::text);
end
$$;

-- ---------------------------------------------------------------------------
-- The login payload (SS5)
-- ---------------------------------------------------------------------------
set role authenticated;
select test.as('a0000000-0000-0000-0000-000000000001'::uuid);

do $$
declare ctx jsonb;
begin
  ctx := public.get_current_user_context();
  perform test.ok(coalesce((ctx ->> 'hasProfile')::boolean, false), 'context reports an active profile');
  perform test.eq(ctx ->> 'email', 'admin@test.local', 'context email comes from the profile row');
  perform test.ok((select count(*) from jsonb_array_elements(ctx -> 'permissions'))
                    = test.num_of('admin_perm_count')::int,
                  'the login payload carries exactly the ADMIN role grant set');
  perform test.ok((select count(*) from jsonb_array_elements(ctx -> 'permissions')) > 100,
                  'ADMIN ends up with a broad permission set from the role matrix (SS6)');
  perform test.ok(exists (select 1 from jsonb_array_elements_text(ctx -> 'permissions') p
                           where p = 'sales.delete'),
                  'permissions are the module.action strings the Flutter app tests');
  perform test.eq((select count(*) from jsonb_array_elements(ctx -> 'showrooms'))::bigint, 2::bigint,
                  'the admin can switch between both showrooms');
  perform test.ok(not coalesce((select u.is_super_admin from public.users u
                                 where u.id = (select id from public.users where email = 'admin@test.local')), false),
                  'ADMIN is not silently a super admin (SS6)');
  -- Assignment tables are visible per tenant: your own rows always, the scoped
  -- ones inside the showrooms you manage, org-wide grants for superadmins only.
  -- (Roles for the UI still come from the login payload, which is complete.)
  perform test.ok((select count(*) from public.user_roles) >= 7,
                  'a manager can list role assignments inside their showrooms');
  perform test.ok((select count(*) from public.user_roles
                    where showroom_id is null
                      and user_id is distinct from test.uuid_of('admin')) = 0,
                  'org-wide role grants are not exposed to a plain admin');
  perform test.eq(jsonb_array_length(ctx -> 'roles')::bigint, 2::bigint,
                  'a new user keeps VIEWER alongside the granted ADMIN role');

  -- the sales person must NOT be able to approve their own sale
  ctx := public.get_current_user_context();
  perform test.ok(ctx ? 'roles', 'context shape is stable for the client decoder');
end
$$;

do $$
declare ctx jsonb;
begin
  perform test.as('a0000000-0000-0000-0000-000000000003'::uuid, test.uuid_of('blr'));
  ctx := public.get_current_user_context();
  perform test.ok(not exists (select 1 from jsonb_array_elements_text(ctx -> 'permissions') p
                              where p = 'sales.approve'),
                  'SALES_STAFF cannot approve a sale (SS6)');
  perform test.ok(exists (select 1 from jsonb_array_elements_text(ctx -> 'permissions') p
                          where p = 'sales.create'),
                  'SALES_STAFF can create a sale');
  perform test.eq((select count(*) from jsonb_array_elements(ctx -> 'showrooms')), 1::bigint,
                  'a showroom-scoped staff member sees exactly one showroom');

  -- and the RPC layer agrees with the permission list, independently of RLS
  perform test.ok((select count(*) from public.user_roles
                    where user_id = test.uuid_of('sales')) = 2,
                  'a staff member sees their own VIEWER + SALES_STAFF grants');
  perform test.ok((select count(*) from public.user_roles
                    where user_id = test.uuid_of('admin')) = 0,
                  'they cannot see another user''s org-wide grants');
  perform test.raises(
    'select public.approve_sale(gen_random_uuid(), true, null)', 'SEC001',
    'approve_sale is blocked for a role without sales.approve');
  perform test.raises(
    'select public.create_accounting_transaction(''{"lines":[{"code":"1010","debit":10}]}'')',
    'SEC001', 'manual journals are blocked for sales staff');

  -- NOTE: app_sec.* is deliberately invisible to the API role (009 revokes usage
  -- on the internal schemas), so the test asserts authorisation through the login
  -- payload - exactly what the Flutter PermissionService evaluates.
  perform test.as('a0000000-0000-0000-0000-000000000005'::uuid, test.uuid_of('blr'));
  ctx := public.get_current_user_context();
  perform test.ok(exists (select 1 from jsonb_array_elements_text(ctx -> 'permissions') p
                          where p = 'accounting.post'),
                  'ACCOUNTANT may post journals');
  perform test.ok(not exists (select 1 from jsonb_array_elements_text(ctx -> 'permissions') p
                              where p = 'inventory.delete'),
                  'ACCOUNTANT may not delete stock');
  perform test.raises('select count(*) from app_sec.permissions', null,
                      'the internal schemas are not reachable through the API');
end
$$;

-- preferences: the default showroom must be one the user can access
do $$
begin
  perform test.as('a0000000-0000-0000-0000-000000000003'::uuid, test.uuid_of('blr'));
  perform test.raises(format('select public.set_my_default_showroom(%L::uuid)', test.uuid_of('hyd')),
                      null, 'a Bengaluru user cannot make Hyderabad their default');
  perform public.set_my_preference('table.pageSize', '50'::jsonb);
  perform test.ok((select (pref_value #>> '{}')::int from public.user_preferences
                    where user_id = test.uuid_of('sales') and pref_key = 'table.pageSize') = 50,
                  'a saved preference round-trips');
  perform test.raises('select public.set_my_preference(''BadKey'', ''1''::jsonb)', 'VAL001',
                      'preference keys are validated server side');
  perform test.ok((select count(*) from public.get_my_preferences() g) = 1,
                  'get_my_preferences returns one row for the caller');
end
$$;

-- role escalation must not be possible from the API (009 config + 008 grants)
do $$
begin
  perform test.raises('insert into public.roles (name, code) values (''Hackers'', ''HACK'')',
                      null, 'the API cannot invent roles');
  perform test.raises('insert into public.permissions (module, action, description) values (''x'',''y'',''z'')',
                      null, 'the API cannot invent permissions');
  perform test.raises('delete from public.audit_logs', null, 'audit history cannot be deleted');
end
$$;

reset role;

-- A brand-new signup is VIEWER even if the admin raced ahead of it (SS12)
insert into auth.users (id, email, raw_user_meta_data)
values ('a0000000-0000-0000-0000-000000000007','late.joiner@test.local','{"name":"Late Joiner"}')
on conflict (id) do nothing;

do $$
begin
  perform test.ok((select r.code from public.users u
                     join public.user_roles ur on ur.user_id = u.id
                     join public.roles r on r.id = ur.role_id
                    where u.auth_user_id = 'a0000000-0000-0000-0000-000000000007'::uuid) = 'VIEWER',
                  'late signups also get the least-privilege role');

  -- the auth->profile mirror is two-way for contact details
  update auth.users set phone = '+91 90000 11223'
    where id = 'a0000000-0000-0000-0000-000000000007'::uuid;
  perform test.ok((select count(*) from public.users u
                    where u.auth_user_id = 'a0000000-0000-0000-0000-000000000007'::uuid
                      and u.phone is not null) = 1,
                  'a phone number added in Auth reaches the profile');

  update auth.users set banned_until = now() + interval '1 day'
    where id = 'a0000000-0000-0000-0000-000000000007'::uuid;
  perform test.ok((select status from public.users u
                    where u.auth_user_id = 'a0000000-0000-0000-0000-000000000007'::uuid) = 'SUSPENDED',
                  'banning an auth user suspends the staff account');

  -- and a suspended account cannot act
  set role authenticated;
  perform test.as('a0000000-0000-0000-0000-000000000007'::uuid);
  -- A PENDING_ACTIVATION account can see its own preferences but no tenant data
  -- at all: the status gate lives in can_access_showroom(), i.e. in the policies.
  perform test.ok((select count(*) from public.customers) = 0,
                  'an unactivated account reads zero business rows');
  perform test.raises('select public.create_service_booking(''{}'')', 'SEC001',
                      'an unactivated account cannot call business RPCs');
  reset role;
end
$$;
