-- The function must remain callable by anon/authenticated because RLS policies
-- invoke it under the querying role's privileges. Revoking execute breaks every
-- policy that references it. Re-grant; direct RPC access is safe since it only
-- returns whether auth.uid() is an admin of a given store (no data exposure).
grant execute on function is_store_admin(uuid) to anon, authenticated;
