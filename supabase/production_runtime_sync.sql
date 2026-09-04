-- Altayebat production runtime contract sync
--
-- Apply AFTER production_hardening.sql on the existing Altayebat schema.
-- This file captures production behavior that was previously deployed manually
-- and therefore drifted ahead of GitHub.

begin;

-- Fail early instead of silently creating an incompatible partial schema.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'payment_method'
  ) then
    raise exception 'orders.payment_method is required before applying production_runtime_sync.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'payment_status'
  ) then
    raise exception 'orders.payment_status is required before applying production_runtime_sync.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'subtotal'
  ) then
    raise exception 'orders.subtotal is required before applying production_runtime_sync.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'stores'
      and column_name = 'delivery_fee'
  ) then
    raise exception 'stores.delivery_fee is required before applying production_runtime_sync.sql';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'stores'
      and column_name = 'is_active'
  ) then
    raise exception 'stores.is_active is required before applying production_runtime_sync.sql';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Checkout contract used by the Flutter client.
-- ---------------------------------------------------------------------------
create or replace function private.create_order_atomic(
  p_store_id uuid,
  p_items jsonb,
  p_payment_method text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_order_id uuid;
  v_item record;
  v_price numeric;
  v_stock integer;
  v_available boolean;
  v_total numeric := 0;
  v_delivery_fee numeric := 0;
  v_payment_method text := lower(trim(coalesce(p_payment_method, 'cash')));
  v_payment_status text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if v_payment_method not in ('cash', 'cliq', 'card') then
    raise exception 'Unsupported payment method' using errcode = '22023';
  end if;

  v_payment_status := case
    when v_payment_method = 'cash' then 'unpaid'
    else 'pending'
  end;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item' using errcode = '22023';
  end if;

  if jsonb_array_length(p_items) > 100 then
    raise exception 'Too many order items' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.customers c where c.id = v_user_id
  ) then
    raise exception 'Customer profile is required' using errcode = '42501';
  end if;

  select coalesce(s.delivery_fee, 0)
    into v_delivery_fee
  from public.stores s
  where s.id = p_store_id
    and s.is_active = true;

  if not found then
    raise exception 'Store is unavailable' using errcode = 'P0001';
  end if;

  -- Validate and lock all requested products before inserting the order.
  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    group by x.product_id
  loop
    if v_item.product_id is null
       or v_item.quantity is null
       or v_item.quantity <= 0 then
      raise exception 'Invalid order item' using errcode = '22023';
    end if;

    select p.price, p.stock_qty, p.is_available
      into v_price, v_stock, v_available
    from public.products p
    where p.id = v_item.product_id
      and p.store_id = p_store_id
    for update;

    if not found or not coalesce(v_available, false) then
      raise exception 'Product is unavailable' using errcode = 'P0001';
    end if;

    if coalesce(v_stock, 0) < v_item.quantity then
      raise exception 'Insufficient stock' using errcode = 'P0001';
    end if;

    if v_price is null or v_price <= 0 then
      raise exception 'Invalid product price' using errcode = 'P0001';
    end if;

    v_total := v_total + (v_price * v_item.quantity);
  end loop;

  if v_total <= 0 then
    raise exception 'Invalid order total' using errcode = 'P0001';
  end if;

  insert into public.orders (
    store_id,
    customer_id,
    subtotal,
    delivery_fee,
    total,
    status,
    payment_method,
    payment_status
  )
  values (
    p_store_id,
    v_user_id,
    v_total,
    v_delivery_fee,
    v_total + v_delivery_fee,
    'pending',
    v_payment_method,
    v_payment_status
  )
  returning id into v_order_id;

  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    group by x.product_id
  loop
    insert into public.order_items (
      order_id,
      product_id,
      quantity,
      unit_price,
      product_name,
      subtotal
    )
    select
      v_order_id,
      p.id,
      v_item.quantity,
      p.price,
      p.name,
      p.price * v_item.quantity
    from public.products p
    where p.id = v_item.product_id
      and p.store_id = p_store_id;

    update public.products
    set stock_qty = stock_qty - v_item.quantity,
        is_available = case
          when stock_qty - v_item.quantity <= 0 then false
          else is_available
        end,
        updated_at = now()
    where id = v_item.product_id
      and store_id = p_store_id;
  end loop;

  insert into public.order_status_history(order_id, status, changed_by)
  values (v_order_id, 'pending', v_user_id);

  return v_order_id;
end;
$$;

revoke execute on function private.create_order_atomic(uuid, jsonb, text)
  from public, anon;
grant execute on function private.create_order_atomic(uuid, jsonb, text)
  to authenticated;

create or replace function public.create_order(
  p_store_id uuid,
  p_items jsonb,
  p_payment_method text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_order_atomic(p_store_id, p_items, p_payment_method);
$$;

revoke execute on function public.create_order(uuid, jsonb, text)
  from public, anon;
grant execute on function public.create_order(uuid, jsonb, text)
  to authenticated;

-- Keep the legacy 2-argument RPC compatible for older clients, but route it
-- through the current implementation so all checkout validation stays unified.
create or replace function public.create_order(
  p_store_id uuid,
  p_items jsonb
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_order_atomic(p_store_id, p_items, 'cash');
$$;

revoke execute on function public.create_order(uuid, jsonb)
  from public, anon;
grant execute on function public.create_order(uuid, jsonb)
  to authenticated;

-- Customers need the active store row for public contact/CliQ configuration;
-- administrators retain access to their assigned store even if it is inactive.
drop policy if exists altayebat_stores_select on public.stores;
create policy altayebat_stores_select
on public.stores for select
to authenticated
using (
  is_active = true
  or private.is_store_admin(id)
);

-- Payment lookups used by the dashboard/callback path.
create index if not exists idx_orders_store_payment_status
  on public.orders (store_id, payment_status);
create index if not exists idx_orders_payment_reference
  on public.orders (payment_reference)
  where payment_reference is not null;

commit;
