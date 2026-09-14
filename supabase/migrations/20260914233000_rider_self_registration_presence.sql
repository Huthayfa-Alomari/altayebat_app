-- Altayebat rider self-registration + presence v1
-- Adds phone-OTP rider accounts, admin approval, live availability and rider heartbeat.
-- Existing manually-created delivery drivers remain approved and usable.

alter table public.drivers
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null,
  add column if not exists approval_status text not null default 'approved',
  add column if not exists availability_status text not null default 'offline',
  add column if not exists registration_source text not null default 'admin',
  add column if not exists vehicle_type text,
  add column if not exists vehicle_plate text,
  add column if not exists last_seen_at timestamptz,
  add column if not exists status_updated_at timestamptz not null default now(),
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id) on delete set null;

-- Existing drivers were created by the store, so keep them approved.
update public.drivers
   set approval_status = coalesce(nullif(approval_status, ''), 'approved'),
       registration_source = coalesce(nullif(registration_source, ''), 'admin'),
       availability_status = coalesce(nullif(availability_status, ''), 'offline'),
       approved_at = case
         when coalesce(nullif(approval_status, ''), 'approved') = 'approved'
           then coalesce(approved_at, created_at, now())
         else approved_at
       end
 where true;

create unique index if not exists drivers_auth_user_unique_idx
  on public.drivers(auth_user_id)
  where auth_user_id is not null;

create index if not exists drivers_store_presence_idx
  on public.drivers(store_id, approval_status, is_active, availability_status, last_seen_at desc);

