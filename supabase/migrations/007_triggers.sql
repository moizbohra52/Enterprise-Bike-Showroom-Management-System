-- 007_triggers.sql
-- Maintenance triggers only: `updated_at` stamping, audit trail and derived
-- vehicle bookkeeping. Business-critical money logic lives in explicit RPCs
-- (006), never hidden in triggers.

-- ------------------------------------------------------------ updated_at

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  for t in
    select c.relname
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and a.attname = 'updated_at'
      and not a.attisdropped
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      t || '_touch_updated_at', t
    );
    execute format(
      'create trigger %I before update on public.%I
       for each row execute function public.touch_updated_at()',
      t || '_touch_updated_at', t
    );
  end loop;
end;
$$;

-- ------------------------------------------------------------- audit log

-- Writes one audit_logs row per data change. `security definer` + a guard on
-- the audit table itself keeps RLS from recursing (see 009_rls.sql).
create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor       uuid;
  actor_name  text := '';
  room_id     uuid;
  action_name text;
  old_row     jsonb;
  new_row     jsonb;
begin
  select u.id, coalesce(u.name, '')
    into actor, actor_name
    from public.users u
   where u.auth_user_id = auth.uid();

  -- No matching profile (service_role, migrations, deleted user): record the
  -- change with an anonymous actor instead of failing the statement.
  actor_name := coalesce(actor_name, '');

  -- Audited tables do not all carry showroom_id (e.g. roles), so the tenant
  -- is read defensively from the row payload.
  old_row := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  new_row := case when tg_op = 'DELETE' then null else to_jsonb(new) end;

  if tg_op = 'INSERT' then
    action_name := 'create';
  elsif tg_op = 'UPDATE' then
    action_name := 'update';
  else
    action_name := 'delete';
  end if;

  room_id := nullif(coalesce(new_row ->> 'showroom_id',
                             old_row ->> 'showroom_id'), '')::uuid;

  insert into public.audit_logs
    (showroom_id, user_id, user_name, module, action, entity_type, entity_id,
     old_values, new_values, ip_address, user_agent)
  values
    (room_id,
     actor,
     actor_name,
     tg_table_name,
     action_name,
     tg_table_name,
     coalesce(nullif(new_row ->> 'id', '')::uuid,
              nullif(old_row ->> 'id', '')::uuid),
     old_row,
     new_row,
     null,
     current_setting('request.headers', true));

  return coalesce(new, old);
end;
$$;

do $$
declare
  t text;
  audited constant text[] := array[
    'sales', 'invoices', 'payments', 'inventory', 'customers',
    'customer_vehicles', 'expenses', 'purchases', 'loans', 'service_records',
    'users', 'roles'
  ];
begin
  foreach t in array audited loop
    execute format(
      'drop trigger if exists %I on public.%I', t || '_audit', t
    );
    execute format(
      'create trigger %I after insert or update or delete on public.%I
       for each row execute function public.write_audit_log()',
      t || '_audit', t
    );
  end loop;
end;
$$;

-- ------------------------------------------------- derived vehicle state

-- Keeps the vehicle's odometer and next-service pointers in step with the
-- latest completed job card.
create or replace function public.sync_vehicle_from_service()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('completed', 'delivered') and new.vehicle_id is not null then
    update public.customer_vehicles v
       set current_odometer = greatest(
             v.current_odometer,
             coalesce(new.odometer_out, new.odometer_in, 0)
           ),
           next_service_date = coalesce(new.next_service_date, v.next_service_date),
           next_service_km   = coalesce(new.next_service_km, v.next_service_km),
           updated_at        = now()
     where v.id = new.vehicle_id;
  end if;
  return new;
end;
$$;

drop trigger if exists service_records_sync_vehicle on public.service_records;
create trigger service_records_sync_vehicle
  after insert or update on public.service_records
  for each row execute function public.sync_vehicle_from_service();

-- Records the sign-in timestamp on the application profile.
create or replace function public.touch_last_login()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.users
     set last_login_at = now()
   where auth_user_id = auth.uid();
  return new;
end;
$$;

-- ------------------------------------------------ client-supplied numbers

-- The app creates warranty claims with only (warranty_id, description,
-- estimated_cost); the claim number is generated here.
create or replace function public.fill_claim_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.claim_number is null or new.claim_number = '' then
    new.claim_number := public.next_document_number(
      (select w.showroom_id from public.warranties w where w.id = new.warranty_id),
      'CLM'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists warranty_claims_fill_number on public.warranty_claims;
create trigger warranty_claims_fill_number
  before insert on public.warranty_claims
  for each row execute function public.fill_claim_number();
