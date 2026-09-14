-- Altayebat Benchmark v2 classification
-- Date: 2026-09-14
-- Scope: staging only. Does not publish, delete, or modify live products.

begin;

with s as (
  select id as store_id
  from public.stores
  where name='أسواق الطيبات'
  order by created_at
  limit 1
)
update private.catalog_import_staging
set match_status='APPROVED_NEW',
    matched_product_id=null,
    review_status='READY_FOR_PROCUREMENT_REVIEW',
    notes='New benchmark candidate. Keep inactive until Altayebat selling price, barcode, actual stock, and image rights are verified.',
    updated_at=now()
where store_id=(select store_id from s)
  and benchmark_version='Benchmark v2';

-- Competitor private-label products stay reference-only.
with s as (
  select id as store_id
  from public.stores
  where name='أسواق الطيبات'
  order by created_at
  limit 1
)
update private.catalog_import_staging
set match_status='REJECTED',
    matched_product_id=null,
    review_status='DO_NOT_IMPORT',
    notes='Competitor private-label item (Talabat). Keep for benchmark/reference only; do not source as an Altayebat catalog item.',
    updated_at=now()
where store_id=(select store_id from s)
  and benchmark_version='Benchmark v2'
  and lower(trim(coalesce(brand_text,'')))='talabat';

-- Confirmed existing Altayebat product matches.
with matches(candidate_id, product_id) as (
  values
    (3,  'c6c1f042-1531-4f1c-85ea-0c2e170b3a6e'::uuid),
    (9,  '4bcace04-55bb-466b-a2af-9abd2d29cc23'::uuid),
    (10, '7b302b3b-9e20-4353-aa02-c2e03a003e13'::uuid),
    (15, 'b6f39e0c-6a1c-4d3d-8315-d0ca663bc989'::uuid),
    (35, 'a69e1b44-fa3a-49c5-b02b-871c168411cc'::uuid),
    (37, '6a6065c2-6b16-4e83-883c-7db1268ba5a2'::uuid)
), s as (
  select id as store_id
  from public.stores
  where name='أسواق الطيبات'
  order by created_at
  limit 1
)
update private.catalog_import_staging c
set match_status='CONFIRMED_DUPLICATE',
    matched_product_id=m.product_id,
    review_status='DO_NOT_IMPORT_DUPLICATE',
    notes='Confirmed existing Altayebat SKU/pack match. Do not import a second product; competitor price remains reference-only.',
    updated_at=now()
from matches m
where c.store_id=(select store_id from s)
  and c.benchmark_version='Benchmark v2'
  and c.candidate_id=m.candidate_id;

-- Similar existing products requiring barcode/variant verification.
with matches(candidate_id, product_id, reason) as (
  values
    (11,  'f626e748-31e0-473f-a433-8f026e3452cf'::uuid, 'Brand and 4kg pack align, but benchmark generic Rice vs live Basmati; manual verification required.'),
    (231, '711b81fe-f164-4922-9eab-dff056168f87'::uuid, 'Alyoum 1kg yoghurt/baladi naming is close; verify exact SKU/barcode before dedupe.'),
    (232, '90ef366e-f704-4e24-b4d7-9ffb7a78f606'::uuid, 'Alyoum 1kg yoghurt naming is close; verify exact SKU/barcode before dedupe.'),
    (319, '7613f68c-47b2-474b-8c0b-961d14e31492'::uuid, 'Ariel 3kg exists live, but benchmark specifies Downy variant; verify exact variant/barcode.')
), s as (
  select id as store_id
  from public.stores
  where name='أسواق الطيبات'
  order by created_at
  limit 1
)
update private.catalog_import_staging c
set match_status='POSSIBLE_MATCH',
    matched_product_id=m.product_id,
    review_status='MANUAL_REVIEW',
    notes=m.reason,
    updated_at=now()
from matches m
where c.store_id=(select store_id from s)
  and c.benchmark_version='Benchmark v2'
  and c.candidate_id=m.candidate_id;

commit;
