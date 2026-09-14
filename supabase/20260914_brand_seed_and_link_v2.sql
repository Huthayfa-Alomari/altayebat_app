-- Altayebat verified brand seed/link v2
-- Date: 2026-09-14
-- Non-destructive: adds only explicit, unambiguous brands found in current product names.

begin;

with brand_map(alias, canonical, slug) as (
  values
    ('شيخ الكار','شيخ الكار','sheikh-al-kar'),
    ('صانسيلك','صانسيلك','sunsilk'),
    ('صنسيلك','صانسيلك','sunsilk'),
    ('ادييس','أدييس','adies'),
    ('أدييس','أدييس','adies'),
    ('أمريكان جورميه','أمريكان جورميه','american-gourmet'),
    ('الوردة','الوردة','al-warda'),
    ('بانتين','بانتين','pantene'),
    ('جوهر','جوهر','jawhar'),
    ('سيجنال','سيجنال','signal'),
    ('شيف ويست','شيف ويست','chef-west'),
    ('كلير','كلير','clear'),
    ('هيد آند شولدرز','هيد آند شولدرز','head-and-shoulders')
), matched_brands as (
  select distinct p.store_id, bm.canonical, bm.slug
  from public.products p
  join brand_map bm on strpos(lower(p.name), lower(bm.alias)) > 0
)
insert into public.brands(store_id,name,slug,is_active,sort_order)
select mb.store_id, mb.canonical, mb.slug, true, 0
from matched_brands mb
where not exists (
  select 1 from public.brands b
  where b.store_id=mb.store_id and b.slug=mb.slug
);

with brand_map(alias, canonical, slug) as (
  values
    ('شيخ الكار','شيخ الكار','sheikh-al-kar'),
    ('صانسيلك','صانسيلك','sunsilk'),
    ('صنسيلك','صانسيلك','sunsilk'),
    ('ادييس','أدييس','adies'),
    ('أدييس','أدييس','adies'),
    ('أمريكان جورميه','أمريكان جورميه','american-gourmet'),
    ('الوردة','الوردة','al-warda'),
    ('بانتين','بانتين','pantene'),
    ('جوهر','جوهر','jawhar'),
    ('سيجنال','سيجنال','signal'),
    ('شيف ويست','شيف ويست','chef-west'),
    ('كلير','كلير','clear'),
    ('هيد آند شولدرز','هيد آند شولدرز','head-and-shoulders')
), candidate_matches as (
  select p.id as product_id, p.store_id, bm.slug
  from public.products p
  join brand_map bm on strpos(lower(p.name), lower(bm.alias)) > 0
  where p.brand_id is null
), unambiguous as (
  select product_id, store_id, min(slug) as slug
  from candidate_matches
  group by product_id, store_id
  having count(distinct slug)=1
)
update public.products p
set brand_id=b.id,
    updated_at=now()
from unambiguous u
join public.brands b on b.store_id=u.store_id and b.slug=u.slug
where p.id=u.product_id and p.brand_id is null;

commit;
