begin;

with wanted(name, relative_order) as (
  values
    ('مكسرات'::text, 1),
    ('قهوة'::text, 2),
    ('ألبان'::text, 3)
), base_order as (
  select coalesce(max(sort_order), 0) as max_order
  from public.categories
  where store_id = '61e6f35d-7004-4a33-948c-b297ba446678'::uuid
)
insert into public.categories (id, store_id, name, sort_order, is_active)
select
  gen_random_uuid(),
  '61e6f35d-7004-4a33-948c-b297ba446678'::uuid,
  w.name,
  b.max_order + w.relative_order,
  true
from wanted w
cross join base_order b
where not exists (
  select 1
  from public.categories c
  where c.store_id = '61e6f35d-7004-4a33-948c-b297ba446678'::uuid
    and lower(trim(c.name)) = lower(trim(w.name))
);

-- Classify only uncategorized products, so existing manual assignments are preserved.
update public.products p
set category_id = (
  select c.id
  from public.categories c
  where c.store_id = p.store_id and c.name = 'مكسرات'
  order by c.sort_order
  limit 1
)
where p.store_id = '61e6f35d-7004-4a33-948c-b297ba446678'::uuid
  and p.category_id is null
  and (
    p.name ilike '%مكسر%'
    or p.name ilike '%لوز%'
    or p.name ilike '%كاجو%'
    or p.name ilike '%فستق%'
    or p.name ilike '%بندق%'
    or p.name ilike '%جوز%'
    or p.name ilike '%nuts%'
  );

update public.products p
set category_id = (
  select c.id
  from public.categories c
  where c.store_id = p.store_id and c.name = 'قهوة'
  order by c.sort_order
  limit 1
)
where p.store_id = '61e6f35d-7004-4a33-948c-b297ba446678'::uuid
  and p.category_id is null
  and (
    p.name ilike '%قهوة%'
    or p.name ilike '%نسكافيه%'
    or p.name ilike '%كابتشينو%'
    or p.name ilike '%coffee%'
  );

update public.products p
set category_id = (
  select c.id
  from public.categories c
  where c.store_id = p.store_id and c.name = 'ألبان'
  order by c.sort_order
  limit 1
)
where p.store_id = '61e6f35d-7004-4a33-948c-b297ba446678'::uuid
  and p.category_id is null
  and (
    p.name ilike '%حليب%'
    or p.name ilike '%لبن%'
    or p.name ilike '%لبنة%'
    or p.name ilike '%جبن%'
    or p.name ilike '%زبادي%'
    or p.name ilike '%شنينة%'
    or p.name ilike '%قشطة%'
    or p.name ilike '%milk%'
    or p.name ilike '%yogurt%'
    or p.name ilike '%cheese%'
    or p.name ilike '%dairy%'
  );

commit;
