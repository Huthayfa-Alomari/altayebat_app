-- Altayebat admin RPC hardening
--
-- Keeps the public RPC signatures used by the Next.js Admin app, while moving
-- SECURITY DEFINER implementations into the non-exposed private schema.

begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

create or replace function private.admin_dashboard_summary_impl(
  p_store_id uuid,
  p_from timestamptz default date_trunc('day', now()),
  p_to timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'orders_count', count(*),
    'delivered_count', count(*) filter (where status = 'delivered'),
    'open_count', count(*) filter (where status not in ('delivered', 'cancelled')),
    'cancelled_count', count(*) filter (where status = 'cancelled'),
    'gross_order_value', coalesce(sum(total), 0),
    'delivered_revenue', coalesce(sum(total) filter (where status = 'delivered'), 0),
    'pending_payment_count', count(*) filter (where payment_status in ('pending', 'unpaid')),
    'card_orders', count(*) filter (where payment_method = 'card'),
    'cash_orders', count(*) filter (where payment_method = 'cash'),
    'cliq_orders', count(*) filter (where payment_method = 'cliq')
  )
  into v_result
  from public.orders
  where store_id = p_store_id
    and created_at >= p_from
    and created_at < p_to;

  return v_result;
end;
$$;

revoke execute on function private.admin_dashboard_summary_impl(uuid, timestamptz, timestamptz)
  from public, anon;
grant execute on function private.admin_dashboard_summary_impl(uuid, timestamptz, timestamptz)
  to authenticated, service_role;

create or replace function public.admin_dashboard_summary(
  p_store_id uuid,
  p_from timestamptz default date_trunc('day', now()),
  p_to timestamptz default now()
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.admin_dashboard_summary_impl(p_store_id, p_from, p_to);
$$;

revoke execute on function public.admin_dashboard_summary(uuid, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_dashboard_summary(uuid, timestamptz, timestamptz)
  to authenticated, service_role;

create or replace function private.admin_low_stock_impl(
  p_store_id uuid,
  p_limit integer default 100
)
returns table(
  id uuid,
  name text,
  sku text,
  barcode text,
  stock_qty integer,
  low_stock_threshold integer,
  is_available boolean,
  image_url text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return query
  select
    p.id,
    p.name,
    p.sku,
    p.barcode,
    p.stock_qty,
    p.low_stock_threshold,
    p.is_available,
    p.image_url
  from public.products p
  where p.store_id = p_store_id
    and coalesce(p.stock_qty, 0) <= coalesce(p.low_stock_threshold, 5)
  order by p.stock_qty asc, p.name
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

revoke execute on function private.admin_low_stock_impl(uuid, integer)
  from public, anon;
grant execute on function private.admin_low_stock_impl(uuid, integer)
  to authenticated, service_role;

create or replace function public.admin_low_stock(
  p_store_id uuid,
  p_limit integer default 100
)
returns table(
  id uuid,
  name text,
  sku text,
  barcode text,
  stock_qty integer,
  low_stock_threshold integer,
  is_available boolean,
  image_url text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.admin_low_stock_impl(p_store_id, p_limit);
$$;

revoke execute on function public.admin_low_stock(uuid, integer)
  from public, anon;
grant execute on function public.admin_low_stock(uuid, integer)
  to authenticated, service_role;

commit;
