alter table public.products
  add column if not exists image_secondary_source text,
  add column if not exists image_secondary_status text,
  add column if not exists image_secondary_checked_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='products_image_secondary_status_check'
  ) then
    alter table public.products
      add constraint products_image_secondary_status_check
      check (
        image_secondary_status is null
        or image_secondary_status in ('matched','not_found','error','rate_limited')
      );
  end if;
end $$;

create index if not exists idx_products_image_secondary_queue
  on public.products (store_id, image_secondary_status, image_secondary_checked_at, sort_order)
  where is_available = true and image_url is null;

comment on column public.products.image_secondary_source is
  'Secondary internet/catalog source used after the primary Open Facts lookup.';
comment on column public.products.image_secondary_status is
  'Secondary internet image lookup state.';
comment on column public.products.image_secondary_checked_at is
  'Last time the secondary internet image lookup was attempted.';
