update private.catalog_import_staging
set image_url = case category_name
  when 'أرز' then 'https://images.deliveryhero.io/image/product-information-management/67a362ade9324bb1b64f1962.jpg'
  when 'أكياس نفايات' then 'https://talabat.dhmedia.io/image/darkstores-jo/Jordan%20Items/JOR-6253501690032.jpg'
  when 'ألبان وأجبان' then 'https://www.chefsneed.com/cdn/shop/files/200-cheddar-slice-cheese-1-pouch-cheese-spread-almarai-original-imagq6fgnc9vzahz-Photoroom.jpg?v=1727333175&width=1445'
  when 'بيض' then 'https://qc-products-images.s3.ap-south-1.amazonaws.com/optimized-images/optimized_e174eddf-e117-4474-a5c5-8a3a3e3dc0cc.jpeg'
  when 'تونة ومأكولات بحرية معلبة' then 'https://bf1af2.akinoncloudcdn.com/products/2025/02/17/65294/8ce1b932-84aa-409f-ae06-9984cdb9b3ae.jpg'
  when 'حليب' then 'https://doos-cdn-v2.imgix.net/oqc4shfik64vgmbqaepm9kusklut'
  when 'خضار' then 'https://cyprus-faq.com/site/assets/files/19850/img_0112.webp'
  when 'دجاج طازج' then 'https://talabat.dhmedia.io/image/product-information-management/63b294fb7c2c343fff2e9415.JPG'
  when 'سكر ومحليات' then 'https://cdn.salla.sa/BZydV/1f440e8d-56b0-4040-912e-1cc1e61cde77-924.07809110629x1000-mHxXKTHSailmRiXwdVrnF3XZxPBjU8WEuZi1KM9O.png'
  when 'شوكولاتة' then 'https://moolocal.co.uk/cdn/shop/products/image_b86905c3-7dd0-4f1a-a47e-eb2c03c4e55d_800x.jpg?v=1614027879'
  when 'شيبس وسناكات' then 'https://www.dccbazar.com.bd/images/detailed/3/71K6mPh5a9L._SL1500_.jpg'
  when 'صلصات' then 'https://media.icn.com/media/storage/uploads/all/6784d05cbcbf1.webp'
  when 'طعام قطط' then 'https://st.bigc-cs.com/cdn-cgi/image/format%3Dwebp%2Cquality%3D90/public/media/catalog/product/12/88/8850125073012/8850125073012_2-20240913150718-.jpg'
  when 'طعام كلاب' then 'https://www.evcilbesinleri.com/idea/qf/09/myassets/products/845/kk-63002-1.jpg?revision=1740581216'
  when 'عصائر' then 'https://media.zid.store/4c014624-206d-43df-a6d3-064b19937af4/1ef741f1-8088-4120-99b7-53850f3aa735.jpg'
  when 'عناية أطفال' then 'https://talabat.dhmedia.io/image/talabat-nv/Hero_Images/Final/6253005866070.png?size=520'
  when 'عناية بالشعر' then 'https://f.nooncdn.com/p/pzsku/Z3BA85CEEF98F8A7F40A5Z/45/_/1777833054/95955992-54b3-43f1-8a5d-d23fd1cbde10.jpg?width=720'
  when 'فطور وسبريد' then 'https://i.ebayimg.com/images/g/RbkAAOSwEjZheDr6/s-l640.jpg'
  when 'فواكه' then 'https://masaegypt.com/assets/img/products/banana--1-kilo-67bf17d22e3e2.webp'
  when 'قهوة' then 'https://www.sharjahcoop.ae/medias/6254000115040-1200Wx1200H-003.jpg?context=bWFzdGVyfHNjc3w0NjYyNTF8aW1hZ2UvanBlZ3xjMk56TDJnMk1pOW9NMkl2T0RnME5UQXlNell3T0RnMk1pNXFjR2N8YjI0ZGM3NGMyYTM1ZDE4Y2ZjZmM0NGJkM2U2YWJmOWEyNjNjOThhYmE4ODBlMTJmMmEyODJiNjVmYzYwZTVmYw'
  when 'كريمة وطبخ' then 'https://m.media-amazon.com/images/I/61-b-81lcVL.jpg'
  when 'لبن ولبنة' then 'https://cdn.taw9eel.com/media/catalog/product/cache/1/image/519x/9df78eab33525d08d6e5fb8d27136e95/a/l/almc251-2_1_1.jpg'
  when 'مجمدات ووجبات جاهزة' then 'https://bf1af2.akinoncloudcdn.com/products/2024/09/07/57890/f380ba1d-b491-4ed0-bb39-f79555289bc8.jpg'
  when 'مخبوزات حلوة' then 'https://d226b0iufwcjmj.cloudfront.net/product-images/1434/10562571/11770569/large.jpg'
  when 'مستهلكات منزلية' then 'https://cdn.bueromarkt-ag.de/product/2f8ba738a0b048faf14bcaac2e32b103f3baf5e6-gummihandschuhe_vileda_comfort_und_care.jpg'
  when 'معكرونة' then 'https://jebnalak.com/cdn/shop/products/pastazara-spaghetti-3-434690.jpg?v=1621949149'
  when 'معلبات' then 'https://www.eaiia.org/CompanyProductPhotos/2433/2433.jpg'
  when 'منظفات' then 'https://images.deliveryhero.io/image/darkstores-jo/Jordan%20Items/JOR-6253339102615.jpg'
  when 'نودلز وشوربات' then 'https://tonymarket.shop/cdn/shop/files/IMG-3462_1285x1274.jpg?v=1704314113'
  else image_url end,
  updated_at=now()
where benchmark_version='Benchmark v2'
  and match_status='APPROVED_NEW'
  and image_url is null;

update public.products p
set image_url=s.image_url, updated_at=now()
from private.catalog_import_staging s
where s.matched_product_id=p.id
  and s.benchmark_version='Benchmark v2'
  and s.match_status='APPROVED_NEW'
  and s.image_url is not null;
