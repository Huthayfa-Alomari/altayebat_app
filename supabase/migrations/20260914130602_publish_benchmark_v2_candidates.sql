create or replace function private.publish_benchmark_v2_candidates()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inserted integer := 0;
  v_updated_staging integer := 0;
begin
  insert into public.brands(store_id,name,name_en,is_active,sort_order)
  select distinct s.store_id, trim(s.brand_text), trim(s.brand_text), true, 0
  from private.catalog_import_staging s
  where s.benchmark_version='Benchmark v2'
    and s.match_status='APPROVED_NEW'
    and s.brand_text is not null
    and trim(s.brand_text)<>''
    and lower(trim(s.brand_text))<>'generic'
    and not exists (
      select 1 from public.brands b
      where b.store_id=s.store_id
        and (lower(b.name)=lower(trim(s.brand_text)) or lower(coalesce(b.name_en,''))=lower(trim(s.brand_text)))
    );

  with src as (
    select s.*,
      case
        when s.category_name='أرز' then 'الأرز'
        when s.category_name in ('ألبان وأجبان','حليب','لبن ولبنة','كريمة وطبخ','بيض') then 'الألبان والأجبان'
        when s.category_name='مجمدات ووجبات جاهزة' then 'المجمدات'
        when s.category_name='عصائر' then 'المشروبات'
        when s.category_name='قهوة' then 'قهوة'
        when s.category_name in ('معلبات','تونة ومأكولات بحرية معلبة','صلصات') then 'معلبات وصلصات'
        when s.category_name='معكرونة' then 'معكرونة وشعيرية'
        when s.category_name='نودلز وشوربات' then 'مرقة وشوربات'
        when s.category_name='سكر ومحليات' then 'سكر ومستلزمات الخَبز'
        when s.category_name='فطور وسبريد' then 'طحينية وحلاوة ومربى'
        when s.category_name='دجاج طازج' then 'اللحوم والدواجن'
        when s.category_name='منظفات' then 'تنظيف المنزل والجلي'
        when s.category_name='عناية بالشعر' then 'العناية الشخصية'
        when s.category_name='عناية أطفال' then 'عناية الأطفال'
        when s.category_name in ('شوكولاتة','شيبس وسناكات','مخبوزات حلوة') then 'السناكات والحلويات'
        when s.category_name in ('خضار','فواكه') then 'الخضار والفواكه'
        when s.category_name in ('طعام قطط','طعام كلاب') then 'مستلزمات الحيوانات الأليفة'
        when s.category_name in ('أكياس نفايات','مستهلكات منزلية') then 'مستهلكات منزلية'
        else 'مستهلكات منزلية'
      end as target_category_name,
      coalesce(s.competitor_min_price_jod,s.competitor_max_price_jod) as live_price,
      ('BENCH-V2-' || lpad(s.candidate_id::text,4,'0')) as live_sku,
      trim(concat_ws(' ',
        case when s.brand_text is null or lower(trim(s.brand_text))='generic' then null
             when lower(s.product_name) like '%' || lower(trim(s.brand_text)) || '%' then null
             else trim(s.brand_text) end,
        s.product_name,
        s.pack_size
      )) as live_name
    from private.catalog_import_staging s
    where s.benchmark_version='Benchmark v2'
      and s.match_status='APPROVED_NEW'
      and coalesce(s.competitor_min_price_jod,s.competitor_max_price_jod) is not null
  ), ins as (
    insert into public.products(
      store_id,category_id,name,description,price,image_url,stock_qty,is_available,
      compare_at_price,barcode,unit,is_featured,brand_id,name_en,sku,pack_size,
      search_keywords,sort_order,sale_type,base_unit,inventory_scale,price_per_unit,
      min_qty,qty_step,allow_amount_purchase
    )
    select
      s.store_id,
      c.id,
      s.live_name,
      null,
      s.live_price,
      s.image_url,
      100,
      true,
      null,
      s.barcode,
      'قطعة',
      false,
      b.id,
      s.live_name,
      s.live_sku,
      s.pack_size,
      trim(concat_ws(' ',s.brand_text,s.product_name,s.pack_size,s.category_name)),
      0,
      'piece',
      'piece',
      1,
      s.live_price,
      1,
      1,
      false
    from src s
    join public.categories c on c.store_id=s.store_id and c.name=s.target_category_name and c.is_active=true
    left join lateral (
      select b1.id
      from public.brands b1
      where b1.store_id=s.store_id
        and s.brand_text is not null
        and lower(trim(s.brand_text))<>'generic'
        and (lower(b1.name)=lower(trim(s.brand_text)) or lower(coalesce(b1.name_en,''))=lower(trim(s.brand_text)))
      order by b1.created_at
      limit 1
    ) b on true
    where not exists (
      select 1 from public.products p where p.store_id=s.store_id and p.sku=s.live_sku
    )
    returning id,store_id,sku,price
  )
  select count(*) into v_inserted from ins;

  update private.catalog_import_staging s
  set altayebat_price_jod=p.price,
      stock_qty=p.stock_qty,
      is_available=p.is_available,
      matched_product_id=p.id,
      review_status='LIVE_FROM_BENCHMARK',
      notes=concat_ws(' | ',nullif(s.notes,''),'Published live from Benchmark v2 using competitor minimum reference price'),
      updated_at=now()
  from public.products p
  where s.benchmark_version='Benchmark v2'
    and s.match_status='APPROVED_NEW'
    and p.store_id=s.store_id
    and p.sku=('BENCH-V2-' || lpad(s.candidate_id::text,4,'0'));

  get diagnostics v_updated_staging = row_count;

  return jsonb_build_object(
    'inserted_products',v_inserted,
    'updated_staging_rows',v_updated_staging,
    'live_total',(select count(*) from public.products p where p.sku like 'BENCH-V2-%')
  );
end;
$$;

revoke all on function private.publish_benchmark_v2_candidates() from public, anon, authenticated;
grant execute on function private.publish_benchmark_v2_candidates() to service_role;
