create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.is_store_admin(target_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
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
    select 1 from public.orders o
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

create or replace function private.create_order_atomic(p_store_id uuid, p_items jsonb)
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
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'Too many order items' using errcode = '22023';
  end if;

  if not exists (select 1 from public.customers c where c.id = v_user_id) then
    raise exception 'Customer profile is required' using errcode = '42501';
  end if;

  select coalesce(s.delivery_fee, 0)
    into v_delivery_fee
  from public.stores s
  where s.id = p_store_id and s.is_active = true;
  if not found then
    raise exception 'Store is unavailable' using errcode = 'P0001';
  end if;

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
    where p.id = v_item.product_id and p.store_id = p_store_id
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

  insert into public.orders (store_id, customer_id, subtotal, delivery_fee, total, status)
  values (p_store_id, v_user_id, v_total, v_delivery_fee, v_total + v_delivery_fee, 'pending')
  returning id into v_order_id;

  for v_item in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as x(product_id uuid, quantity integer)
    group by x.product_id
  loop
    select p.price into v_price
    from public.products p
    where p.id = v_item.product_id and p.store_id = p_store_id;

    insert into public.order_items (order_id, product_id, quantity, unit_price, product_name, subtotal)
    select v_order_id, p.id, v_item.quantity, p.price, p.name, p.price * v_item.quantity
    from public.products p
    where p.id = v_item.product_id and p.store_id = p_store_id;

    update public.products
    set stock_qty = stock_qty - v_item.quantity,
        is_available = case when stock_qty - v_item.quantity <= 0 then false else is_available end,
        updated_at = now()
    where id = v_item.product_id and store_id = p_store_id;
  end loop;

  insert into public.order_status_history(order_id, status, changed_by)
  values (v_order_id, 'pending', v_user_id);

  return v_order_id;
end;
$$;
revoke execute on function private.create_order_atomic(uuid, jsonb) from public, anon;
grant execute on function private.create_order_atomic(uuid, jsonb) to authenticated;

create or replace function public.create_order(p_store_id uuid, p_items jsonb)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select private.create_order_atomic(p_store_id, p_items); $$;
revoke execute on function public.create_order(uuid, jsonb) from public, anon;
grant execute on function public.create_order(uuid, jsonb) to authenticated;

alter table public.stores enable row level security;
alter table public.store_admins enable row level security;
alter table public.customers enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.driver_locations enable row level security;
alter table public.call_requests enable row level security;

-- Replace overlapping legacy policies on the hardened tables.
drop policy if exists "Public can view active stores" on public.stores;
drop policy if exists "Store admins manage their store" on public.stores;
drop policy if exists altayebat_stores_select on public.stores;
create policy altayebat_stores_select on public.stores for select to authenticated
using (is_active = true or private.is_store_admin(id));

drop policy if exists "Store admins manage admin list" on public.store_admins;
drop policy if exists "Store admins view own store admin list" on public.store_admins;
drop policy if exists altayebat_store_admins_select on public.store_admins;
create policy altayebat_store_admins_select on public.store_admins for select to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Customers create own profile" on public.customers;
drop policy if exists "Customers update own profile" on public.customers;
drop policy if exists "Customers view own profile" on public.customers;
drop policy if exists altayebat_customers_select on public.customers;
drop policy if exists altayebat_customers_insert on public.customers;
drop policy if exists altayebat_customers_update on public.customers;
create policy altayebat_customers_select on public.customers for select to authenticated
using ((select auth.uid()) = id or private.admin_can_see_customer(id));
create policy altayebat_customers_insert on public.customers for insert to authenticated
with check ((select auth.uid()) = id);
create policy altayebat_customers_update on public.customers for update to authenticated
using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

drop policy if exists "Public can view categories" on public.categories;
drop policy if exists "Store admins manage categories" on public.categories;
drop policy if exists altayebat_categories_select on public.categories;
drop policy if exists altayebat_categories_insert on public.categories;
drop policy if exists altayebat_categories_update on public.categories;
drop policy if exists altayebat_categories_delete on public.categories;
create policy altayebat_categories_select on public.categories for select to authenticated using (is_active = true or private.is_store_admin(store_id));
create policy altayebat_categories_insert on public.categories for insert to authenticated with check (private.is_store_admin(store_id));
create policy altayebat_categories_update on public.categories for update to authenticated using (private.is_store_admin(store_id)) with check (private.is_store_admin(store_id));
create policy altayebat_categories_delete on public.categories for delete to authenticated using (private.is_store_admin(store_id));

drop policy if exists "Public can view available products" on public.products;
drop policy if exists "Store admins manage products" on public.products;
drop policy if exists altayebat_products_select on public.products;
drop policy if exists altayebat_products_insert on public.products;
drop policy if exists altayebat_products_update on public.products;
drop policy if exists altayebat_products_delete on public.products;
create policy altayebat_products_select on public.products for select to authenticated using (is_available = true or private.is_store_admin(store_id));
create policy altayebat_products_insert on public.products for insert to authenticated with check (private.is_store_admin(store_id));
create policy altayebat_products_update on public.products for update to authenticated using (private.is_store_admin(store_id)) with check (private.is_store_admin(store_id));
create policy altayebat_products_delete on public.products for delete to authenticated using (private.is_store_admin(store_id));

drop policy if exists "Customers view own orders" on public.orders;
drop policy if exists "Store admins manage store orders" on public.orders;
drop policy if exists altayebat_orders_select on public.orders;
drop policy if exists altayebat_orders_update on public.orders;
create policy altayebat_orders_select on public.orders for select to authenticated
using ((select auth.uid()) = customer_id or private.is_store_admin(store_id));
create policy altayebat_orders_update on public.orders for update to authenticated
using (private.is_store_admin(store_id)) with check (private.is_store_admin(store_id));

drop policy if exists "View items of accessible orders" on public.order_items;
drop policy if exists altayebat_order_items_select on public.order_items;
create policy altayebat_order_items_select on public.order_items for select to authenticated
using (private.owns_order(order_id) or private.admin_can_access_order(order_id));

drop policy if exists "View driver location for own order" on public.driver_locations;
drop policy if exists "Store admins manage driver locations" on public.driver_locations;
drop policy if exists altayebat_driver_locations_select on public.driver_locations;
create policy altayebat_driver_locations_select on public.driver_locations for select to authenticated
using (private.owns_order(order_id) or private.admin_can_access_order(order_id));

drop policy if exists "Customers create own call requests" on public.call_requests;
drop policy if exists "Customers view own call requests" on public.call_requests;
drop policy if exists "Store admins view store call requests" on public.call_requests;
drop policy if exists altayebat_call_requests_select on public.call_requests;
drop policy if exists altayebat_call_requests_insert on public.call_requests;
drop policy if exists altayebat_call_requests_update on public.call_requests;
create policy altayebat_call_requests_select on public.call_requests for select to authenticated
using ((select auth.uid()) = customer_id or private.is_store_admin(store_id));
create policy altayebat_call_requests_insert on public.call_requests for insert to authenticated
with check ((select auth.uid()) = customer_id and (order_id is null or private.owns_order(order_id)));
create policy altayebat_call_requests_update on public.call_requests for update to authenticated
using (private.is_store_admin(store_id)) with check (private.is_store_admin(store_id));

-- Explicitly reset exposed-role privileges to least privilege for hardened tables.
revoke all on public.stores, public.store_admins, public.customers, public.categories, public.products, public.orders, public.order_items, public.driver_locations, public.call_requests from anon;
revoke all on public.stores, public.store_admins, public.customers, public.categories, public.products, public.orders, public.order_items, public.driver_locations, public.call_requests from authenticated;

grant select on public.stores to authenticated;
grant select on public.store_admins to authenticated;
grant select, insert, update on public.customers to authenticated;
grant select, insert, update, delete on public.categories to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select, update on public.orders to authenticated;
grant select on public.order_items to authenticated;
grant select on public.driver_locations to authenticated;
grant select, insert, update on public.call_requests to authenticated;

create index if not exists idx_store_admins_user_store on public.store_admins(user_id, store_id);
create index if not exists idx_products_store_category on public.products(store_id, category_id);
create index if not exists idx_orders_store_created on public.orders(store_id, created_at desc);
create index if not exists idx_orders_customer_created on public.orders(customer_id, created_at desc);
create index if not exists idx_order_items_order on public.order_items(order_id);
create index if not exists idx_driver_locations_order_updated on public.driver_locations(order_id, updated_at desc);
create index if not exists idx_call_requests_store_status on public.call_requests(store_id, status);
