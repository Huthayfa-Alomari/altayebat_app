-- Enable UUID generation
create extension if not exists "pgcrypto";

-- STORES: كل مول عنده هويته الخاصة
create table stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_en text,
  slug text unique not null,
  logo_url text,
  primary_color text default '#E31E24',
  phone text,
  address text,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- CATEGORIES: تصنيفات المنتجات لكل مول
create table categories (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references stores(id) on delete cascade not null,
  name text not null,
  sort_order int default 0,
  created_at timestamptz default now()
);

-- PRODUCTS
create table products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references stores(id) on delete cascade not null,
  category_id uuid references categories(id) on delete set null,
  name text not null,
  description text,
  price numeric(10,2) not null,
  image_url text,
  stock_qty int default 0,
  is_available boolean default true,
  created_at timestamptz default now()
);

-- CUSTOMERS (linked to Supabase auth.users)
create table customers (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text unique,
  name text,
  created_at timestamptz default now()
);

-- ADDRESSES
create table addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references customers(id) on delete cascade not null,
  label text,
  address_text text,
  lat numeric(9,6),
  lng numeric(9,6),
  created_at timestamptz default now()
);

-- DRIVERS
create table drivers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references stores(id) on delete cascade not null,
  name text not null,
  phone text,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- ORDERS
create table orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references stores(id) on delete cascade not null,
  customer_id uuid references customers(id) on delete set null,
  address_id uuid references addresses(id) on delete set null,
  driver_id uuid references drivers(id) on delete set null,
  status text default 'pending' check (status in ('pending','preparing','out_for_delivery','delivered','cancelled')),
  total numeric(10,2) not null default 0,
  delivery_fee numeric(10,2) default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ORDER_ITEMS
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade not null,
  product_id uuid references products(id) on delete restrict not null,
  quantity int not null default 1,
  unit_price numeric(10,2) not null
);

-- DRIVER_LOCATIONS (live GPS tracking via driver's phone)
create table driver_locations (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid references drivers(id) on delete cascade not null,
  order_id uuid references orders(id) on delete cascade,
  lat numeric(9,6) not null,
  lng numeric(9,6) not null,
  updated_at timestamptz default now()
);

-- STORE_ADMINS (dashboard access per store, linked to auth.users)
create table store_admins (
  id uuid primary key default gen_random_uuid(),
  store_id uuid references stores(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  role text default 'admin',
  created_at timestamptz default now(),
  unique(store_id, user_id)
);

-- CALL_REQUESTS (voice/video/chat with employee)
create table call_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade,
  store_id uuid references stores(id) on delete cascade not null,
  customer_id uuid references customers(id) on delete cascade,
  type text not null check (type in ('voice','video','chat')),
  status text default 'requested' check (status in ('requested','active','ended','missed')),
  created_at timestamptz default now()
);

-- Indexes for common lookups
create index idx_products_store on products(store_id);
create index idx_categories_store on categories(store_id);
create index idx_orders_store on orders(store_id);
create index idx_orders_customer on orders(customer_id);
create index idx_driver_locations_order on driver_locations(order_id);
create index idx_store_admins_user on store_admins(user_id);
