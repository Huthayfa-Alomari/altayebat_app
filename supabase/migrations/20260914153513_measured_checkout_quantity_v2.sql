create or replace function public.checkout_quote_v2(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid
)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_item record;
  v_product record;
  v_subtotal numeric(12,3):=0;
  v_service jsonb;
  v_delivery numeric(12,3):=0;
  v_min_order numeric(12,3):=0;
  v_currency text:='JOD';
  v_items jsonb:='[]'::jsonb;
  v_min_qty integer;
  v_qty_step integer;
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
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 then
      raise exception 'INVALID_ITEM' using errcode='22023';
    end if;

    select p.id,p.name,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.is_available,
           p.unit,p.pack_size,p.sale_type,p.base_unit,p.inventory_scale,p.price_per_unit,
           p.min_qty,p.qty_step,p.allow_amount_purchase
      into v_product
    from public.products p
    where p.id=v_item.product_id and p.store_id=p_store_id;

    if not found or not coalesce(v_product.is_available,false) then
      raise exception 'PRODUCT_UNAVAILABLE:%',v_item.product_id;
    end if;

    v_min_qty := greatest(coalesce(v_product.min_qty,1),1);
    v_qty_step := greatest(coalesce(v_product.qty_step,1),1);

    if v_item.quantity < v_min_qty then
      raise exception 'MIN_QTY:%:%',v_product.name,v_min_qty using errcode='22023';
    end if;
    if mod(v_item.quantity-v_min_qty,v_qty_step)<>0 then
      raise exception 'INVALID_QTY_STEP:%:%',v_product.name,v_qty_step using errcode='22023';
    end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then
      raise exception 'INSUFFICIENT_STOCK:%',v_product.name;
    end if;
    if v_product.price is null or v_product.price<=0 then
      raise exception 'INVALID_PRICE:%',v_product.name;
    end if;

    v_subtotal:=v_subtotal+(v_product.price*v_item.quantity);
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'product_id',v_product.id,
      'name',v_product.name,
      'image_url',v_product.image_url,
      'quantity',v_item.quantity,
      'unit_price',v_product.price,
      'line_total',v_product.price*v_item.quantity,
      'compare_at_price',v_product.compare_at_price,
      'stock_qty',v_product.stock_qty,
      'unit',v_product.unit,
      'pack_size',v_product.pack_size,
      'sale_type',coalesce(v_product.sale_type,'piece'),
      'base_unit',coalesce(v_product.base_unit,'piece'),
      'inventory_scale',greatest(coalesce(v_product.inventory_scale,1),1),
      'display_unit_price',coalesce(v_product.price_per_unit,v_product.price),
      'min_qty',v_min_qty,
      'qty_step',v_qty_step
    ));
  end loop;

  return jsonb_build_object(
    'serviceable',true,'service',v_service,'items',v_items,'subtotal',v_subtotal,
    'delivery_fee',v_delivery,'discount',0,'total',v_subtotal+v_delivery,'currency',v_currency,
    'min_order',v_min_order,'meets_min_order',v_subtotal>=v_min_order,
    'amount_to_min_order',greatest(v_min_order-v_subtotal,0)
  );
end;
$function$;