create index if not exists drivers_store_phone_idx
  on public.drivers(store_id, phone);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'drivers_approval_status_check'
      and conrelid = 'public.drivers'::regclass
  ) then
    alter table public.drivers
      add constraint drivers_approval_status_check
      check (approval_status in ('pending', 'approved', 'rejected'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'drivers_availability_status_check'
      and conrelid = 'public.drivers'::regclass
  ) then
    alter table public.drivers
      add constraint drivers_availability_status_check
      check (availability_status in ('offline', 'available', 'busy', 'break'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'drivers_registration_source_check'
      and conrelid = 'public.drivers'::regclass
  ) then
    alter table public.drivers
      add constraint drivers_registration_source_check
      check (registration_source in ('admin', 'self'));
  end if;
end $$;

create or replace function private.normalize_jo_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if v_digits ~ '^9627[0-9]{8}$' then
    return '+' || v_digits;
  end if;
  if v_digits ~ '^07[0-9]{8}$' then
    return '+962' || substr(v_digits, 2);
  end if;
  if v_digits ~ '^7[0-9]{8}$' then
    return '+962' || v_digits;
  end if;
  return null;
end;
$$;

revoke all on function private.normalize_jo_phone(text) from public, anon, authenticated;

create or replace function public.rider_register(
  p_store_id uuid,
  p_name text,
  p_vehicle_type text default null,
  p_vehicle_plate text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
  v_vehicle_type text := nullif(btrim(p_vehicle_type), '');
  v_vehicle_plate text := nullif(btrim(p_vehicle_plate), '');
  v_phone text;
  v_driver public.drivers%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'PHONE_AUTH_REQUIRED' using errcode = '42501';
  end if;

  if v_name is null or length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'INVALID_DRIVER_NAME' using errcode = '22023';
  end if;
  if v_vehicle_type is not null and length(v_vehicle_type) > 80 then
    raise exception 'INVALID_VEHICLE_TYPE' using errcode = '22023';
  end if;
  if v_vehicle_plate is not null and length(v_vehicle_plate) > 40 then
    raise exception 'INVALID_VEHICLE_PLATE' using errcode = '22023';
  end if;

  if not exists (select 1 from public.stores s where s.id = p_store_id) then
    raise exception 'STORE_NOT_FOUND' using errcode = '22023';
  end if;

  select private.normalize_jo_phone(u.phone)
    into v_phone
  from auth.users u
  where u.id = v_uid;

  if v_phone is null then
    raise exception 'PHONE_AUTH_REQUIRED' using errcode = '42501';
  end if;

  -- A pre-created driver can claim their record after verifying the same phone.
  select d.*
    into v_driver
  from public.drivers d
  where d.store_id = p_store_id
    and d.auth_user_id is null
    and private.normalize_jo_phone(d.phone) = v_phone
  order by d.created_at desc
  limit 1
  for update;

  if found then
    update public.drivers d
       set auth_user_id = v_uid,
           name = v_name,
           phone = v_phone,
           vehicle_type = coalesce(v_vehicle_type, d.vehicle_type),
           vehicle_plate = coalesce(v_vehicle_plate, d.vehicle_plate),
           registration_source = d.registration_source,
           status_updated_at = now()
     where d.id = v_driver.id
     returning d.* into v_driver;
  else
    select d.*
      into v_driver
    from public.drivers d
    where d.auth_user_id = v_uid
    limit 1
    for update;

    if found then
      if v_driver.store_id <> p_store_id then
        raise exception 'RIDER_ALREADY_LINKED_TO_ANOTHER_STORE' using errcode = '22023';
      end if;

      update public.drivers d
         set name = v_name,
             phone = v_phone,
             vehicle_type = v_vehicle_type,
             vehicle_plate = v_vehicle_plate,
             status_updated_at = now()
       where d.id = v_driver.id
       returning d.* into v_driver;
    else
      insert into public.drivers(
        store_id,
        name,
        phone,
        is_active,
        auth_user_id,
        approval_status,
        availability_status,
        registration_source,
        vehicle_type,
        vehicle_plate,
        status_updated_at
      ) values (
        p_store_id,
        v_name,
        v_phone,
        false,
        v_uid,
        'pending',
        'offline',
        'self',
        v_vehicle_type,
        v_vehicle_plate,
        now()
      )
      returning * into v_driver;
    end if;
  end if;

  return jsonb_build_object(
    'id', v_driver.id,
    'store_id', v_driver.store_id,
    'name', v_driver.name,
    'phone', v_driver.phone,
    'approval_status', v_driver.approval_status,
    'is_active', v_driver.is_active,
    'availability_status', v_driver.availability_status,
    'vehicle_type', v_driver.vehicle_type,
    'vehicle_plate', v_driver.vehicle_plate
  );
end;
$$;

create or replace function public.rider_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_driver public.drivers%rowtype;
  v_active_orders bigint := 0;
  v_effective_status text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select d.* into v_driver
  from public.drivers d
  where d.auth_user_id = v_uid
  limit 1;

  if not found then
    return null;
  end if;

  select count(*)::bigint into v_active_orders
  from public.orders o
  where o.store_id = v_driver.store_id
    and o.driver_id = v_driver.id
    and o.status in ('preparing', 'out_for_delivery');

  v_effective_status := case
    when v_driver.approval_status <> 'approved' or not coalesce(v_driver.is_active, false) then 'offline'
    when v_active_orders > 0 then 'busy'
    when v_driver.availability_status = 'offline' then 'offline'
    when v_driver.last_seen_at is null or v_driver.last_seen_at < now() - interval '2 minutes' then 'offline'
    else v_driver.availability_status
  end;

  return jsonb_build_object(
    'id', v_driver.id,
    'store_id', v_driver.store_id,
    'name', v_driver.name,
    'phone', v_driver.phone,
    'approval_status', v_driver.approval_status,
    'is_active', v_driver.is_active,
    'availability_status', v_driver.availability_status,
    'effective_status', v_effective_status,
    'vehicle_type', v_driver.vehicle_type,
    'vehicle_plate', v_driver.vehicle_plate,
    'last_seen_at', v_driver.last_seen_at,
    'active_orders', v_active_orders
  );
end;
$$;

create or replace function public.rider_set_availability(p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_status text := lower(coalesce(nullif(btrim(p_status), ''), 'offline'));
  v_driver public.drivers%rowtype;
  v_active_orders bigint := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if v_status not in ('available', 'break', 'offline') then
    raise exception 'INVALID_AVAILABILITY_STATUS' using errcode = '22023';
  end if;

  select d.* into v_driver
  from public.drivers d
  where d.auth_user_id = v_uid
  limit 1
  for update;

  if not found then
    raise exception 'RIDER_NOT_REGISTERED' using errcode = '42501';
  end if;
  if v_driver.approval_status <> 'approved' or not coalesce(v_driver.is_active, false) then
    raise exception 'RIDER_NOT_APPROVED' using errcode = '42501';
  end if;

  select count(*)::bigint into v_active_orders
  from public.orders o
  where o.store_id = v_driver.store_id
    and o.driver_id = v_driver.id
    and o.status in ('preparing', 'out_for_delivery');

  update public.drivers
     set availability_status = case when v_active_orders > 0 then 'busy' else v_status end,
         last_seen_at = now(),
         status_updated_at = now()
   where id = v_driver.id
   returning * into v_driver;

  return jsonb_build_object(
    'ok', true,
    'availability_status', v_driver.availability_status,
    'effective_status', case when v_active_orders > 0 then 'busy' else v_driver.availability_status end,
    'active_orders', v_active_orders,
    'last_seen_at', v_driver.last_seen_at
  );
end;
$$;

create or replace function public.rider_heartbeat()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_driver public.drivers%rowtype;
  v_active_orders bigint := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select d.* into v_driver
  from public.drivers d
  where d.auth_user_id = v_uid
  limit 1
  for update;

  if not found then
    raise exception 'RIDER_NOT_REGISTERED' using errcode = '42501';
  end if;

  select count(*)::bigint into v_active_orders
  from public.orders o
  where o.store_id = v_driver.store_id
    and o.driver_id = v_driver.id
    and o.status in ('preparing', 'out_for_delivery');

  update public.drivers
     set availability_status = case
           when v_active_orders > 0 then 'busy'
           when availability_status = 'busy' then 'available'
           else availability_status
         end,
         last_seen_at = now()
   where id = v_driver.id
   returning * into v_driver;

  return jsonb_build_object(
    'ok', true,
    'last_seen_at', v_driver.last_seen_at,
    'availability_status', v_driver.availability_status,
    'active_orders', v_active_orders
  );
end;
$$;

create or replace function public.rider_my_active_orders()
returns table(
  id uuid,
  status text,
  total numeric,
  payment_method text,
  payment_status text,
  address_snapshot jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_driver_id uuid;
  v_store_id uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select d.id, d.store_id into v_driver_id, v_store_id
  from public.drivers d
  where d.auth_user_id = v_uid
    and d.approval_status = 'approved'
    and d.is_active = true
  limit 1;

  if v_driver_id is null then
    return;
  end if;

  return query
  select
    o.id,
    o.status::text,
    o.total::numeric,
    o.payment_method::text,
    o.payment_status::text,
    coalesce(o.address_snapshot, '{}'::jsonb),
    o.created_at
  from public.orders o
  where o.store_id = v_store_id
    and o.driver_id = v_driver_id
    and o.status in ('preparing', 'out_for_delivery')
  order by o.created_at asc;
end;
$$;

create or replace function public.admin_list_riders(p_store_id uuid)
returns table(
  id uuid,
  name text,
  phone text,
  is_active boolean,
  approval_status text,
  availability_status text,
  effective_status text,
  registration_source text,
  vehicle_type text,
  vehicle_plate text,
  last_seen_at timestamptz,
  status_updated_at timestamptz,
  active_orders bigint,
  connected_account boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return query
  with rider_rows as (
    select
      d.*,
      count(o.id) filter (where o.status in ('preparing', 'out_for_delivery'))::bigint as active_orders_count
    from public.drivers d
    left join public.orders o
      on o.driver_id = d.id
     and o.store_id = d.store_id
    where d.store_id = p_store_id
    group by d.id
  )
  select
    r.id,
    r.name,
    r.phone,
    r.is_active,
    r.approval_status,
    r.availability_status,
    case
      when r.approval_status <> 'approved' or not coalesce(r.is_active, false) then 'offline'
      when r.active_orders_count > 0 then 'busy'
      when r.auth_user_id is null then 'offline'
      when r.availability_status = 'offline' then 'offline'
      when r.last_seen_at is null or r.last_seen_at < now() - interval '2 minutes' then 'offline'
      else r.availability_status
    end as effective_status,
    r.registration_source,
    r.vehicle_type,
    r.vehicle_plate,
    r.last_seen_at,
    r.status_updated_at,
    r.active_orders_count,
    (r.auth_user_id is not null) as connected_account,
    r.created_at
  from rider_rows r
  order by
    case r.approval_status when 'pending' then 0 when 'approved' then 1 else 2 end,
    case
      when r.active_orders_count > 0 then 0
      when r.availability_status = 'available' and r.last_seen_at >= now() - interval '2 minutes' then 1
      else 2
    end,
    r.created_at desc;
end;
$$;

create or replace function public.admin_review_rider(
  p_driver_id uuid,
  p_decision text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver public.drivers%rowtype;
  v_decision text := lower(coalesce(nullif(btrim(p_decision), ''), ''));
begin
  select d.* into v_driver
  from public.drivers d
  where d.id = p_driver_id
  limit 1
  for update;

  if not found or not private.is_store_admin(v_driver.store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_decision not in ('approved', 'rejected') then
    raise exception 'INVALID_REVIEW_DECISION' using errcode = '22023';
  end if;

  update public.drivers
     set approval_status = v_decision,
         is_active = (v_decision = 'approved'),
         availability_status = 'offline',
         approved_at = case when v_decision = 'approved' then now() else null end,
         approved_by = case when v_decision = 'approved' then auth.uid() else null end,
         status_updated_at = now()
   where id = p_driver_id
   returning * into v_driver;

  if v_decision = 'rejected' then
    update public.driver_tracking_sessions
       set revoked_at = coalesce(revoked_at, now())
     where driver_id = p_driver_id
       and revoked_at is null;
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_driver.id,
    'approval_status', v_driver.approval_status,
    'is_active', v_driver.is_active
  );
end;
$$;

-- Rider pages use authenticated phone sessions only. Underlying tables remain private.
revoke all on function public.rider_register(uuid,text,text,text) from public, anon;
revoke all on function public.rider_me() from public, anon;
revoke all on function public.rider_set_availability(text) from public, anon;
revoke all on function public.rider_heartbeat() from public, anon;
revoke all on function public.rider_my_active_orders() from public, anon;
revoke all on function public.admin_list_riders(uuid) from public, anon;
revoke all on function public.admin_review_rider(uuid,text) from public, anon;

grant execute on function public.rider_register(uuid,text,text,text) to authenticated;
grant execute on function public.rider_me() to authenticated;
grant execute on function public.rider_set_availability(text) to authenticated;
grant execute on function public.rider_heartbeat() to authenticated;
grant execute on function public.rider_my_active_orders() to authenticated;
grant execute on function public.admin_list_riders(uuid) to authenticated;
grant execute on function public.admin_review_rider(uuid,text) to authenticated;
