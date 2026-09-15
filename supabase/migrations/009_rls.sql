-- =============================================================================
-- 009_rls.sql  (SS49)
-- -----------------------------------------------------------------------------
-- Row Level Security for the whole system.  Policies are generated from a
-- small declarative config (app_sec.rls_policy_config) instead of 400
-- hand-written statements:
--
--   * the config is the single place to read "who may touch which table"
--   * re-running 009 is idempotent (drop + create per table)
--   * every policy is expressed through the SECURITY DEFINER helpers in 006,
--     which are owned by a superuser role and therefore never re-enter RLS
--     (the recursion trap called out in SS49)
--   * financial tables get SELECT/INSERT/UPDATE but deliberately *no* DELETE
--     policy, and DELETE is additionally revoked at the grant level
--
-- Policy shapes
--   tenant      : row is visible/writable when its showroom is granted to me
--   parent      : a child line table inherits the scope of its header row
--   self        : only my own rows (profile, notifications, devices, prefs)
--   global_read : readable by any authenticated user, written by permission
--   admin_only  : SUPER ADMIN only, everyone else sees nothing
--   append_only : readable per scope, insert-only, no update/delete at all
-- =============================================================================

create table if not exists app_sec.rls_policy_config (
  table_name     text primary key,
  kind           text not null check (kind in
                   ('tenant','parent','self','global_read','admin_only','append_only')),
  module         text,                              -- permission module governing writes
  select_action  text,          -- null = no SELECT policy (denied to the API)
  insert_action  text,                              -- null = no INSERT policy
  update_action  text,                              -- null = no UPDATE policy
  delete_action  text,                              -- null = no DELETE policy
  parent_table   text,                              -- for kind = 'parent'
  parent_fk      text,                              -- FK column on the child
  scope_column   text,          -- column on THIS table holding the tenant id
  note           text
);

comment on table app_sec.rls_policy_config is
  'Declarative RLS matrix. NULL in *_action means "no policy of that kind exists", which under RLS means "denied".';

insert into app_sec.rls_policy_config
      (table_name, kind, module, select_action, insert_action, update_action, delete_action, parent_table, parent_fk, scope_column, note)
