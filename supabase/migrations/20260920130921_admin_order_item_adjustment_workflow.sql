create table if not exists private.order_item_adjustments (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  admin_user_id uuid not null,
  reason text not null,
  changes jsonb not null default '[]'::jsonb,
  old_total numeric(12,3) not null,
  new_total numeric(12,3) not null,
  refund_amount numeric(12,3) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_item_adjustments_order_created
  on private.order_item_adjustments(order_id, created_at desc);

revoke all on table private.order_item_adjustments from public, anon, authenticated;

create or replace function private.admin_adjust_order_items_impl(
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
  v_user uuid := (select auth.uid());
  v_order public.orders%rowtype;
  v_line public.order_items%rowtype;
  v_product public.products%rowtype;
  v_req record;
  v_old_total numeric(12,3);
  v_new_subtotal numeric(12,3);
  v_new_total numeric(12,3);
  v_refund numeric(12,3) := 0;
  v_delta integer;
  v_min_qty integer;
  v_qty_step integer;
  v_changes jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'ADJUSTMENT_REASON_REQUIRED' using errcode='22023';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'ADJUSTMENT_ITEMS_REQUIRED' using errcode='22023';
  end if;

  if jsonb_array_length(p_items) > 100 then
    raise exception 'TOO_MANY_ADJUSTMENT_ITEMS' using errcode='22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items)
      as x(item_id uuid, quantity integer, mark_unavailable boolean)
    group by x.item_id
    having count(*) > 1
  ) then
    raise exception 'DUPLICATE_ADJUSTMENT_ITEM' using errcode='22023';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  if not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if coalesce(v_order.status,'') not in ('pending','preparing') then
    raise exception 'ORDER_LOCKED_FOR_ADJUSTMENT' using errcode='22023';
  end if;

  v_old_total := coalesce(v_order.total,0);

  for v_req in
    select
      x.item_id,
      x.quantity,
      coalesce(x.mark_unavailable,false) as mark_unavailable
    from jsonb_to_recordset(p_items)
      as x(item_id uuid, quantity integer, mark_unavailable boolean)
    order by x.item_id
  loop
    if v_req.item_id is null or v_req.quantity is null or v_req.quantity < 0 then
      raise exception 'INVALID_ADJUSTMENT_ITEM' using errcode='22023';
    end if;

    select *
    into v_line
    from public.order_items
    where id = v_req.item_id
      and order_id = p_order_id
    for update;

    if not found then
      raise exception 'ORDER_ITEM_NOT_FOUND:%', v_req.item_id using errcode='P0002';
    end if;

    select *
    into v_product
    from public.products
    where id = v_line.product_id
      and store_id = v_order.store_id
    for update;

    if not found then
      raise exception 'PRODUCT_NOT_FOUND:%', v_line.product_id using errcode='P0002';
    end if;

    if v_req.mark_unavailable and v_req.quantity <> 0 then
      raise exception 'UNAVAILABLE_ITEM_QUANTITY_MUST_BE_ZERO' using errcode='22023';
    end if;

    if v_req.quantity > 0 then
      v_min_qty := greatest(coalesce(v_product.min_qty,1),1);
      v_qty_step := greatest(coalesce(v_product.qty_step,1),1);

      if v_req.quantity < v_min_qty then
        raise exception 'MIN_QTY_FOR_ADJUSTMENT:%:%', v_product.name, v_min_qty using errcode='22023';
      end if;

      if mod(v_req.quantity - v_min_qty, v_qty_step) <> 0 then
        raise exception 'INVALID_QTY_STEP_FOR_ADJUSTMENT:%:%', v_product.name, v_qty_step using errcode='22023';
      end if;
    end if;

    if coalesce(v_order.payment_status,'') = 'paid'
       and v_req.quantity > v_line.quantity then
      raise exception 'PAID_ORDER_INCREASE_NOT_ALLOWED' using errcode='22023';
    end if;

    if v_req.quantity > v_line.quantity then
      v_delta := v_req.quantity - v_line.quantity;

      if not coalesce(v_product.is_available,false)
         or coalesce(v_product.stock_qty,0) < v_delta then
        raise exception 'INSUFFICIENT_STOCK_FOR_ADJUSTMENT:%', v_product.name using errcode='22023';
      end if;

      update public.products
      set stock_qty = stock_qty - v_delta,
          is_available = case
            when stock_qty - v_delta < greatest(coalesce(min_qty,1),1) then false
            else is_available
          end,
          updated_at = now()
      where id = v_product.id;

    elsif v_req.quantity < v_line.quantity then
      v_delta := v_line.quantity - v_req.quantity;

      if v_req.mark_unavailable then
        update public.products
        set stock_qty = 0,
            is_available = false,
            updated_at = now()
        where id = v_product.id;
      else
        update public.products
        set stock_qty = stock_qty + v_delta,
            is_available = case
              when is_available = false
                   and stock_qty = 0
                   and stock_qty + v_delta >= greatest(coalesce(min_qty,1),1)
                then true
              else is_available
            end,
            updated_at = now()
        where id = v_product.id;
      end if;
    end if;

    v_changes := v_changes || jsonb_build_array(
      jsonb_build_object(
        'item_id', v_line.id,
        'product_id', v_line.product_id,
        'product_name', coalesce(v_line.product_name, v_product.name),
        'old_quantity', v_line.quantity,
        'new_quantity', v_req.quantity,
        'mark_unavailable', v_req.mark_unavailable
      )
    );

    if v_req.quantity = 0 then
      delete from public.order_items
      where id = v_line.id;
    else
      update public.order_items
      set quantity = v_req.quantity,
          subtotal = round((v_line.unit_price * v_req.quantity)::numeric, 3)
      where id = v_line.id;
    end if;
  end loop;

  if not exists (
    select 1 from public.order_items where order_id = p_order_id
  ) then
    raise exception 'EMPTY_ORDER_AFTER_ADJUSTMENT' using errcode='22023';
  end if;

  select coalesce(sum(coalesce(subtotal, unit_price * quantity)),0)::numeric(12,3)
  into v_new_subtotal
  from public.order_items
  where order_id = p_order_id;

  v_new_total := greatest(
    0,
    v_new_subtotal
      + coalesce(v_order.delivery_fee,0)
      - coalesce(v_order.discount,0)
  )::numeric(12,3);

  if coalesce(v_order.payment_status,'') = 'paid'
     and v_new_total > v_old_total then
    raise exception 'PAID_ORDER_INCREASE_NOT_ALLOWED' using errcode='22023';
  end if;

  if coalesce(v_order.payment_status,'') = 'paid' then
    v_refund := greatest(v_old_total - v_new_total,0)::numeric(12,3);
  end if;

  update public.orders
  set subtotal = v_new_subtotal,
      total = v_new_total,
      updated_at = now()
  where id = p_order_id;

  update public.order_invoices
  set subtotal = v_new_subtotal,
      delivery_fee = coalesce(v_order.delivery_fee,0),
      discount = coalesce(v_order.discount,0),
      total = v_new_total,
      payment_method = v_order.payment_method,
      payment_status = v_order.payment_status,
      items_snapshot = items_snapshot,
      updated_at = now()
  where order_id = p_order_id;

  insert into private.order_item_adjustments(
    order_id, store_id, admin_user_id, reason, changes,
    old_total, new_total, refund_amount
  ) values (
    p_order_id, v_order.store_id, v_user, btrim(p_reason), v_changes,
    v_old_total, v_new_total, v_refund
  );

  if v_order.customer_id is not null then
    insert into public.customer_notifications(
      store_id, customer_id, order_id, type, title, body, data
    ) values (
      v_order.store_id,
      v_order.customer_id,
      p_order_id,
      'system',
      'تم تعديل طلبك',
      btrim(p_reason) || ' — الإجمالي الجديد ' || trim(to_char(v_new_total,'FM999999990.00')) || ' د.أ',
      jsonb_build_object(
        'kind','order_adjustment',
        'reason',btrim(p_reason),
        'changes',v_changes,
        'old_total',v_old_total,
        'new_total',v_new_total,
        'refund_amount',v_refund
      )
    );
  end if;

  return jsonb_build_object(
    'order_id', p_order_id,
    'old_total', v_old_total,
    'new_subtotal', v_new_subtotal,
    'new_total', v_new_total,
    'refund_amount', v_refund,
    'changes', v_changes
  );
end;
$$;

revoke all on function private.admin_adjust_order_items_impl(uuid,text,jsonb)
  from public, anon, authenticated;
grant execute on function private.admin_adjust_order_items_impl(uuid,text,jsonb)
  to service_role;

create or replace function public.admin_adjust_order_items(
  p_order_id uuid,
  p_reason text,
  p_items jsonb
)
returns jsonb
language sql
set search_path = ''
as $$
  select private.admin_adjust_order_items_impl(p_order_id,p_reason,p_items);
$$;

revoke all on function public.admin_adjust_order_items(uuid,text,jsonb)
  from public, anon;
grant execute on function public.admin_adjust_order_items(uuid,text,jsonb)
  to authenticated, service_role;

