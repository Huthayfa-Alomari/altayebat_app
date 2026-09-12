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

-- Keep the existing electronic receipt contract, but enrich each item snapshot
-- with its measurement semantics so customer receipts can display 500 g rather
-- than "500 pieces" and can show the human unit price (JOD/kg or JOD/litre).
create or replace function private.ensure_order_invoice(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.orders%rowtype;
  v_store public.stores%rowtype;
  v_customer public.customers%rowtype;
  v_invoice public.order_invoices%rowtype;
  v_items jsonb;
  v_number text;
begin
  select * into v_order from public.orders where id=p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  select * into v_store from public.stores where id=v_order.store_id;
  select * into v_customer from public.customers where id=v_order.customer_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',oi.id,
    'product_id',oi.product_id,
    'name',oi.product_name,
    'quantity',oi.quantity,
    'unit_price',oi.unit_price,
    'subtotal',oi.subtotal,
    'sale_type',oi.sale_type_snapshot,
    'base_unit',oi.base_unit_snapshot,
    'inventory_scale',oi.inventory_scale_snapshot,
    'display_unit_price',oi.display_unit_price_snapshot
  ) order by oi.product_name,oi.id),'[]'::jsonb)
  into v_items
  from public.order_items oi
  where oi.order_id=p_order_id;

  select * into v_invoice
  from public.order_invoices
  where order_id=p_order_id
  for update;

  if not found then
    v_number :=
      'ALT-RCP-' ||
      to_char(
        now() at time zone coalesce(v_store.timezone,'Asia/Amman'),
        'YYYYMMDD'
      ) ||
      '-' ||
      lpad(nextval('public.order_receipt_seq')::text,6,'0');

    insert into public.order_invoices(
      order_id,store_id,customer_id,document_number,document_kind,
      source,status,official,currency,issued_at,
      subtotal,delivery_fee,discount,tax,total,
      payment_method,payment_status,
      customer_name,customer_phone,
      store_name,store_phone,store_address,
      address_snapshot,items_snapshot
    ) values(
      v_order.id,v_order.store_id,v_order.customer_id,v_number,
      'order_receipt','internal_receipt',
      case when v_order.status='delivered' then 'final' else 'draft' end,
      false,
      coalesce(v_store.currency,'JOD'),
      case
        when v_order.status='delivered'
          then coalesce(v_order.updated_at,now())
        else null
      end,
      coalesce(v_order.subtotal,0),
      coalesce(v_order.delivery_fee,0),
      coalesce(v_order.discount,0),
      null,
      coalesce(v_order.total,0),
      v_order.payment_method,
      v_order.payment_status,
      v_customer.name,
      v_customer.phone,
      coalesce(v_store.name,'أسواق الطيبات'),
      v_store.phone,
      v_store.address,
      coalesce(v_order.address_snapshot,'{}'::jsonb),
      v_items
    )
    returning * into v_invoice;
  elsif v_invoice.source='internal_receipt' and v_invoice.official=false then
    update public.order_invoices
    set
      status=case when v_order.status='delivered' then 'final' else status end,
      issued_at=case
        when v_order.status='delivered'
          then coalesce(issued_at,v_order.updated_at,now())
        else issued_at
      end,
      currency=coalesce(v_store.currency,currency),
      subtotal=coalesce(v_order.subtotal,0),
      delivery_fee=coalesce(v_order.delivery_fee,0),
      discount=coalesce(v_order.discount,0),
      total=coalesce(v_order.total,0),
      payment_method=v_order.payment_method,
      payment_status=v_order.payment_status,
      customer_name=coalesce(v_customer.name,customer_name),
      customer_phone=coalesce(v_customer.phone,customer_phone),
      store_name=coalesce(v_store.name,store_name),
      store_phone=coalesce(v_store.phone,store_phone),
      store_address=coalesce(v_store.address,store_address),
      address_snapshot=coalesce(v_order.address_snapshot,address_snapshot),
      items_snapshot=v_items,
      updated_at=now()
    where id=v_invoice.id
    returning * into v_invoice;
  end if;

  return v_invoice.id;
end;
$$;

revoke all on function private.ensure_order_invoice(uuid) from public, anon, authenticated;
grant execute on function private.ensure_order_invoice(uuid) to service_role;

create index if not exists idx_products_store_sale_type
  on public.products (store_id, sale_type);

commit;
