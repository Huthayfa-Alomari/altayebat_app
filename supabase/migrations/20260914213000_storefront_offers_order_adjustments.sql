-- Storefront offer visibility + auditable order/invoice adjustments.
-- New products/checkout behavior remains unchanged; this migration only adds
-- operator controls and a safe adjustment RPC for pending/preparing orders.

begin;

create table if not exists public.storefront_settings (
  store_id uuid primary key references public.stores(id) on delete cascade,
  show_offers_section boolean not null default true,
  offer_banner_title text not null default 'عروض مميزة اليوم',
  offer_banner_subtitle text not null default 'وفر أكثر مع عروض أسواق الطيبات',
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.storefront_settings(store_id)
select s.id from public.stores s
on conflict (store_id) do nothing;

alter table public.storefront_settings enable row level security;

drop policy if exists storefront_settings_read on public.storefront_settings;
create policy storefront_settings_read
on public.storefront_settings for select
to authenticated
using (true);

drop policy if exists storefront_settings_admin_insert on public.storefront_settings;
create policy storefront_settings_admin_insert
on public.storefront_settings for insert
to authenticated
with check (private.is_store_admin(store_id));

drop policy if exists storefront_settings_admin_update on public.storefront_settings;
create policy storefront_settings_admin_update
on public.storefront_settings for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

revoke all on public.storefront_settings from anon, authenticated;
grant select, insert, update on public.storefront_settings to authenticated;
grant all on public.storefront_settings to service_role;

create table if not exists public.order_adjustments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  changed_by uuid,
  reason text not null,
  changes jsonb not null default '[]'::jsonb,
  old_subtotal numeric(12,3) not null default 0,
  new_subtotal numeric(12,3) not null default 0,
  old_total numeric(12,3) not null default 0,
  new_total numeric(12,3) not null default 0,
  refund_amount numeric(12,3) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists order_adjustments_order_created_idx
  on public.order_adjustments(order_id, created_at desc);
create index if not exists order_adjustments_store_created_idx
  on public.order_adjustments(store_id, created_at desc);

alter table public.order_adjustments enable row level security;

drop policy if exists order_adjustments_admin_read on public.order_adjustments;
create policy order_adjustments_admin_read
on public.order_adjustments for select
to authenticated
using (private.is_store_admin(store_id));

revoke all on public.order_adjustments from anon, authenticated;
grant select on public.order_adjustments to authenticated;
grant all on public.order_adjustments to service_role;

create or replace function public.admin_adjust_order_items(
  p_order_id uuid,
  p_reason text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
  v_line record;
  v_item public.order_items%rowtype;
  v_product public.products%rowtype;
  v_new_quantity integer;
  v_delta integer;
  v_mark_unavailable boolean;
  v_old_subtotal numeric(12,3);
  v_new_subtotal numeric(12,3);
  v_old_total numeric(12,3);
  v_new_total numeric(12,3);
  v_refund_amount numeric(12,3) := 0;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_changes jsonb := '[]'::jsonb;
  v_remaining_items integer;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if v_order.status not in ('pending', 'preparing') then
    raise exception 'ORDER_LOCKED_FOR_ADJUSTMENT' using errcode = 'P0001';
  end if;

  if v_reason is null then
    raise exception 'ADJUSTMENT_REASON_REQUIRED' using errcode = '22023';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'ADJUSTMENT_ITEMS_REQUIRED' using errcode = '22023';
  end if;

  if jsonb_array_length(p_items) > 100 then
    raise exception 'TOO_MANY_ADJUSTMENT_ITEMS' using errcode = '22023';
  end if;

  if exists (
    select 1
    from (
      select x.item_id, count(*) as c
      from jsonb_to_recordset(p_items)
        as x(item_id uuid, quantity integer, mark_unavailable boolean)
      group by x.item_id
    ) d
    where d.item_id is null or d.c > 1
  ) then
    raise exception 'INVALID_OR_DUPLICATE_ITEM' using errcode = '22023';
  end if;

  v_old_subtotal := coalesce(v_order.subtotal, 0);
  v_old_total := coalesce(v_order.total, 0);

  for v_line in
    select x.item_id, x.quantity, coalesce(x.mark_unavailable, false) as mark_unavailable
    from jsonb_to_recordset(p_items)
      as x(item_id uuid, quantity integer, mark_unavailable boolean)
  loop
    select * into v_item
    from public.order_items
    where id = v_line.item_id
      and order_id = p_order_id
    for update;

    if not found then
      raise exception 'ORDER_ITEM_NOT_FOUND' using errcode = 'P0002';
    end if;

    v_new_quantity := coalesce(v_line.quantity, -1);
    v_mark_unavailable := coalesce(v_line.mark_unavailable, false);

    if v_new_quantity < 0 then
      raise exception 'INVALID_QUANTITY' using errcode = '22023';
    end if;

    if v_new_quantity = v_item.quantity
       and not v_mark_unavailable then
      continue;
    end if;

    select * into v_product
    from public.products
    where id = v_item.product_id
      and store_id = v_order.store_id
    for update;

    if not found then
      raise exception 'PRODUCT_NOT_FOUND' using errcode = 'P0002';
    end if;

    v_delta := v_new_quantity - v_item.quantity;

    if v_delta > 0 then
      if not coalesce(v_product.is_available, false)
         or coalesce(v_product.stock_qty, 0) < v_delta then
        raise exception 'INSUFFICIENT_STOCK_FOR_ADJUSTMENT' using errcode = 'P0001';
      end if;

      update public.products
      set stock_qty = stock_qty - v_delta,
          is_available = case
            when stock_qty - v_delta <= 0 then false
            else is_available
          end,
          updated_at = now()
      where id = v_product.id;
    elsif v_delta < 0 then
      if v_mark_unavailable then
        update public.products
        set stock_qty = 0,
            is_available = false,
            updated_at = now()
        where id = v_product.id;
      else
        update public.products
        set stock_qty = coalesce(stock_qty, 0) + abs(v_delta),
            is_available = true,
            updated_at = now()
        where id = v_product.id;
      end if;
    elsif v_mark_unavailable then
      update public.products
      set stock_qty = 0,
          is_available = false,
          updated_at = now()
      where id = v_product.id;
    end if;

    v_changes := v_changes || jsonb_build_array(
      jsonb_build_object(
        'item_id', v_item.id,
        'product_id', v_item.product_id,
        'product_name', v_item.product_name,
        'old_quantity', v_item.quantity,
        'new_quantity', v_new_quantity,
        'unit_price', v_item.unit_price,
        'mark_unavailable', v_mark_unavailable
      )
    );

    if v_new_quantity = 0 then
      delete from public.order_items where id = v_item.id;
    else
      update public.order_items
      set quantity = v_new_quantity,
          subtotal = round(v_item.unit_price * v_new_quantity, 3)
      where id = v_item.id;
    end if;
  end loop;

  select count(*)::integer
  into v_remaining_items
  from public.order_items
  where order_id = p_order_id;

  if v_remaining_items = 0 then
    raise exception 'EMPTY_ORDER_AFTER_ADJUSTMENT' using errcode = '22023';
  end if;

  select coalesce(sum(oi.subtotal), 0)
  into v_new_subtotal
  from public.order_items oi
  where oi.order_id = p_order_id;

  v_new_total := greatest(
    0,
    v_new_subtotal
      + coalesce(v_order.delivery_fee, 0)
      - coalesce(v_order.discount, 0)
  );

  if v_order.payment_method = 'card'
     and v_order.payment_status = 'paid'
     and v_new_total < v_old_total then
    v_refund_amount := round(v_old_total - v_new_total, 3);
  end if;

  update public.orders
  set subtotal = v_new_subtotal,
      total = v_new_total,
      updated_at = now()
  where id = p_order_id;

  insert into public.order_adjustments(
    order_id, store_id, changed_by, reason, changes,
    old_subtotal, new_subtotal, old_total, new_total, refund_amount
  ) values (
    p_order_id, v_order.store_id, (select auth.uid()), v_reason, v_changes,
    v_old_subtotal, v_new_subtotal, v_old_total, v_new_total, v_refund_amount
  );

  insert into public.customer_notifications(
    store_id, customer_id, order_id, type, title, body, data
  ) values (
    v_order.store_id,
    v_order.customer_id,
    p_order_id,
    'system',
    'تم تعديل طلبك',
    'حدّث المول بعض أصناف الطلب. المجموع الجديد ' ||
      trim(to_char(v_new_total, 'FM999999990.000')) || ' د.أ. افتح الطلب لمراجعة التفاصيل.',
    jsonb_build_object(
      'kind', 'order_adjusted',
      'order_id', p_order_id,
      'old_total', v_old_total,
      'new_total', v_new_total,
      'refund_amount', v_refund_amount,
      'reason', v_reason
    )
  );

  -- Keep the internal receipt snapshot in sync when the invoice module exists.
  perform private.ensure_order_invoice(p_order_id);

  return jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'old_total', v_old_total,
    'new_total', v_new_total,
    'refund_amount', v_refund_amount,
    'changes', v_changes
  );
end;
$$;

revoke all on function public.admin_adjust_order_items(uuid, text, jsonb)
  from public, anon;
grant execute on function public.admin_adjust_order_items(uuid, text, jsonb)
  to authenticated;

commit;
