-- Altayebat measured/bulk products foundation.
--
-- Backward-compatible design:
--   * products.stock_qty remains INTEGER so all existing checkout/payment RPCs
--     keep working without changing their signatures.
--   * For piece products one stock unit = one piece.
--   * For weight products one stock unit = one gram.
--   * For volume products one stock unit = one millilitre.
--   * products.price remains the atomic-unit price used by the existing checkout.
--   * products.price_per_unit is the customer/admin price per piece/kg/litre.
--
-- Example: lentils at 1.750 JOD/kg with 12.5 kg in stock:
--   sale_type='weight', base_unit='kg', inventory_scale=1000,
--   price_per_unit=1.750, price=0.001750, stock_qty=12500.

begin;

-- Measured products need sub-fils precision at the atomic-unit level. Widening
-- these numeric columns is lossless for every existing piece product/order.
alter table public.products
  alter column price type numeric(14,6)
  using price::numeric(14,6);

alter table public.order_items
  alter column unit_price type numeric(14,6)
  using unit_price::numeric(14,6);

alter table public.products
  add column if not exists sale_type text not null default 'piece',
  add column if not exists base_unit text not null default 'piece',
  add column if not exists inventory_scale integer not null default 1,
  add column if not exists price_per_unit numeric(14,6),
  add column if not exists min_qty integer not null default 1,
  add column if not exists qty_step integer not null default 1,
  add column if not exists allow_amount_purchase boolean not null default false;

update public.products
set price_per_unit = price
where price_per_unit is null;

alter table public.products
  alter column price_per_unit set not null;

alter table public.products
  drop constraint if exists products_sale_type_check;
alter table public.products
  add constraint products_sale_type_check
  check (sale_type in ('piece', 'weight', 'volume'));

alter table public.products
  drop constraint if exists products_base_unit_check;
alter table public.products
  add constraint products_base_unit_check
  check (base_unit in ('piece', 'kg', 'liter'));

alter table public.products
  drop constraint if exists products_inventory_scale_check;
alter table public.products
  add constraint products_inventory_scale_check
  check (inventory_scale in (1, 1000));

alter table public.products
  drop constraint if exists products_measured_shape_check;
alter table public.products
  add constraint products_measured_shape_check
  check (
    (sale_type = 'piece' and base_unit = 'piece' and inventory_scale = 1)
    or (sale_type = 'weight' and base_unit = 'kg' and inventory_scale = 1000)
    or (sale_type = 'volume' and base_unit = 'liter' and inventory_scale = 1000)
  );

alter table public.products
  drop constraint if exists products_qty_rules_check;
alter table public.products
  add constraint products_qty_rules_check
  check (
    price_per_unit > 0
    and min_qty > 0
    and qty_step > 0
    and stock_qty >= 0
    and (sale_type <> 'piece' or allow_amount_purchase = false)
  );

-- Snapshot measured-product semantics onto order items. This means old receipts
-- keep displaying correctly even if the product configuration changes later.
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

revoke all on function private.snapshot_order_item_measurement() from public, anon, authenticated;

drop trigger if exists trg_order_items_measurement_snapshot on public.order_items;
create trigger trg_order_items_measurement_snapshot
before insert on public.order_items
for each row execute function private.snapshot_order_item_measurement();

-- Backfill snapshots for historical rows using the current product values where
-- available. Existing piece orders remain identical.
update public.order_items oi
set sale_type_snapshot = coalesce(p.sale_type, 'piece'),
    base_unit_snapshot = coalesce(p.base_unit, 'piece'),
    inventory_scale_snapshot = coalesce(p.inventory_scale, 1),
    display_unit_price_snapshot = coalesce(p.price_per_unit, oi.unit_price)
from public.products p
where p.id = oi.product_id;

create index if not exists idx_products_store_sale_type
  on public.products (store_id, sale_type);

commit;
