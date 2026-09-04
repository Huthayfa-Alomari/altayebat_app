-- Applied live to Altayebat-MultiStore on 2026-09-04.
-- Barcode normalization + exact customer lookup + admin duplicate validation.
-- Does not touch checkout, payments, PayTabs, stock deduction, or callbacks.

update public.products
set barcode = nullif(btrim(barcode), '')
where barcode is distinct from nullif(btrim(barcode), '');

create or replace function private.normalize_product_barcode()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.barcode := nullif(btrim(new.barcode), '');
  return new;
end;
$$;

drop trigger if exists trg_products_normalize_barcode on public.products;
create trigger trg_products_normalize_barcode
before insert or update of barcode on public.products
for each row execute function private.normalize_product_barcode();

drop index if exists public.uq_products_store_barcode;
create unique index uq_products_store_barcode
on public.products(store_id, barcode)
where barcode is not null;

create index if not exists idx_products_barcode_lookup
on public.products(barcode)
where barcode is not null;

create or replace function public.lookup_product_by_barcode(
  p_store_id uuid,
  p_barcode text
) returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x)
  from (
    select
      p.id,p.store_id,p.category_id,p.brand_id,p.name,p.name_en,p.description,
      p.price,p.compare_at_price,p.image_url,p.stock_qty,p.is_available,
      p.barcode,p.sku,p.unit,p.pack_size,p.is_featured
    from public.products p
    where p.store_id = p_store_id
      and p.is_available = true
      and coalesce(p.stock_qty,0) > 0
      and p.barcode = nullif(btrim(p_barcode),'')
    limit 1
  ) x;
$$;

create or replace function public.admin_barcode_status(
  p_store_id uuid,
  p_barcode text,
  p_exclude_product_id uuid default null
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_barcode text := nullif(btrim(p_barcode),'');
  v_existing record;
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if v_barcode is null then
    return jsonb_build_object('valid',false,'available',false,'reason','EMPTY_BARCODE');
  end if;

  if length(v_barcode) > 64 then
    return jsonb_build_object('valid',false,'available',false,'reason','BARCODE_TOO_LONG');
  end if;

  select p.id,p.name into v_existing
  from public.products p
  where p.store_id=p_store_id
    and p.barcode=v_barcode
    and (p_exclude_product_id is null or p.id<>p_exclude_product_id)
  limit 1;

  if found then
    return jsonb_build_object(
      'valid',true,'available',false,'reason','DUPLICATE',
      'product_id',v_existing.id,'product_name',v_existing.name,'barcode',v_barcode
    );
  end if;

  return jsonb_build_object(
    'valid',true,'available',true,'reason','AVAILABLE','barcode',v_barcode
  );
end;
$$;

revoke all on function public.lookup_product_by_barcode(uuid,text) from public,anon;
revoke all on function public.admin_barcode_status(uuid,text,uuid) from public,anon;
grant execute on function public.lookup_product_by_barcode(uuid,text) to authenticated;
grant execute on function public.admin_barcode_status(uuid,text,uuid) to authenticated;
