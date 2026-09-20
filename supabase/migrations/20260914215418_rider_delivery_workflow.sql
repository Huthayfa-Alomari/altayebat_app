-- Authenticated rider delivery workflow.
-- Adds rider-only task details/actions, live GPS, cash collection audit fields,
-- and admin performance reporting without exposing orders directly through RLS.

alter table public.orders
  add column if not exists rider_picked_up_at timestamptz,
  add column if not exists rider_started_delivery_at timestamptz,
  add column if not exists rider_delivered_at timestamptz,
  add column if not exists rider_cash_collected_at timestamptz,
  add column if not exists rider_cash_collected_amount numeric;

create index if not exists orders_driver_active_delivery_idx
  on public.orders(driver_id, status, created_at)
  where driver_id is not null;

create or replace function public.rider_my_delivery_tasks()
returns table(
  id uuid,
  status text,
  total numeric,
  payment_method text,
  payment_status text,
  address_snapshot jsonb,
  customer_name text,
  customer_phone text,
  created_at timestamptz,
  rider_picked_up_at timestamptz,
  rider_started_delivery_at timestamptz,
  rider_delivered_at timestamptz,
  cash_due numeric
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

  select d.id, d.store_id
    into v_driver_id, v_store_id
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
    c.name::text,
    c.phone::text,
    o.created_at,
    o.rider_picked_up_at,
    o.rider_started_delivery_at,
    o.rider_delivered_at,
    case
      when o.payment_method::text = 'cash'
       and coalesce(o.payment_status::text, '') <> 'paid'
        then o.total::numeric
      else 0::numeric
    end as cash_due
  from public.orders o
  left join public.customers c on c.id = o.customer_id
  where o.store_id = v_store_id
    and o.driver_id = v_driver_id
    and o.status in ('preparing', 'out_for_delivery')
  order by
    case when o.status::text = 'out_for_delivery' then 0 else 1 end,
    o.created_at asc;
end;
$$;

create or replace function public.rider_delivery_action(
  p_order_id uuid,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_driver public.drivers%rowtype;
  v_order public.orders%rowtype;
  v_action text := lower(coalesce(nullif(btrim(p_action), ''), ''));
  v_cash_due numeric := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select d.* into v_driver
  from public.drivers d
  where d.auth_user_id = v_uid
    and d.approval_status = 'approved'
    and d.is_active = true
  limit 1;

  if not found then
    raise exception 'RIDER_NOT_APPROVED' using errcode = '42501';
  end if;

  select o.* into v_order
  from public.orders o
  where o.id = p_order_id
    and o.store_id = v_driver.store_id
    and o.driver_id = v_driver.id
  limit 1
  for update;

  if not found then
    raise exception 'ORDER_NOT_ASSIGNED_TO_RIDER' using errcode = '42501';
  end if;

  if v_action = 'pickup' then
    if v_order.status::text not in ('preparing', 'out_for_delivery') then
      raise exception 'ORDER_NOT_READY_FOR_PICKUP' using errcode = '22023';
    end if;

    update public.orders
       set rider_picked_up_at = coalesce(rider_picked_up_at, now()),
           updated_at = now()
     where id = v_order.id;

  elsif v_action = 'start' then
    if v_order.status::text = 'out_for_delivery' then
      null;
    elsif v_order.status::text <> 'preparing' then
      raise exception 'ORDER_NOT_READY_FOR_DELIVERY' using errcode = '22023';
    end if;

    if v_order.payment_method::text in ('card', 'cliq')
       and coalesce(v_order.payment_status::text, '') <> 'paid' then
      raise exception 'PAYMENT_NOT_CONFIRMED' using errcode = '22023';
    end if;

    update public.orders
       set rider_picked_up_at = coalesce(rider_picked_up_at, now()),
           rider_started_delivery_at = coalesce(rider_started_delivery_at, now()),
           status = 'out_for_delivery',
           updated_at = now()
     where id = v_order.id;

  elsif v_action = 'complete' then
    if v_order.status::text = 'delivered' then
      return jsonb_build_object('ok', true, 'order_id', v_order.id, 'status', 'delivered');
    end if;

    if v_order.status::text <> 'out_for_delivery' then
      raise exception 'ORDER_NOT_OUT_FOR_DELIVERY' using errcode = '22023';
    end if;

    v_cash_due := case
      when v_order.payment_method::text = 'cash'
       and coalesce(v_order.payment_status::text, '') <> 'paid'
        then coalesce(v_order.total, 0)::numeric
      else 0::numeric
    end;

    update public.orders
       set status = 'delivered',
           rider_delivered_at = coalesce(rider_delivered_at, now()),
           rider_cash_collected_at = case
             when v_cash_due > 0 then coalesce(rider_cash_collected_at, now())
             else rider_cash_collected_at
           end,
           rider_cash_collected_amount = case
             when v_cash_due > 0 then coalesce(rider_cash_collected_amount, v_cash_due)
             else rider_cash_collected_amount
           end,
           updated_at = now()
     where id = v_order.id;

  else
    raise exception 'INVALID_RIDER_ACTION' using errcode = '22023';
  end if;

  update public.drivers
     set last_seen_at = now(),
         status_updated_at = now()
   where id = v_driver.id;

  select o.* into v_order from public.orders o where o.id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'order_id', v_order.id,
    'status', v_order.status,
    'rider_picked_up_at', v_order.rider_picked_up_at,
    'rider_started_delivery_at', v_order.rider_started_delivery_at,
    'rider_delivered_at', v_order.rider_delivered_at,
    'cash_collected_amount', v_order.rider_cash_collected_amount
  );
end;
$$;

create or replace function public.rider_push_location(
  p_order_id uuid,
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
  v_uid uuid := auth.uid();
  v_driver_id uuid;
  v_store_id uuid;
  v_order_status text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_lat is null or p_lat < -90 or p_lat > 90
     or p_lng is null or p_lng < -180 or p_lng > 180 then
    raise exception 'INVALID_COORDINATES' using errcode = '22023';
  end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 5000) then
    raise exception 'INVALID_ACCURACY' using errcode = '22023';
  end if;
  if p_speed_mps is not null and (p_speed_mps < 0 or p_speed_mps > 120) then
    raise exception 'INVALID_SPEED' using errcode = '22023';
  end if;
  if p_heading_deg is not null and (p_heading_deg < 0 or p_heading_deg >= 360) then
    raise exception 'INVALID_HEADING' using errcode = '22023';
  end if;

  select d.id, d.store_id
    into v_driver_id, v_store_id
  from public.drivers d
  where d.auth_user_id = v_uid
    and d.approval_status = 'approved'
    and d.is_active = true
  limit 1;

  if v_driver_id is null then
    raise exception 'RIDER_NOT_APPROVED' using errcode = '42501';
  end if;

  select o.status::text into v_order_status
  from public.orders o
  where o.id = p_order_id
    and o.store_id = v_store_id
    and o.driver_id = v_driver_id;

  if v_order_status is null then
    raise exception 'ORDER_NOT_ASSIGNED_TO_RIDER' using errcode = '42501';
  end if;
  if v_order_status <> 'out_for_delivery' then
    raise exception 'ORDER_NOT_OUT_FOR_DELIVERY' using errcode = '22023';
  end if;

  insert into public.driver_locations(
    driver_id, order_id, lat, lng,
    accuracy_m, speed_mps, heading_deg, recorded_at, updated_at
  ) values (
    v_driver_id, p_order_id, p_lat, p_lng,
    p_accuracy_m, p_speed_mps, p_heading_deg, now(), now()
  )
  on conflict(order_id) do update set
    driver_id = excluded.driver_id,
    lat = excluded.lat,
    lng = excluded.lng,
    accuracy_m = excluded.accuracy_m,
    speed_mps = excluded.speed_mps,
    heading_deg = excluded.heading_deg,
    recorded_at = excluded.recorded_at,
    updated_at = excluded.updated_at;

  update public.drivers
     set last_seen_at = now()
   where id = v_driver_id;

  return jsonb_build_object('ok', true, 'order_id', p_order_id, 'recorded_at', now());
end;
$$;

create or replace function public.admin_rider_performance(p_store_id uuid)
returns table(
  driver_id uuid,
  today_delivered bigint,
  week_delivered bigint,
  active_orders bigint,
  avg_delivery_minutes_today numeric,
  cash_collected_today numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Amman') at time zone 'Asia/Amman';
  v_week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Amman') at time zone 'Asia/Amman';
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return query
  select
    d.id as driver_id,
    count(o.id) filter (
      where o.status::text = 'delivered'
        and coalesce(o.rider_delivered_at, o.updated_at) >= v_day_start
    )::bigint as today_delivered,
    count(o.id) filter (
      where o.status::text = 'delivered'
        and coalesce(o.rider_delivered_at, o.updated_at) >= v_week_start
    )::bigint as week_delivered,
    count(o.id) filter (
      where o.status::text in ('preparing', 'out_for_delivery')
    )::bigint as active_orders,
    round(
      avg(
        greatest(
          0::numeric,
          extract(epoch from (
            coalesce(o.rider_delivered_at, o.updated_at)
            - coalesce(o.rider_started_delivery_at, o.created_at)
          ))::numeric / 60
        )
      ) filter (
        where o.status::text = 'delivered'
          and coalesce(o.rider_delivered_at, o.updated_at) >= v_day_start
      ),
      1
    ) as avg_delivery_minutes_today,
    coalesce(sum(o.rider_cash_collected_amount) filter (
      where o.rider_cash_collected_at >= v_day_start
    ), 0)::numeric as cash_collected_today
  from public.drivers d
  left join public.orders o
    on o.driver_id = d.id
   and o.store_id = d.store_id
  where d.store_id = p_store_id
  group by d.id;
end;
$$;

revoke all on function public.rider_my_delivery_tasks() from public, anon;
revoke all on function public.rider_delivery_action(uuid,text) from public, anon;
revoke all on function public.rider_push_location(uuid,numeric,numeric,numeric,numeric,numeric) from public, anon;
revoke all on function public.admin_rider_performance(uuid) from public, anon;

grant execute on function public.rider_my_delivery_tasks() to authenticated;
grant execute on function public.rider_delivery_action(uuid,text) to authenticated;
grant execute on function public.rider_push_location(uuid,numeric,numeric,numeric,numeric,numeric) to authenticated;
grant execute on function public.admin_rider_performance(uuid) to authenticated;
