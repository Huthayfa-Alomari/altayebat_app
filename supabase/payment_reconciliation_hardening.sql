-- Altayebat card reconciliation hardening
--
-- Ensures a late authorised PayTabs result is never hidden after an earlier
-- cancellation/restock. Financial truth wins: keep the order cancelled, record
-- payment_status=paid, and return paid_requires_refund for operator action.

begin;

create or replace function public.finalize_card_payment(
  p_order_id uuid,
  p_tran_ref text,
  p_payment_status text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_reference text;
begin
  if p_payment_status not in ('pending', 'paid', 'failed') then
    raise exception 'Unsupported payment status' using errcode = '22023';
  end if;

  select *
    into v_order
  from public.orders
  where id = p_order_id
    and payment_method = 'card'
  for update;

  if not found then
    raise exception 'Card order not found' using errcode = 'P0002';
  end if;

  v_reference := coalesce(nullif(trim(p_tran_ref), ''), v_order.payment_reference);

  -- An authorised transaction is financial truth. If stock was already restored
  -- and the order cancelled, keep the operational order cancelled but preserve
  -- the paid state so a refund/manual review cannot be missed.
  if v_order.payment_status = 'paid' then
    if v_order.status = 'cancelled' then
      return 'paid_requires_refund';
    end if;
    return 'paid';
  end if;

  if p_payment_status = 'paid' then
    update public.orders
    set payment_reference = v_reference,
        payment_status = 'paid',
        updated_at = now()
    where id = p_order_id;

    if v_order.status = 'cancelled' then
      return 'paid_requires_refund';
    end if;

    return 'paid';
  end if;

  -- A failed card payment that was already cancelled has already had inventory
  -- restored. Duplicate failures are therefore fully idempotent.
  if v_order.status = 'cancelled' and v_order.payment_status = 'failed' then
    return 'cancelled';
  end if;

  if p_payment_status = 'failed' then
    if v_order.status = 'pending' then
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

      update public.orders
      set payment_reference = v_reference,
          payment_status = 'failed',
          status = 'cancelled',
          updated_at = now()
      where id = p_order_id;

      -- automation_order_status writes the cancellation history/notification.
      return 'cancelled';
    end if;

    update public.orders
    set payment_reference = v_reference,
        payment_status = 'failed',
        updated_at = now()
    where id = p_order_id;

    return 'failed_requires_review';
  end if;

  update public.orders
  set payment_reference = v_reference,
      payment_status = 'pending',
      updated_at = now()
  where id = p_order_id;

  return 'pending';
end;
$$;

revoke execute on function public.finalize_card_payment(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.finalize_card_payment(uuid, text, text)
  to service_role;

commit;
