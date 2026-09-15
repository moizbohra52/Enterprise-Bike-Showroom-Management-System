-- =============================================================================
-- 015_auth_triggers.sql  (SS12, SS28, SS72, SS83)
-- -----------------------------------------------------------------------------
-- Glue between Supabase Auth and the application's user table.
--
--   * a signup (email or phone/OTP) creates the public.users row, the least
--     privilege VIEWER role and an audit entry  -  exactly what SS12 promises
--   * an email/phone/name change in Auth is mirrored, never the other way
--     around, so the two identities cannot drift
--   * login/logout/session events reach audit_logs, which SS57 asks the client
--     to trigger (the client cannot write the immutable audit table itself)
--   * the final EXECUTE grant list: the only RPCs PostgREST will accept from
--     anon/authenticated.  Anything not listed here is unreachable over REST,
--     even if a policy would allow it.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. New auth user -> application user
-- ---------------------------------------------------------------------------
create or replace function app_sec.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid;
  v_role  uuid;
  v_shr   uuid;
  v_email text;
  v_name  text;
  v_provider text;
  v_status text;
begin
  v_provider := coalesce(new.raw_app_meta_data ->> 'provider',
                         case when new.phone is not null then 'phone' else 'email' end);
  v_email := nullif(lower(coalesce(new.email, new.raw_user_meta_data ->> 'email', '')), '');
  v_name  := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'name',
                                  new.raw_user_meta_data ->> 'full_name',
                                  split_part(coalesce(new.phone, v_email, 'new user'), '@', 1))), '');

  -- Controlled onboarding (SS83): a signup is attached to a showroom only when the
  -- creator said which one.  Otherwise the profile stays unassigned and
  -- PENDING_ACTIVATION, so an unassigned account cannot read a single business
  -- row - public sign-ups are harmless.  A manager assigns showroom + role from
  -- the Users screen, which flips the status to ACTIVE.
  -- metadata comes from the client, so nothing here may be able to throw: an
  -- error in this trigger would fail the signup itself.
  if (new.raw_user_meta_data ->> 'showroom_id') ~*
     '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_shr := (new.raw_user_meta_data ->> 'showroom_id')::uuid;
    if not exists (select 1 from public.showrooms sh
                    where sh.id = v_shr and sh.status <> 'CLOSED') then
      v_shr := null;   -- a stale id must not create a half-attached account
    end if;
  end if;
  v_status := case when lower(coalesce(new.raw_user_meta_data ->> 'activated','')) = 'true'
                     and v_shr is not null
                   then 'ACTIVE' else 'PENDING_ACTIVATION' end;

  insert into public.users (auth_user_id, showroom_id, name, email, phone, status,
                            employee_code, password_changed_at)
  values (new.id, v_shr, coalesce(v_name, 'New User'), v_email,
          app_util.normalise_phone(new.phone), v_status,
          case when new.raw_user_meta_data ? 'employee_code'
               then nullif(new.raw_user_meta_data ->> 'employee_code','') end,
          now())
  returning id into v_user;

  -- least privilege by default (SS12).  Roles are granted by a manager or by
  -- bootstrap_super_admin(); never auto-elevate on the strength of a signup.
  select id into v_role from public.roles where code = 'VIEWER';
  if v_role is not null then
    insert into public.user_roles (user_id, role_id, showroom_id)
    values (v_user, v_role, null)
    on conflict (user_id, role_id, showroom_id) do nothing;
  end if;

  perform app_util.audit_row('auth','CREATE','users', v_user, null,
          jsonb_build_object('authUserId', new.id, 'email', v_email, 'phone', new.phone,
                             'provider', v_provider, 'showroomId', v_shr,
                             'source', 'auth.users trigger'),
          v_shr, v_user, coalesce(v_name, 'New User'), 'INFO');

  -- a friendly notification for the manager who has to approve the account
  insert into public.notifications (user_id, showroom_id, title, message, notification_type,
                                   severity, route_name, route_params)
  select a.user_id, v_shr, 'New user registered',
         coalesce(v_name, 'A new user') || ' (' || coalesce(v_email, new.phone, 'no email') ||
         ') signed up and is waiting for activation. Assign a showroom and role '
         || case when v_shr is null then ' (no showroom was requested)' else '' end || '.',
         'SYSTEM', 'INFO', '/users', jsonb_build_object('userId', v_user)
    from public.user_showroom_access a
   where a.showroom_id = v_shr and a.access_level = 'MANAGE'
   limit 20
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app_sec.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2. Auth profile changes are mirrored down
-- ---------------------------------------------------------------------------
create or replace function app_sec.handle_user_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.users u
     set email = nullif(lower(coalesce(new.email, '')), ''),
         phone = app_util.normalise_phone(new.phone),
         name  = coalesce(nullif(btrim(coalesce(new.raw_user_meta_data ->> 'name', '')), ''), u.name),
         avatar_url = coalesce(nullif(new.raw_user_meta_data ->> 'avatar_url',''), u.avatar_url),
         updated_at = now()
   where u.auth_user_id = new.id;

  if new.email is not null and old.email is distinct from new.email then
    perform (select app_util.audit_row('auth','UPDATE','users', u.id,
                       jsonb_build_object('email', old.email), jsonb_build_object('email', new.email),
                       u.showroom_id, u.id, 'email changed in Supabase Auth', 'WARNING')
                from public.users u where u.auth_user_id = new.id limit 1);
  end if;

  if new.banned_until is not null and old.banned_until is null then
    update public.users u set status = 'SUSPENDED', updated_at = now()
      where u.auth_user_id = new.id;
  elsif new.banned_until is null and old.banned_until is not null then
    update public.users u set status = 'ACTIVE', updated_at = now()
      where u.auth_user_id = new.id and u.status = 'SUSPENDED';
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update on auth.users
  for each row execute function app_sec.handle_user_update();

