create or replace function public.lookup_product_by_barcode(
  p_store_id uuid,
  p_barcode text
)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  select to_jsonb(x)
  from (
    select
      p.id,p.store_id,p.category_id,p.brand_id,p.name,p.name_en,p.description,
      p.price,p.compare_at_price,p.image_url,p.stock_qty,p.is_available,
      p.barcode,p.sku,p.unit,p.pack_size,p.is_featured,
      p.sale_type,p.base_unit,p.inventory_scale,p.price_per_unit,
      p.min_qty,p.qty_step,p.allow_amount_purchase
    from public.products p
    where p.store_id = p_store_id
      and p.is_available = true
      and coalesce(p.stock_qty,0) >= greatest(coalesce(p.min_qty,1),1)
      and p.barcode = nullif(btrim(p_barcode),'')
    limit 1
  ) x;
$function$;
