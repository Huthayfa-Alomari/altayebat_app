-- Altayebat owner catalog exclusions — 2026-09-14
-- Idempotent guard: fruits/vegetables and pet food must not be present in the live catalog.

begin;

-- Remove any products that may be reintroduced into the two excluded live categories.
delete from public.products p
using public.categories c
where p.category_id = c.id
  and c.name in ('الخضار والفواكه', 'مستلزمات الحيوانات الأليفة');

-- Keep Benchmark candidates excluded from future promotion/import runs.
update private.catalog_import_staging s
set review_status = 'REJECTED',
    match_status = 'REJECTED',
    is_available = false,
    stock_qty = 0,
    notes = case
      when coalesce(s.notes, '') like '%Removed from live catalog by owner request: fruits/vegetables/pet food%'
        then s.notes
      else concat_ws(' | ', nullif(s.notes, ''), 'Removed from live catalog by owner request: fruits/vegetables/pet food')
    end,
    updated_at = now()
where s.category_name in ('خضار', 'فواكه', 'طعام قطط', 'طعام كلاب');

-- Hide the now-empty storefront categories instead of deleting taxonomy rows.
update public.categories c
set is_active = false,
    updated_at = now()
where c.name in ('الخضار والفواكه', 'مستلزمات الحيوانات الأليفة')
  and not exists (
    select 1 from public.products p where p.category_id = c.id
  );

commit;