values
  ('showrooms','tenant','showroom','view','create','edit',null,null,null,'id','a showroom is scoped by its own id'),
  ('users','tenant','users','view','create','edit',null,null,null,'showroom_id','plus users_self_select so a user always reads their own row'),
  ('user_showroom_access','tenant','users','view','edit','edit',null,null,null,'showroom_id',null),
  ('user_roles','tenant','roles','view','assign','assign',null,null,null,'showroom_id','showroom_id may be null = group-wide grant; can_access_showroom() handles null'),
  ('role_permissions','admin_only','roles','view','manage','manage','manage',null,null,null,'the permission matrix itself is SUPER ADMIN only'),
  ('permissions','global_read','roles','view',null,null,null,null,null,null,null),
  ('roles','global_read','roles','view','manage','manage',null,null,null,null,null),
  ('device_tokens','self','users','view','create','edit','delete',null,null,'user_id',null),
  ('user_preferences','self','settings','view','edit','edit','edit',null,null,'user_id',null),
  ('saved_filters','self','settings','view','create','edit','delete',null,null,'user_id',null),
  ('app_settings','global_read','settings','view',null,'edit',null,null,null,null,null),
  ('brands','global_read','products','view','create','edit','delete',null,null,null,null),
  ('products','global_read','products','view','create','edit','delete',null,null,null,null),
  ('product_colors','global_read','products','view','create','edit','delete',null,null,null,null),
  ('product_images','global_read','products','view','create','edit','delete',null,null,null,null),
  ('free_service_plans','global_read','service','view','create','edit','delete',null,null,null,null),
  ('finance_companies','global_read','finance','view','create','edit','delete',null,null,null,null),
  ('suppliers','global_read','suppliers','view','create','edit','delete',null,null,null,null),
  ('expense_categories','global_read','expenses','view','create','edit','delete',null,null,null,null),
  ('inventory','tenant','inventory','view','create','edit',null,null,null,'showroom_id','no physical delete: stock is returned or scrapped, never erased'),
  ('customers','tenant','customers','view','create','edit',null,null,null,'showroom_id',null),
  ('customer_vehicles','tenant','vehicles','view','create','edit',null,null,null,'showroom_id',null),
  ('sales','tenant','sales','view','create','edit',null,null,null,'showroom_id',null),
  ('sale_items','parent','sales','view','create','edit','delete','sales','sale_id',null,null),
  ('invoices','tenant','billing','view','create','edit',null,null,null,'showroom_id','amount columns are guarded by trg_guard_invoices_finalized (007)'),
  ('invoice_items','parent','billing','view','create','edit','delete','invoices','invoice_id',null,null),
  ('payments','tenant','payments','view','create',null,null,null,null,'showroom_id','money is immutable: INSERT only (plus status flips through RPCs that bypass RLS)'),
  ('stock_transfers','tenant','inventory','view','transfer','edit',null,null,null,'from_showroom_id','sender creates; receiver updates via receive_stock_transfer()'),
  ('stock_movements','append_only','inventory','view',null,null,null,null,null,'showroom_id','ledger: readable, never writable from the API'),
  ('purchases','tenant','purchases','view','create','edit',null,null,null,'showroom_id',null),
  ('purchase_items','parent','purchases','view','create','edit','delete','purchases','purchase_id',null,null),
  ('expenses','tenant','expenses','view','create','edit',null,null,null,'showroom_id',null),
  ('loans','tenant','finance','view','create','edit',null,null,null,'showroom_id',null),
  ('emi_schedules','tenant','emi','view','create','edit',null,null,null,'showroom_id',null),
  ('service_records','tenant','service','view','create','edit',null,null,null,'showroom_id',null),
  ('service_items','parent','service','view','create','edit','delete','service_records','service_id',null,null),
  ('vehicle_free_services','tenant','service','view','create','edit',null,null,null,'showroom_id',null),
  ('warranties','tenant','warranty','view','create','edit',null,null,null,'showroom_id',null),
  ('warranty_claims','tenant','warranty','view','claim','edit',null,null,null,'showroom_id',null),
  ('insurance_policies','tenant','insurance','view','create','edit',null,null,null,'showroom_id',null),
  ('reminders','tenant','reminders','view','create','edit',null,null,null,'showroom_id',null),
  ('notifications','tenant','notifications','view','create','edit',null,null,null,'showroom_id','own rows always readable; showroom broadcasts need showroom access'),
  ('accounts','tenant','accounting','view','create','edit',null,null,null,'showroom_id',null),
  ('accounting_transactions','tenant','accounting','view','post',null,null,null,null,'showroom_id','journals are written by app_acc.post_journal() only'),
  ('accounting_entries','parent','accounting','view',null,null,null,'accounting_transactions','transaction_id',null,'append-only through the parent journal'),
  ('attachments','tenant','documents','view','create','edit','delete',null,null,'showroom_id',null),
  ('audit_logs','append_only','audit','view',null,null,null,null,null,'showroom_id','read-only governance log; writers bypass RLS as definer'),
  ('document_sequences','admin_only',null,null,null,null,null,null,null,null,'numbering is allocated by RPCs; never exposed through the API'),
  ('idempotency_keys','self','settings','view',null,null,null,null,null,'user_id','a user may inspect their own replay guard'),
  ('sync_conflicts','tenant','settings','view','create','edit',null,null,null,'showroom_id',null)
on conflict (table_name) do update
   set kind = excluded.kind, module = excluded.module,
       select_action = excluded.select_action, insert_action = excluded.insert_action,
       update_action = excluded.update_action, delete_action = excluded.delete_action,
       parent_table = excluded.parent_table, parent_fk = excluded.parent_fk,
       scope_column = excluded.scope_column, note = excluded.note;