create or replace function private.create_order_checkout_v2_atomic(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_payment_method text default 'cash'::text,
  p_customer_note text default null::text,
  p_substitute_policy text default 'call_me'::text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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
  v_min_qty integer;
  v_qty_step integer;
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
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 then
      raise exception 'INVALID_ITEM' using errcode='22023';
    end if;

    select p.id,p.name,p.price,p.stock_qty,p.is_available,p.min_qty,p.qty_step
      into v_product
    from public.products p
    where p.id=v_item.product_id and p.store_id=p_store_id
    for update;

    if not found or not coalesce(v_product.is_available,false) then
      raise exception 'PRODUCT_UNAVAILABLE:%',v_item.product_id;
    end if;

    v_min_qty := greatest(coalesce(v_product.min_qty,1),1);
    v_qty_step := greatest(coalesce(v_product.qty_step,1),1);

    if v_item.quantity < v_min_qty then
      raise exception 'MIN_QTY:%:%',v_product.name,v_min_qty using errcode='22023';
    end if;
    if mod(v_item.quantity-v_min_qty,v_qty_step)<>0 then
      raise exception 'INVALID_QTY_STEP:%:%',v_product.name,v_qty_step using errcode='22023';
    end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then
      raise exception 'INSUFFICIENT_STOCK:%',v_product.name;
    end if;
    if v_product.price is null or v_product.price<=0 then
      raise exception 'INVALID_PRICE:%',v_product.name;
    end if;

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
        is_available=case
          when stock_qty-v_item.quantity < greatest(coalesce(min_qty,1),1) then false
          else is_available
        end,
        updated_at=now()
    where id=v_item.product_id and store_id=p_store_id and stock_qty>=v_item.quantity;
    if not found then raise exception 'STOCK_CHANGED:%',v_item.product_id; end if;
  end loop;

  insert into public.order_status_history(order_id,status,changed_by)
  values(v_order,'pending',v_user);
  return v_order;
end;
$function$;

create or replace function private.create_order_atomic(
  p_store_id uuid,
  p_items jsonb,
  p_payment_method text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_order_id uuid;
  v_item record;
  v_product record;
  v_total numeric := 0;
  v_delivery_fee numeric := 0;
  v_payment_method text := lower(trim(coalesce(p_payment_method, 'cash')));
  v_payment_status text;
  v_min_qty integer;
  v_qty_step integer;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if v_payment_method not in ('cash','cliq','card') then raise exception 'Unsupported payment method' using errcode='22023'; end if;
  v_payment_status := case when v_payment_method='cash' then 'unpaid' else 'pending' end;

  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Order must contain at least one item' using errcode='22023';
  end if;
  if jsonb_array_length(p_items)>100 then raise exception 'Too many order items' using errcode='22023'; end if;
  if not exists(select 1 from public.customers c where c.id=v_user_id) then raise exception 'Customer profile is required' using errcode='42501'; end if;

  select coalesce(s.delivery_fee,0) into v_delivery_fee
  from public.stores s where s.id=p_store_id and s.is_active=true;
  if not found then raise exception 'Store is unavailable' using errcode='P0001'; end if;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 then
      raise exception 'Invalid order item' using errcode='22023';
    end if;

    select p.id,p.name,p.price,p.stock_qty,p.is_available,p.min_qty,p.qty_step
      into v_product
    from public.products p
    where p.id=v_item.product_id and p.store_id=p_store_id
    for update;

    if not found or not coalesce(v_product.is_available,false) then raise exception 'Product is unavailable' using errcode='P0001'; end if;

    v_min_qty := greatest(coalesce(v_product.min_qty,1),1);
    v_qty_step := greatest(coalesce(v_product.qty_step,1),1);
    if v_item.quantity < v_min_qty then raise exception 'MIN_QTY:%:%',v_product.name,v_min_qty using errcode='22023'; end if;
    if mod(v_item.quantity-v_min_qty,v_qty_step)<>0 then raise exception 'INVALID_QTY_STEP:%:%',v_product.name,v_qty_step using errcode='22023'; end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then raise exception 'Insufficient stock' using errcode='P0001'; end if;
    if v_product.price is null or v_product.price<=0 then raise exception 'Invalid product price' using errcode='P0001'; end if;
    v_total := v_total + (v_product.price*v_item.quantity);
  end loop;

  if v_total<=0 then raise exception 'Invalid order total' using errcode='P0001'; end if;

  insert into public.orders(store_id,customer_id,subtotal,delivery_fee,total,status,payment_method,payment_status)
  values(p_store_id,v_user_id,v_total,v_delivery_fee,v_total+v_delivery_fee,'pending',v_payment_method,v_payment_status)
  returning id into v_order_id;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    insert into public.order_items(order_id,product_id,quantity,unit_price,product_name,subtotal)
    select v_order_id,p.id,v_item.quantity,p.price,p.name,p.price*v_item.quantity
    from public.products p where p.id=v_item.product_id and p.store_id=p_store_id;

    update public.products
    set stock_qty=stock_qty-v_item.quantity,
        is_available=case
          when stock_qty-v_item.quantity < greatest(coalesce(min_qty,1),1) then false
          else is_available
        end,
        updated_at=now()
    where id=v_item.product_id and store_id=p_store_id and stock_qty>=v_item.quantity;
    if not found then raise exception 'STOCK_CHANGED:%',v_item.product_id; end if;
  end loop;

  insert into public.order_status_history(order_id,status,changed_by)
  values(v_order_id,'pending',v_user_id);
  return v_order_id;
end;
$function$;

create or replace function private.create_order_atomic(
  p_store_id uuid,
  p_items jsonb
)
returns uuid
language sql
security definer
set search_path to ''
as $function$
  select private.create_order_atomic(p_store_id,p_items,'cash');
$function$;
