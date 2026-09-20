drop policy if exists account_deletion_requests_customer_select
  on public.account_deletion_requests;
drop policy if exists account_deletion_requests_admin_select
  on public.account_deletion_requests;

create policy account_deletion_requests_select
on public.account_deletion_requests
for select
to authenticated
using (
  (select auth.uid()) = customer_id
  or private.is_store_admin(store_id)
);
