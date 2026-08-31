-- Altayebat production hardening
-- Run this in the Supabase SQL editor after reviewing it against the live schema.
-- It is intentionally kept as a reviewable SQL script because this repository
-- does not yet contain a Supabase CLI migration history.

begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Authorization helpers. Kept in a non-exposed schema and locked down.
-- ---------------------------------------------------------------------------
create or replace function private.is_store_admin(target_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.store_admins sa
    where sa.user_id = (select auth.uid())
      and sa.store_id = target_store_id
  );
$$;

revoke execute on function private.is_store_admin(uuid) from public, anon;
grant execute on function private.is_store_admin(uuid) to authenticated;

create or replace function private.owns_order(target_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = target_order_id
      and o.customer_id = (select auth.uid())
  );
$$;

revoke execute on function private.owns_order(uuid) from public, anon;
grant execute on function private.owns_order(uuid) to authenticated;

create or replace function private.admin_can_see_customer(target_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    join public.store_admins sa on sa.store_id = o.store_id
    where o.customer_id = target_customer_id
      and sa.user_id = (select auth.uid())
  );
$$;

revoke execute on function private.admin_can_see_customer(uuid) from public, anon;
grant execute on function private.admin_can_see_customer(uuid) to authenticated;

create or replace function private.admin_can_access_order(target_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders o
    join public.store_admins sa on sa.store_id = o.store_id
    where o.id = target_order_id
      and sa.user_id = (select auth.uid())
  );
$$;

