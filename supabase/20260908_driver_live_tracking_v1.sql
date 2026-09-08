-- Altayebat live driver tracking v1
-- Secure token-based driver access + realtime latest location.

alter table public.driver_locations
  add column if not exists accuracy_m numeric,
  add column if not exists speed_mps numeric,
  add column if not exists heading_deg numeric,
  add column if not exists recorded_at timestamptz not null default now();

create unique index if not exists driver_locations_one_per_order_idx
  on public.driver_locations(order_id);

create table if not exists public.driver_tracking_sessions (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  driver_id uuid not null references public.drivers(id) on delete cascade,
  token_hash bytea not null unique,
  created_by uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '18 hours'),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  constraint driver_tracking_sessions_expiry_check check (expires_at > created_at)
);

create index if not exists driver_tracking_sessions_order_idx
  on public.driver_tracking_sessions(order_id, created_at desc);
create index if not exists driver_tracking_sessions_driver_idx
  on public.driver_tracking_sessions(driver_id, created_at desc);
create unique index if not exists driver_tracking_sessions_one_active_order_idx
  on public.driver_tracking_sessions(order_id)
  where revoked_at is null;

alter table public.driver_tracking_sessions enable row level security;

revoke all on table public.driver_tracking_sessions from anon, authenticated;

create or replace function private.driver_session_by_token(p_token text)
returns table(
  session_id uuid,
  store_id uuid,
  order_id uuid,
  driver_id uuid,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.store_id, s.order_id, s.driver_id, s.expires_at
  from public.driver_tracking_sessions s
  join public.drivers d on d.id = s.driver_id and d.store_id = s.store_id and d.is_active = true
  join public.orders o on o.id = s.order_id and o.store_id = s.store_id and o.driver_id = s.driver_id
  where p_token is not null
    and p_token ~ '^[0-9a-fA-F]{64}$'
    and s.token_hash = extensions.digest(lower(p_token), 'sha256')
    and s.revoked_at is null
    and s.expires_at > now()
  limit 1;
$$;

revoke all on function private.driver_session_by_token(text) from public, anon, authenticated;

create or replace function public.admin_list_delivery_drivers(p_store_id uuid)
returns table(
  id uuid,
  name text,
  phone text,
  is_active boolean,
  active_orders bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  return query
  select d.id, d.name, d.phone, d.is_active,
         count(o.id) filter (where o.status in ('preparing','out_for_delivery'))::bigint as active_orders
  from public.drivers d
  left join public.orders o on o.driver_id=d.id and o.store_id=d.store_id
  where d.store_id=p_store_id
  group by d.id,d.name,d.phone,d.is_active,d.created_at
  order by d.is_active desc,d.created_at desc;
end;
$$;

create or replace function public.admin_create_delivery_driver(
  p_store_id uuid,
  p_name text,
  p_phone text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_name text := nullif(btrim(p_name),'');
  v_phone text := nullif(btrim(p_phone),'');
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if v_name is null or length(v_name) > 120 then
    raise exception 'INVALID_DRIVER_NAME' using errcode='22023';
  end if;
  if v_phone is not null and length(v_phone) > 32 then
    raise exception 'INVALID_DRIVER_PHONE' using errcode='22023';
  end if;

  insert into public.drivers(store_id,name,phone,is_active)
  values(p_store_id,v_name,v_phone,true)
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.admin_set_delivery_driver_active(
  p_driver_id uuid,
  p_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store_id uuid;
begin
  select d.store_id into v_store_id from public.drivers d where d.id=p_driver_id;
  if v_store_id is null or not private.is_store_admin(v_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  update public.drivers set is_active=coalesce(p_active,false) where id=p_driver_id;
  if not coalesce(p_active,false) then
    update public.driver_tracking_sessions
       set revoked_at=coalesce(revoked_at,now())
     where driver_id=p_driver_id and revoked_at is null;
  end if;
  return true;
end;
$$;

create or replace function public.admin_assign_delivery_driver(
  p_order_id uuid,
  p_driver_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_driver record;
begin
  select o.id,o.store_id,o.status,o.driver_id
    into v_order
  from public.orders o where o.id=p_order_id;

  if not found or not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if v_order.status in ('delivered','cancelled') then
    raise exception 'ORDER_CLOSED' using errcode='22023';
  end if;

  select d.id,d.name,d.phone,d.is_active
    into v_driver
  from public.drivers d
  where d.id=p_driver_id and d.store_id=v_order.store_id;

  if not found or not coalesce(v_driver.is_active,false) then
    raise exception 'DRIVER_UNAVAILABLE' using errcode='22023';
  end if;

  if v_order.driver_id is distinct from p_driver_id then
    update public.driver_tracking_sessions
       set revoked_at=coalesce(revoked_at,now())
     where order_id=p_order_id and revoked_at is null;
  end if;

  update public.orders
     set driver_id=p_driver_id, updated_at=now()
   where id=p_order_id;

  return jsonb_build_object(
    'ok',true,
    'order_id',p_order_id,
    'driver_id',v_driver.id,
    'driver_name',v_driver.name,
    'driver_phone',v_driver.phone
  );
end;
$$;

create or replace function public.admin_issue_driver_tracking_session(
  p_order_id uuid,
  p_driver_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_driver record;
  v_driver_id uuid;
  v_token text;
  v_expires_at timestamptz := now() + interval '18 hours';
begin
  select o.id,o.store_id,o.status,o.driver_id
    into v_order
  from public.orders o where o.id=p_order_id;

  if not found or not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if v_order.status in ('delivered','cancelled') then
    raise exception 'ORDER_CLOSED' using errcode='22023';
  end if;

  v_driver_id := coalesce(p_driver_id,v_order.driver_id);
  if v_driver_id is null then
    raise exception 'DRIVER_REQUIRED' using errcode='22023';
  end if;

  select d.id,d.name,d.phone,d.is_active
    into v_driver
  from public.drivers d
  where d.id=v_driver_id and d.store_id=v_order.store_id;

  if not found or not coalesce(v_driver.is_active,false) then
    raise exception 'DRIVER_UNAVAILABLE' using errcode='22023';
  end if;

  update public.orders
     set driver_id=v_driver_id, updated_at=now()
   where id=p_order_id;

  update public.driver_tracking_sessions
     set revoked_at=coalesce(revoked_at,now())
   where order_id=p_order_id and revoked_at is null;

  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');

  insert into public.driver_tracking_sessions(
    store_id,order_id,driver_id,token_hash,created_by,expires_at
  ) values(
    v_order.store_id,p_order_id,v_driver_id,
    extensions.digest(lower(v_token),'sha256'),auth.uid(),v_expires_at
  );

  return jsonb_build_object(
    'ok',true,
    'token',v_token,
    'expires_at',v_expires_at,
    'order_id',p_order_id,
    'driver_id',v_driver.id,
    'driver_name',v_driver.name,
    'driver_phone',v_driver.phone
  );
end;
$$;

create or replace function public.admin_revoke_driver_tracking(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store_id uuid;
begin
  select o.store_id into v_store_id from public.orders o where o.id=p_order_id;
  if v_store_id is null or not private.is_store_admin(v_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  update public.driver_tracking_sessions
     set revoked_at=coalesce(revoked_at,now())
   where order_id=p_order_id and revoked_at is null;

  return true;
end;
$$;

create or replace function public.driver_tracking_bootstrap(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_order record;
  v_driver record;
  v_customer record;
  v_location record;
begin
  select * into v_session from private.driver_session_by_token(p_token);
  if not found then
    raise exception 'INVALID_OR_EXPIRED_TRACKING_TOKEN' using errcode='42501';
  end if;

  select o.* into v_order from public.orders o where o.id=v_session.order_id;
  select d.id,d.name,d.phone into v_driver from public.drivers d where d.id=v_session.driver_id;
  select c.name,c.phone into v_customer from public.customers c where c.id=v_order.customer_id;
  select dl.lat,dl.lng,dl.accuracy_m,dl.speed_mps,dl.heading_deg,dl.recorded_at,dl.updated_at
    into v_location
  from public.driver_locations dl where dl.order_id=v_order.id;

  update public.driver_tracking_sessions
     set last_seen_at=now()
   where id=v_session.session_id;

  return jsonb_build_object(
    'session_id',v_session.session_id,
    'expires_at',v_session.expires_at,
    'order_id',v_order.id,
    'order_status',v_order.status,
    'total',v_order.total,
    'payment_method',v_order.payment_method,
    'payment_status',v_order.payment_status,
    'driver',jsonb_build_object('id',v_driver.id,'name',v_driver.name,'phone',v_driver.phone),
    'customer',jsonb_build_object('name',v_customer.name,'phone',v_customer.phone),
    'address',coalesce(v_order.address_snapshot,'{}'::jsonb),
    'last_location',case when v_location.lat is null then null else jsonb_build_object(
      'lat',v_location.lat,'lng',v_location.lng,'accuracy_m',v_location.accuracy_m,
      'speed_mps',v_location.speed_mps,'heading_deg',v_location.heading_deg,
      'recorded_at',v_location.recorded_at,'updated_at',v_location.updated_at
    ) end
  );
end;
$$;

create or replace function public.driver_tracking_push_location(
  p_token text,
  p_lat numeric,
  p_lng numeric,
  p_accuracy_m numeric default null,
  p_speed_mps numeric default null,
  p_heading_deg numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_status text;
begin
  if p_lat is null or p_lat < -90 or p_lat > 90 or p_lng is null or p_lng < -180 or p_lng > 180 then
    raise exception 'INVALID_COORDINATES' using errcode='22023';
  end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 5000) then
    raise exception 'INVALID_ACCURACY' using errcode='22023';
  end if;
  if p_speed_mps is not null and (p_speed_mps < 0 or p_speed_mps > 120) then
    raise exception 'INVALID_SPEED' using errcode='22023';
  end if;
  if p_heading_deg is not null and (p_heading_deg < 0 or p_heading_deg >= 360) then
    raise exception 'INVALID_HEADING' using errcode='22023';
  end if;

  select * into v_session from private.driver_session_by_token(p_token);
  if not found then
    raise exception 'INVALID_OR_EXPIRED_TRACKING_TOKEN' using errcode='42501';
  end if;

  select o.status into v_status from public.orders o where o.id=v_session.order_id;
  if v_status in ('delivered','cancelled') then
    raise exception 'ORDER_CLOSED' using errcode='22023';
  end if;

  insert into public.driver_locations(
    driver_id,order_id,lat,lng,accuracy_m,speed_mps,heading_deg,recorded_at,updated_at
  ) values(
    v_session.driver_id,v_session.order_id,p_lat,p_lng,p_accuracy_m,p_speed_mps,p_heading_deg,now(),now()
  )
  on conflict(order_id) do update set
    driver_id=excluded.driver_id,
    lat=excluded.lat,
    lng=excluded.lng,
    accuracy_m=excluded.accuracy_m,
    speed_mps=excluded.speed_mps,
    heading_deg=excluded.heading_deg,
    recorded_at=excluded.recorded_at,
    updated_at=excluded.updated_at;

  update public.driver_tracking_sessions
     set last_seen_at=now()
   where id=v_session.session_id;

  return jsonb_build_object('ok',true,'order_id',v_session.order_id,'recorded_at',now());
end;
$$;

create or replace function public.driver_tracking_start_delivery(
  p_token text,
  p_lat numeric default null,
  p_lng numeric default null,
  p_accuracy_m numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_order record;
begin
  select * into v_session from private.driver_session_by_token(p_token);
  if not found then
    raise exception 'INVALID_OR_EXPIRED_TRACKING_TOKEN' using errcode='42501';
  end if;

  select o.id,o.status,o.payment_method,o.payment_status into v_order
  from public.orders o where o.id=v_session.order_id for update;

  if v_order.status='pending' then
    raise exception 'ORDER_NOT_READY' using errcode='22023';
  end if;
  if v_order.status in ('delivered','cancelled') then
    raise exception 'ORDER_CLOSED' using errcode='22023';
  end if;
  if v_order.payment_method in ('card','cliq') and v_order.payment_status<>'paid' then
    raise exception 'PAYMENT_NOT_CONFIRMED' using errcode='22023';
  end if;

  if v_order.status='preparing' then
    update public.orders set status='out_for_delivery',updated_at=now() where id=v_order.id;
  end if;

  if p_lat is not null and p_lng is not null then
    if p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
      raise exception 'INVALID_COORDINATES' using errcode='22023';
    end if;
    insert into public.driver_locations(
      driver_id,order_id,lat,lng,accuracy_m,recorded_at,updated_at
    ) values(
      v_session.driver_id,v_session.order_id,p_lat,p_lng,p_accuracy_m,now(),now()
    )
    on conflict(order_id) do update set
      driver_id=excluded.driver_id,lat=excluded.lat,lng=excluded.lng,
      accuracy_m=excluded.accuracy_m,recorded_at=excluded.recorded_at,updated_at=excluded.updated_at;
  end if;

  update public.driver_tracking_sessions set last_seen_at=now() where id=v_session.session_id;

  return jsonb_build_object('ok',true,'order_id',v_session.order_id,'status','out_for_delivery');
end;
$$;

create or replace function public.driver_tracking_complete_delivery(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session record;
  v_status text;
begin
  select * into v_session from private.driver_session_by_token(p_token);
  if not found then
    raise exception 'INVALID_OR_EXPIRED_TRACKING_TOKEN' using errcode='42501';
  end if;

  select o.status into v_status from public.orders o where o.id=v_session.order_id for update;
  if v_status='delivered' then
    return jsonb_build_object('ok',true,'order_id',v_session.order_id,'status','delivered');
  end if;
  if v_status<>'out_for_delivery' then
    raise exception 'ORDER_NOT_OUT_FOR_DELIVERY' using errcode='22023';
  end if;

  update public.orders set status='delivered',updated_at=now() where id=v_session.order_id;
  update public.driver_tracking_sessions set revoked_at=now(),last_seen_at=now() where id=v_session.session_id;

  return jsonb_build_object('ok',true,'order_id',v_session.order_id,'status','delivered');
end;
$$;

-- Driver links are capability tokens: anon/authenticated may call only these RPCs,
-- while all underlying tables remain protected by RLS / revoked direct access.
revoke all on function public.admin_list_delivery_drivers(uuid) from public, anon;
revoke all on function public.admin_create_delivery_driver(uuid,text,text) from public, anon;
revoke all on function public.admin_set_delivery_driver_active(uuid,boolean) from public, anon;
revoke all on function public.admin_assign_delivery_driver(uuid,uuid) from public, anon;
revoke all on function public.admin_issue_driver_tracking_session(uuid,uuid) from public, anon;
revoke all on function public.admin_revoke_driver_tracking(uuid) from public, anon;

grant execute on function public.admin_list_delivery_drivers(uuid) to authenticated;
grant execute on function public.admin_create_delivery_driver(uuid,text,text) to authenticated;
grant execute on function public.admin_set_delivery_driver_active(uuid,boolean) to authenticated;
grant execute on function public.admin_assign_delivery_driver(uuid,uuid) to authenticated;
grant execute on function public.admin_issue_driver_tracking_session(uuid,uuid) to authenticated;
grant execute on function public.admin_revoke_driver_tracking(uuid) to authenticated;

revoke all on function public.driver_tracking_bootstrap(text) from public;
revoke all on function public.driver_tracking_push_location(text,numeric,numeric,numeric,numeric,numeric) from public;
revoke all on function public.driver_tracking_start_delivery(text,numeric,numeric,numeric) from public;
revoke all on function public.driver_tracking_complete_delivery(text) from public;

grant execute on function public.driver_tracking_bootstrap(text) to anon, authenticated;
grant execute on function public.driver_tracking_push_location(text,numeric,numeric,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.driver_tracking_start_delivery(text,numeric,numeric,numeric) to anon, authenticated;
grant execute on function public.driver_tracking_complete_delivery(text) to anon, authenticated;
