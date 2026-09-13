-- 012_reminders.sql
-- Reminder generation. Both functions are idempotent: a reminder is only
-- created when no pending reminder of the same type exists for the same
-- reference, so they can be scheduled (pg_cron / app-triggered) freely.

create or replace function public.create_emi_reminders(
  p_days_ahead integer default 3
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  created integer := 0;
  row_emi public.emi_schedules%rowtype;
begin
  for row_emi in
    select e.*
      from public.emi_schedules e
      join public.loans l on l.id = e.loan_id
     where e.status in ('pending', 'partial')
       and l.status = 'active'
       and e.due_date between current_date
                          and current_date + greatest(p_days_ahead, 0)
  loop
    if exists (
      select 1 from public.reminders r
       where r.type = 'emi_due'
         and r.reference_id = row_emi.id
         and r.status in ('pending', 'sent')
    ) then
      continue;
    end if;

    insert into public.reminders
      (showroom_id, customer_id, vehicle_id, loan_id, type, title, message,
       reminder_date, priority, status, reference_id, reference_type)
    select l.showroom_id, l.customer_id, l.vehicle_id, l.id, 'emi_due',
           'EMI #' || row_emi.installment_no || ' due '
             || to_char(row_emi.due_date, 'DD Mon YYYY'),
           'EMI of ' || row_emi.emi_amount || ' is due on '
             || to_char(row_emi.due_date, 'DD Mon YYYY') || '.',
           row_emi.due_date,
           case when row_emi.due_date <= current_date then 'urgent'
                when row_emi.due_date <= current_date + 1 then 'high'
                else 'normal' end,
           'pending', row_emi.id, 'emi_schedule'
      from public.loans l
     where l.id = row_emi.loan_id;

    created := created + 1;
  end loop;

  -- Mark installments that slipped past their due date.
  update public.emi_schedules
     set status = 'overdue', updated_at = now()
   where status in ('pending', 'partial')
     and due_date < current_date;

  return created;
end;
$$;

create or replace function public.create_service_reminders(
  p_days_ahead integer default 7
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  created integer := 0;
begin
  -- Scheduled service (date or odometer threshold reached).
  insert into public.reminders
    (showroom_id, customer_id, vehicle_id, type, title, message,
     reminder_date, priority, status, reference_id, reference_type)
  select v.showroom_id, v.customer_id, v.id, 'service_due',
         'Service due for ' || coalesce(v.registration_number, 'vehicle'),
         'Periodic service is due on '
           || to_char(v.next_service_date, 'DD Mon YYYY') || '.',
         v.next_service_date, 'normal', 'pending', v.id, 'vehicle'
    from public.customer_vehicles v
   where v.status = 'active'
     and v.next_service_date is not null
     and v.next_service_date between current_date
                                 and current_date + greatest(p_days_ahead, 0)
     and not exists (
       select 1 from public.reminders r
        where r.type = 'service_due'
          and r.reference_id = v.id
          and r.status in ('pending', 'sent')
     );
  get diagnostics created = row_count;

  -- Insurance renewal.
  insert into public.reminders
    (showroom_id, customer_id, vehicle_id, type, title, message,
     reminder_date, priority, status, reference_id, reference_type)
  select coalesce(p.showroom_id, v.showroom_id), v.customer_id, v.id,
         'insurance_expiry',
         'Insurance expires ' || to_char(p.end_date, 'DD Mon YYYY'),
         'Policy ' || p.policy_number || ' expires on '
           || to_char(p.end_date, 'DD Mon YYYY') || '.',
         p.end_date - 30, 'high', 'pending', p.id, 'insurance_policy'
    from public.insurance_policies p
    join public.customer_vehicles v on v.id = p.vehicle_id
   where p.status = 'active'
     and p.end_date between current_date
                        and current_date + 30 + greatest(p_days_ahead, 0)
     and not exists (
       select 1 from public.reminders r
        where r.type = 'insurance_expiry'
          and r.reference_id = p.id
          and r.status in ('pending', 'sent')
     );

  -- Warranty expiry.
  insert into public.reminders
    (showroom_id, customer_id, vehicle_id, type, title, message,
     reminder_date, priority, status, reference_id, reference_type)
  select coalesce(w.showroom_id, v.showroom_id), v.customer_id, v.id,
         'warranty_expiry',
         'Warranty expires ' || to_char(w.end_date, 'DD Mon YYYY'),
         'Warranty ' || w.warranty_number || ' expires on '
           || to_char(w.end_date, 'DD Mon YYYY') || '.',
         w.end_date - 60, 'normal', 'pending', w.id, 'warranty'
    from public.warranties w
    join public.customer_vehicles v on v.id = w.vehicle_id
   where w.status = 'active'
     and w.end_date between current_date
                        and current_date + 60 + greatest(p_days_ahead, 0)
     and not exists (
       select 1 from public.reminders r
        where r.type = 'warranty_expiry'
          and r.reference_id = w.id
          and r.status in ('pending', 'sent')
     );

  -- Free services that are due and still unused.
  insert into public.reminders
    (showroom_id, customer_id, vehicle_id, type, title, message,
     reminder_date, priority, status, reference_id, reference_type)
  select coalesce(g.showroom_id, v.showroom_id), v.customer_id, v.id,
         'free_service',
         'Free service #' || g.service_number || ' due',
         'A free service is due for '
           || coalesce(v.registration_number, 'the vehicle') || '.',
         coalesce(g.end_date, current_date), 'normal', 'pending',
         g.id, 'free_service_grant'
    from public.free_service_grants g
    join public.customer_vehicles v on v.id = g.vehicle_id
   where g.status = 'active'
     and g.end_date is not null
     and g.end_date <= current_date + greatest(p_days_ahead, 0)
     and not exists (
       select 1 from public.reminders r
        where r.type = 'free_service'
          and r.reference_id = g.id
          and r.status in ('pending', 'sent')
     );

  -- Expire lapsed free services.
  update public.free_service_grants
     set status = 'expired'
   where status = 'active'
     and end_date is not null
     and end_date < current_date;

  update public.insurance_policies
     set status = 'expired', updated_at = now()
   where status = 'active' and end_date < current_date;

  update public.warranties
     set status = 'expired', updated_at = now()
   where status = 'active' and end_date < current_date;

  return created;
end;
$$;

grant execute on function public.create_emi_reminders(integer) to authenticated;
grant execute on function public.create_service_reminders(integer) to authenticated;
