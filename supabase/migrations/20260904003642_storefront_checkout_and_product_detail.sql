create or replace function public.checkout_quote(p_store_id uuid,p_items jsonb)
returns jsonb
language plpgsql
stable
set search_path=''
as $$
declare
  v_item record;
  v_product record;
  v_subtotal numeric(12,3):=0;
  v_delivery numeric(12,3):=0;
  v_min_order numeric(12,3):=0;
  v_currency text:='JOD';
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART' using errcode='22023'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'TOO_MANY_ITEMS' using errcode='22023'; end if;

  select s.delivery_fee,s.min_order,s.currency into v_delivery,v_min_order,v_currency
  from public.stores s where s.id=p_store_id and s.is_active=true;
  if not found then raise exception 'STORE_UNAVAILABLE'; end if;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 then raise exception 'INVALID_ITEM'; end if;
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
    'items',v_items,'subtotal',v_subtotal,'delivery_fee',v_delivery,'discount',0,
    'total',v_subtotal+v_delivery,'currency',v_currency,'min_order',v_min_order,
    'meets_min_order',v_subtotal>=v_min_order,'amount_to_min_order',greatest(v_min_order-v_subtotal,0)
  );
end;
$$;
revoke all on function public.checkout_quote(uuid,jsonb) from public,anon;
grant execute on function public.checkout_quote(uuid,jsonb) to authenticated;

create or replace function private.create_order_checkout_atomic(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid default null,
  p_payment_method text default 'cash',
  p_customer_note text default null,
  p_substitute_policy text default 'call_me'
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_order uuid;
  v_item record;
  v_product record;
  v_subtotal numeric(12,3):=0;
  v_delivery numeric(12,3):=0;
  v_min_order numeric(12,3):=0;
  v_payment text:=lower(btrim(coalesce(p_payment_method,'cash')));
  v_payment_status text;
  v_sub_policy text:=lower(btrim(coalesce(p_substitute_policy,'call_me')));
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if v_payment not in ('cash','card','cliq') then raise exception 'INVALID_PAYMENT_METHOD' using errcode='22023'; end if;
  if v_sub_policy not in ('call_me','best_match','remove_item') then raise exception 'INVALID_SUBSTITUTE_POLICY' using errcode='22023'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART' using errcode='22023'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'TOO_MANY_ITEMS' using errcode='22023'; end if;
  if not exists(select 1 from public.customers c where c.id=v_user) then raise exception 'CUSTOMER_PROFILE_REQUIRED' using errcode='42501'; end if;

  select s.delivery_fee,s.min_order into v_delivery,v_min_order from public.stores s where s.id=p_store_id and s.is_active=true;
  if not found then raise exception 'STORE_UNAVAILABLE'; end if;

  if p_address_id is not null and not exists(select 1 from public.addresses a where a.id=p_address_id and a.customer_id=v_user) then
    raise exception 'INVALID_ADDRESS' using errcode='42501';
  end if;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 then raise exception 'INVALID_ITEM'; end if;
    select p.id,p.name,p.price,p.stock_qty,p.is_available into v_product
    from public.products p where p.id=v_item.product_id and p.store_id=p_store_id for update;
    if not found or not coalesce(v_product.is_available,false) then raise exception 'PRODUCT_UNAVAILABLE'; end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then raise exception 'INSUFFICIENT_STOCK:%',v_product.name; end if;
    if v_product.price is null or v_product.price<=0 then raise exception 'INVALID_PRICE:%',v_product.name; end if;
    v_subtotal:=v_subtotal+(v_product.price*v_item.quantity);
  end loop;

  if v_subtotal<v_min_order then raise exception 'MIN_ORDER:%',v_min_order; end if;
  v_payment_status:=case when v_payment='cash' then 'unpaid' else 'pending' end;

  insert into public.orders(store_id,customer_id,address_id,status,payment_method,payment_status,subtotal,delivery_fee,discount,total,customer_note,substitute_policy)
  values(p_store_id,v_user,p_address_id,'pending',v_payment,v_payment_status,v_subtotal,v_delivery,0,v_subtotal+v_delivery,nullif(btrim(p_customer_note),''),v_sub_policy)
  returning id into v_order;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
  loop
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,subtotal)
    select v_order,p.id,p.name,v_item.quantity,p.price,p.price*v_item.quantity
    from public.products p where p.id=v_item.product_id and p.store_id=p_store_id;

    update public.products
    set stock_qty=stock_qty-v_item.quantity,
        is_available=case when stock_qty-v_item.quantity<=0 then false else is_available end,
        updated_at=now()
    where id=v_item.product_id and store_id=p_store_id;
  end loop;

  insert into public.order_status_history(order_id,status,changed_by) values(v_order,'pending',v_user);
  return v_order;
end;
$$;
revoke all on function private.create_order_checkout_atomic(uuid,jsonb,uuid,text,text,text) from public,anon,authenticated;

create or replace function public.create_order_checkout(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid default null,
  p_payment_method text default 'cash',
  p_customer_note text default null,
  p_substitute_policy text default 'call_me'
)
returns uuid
language sql
set search_path=''
as $$ select private.create_order_checkout_atomic(p_store_id,p_items,p_address_id,p_payment_method,p_customer_note,p_substitute_policy); $$;
revoke all on function public.create_order_checkout(uuid,jsonb,uuid,text,text,text) from public,anon;
grant execute on function public.create_order_checkout(uuid,jsonb,uuid,text,text,text) to authenticated;

create or replace function public.get_product_detail(p_product_id uuid)
returns jsonb
language sql
stable
set search_path=''
as $$
with product_row as (
  select p.id,p.store_id,p.name,p.name_en,p.description,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.is_available,p.unit,p.pack_size,p.barcode,p.sku,p.is_featured,
         p.category_id,c.name category_name,c.parent_id category_parent_id,p.brand_id,b.name brand_name,b.logo_url brand_logo,
         exists(select 1 from public.favorites f where f.customer_id=auth.uid() and f.product_id=p.id) is_favorite
  from public.products p
  left join public.categories c on c.id=p.category_id
  left join public.brands b on b.id=p.brand_id
  where p.id=p_product_id
), similar_products as (
  select p.id,p.name,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.unit,p.pack_size
  from public.products p cross join product_row pr
  where p.store_id=pr.store_id and p.id<>pr.id and p.category_id=pr.category_id and p.is_available=true and p.stock_qty>0
  order by abs(p.price-pr.price),p.is_featured desc,p.sort_order,p.name
  limit 12
)
select jsonb_build_object(
  'product',(select to_jsonb(pr) from product_row pr),
  'similar',coalesce((select jsonb_agg(to_jsonb(sp)) from similar_products sp),'[]'::jsonb)
);
$$;
revoke all on function public.get_product_detail(uuid) from public,anon;
grant execute on function public.get_product_detail(uuid) to authenticated;

create or replace function public.toggle_favorite(p_product_id uuid)
returns boolean
language plpgsql
set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_now_favorite boolean;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not exists(select 1 from public.products p where p.id=p_product_id and p.is_available=true) then raise exception 'PRODUCT_UNAVAILABLE'; end if;
  if exists(select 1 from public.favorites f where f.customer_id=v_user and f.product_id=p_product_id) then
    delete from public.favorites where customer_id=v_user and product_id=p_product_id;
    v_now_favorite:=false;
  else
    insert into public.favorites(customer_id,product_id) values(v_user,p_product_id);
    v_now_favorite:=true;
  end if;
  return v_now_favorite;
end;
$$;
revoke all on function public.toggle_favorite(uuid) from public,anon;
grant execute on function public.toggle_favorite(uuid) to authenticated;
