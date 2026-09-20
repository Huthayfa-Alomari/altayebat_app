
alter table public.store_public_settings
  add column if not exists tiktok_enabled boolean not null default true,
  add column if not exists website_enabled boolean not null default true,
  add column if not exists google_maps_enabled boolean not null default true;
