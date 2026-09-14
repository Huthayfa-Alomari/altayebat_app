-- Altayebat catalog completion validation
-- Date: 2026-09-14

select
  count(*) as live_products,
  count(*) filter (where sku is null) as missing_sku,
  count(*) filter (where barcode is null) as missing_barcode,
  count(*) filter (where brand_id is not null) as branded_products
from public.products;

select count(*) as brands_total from public.brands;

select
  count(*) as benchmark_candidates,
  count(*) filter (where stock_qty=0 and is_available=false and altayebat_price_jod is null) as safe_staging_rows
from private.catalog_import_staging
where benchmark_version='Benchmark v2';

select match_status, review_status, count(*) as candidate_count
from private.catalog_import_staging
where benchmark_version='Benchmark v2'
group by match_status, review_status
order by match_status, review_status;

select id,name,is_active
from public.categories
where name in ('ألبان','الألبان والأجبان')
order by name;
