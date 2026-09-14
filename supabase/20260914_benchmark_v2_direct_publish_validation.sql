-- Benchmark v2 direct-publish validation
select
  count(*) as benchmark_live,
  count(*) filter (where category_id is null) as missing_category,
  count(*) filter (where price is null or price<=0) as bad_price,
  count(*) filter (where sku is null) as missing_sku,
  count(*) filter (where image_url is null or length(trim(image_url))=0) as missing_image,
  count(*) filter (where is_available=true) as available
from public.products
where sku like 'BENCH-V2-%';

select c.name as category_name,count(*) as products
from public.products p
join public.categories c on c.id=p.category_id
where p.sku like 'BENCH-V2-%'
group by c.name
order by products desc,c.name;
