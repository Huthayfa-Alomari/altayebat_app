-- Benchmark v2 internet image fallback mapping.
-- Exact brand/product images should override these URLs when available.
-- These are external hotlinks and should ultimately be replaced with supplier/manufacturer-owned assets.

with image_map(category_name, image_url) as (
  values
  ('أرز','https://images.deliveryhero.io/image/product-information-management/67a362ade9324bb1b64f1962.jpg'),
  ('أكياس نفايات','https://talabat.dhmedia.io/image/darkstores-jo/Jordan%20Items/JOR-6253501690032.jpg'),
  ('بيض','https://qc-products-images.s3.ap-south-1.amazonaws.com/optimized-images/optimized_e174eddf-e117-4474-a5c5-8a3a3e3dc0cc.jpeg'),
  ('حليب','https://doos-cdn-v2.imgix.net/oqc4shfik64vgmbqaepm9kusklut'),
  ('خضار','https://cyprus-faq.com/site/assets/files/19850/img_0112.webp'),
  ('دجاج طازج','https://talabat.dhmedia.io/image/product-information-management/63b294fb7c2c343fff2e9415.JPG'),
  ('عناية أطفال','https://talabat.dhmedia.io/image/talabat-nv/Hero_Images/Final/6253005866070.png?size=520'),
  ('فواكه','https://masaegypt.com/assets/img/products/banana--1-kilo-67bf17d22e3e2.webp'),
  ('معكرونة','https://jebnalak.com/cdn/shop/products/pastazara-spaghetti-3-434690.jpg?v=1621949149'),
  ('منظفات','https://images.deliveryhero.io/image/darkstores-jo/Jordan%20Items/JOR-6253339102615.jpg')
)
update private.catalog_import_staging s
set image_url=m.image_url, updated_at=now()
from image_map m
where s.benchmark_version='Benchmark v2'
  and s.match_status='APPROVED_NEW'
  and s.category_name=m.category_name
  and s.image_url is null;

update public.products p
set image_url=s.image_url, updated_at=now()
from private.catalog_import_staging s
where s.matched_product_id=p.id
  and s.benchmark_version='Benchmark v2'
  and s.match_status='APPROVED_NEW'
  and s.image_url is not null;
