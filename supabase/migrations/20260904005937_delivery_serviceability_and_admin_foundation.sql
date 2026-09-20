create table if not exists public.delivery_zones (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  city text,
  areas text[] not null default '{}'::text[],
  center_lat numeric(9,6),
  center_lng numeric(9,6),
  radius_km numeric(8,3),
  delivery_fee numeric(10,3) not null default 0,
  min_order numeric(10,3) not null default 0,
  eta_min_minutes integer not null default 25,
  eta_max_minutes integer not null default 60,
  priority integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint delivery_zones_fee_nonnegative check (delivery_fee >= 0),
  constraint delivery_zones_min_order_nonnegative check (min_order >= 0),
  constraint delivery_zones_eta_valid check (eta_min_minutes >= 0 and eta_max_minutes >= eta_min_minutes),
  constraint delivery_zones_radius_valid check (radius_km is null or radius_km > 0),
  constraint delivery_zones_lat_valid check (center_lat is null or (center_lat between -90 and 90)),
  constraint delivery_zones_lng_valid check (center_lng is null or (center_lng between -180 and 180)),
  constraint delivery_zones_geo_complete check (
    (center_lat is null and center_lng is null and radius_km is null)
    or (center_lat is not null and center_lng is not null and radius_km is not null)
  )
);

create index if not exists idx_delivery_zones_store_active_priority
  on public.delivery_zones(store_id,is_active,priority);

create table if not exists public.store_hours (
  store_id uuid not null references public.stores(id) on delete cascade,
  day_of_week smallint not null,
  open_time time,
  close_time time,
  is_closed boolean not null default false,
  closes_next_day boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(store_id,day_of_week),
  constraint store_hours_day_valid check (day_of_week between 0 and 6),
  constraint store_hours_times_valid check (
    is_closed = true or (open_time is not null and close_time is not null)
  )
);

alter table public.stores
  add column if not exists timezone text not null default 'Asia/Amman',
  add column if not exists accepts_orders boolean not null default true,
  add column if not exists prep_time_min_minutes integer not null default 10,
  add column if not exists prep_time_max_minutes integer not null default 30;

alter table public.addresses
  add column if not exists location_source text,
  add column if not exists location_accuracy_m numeric(10,2),
  add column if not exists updated_at timestamptz not null default now();

alter table public.orders
  add column if not exists delivery_zone_id uuid references public.delivery_zones(id) on delete set null,
  add column if not exists delivery_eta_min_minutes integer,
  add column if not exists delivery_eta_max_minutes integer,
  add column if not exists fulfillment_method text not null default 'delivery',
  add column if not exists address_snapshot jsonb;

create index if not exists idx_orders_delivery_zone on public.orders(delivery_zone_id);
create index if not exists idx_orders_store_created_status on public.orders(store_id,created_at desc,status);

alter table public.delivery_zones enable row level security;
alter table public.store_hours enable row level security;

drop policy if exists "Customers view active delivery zones" on public.delivery_zones;
create policy "Customers view active delivery zones"
on public.delivery_zones for select to authenticated
using (is_active = true);

drop policy if exists "Store admins manage delivery zones" on public.delivery_zones;
create policy "Store admins manage delivery zones"
on public.delivery_zones for all to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

drop policy if exists "Customers view store hours" on public.store_hours;
create policy "Customers view store hours"
on public.store_hours for select to authenticated
using (true);

drop policy if exists "Store admins manage store hours" on public.store_hours;
create policy "Store admins manage store hours"
on public.store_hours for all to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

grant select on public.delivery_zones, public.store_hours to authenticated;
grant insert,update,delete on public.delivery_zones, public.store_hours to authenticated;

