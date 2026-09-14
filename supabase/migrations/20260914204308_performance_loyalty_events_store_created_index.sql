-- Cover loyalty_events.store_id foreign key and speed store-scoped loyalty history.
-- Safe additive performance migration; does not modify production rows.

create index if not exists loyalty_events_store_created_idx
  on public.loyalty_events(store_id, created_at desc);
