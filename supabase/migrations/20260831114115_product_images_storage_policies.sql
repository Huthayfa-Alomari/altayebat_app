drop policy if exists altayebat_product_images_insert on storage.objects;
drop policy if exists altayebat_product_images_update on storage.objects;
drop policy if exists altayebat_product_images_delete on storage.objects;

create policy altayebat_product_images_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and exists (
    select 1
    from public.store_admins sa
    where sa.user_id = (select auth.uid())
      and sa.store_id::text = (storage.foldername(name))[1]
  )
);

create policy altayebat_product_images_update
on storage.objects
for update
to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1
    from public.store_admins sa
    where sa.user_id = (select auth.uid())
      and sa.store_id::text = (storage.foldername(name))[1]
  )
)
with check (
  bucket_id = 'product-images'
  and exists (
    select 1
    from public.store_admins sa
    where sa.user_id = (select auth.uid())
      and sa.store_id::text = (storage.foldername(name))[1]
  )
);

create policy altayebat_product_images_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'product-images'
  and exists (
    select 1
    from public.store_admins sa
    where sa.user_id = (select auth.uid())
      and sa.store_id::text = (storage.foldername(name))[1]
  )
);