create or replace function public.get_store_open_state(
  p_store_id uuid,
  p_at timestamptz default now()
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_store record;
  v_local timestamp;
  v_dow integer;
  v_time time;
  v_hours record;
  v_open boolean;
begin
  select s.id,s.name,s.is_active,s.accepts_orders,s.timezone,
         s.prep_time_min_minutes,s.prep_time_max_minutes
    into v_store
  from public.stores s
  where s.id=p_store_id;
  if not found then return jsonb_build_object('open',false,'reason','STORE_NOT_FOUND'); end if;
  if not coalesce(v_store.is_active,false) then return jsonb_build_object('open',false,'reason','STORE_INACTIVE'); end if;
  if not coalesce(v_store.accepts_orders,false) then return jsonb_build_object('open',false,'reason','ORDERS_PAUSED'); end if;

  v_local := p_at at time zone coalesce(nullif(v_store.timezone,''),'Asia/Amman');
  v_dow := extract(dow from v_local)::integer;
  v_time := v_local::time;

  select * into v_hours
  from public.store_hours h
  where h.store_id=p_store_id and h.day_of_week=v_dow;

  if not found then
    return jsonb_build_object(
      'open',true,'reason','NO_HOURS_CONFIGURED','timezone',v_store.timezone,
      'prep_time_min_minutes',v_store.prep_time_min_minutes,
      'prep_time_max_minutes',v_store.prep_time_max_minutes
    );
  end if;
  if v_hours.is_closed then
    return jsonb_build_object('open',false,'reason','CLOSED_TODAY','timezone',v_store.timezone);
  end if;

  if v_hours.closes_next_day then
    v_open := (v_time >= v_hours.open_time or v_time < v_hours.close_time);
  else
    v_open := (v_time >= v_hours.open_time and v_time < v_hours.close_time);
  end if;

  return jsonb_build_object(
    'open',v_open,
    'reason',case when v_open then 'OPEN' else 'OUTSIDE_HOURS' end,
    'timezone',v_store.timezone,
    'open_time',v_hours.open_time,
    'close_time',v_hours.close_time,
    'closes_next_day',v_hours.closes_next_day,
    'prep_time_min_minutes',v_store.prep_time_min_minutes,
    'prep_time_max_minutes',v_store.prep_time_max_minutes
  );
end;
$$;

create or replace function public.get_delivery_serviceability(
  p_store_id uuid,
  p_address_id uuid default null,
  p_lat numeric default null,
  p_lng numeric default null,
  p_city text default null,
  p_area text default null
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_store record;
  v_lat numeric := p_lat;
  v_lng numeric := p_lng;
  v_city text := nullif(btrim(p_city),'');
  v_area text := nullif(btrim(p_area),'');
  v_zone record;
  v_active_zone_count integer;
  v_distance double precision;
begin
  select s.id,s.delivery_fee,s.min_order,s.currency,s.is_active,s.accepts_orders
    into v_store
  from public.stores s where s.id=p_store_id;
  if not found or not coalesce(v_store.is_active,false) or not coalesce(v_store.accepts_orders,false) then
    return jsonb_build_object('serviceable',false,'reason','STORE_UNAVAILABLE');
  end if;

  if p_address_id is not null then
    if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
    select a.lat,a.lng,a.city,a.area
      into v_lat,v_lng,v_city,v_area
    from public.addresses a
    where a.id=p_address_id and a.customer_id=v_uid;
    if not found then raise exception 'INVALID_ADDRESS' using errcode='42501'; end if;
  end if;

  select count(*) into v_active_zone_count
  from public.delivery_zones z where z.store_id=p_store_id and z.is_active=true;

  if v_active_zone_count=0 then
    return jsonb_build_object(
      'serviceable',true,'reason','STORE_DEFAULT','zone_id',null,'zone_name',null,
      'delivery_fee',v_store.delivery_fee,'min_order',v_store.min_order,'currency',v_store.currency,
      'eta_min_minutes',null,'eta_max_minutes',null,'distance_km',null
    );
  end if;

  select q.*,q.distance_km into v_zone
  from (
    select z.*,
      case
        when v_lat is not null and v_lng is not null and z.center_lat is not null then
          6371.0 * 2.0 * asin(sqrt(
            power(sin(radians((z.center_lat::double precision-v_lat::double precision)/2.0)),2)
            + cos(radians(v_lat::double precision))*cos(radians(z.center_lat::double precision))
            * power(sin(radians((z.center_lng::double precision-v_lng::double precision)/2.0)),2)
          ))
        else null
      end as distance_km,
      case
        when v_lat is not null and v_lng is not null and z.center_lat is not null then 0
        else 1
      end as match_rank
    from public.delivery_zones z
    where z.store_id=p_store_id and z.is_active=true
      and (
        (
          v_lat is not null and v_lng is not null and z.center_lat is not null
          and 6371.0 * 2.0 * asin(sqrt(
            power(sin(radians((z.center_lat::double precision-v_lat::double precision)/2.0)),2)
            + cos(radians(v_lat::double precision))*cos(radians(z.center_lat::double precision))
            * power(sin(radians((z.center_lng::double precision-v_lng::double precision)/2.0)),2)
          )) <= z.radius_km::double precision
        )
        or (
          (z.city is null or lower(btrim(z.city))=lower(btrim(coalesce(v_city,''))))
          and (
            cardinality(z.areas)=0
            or exists(select 1 from unnest(z.areas) a where lower(btrim(a))=lower(btrim(coalesce(v_area,''))))
          )
        )
      )
  ) q
  order by q.match_rank asc,q.priority asc,q.distance_km asc nulls last,q.id
  limit 1;

  if not found then
    return jsonb_build_object('serviceable',false,'reason','OUTSIDE_DELIVERY_ZONES','currency',v_store.currency);
  end if;

  v_distance := v_zone.distance_km;
  return jsonb_build_object(
    'serviceable',true,'reason','ZONE_MATCH','zone_id',v_zone.id,'zone_name',v_zone.name,
    'delivery_fee',v_zone.delivery_fee,'min_order',v_zone.min_order,'currency',v_store.currency,
    'eta_min_minutes',v_zone.eta_min_minutes,'eta_max_minutes',v_zone.eta_max_minutes,
    'distance_km',case when v_distance is null then null else round(v_distance::numeric,2) end
  );
end;
$$;

create or replace function public.checkout_quote_v2(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid
) returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_item record;
  v_product record;
  v_subtotal numeric(12,3):=0;
  v_service jsonb;
  v_delivery numeric(12,3):=0;
  v_min_order numeric(12,3):=0;
  v_currency text:='JOD';
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_address_id is null then raise exception 'ADDRESS_REQUIRED' using errcode='22023'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART' using errcode='22023'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'TOO_MANY_ITEMS' using errcode='22023'; end if;

  v_service := public.get_delivery_serviceability(p_store_id,p_address_id,null,null,null,null);
  if coalesce((v_service->>'serviceable')::boolean,false)=false then
    return jsonb_build_object('serviceable',false,'reason',v_service->>'reason','items','[]'::jsonb);
  end if;
  v_delivery := coalesce((v_service->>'delivery_fee')::numeric,0);
  v_min_order := coalesce((v_service->>'min_order')::numeric,0);
  v_currency := coalesce(v_service->>'currency','JOD');

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 or v_item.quantity>99 then raise exception 'INVALID_ITEM'; end if;
    select p.id,p.name,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.is_available,p.unit,p.pack_size
      into v_product
    from public.products p where p.id=v_item.product_id and p.store_id=p_store_id;
    if not found or not coalesce(v_product.is_available,false) then raise exception 'PRODUCT_UNAVAILABLE:%',v_item.product_id; end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then raise exception 'INSUFFICIENT_STOCK:%',v_product.name; end if;
    if v_product.price is null or v_product.price<=0 then raise exception 'INVALID_PRICE:%',v_product.name; end if;
    v_subtotal:=v_subtotal+(v_product.price*v_item.quantity);
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'product_id',v_product.id,'name',v_product.name,'image_url',v_product.image_url,
      'quantity',v_item.quantity,'unit_price',v_product.price,'line_total',v_product.price*v_item.quantity,
      'compare_at_price',v_product.compare_at_price,'stock_qty',v_product.stock_qty,'unit',v_product.unit,'pack_size',v_product.pack_size
    ));
  end loop;

  return jsonb_build_object(
    'serviceable',true,'service',v_service,'items',v_items,'subtotal',v_subtotal,
    'delivery_fee',v_delivery,'discount',0,'total',v_subtotal+v_delivery,'currency',v_currency,
    'min_order',v_min_order,'meets_min_order',v_subtotal>=v_min_order,
    'amount_to_min_order',greatest(v_min_order-v_subtotal,0)
  );
