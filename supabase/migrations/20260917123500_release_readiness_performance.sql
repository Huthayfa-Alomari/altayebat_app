-- Final low-risk production readiness performance cleanup.
-- 1) Cover the drivers.approved_by foreign key.
-- 2) Avoid per-row auth.uid() re-evaluation in the app_events INSERT RLS policy.

begin;

create index if not exists drivers_approved_by_idx
  on public.drivers(approved_by);

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

commit;
