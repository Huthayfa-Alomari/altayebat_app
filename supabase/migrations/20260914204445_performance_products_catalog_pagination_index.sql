-- Match the storefront pagination path: store + available products ordered newest first.
-- This is additive only and does not modify production rows.

create index if not exists idx_products_store_available_created
  on public.products(store_id, created_at desc)
  where is_available = true;
