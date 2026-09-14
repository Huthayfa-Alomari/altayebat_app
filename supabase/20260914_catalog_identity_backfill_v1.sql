-- Altayebat catalog identity backfill v1
-- Date: 2026-09-14
-- Scope: non-destructive enrichment only.
-- IMPORTANT:
--   * Does NOT delete products.
--   * Does NOT modify prices, stock, availability, category, image, barcode, or brand_id.
--   * Generates an internal SKU only where sku IS NULL.
--   * Fills pack_size only where an explicit mass/volume token appears in the product name.
--   * Multipacks containing *, ×, or spaced x are excluded from automatic pack-size backfill.

begin;

-- 1) Deterministic internal SKU from the product UUID.
-- Full UUID payload is kept to avoid collisions.
update public.products
set
  sku = 'ALT-' || upper(replace(id::text, '-', '')),
  updated_at = now()
where sku is null;

-- 2) Safe pack-size extraction from the explicit number+unit token itself.
-- Using the complete regex token prevents taking an earlier unrelated number
-- (example: "16 قطعة / 280g" must produce 280g, not 16g).
with candidates as (
  select
    id,
    case
      when name ~* '([0-9]+([.,][0-9]+)?)\s*(kg|كغم|كغ|كيلو|كجم)'
        then substring(name from '(?i)([0-9]+([.,][0-9]+)?\s*(kg|كغم|كغ|كيلو|كجم))')
      when name ~* '([0-9]+([.,][0-9]+)?)\s*(ml|مل|مليلتر)'
        then substring(name from '(?i)([0-9]+([.,][0-9]+)?\s*(ml|مل|مليلتر))')
      when name ~* '([0-9]+([.,][0-9]+)?)\s*(g|غرام|غم)'
        then substring(name from '(?i)([0-9]+([.,][0-9]+)?\s*(g|غرام|غم))')
      when name ~* '([0-9]+([.,][0-9]+)?)\s*(l|لتر)'
        then substring(name from '(?i)([0-9]+([.,][0-9]+)?\s*(l|لتر))')
      else null
    end as inferred_pack_size
  from public.products
  where pack_size is null
    and sale_type = 'piece'
    and not (name ~ '[×*]' or name ~* '\sx\s')
), safe_candidates as (
  select id, inferred_pack_size
  from candidates
  where inferred_pack_size is not null
)
update public.products p
set
  pack_size = c.inferred_pack_size,
  updated_at = now()
from safe_candidates c
where p.id = c.id
  and p.pack_size is null;

commit;

-- Verification summary
select
  count(*) as products_total,
  count(*) filter (where sku is null) as missing_sku,
  count(*) filter (where barcode is null) as missing_barcode,
  count(*) filter (where brand_id is null) as missing_brand,
  count(*) filter (where sale_type = 'piece' and pack_size is null) as piece_missing_pack_size,
  count(*) filter (where pack_size is not null) as products_with_pack_size
from public.products;
