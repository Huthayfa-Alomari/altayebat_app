-- Snapshot measurement semantics on each order item so historical receipts stay
-- correct even if the product configuration changes later.

begin;

alter table public.order_items
  add column if not exists sale_type_snapshot text not null default 'piece',
  add column if not exists base_unit_snapshot text not null default 'piece',
  add column if not exists inventory_scale_snapshot integer not null default 1,
  add column if not exists display_unit_price_snapshot numeric(14,6);

create or replace function private.snapshot_order_item_measurement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select
    coalesce(p.sale_type, 'piece'),
    coalesce(p.base_unit, 'piece'),
    coalesce(p.inventory_scale, 1),
    coalesce(p.price_per_unit, p.price)
  into
    new.sale_type_snapshot,
    new.base_unit_snapshot,
    new.inventory_scale_snapshot,
    new.display_unit_price_snapshot
  from public.products p
  where p.id = new.product_id;

  if not found then
    new.sale_type_snapshot := 'piece';
    new.base_unit_snapshot := 'piece';
    new.inventory_scale_snapshot := 1;
    new.display_unit_price_snapshot := new.unit_price;
  end if;

  return new;
end;
$$;

revoke all on function private.snapshot_order_item_measurement()
  from public, anon, authenticated;

drop trigger if exists trg_order_items_measurement_snapshot
  on public.order_items;

create trigger trg_order_items_measurement_snapshot
before insert on public.order_items
for each row
execute function private.snapshot_order_item_measurement();

update public.order_items oi
set sale_type_snapshot = coalesce(p.sale_type, 'piece'),
    base_unit_snapshot = coalesce(p.base_unit, 'piece'),
    inventory_scale_snapshot = coalesce(p.inventory_scale, 1),
    display_unit_price_snapshot = coalesce(p.price_per_unit, oi.unit_price)
from public.products p
where p.id = oi.product_id;

-- Preserve legacy rows even when their product was deleted.
update public.order_items
set display_unit_price_snapshot = unit_price
where display_unit_price_snapshot is null;

commit;
