-- Automatically release inventory reserved by abandoned card checkouts that
-- never received a PayTabs transaction reference.
-- Applied to production as migration 20260911154347.

create or replace function private.cleanup_stale_unstarted_card_orders(
  p_stale_after interval default interval '30 minutes',
  p_batch_size integer default 50
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_cancelled integer := 0;
begin
  if p_stale_after < interval '10 minutes' then
    raise exception 'stale interval is too short' using errcode = '22023';
  end if;

  if p_batch_size < 1 or p_batch_size > 500 then
    raise exception 'invalid batch size' using errcode = '22023';
  end if;

  for v_order in
    select o.id
    from public.orders o
    where o.payment_method = 'card'
      and o.status = 'pending'
      and o.payment_status = 'pending'
      and nullif(trim(coalesce(o.payment_reference, '')), '') is null
      and o.created_at <= now() - p_stale_after
    order by o.created_at
    limit p_batch_size
    for update skip locked
  loop
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
      where oi.order_id = v_order.id
      group by oi.product_id
    ) restored
    where p.id = restored.product_id;

    update public.orders
    set payment_status = 'failed',
        status = 'cancelled',
        updated_at = now()
    where id = v_order.id
      and payment_method = 'card'
      and status = 'pending'
      and payment_status = 'pending'
      and nullif(trim(coalesce(payment_reference, '')), '') is null;

    if found then
      v_cancelled := v_cancelled + 1;
    end if;
  end loop;

  return v_cancelled;
end;
$$;

revoke all on function private.cleanup_stale_unstarted_card_orders(interval, integer)
  from public;

-- Reuse the existing payment operations job (every 10 minutes) rather than
-- creating another cron worker.
create or replace function private.run_ops_payments()
returns void
language plpgsql
security definer
set search_path = 'public', 'private', 'pg_temp'
as $$
declare
  r record;
begin
  perform private.cleanup_stale_unstarted_card_orders();

  for r in
    select store_id
    from public.store_automation_config
    where enabled
  loop
    perform public.n8n_run_payment_reconciliation_monitor(r.store_id);
  end loop;
end;
$$;
