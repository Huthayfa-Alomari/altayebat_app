-- Altayebat production performance hardening
--
-- Safe, behavior-preserving fixes for Supabase Database Advisor findings:
--   * cover foreign keys used by cascades/lookups
--   * avoid per-row auth.uid() init plans
--   * remove duplicate permissive SELECT policies caused by admin FOR ALL rules

begin;

-- ---------------------------------------------------------------------------
-- Foreign-key coverage
-- ---------------------------------------------------------------------------
create index if not exists idx_categories_parent_id
  on public.categories (parent_id)
  where parent_id is not null;

create index if not exists idx_products_brand_id
  on public.products (brand_id)
  where brand_id is not null;

-- ---------------------------------------------------------------------------
-- RLS init-plan optimization. Using (select auth.uid()) evaluates the session
-- identity once per statement instead of once per candidate row.
-- ---------------------------------------------------------------------------
drop policy if exists "Customers manage favorites" on public.favorites;
create policy "Customers manage favorites"
on public.favorites
for all
to authenticated
using (customer_id = (select auth.uid()))
with check (customer_id = (select auth.uid()));

drop policy if exists "Customers manage shopping lists" on public.shopping_lists;
create policy "Customers manage shopping lists"
on public.shopping_lists
for all
to authenticated
using (customer_id = (select auth.uid()))
with check (customer_id = (select auth.uid()));

drop policy if exists "Customers manage shopping list items" on public.shopping_list_items;
create policy "Customers manage shopping list items"
on public.shopping_list_items
for all
to authenticated
using (
  exists (
    select 1
    from public.shopping_lists l
    where l.id = shopping_list_items.list_id
      and l.customer_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.shopping_lists l
    where l.id = shopping_list_items.list_id
      and l.customer_id = (select auth.uid())
  )
);

-- ---------------------------------------------------------------------------
-- Split admin FOR ALL policies into write-only policies. Catalog/customer
-- SELECT policies already include the required admin visibility, so this
-- removes duplicate permissive SELECT evaluation without narrowing access.
-- ---------------------------------------------------------------------------

-- Brands: catalog SELECT already includes private.is_store_admin(store_id).
drop policy if exists "Store admins manage brands" on public.brands;
drop policy if exists "Store admins insert brands" on public.brands;
drop policy if exists "Store admins update brands" on public.brands;
drop policy if exists "Store admins delete brands" on public.brands;
create policy "Store admins insert brands"
on public.brands for insert to authenticated
with check (private.is_store_admin(store_id));
create policy "Store admins update brands"
on public.brands for update to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));
create policy "Store admins delete brands"
on public.brands for delete to authenticated
using (private.is_store_admin(store_id));

-- Product images: catalog SELECT already allows images for available products
-- and all images belonging to a store admin's store.
drop policy if exists "Store admins manage product images" on public.product_images;
drop policy if exists "Store admins insert product images" on public.product_images;
drop policy if exists "Store admins update product images" on public.product_images;
drop policy if exists "Store admins delete product images" on public.product_images;
create policy "Store admins insert product images"
on public.product_images for insert to authenticated
with check (
  exists (
    select 1 from public.products p
    where p.id = product_images.product_id
      and private.is_store_admin(p.store_id)
  )
);
create policy "Store admins update product images"
on public.product_images for update to authenticated
using (
  exists (
    select 1 from public.products p
    where p.id = product_images.product_id
      and private.is_store_admin(p.store_id)
  )
)
with check (
  exists (
    select 1 from public.products p
    where p.id = product_images.product_id
      and private.is_store_admin(p.store_id)
  )
);
create policy "Store admins delete product images"
on public.product_images for delete to authenticated
using (
  exists (
    select 1 from public.products p
    where p.id = product_images.product_id
      and private.is_store_admin(p.store_id)
  )
);

-- Storefront banners: catalog SELECT already includes admins for inactive or
-- out-of-window banners.
drop policy if exists "Store admins manage banners" on public.storefront_banners;
drop policy if exists "Store admins insert banners" on public.storefront_banners;
drop policy if exists "Store admins update banners" on public.storefront_banners;
drop policy if exists "Store admins delete banners" on public.storefront_banners;
create policy "Store admins insert banners"
on public.storefront_banners for insert to authenticated
with check (private.is_store_admin(store_id));
create policy "Store admins update banners"
on public.storefront_banners for update to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));
create policy "Store admins delete banners"
on public.storefront_banners for delete to authenticated
using (private.is_store_admin(store_id));

-- Store hours are intentionally readable by all authenticated storefront
-- sessions. Admin policy is only required for writes.
drop policy if exists "Store admins manage store hours" on public.store_hours;
drop policy if exists "Store admins insert store hours" on public.store_hours;
drop policy if exists "Store admins update store hours" on public.store_hours;
drop policy if exists "Store admins delete store hours" on public.store_hours;
create policy "Store admins insert store hours"
on public.store_hours for insert to authenticated
with check (private.is_store_admin(store_id));
create policy "Store admins update store hours"
on public.store_hours for update to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));
create policy "Store admins delete store hours"
on public.store_hours for delete to authenticated
using (private.is_store_admin(store_id));

-- Delivery zones need one small SELECT adjustment: customers keep seeing active
-- zones, while store admins must retain visibility of inactive zones after the
-- admin FOR ALL policy is split into write-only policies.
drop policy if exists "Customers view active delivery zones" on public.delivery_zones;
create policy "Customers view active delivery zones"
on public.delivery_zones for select to authenticated
using (is_active = true or private.is_store_admin(store_id));

drop policy if exists "Store admins manage delivery zones" on public.delivery_zones;
drop policy if exists "Store admins insert delivery zones" on public.delivery_zones;
drop policy if exists "Store admins update delivery zones" on public.delivery_zones;
drop policy if exists "Store admins delete delivery zones" on public.delivery_zones;
create policy "Store admins insert delivery zones"
on public.delivery_zones for insert to authenticated
with check (private.is_store_admin(store_id));
create policy "Store admins update delivery zones"
on public.delivery_zones for update to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));
create policy "Store admins delete delivery zones"
on public.delivery_zones for delete to authenticated
using (private.is_store_admin(store_id));

commit;
