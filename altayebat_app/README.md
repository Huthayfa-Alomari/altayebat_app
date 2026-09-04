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

راجع ثم طبّق ملفات Supabase بالترتيب التالي على الـschema المطلوب:

1. `../supabase/production_hardening.sql`
2. `../supabase/production_runtime_sync.sql`

الملف الأول يضيف طبقة الـRLS والمساعدات الأمنية والـcheckout الذري الأساسية. الملف الثاني يزامن عقد التشغيل الحالي الموجود في الإنتاج، بما يشمل:

- RPC باسم `create_order` يدعم `cash` و`cliq` و`card`.
- احتساب السعر ورسوم التوصيل داخل قاعدة البيانات بدل الوثوق بقيم العميل.
- خصم المخزون داخل نفس transaction.
- تخزين `payment_method` و`payment_status`.
- إنشاء سجل أولي في `order_status_history`.
- إبقاء active store قابلًا للقراءة من تطبيق الزبون مع المحافظة على عزل إدارة المولات.
- فهارس لمسارات الاستعلام الخاصة بحالة ومرجع الدفع.

**مهم:** لا يعمل checkout الإنتاجي قبل وجود الدالة ذات التوقيع التالي:

```text
public.create_order(p_store_id, p_items, p_payment_method)
```

تفاصيل وظائف PayTabs والأسرار المطلوبة موجودة في `../supabase/README.md`.

## Android release signing

Application ID الحالي:

`com.altayebat.app`

الـrelease build لم يعد يسمح بالنشر الفعلي اعتمادًا على debug signing. قبل بناء نسخة Release:

1. أنشئ upload/release keystore خاصًا بالتطبيق.
2. انسخ `android/key.properties.example` إلى `android/key.properties`.
3. ضع بيانات الـkeystore الحقيقية في `key.properties` وعدّل `storeFile` لمسار ملف الـJKS.
4. شغّل `flutter build appbundle --release ...`.

`key.properties` وملفات `*.jks`/`*.keystore` مستثناة من Git، لذلك لا ترفع كلمات المرور أو ملف المفتاح إلى GitHub.

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
- طلبات البطاقة تخصم المخزون عند إنشاء الطلب قبل اكتمال الدفع لمنع overselling. لذلك يجب أن توجد سياسة تشغيلية لإلغاء/إرجاع مخزون الطلبات التي يفشل أو يُترك دفعها.
