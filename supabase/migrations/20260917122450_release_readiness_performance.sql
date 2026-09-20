create index if not exists drivers_approved_by_idx on public.drivers(approved_by);

drop policy if exists "Customers insert own app events" on public.app_events;
create policy "Customers insert own app events"
on public.app_events
for insert
to authenticated
with check (
  customer_id = (select auth.uid())
  and exists (
    select 1
    from public.stores s
    where s.id = app_events.store_id
      and s.is_active = true
  )
);
