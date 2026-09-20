create or replace function private.create_order_checkout_v2_atomic(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_payment_method text default 'cash',
  p_customer_note text default null,
  p_substitute_policy text default 'call_me'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_item record;
  v_product record;
  v_address record;
  v_subtotal numeric(12,3) := 0;
  v_payment text := lower(btrim(coalesce(p_payment_method,'cash')));
  v_payment_status text;
  v_sub_policy text := lower(btrim(coalesce(p_substitute_policy,'call_me')));
  v_service jsonb;
  v_open_state jsonb;
  v_delivery numeric(12,3) := 0;
  v_min_order numeric(12,3) := 0;
  v_zone_id uuid;
  v_eta_min integer;
  v_eta_max integer;
  v_address_snapshot jsonb;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_address_id is null then raise exception 'ADDRESS_REQUIRED' using errcode='22023'; end if;
  if v_payment not in ('cash','card','cliq') then raise exception 'INVALID_PAYMENT_METHOD' using errcode='22023'; end if;
  if v_sub_policy not in ('call_me','best_match','remove_item') then raise exception 'INVALID_SUBSTITUTE_POLICY' using errcode='22023'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART' using errcode='22023'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'TOO_MANY_ITEMS' using errcode='22023'; end if;
  if not exists(select 1 from public.customers c where c.id=v_user) then raise exception 'CUSTOMER_PROFILE_REQUIRED' using errcode='42501'; end if;

  select a.* into v_address
  from public.addresses a
  where a.id=p_address_id and a.customer_id=v_user;
  if not found then raise exception 'INVALID_ADDRESS' using errcode='42501'; end if;

  v_open_state := public.get_store_open_state(p_store_id,now());
  if coalesce((v_open_state->>'open')::boolean,false)=false then
    raise exception 'STORE_CLOSED:%',coalesce(v_open_state->>'reason','UNKNOWN');
  end if;

  v_service := public.get_delivery_serviceability(p_store_id,p_address_id,null,null,null,null);
  if coalesce((v_service->>'serviceable')::boolean,false)=false then
    raise exception 'OUTSIDE_DELIVERY_ZONE';
  end if;

  v_delivery := coalesce((v_service->>'delivery_fee')::numeric,0);
  v_min_order := coalesce((v_service->>'min_order')::numeric,0);
  v_zone_id := nullif(v_service->>'zone_id','')::uuid;
  v_eta_min := nullif(v_service->>'eta_min_minutes','')::integer;
  v_eta_max := nullif(v_service->>'eta_max_minutes','')::integer;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 or v_item.quantity>99 then
      raise exception 'INVALID_ITEM' using errcode='22023';
    end if;
    select p.id,p.name,p.price,p.stock_qty,p.is_available into v_product
    from public.products p
    where p.id=v_item.product_id and p.store_id=p_store_id
    for update;
    if not found or not coalesce(v_product.is_available,false) then raise exception 'PRODUCT_UNAVAILABLE:%',v_item.product_id; end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then raise exception 'INSUFFICIENT_STOCK:%',v_product.name; end if;
    if v_product.price is null or v_product.price<=0 then raise exception 'INVALID_PRICE:%',v_product.name; end if;
    v_subtotal := v_subtotal + (v_product.price*v_item.quantity);
  end loop;

  if v_subtotal<v_min_order then raise exception 'MIN_ORDER:%',v_min_order; end if;
  v_payment_status := case when v_payment='cash' then 'unpaid' else 'pending' end;

  v_address_snapshot := jsonb_build_object(
    'id',v_address.id,'label',v_address.label,'address_text',v_address.address_text,
    'city',v_address.city,'area',v_address.area,'street',v_address.street,
    'building',v_address.building,'floor',v_address.floor,'notes',v_address.notes,
    'lat',v_address.lat,'lng',v_address.lng
  );

  insert into public.orders(
    store_id,customer_id,address_id,status,payment_method,payment_status,
    subtotal,delivery_fee,discount,total,customer_note,substitute_policy,
    delivery_zone_id,delivery_eta_min_minutes,delivery_eta_max_minutes,
    fulfillment_method,address_snapshot
  ) values(
    p_store_id,v_user,p_address_id,'pending',v_payment,v_payment_status,
    v_subtotal,v_delivery,0,v_subtotal+v_delivery,nullif(btrim(p_customer_note),''),v_sub_policy,
    v_zone_id,v_eta_min,v_eta_max,'delivery',v_address_snapshot
  ) returning id into v_order;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,subtotal)
    select v_order,p.id,p.name,v_item.quantity,p.price,p.price*v_item.quantity
    from public.products p where p.id=v_item.product_id and p.store_id=p_store_id;

    update public.products
    set stock_qty=stock_qty-v_item.quantity,
        is_available=case when stock_qty-v_item.quantity<=0 then false else is_available end,
        updated_at=now()
    where id=v_item.product_id and store_id=p_store_id and stock_qty>=v_item.quantity;
    if not found then raise exception 'STOCK_CHANGED:%',v_item.product_id; end if;
  end loop;

  insert into public.order_status_history(order_id,status,changed_by)
  values(v_order,'pending',v_user);
  return v_order;
end;
$$;

revoke all on function private.create_order_checkout_v2_atomic(uuid,jsonb,uuid,text,text,text) from public,anon,authenticated;

create or replace function public.create_order_checkout_v2(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_payment_method text default 'cash',
  p_customer_note text default null,
  p_substitute_policy text default 'call_me'
) returns uuid
language sql
set search_path = ''
as $$
  select private.create_order_checkout_v2_atomic(
    p_store_id,p_items,p_address_id,p_payment_method,p_customer_note,p_substitute_policy
  );
$$;

revoke all on function public.create_order_checkout_v2(uuid,jsonb,uuid,text,text,text) from public,anon;
grant execute on function public.create_order_checkout_v2(uuid,jsonb,uuid,text,text,text) to authenticated;
