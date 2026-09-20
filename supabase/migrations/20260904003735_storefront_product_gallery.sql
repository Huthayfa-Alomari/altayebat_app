create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  url text not null,
  alt_text text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_product_images_product_sort on public.product_images(product_id,sort_order,id);
alter table public.product_images enable row level security;
drop policy if exists "Catalog product images are visible" on public.product_images;
create policy "Catalog product images are visible" on public.product_images for select to authenticated
using (exists(select 1 from public.products p where p.id=product_id and (p.is_available=true or private.is_store_admin(p.store_id))));
drop policy if exists "Store admins manage product images" on public.product_images;
create policy "Store admins manage product images" on public.product_images for all to authenticated
using (exists(select 1 from public.products p where p.id=product_id and private.is_store_admin(p.store_id)))
with check (exists(select 1 from public.products p where p.id=product_id and private.is_store_admin(p.store_id)));
grant select,insert,update,delete on public.product_images to authenticated;

insert into public.product_images(product_id,url,alt_text,sort_order)
select p.id,p.image_url,p.name,0
from public.products p
where p.image_url is not null and btrim(p.image_url)<>''
  and not exists(select 1 from public.product_images pi where pi.product_id=p.id and pi.url=p.image_url);

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
), gallery as (
  select pi.id,pi.url,pi.alt_text,pi.sort_order from public.product_images pi where pi.product_id=p_product_id order by pi.sort_order,pi.id
), similar_products as (
  select p.id,p.name,p.price,p.compare_at_price,p.image_url,p.stock_qty,p.unit,p.pack_size
  from public.products p cross join product_row pr
  where p.store_id=pr.store_id and p.id<>pr.id and p.category_id=pr.category_id and p.is_available=true and p.stock_qty>0
  order by abs(p.price-pr.price),p.is_featured desc,p.sort_order,p.name
  limit 12
)
select jsonb_build_object(
  'product',(select to_jsonb(pr) from product_row pr),
  'images',coalesce((select jsonb_agg(to_jsonb(g) order by g.sort_order,g.id) from gallery g),'[]'::jsonb),
  'similar',coalesce((select jsonb_agg(to_jsonb(sp)) from similar_products sp),'[]'::jsonb)
);
$$;
revoke all on function public.get_product_detail(uuid) from public,anon;
grant execute on function public.get_product_detail(uuid) to authenticated;
