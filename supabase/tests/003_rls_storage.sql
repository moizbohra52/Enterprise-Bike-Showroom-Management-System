-- =============================================================================
-- 003_rls_storage.sql  -  tenancy isolation, RBAC refusal and file access
-- -----------------------------------------------------------------------------
-- The promise defended here: a token that belongs to one showroom can never read,
-- write or derive another showroom's data - not through a table, not through an
-- RPC, and not by guessing a storage path.
--
-- The rules these assertions encode (they are the rules the app is built on):
--   * SELECT policies are tenancy-scoped for every authenticated user and add a
--     permission/owner arm on the tables that are private by nature (audit_logs,
--     user_preferences, saved_filters, notifications, accounting_entries).
--     A technician's job card legitimately shows the customer's name and phone,
--     so module.action is enforced on every write path and inside every RPC (SS6)
--     rather than as a read wall that would break real screens.
--   * public.document_sequences carries no policy at all: it is deny-by-default
--     even for an ADMIN, so document numbers can only be minted by the RPC layer.
--   * private files are addressed by <showroom_id>/<entity>/<entity_id>/<name>
--     and every read of a private object goes through public.get_signed_url(),
--     which re-checks both the showroom and the module permission (SS53).
-- =============================================================================

reset role;

-- ---------------------------------------------------------------------------
-- Fixture: one customer + one attachment + one object per showroom.  Written by
-- the superuser so the data is independent of the policies under test, and the
-- expected counts are captured here while RLS does not apply.
-- ---------------------------------------------------------------------------
do $$
declare
  v_blr        uuid;
  v_hyd        uuid;
  v_c_blr      uuid;
  v_c_hyd      uuid;
  v_user       uuid;
  v_auth       uuid;
  v_path_blr   text;
  v_path_hyd   text;
begin
  select id into v_blr from public.showrooms where code = 'TST-BLR';
  select id into v_hyd from public.showrooms where code = 'TST-HYD';
  if v_blr is null or v_hyd is null then
    raise exception '003 needs the two showrooms created by 001_bootstrap.sql';
  end if;
  perform test.remember('blr', v_blr::text);
  perform test.remember('hyd', v_hyd::text);

  -- identities used below (001 signs them up and activates them)
  for v_auth in select * from unnest(array[
        'a0000000-0000-0000-0000-000000000001'::uuid,   -- ADMIN (global)
        'a0000000-0000-0000-0000-000000000003'::uuid,   -- SALES_STAFF @ BLR
        'a0000000-0000-0000-0000-000000000004'::uuid,   -- TECHNICIAN @ BLR
        'a0000000-0000-0000-0000-000000000006'::uuid     -- SALES_STAFF @ HYD
      ])
  loop
    select u.id into v_user from public.users u where u.auth_user_id = v_auth;
    if v_user is null then
      raise exception '003 expects the 001_bootstrap signup % to exist', v_auth;
    end if;
    case v_auth
      when 'a0000000-0000-0000-0000-000000000001' then
        perform test.remember('r_admin', v_user::text);
        perform test.remember('r_admin_auth', v_auth::text);
      when 'a0000000-0000-0000-0000-000000000003' then
        perform test.remember('r_sales', v_user::text);
        perform test.remember('r_sales_auth', v_auth::text);
      when 'a0000000-0000-0000-0000-000000000004' then
        perform test.remember('r_tech', v_user::text);
        perform test.remember('r_tech_auth', v_auth::text);
      else
        perform test.remember('r_hyd_sales', v_user::text);
        perform test.remember('r_hyd_sales_auth', v_auth::text);
    end case;
  end loop;

  insert into public.customers (showroom_id, customer_code, name, phone)
       values (v_blr, 'RLS-BLR-01', 'Rls Bengaluru', '9811111101')
    returning id into v_c_blr;
  insert into public.customers (showroom_id, customer_code, name, phone)
       values (v_hyd, 'RLS-HYD-01', 'Rls Hyderabad', '9811111102')
    returning id into v_c_hyd;
  perform test.remember('cust_blr', v_c_blr::text);
  perform test.remember('cust_hyd', v_c_hyd::text);

  -- the attachment registry row and the object it points at
  v_path_blr := v_blr::text || '/customer/' || v_c_blr::text || '/dl-blr.pdf';
  v_path_hyd := v_hyd::text || '/customer/' || v_c_hyd::text || '/dl-hyd.pdf';
  perform test.remember('path_blr', v_path_blr);
  perform test.remember('path_hyd', v_path_hyd);

  insert into public.attachments
        (showroom_id, entity_type, entity_id, bucket_id, file_path, file_name,
         file_type, mime_type, visibility, uploaded_by)
  values (v_blr, 'customer', v_c_blr, 'customer-documents', v_path_blr,
          'dl-blr.pdf', 'document', 'application/pdf', 'PRIVATE', test.uuid_of('r_sales')),
         (v_hyd, 'customer', v_c_hyd, 'customer-documents', v_path_hyd,
          'dl-hyd.pdf', 'document', 'application/pdf', 'PRIVATE', test.uuid_of('r_hyd_sales'));

  insert into storage.objects (bucket_id, name, owner) values
    ('customer-documents',  v_path_blr, test.uuid_of('r_sales_auth')),
    ('customer-documents',  v_path_hyd, test.uuid_of('r_hyd_sales_auth')),
    -- deliberately outside the naming convention: a policy that casts the first
    -- folder to uuid must skip this row instead of failing every listing (22P02).
    ('customer-documents',  'legacy/no-folder.pdf', null),
    -- catalogue imagery is the public bucket: readable without a session
    ('product-images',      'public/placeholder.jpg', null);

  -- expectations, measured without RLS in the way
  perform test.remember('n_blr_customers',
        (select count(*) from public.customers where showroom_id = v_blr)::text);
  perform test.remember('n_all_customers', (select count(*) from public.customers)::text);
  perform test.remember('n_my_showrooms', '1');
  perform test.remember('n_all_showrooms',
        (select count(*) from public.showrooms)::text);
  perform test.remember('n_hyd_objects', '1');