end;
$$;

create or replace function public.admin_dashboard_summary(
  p_store_id uuid,
  p_from timestamptz default date_trunc('day',now()),
  p_to timestamptz default now()
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.is_store_admin(p_store_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select jsonb_build_object(
    'orders_count',count(*),
    'delivered_count',count(*) filter(where status='delivered'),
    'open_count',count(*) filter(where status not in ('delivered','cancelled')),
    'cancelled_count',count(*) filter(where status='cancelled'),
    'gross_order_value',coalesce(sum(total),0),
    'delivered_revenue',coalesce(sum(total) filter(where status='delivered'),0),
    'pending_payment_count',count(*) filter(where payment_status in ('pending','unpaid')),
    'card_orders',count(*) filter(where payment_method='card'),
    'cash_orders',count(*) filter(where payment_method='cash'),
    'cliq_orders',count(*) filter(where payment_method='cliq')
  ) into v_result
  from public.orders
  where store_id=p_store_id and created_at>=p_from and created_at<p_to;
  return v_result;
end;
$$;

create or replace function public.admin_low_stock(
  p_store_id uuid,
  p_limit integer default 100
) returns table(
  id uuid,name text,sku text,barcode text,stock_qty integer,low_stock_threshold integer,is_available boolean,image_url text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_store_admin(p_store_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  return query
  select p.id,p.name,p.sku,p.barcode,p.stock_qty,p.low_stock_threshold,p.is_available,p.image_url
  from public.products p
  where p.store_id=p_store_id
    and coalesce(p.stock_qty,0) <= coalesce(p.low_stock_threshold,5)
  order by p.stock_qty asc,p.name
  limit greatest(1,least(coalesce(p_limit,100),500));
end;
$$;

revoke all on function public.admin_dashboard_summary(uuid,timestamptz,timestamptz) from public,anon;
revoke all on function public.admin_low_stock(uuid,integer) from public,anon;
grant execute on function public.admin_dashboard_summary(uuid,timestamptz,timestamptz) to authenticated;
grant execute on function public.admin_low_stock(uuid,integer) to authenticated;
grant execute on function public.get_store_open_state(uuid,timestamptz) to authenticated;
grant execute on function public.get_delivery_serviceability(uuid,uuid,numeric,numeric,text,text) to authenticated;
grant execute on function public.checkout_quote_v2(uuid,jsonb,uuid) to authenticated;
