-- Altayebat payment flow hardening
-- Production migration applied 2026-09-06.
-- Safe to keep in source control as the canonical schema change.

create or replace function public.get_store_payment_config(p_store_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'cliq_alias', s.cliq_alias,
        'cliq_recipient_name', s.cliq_recipient_name,
        'phone', s.phone
      )
      from public.stores s
      where s.id = p_store_id
        and s.is_active = true
    ),
    '{}'::jsonb
  );
$$;

revoke all on function public.get_store_payment_config(uuid) from public;
revoke all on function public.get_store_payment_config(uuid) from anon;
grant execute on function public.get_store_payment_config(uuid) to authenticated;

create or replace function private.admin_update_store_payment_config_impl(
  p_store_id uuid,
  p_cliq_alias text,
  p_cliq_recipient_name text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.stores
  set cliq_alias = nullif(btrim(p_cliq_alias), ''),
      cliq_recipient_name = nullif(btrim(p_cliq_recipient_name), ''),
      phone = nullif(btrim(p_phone), '')
  where id = p_store_id
  returning jsonb_build_object(
    'cliq_alias', cliq_alias,
    'cliq_recipient_name', cliq_recipient_name,
    'phone', phone
  ) into v_result;

  if v_result is null then
    raise exception 'STORE_NOT_FOUND' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;

revoke all on function private.admin_update_store_payment_config_impl(uuid,text,text,text)
  from public;

create or replace function public.admin_update_store_payment_config(
  p_store_id uuid,
  p_cliq_alias text,
  p_cliq_recipient_name text,
  p_phone text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.admin_update_store_payment_config_impl(
    p_store_id,
    p_cliq_alias,
    p_cliq_recipient_name,
    p_phone
  );
$$;

revoke all on function public.admin_update_store_payment_config(uuid,text,text,text)
  from public;
revoke all on function public.admin_update_store_payment_config(uuid,text,text,text)
  from anon;
grant execute on function public.admin_update_store_payment_config(uuid,text,text,text)
  to authenticated;

create or replace function private.cancel_unstarted_card_order_impl(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order public.orders%rowtype;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
    and customer_id = v_user
    and payment_method = 'card'
  for update;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_order.status <> 'pending'
     or v_order.payment_status <> 'pending'
     or v_order.payment_reference is not null then
    return false;
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

  update public.orders
  set payment_status = 'failed',
      status = 'cancelled',
      updated_at = now()
  where id = p_order_id;

  insert into public.order_status_history(order_id, status, changed_by)
  values (p_order_id, 'cancelled', v_user);

  return true;
end;
$$;

revoke all on function private.cancel_unstarted_card_order_impl(uuid)
  from public;

create or replace function public.cancel_unstarted_card_order(p_order_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select private.cancel_unstarted_card_order_impl(p_order_id);
$$;

revoke all on function public.cancel_unstarted_card_order(uuid) from public;
revoke all on function public.cancel_unstarted_card_order(uuid) from anon;
grant execute on function public.cancel_unstarted_card_order(uuid) to authenticated;
