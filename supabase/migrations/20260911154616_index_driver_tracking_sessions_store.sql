-- Cover the driver_tracking_sessions.store_id foreign key used by store-scoped
-- tracking and operations queries.

create index if not exists driver_tracking_sessions_store_idx
  on public.driver_tracking_sessions (store_id);
