# أسواق الطيبات — تطبيق الزبون

تطبيق Flutter للتسوق من أسواق الطيبات، مرتبط بـ Supabase، ويدعم تصفح التصنيفات والمنتجات، البحث، السلة، إنشاء الطلبات، تتبع حالة الطلب لحظيًا، وطلبات التواصل مع موظف المول.

## المتطلبات

- Flutter stable (المشروع مستهدف لـ Dart 3.9+)
- مشروع Supabase مهيأ بالجداول والسياسات المطلوبة
- تفعيل Anonymous Sign-ins في Supabase Auth لتجربة الدخول الحالية

## إعداد التطبيق

القيم العامة غير السرية تُمرّر عبر `--dart-define`:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY \
  --dart-define=STORE_ID=YOUR_STORE_UUID
```

يمكن بناء Android بنفس القيم:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY \
  --dart-define=STORE_ID=YOUR_STORE_UUID
```

> لا تضع `service_role` أو أي Secret Key داخل تطبيق Flutter. المفتاح المسموح للعميل هو Supabase Publishable Key فقط، والحماية الفعلية تتم عبر RLS وسياسات قاعدة البيانات.

## قاعدة البيانات

قبل اعتماد checkout الجديد، راجع ثم طبّق الملف:

`../supabase/production_hardening.sql`

الملف يضيف:

- RLS للجداول المكشوفة للتطبيق ولوحة الإدارة.
- عزل كل مدير على المول المرتبط به في `store_admins`.
- RPC باسم `create_order` لإنشاء الطلب بشكل ذري داخل PostgreSQL.
- التحقق من السعر والمخزون داخل قاعدة البيانات بدل الوثوق بقيم العميل.
- خصم المخزون داخل نفس transaction.
- سياسات وصول للطلبات، عناصر الطلب، مواقع التوصيل، وطلبات التواصل.
- فهارس للاستعلامات الأساسية.

**مهم:** لا يعمل checkout الإنتاجي قبل تطبيق SQL وإنشاء الدالة `public.create_order` في مشروع Supabase.

## Android

Application ID الحالي:

`com.altayebat.app`

الـrelease build ما زال يستخدم debug signing لتسهيل التشغيل المحلي. قبل النشر على Google Play أنشئ keystore خاص بالإنتاج وعدّل `android/app/build.gradle.kts` لاستخدام release signing الحقيقي. لا ترفع ملف keystore أو كلمات المرور إلى GitHub.

## فحوص الجودة

GitHub Actions يشغّل تلقائيًا:

```bash
flutter pub get
flutter analyze
flutter test
```

كما يبلغ عن ملفات Dart التي تحتاج `dart format`.

## ملاحظات تشغيلية

- السلة تمنع تجاوز `stock_qty` الموجود لدى العميل، بينما قاعدة البيانات تعيد التحقق من المخزون وقت checkout.
- السعر النهائي لا يؤخذ من السلة؛ يتم احتسابه في قاعدة البيانات من جدول `products`.
- البحث يتم عبر Supabase على اسم المنتج.
- تتبع الطلب يعتمد على Supabase Realtime/stream، لذلك يجب أن تسمح إعدادات Realtime بالجدول المطلوب بحسب إعداد مشروعك.
