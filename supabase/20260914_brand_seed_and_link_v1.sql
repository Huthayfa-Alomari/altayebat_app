-- Altayebat verified brand seed/link v1
-- Date: 2026-09-14
-- Scope: non-destructive enrichment only.
-- IMPORTANT:
--   * Does NOT delete products.
--   * Does NOT modify prices, stock, availability, categories, images, barcodes, SKU, or pack_size.
--   * Inserts only curated brand names that are explicitly present in product names.
--   * Links only products with exactly one unambiguous curated brand match.

begin;

with brand_map(alias, canonical, slug) as (
  values
  ('فاتيكا','فاتيكا','vatika'),('لويال','لويال','loyal'),('برسيل','برسيل','persil'),('تايجر','تايجر','tiger'),
  ('عبير','عبير','abeer'),('شعبان','شعبان','shaaban'),('كراشا','كراشا','krasha'),('هايبكس','هايبكس','hypex'),
  ('الدرة','الدرة','al-durra'),('المراعي','المراعي','almarai'),('الوادي','الوادي','al-wadi'),('اليوم','اليوم','alyoum'),
  ('بونو','بونو','bono'),('صنوايت','صنوايت','sunwhite'),('فرح','فرح','farah'),('فلفليهم','فلفليهم','falfelihom'),
  ('فنيش','فنيش','finish'),('أمريكانا','أمريكانا','americana'),('الربيع','الربيع','al-rabie'),('الشميس','الشميس','al-shmeis'),
  ('الضفتين','الضفتين','al-daftain'),('الوطنية','الوطنية','al-watania'),('بوستمان','بوستمان','postman'),
  ('أبو الولد','أبو الولد','abu-al-walad'),('ابو كاس','أبو كاس','abu-kass'),('أبو كاس','أبو كاس','abu-kass'),
  ('ابو راشد','أبو راشد','abu-rashid'),('أبو راشد','أبو راشد','abu-rashid'),('الشعلان','الشعلان','al-shalan'),
  ('كنور','كنور','knorr'),('ماجي','ماجي','maggi'),('بوك','بوك','puck'),('كيري','كيري','kiri'),
  ('لوكس','لوكس','lux'),('أكس','أكس','axe'),('فاين','فاين','fine'),('توينو','توينو','twino'),('سمايل','سمايل','smile'),
  ('سنيورة','سنيورة','siniora'),('نبيل','نبيل','nabil'),('كانزا','كانزا','kanza'),('مايسترو','مايسترو','maestro'),
  ('تي توب','تي توب','t-top'),('سبوبة','سبوبة','saboba'),('بانزاني','بانزاني','panzani'),
  ('بيتي كروكر','بيتي كروكر','betty-crocker'),('حليبنا','حليبنا','halibna'),('خمس بقرات','خمس بقرات','five-cows'),
  ('كيزا','كيزا','kiza'),('كولمار','كولمار','colmar'),('صبا','صبا','saba'),('ميار','ميار','mayar'),
  ('عنجرة','عنجرة','anjara'),('جبل الشيخ','جبل الشيخ','jabal-al-sheikh'),('جولدن','جولدن','golden'),
  ('بيسان','بيسان','beisan'),('نسكافيه','نسكافيه','nescafe')
), matched_brands as (
  select distinct p.store_id, bm.canonical, bm.slug
  from public.products p
  join brand_map bm on strpos(lower(p.name), lower(bm.alias)) > 0
)
insert into public.brands (store_id, name, slug, is_active, sort_order)
select mb.store_id, mb.canonical, mb.slug, true, 0
from matched_brands mb
where not exists (
  select 1
  from public.brands b
  where b.store_id = mb.store_id
    and b.slug = mb.slug
);

with brand_map(alias, canonical, slug) as (
  values
  ('فاتيكا','فاتيكا','vatika'),('لويال','لويال','loyal'),('برسيل','برسيل','persil'),('تايجر','تايجر','tiger'),
  ('عبير','عبير','abeer'),('شعبان','شعبان','shaaban'),('كراشا','كراشا','krasha'),('هايبكس','هايبكس','hypex'),
  ('الدرة','الدرة','al-durra'),('المراعي','المراعي','almarai'),('الوادي','الوادي','al-wadi'),('اليوم','اليوم','alyoum'),
  ('بونو','بونو','bono'),('صنوايت','صنوايت','sunwhite'),('فرح','فرح','farah'),('فلفليهم','فلفليهم','falfelihom'),
  ('فنيش','فنيش','finish'),('أمريكانا','أمريكانا','americana'),('الربيع','الربيع','al-rabie'),('الشميس','الشميس','al-shmeis'),
  ('الضفتين','الضفتين','al-daftain'),('الوطنية','الوطنية','al-watania'),('بوستمان','بوستمان','postman'),
  ('أبو الولد','أبو الولد','abu-al-walad'),('ابو كاس','أبو كاس','abu-kass'),('أبو كاس','أبو كاس','abu-kass'),
  ('ابو راشد','أبو راشد','abu-rashid'),('أبو راشد','أبو راشد','abu-rashid'),('الشعلان','الشعلان','al-shalan'),
  ('كنور','كنور','knorr'),('ماجي','ماجي','maggi'),('بوك','بوك','puck'),('كيري','كيري','kiri'),
  ('لوكس','لوكس','lux'),('أكس','أكس','axe'),('فاين','فاين','fine'),('توينو','توينو','twino'),('سمايل','سمايل','smile'),
  ('سنيورة','سنيورة','siniora'),('نبيل','نبيل','nabil'),('كانزا','كانزا','kanza'),('مايسترو','مايسترو','maestro'),
  ('تي توب','تي توب','t-top'),('سبوبة','سبوبة','saboba'),('بانزاني','بانزاني','panzani'),
  ('بيتي كروكر','بيتي كروكر','betty-crocker'),('حليبنا','حليبنا','halibna'),('خمس بقرات','خمس بقرات','five-cows'),
  ('كيزا','كيزا','kiza'),('كولمار','كولمار','colmar'),('صبا','صبا','saba'),('ميار','ميار','mayar'),
  ('عنجرة','عنجرة','anjara'),('جبل الشيخ','جبل الشيخ','jabal-al-sheikh'),('جولدن','جولدن','golden'),
  ('بيسان','بيسان','beisan'),('نسكافيه','نسكافيه','nescafe')
), product_brand as (
  select p.id, p.store_id, bm.canonical, bm.slug
  from public.products p
  join brand_map bm on strpos(lower(p.name), lower(bm.alias)) > 0
  where p.brand_id is null
  group by p.id, p.store_id, bm.canonical, bm.slug
), unambiguous as (
  select id, store_id, min(slug) as slug
  from product_brand
  group by id, store_id
  having count(*) = 1
)
update public.products p
set brand_id = b.id,
    updated_at = now()
from unambiguous u
join public.brands b
  on b.store_id = u.store_id
 and b.slug = u.slug
where p.id = u.id
  and p.brand_id is null;

commit;

-- Verification summary
select
  (select count(*) from public.brands) as brands_total,
  count(*) filter (where brand_id is not null) as products_with_brand,
  count(*) filter (where brand_id is null) as products_missing_brand,
  count(*) as products_total
from public.products;
