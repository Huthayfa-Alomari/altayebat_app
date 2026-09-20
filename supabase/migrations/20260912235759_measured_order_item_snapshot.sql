create or replace function private.snapshot_order_item_measurement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select coalesce(p.sale_type,'piece'), coalesce(p.base_unit,'piece'), coalesce(p.inventory_scale,1), coalesce(p.price_per_unit,p.price)
  into new.sale_type_snapshot, new.base_unit_snapshot, new.inventory_scale_snapshot, new.display_unit_price_snapshot
  from public.products p where p.id = new.product_id;

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
create trigger trg_order_items_measurement_snapshot before insert on public.order_items for each row execute function private.snapshot_order_item_measurement();
update public.order_items oi
set sale_type_snapshot = coalesce(p.sale_type,'piece'),
    base_unit_snapshot = coalesce(p.base_unit,'piece'),
    inventory_scale_snapshot = coalesce(p.inventory_scale,1),
    display_unit_price_snapshot = coalesce(p.price_per_unit,oi.unit_price)
from public.products p
where p.id = oi.product_id;
