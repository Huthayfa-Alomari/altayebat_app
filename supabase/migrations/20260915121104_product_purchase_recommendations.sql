create or replace function public.get_product_recommendations(
  p_product_id uuid,
  p_limit integer default 4
)
returns table (
  id uuid,
  name text,
  description text,
  price numeric,
  image_url text,
  stock_qty integer,
  is_available boolean,
  category_id uuid,
  sale_type text,
  base_unit text,
  inventory_scale integer,
  price_per_unit numeric,
  min_qty integer,
  qty_step integer,
  allow_amount_purchase boolean,
  recommendation_score integer,
  bought_together_count integer,
  last_bought_together_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with target_context as (
    select p.id, p.store_id, p.category_id, p.brand_id
    from public.products p
    where p.id = p_product_id
      and p.is_available = true
    limit 1
  ),
  history as (
    select
      sibling.product_id,
      count(distinct source.order_id)::integer as pair_count,
      count(distinct source.order_id) filter (where o.status = 'delivered')::integer as delivered_pair_count,
      max(o.created_at) as last_at
    from target_context tc
    join public.order_items source
      on source.product_id = tc.id
    join public.orders o
      on o.id = source.order_id
     and o.store_id = tc.store_id
     and o.status <> 'cancelled'
    join public.order_items sibling
      on sibling.order_id = source.order_id
     and sibling.product_id <> tc.id
    group by sibling.product_id
  ),
  candidates as (
    select
      h.product_id,
      (1000 + (h.delivered_pair_count * 100) + (h.pair_count * 10))::integer as score,
      h.pair_count,
      h.last_at
    from history h

    union all

    select
      p.id as product_id,
      case
        when tc.brand_id is not null and p.brand_id = tc.brand_id then 180
        when tc.category_id is not null and p.category_id = tc.category_id then 120
        else 0
      end::integer as score,
      0::integer as pair_count,
      null::timestamptz as last_at
    from target_context tc
    join public.products p
      on p.store_id = tc.store_id
     and p.id <> tc.id
     and p.is_available = true
     and p.stock_qty > 0
     and (
       (tc.brand_id is not null and p.brand_id = tc.brand_id)
       or (tc.category_id is not null and p.category_id = tc.category_id)
     )
  ),
  ranked as (
    select
      c.product_id,
      max(c.score)::integer as score,
      max(c.pair_count)::integer as pair_count,
      max(c.last_at) as last_at
    from candidates c
    group by c.product_id
  )
  select
    p.id,
    p.name,
    p.description,
    p.price,
    p.image_url,
    p.stock_qty,
    p.is_available,
    p.category_id,
    p.sale_type,
    p.base_unit,
    p.inventory_scale,
    p.price_per_unit,
    p.min_qty,
    p.qty_step,
    p.allow_amount_purchase,
    r.score as recommendation_score,
    r.pair_count as bought_together_count,
    r.last_at as last_bought_together_at
  from ranked r
  join public.products p on p.id = r.product_id
  join target_context tc on p.store_id = tc.store_id
  where (select auth.uid()) is not null
    and p.is_available = true
    and p.stock_qty > 0
  order by
    r.score desc,
    r.pair_count desc,
    r.last_at desc nulls last,
    p.sort_order asc nulls last,
    p.name asc
  limit least(greatest(coalesce(p_limit, 4), 1), 12);
$$;

revoke execute on function public.get_product_recommendations(uuid, integer) from public;
revoke execute on function public.get_product_recommendations(uuid, integer) from anon;
grant execute on function public.get_product_recommendations(uuid, integer) to authenticated;
