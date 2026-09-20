create index if not exists loyalty_events_store_created_idx
  on public.loyalty_events(store_id, created_at desc);
