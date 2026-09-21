alter table public.categories
  add column if not exists image_url text;

comment on column public.categories.image_url is
  'Optional public image/GIF/WebP URL used by the customer storefront category cards.';
