-- Altayebat taxonomy cleanup
-- Date: 2026-09-14
-- Non-destructive: deactivate the empty duplicate category only when it has no references.

update public.categories
set is_active=false,
    updated_at=now()
where id='c33c0c29-48ba-4903-a50a-5d0c5ba667b5'
  and name='ألبان'
  and is_active=true
  and not exists (
    select 1 from public.products
    where category_id='c33c0c29-48ba-4903-a50a-5d0c5ba667b5'
  )
  and not exists (
    select 1 from public.categories
    where parent_id='c33c0c29-48ba-4903-a50a-5d0c5ba667b5'
  )
  and not exists (
    select 1 from public.customer_store_stats
    where favorite_category_id='c33c0c29-48ba-4903-a50a-5d0c5ba667b5'
  );
