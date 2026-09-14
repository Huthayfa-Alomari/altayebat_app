-- Altayebat performance indexes
-- Date: 2026-09-14

create index if not exists idx_customer_notifications_store_id
  on public.customer_notifications(store_id);

create index if not exists idx_catalog_import_staging_matched_product_id
  on private.catalog_import_staging(matched_product_id)
  where matched_product_id is not null;
