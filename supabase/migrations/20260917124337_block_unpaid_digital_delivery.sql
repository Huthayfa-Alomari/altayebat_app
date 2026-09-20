create or replace function private.admin_update_order_status_impl(
  p_order_id uuid,
  p_store_id uuid,
  p_new_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_new_status not in (
    'pending', 'preparing', 'out_for_delivery', 'delivered', 'cancelled'
  ) then
    raise exception 'Unsupported order status' using errcode = '22023';
  end if;

  select *
    into v_order
  from public.orders
  where id = p_order_id
    and store_id = p_store_id
  for update;

  if not found then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  if p_new_status = v_order.status then
    return v_order.status;
  end if;

  if v_order.status = 'pending'
     and p_new_status not in ('preparing', 'cancelled') then
    raise exception 'Invalid order status transition' using errcode = '22023';
  elsif v_order.status = 'preparing'
     and p_new_status not in ('out_for_delivery', 'cancelled') then
    raise exception 'Invalid order status transition' using errcode = '22023';
  elsif v_order.status = 'out_for_delivery'
     and p_new_status <> 'delivered' then
    raise exception 'Invalid order status transition' using errcode = '22023';
  elsif v_order.status in ('delivered', 'cancelled') then
    raise exception 'Order status is terminal' using errcode = '22023';
  end if;

  if p_new_status in ('out_for_delivery', 'delivered')
     and v_order.payment_method in ('card', 'cliq')
     and coalesce(v_order.payment_status, '') <> 'paid' then
    raise exception 'PAYMENT_NOT_CONFIRMED' using errcode = '22023';
  end if;

  if p_new_status = 'cancelled' then
    if v_order.payment_method = 'card' then
      raise exception 'Card order cancellation is gateway managed'
        using errcode = '42501';
    end if;

    if v_order.payment_status = 'paid' then
      raise exception 'Paid order requires refund before cancellation'
        using errcode = '42501';
    end if;

    update public.products p
    set stock_qty = coalesce(p.stock_qty, 0) + restored.quantity,
        is_available = case
          when coalesce(p.stock_qty, 0) <= 0
            and coalesce(p.stock_qty, 0) + restored.quantity > 0
            then true
          else p.is_available
        end,
        updated_at = now()
    from (
      select oi.product_id, sum(oi.quantity)::integer as quantity
      from public.order_items oi
      where oi.order_id = p_order_id
      group by oi.product_id
    ) restored
    where p.id = restored.product_id;
  end if;

  update public.orders
  set status = p_new_status,
      updated_at = now()
  where id = p_order_id;

  return p_new_status;
end;
$$;

revoke execute on function private.admin_update_order_status_impl(uuid, uuid, text)
  from public, anon;
grant execute on function private.admin_update_order_status_impl(uuid, uuid, text)
  to authenticated, service_role;
