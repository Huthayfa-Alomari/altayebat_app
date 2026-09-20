create table if not exists private.catalog_import_staging (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores(id) on delete cascade,
  benchmark_version text not null,
  candidate_id integer not null,
  priority text not null check (priority in ('P1','P2')),
  category_name text not null,
  brand_text text,
  product_name text not null,
  pack_size text,
  competitor_count integer not null default 0 check (competitor_count >= 0),
  competitors text,
  competitor_min_price_jod numeric(12,3),
  competitor_max_price_jod numeric(12,3),
  source_urls text,
  altayebat_price_jod numeric(12,3),
  stock_qty integer not null default 0 check (stock_qty >= 0),
  is_available boolean not null default false,
  sale_type text not null default 'piece',
  barcode text,
  image_url text,
  review_status text not null default 'REVIEW_BEFORE_IMPORT',
  match_status text not null default 'UNREVIEWED' check (match_status in ('UNREVIEWED','CONFIRMED_DUPLICATE','POSSIBLE_MATCH','APPROVED_NEW','REJECTED')),
  matched_product_id uuid references public.products(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_catalog_import_staging_candidate unique (store_id, benchmark_version, candidate_id),
  constraint ck_catalog_import_staging_reference_price_range check (
    competitor_min_price_jod is null or competitor_max_price_jod is null or competitor_min_price_jod <= competitor_max_price_jod
  )
);
create index if not exists idx_catalog_import_staging_store_status on private.catalog_import_staging (store_id, benchmark_version, match_status, priority);
create index if not exists idx_catalog_import_staging_category on private.catalog_import_staging (store_id, category_name);
create index if not exists idx_catalog_import_staging_brand on private.catalog_import_staging (store_id, brand_text);
revoke all on table private.catalog_import_staging from anon, authenticated;
comment on table private.catalog_import_staging is 'Private review queue for external catalog benchmark candidates. Never customer-facing.';
comment on column private.catalog_import_staging.competitor_min_price_jod is 'Research reference only; never auto-copy to Altayebat selling price.';
comment on column private.catalog_import_staging.competitor_max_price_jod is 'Research reference only; never auto-copy to Altayebat selling price.';
