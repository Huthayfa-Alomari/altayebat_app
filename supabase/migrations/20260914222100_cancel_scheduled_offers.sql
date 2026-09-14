-- Extend the existing end-offer action so it also cancels a scheduled offer.

begin;

create or replace function public.admin_end_product_offer(p_offer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.store_offers%rowtype;
begin
  select * into v_offer
  from public.store_offers
  where id = p_offer_id
  for update;

  if not found then
    raise exception 'OFFER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not private.is_store_admin(v_offer.store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_offer.ended_at is not null then
    return;
  end if;

  if v_offer.is_active then
    update public.products
    set price = v_offer.regular_atomic_price,
        price_per_unit = v_offer.regular_price_per_unit,
        updated_at = now()
    where id = v_offer.product_id
      and store_id = v_offer.store_id
      and abs(price - v_offer.offer_atomic_price) < 0.000001
      and abs(price_per_unit - v_offer.offer_price_per_unit) < 0.000001;
  end if;

  update public.store_offers
  set is_active = false,
      ended_at = now()
  where id = p_offer_id;
end;
$$;

revoke all on function public.admin_end_product_offer(uuid) from public, anon;
grant execute on function public.admin_end_product_offer(uuid) to authenticated;

commit;
