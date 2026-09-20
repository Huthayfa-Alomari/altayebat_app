create extension if not exists pg_trgm with schema extensions;

alter table public.categories
  add column if not exists parent_id uuid references public.categories(id) on delete set null,
  add column if not exists slug text,
  add column if not exists name_en text,
  add column if not exists updated_at timestamptz not null default now();

create index if not exists idx_categories_store_parent_sort
  on public.categories(store_id, parent_id, sort_order, name);
create unique index if not exists uq_categories_store_slug
  on public.categories(store_id, slug) where slug is not null and slug <> '';

create table if not exists public.brands (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  name_en text,
  slug text,
  logo_url text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_brands_store_active_sort on public.brands(store_id,is_active,sort_order,name);
create unique index if not exists uq_brands_store_slug on public.brands(store_id,slug) where slug is not null and slug <> '';

alter table public.products
  add column if not exists brand_id uuid references public.brands(id) on delete set null,
  add column if not exists name_en text,
  add column if not exists sku text,
  add column if not exists pack_size text,
  add column if not exists search_keywords text,
  add column if not exists sort_order integer not null default 0;

create index if not exists idx_products_store_brand on public.products(store_id,brand_id) where is_available = true;
create index if not exists idx_products_store_category_available on public.products(store_id,category_id,is_available,sort_order);
create index if not exists idx_products_name_trgm on public.products using gin (lower(name) extensions.gin_trgm_ops);
create index if not exists idx_products_name_en_trgm on public.products using gin (lower(coalesce(name_en,'')) extensions.gin_trgm_ops);
create index if not exists idx_products_keywords_trgm on public.products using gin (lower(coalesce(search_keywords,'')) extensions.gin_trgm_ops);
create unique index if not exists uq_products_store_barcode on public.products(store_id,barcode) where barcode is not null and btrim(barcode) <> '';
create unique index if not exists uq_products_store_sku on public.products(store_id,sku) where sku is not null and btrim(sku) <> '';

create table if not exists public.storefront_banners (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  title text,
  subtitle text,
  image_url text not null,
  position text not null default 'home',
  target_type text not null default 'none' check (target_type in ('none','product','category','search','url')),
  target_value text,
  sort_order integer not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_storefront_banners_active on public.storefront_banners(store_id,position,is_active,sort_order);

create table if not exists public.favorites (
  customer_id uuid not null references public.customers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(customer_id,product_id)
);
create index if not exists idx_favorites_product on public.favorites(product_id);

create table if not exists public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_shopping_lists_customer on public.shopping_lists(customer_id,updated_at desc);
create unique index if not exists uq_shopping_lists_one_default on public.shopping_lists(customer_id) where is_default = true;

create table if not exists public.shopping_list_items (
  list_id uuid not null references public.shopping_lists(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null default 1 check (quantity > 0 and quantity <= 999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(list_id,product_id)
);
create index if not exists idx_shopping_list_items_product on public.shopping_list_items(product_id);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_categories_updated_at on public.categories;
create trigger trg_categories_updated_at before update on public.categories for each row execute function private.set_updated_at();
drop trigger if exists trg_brands_updated_at on public.brands;
create trigger trg_brands_updated_at before update on public.brands for each row execute function private.set_updated_at();
drop trigger if exists trg_storefront_banners_updated_at on public.storefront_banners;
create trigger trg_storefront_banners_updated_at before update on public.storefront_banners for each row execute function private.set_updated_at();
drop trigger if exists trg_shopping_lists_updated_at on public.shopping_lists;
create trigger trg_shopping_lists_updated_at before update on public.shopping_lists for each row execute function private.set_updated_at();
drop trigger if exists trg_shopping_list_items_updated_at on public.shopping_list_items;
create trigger trg_shopping_list_items_updated_at before update on public.shopping_list_items for each row execute function private.set_updated_at();

alter table public.brands enable row level security;
alter table public.storefront_banners enable row level security;
alter table public.favorites enable row level security;
alter table public.shopping_lists enable row level security;
alter table public.shopping_list_items enable row level security;

drop policy if exists "Catalog brands are visible" on public.brands;
create policy "Catalog brands are visible" on public.brands for select to authenticated
using (is_active or private.is_store_admin(store_id));
drop policy if exists "Store admins manage brands" on public.brands;
create policy "Store admins manage brands" on public.brands for all to authenticated
using (private.is_store_admin(store_id)) with check (private.is_store_admin(store_id));

drop policy if exists "Catalog banners are visible" on public.storefront_banners;
create policy "Catalog banners are visible" on public.storefront_banners for select to authenticated
using ((is_active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())) or private.is_store_admin(store_id));
drop policy if exists "Store admins manage banners" on public.storefront_banners;
create policy "Store admins manage banners" on public.storefront_banners for all to authenticated
using (private.is_store_admin(store_id)) with check (private.is_store_admin(store_id));

drop policy if exists "Customers manage favorites" on public.favorites;
create policy "Customers manage favorites" on public.favorites for all to authenticated
using (customer_id = auth.uid()) with check (customer_id = auth.uid());

drop policy if exists "Customers manage shopping lists" on public.shopping_lists;
create policy "Customers manage shopping lists" on public.shopping_lists for all to authenticated
using (customer_id = auth.uid()) with check (customer_id = auth.uid());

drop policy if exists "Customers manage shopping list items" on public.shopping_list_items;
create policy "Customers manage shopping list items" on public.shopping_list_items for all to authenticated
using (exists(select 1 from public.shopping_lists l where l.id=list_id and l.customer_id=auth.uid()))
with check (exists(select 1 from public.shopping_lists l where l.id=list_id and l.customer_id=auth.uid()));

grant select,insert,update,delete on public.brands to authenticated;
grant select,insert,update,delete on public.storefront_banners to authenticated;
grant select,insert,update,delete on public.favorites to authenticated;
grant select,insert,update,delete on public.shopping_lists to authenticated;
grant select,insert,update,delete on public.shopping_list_items to authenticated;

create or replace function public.get_category_tree(p_store_id uuid)
returns table(id uuid,parent_id uuid,name text,name_en text,image_url text,slug text,sort_order integer,depth integer)
language sql
stable
set search_path=''
as $$
with recursive tree as (
  select c.id,c.parent_id,c.name,c.name_en,c.image_url,c.slug,c.sort_order,0 as depth
  from public.categories c
  where c.store_id=p_store_id and c.parent_id is null and coalesce(c.is_active,true)=true
  union all
  select c.id,c.parent_id,c.name,c.name_en,c.image_url,c.slug,c.sort_order,t.depth+1
  from public.categories c
  join tree t on c.parent_id=t.id
  where c.store_id=p_store_id and coalesce(c.is_active,true)=true and t.depth < 5
)
select * from tree order by depth,sort_order,name;
$$;
revoke all on function public.get_category_tree(uuid) from public,anon;
grant execute on function public.get_category_tree(uuid) to authenticated;

create or replace function public.catalog_search(
  p_store_id uuid,
  p_query text default null,
  p_category_id uuid default null,
  p_brand_ids uuid[] default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_only_deals boolean default false,
  p_sort text default 'relevance',
  p_limit integer default 40,
  p_offset integer default 0
)
returns table(
  id uuid,name text,name_en text,description text,price numeric,compare_at_price numeric,image_url text,
  stock_qty integer,unit text,pack_size text,barcode text,category_id uuid,brand_id uuid,brand_name text,
  is_featured boolean,sales_30d bigint
)
language sql
stable
set search_path=''
as $$
with recursive category_scope as (
  select p_category_id as id where p_category_id is not null
  union all
  select c.id from public.categories c join category_scope s on c.parent_id=s.id where c.store_id=p_store_id
), sales as (
  select oi.product_id,coalesce(sum(oi.quantity),0)::bigint sales_30d
  from public.order_items oi
  join public.orders o on o.id=oi.order_id
  where o.store_id=p_store_id and o.created_at >= now()-interval '30 days' and o.status <> 'cancelled'
  group by oi.product_id
), base as (
  select p.*,b.name brand_name,coalesce(s.sales_30d,0) sales_30d,
    case when nullif(btrim(coalesce(p_query,'')),'') is null then 0::real
         else greatest(
           extensions.similarity(lower(p.name),lower(p_query)),
           extensions.similarity(lower(coalesce(p.name_en,'')),lower(p_query)),
           extensions.similarity(lower(coalesce(p.search_keywords,'')),lower(p_query))
         ) end as relevance
  from public.products p
  left join public.brands b on b.id=p.brand_id
  left join sales s on s.product_id=p.id
  where p.store_id=p_store_id
    and coalesce(p.is_available,false)=true
    and coalesce(p.stock_qty,0)>0
    and (p_category_id is null or p.category_id in (select id from category_scope))
    and (p_brand_ids is null or cardinality(p_brand_ids)=0 or p.brand_id=any(p_brand_ids))
    and (p_min_price is null or p.price>=p_min_price)
    and (p_max_price is null or p.price<=p_max_price)
    and (not p_only_deals or (p.compare_at_price is not null and p.compare_at_price>p.price))
    and (
      nullif(btrim(coalesce(p_query,'')),'') is null
      or p.barcode=p_query
      or p.sku=p_query
      or lower(p.name) like '%'||lower(p_query)||'%'
      or lower(coalesce(p.name_en,'')) like '%'||lower(p_query)||'%'
      or lower(coalesce(p.search_keywords,'')) like '%'||lower(p_query)||'%'
      or extensions.similarity(lower(p.name),lower(p_query)) > 0.20
    )
)
select b.id,b.name,b.name_en,b.description,b.price,b.compare_at_price,b.image_url,b.stock_qty,b.unit,b.pack_size,b.barcode,
       b.category_id,b.brand_id,b.brand_name,b.is_featured,b.sales_30d
from base b
order by
  case when p_sort='price_asc' then b.price end asc,
  case when p_sort='price_desc' then b.price end desc,
  case when p_sort='newest' then b.created_at end desc,
  case when p_sort='bestselling' then b.sales_30d end desc,
  case when p_sort='relevance' then b.relevance end desc,
  b.is_featured desc,b.sort_order asc,b.name asc
limit greatest(1,least(coalesce(p_limit,40),100))
offset greatest(0,coalesce(p_offset,0));
$$;
revoke all on function public.catalog_search(uuid,text,uuid,uuid[],numeric,numeric,boolean,text,integer,integer) from public,anon;
grant execute on function public.catalog_search(uuid,text,uuid,uuid[],numeric,numeric,boolean,text,integer,integer) to authenticated;

create or replace function public.get_home_feed(p_store_id uuid)
returns jsonb
language sql
stable
set search_path=''
as $$
select jsonb_build_object(
  'store',(select to_jsonb(s) - 'cliq_alias' - 'cliq_recipient_name' from public.stores s where s.id=p_store_id and s.is_active=true),
  'banners',coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order) from (
    select id,title,subtitle,image_url,target_type,target_value,sort_order
    from public.storefront_banners
    where store_id=p_store_id and position='home' and is_active=true
      and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())
    order by sort_order limit 10
  ) x),'[]'::jsonb),
  'categories',coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order,x.name) from (
    select id,name,name_en,image_url,slug,sort_order
    from public.categories
    where store_id=p_store_id and parent_id is null and coalesce(is_active,true)=true
    order by sort_order,name limit 16
  ) x),'[]'::jsonb),
  'featured',coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order,x.name) from (
    select p.id,p.name,p.name_en,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.unit,p.pack_size,p.category_id,p.brand_id,p.sort_order
    from public.products p
    where p.store_id=p_store_id and p.is_featured=true and p.is_available=true and p.stock_qty>0
    order by p.sort_order,p.name limit 20
  ) x),'[]'::jsonb),
  'deals',coalesce((select jsonb_agg(to_jsonb(x) order by ((x.compare_at_price-x.price)/nullif(x.compare_at_price,0)) desc) from (
    select p.id,p.name,p.name_en,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.unit,p.pack_size,p.category_id,p.brand_id
    from public.products p
    where p.store_id=p_store_id and p.is_available=true and p.stock_qty>0 and p.compare_at_price is not null and p.compare_at_price>p.price
    limit 20
  ) x),'[]'::jsonb),
  'best_sellers',coalesce((select jsonb_agg(to_jsonb(x) order by x.sales_30d desc) from (
    select p.id,p.name,p.name_en,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.unit,p.pack_size,p.category_id,p.brand_id,
           sum(oi.quantity)::bigint sales_30d
    from public.order_items oi join public.orders o on o.id=oi.order_id join public.products p on p.id=oi.product_id
    where o.store_id=p_store_id and o.created_at>=now()-interval '30 days' and o.status<>'cancelled' and p.is_available=true and p.stock_qty>0
    group by p.id order by sales_30d desc limit 20
  ) x),'[]'::jsonb),
  'buy_again',coalesce((select jsonb_agg(to_jsonb(x) order by x.last_bought desc) from (
    select p.id,p.name,p.name_en,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.unit,p.pack_size,p.category_id,p.brand_id,
           max(o.created_at) last_bought,sum(oi.quantity)::bigint times_qty
    from public.order_items oi join public.orders o on o.id=oi.order_id join public.products p on p.id=oi.product_id
    where o.store_id=p_store_id and o.customer_id=auth.uid() and o.status='delivered' and p.is_available=true and p.stock_qty>0
    group by p.id order by last_bought desc limit 20
  ) x),'[]'::jsonb)
);
$$;
revoke all on function public.get_home_feed(uuid) from public,anon;
grant execute on function public.get_home_feed(uuid) to authenticated;

create or replace function public.get_reorder_items(p_order_id uuid)
returns table(product_id uuid,name text,image_url text,requested_quantity integer,current_price numeric,stock_qty integer,is_available boolean)
language sql
stable
set search_path=''
as $$
select p.id,p.name,p.image_url,oi.quantity,p.price,p.stock_qty,
       (coalesce(p.is_available,false) and coalesce(p.stock_qty,0)>0)
from public.orders o
join public.order_items oi on oi.order_id=o.id
join public.products p on p.id=oi.product_id
where o.id=p_order_id and o.customer_id=auth.uid()
order by oi.id;
$$;
revoke all on function public.get_reorder_items(uuid) from public,anon;
grant execute on function public.get_reorder_items(uuid) to authenticated;
