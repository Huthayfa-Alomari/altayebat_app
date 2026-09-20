create index if not exists idx_products_store_available_created
  on public.products(store_id, created_at desc)
  where is_available = true;
