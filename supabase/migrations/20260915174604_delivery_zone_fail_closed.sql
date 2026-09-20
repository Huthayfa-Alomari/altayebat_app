create or replace function public.get_delivery_serviceability(
  p_store_id uuid,
  p_address_id uuid default null,
  p_lat numeric default null,
  p_lng numeric default null,
  p_city text default null,
  p_area text default null
)
returns jsonb
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
  from public.stores s
  where s.id=p_store_id;

  if not found or not coalesce(v_store.is_active,false) or not coalesce(v_store.accepts_orders,false) then
    return jsonb_build_object('serviceable',false,'reason','STORE_UNAVAILABLE');
  end if;

  if p_address_id is not null then
    if v_uid is null then
      raise exception 'AUTH_REQUIRED' using errcode='42501';
    end if;

    select a.lat,a.lng,a.city,a.area
      into v_lat,v_lng,v_city,v_area
    from public.addresses a
    where a.id=p_address_id and a.customer_id=v_uid;

    if not found then
      raise exception 'INVALID_ADDRESS' using errcode='42501';
    end if;
  end if;

  select count(*) into v_active_zone_count
  from public.delivery_zones z
  where z.store_id=p_store_id and z.is_active=true;

  if v_active_zone_count=0 then
    return jsonb_build_object(
      'serviceable',false,
      'reason','NO_DELIVERY_ZONE_CONFIGURED',
      'currency',v_store.currency
    );
  end if;

  if v_lat is null or v_lng is null then
    return jsonb_build_object(
      'serviceable',false,
      'reason','LOCATION_REQUIRED',
      'currency',v_store.currency
    );
  end if;

  select q.* into v_zone
  from (
    select z.*,
      6371.0 * 2.0 * asin(sqrt(
        power(sin(radians((z.center_lat::double precision-v_lat::double precision)/2.0)),2)
        + cos(radians(v_lat::double precision))*cos(radians(z.center_lat::double precision))
        * power(sin(radians((z.center_lng::double precision-v_lng::double precision)/2.0)),2)
      )) as distance_km
    from public.delivery_zones z
    where z.store_id=p_store_id
      and z.is_active=true
      and z.center_lat is not null
      and z.center_lng is not null
      and z.radius_km is not null
      and z.radius_km > 0
      and 6371.0 * 2.0 * asin(sqrt(
        power(sin(radians((z.center_lat::double precision-v_lat::double precision)/2.0)),2)
        + cos(radians(v_lat::double precision))*cos(radians(z.center_lat::double precision))
        * power(sin(radians((z.center_lng::double precision-v_lng::double precision)/2.0)),2)
      )) <= z.radius_km::double precision
  ) q
  order by q.priority asc,q.distance_km asc,q.id
  limit 1;

  if not found then
    return jsonb_build_object(
      'serviceable',false,
      'reason','OUTSIDE_DELIVERY_ZONES',
      'currency',v_store.currency
    );
  end if;

  v_distance := v_zone.distance_km;
  return jsonb_build_object(
    'serviceable',true,
    'reason','ZONE_MATCH',
    'zone_id',v_zone.id,
    'zone_name',v_zone.name,
    'delivery_fee',v_zone.delivery_fee,
    'min_order',v_zone.min_order,
    'currency',v_store.currency,
    'eta_min_minutes',v_zone.eta_min_minutes,
    'eta_max_minutes',v_zone.eta_max_minutes,
    'distance_km',round(v_distance::numeric,2)
  );
end;
$$;