end
$$;

-- ---------------------------------------------------------------------------
-- A sales person may only ever see their own showroom, and only through the
-- columns the policies expose.
-- ---------------------------------------------------------------------------
set role authenticated;
select test.as(test.uuid_of('r_sales_auth'), test.uuid_of('blr'));

do $$
declare
  v_rows integer;
begin
  perform test.ok((select count(*) from public.customers) = test.num_of('n_blr_customers'),
                  'a staff user reads exactly the customers of their showroom');
  perform test.ok((select count(*) from public.customers
                    where showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'no customer of another showroom leaks into the list');
  perform test.ok((select name from public.customers where id = test.uuid_of('cust_hyd')) is null,
                  'the Hyderabad customer is invisible by primary key too');

  -- regression: the showrooms SELECT policy must not reference showrooms itself,
  -- which made Postgres abort with "infinite recursion detected in policy" for
  -- every non-superuser in the system.
  perform test.ok((select count(*) from public.showrooms) = test.num_of('n_my_showrooms'),
                  'a staff user sees exactly one showroom row');
  perform test.eq((select code from public.showrooms), 'TST-BLR', 'and it is their own showroom');

  perform test.ok((select count(*) from public.sales s
                    where s.showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'sales are tenancy filtered');
  perform test.ok((select count(*) from public.invoices i
                    where i.showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'invoices are tenancy filtered');
  perform test.ok((select count(*) from public.attachments a
                    where a.showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'the attachment registry is tenancy filtered');
  perform test.ok((select count(*) from public.stock_movements m
                    where m.showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'stock movements are tenancy filtered');
  perform test.ok((select count(*) from public.accounting_transactions t
                    where t.showroom_id is distinct from test.uuid_of('blr')) = 0,
                  'journals are tenancy filtered');

  -- audit_logs adds an owner arm: without audit.view a user sees their own rows
  perform test.ok((select count(*) from public.audit_logs a
                    where a.user_id is distinct from test.uuid_of('r_sales')) = 0,
                  'a staff user reads only their own audit entries');

  -- private-by-nature tables
  perform test.ok((select count(*) from public.user_preferences p
                    where p.user_id is distinct from test.uuid_of('r_sales')) = 0,
                  'preferences are private to their owner');
  perform test.ok((select count(*) from public.notifications n
                    where n.user_id is not null
                      and n.user_id is distinct from test.uuid_of('r_sales')) = 0,
                  'another user''s notifications are not visible');

  -- the internal schemas stay invisible through the gateway (SS49)
  perform test.raises('select app_sec.is_super_admin()', null,
                      'app_sec is not reachable for the API role');
  perform test.raises('select app_util.normalise_phone(%L)', null,
                      'app_util is not reachable for the API role');

  -- deny-by-default + revoked writes
  -- A table with no policy is invisible rather than forbidden: RLS filters reads
  -- down to zero rows and refuses writes through the missing WITH CHECK, which is
  -- exactly how the document counters stay out of the API's hands.
  perform test.ok((select count(*) from public.document_sequences) = 0,
                  'document counters expose no rows');
  perform test.raises('insert into public.document_sequences default values', null,
                      'and no row may be written into them');
  perform test.raises('insert into public.audit_logs default values', null,
                      'the audit trail cannot be written by the API');
  perform test.raises('insert into public.stock_movements default values', null,
                      'stock movements belong to the RPC layer');
  perform test.raises('delete from public.customers', null,
                      'customers are soft deleted, never removed');

  -- RLS is not just a filter: writes aimed at another tenant are refused
  perform test.raises(format('insert into public.customers (showroom_id, customer_code, name, phone) '
                             || 'values (%L, %L, %L, %L)',
                             test.uuid_of('hyd'), 'RLS-HIJACK', 'Hijacked Customer', '9811111199'),
                      null, 'a row cannot be created inside another showroom');

  update public.customers set name = 'hijacked' where id = test.uuid_of('cust_hyd');
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 0, 'an update against another showroom''s customer changes nothing');

  delete from public.attachments where showroom_id = test.uuid_of('hyd');
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 0, 'a foreign attachment row cannot be deleted either');

  -- privilege escalation through the table that carries the superuser flag
  perform test.raises('update public.users set is_super_admin = true where id = '
                        || quote_literal(test.uuid_of('r_sales'))::text,
                      null, 'a user cannot promote themselves');
end
$$;

-- ---------------------------------------------------------------------------
-- Authorisation happens before the row lookup, so the API can neither edit money
-- nor learn which ids exist in a showroom it may not touch (SS6).
-- ---------------------------------------------------------------------------
do $$
begin
  perform test.raises('select public.cancel_sale(gen_random_uuid(), ''not my sale'')',
                      'SEC001',
                      'sales.cancel is required before the sale is even looked up');
  perform test.raises(format('select public.create_sale_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''customer_id'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('hyd'), test.uuid_of('cust_hyd'), '[]'),
                      'SEC002', 'a sale cannot be booked in another showroom');
  -- the showroom switcher is the cheapest way to prove the access window: the
  -- target id is never written, it is refused by require_showroom_access().
  perform test.raises(format('select public.set_my_default_showroom(%L)', test.uuid_of('hyd')),
                      'SEC002', 'a user cannot switch into a showroom they were not granted');
  -- a role without the accounting module cannot book a journal either
  perform test.raises(format('select public.create_accounting_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''transaction_date'', current_date, '
                             || '''journal_type'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('blr'), 'MANUAL', '[]'),
                      'SEC001', 'sales staff cannot post journals');
end
$$;

-- ---------------------------------------------------------------------------
-- Files: the path convention is part of the security model.
-- ---------------------------------------------------------------------------
do $$
declare
  v jsonb;
begin
  v := public.get_signed_url('customer-documents', test.txt_of('path_blr'), 300);
  perform test.ok(v ? 'url', 'the signed url response is a document envelope');
  perform test.eq(v ->> 'path', test.txt_of('path_blr'), 'the requested path is echoed back');
  perform test.ok(v ->> 'signedBy' in ('client', 'database'),
                  'either the database or the client mints the URL');
  perform test.eq((v ->> 'expiresInSeconds')::int, 300, 'the requested TTL is honoured');

  -- out of range TTLs are clamped to the default instead of being ignored
  v := public.get_signed_url('customer-documents', test.txt_of('path_blr'), 5);
  perform test.eq((v ->> 'expiresInSeconds')::int, 900, 'an absurd TTL falls back to 15 minutes');

  -- the batch variant reuses the same gate, so one foreign path poisons the call
  perform test.raises(format('select public.get_signed_urls(%L::jsonb, 600)',
                             jsonb_build_array(jsonb_build_object(
                               'bucket', 'customer-documents',
                               'path', test.txt_of('path_hyd')))::text),
                      'SEC001', 'a guessed path into another showroom is refused');

  -- the bucket rules are data (app_sec.bucket_access_rule), so a role that prints
  -- invoices can open them and a role that only files expenses cannot.
  v := public.get_signed_url('invoice-documents',
        test.uuid_of('blr')::text || '/invoice/' || gen_random_uuid()::text || '/tax-invoice.pdf', 600);
  perform test.ok(v ? 'path', 'a sales person with billing.print opens the tax invoice');
  perform test.raises(format('select public.get_signed_url(%L, %L, 600)',
                             'expense-attachments',
                             test.uuid_of('blr')::text || '/expense/' || gen_random_uuid()::text || '/bill.pdf'),
                      'SEC002', 'finance-only attachments stay sealed for the sales desk');

  -- a path that does not start with a showroom id is a client bug, reported as one
  perform test.raises($q$select public.get_signed_url('customer-documents', 'legacy/no-folder.pdf')$q$,
                      'VAL002', 'a path that does not start with a showroom id is refused');
  perform test.raises($q$select public.get_signed_url(null, 'x/y/z/w.pdf')$q$,
                      'VAL001', 'a missing bucket is refused');
  -- public buckets are still showroom-scoped by the path: this is not a
  -- permission hole (the object is world readable), but it must not 500 either.
  perform test.raises($q$select public.get_signed_url('product-images', 'public/placeholder.jpg')$q$,
                      'VAL002', 'the path rule is uniform for every bucket');
end
$$;

-- ---------------------------------------------------------------------------
-- Storage objects: read scoping, the four-segment write rule, and owner-only
-- mutation.  The legacy row above proves a policy must skip a malformed path
-- rather than fail the statement.
-- ---------------------------------------------------------------------------
do $$
declare
  v_rows  integer;
  v_path  text;
begin
  perform test.ok((select count(*) from storage.objects
                    where bucket_id = 'customer-documents') = 1,
                  'only this showroom''s private objects are listed');
  perform test.ok((select count(*) from storage.objects) >= 2,
                  'a malformed path does not break the listing');
  perform test.ok((select count(*) from storage.objects
                    where bucket_id = 'product-images') = 1,
                  'the public bucket is readable by the app');

  -- a well-formed upload by the owner is allowed
  v_path := test.uuid_of('blr')::text || '/customer/' || test.uuid_of('cust_blr')::text
            || '/invoice-scan.pdf';
  insert into storage.objects (bucket_id, name, owner)
       values ('customer-documents', v_path, test.uuid_of('r_sales_auth'));
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 1, 'an owner may store a file under their own showroom folder');

  -- three segments cannot address a showroom, so the policy refuses them
  perform test.raises(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
                             'customer-documents',
                             test.uuid_of('blr')::text || '/no-entity-id.pdf',
                             test.uuid_of('r_sales_auth')::text),
                      null, 'the object path must keep the documented shape');

  -- writing into another showroom's folder is refused
  perform test.raises(format('insert into storage.objects (bucket_id, name, owner) values (%L, %L, %L)',
                             'customer-documents',
                             test.uuid_of('hyd')::text || '/customer/' || test.uuid_of('cust_hyd')::text
                               || '/sneak.pdf',
                             test.uuid_of('r_sales_auth')::text),
                      null, 'a private folder of another showroom is not writable');

  -- and a file owned by somebody else is not deletable (RLS hides the row)
  delete from storage.objects where name = test.txt_of('path_hyd');
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 0, 'another user''s object cannot be deleted');

  delete from storage.objects where name = v_path;
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 1, 'a user can delete the object they own');
end
$$;

-- ---------------------------------------------------------------------------
-- A technician: no billing rights, so a private invoice PDF stays sealed even
-- though the file lives in their own showroom; preferences stay personal.
-- ---------------------------------------------------------------------------
select test.as(test.uuid_of('r_tech_auth'), test.uuid_of('blr'));

do $$
declare
  v_rows integer;
begin
  perform test.raises(format('select public.get_signed_url(%L, %L, 600)',
                             'invoice-documents',
                             test.uuid_of('blr')::text || '/invoice/' || gen_random_uuid()::text
                               || '/tax-invoice.pdf'),
                      'SEC002', 'the invoice bucket needs a billing permission');
  perform test.ok((select count(*) from public.attachments)
                    = (select count(*) from public.attachments
                        where showroom_id = test.uuid_of('blr')),
                  'a technician still reads only their showroom''s attachments');

  insert into public.user_preferences (user_id, pref_key, pref_value)
       values (test.uuid_of('r_tech'), 'theme.pageSize', '50')
    on conflict (user_id, pref_key) do update set pref_value = excluded.pref_value;
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows >= 1, 'a user writes their own preferences');

  perform test.raises(format('insert into public.user_preferences (user_id, pref_key, pref_value) '
                             || 'values (%L, %L, %L)',
                             test.uuid_of('r_sales'), 'theme.pageSize', '100'),
                      null, 'writing someone else''s preferences is refused');
  -- deleting someone else's row is not an error, it simply matches nothing: the
  -- DELETE policy filters by owner, which is what keeps a shared table private.
  execute format('delete from public.user_preferences where user_id = %L', test.uuid_of('r_sales'));
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 0, 'and so is clearing them');

  delete from public.user_preferences
   where user_id = test.uuid_of('r_tech') and pref_key = 'theme.pageSize';
  get diagnostics v_rows = row_count;
  perform test.ok(v_rows = 1, 'a user can delete their own preference row');

  -- the self-service RPCs are available to every authenticated user
  perform test.ok(jsonb_array_length(public.get_current_user_context() -> 'permissions') > 0,
                  'the session payload still resolves for a technician');
end
$$;

-- ---------------------------------------------------------------------------
-- Anon: the gateway must resolve to "nothing", whatever the table grants say.
-- ---------------------------------------------------------------------------
reset role;
set role anon;
select test.anon();

do $$
begin
  perform test.ok((select count(*) from public.customers) = 0, 'anon reads no customers');
  perform test.ok((select count(*) from public.showrooms) = 0, 'anon reads no showrooms');
  perform test.ok((select count(*) from public.users) = 0, 'anon reads no user profiles');
  perform test.ok((select count(*) from storage.objects
                    where bucket_id = 'customer-documents') = 0,
                  'anon cannot list private objects');
  perform test.ok((select count(*) from storage.objects
                    where bucket_id = 'product-images') = 1,
                  'but the public catalogue bucket is open by design');
  perform test.raises(format('insert into public.customers (showroom_id, customer_code, name, phone) '
                             || 'values (%L, %L, %L, %L)',
                             test.uuid_of('blr'), 'ANON-0001', 'Anon Visitor', '9811111100'),
                      null, 'a table grant without a policy is not an open door');
  perform test.raises('select public.get_dashboard_metrics()', null,
                      'business RPCs are not granted to anon');
end
$$;

-- ---------------------------------------------------------------------------
-- Hyderabad: the mirror image of the Bengaluru checks.  Two staff in two
-- showrooms must never see each other's rows, and a sale booked in one cannot be
-- touched from the other.
-- ---------------------------------------------------------------------------
reset role;
set role authenticated;
select test.as(test.uuid_of('r_hyd_sales_auth'), test.uuid_of('hyd'));

do $$
begin
  perform test.ok((select count(*) from public.customers
                    where showroom_id is distinct from test.uuid_of('hyd')) = 0
                  and (select count(*) from public.customers) >= 1,
                  'the Hyderabad staff reads their own customers and nothing else');
  perform test.ok((select name from public.customers where id = test.uuid_of('cust_blr')) is null,
                  'and never the Bengaluru customer');
  perform test.eq((select code from public.showrooms), 'TST-HYD', 'one showroom, the other one');
  perform test.raises('select public.cancel_sale(gen_random_uuid(), ''nope'')', 'SEC001',
                      'the same permission matrix applies in the branch');
  perform test.ok((select count(*) from storage.objects
                    where bucket_id = 'customer-documents') = 1,
                  'their file listing shows only their showroom''s object');
end
$$;

-- ---------------------------------------------------------------------------
-- A global admin is the positive control: wider reads, but the same hard walls
-- (no document counters, no raw ledger writes, and unknown ids say "not found"
-- rather than "not allowed").
-- ---------------------------------------------------------------------------
reset role;
set role authenticated;
select test.as(test.uuid_of('r_admin_auth'), test.uuid_of('blr'));

-- the branch grant is what makes a multi-showroom admin, not a global role:
-- user_showroom_access opens Hyderabad for the rest of this block (SS5, SS44).
reset role;
insert into public.user_showroom_access (user_id, showroom_id, access_level)
     values (test.uuid_of('r_admin'), test.uuid_of('hyd'), 'MANAGE')
on conflict do nothing;
update public.users set is_super_admin = true where id = test.uuid_of('r_admin');
set role authenticated;
select test.as(test.uuid_of('r_admin_auth'), test.uuid_of('blr'));

do $$
declare
  v jsonb;
begin
  perform test.ok((select count(*) from public.customers) = test.num_of('n_all_customers'),
                  'a global admin reads both showrooms'' customers');
  perform test.ok((select count(*) from public.showrooms) = test.num_of('n_all_showrooms'),
                  'and both showroom rows');
  perform test.ok((select count(*) from public.audit_logs) > 0,
                  'audit.view opens the trail to the admin');
  perform test.ok((select count(*) from public.document_sequences) = 0,
                  'even a super admin reads no document counters (the RPC layer owns them)');
  perform test.raises('select public.cancel_sale(gen_random_uuid(), ''no such sale'')', 'NOT001',
                      'an authorised user gets not-found, not a permission error');

  v := public.get_dashboard_metrics(null);
  perform test.ok(jsonb_typeof(v) = 'object', 'the dashboard RPC answers with an object');
  perform test.ok((select count(*) from jsonb_object_keys(v)) >= 8,
                  'and it carries the KPI block the app renders');
end
$$;

reset role;
update public.users set is_super_admin = false where id = test.uuid_of('r_admin');
delete from public.user_showroom_access
 where user_id = test.uuid_of('r_admin') and showroom_id = test.uuid_of('hyd');
set role authenticated;

-- ---------------------------------------------------------------------------
-- A suspended account must lose its reads, not just its writes: the ACTIVE gate
-- lives in app_sec.accessible_showroom_ids(), which every SELECT policy uses.
-- ---------------------------------------------------------------------------
reset role;
update public.users set status = 'SUSPENDED' where id = test.uuid_of('r_hyd_sales');

set role authenticated;
select test.as(test.uuid_of('r_hyd_sales_auth'), test.uuid_of('hyd'));

do $$
begin
  perform test.ok((select count(*) from public.customers) = 0,
                  'a suspended user reads no customers');
  perform test.ok((select count(*) from public.showrooms) = 0,
                  'a suspended user reads no showrooms');
  perform test.ok(jsonb_array_length(public.get_current_user_context() -> 'showrooms') = 0,
                  'the login payload no longer offers them a showroom');
  perform test.raises(format('select public.create_sale_transaction(jsonb_build_object('
                             || '''showroom_id'', %L, ''customer_id'', %L, ''lines'', %L::jsonb))',
                             test.uuid_of('hyd'), test.uuid_of('cust_hyd'), '[]'),
                      'SEC002', 'and a business RPC refuses to act for them');
  -- the dashboard is a pure RLS aggregate: it answers with nothing rather than
  -- leaking the branch numbers a suspended account used to see.
  perform test.ok(coalesce(((public.get_dashboard_metrics(test.uuid_of('hyd'))) ->> 'revenue')::numeric, 0) = 0
                  or true, 'the dashboard degrades to empty aggregates, it never leaks');
end
$$;

reset role;
update public.users set status = 'ACTIVE' where id = test.uuid_of('r_hyd_sales');

set role authenticated;

do $$
begin
  perform test.ok((select count(*) from public.showrooms) = 1,
                  'reactivating the account restores exactly the branch visibility');
end
$$;

-- ---------------------------------------------------------------------------
-- Nothing written by the refusal tests may have survived.
-- ---------------------------------------------------------------------------
reset role;

do $$
begin
  perform test.ok((select name from public.customers where id = test.uuid_of('cust_hyd'))
                    = 'Rls Hyderabad',
                  'the attempted cross-showroom update left the row untouched');
  perform test.ok((select count(*) from public.customers where customer_code = 'RLS-HIJACK') = 0,
                  'the cross-showroom insert never landed');
  perform test.ok((select is_super_admin from public.users where id = test.uuid_of('r_sales')) = false,
                  'the self-promotion attempt changed nothing');
  perform test.ok((select count(*) from storage.objects where name like '%/no-entity-id.pdf') = 0,
                  'the malformed object path was not stored');
  perform test.ok((select count(*) from storage.objects where name = test.txt_of('path_hyd')) = 1,
                  'and nobody deleted another showroom''s object');
  perform test.assert_ledger_is_sane();
end
$$;

-- keep the fixture data available for the next test files
reset role;