-- ---------------------------------------------------------------------------
-- Policy generator
-- ---------------------------------------------------------------------------
create or replace function app_sec.rebuild_rls_policies(p_only_table text default null)
returns table (configured_table text, policy_count integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  c        record;
  v_sel    text;
  v_ins    text;
  v_upd    text;
  v_del    text;
  v_created integer;
  v_sql    text;
begin
  for c in
    select cfg.*
      from app_sec.rls_policy_config cfg
     where (p_only_table is null or p_only_table = cfg.table_name)
       and exists (select 1 from information_schema.tables t
                    where t.table_schema = 'public' and t.table_name = cfg.table_name)
     order by cfg.table_name
  loop
    -- reset per iteration: a policy expression from the previous table must
    -- never leak into this one (plpgsql keeps locals between loop passes)
    v_sel := null; v_ins := null; v_upd := null; v_del := null; v_created := 0;

    execute format('alter table public.%I enable row level security', c.table_name);
    execute format('alter table public.%I force row level security', c.table_name);

    -- ---- SELECT ----------------------------------------------------------
    case c.kind
      when 'tenant' then
        if c.table_name = 'showrooms' then
          -- Never reference the policy's own table here: a self-join inside a
          -- policy on showrooms makes Postgres re-enter the policy and abort with
          -- "infinite recursion detected in policy". accessible_showroom_ids() is
          -- SECURITY DEFINER, so its own scan of showrooms runs outside RLS.
          v_sel := 'app_sec.is_super_admin() or id in (select app_sec.accessible_showroom_ids())';
        elsif c.table_name = 'notifications' then
          v_sel := '(user_id = app_sec.current_user_id()) or (user_id is null '
                || 'and (showroom_id is null or app_sec.can_access_showroom(showroom_id))) or app_sec.is_super_admin()';
        elsif c.table_name = 'users' then
          v_sel := 'app_sec.is_super_admin() or auth_user_id = auth.uid() '
                || 'or showroom_id in (select app_sec.accessible_showroom_ids())';
        elsif c.table_name in ('user_roles','user_showroom_access') then
          -- assignment tables: you always see your own, a manager sees the ones
          -- inside their showrooms, and org-wide grants stay super-admin only.
          v_sel := format('app_sec.is_super_admin() or %1$I.user_id = app_sec.current_user_id() '
                       || 'or (%2$I is not null and %2$I in (select app_sec.accessible_showroom_ids()))',
                          c.table_name, c.scope_column);
        else
          v_sel := format('app_sec.is_super_admin() or %s',
                          case when c.scope_column is null then 'true'
                               else format('%I in (select app_sec.accessible_showroom_ids())', c.scope_column)
                          end);
        end if;
      when 'parent' then
        v_sel := format('app_sec.is_super_admin() or exists (select 1 from public.%I p '
                     || 'where p.id = %I.%I and (p.showroom_id is null or app_sec.can_access_showroom(p.showroom_id)))',
                     c.parent_table, c.table_name, c.parent_fk);
      when 'self' then
        v_sel := format('app_sec.is_super_admin() or %I = app_sec.current_user_id()', c.scope_column);
      when 'global_read' then
        v_sel := 'auth.uid() is not null';
      when 'admin_only' then
        v_sel := 'app_sec.is_super_admin()';
      when 'append_only' then
        if c.table_name = 'audit_logs' then
          v_sel := 'app_sec.is_super_admin() or (showroom_id in (select app_sec.accessible_showroom_ids())'
                || ' and (user_id = app_sec.current_user_id()'
                || '      or app_sec.has_permission(''audit'',''view'')))';
        else
          v_sel := 'app_sec.is_super_admin() or showroom_id in (select app_sec.accessible_showroom_ids())';
        end if;
    end case;

    if c.select_action is not null and c.kind = 'tenant'
       and c.table_name not in ('showrooms','users','notifications','audit_logs') then
      v_sel := format('(app_sec.is_super_admin() or app_sec.has_permission(%L,%L)) and %s',
                      c.module, c.select_action, v_sel);
    end if;

    -- ---- INSERT ----------------------------------------------------------
    if c.insert_action is not null then
      case
        when c.kind = 'tenant' and c.table_name = 'showrooms' then
          v_ins := format('app_sec.is_super_admin() or app_sec.has_permission(%L,%L)', c.module, c.insert_action);
        when c.kind = 'tenant' then
          v_ins := format('(app_sec.is_super_admin() or app_sec.has_permission(%L,%L)) %s',
                       c.module, c.insert_action,
                       case when c.scope_column is null then ''
                            else format(' and app_sec.can_access_showroom(%I)', c.scope_column) end);
        when c.kind = 'self' then
          v_ins := format('%I = app_sec.current_user_id()', c.scope_column);
        when c.kind = 'global_read' then
          v_ins := format('app_sec.has_permission(%L,%L)', c.module, c.insert_action);
        when c.kind = 'admin_only' then
          v_ins := 'app_sec.is_super_admin()';
        when c.kind = 'parent' then
          v_ins := format('app_sec.has_permission(%L,%L) and exists (select 1 from public.%I p '
                       || 'where p.id = %I.%I and app_sec.can_access_showroom(p.showroom_id))',
                       c.module, c.insert_action, c.parent_table, c.table_name, c.parent_fk);
        when c.kind = 'append_only' then
          v_ins := null;   -- ledgers are written by SECURITY DEFINER paths only
      end case;
    else
      v_ins := null;
    end if;

    -- ---- UPDATE / DELETE -------------------------------------------------
    if c.update_action is not null then
      v_upd := format('(app_sec.is_super_admin() or app_sec.has_permission(%L,%L))', c.module, c.update_action);
      if c.kind = 'tenant' and c.table_name <> 'showrooms' and c.scope_column is not null then
        v_upd := v_upd || format(' and %I in (select app_sec.accessible_showroom_ids())', c.scope_column);
      elsif c.kind = 'tenant' then
        v_upd := v_upd || format(' and id in (select app_sec.accessible_showroom_ids())');
      elsif c.kind = 'self' then
        v_upd := format('%I = app_sec.current_user_id()', c.scope_column);
      elsif c.kind = 'parent' then
        v_upd := v_upd || format(' and exists (select 1 from public.%I p where p.id = %I.%I'
                             || ' and app_sec.can_access_showroom(p.showroom_id))',
                             c.parent_table, c.table_name, c.parent_fk);
      end if;
    end if;

    if c.delete_action is not null then
      v_del := format('(app_sec.is_super_admin() or app_sec.has_permission(%L,%L))', c.module, c.delete_action);
      if c.kind = 'tenant' and c.scope_column is not null then
        v_del := v_del || format(' and %I in (select app_sec.accessible_showroom_ids())', c.scope_column);
      elsif c.kind = 'global_read' or c.kind = 'admin_only' then
        v_del := v_del;
      elsif c.kind = 'parent' then
        v_del := v_del || format(' and exists (select 1 from public.%I p where p.id = %I.%I'
                             || ' and app_sec.can_access_showroom(p.showroom_id))',
                             c.parent_table, c.table_name, c.parent_fk);
      elsif c.kind = 'self' then
        v_del := format('%I = app_sec.current_user_id()', c.scope_column);
      end if;
    end if;

    -- drop then recreate: idempotent by construction
    if c.select_action is not null then
      execute format('drop policy if exists %1$I_select on public.%1$I', c.table_name);
      execute format('create policy %1$I_select on public.%1$I for select to authenticated
                        using (%s)', c.table_name, coalesce(v_sel, 'false'));
      v_created := 1;
    else
      execute format('drop policy if exists %1$I_select on public.%1$I', c.table_name);
    end if;

    if v_ins is not null then
      execute format('drop policy if exists %1$I_insert on public.%1$I', c.table_name);
      execute format('create policy %1$I_insert on public.%1$I for insert to authenticated
                        with check (%s)', c.table_name, v_ins);
      v_created := v_created + 1;
    end if;

    if v_upd is not null then
      execute format('drop policy if exists %1$I_update on public.%1$I', c.table_name);
      execute format('create policy %1$I_update on public.%1$I for update to authenticated
                        using (%s) with check (%s)', c.table_name,
                        coalesce(v_sel, v_upd), v_upd);
      v_created := v_created + 1;
    end if;

    if v_del is not null then
      execute format('drop policy if exists %1$I_delete on public.%1$I', c.table_name);
      execute format('create policy %1$I_delete on public.%1$I for delete to authenticated
                        using (%s)', c.table_name, v_del);
      v_created := v_created + 1;
    end if;

    -- A second, narrower SELECT policy so a user can always read their own profile.
    if c.table_name = 'users' then
      execute format('drop policy if exists users_self_select on public.users');
      execute format('create policy users_self_select on public.users for select to authenticated
                        using (auth_user_id = auth.uid())');
      v_created := v_created + 1;
    end if;

    return query select c.table_name, v_created;
  end loop;
end;
$$;

select configured_table as table_name, policy_count as policies
  from app_sec.rebuild_rls_policies() order by 1;

-- ---------------------------------------------------------------------------
-- Grant hygiene: the API role gets only what the policies assume, and no
-- financial table can ever be TRUNCATEd/DELETEd through the gateway.
-- ---------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in select * from app_sec.rls_policy_config order by table_name loop
    execute format('grant select on public.%I to anon, authenticated', c.table_name);
    execute format('grant insert on public.%I to authenticated', c.table_name);
    execute format('grant update on public.%I to authenticated', c.table_name);
    if c.delete_action is not null then
      execute format('grant delete on public.%I to authenticated', c.table_name);
    else
      execute format('revoke delete on public.%I from anon, authenticated', c.table_name);
    end if;
    execute format('revoke truncate on public.%I from anon, authenticated', c.table_name);
    execute format('revoke all on public.%I from public', c.table_name);
  end loop;
  -- ledgers: no client-side writes at all, they belong to the RPC layer
  execute 'revoke insert, update, delete on public.audit_logs, public.stock_movements,
            public.accounting_entries, public.document_sequences from anon, authenticated';
end
$$;

-- Internal schemas must never be reachable from the API.
revoke all on schema app_sec, app_util, app_gen, app_acc from public, anon, authenticated;
grant usage on schema app_sec, app_util, app_gen, app_acc to service_role;

-- Views are exposed read-only; every business view is created WITH
-- (security_invoker = true) in 011 so it can never leak a row the base-table
-- RLS would hide.
do $$
declare
  v record;
begin
  for v in select viewname from pg_views where schemaname = 'public' loop
    execute format('grant select on public.%I to authenticated', v.viewname);
    execute format('revoke all on public.%I from public', v.viewname);
  end loop;
end
$$;
