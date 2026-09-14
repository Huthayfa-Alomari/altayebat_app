create or replace function public.normalize_catalog_search(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select trim(
    regexp_replace(
      regexp_replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(
                      replace(lower(coalesce(p_text, '')), 'أ', 'ا'),
                    'إ', 'ا'),
                  'آ', 'ا'),
                'ٱ', 'ا'),
              'ى', 'ي'),
            'ة', 'ه'),
          'ؤ', 'و'),
        'ئ', 'ي'),
      '[ًٌٍَُِّْـ]', '', 'g'),
    '[-_/،,×]+', ' ', 'g')
  );
$$;

create or replace function public.search_store_products(
  p_store_id uuid,
  p_query text default null,
  p_category_id uuid default null,
  p_limit integer default 1000,
  p_offset integer default 0
)
returns setof public.products
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with q as (
    select public.normalize_catalog_search(p_query) as term
  )
  select p.*
  from public.products p
  left join public.brands b on b.id = p.brand_id
  left join public.categories c on c.id = p.category_id
  cross join q
  where p.store_id = p_store_id
    and p.is_available = true
    and (p_category_id is null or p.category_id = p_category_id)
    and (
      q.term = ''
      or not exists (
        select 1
        from unnest(regexp_split_to_array(q.term, '[[:space:]]+')) as token
        where token <> ''
          and public.normalize_catalog_search(
                concat_ws(' ',
                  p.name,
                  p.name_en,
                  p.search_keywords,
                  p.sku,
                  p.barcode,
                  p.pack_size,
                  b.name,
                  c.name
                )
              ) not like '%' || token || '%'
      )
    )
  order by
    case
      when q.term <> '' and public.normalize_catalog_search(p.name) = q.term then 0
      when q.term <> '' and public.normalize_catalog_search(p.name) like q.term || '%' then 1
      else 2
    end,
    coalesce(p.sort_order, 0),
    p.created_at desc
  limit greatest(1, least(coalesce(p_limit, 1000), 1000))
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.search_store_products(uuid,text,uuid,integer,integer) from public;
grant execute on function public.search_store_products(uuid,text,uuid,integer,integer) to anon, authenticated;

comment on function public.search_store_products(uuid,text,uuid,integer,integer)
is 'Catalog search across Arabic/English name, keywords, SKU, barcode, pack size, brand, and category with Arabic letter normalization. SECURITY INVOKER keeps products RLS in force.';
