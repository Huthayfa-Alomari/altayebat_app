do $$
declare
  v_store uuid;
  v_grocery uuid;
  v_frozen uuid;
  v_cleaning uuid;
  v_drinks uuid;
  v_snacks uuid;
  v_dairy uuid;
  v_baby uuid;
  v_personal uuid;
begin
  select id into v_store from public.stores where slug='altayebat' limit 1;
  if v_store is null then return; end if;

  insert into public.categories(store_id,name,slug,sort_order,is_active)
  select v_store,x.name,x.slug,x.sort_order,true
  from (values
    ('العروض','offers',0),
    ('خضار وفواكه','fresh-produce',10),
    ('مخبوزات','bakery',20),
    ('ألبان وأجبان وبيض','dairy-eggs',30),
    ('لحوم ودواجن','meat-poultry',40),
    ('المجمدات','frozen',50),
    ('مشروبات','beverages',60),
    ('بقالة','grocery',70),
    ('حلويات وتسالي','snacks-sweets',80),
    ('التنظيف والمنزل','home-cleaning',90),
    ('العناية الشخصية','personal-care',100),
    ('احتياجات الطفل','baby',110),
    ('مستلزمات منزلية','household',120),
    ('حيوانات أليفة','pets',130)
  ) as x(name,slug,sort_order)
  where not exists(select 1 from public.categories c where c.store_id=v_store and c.parent_id is null and c.name=x.name);

  update public.categories c set slug=x.slug,sort_order=x.sort_order
  from (values
    ('العروض','offers',0),('خضار وفواكه','fresh-produce',10),('مخبوزات','bakery',20),
    ('ألبان وأجبان وبيض','dairy-eggs',30),('لحوم ودواجن','meat-poultry',40),('المجمدات','frozen',50),
    ('مشروبات','beverages',60),('بقالة','grocery',70),('حلويات وتسالي','snacks-sweets',80),
    ('التنظيف والمنزل','home-cleaning',90),('العناية الشخصية','personal-care',100),
    ('احتياجات الطفل','baby',110),('مستلزمات منزلية','household',120),('حيوانات أليفة','pets',130)
  ) as x(name,slug,sort_order)
  where c.store_id=v_store and c.parent_id is null and c.name=x.name and (c.slug is null or c.slug=x.slug);

  select id into v_grocery from public.categories where store_id=v_store and parent_id is null and name='بقالة' limit 1;
  select id into v_frozen from public.categories where store_id=v_store and parent_id is null and name='المجمدات' limit 1;
  select id into v_cleaning from public.categories where store_id=v_store and parent_id is null and name='التنظيف والمنزل' limit 1;
  select id into v_drinks from public.categories where store_id=v_store and parent_id is null and name='مشروبات' limit 1;
  select id into v_snacks from public.categories where store_id=v_store and parent_id is null and name='حلويات وتسالي' limit 1;
  select id into v_dairy from public.categories where store_id=v_store and parent_id is null and name='ألبان وأجبان وبيض' limit 1;
  select id into v_baby from public.categories where store_id=v_store and parent_id is null and name='احتياجات الطفل' limit 1;
  select id into v_personal from public.categories where store_id=v_store and parent_id is null and name='العناية الشخصية' limit 1;

  update public.categories set parent_id=v_grocery,slug='canned-food',sort_order=10 where store_id=v_store and name='معلبات' and id<>v_grocery;
  update public.categories set parent_id=v_grocery,slug='rice-oil',sort_order=20 where store_id=v_store and name='رز وزيت' and id<>v_grocery;
  update public.categories set parent_id=v_grocery,slug='flour-legumes',sort_order=30 where store_id=v_store and name='طحين وبقوليات' and id<>v_grocery;
  update public.categories set parent_id=v_frozen,slug='ice-cream',sort_order=10 where store_id=v_store and name='آيس كريم' and id<>v_frozen;
  update public.categories set parent_id=v_cleaning,slug='cleaners',sort_order=10 where store_id=v_store and name='منظفات' and id<>v_cleaning;

  insert into public.categories(store_id,parent_id,name,slug,sort_order,is_active)
  select v_store,x.parent_id,x.name,x.slug,x.sort_order,true
  from (values
    (v_grocery,'صلصات وتوابل','sauces-spices',40),(v_grocery,'مخللات وزيتون','pickles-olives',50),(v_grocery,'سكر وملح','sugar-salt',60),(v_grocery,'مكرونة ونودلز','pasta-noodles',70),(v_grocery,'قهوة وشاي','coffee-tea',80),
    (v_drinks,'مياه','water',10),(v_drinks,'عصائر','juices',20),(v_drinks,'مشروبات غازية','soft-drinks',30),(v_drinks,'مشروبات طاقة','energy-drinks',40),
    (v_frozen,'خضار مجمدة','frozen-vegetables',20),(v_frozen,'بطاطا ومقبلات','frozen-fries-appetizers',30),(v_frozen,'لحوم ودواجن مجمدة','frozen-meat-poultry',40),(v_frozen,'مخبوزات مجمدة','frozen-bakery',50),
    (v_dairy,'حليب','milk',10),(v_dairy,'أجبان','cheese',20),(v_dairy,'لبنة ولبن','labneh-yogurt',30),(v_dairy,'بيض','eggs',40),(v_dairy,'زبدة وقشطة','butter-cream',50),
    (v_snacks,'شوكولاتة','chocolate',10),(v_snacks,'شيبس','chips',20),(v_snacks,'بسكويت وويفر','biscuits-wafers',30),(v_snacks,'مكسرات','nuts',40),
    (v_cleaning,'غسيل الملابس','laundry',20),(v_cleaning,'تنظيف المنزل','home-cleaners',30),(v_cleaning,'مناديل وورقيات','tissues-paper',40),(v_cleaning,'أكياس نفايات','trash-bags',50),
    (v_personal,'العناية بالشعر','hair-care',10),(v_personal,'العناية بالفم','oral-care',20),(v_personal,'استحمام وعناية بالجسم','body-care',30),(v_personal,'حلاقة','shaving',40),
    (v_baby,'حفاضات','diapers',10),(v_baby,'حليب أطفال','baby-milk',20),(v_baby,'مناديل وعناية','baby-care',30)
  ) as x(parent_id,name,slug,sort_order)
  where x.parent_id is not null and not exists(select 1 from public.categories c where c.store_id=v_store and c.slug=x.slug);
end $$;