-- ---------------------------------------------------------------------------
-- 3. A deleted auth user must not orphan tenant data: soft-delete + audit
-- ---------------------------------------------------------------------------
create or replace function app_sec.handle_user_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.users u
     set status = 'INACTIVE', is_deleted = true, deleted_at = now(),
         email = u.email,   -- kept for audit trail; uniqueness is on active rows only
         updated_at = now()
   where u.auth_user_id = old.id;

  perform (select app_util.audit_row('auth','DELETE','users', u.id,
                   to_jsonb(u) - 'preferences', null,
                   u.showroom_id, u.id,
                   'auth.users row deleted; profile retained for financial audit trail', 'CRITICAL')
             from public.users u where u.auth_user_id = old.id limit 1);
  return old;
end;
$$;

drop trigger if exists on_auth_user_deleted on auth.users;
create trigger on_auth_user_deleted
  before delete on auth.users
  for each row execute function app_sec.handle_user_delete();

-- ---------------------------------------------------------------------------
-- 4. Session events (SS57) - the client calls these; it never writes the log
-- ---------------------------------------------------------------------------
create or replace function public.record_session_event(
  p_action text default 'LOGIN',
  p_platform text default null,
  p_app_version text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_user uuid := app_sec.current_user_id();
begin
  if v_user is null then
    return false;   -- pre-login event: Supabase Auth already logs that itself
  end if;
  if p_action not in ('LOGIN','LOGOUT','SESSION_REFRESH','APP_OPEN','APP_BACKGROUND') then
    perform app_util.fail('VAL001', 'unknown session event ' || p_action);
  end if;

  perform app_util.audit_row('auth',
          case when p_action = 'LOGIN'  then 'LOGIN'
               when p_action = 'LOGOUT' then 'LOGOUT'
               else 'UPDATE' end,
          'users', v_user, null,
          jsonb_build_object('event', p_action, 'platform', p_platform,
                             'appVersion', p_app_version,
                             'sessionId', nullif(current_setting('request.jwt.claim.session_id', true), '')),
          null, v_user, 'client reported session event',
          case when p_action = 'LOGOUT' then 'DEBUG' else 'INFO' end);

  update public.users u
     set last_active_at = now(), last_login_at = case when p_action in ('LOGIN','APP_OPEN')
                                                       then now() else u.last_login_at end
   where u.id = v_user;

  return true;
end;
$$;

-- Heartbeat + profile self-service.  register_user_profile is how a staff account
-- (created by an admin) claims its own record after first login.
create or replace function public.register_user_profile(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := app_sec.current_user_id();
        v_shr uuid := (p_payload ->> 'showroom_id')::uuid;
        v_pref jsonb;
begin
  if v_uid is null then perform app_util.fail('SEC001', 'not signed in'); end if;

  if p_payload ? 'showroom_id' and v_shr is null then
    perform app_util.fail('VAL001', 'unknown showroom id');
  end if;
  if v_shr is not null then
    perform app_sec.require_showroom_access(v_shr);
  end if;

  -- language / theme / notification switches are preferences, not profile
  -- columns: the same jsonb feeds get_my_preferences() and the login payload.
  select jsonb_strip_nulls(jsonb_build_object(
           'language',   nullif(p_payload ->> 'language',''),
           'themeMode',  nullif(p_payload ->> 'theme_mode',''),
           'notificationsEnabled', (p_payload ->> 'notifications_enabled')::boolean,
           'jobTitle',   nullif(p_payload ->> 'job_title',''),
           'profileCompleted', (p_payload ->> 'profile_completed')::boolean
         ))
    into v_pref;

  update public.users u
     set name          = coalesce(nullif(p_payload ->> 'name',''), u.name),
         phone         = coalesce(app_util.normalise_phone(p_payload ->> 'phone'), u.phone),
         avatar_url    = coalesce(nullif(p_payload ->> 'avatar_url',''), u.avatar_url),
         designation   = coalesce(nullif(p_payload ->> 'designation',''), u.designation),
         employee_code = coalesce(nullif(p_payload ->> 'employee_code',''), u.employee_code),
         showroom_id   = coalesce(v_shr, u.showroom_id),
         preferences   = coalesce(u.preferences, '{}'::jsonb) || coalesce(v_pref, '{}'::jsonb),
         last_active_at = now(),
         updated_at    = now(), updated_by = v_uid
   where u.id = v_uid;

  -- job_title is a preference label, designation is the HR field on the profile
  update public.users u
     set designation = coalesce(nullif(p_payload ->> 'job_title',''), u.designation)
   where u.id = v_uid and u.designation is null;

  return jsonb_build_object('ok', true, 'userId', v_uid,
                            'context', public.get_current_user_context());
end;
$$;

create or replace function public.refresh_my_session()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.get_current_user_context()
$$;

-- ---------------------------------------------------------------------------
-- 5. The public API surface.  Everything else in `public` is deliberately not
--    granted to anon/authenticated: it is reachable only from SQL with a
--    privileged role (migrations, tests, the service role).
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant  execute on all functions in schema public to service_role;

grant execute on function public.get_current_user_context() to anon, authenticated;
grant execute on function public.refresh_my_session() to authenticated;
grant execute on function public.record_session_event(text, text, text) to authenticated;
grant execute on function public.register_user_profile(jsonb) to authenticated;
grant execute on function public.bootstrap_super_admin(text, text, text) to service_role;

-- reference data (read via the tables' SELECT policies, written via these RPCs)
grant execute on function public.calculate_emi(numeric, numeric, integer, text) to authenticated;
grant execute on function public.calculate_loan_summary(numeric, numeric, integer, text) to authenticated;
grant execute on function public.generate_emi_schedule(uuid, date, boolean) to authenticated;
grant execute on function public.reverse_emi_schedule(uuid, integer, text) to authenticated;
grant execute on function public.create_emi_reminders(uuid, integer) to authenticated;

-- sales / billing / payments
grant execute on function public.create_sale_transaction(jsonb) to authenticated;
grant execute on function public.approve_sale(uuid, boolean, text) to authenticated;
grant execute on function public.cancel_sale(uuid, text, boolean) to authenticated;
grant execute on function public.record_payment(jsonb) to authenticated;
grant execute on function public.reverse_payment(uuid, text, date) to authenticated;
grant execute on function public.finalize_invoice(uuid) to authenticated;
grant execute on function public.recalc_invoice_header(uuid) to authenticated;
grant execute on function public.recalc_sale_header(uuid) to authenticated;

-- inventory / purchases / expenses
grant execute on function public.create_inventory_unit(jsonb) to authenticated;
grant execute on function public.adjust_inventory(uuid, text, text, numeric) to authenticated;
grant execute on function public.reserve_inventory(uuid, uuid, integer) to authenticated;
grant execute on function public.release_inventory(uuid, text) to authenticated;
grant execute on function public.transfer_inventory(uuid, uuid, date, date, numeric, text, text) to authenticated;
grant execute on function public.receive_stock_transfer(uuid, text, boolean) to authenticated;
grant execute on function public.create_purchase_transaction(jsonb) to authenticated;
grant execute on function public.approve_purchase(uuid, boolean, text) to authenticated;
grant execute on function public.receive_purchase(uuid, jsonb) to authenticated;
grant execute on function public.create_expense_transaction(jsonb) to authenticated;
grant execute on function public.decide_expense(uuid, boolean, text, boolean, text) to authenticated;
grant execute on function public.pay_expense(uuid, text, date, text) to authenticated;
grant execute on function public.recalc_purchase_header(uuid) to authenticated;
grant execute on function public.recalc_service_header(uuid) to authenticated;

-- service / warranty / reminders
grant execute on function public.create_service_booking(jsonb) to authenticated;
grant execute on function public.set_service_status(uuid, text, jsonb) to authenticated;
grant execute on function public.complete_service(uuid, jsonb, boolean) to authenticated;
grant execute on function public.create_service_reminders(uuid, date, integer, integer) to authenticated;
grant execute on function public.check_free_service_eligibility(uuid) to authenticated;
grant execute on function public.create_warranty_claim(jsonb) to authenticated;
grant execute on function public.decide_warranty_claim(uuid, text, numeric, text) to authenticated;
grant execute on function public.create_insurance_reminders(integer) to authenticated;
grant execute on function public.create_warranty_reminders(uuid, integer) to authenticated;
grant execute on function public.create_payment_reminders(integer) to authenticated;
grant execute on function public.enqueue_reminder(jsonb) to authenticated;
grant execute on function public.complete_reminder(uuid, text, text) to authenticated;
grant execute on function public.run_reminder_sweep(date) to authenticated;
grant execute on function public.refresh_emi_statuses(date) to authenticated;

-- notifications / documents
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
grant execute on function public.unread_notification_count() to authenticated;
grant execute on function public.push_notification(jsonb) to authenticated;
grant execute on function public.register_device_token(jsonb) to authenticated;
grant execute on function public.deactivate_device_token(text) to authenticated;
grant execute on function public.get_signed_url(text, text, integer) to authenticated;
grant execute on function public.get_signed_urls(jsonb, integer) to authenticated;

-- reporting / search / 360 views
grant execute on function public.global_search(text, integer) to authenticated;
grant execute on function public.get_dashboard_metrics(uuid, date) to authenticated;
grant execute on function public.get_customer_360(uuid) to authenticated;
grant execute on function public.get_vehicle_360(uuid) to authenticated;
grant execute on function public.get_invoice_print_payload(uuid) to authenticated;
grant execute on function public.get_trial_balance(uuid, date, date) to authenticated;
grant execute on function public.get_account_ledger(uuid, date, date, integer, integer) to authenticated;
grant execute on function public.get_profit_and_loss(uuid, date, date) to authenticated;
grant execute on function public.create_accounting_transaction(jsonb) to authenticated;
grant execute on function public.reverse_accounting_transaction(uuid, text) to authenticated;

-- offline sync (SS84)
grant execute on function public.recognise_sync_conflict(jsonb) to authenticated;
grant execute on function public.resolve_sync_conflict(uuid, text, text) to authenticated;
grant execute on function public.record_offline_operation(jsonb) to authenticated;
grant execute on function public.pull_changes(uuid, timestamptz, integer) to authenticated;

-- settings self-service
grant execute on function public.get_my_preferences() to authenticated;
grant execute on function public.set_my_preference(text, jsonb) to authenticated;
grant execute on function public.set_my_preferences(jsonb) to authenticated;
grant execute on function public.set_my_default_showroom(uuid) to authenticated;
grant execute on function public.reset_my_preferences() to authenticated;
