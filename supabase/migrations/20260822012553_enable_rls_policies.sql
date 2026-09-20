-- Enable RLS on all tables
alter table stores enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table customers enable row level security;
alter table addresses enable row level security;
alter table drivers enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table driver_locations enable row level security;
alter table store_admins enable row level security;
alter table call_requests enable row level security;

-- Helper: is the current user an admin of a given store?
create or replace function is_store_admin(target_store_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from store_admins
    where store_id = target_store_id and user_id = auth.uid()
  );
$$;

-- STORES: public can read active stores; only that store's admins can edit
create policy "Public can view active stores" on stores
  for select using (is_active = true);
create policy "Store admins manage their store" on stores
  for all using (is_store_admin(id));

-- CATEGORIES: public read, store admins write
create policy "Public can view categories" on categories
  for select using (true);
create policy "Store admins manage categories" on categories
  for all using (is_store_admin(store_id));

-- PRODUCTS: public read available products, store admins full control
create policy "Public can view available products" on products
  for select using (is_available = true or is_store_admin(store_id));
create policy "Store admins manage products" on products
  for all using (is_store_admin(store_id));

-- CUSTOMERS: only the customer themself
create policy "Customers manage own profile" on customers
  for all using (auth.uid() = id);

-- ADDRESSES: only the owning customer
create policy "Customers manage own addresses" on addresses
  for all using (auth.uid() = customer_id);

-- DRIVERS: store admins manage; drivers can see their own row
create policy "Store admins manage drivers" on drivers
  for all using (is_store_admin(store_id));

-- ORDERS: customer sees own orders, store admins see their store's orders
create policy "Customers view own orders" on orders
  for select using (auth.uid() = customer_id);
create policy "Customers create own orders" on orders
  for insert with check (auth.uid() = customer_id);
create policy "Store admins manage store orders" on orders
  for all using (is_store_admin(store_id));

-- ORDER_ITEMS: visible if you can see the parent order
create policy "View items of accessible orders" on order_items
  for select using (
    exists (
      select 1 from orders o
      where o.id = order_id
      and (o.customer_id = auth.uid() or is_store_admin(o.store_id))
    )
  );
create policy "Customers add items to own orders" on order_items
  for insert with check (
    exists (
      select 1 from orders o
      where o.id = order_id and o.customer_id = auth.uid()
    )
  );

-- DRIVER_LOCATIONS: visible to the order's customer and store admins
create policy "View driver location for own order" on driver_locations
  for select using (
    exists (
      select 1 from orders o
      where o.id = order_id
      and (o.customer_id = auth.uid() or is_store_admin(o.store_id))
    )
  );
create policy "Store admins manage driver locations" on driver_locations
  for all using (
    exists (select 1 from drivers d where d.id = driver_id and is_store_admin(d.store_id))
  );

-- STORE_ADMINS: only visible/manageable by admins of that store
create policy "Store admins view own store admin list" on store_admins
  for select using (is_store_admin(store_id));
create policy "Store admins manage admin list" on store_admins
  for all using (is_store_admin(store_id));

-- CALL_REQUESTS: customer and store admins of that store
create policy "Customers manage own call requests" on call_requests
  for all using (auth.uid() = customer_id);
create policy "Store admins view store call requests" on call_requests
  for all using (is_store_admin(store_id));
