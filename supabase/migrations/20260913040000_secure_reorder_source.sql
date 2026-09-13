-- Secure customer reorder source. This avoids depending on direct order_items RLS
-- while still returning only the caller's own historical order and current
-- product rows/prices/stock.

begin;

create or replace function public.get_reorder_source(
  p_order_id uuid,
  p_store_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and o.store_id = p_store_id
      and o.customer_id = v_user_id
  ) then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  return (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'quantity', oi.quantity,
          'products', case
            when p.id is null then null
            else to_jsonb(p)
          end
        )
        order by oi.id
      ),
      '[]'::jsonb
    )
    from public.order_items oi
    left join public.products p on p.id = oi.product_id
    where oi.order_id = p_order_id
  );
end;
$$;

revoke all on function public.get_reorder_source(uuid, uuid) from public, anon;
grant execute on function public.get_reorder_source(uuid, uuid) to authenticated;

commit;
