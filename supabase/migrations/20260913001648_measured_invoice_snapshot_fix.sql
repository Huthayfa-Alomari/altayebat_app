-- Keep electronic invoice item snapshots measurement-aware on every deployment.
-- This is intentionally independent from private.ensure_order_invoice() so it
-- also repairs environments where the measured-products schema was deployed in
-- smaller migrations before the full invoice function replacement landed.

begin;

-- Historical order items whose product row no longer exists still need a sane
-- display price. For legacy piece items the atomic price is also the display
-- unit price, so this fallback is lossless.
update public.order_items
set display_unit_price_snapshot = unit_price
where display_unit_price_snapshot is null;

create or replace function private.refresh_invoice_items_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', oi.id,
        'product_id', oi.product_id,
        'name', oi.product_name,
        'quantity', oi.quantity,
        'unit_price', oi.unit_price,
        'subtotal', oi.subtotal,
        'sale_type', oi.sale_type_snapshot,
        'base_unit', oi.base_unit_snapshot,
        'inventory_scale', oi.inventory_scale_snapshot,
        'display_unit_price', oi.display_unit_price_snapshot
      ) order by oi.product_name, oi.id
    ),
    '[]'::jsonb
  )
  into new.items_snapshot
  from public.order_items oi
  where oi.order_id = new.order_id;

  return new;
end;
$$;

revoke all on function private.refresh_invoice_items_snapshot()
  from public, anon, authenticated;

drop trigger if exists trg_order_invoices_measured_snapshot
  on public.order_invoices;

create trigger trg_order_invoices_measured_snapshot
before insert or update of items_snapshot on public.order_invoices
for each row
execute function private.refresh_invoice_items_snapshot();

-- Rebuild existing electronic snapshots through the trigger. No financial
-- totals or order data are modified by this statement.
update public.order_invoices
set items_snapshot = items_snapshot;

commit;
