create table if not exists private.retail_benchmark_sources (
  slug text primary key,
  name text not null,
  website_url text not null,
  channel text not null default 'online_catalog',
  country_code text not null default 'JO',
  image_policy text not null default 'reference_only'
    check (image_policy in ('reference_only','licensed','official_brand')),
  active boolean not null default true,
  last_verified_at timestamptz,
  notes text
);

create table if not exists private.retail_benchmark_observations (
  id bigint generated always as identity primary key,
  source_slug text not null
    references private.retail_benchmark_sources(slug) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  barcode text,
  external_name text not null,
  external_price_jod numeric(12,3),
  external_url text not null,
  external_image_url text,
  exact_barcode_match boolean not null default false,
  image_usage_status text not null default 'reference_only'
    check (image_usage_status in ('reference_only','approved','unknown')),
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create unique index if not exists retail_benchmark_observation_unique
  on private.retail_benchmark_observations
  (source_slug, store_id, coalesce(barcode,''), external_url);

create index if not exists retail_benchmark_observations_product_idx
  on private.retail_benchmark_observations (store_id, product_id, observed_at desc);

revoke all on private.retail_benchmark_sources
  from public, anon, authenticated;
revoke all on private.retail_benchmark_observations
  from public, anon, authenticated;

insert into private.retail_benchmark_sources
  (slug,name,website_url,channel,image_policy,last_verified_at,notes)
values
  ('hypermax','HyperMax Jordan','https://www.hypermax.com.jo/mafjor/en','online_catalog','reference_only',now(),'Major Jordan hypermarket catalog; groceries, fresh food, household, electronics and more.'),
  ('cozmo','Cozmo','https://cozmo.jo/','online_catalog','reference_only',now(),'Large Amman supermarket catalog with SKU/barcode exposed on many product pages.'),
  ('safeway_jo','Safeway Jordan','https://www.safeway.com.jo/','online_catalog','reference_only',now(),'Jordan grocery catalog and category benchmark.'),
  ('ctown','C-Town Jordan','https://play.google.com/store/apps/details?id=jo.ctown.ecom','app_catalog','reference_only',now(),'Jordan grocery and supermarket app benchmark.'),
  ('sameh_mall','Sameh Mall','https://www.talabat.com/jordan/sameh-malltabarbour','marketplace_catalog','reference_only',now(),'Jordan hypermarket presence; public marketplace catalog used for assortment comparison.'),
  ('centro','Centro','https://www.talabat.com/jordan/centro','marketplace_catalog','reference_only',now(),'Jordan supermarket presence; public marketplace catalog used for assortment comparison.'),
  ('miles','Miles','https://www.miles.com.jo/','online_catalog','reference_only',now(),'Jordan supermarket catalog benchmark.'),
  ('talabat_mart','Talabat Mart Jordan','https://www.talabat.com/jordan/tmart','online_catalog','reference_only',now(),'Fast grocery benchmark with broad category coverage.'),
  ('familys_basket','Family''s Basket','https://www.talabat.com/jordan/familys-basket','marketplace_catalog','reference_only',now(),'Jordan supermarket marketplace listing; reference-only.'),
  ('yaser_mall','Yaser Mall','https://www.yasermallonline.com/','online_catalog','reference_only',now(),'Jordan online grocery catalog; 30,000+ products advertised in current app listing.'),
  ('jcscc','المؤسسة الاستهلاكية المدنية','https://jcsccshop.gov.jo/','online_catalog','reference_only',now(),'Official civil consumer establishment online market and price benchmark.'),
  ('mce','المؤسسة الاستهلاكية العسكرية','https://mce.jaf.mil.jo/','official_catalog','reference_only',now(),'Official military consumer establishment; broad national retail and price benchmark.'),
  ('city_stores','City Stores','https://www.talabat.com/jordan/city-stores','marketplace_catalog','reference_only',now(),'Jordan supermarket marketplace catalog.'),
  ('golden_basket','Golden Basket','https://www.talabat.com/jordan/golden-basket','marketplace_catalog','reference_only',now(),'Jordan hypermarket and fresh-food marketplace catalog.'),
  ('gourmet_grocery','Gourmet Grocery Supermarket','https://www.talabat.com/jordan/gourmet-grocery-supermarket','marketplace_catalog','reference_only',now(),'Jordan supermarket marketplace catalog.')
on conflict (slug) do update
set name=excluded.name,
    website_url=excluded.website_url,
    channel=excluded.channel,
    image_policy=excluded.image_policy,
    active=true,
    last_verified_at=excluded.last_verified_at,
    notes=excluded.notes;

with obs(barcode, external_name, price, url) as (values
  ('6281048105580','Puck Triangles Cheese 120g - 8 pieces',1.000::numeric,'https://cozmo.jo/dairy-eggs-butter/cheese/cheese-portion-snacks/puck-triangles-cheese-120g-8-pieces'),
  ('5711953128530','Puck Shredded Mozzarella Cheese 200g',1.690::numeric,'https://cozmo.jo/dairy-eggs-butter/cheese/mozzarella-cheese/puck-shredded-mozzarella-cheese-200g'),
  ('5711953031144','Puck Feta Cheese Cubes 200g',1.890::numeric,'https://cozmo.jo/dairy-eggs-butter/cheese/feta-cheese/puck-feta-cheese-cubes-200g'),
  ('5711953022869','Puck Feta Cheese 500g',2.950::numeric,'https://cozmo.jo/dairy-eggs-butter/cheese/feta-cheese/puck-feta-cheese-500g'),
  ('6287034100805','Kinza Orange Carbonated Drink Can 320ml',0.350::numeric,'https://cozmo.jo/tea-coffee-soft-drinks/soft-drinks/fizzy-drinks/kinza-orange-carbonated-drink-can-320ml'),
  ('6287034100904','Kinza Cocktail Carbonated Drink Can 250ml',0.500::numeric,'https://cozmo.jo/tea-coffee-soft-drinks/soft-drinks/fizzy-drinks/kinza-cocktail-carbonated-drink-can-250ml'),
  ('6251040000558','Hala Chips Zoom Chili 22g',0.100::numeric,'https://cozmo.jo/productShare/91395'),
  ('6281022102055','Danette Chocolate Dessert 90g',0.450::numeric,'https://cozmo.jo/dairy-eggs-butter/yoghurt/puddings/danette-chocolate-dessert-90g'),
  ('6281034907754','Vimto Fruit Flavoured Drink 125ml',0.200::numeric,'https://cozmo.jo/tea-coffee-soft-drinks/juices/long-life-juices/vimto-fruit-flavoured-drink-125ml'),
  ('6281007070461','Almarai UHT Nijoom Chocolate Flavored Milk 6x150ml',1.150::numeric,'https://cozmo.jo/dairy-eggs-butter/milk/flavoured-milk/almarai-uht-nijoom-chocolate-flavored-milk-6x150ml'),
  ('6291069701272','Dabur Vatika Volume & Thickness Shampoo 400ml',2.300::numeric,'https://cozmo.jo/personal-care/hair-care/dabur-vatika-volume-thickness-shampoo-with-coconut-castor-400ml')
)
insert into private.retail_benchmark_observations
  (source_slug,store_id,product_id,barcode,external_name,external_price_jod,external_url,exact_barcode_match,image_usage_status,metadata)
select
  'cozmo',
  '61e6f35d-7004-4a33-948c-b297ba446678'::uuid,
  p.id,
  o.barcode,
  o.external_name,
  o.price,
  o.url,
  p.id is not null,
  'reference_only',
  jsonb_build_object('capture','public_catalog','captured_on','2026-09-22')
from obs o
left join public.products p
  on p.store_id='61e6f35d-7004-4a33-948c-b297ba446678'::uuid
 and p.is_available=true
 and regexp_replace(coalesce(p.barcode,''),'\D','','g')=o.barcode
on conflict do nothing;
