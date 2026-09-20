create or replace function is_store_admin(target_store_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from store_admins
    where store_id = target_store_id and user_id = auth.uid()
  );
$$;

revoke execute on function is_store_admin(uuid) from anon, authenticated;
