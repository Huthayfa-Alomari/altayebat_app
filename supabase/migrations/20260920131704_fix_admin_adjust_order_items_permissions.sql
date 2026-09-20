create or replace function public.admin_adjust_order_items(
  p_order_id uuid,
  p_reason text,
  p_items jsonb
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.admin_adjust_order_items_impl(p_order_id,p_reason,p_items);
$$;

revoke all on function public.admin_adjust_order_items(uuid,text,jsonb)
  from public, anon;
grant execute on function public.admin_adjust_order_items(uuid,text,jsonb)
  to authenticated, service_role;

revoke all on function private.admin_adjust_order_items_impl(uuid,text,jsonb)
  from public, anon, authenticated;
grant execute on function private.admin_adjust_order_items_impl(uuid,text,jsonb)
  to service_role;

