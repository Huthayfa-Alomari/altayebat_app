-- Hypermarket-style two-level category taxonomy for the customer storefront.
-- Existing product -> category assignments are preserved. We only add parent
-- categories and attach the current leaf categories beneath them.

insert into public.categories (store_id, name, name_en, slug, sort_order, is_active)
select s.id, v.name, v.name_en, v.slug, v.sort_order, true
from public.stores s
cross join (
  values
    ('الطازج واللحوم', 'Fresh & Meat', 'fresh-meat', 10),
    ('الألبان والمبردات', 'Dairy & Chilled', 'dairy-chilled', 20),
    ('المواد الغذائية', 'Food Cupboard', 'food-cupboard', 30),
    ('الأطعمة المجمدة', 'Frozen Food', 'frozen-food', 40),
    ('المشروبات والقهوة', 'Beverages & Coffee', 'beverages-coffee', 50),
    ('السناكات والحلويات', 'Snacks & Sweets', 'snacks-sweets', 60),
    ('المنزل والتنظيف', 'Home & Cleaning', 'home-cleaning', 70),
    ('العناية والجمال', 'Personal Care & Beauty', 'personal-care-beauty', 80),
    ('الأطفال', 'Baby', 'baby', 90),
    ('متفرقات', 'More', 'more', 100)
) as v(name, name_en, slug, sort_order)
on conflict do nothing;

-- Fresh & meat
update public.categories c
set parent_id = p.id,
    sort_order = case c.name
      when 'اللحوم والدواجن' then 10
      when 'خبز ومخبوزات' then 20
      when 'الخضار والفواكه' then 30
      else c.sort_order
    end
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'fresh-meat'
  and c.name in ('اللحوم والدواجن', 'خبز ومخبوزات', 'الخضار والفواكه')
  and c.id <> p.id;

-- Dairy & chilled
update public.categories c
set parent_id = p.id,
    sort_order = case c.name
      when 'الألبان والأجبان' then 10
      when 'ألبان' then 20
      else c.sort_order
    end
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'dairy-chilled'
  and c.name in ('الألبان والأجبان', 'ألبان')
  and c.id <> p.id;

-- Food cupboard
update public.categories c
set parent_id = p.id,
    sort_order = case c.name
      when 'الأرز' then 10
      when 'بقوليات' then 20
      when 'الزيوت' then 30
      when 'معكرونة وشعيرية' then 40
      when 'بهارات وأعشاب' then 50
      when 'معلبات وصلصات' then 60
      when 'مرقة وشوربات' then 70
      when 'سكر ومستلزمات الخَبز' then 80
      when 'طحينية وحلاوة ومربى' then 90
      when 'تمور وعسل' then 100
      else c.sort_order
    end
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'food-cupboard'
  and c.name in (
    'الأرز',
    'بقوليات',
    'الزيوت',
    'معكرونة وشعيرية',
    'بهارات وأعشاب',
    'معلبات وصلصات',
    'مرقة وشوربات',
    'سكر ومستلزمات الخَبز',
    'طحينية وحلاوة ومربى',
    'تمور وعسل'
  )
  and c.id <> p.id;

-- Frozen food
update public.categories c
set parent_id = p.id, sort_order = 10
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'frozen-food'
  and c.name = 'المجمدات'
  and c.id <> p.id;

-- Beverages & coffee
update public.categories c
set parent_id = p.id,
    sort_order = case c.name
      when 'المشروبات' then 10
      when 'قهوة' then 20
      else c.sort_order
    end
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'beverages-coffee'
  and c.name in ('المشروبات', 'قهوة')
  and c.id <> p.id;

-- Snacks & sweets
update public.categories c
set parent_id = p.id,
    sort_order = case c.name
      when 'السناكات والحلويات' then 10
      when 'مكسرات' then 20
      else c.sort_order
    end
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'snacks-sweets'
  and c.name in ('السناكات والحلويات', 'مكسرات')
  and c.id <> p.id;

-- Home & cleaning
update public.categories c
set parent_id = p.id,
    sort_order = case c.name
      when 'تنظيف المنزل والجلي' then 10
      when 'غسيل الملابس' then 20
      when 'مناديل وورقيات' then 30
      when 'مستهلكات منزلية' then 40
      else c.sort_order
    end
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'home-cleaning'
  and c.name in (
    'تنظيف المنزل والجلي',
    'غسيل الملابس',
    'مناديل وورقيات',
    'مستهلكات منزلية'
  )
  and c.id <> p.id;

-- Personal care
update public.categories c
set parent_id = p.id, sort_order = 10
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'personal-care-beauty'
  and c.name = 'العناية الشخصية'
  and c.id <> p.id;

-- Baby
update public.categories c
set parent_id = p.id, sort_order = 10
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'baby'
  and c.name = 'عناية الأطفال'
  and c.id <> p.id;

-- More
update public.categories c
set parent_id = p.id, sort_order = 10
from public.categories p
where p.store_id = c.store_id
  and p.slug = 'more'
  and c.name = 'أخرى'
  and c.id <> p.id;

-- Give every leaf category a real product photo when no category artwork was
-- uploaded manually. Prefer mirrored Supabase Storage images.
update public.categories c
set image_url = (
  select p.image_url
  from public.products p
  where p.store_id = c.store_id
    and p.category_id = c.id
    and p.image_url is not null
    and btrim(p.image_url) <> ''
  order by
    (p.image_url like '%/storage/v1/object/public/product-images/%') desc,
    p.is_featured desc,
    coalesce(p.stock_qty, 0) desc,
    p.created_at desc
  limit 1
)
where c.image_url is null
  and exists (
    select 1
    from public.products p
    where p.store_id = c.store_id
      and p.category_id = c.id
      and p.image_url is not null
      and btrim(p.image_url) <> ''
  );

-- Parent artwork inherits the first available child artwork. Admins can
-- replace any of these images/GIFs later without changing the hierarchy.
update public.categories parent
set image_url = (
  select child.image_url
  from public.categories child
  where child.store_id = parent.store_id
    and child.parent_id = parent.id
    and child.is_active = true
    and child.image_url is not null
    and btrim(child.image_url) <> ''
  order by child.sort_order, child.name
  limit 1
)
where parent.parent_id is null
  and parent.slug in (
    'fresh-meat',
    'dairy-chilled',
    'food-cupboard',
    'frozen-food',
    'beverages-coffee',
    'snacks-sweets',
    'home-cleaning',
    'personal-care-beauty',
    'baby',
    'more'
  )
  and parent.image_url is null;
