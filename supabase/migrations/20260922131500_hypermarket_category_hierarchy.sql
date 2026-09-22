do $$
declare
  v_store uuid := '61e6f35d-7004-4a33-948c-b297ba446678';
begin
  insert into public.categories (store_id, name, sort_order, is_active)
  select v_store, x.name, x.sort_order, true
  from (values
    ('الطازج واللحوم', 10),
    ('الألبان والمبردات', 20),
    ('البقالة', 30),
    ('سناكات وحلويات', 40),
    ('المشروبات والقهوة', 50),
    ('مجمدات ووجبات جاهزة', 60),
    ('المنزل والتنظيف', 70),
    ('العناية والطفل', 80)
  ) as x(name, sort_order)
  where not exists (
    select 1 from public.categories c
    where c.store_id = v_store and c.name = x.name and c.parent_id is null
  );

  update public.categories child
  set parent_id = parent.id
  from public.categories parent
  where child.store_id = v_store
    and parent.store_id = v_store
    and parent.parent_id is null
    and (
      (parent.name = 'الطازج واللحوم' and child.name in ('اللحوم والدواجن'))
      or (parent.name = 'الألبان والمبردات' and child.name in ('الألبان والأجبان'))
      or (parent.name = 'البقالة' and child.name in (
        'الأرز','بقوليات','الزيوت','معكرونة وشعيرية','مرقة وشوربات',
        'سكر ومستلزمات الخَبز','معلبات وصلصات','طحينية وحلاوة ومربى',
        'بهارات وأعشاب','خبز ومخبوزات','تمور وعسل','أخرى'
      ))
      or (parent.name = 'سناكات وحلويات' and child.name in ('السناكات والحلويات','مكسرات'))
      or (parent.name = 'المشروبات والقهوة' and child.name in ('المشروبات','قهوة'))
      or (parent.name = 'مجمدات ووجبات جاهزة' and child.name in ('المجمدات'))
      or (parent.name = 'المنزل والتنظيف' and child.name in (
        'غسيل الملابس','تنظيف المنزل والجلي','مناديل وورقيات','مستهلكات منزلية'
      ))
      or (parent.name = 'العناية والطفل' and child.name in ('العناية الشخصية','عناية الأطفال'))
    )
    and child.id <> parent.id;

  update public.categories c
  set image_url = (
    select p.image_url
    from public.products p
    where p.store_id = c.store_id
      and p.category_id = c.id
      and nullif(trim(p.image_url), '') is not null
    order by p.is_featured desc nulls last, p.stock_qty desc nulls last, p.created_at desc
    limit 1
  )
  where c.store_id = v_store
    and c.is_active = true
    and nullif(trim(c.image_url), '') is null
    and exists (
      select 1
      from public.products p
      where p.store_id = c.store_id
        and p.category_id = c.id
        and nullif(trim(p.image_url), '') is not null
    );

  update public.categories parent
  set image_url = (
    select child.image_url
    from public.categories child
    where child.store_id = parent.store_id
      and child.parent_id = parent.id
      and child.is_active = true
      and nullif(trim(child.image_url), '') is not null
    order by child.sort_order, child.name
    limit 1
  )
  where parent.store_id = v_store
    and parent.parent_id is null
    and nullif(trim(parent.image_url), '') is null;

  update public.categories c
  set image_url = (
    select p.image_url
    from public.products p
    where p.store_id = v_store
      and nullif(trim(p.image_url), '') is not null
    order by p.is_featured desc nulls last, p.stock_qty desc nulls last, p.created_at desc
    limit 1
  )
  where c.store_id = v_store
    and c.is_active = true
    and nullif(trim(c.image_url), '') is null;
end $$;

create index if not exists idx_categories_store_parent_active_sort
  on public.categories (store_id, parent_id, is_active, sort_order, name);
