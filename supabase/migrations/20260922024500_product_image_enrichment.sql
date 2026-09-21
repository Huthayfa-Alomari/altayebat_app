alter table public.products
  add column if not exists image_source text,
  add column if not exists image_source_url text,
  add column if not exists image_license text,
  add column if not exists image_match_method text,
  add column if not exists image_external_name text,
  add column if not exists image_enrichment_status text,
  add column if not exists image_checked_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_image_enrichment_status_check'
  ) then
    alter table public.products
      add constraint products_image_enrichment_status_check
      check (
        image_enrichment_status is null
        or image_enrichment_status in (
          'matched',
          'not_found',
          'needs_review',
          'error'
        )
      );
  end if;
end $$;

create index if not exists idx_products_image_enrichment_queue
  on public.products (store_id, image_enrichment_status, sort_order, created_at)
  where is_available = true and image_url is null;

comment on column public.products.image_source is
  'Machine-readable source name for the current automated product image.';
comment on column public.products.image_source_url is
  'Original source URL used to obtain the current automated product image.';
comment on column public.products.image_license is
  'License/attribution note for the current automated product image.';
comment on column public.products.image_match_method is
  'How the automated image match was made, e.g. exact_gtin.';
comment on column public.products.image_external_name is
  'Product name returned by the external image/catalog source.';
comment on column public.products.image_enrichment_status is
  'Automated image lookup state: matched, not_found, needs_review, error.';
comment on column public.products.image_checked_at is
  'Last time an automated image lookup was attempted.';
