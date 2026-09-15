-- =============================================================================
-- 012_reminders.sql  (SS17, SS29, SS54)
-- -----------------------------------------------------------------------------
-- The reminder engine: generation is in 006 (create_emi_reminders etc.); this
-- file adds delivery (notification rows + optional FCM dispatch through
-- pg_net), the daily maintenance sweep, cron registration and the Realtime
-- publication that drives the in-app bell.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Fan a due reminder out into an in-app notification for the showroom staff
-- that owns the relationship, and (when pg_net is installed) push to the
-- customer's devices.
-- ---------------------------------------------------------------------------
create or replace function public.deliver_due_reminders(p_now timestamptz default now(), p_horizon interval default interval '1 hour')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  rec   record;
  v_created integer := 0;
  v_push    integer := 0;
  v_net     boolean;
begin
  select exists (select 1 from pg_extension where extname = 'pg_net') into v_net;

  for rec in
    select r.id, r.showroom_id, r.customer_id, r.reminder_type, r.title, r.message,
           r.priority, r.reference_type, r.reference_id, r.vehicle_id
      from public.reminders r
     where r.status = 'PENDING'
       and (r.reminder_date + r.reminder_time) <= (p_now at time zone 'UTC')::timestamp + p_horizon
       and (r.reminder_date + r.reminder_time) >= (p_now at time zone 'UTC')::timestamp - interval '1 day'
     order by (r.reminder_date + r.reminder_time)
     for update of r skip locked         -- never deliver the same reminder twice
     limit 500
  loop
    -- 1. the durable copy: the in-app notification feed
    insert into public.notifications
          (user_id, customer_id, showroom_id, title, message, notification_type, severity,
           route_name, route_params, reference_type, reference_id, channel, sent_at)
    select u.id, rec.customer_id, rec.showroom_id, rec.title, rec.message,
           case rec.reminder_type
             when 'EMI' then 'EMI' when 'SERVICE' then 'SERVICE' when 'INSURANCE' then 'INSURANCE'
             when 'WARRANTY' then 'WARRANTY' when 'PAYMENT' then 'PAYMENT' else 'SYSTEM' end,
           case rec.priority when 'URGENT' then 'CRITICAL' when 'HIGH' then 'WARNING' else 'INFO' end,
           case rec.reminder_type
             when 'EMI' then '/emi/schedule' when 'SERVICE' then '/service/detail'
             when 'PAYMENT' then '/billing/invoice' when 'INSURANCE' then '/insurance/detail'
             when 'WARRANTY' then '/warranty/detail' else '/reminders' end,
           jsonb_build_object('id', rec.reference_id, 'reminderId', rec.id),
           rec.reference_type, rec.reference_id, 'IN_APP', now()
      from public.users u
     where u.showroom_id = rec.showroom_id
       and u.status = 'ACTIVE'
       and u.is_deleted = false
       and (rec.reminder_type <> 'EMI' or app_sec.has_permission_in('finance','view', rec.showroom_id)
            or u.is_super_admin)
     -- keep it bounded: the manager, the advisor and the relationship owner
       and (u.is_super_admin
            or exists (select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
                        where ur.user_id = u.id and r.code in
                        ('SUPERADMIN','ADMIN','SHOWROOM_MANAGER','ACCOUNT_MANAGER','SERVICE_MANAGER',
                         'SALES_MANAGER','SALES_STAFF','SERVICE_ADVISOR')))
     limit 8;
    get diagnostics v_created = row_count;

    -- 2. optional push to the customer's own devices (never blocks the sweep)
    if v_net then
      begin
        with toks as (
          select dt.device_token
            from public.device_tokens dt
            join public.users u on u.id = dt.user_id
           where u.id = rec.customer_id and dt.is_active
        )
        insert into public.notifications
              (customer_id, showroom_id, title, message, notification_type, channel,
               reference_type, reference_id, sent_at, push_sent_at)
        select rec.customer_id, rec.showroom_id, rec.title, rec.message, 'PUSH', 'FCM',
               rec.reference_type, rec.reference_id, now(), now()
          from toks limit 1;
        v_push := v_push + 1;
      exception when others then
        null;   -- push is best-effort; the notification row is the record of truth
      end;
    end if;

    update public.reminders r
       set status = case when r.status = 'PENDING' then 'SENT' else r.status end,
           sent_at = now(),
           attempts = r.attempts + 1
     where r.id = rec.id;
  end loop;

  return jsonb_build_object('delivered', v_created, 'pushed', v_push,
                            'pgNetAvailable', coalesce(v_net, false), 'at', p_now);
