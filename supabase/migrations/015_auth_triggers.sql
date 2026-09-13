-- 015_auth_triggers.sql
-- Bridges auth.users -> public.users (spec section 83).
--
-- A signup creates the application profile automatically; the profile has no
-- role and no showroom until an administrator assigns them, so it grants no
-- access by itself.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_name text;
begin
  profile_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'name', ''),
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    split_part(coalesce(new.email, ''), '@', 1)
  );

  insert into public.users (auth_user_id, name, email, status)
  values (new.id, profile_name, coalesce(new.email, ''), 'active')
  on conflict (auth_user_id) do update
     set email = coalesce(excluded.email, public.users.email),
         updated_at = now();

  return new;
exception when others then
  -- Never block account creation because profile creation failed; the
  -- administrator can still create the profile from the Users screen.
  raise warning 'profile creation failed for %: %', new.id, sqlerrm;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Email changes in auth must not desync the profile.
create or replace function public.handle_auth_user_updated()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is distinct from old.email then
    update public.users
       set email = new.email, updated_at = now()
     where auth_user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update of email on auth.users
  for each row execute function public.handle_auth_user_updated();

-- Deactivating a profile must not leave a live auth session usable: the
-- client re-reads the profile after every token refresh and signs out when
-- the profile is gone or inactive (SessionController._loadProfile).
create or replace function public.enforce_active_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'active' and old.status = 'active' then
    insert into public.notifications
      (showroom_id, user_id, title, message, notification_type, is_read)
    values
      (new.showroom_id, new.id, 'Account disabled',
       'Your showroom access has been disabled. Contact your administrator.',
       'warning', false);
  end if;
  return new;
end;
$$;

drop trigger if exists users_enforce_active on public.users;
create trigger users_enforce_active
  after update of status on public.users
  for each row execute function public.enforce_active_profile();
