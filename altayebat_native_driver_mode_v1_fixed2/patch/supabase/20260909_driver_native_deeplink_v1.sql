create or replace function public.admin_issue_driver_tracking_session(
  p_order_id uuid,
  p_driver_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

  v_token := replace(gen_random_uuid()::text,'-','') ||
             replace(gen_random_uuid()::text,'-','');

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
    'driver_phone',v_driver.phone,
    'app_uri','altayebat://driver?token=' || v_token,
    'web_path','/driver?token=' || v_token
  );
end;
$function$;