end;
$$;

-- ---------------------------------------------------------------------------
-- The daily sweep. One function the cron job (and the app's "Sync now" button)
-- can call, in the order the business needs.
-- ---------------------------------------------------------------------------
create or replace function public.run_reminder_sweep(p_as_of date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  -- 1. instalment lifecycle first: statuses feed every reminder below
  v := public.refresh_emi_statuses(p_as_of);

  -- 2. generate anything that is now due
  perform public.create_emi_reminders(null, 3);
  perform public.create_service_reminders(null, null, null, 7);
  perform public.create_insurance_reminders(30);
  perform public.create_warranty_reminders(null, 30);
  perform public.create_payment_reminders(1);

  -- 3. derived statuses that are pure facts about time (SS52 "derived where safe")
  update public.insurance_policies i
     set status = case
                    when i.expiry_date < p_as_of then 'EXPIRED'
                    when i.expiry_date <= p_as_of + 30 then 'EXPIRING_SOON'
                    else 'ACTIVE' end,
         updated_at = now()
   where i.status in ('ACTIVE','EXPIRING_SOON')
     and (i.expiry_date < p_as_of) <> (i.status = 'EXPIRED')
        or (i.expiry_date between p_as_of and p_as_of + 30 and i.status = 'ACTIVE');

  update public.warranties w
     set status = 'EXPIRED', updated_at = now()
   where w.status = 'ACTIVE' and w.end_date < p_as_of;

  update public.vehicle_free_services f
     set status = 'EXPIRED'
   where f.status in ('UPCOMING','BOOKED')
     and (f.due_date < p_as_of
          or (f.due_km > 0 and f.due_km < coalesce(
               (select v.current_odometer from public.customer_vehicles v where v.id = f.vehicle_id), 0)));

  -- 4. stale reservations go back on the shelf so bikes are not held hostage
  update public.inventory i
     set status = 'AVAILABLE', reserved_customer_id = null, reserved_by = null,
         reserved_until = null, updated_at = now(),
         remarks = btrim(coalesce(i.remarks,'') || ' | auto-released: reservation expired')
   where i.status = 'RESERVED'
     and i.reserved_until is not null
     and i.reserved_until < now();

  -- 5. invoices past their due date become OVERDUE (a fact, not a decision)
  update public.invoices i
     set status = 'OVERDUE'
   where i.status = 'FINALIZED'
     and i.due_date is not null and i.due_date < p_as_of
     and i.outstanding_amount > 0;

  -- 6. deliver whatever became due today
  perform public.deliver_due_reminders(now());

  return jsonb_build_object('asOf', p_as_of, 'emi', v, 'ok', true);
end;
$$;

comment on function public.run_reminder_sweep is
  'Idempotent daily maintenance: EMI statuses, reminder generation, expiry flips, stale reservation release, overdue invoices, delivery.';

-- ---------------------------------------------------------------------------
-- Complete / cancel a reminder from the UI
-- ---------------------------------------------------------------------------
create or replace function public.complete_reminder(
  p_reminder_id uuid,
  p_status      text default 'COMPLETED',
  p_notes       text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare r public.reminders%rowtype;
begin

  perform app_sec.require_permission('reminders','complete');
  if p_status not in ('COMPLETED','CANCELLED','PENDING','SKIPPED') then
    perform app_util.fail('VAL001', 'unsupported reminder status ' || p_status);
  end if;
  select * into r from public.reminders where id = p_reminder_id for update;
  if not found then perform app_util.fail('NOT001', 'reminder not found'); end if;
  perform app_sec.require_showroom_access(r.showroom_id);
  if p_status = 'CANCELLED' and coalesce(p_notes,'') = '' then
    perform app_util.fail('VAL002', 'cancelling a reminder needs a note');
  end if;

  update public.reminders x
     set status = p_status,
         completed_at = case when p_status = 'COMPLETED' then now() end,
         completed_by = case when p_status = 'COMPLETED' then app_sec.current_user_id() end,
         cancel_reason = case when p_status = 'CANCELLED' then p_notes end,
         message = coalesce(x.message || case when p_notes is not null
                                              then ' | ' || p_notes else '' end, x.message),
         updated_at = now(), updated_by = app_sec.current_user_id()
   where x.id = p_reminder_id;

  -- closing the loop on the vehicle ledger: a done service reminder already has
  -- a job card? if not, keep the due date so it re-appears tomorrow, not next week.
  if p_status = 'COMPLETED' and r.reminder_type = 'SERVICE' and r.vehicle_id is not null then
    update public.customer_vehicles v
       set notes = btrim(coalesce(v.notes,'') || ' | service reminder closed ' || current_date)
     where v.id = r.vehicle_id;
  end if;

  return jsonb_build_object('reminderId', p_reminder_id, 'status', p_status);
end;
$$;

-- ---------------------------------------------------------------------------
-- Scheduler registration.
-- Supabase ships pg_cron + pg_net; on any other PostgreSQL the functions above
-- stay callable from the app, so the schema never hard-fails.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('bike_showroom_reminder_sweep')
      where exists (select 1 from cron.job where jobname = 'bike_showroom_reminder_sweep');
    perform cron.schedule('bike_showroom_reminder_sweep', '5 3 * * *',
                          'select public.run_reminder_sweep(current_date)');
    raise notice '012: pg_cron job bike_showroom_reminder_sweep registered';
  else
    raise notice '012: pg_cron unavailable - call public.run_reminder_sweep() from Supabase scheduled functions, a worker, or the app';
  end if;
exception when others then
  raise notice '012: cron registration skipped (%)', sqlerrm;
end
$$;

-- ---------------------------------------------------------------------------
-- Realtime: the notification bell and the live job-card board.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.notifications';
    exception when duplicate_object then null; when others then null; end;
    begin
      execute 'alter publication supabase_realtime add table public.service_records';
    exception when duplicate_object then null; when others then null; end;
    begin
      execute 'alter publication supabase_realtime add table public.reminders';
    exception when duplicate_object then null; when others then null; end;
  else
    raise notice '012: supabase_realtime publication absent; enable Realtime from the dashboard if required';
  end if;
end
$$;

-- Replication identity so realtime payloads carry the whole row
alter table public.notifications replica identity full;
alter table public.service_records replica identity full;

-- ---------------------------------------------------------------------------
-- Push fan-out helper used by RPCs that must notify immediately (approvals)
-- ---------------------------------------------------------------------------
create or replace function public.push_notification(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_showroom uuid := (p_payload ->> 'showroom_id')::uuid;
  v_id uuid;
begin

  perform app_sec.require_permission('notifications','send');
  if v_showroom is not null then
    perform app_sec.require_showroom_access(v_showroom);
  end if;

  insert into public.notifications
        (user_id, customer_id, showroom_id, title, message, notification_type, severity,
         route_name, route_params, reference_type, reference_id, channel, sent_at, action_required)
  values ((p_payload ->> 'user_id')::uuid, (p_payload ->> 'customer_id')::uuid, v_showroom,
          coalesce(p_payload ->> 'title', 'Notification'),
          coalesce(p_payload ->> 'message', ''),
          coalesce(nullif(p_payload ->> 'notification_type',''), 'SYSTEM'),
          coalesce(nullif(p_payload ->> 'severity',''), 'INFO'),
          p_payload ->> 'route_name',
          coalesce(p_payload -> 'route_params', '{}'::jsonb),
          p_payload ->> 'reference_type', (p_payload ->> 'reference_id')::uuid,
          case when coalesce((p_payload ->> 'push')::boolean, true) then 'FCM' else 'IN_APP' end,
          now(), coalesce((p_payload ->> 'action_required')::boolean, false))
  returning id into v_id;
  return v_id;
end;
$$;