revoke execute on function private.admin_can_access_order(uuid) from public, anon;
grant execute on function private.admin_can_access_order(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Atomic checkout implementation. The privileged implementation lives in the
-- private schema; the public RPC wrapper remains SECURITY INVOKER.
-- ---------------------------------------------------------------------------
create or replace function private.create_order_atomic(
  p_store_id uuid,
  p_items jsonb
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
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

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

  -- Validate and lock every requested product. Duplicate product IDs are folded
  -- into a single quantity before validation.
  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    group by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity <= 0 then
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

    if v_stock < v_item.quantity then
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

  insert into public.orders (store_id, customer_id, total, status)
  values (p_store_id, v_user_id, v_total, 'pending')
  returning id into v_order_id;

  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    group by x.product_id
  loop
    select p.price
      into v_price
    from public.products p
    where p.id = v_item.product_id
      and p.store_id = p_store_id;

    insert into public.order_items (order_id, product_id, quantity, unit_price)
    values (v_order_id, v_item.product_id, v_item.quantity, v_price);

    update public.products
    set stock_qty = stock_qty - v_item.quantity,
        is_available = case
          when stock_qty - v_item.quantity <= 0 then false
          else is_available
        end
    where id = v_item.product_id
      and store_id = p_store_id;
  end loop;

  return v_order_id;
end;
$$;

revoke execute on function private.create_order_atomic(uuid, jsonb) from public, anon;
grant execute on function private.create_order_atomic(uuid, jsonb) to authenticated;

create or replace function public.create_order(
  p_store_id uuid,
  p_items jsonb
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.create_order_atomic(p_store_id, p_items);
$$;

revoke execute on function public.create_order(uuid, jsonb) from public, anon;
grant execute on function public.create_order(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.stores enable row level security;
alter table public.store_admins enable row level security;
alter table public.customers enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.driver_locations enable row level security;
alter table public.call_requests enable row level security;

-- Existing policy names from older/manual setups are deliberately not guessed.
-- These DROP statements only target the policy names managed by this script.
drop policy if exists altayebat_stores_select on public.stores;
create policy altayebat_stores_select
on public.stores for select
to authenticated
using (private.is_store_admin(id));

drop policy if exists altayebat_store_admins_select on public.store_admins;
create policy altayebat_store_admins_select
on public.store_admins for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists altayebat_customers_select on public.customers;
create policy altayebat_customers_select
on public.customers for select
to authenticated
using (
  (select auth.uid()) = id
  or private.admin_can_see_customer(id)
);

drop policy if exists altayebat_customers_insert on public.customers;
create policy altayebat_customers_insert
on public.customers for insert
to authenticated
with check ((select auth.uid()) = id);

drop policy if exists altayebat_customers_update on public.customers;
create policy altayebat_customers_update
on public.customers for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists altayebat_categories_select on public.categories;
create policy altayebat_categories_select
on public.categories for select
to authenticated
using (true);

drop policy if exists altayebat_categories_insert on public.categories;
create policy altayebat_categories_insert
on public.categories for insert
to authenticated
with check (private.is_store_admin(store_id));

drop policy if exists altayebat_categories_update on public.categories;
create policy altayebat_categories_update
on public.categories for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

drop policy if exists altayebat_categories_delete on public.categories;
create policy altayebat_categories_delete
on public.categories for delete
to authenticated
using (private.is_store_admin(store_id));

drop policy if exists altayebat_products_select on public.products;
create policy altayebat_products_select
on public.products for select
to authenticated
using (true);

drop policy if exists altayebat_products_insert on public.products;
create policy altayebat_products_insert
on public.products for insert
to authenticated
with check (private.is_store_admin(store_id));

drop policy if exists altayebat_products_update on public.products;
create policy altayebat_products_update
on public.products for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

drop policy if exists altayebat_products_delete on public.products;
create policy altayebat_products_delete
on public.products for delete
to authenticated
using (private.is_store_admin(store_id));

drop policy if exists altayebat_orders_select on public.orders;
create policy altayebat_orders_select
on public.orders for select
to authenticated
using (
  (select auth.uid()) = customer_id
  or private.is_store_admin(store_id)
);

drop policy if exists altayebat_orders_update on public.orders;
create policy altayebat_orders_update
on public.orders for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

drop policy if exists altayebat_order_items_select on public.order_items;
create policy altayebat_order_items_select
on public.order_items for select
to authenticated
using (
  private.owns_order(order_id)
  or private.admin_can_access_order(order_id)
);

drop policy if exists altayebat_driver_locations_select on public.driver_locations;
create policy altayebat_driver_locations_select
on public.driver_locations for select
to authenticated
using (
  private.owns_order(order_id)
  or private.admin_can_access_order(order_id)
);

drop policy if exists altayebat_call_requests_select on public.call_requests;
create policy altayebat_call_requests_select
on public.call_requests for select
to authenticated
using (
  (select auth.uid()) = customer_id
  or private.is_store_admin(store_id)
);

drop policy if exists altayebat_call_requests_insert on public.call_requests;
create policy altayebat_call_requests_insert
on public.call_requests for insert
to authenticated
with check (
  (select auth.uid()) = customer_id
  and (
    order_id is null
    or private.owns_order(order_id)
  )
);

drop policy if exists altayebat_call_requests_update on public.call_requests;
create policy altayebat_call_requests_update
on public.call_requests for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

-- ---------------------------------------------------------------------------
-- Explicit Data API privileges. Supabase no longer guarantees automatic table
-- exposure for new projects, so the required privileges are declared here.
-- Direct customer inserts into orders/order_items are intentionally omitted;
-- checkout goes through public.create_order().
-- ---------------------------------------------------------------------------
grant select on public.stores to authenticated;
grant select on public.store_admins to authenticated;
grant select, insert, update on public.customers to authenticated;
grant select, insert, update, delete on public.categories to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select, update on public.orders to authenticated;
grant select on public.order_items to authenticated;
grant select on public.driver_locations to authenticated;
grant select, insert, update on public.call_requests to authenticated;

revoke insert, delete on public.orders from authenticated;
revoke insert, update, delete on public.order_items from authenticated;

-- Helpful indexes for tenant filters and RLS helper lookups.
create index if not exists idx_store_admins_user_store
  on public.store_admins (user_id, store_id);
create index if not exists idx_products_store_category
  on public.products (store_id, category_id);
create index if not exists idx_orders_store_created
  on public.orders (store_id, created_at desc);
create index if not exists idx_orders_customer_created
  on public.orders (customer_id, created_at desc);
create index if not exists idx_order_items_order
  on public.order_items (order_id);
create index if not exists idx_driver_locations_order_updated
  on public.driver_locations (order_id, updated_at desc);
create index if not exists idx_call_requests_store_status
  on public.call_requests (store_id, status);

commit;
