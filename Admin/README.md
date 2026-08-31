# أسواق الطيبات — لوحة الإدارة

لوحة Next.js لإدارة الطلبات والمنتجات والتصنيفات وطلبات التواصل لكل مول بشكل معزول حسب حساب المدير.

## المتطلبات

- Node.js 22+
- npm
- Supabase project
- مستخدم Supabase Auth مربوط بصف في `store_admins`

## الإعداد

انسخ ملف البيئة:

```bash
cp .env.local.example .env.local
```

ثم عرّف:

```env
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_YOUR_KEY
```

لا يوجد `NEXT_PUBLIC_STORE_ID`. هوية المول تؤخذ على السيرفر من `store_admins` بناءً على المستخدم المسجل دخوله.

## التشغيل

```bash
npm install
npm run dev
```

فحوص الإنتاج:

```bash
npm run typecheck
npm run build
npm audit --omit=dev --audit-level=high
```

## الأمان

- لا تستخدم `service_role` أو Secret Key في متغيرات تبدأ بـ `NEXT_PUBLIC_`.
- كل استعلامات الإدارة الأساسية مقيدة بـ `store_id` الخاص بالمدير، إضافة إلى RLS في قاعدة البيانات.
- طبّق `../supabase/production_hardening.sql` بعد مراجعته مع الـschema الفعلي قبل الإنتاج.
- HTTP hardening headers مضبوطة في `next.config.mjs`.

## الصفحات

- `/dashboard` — آخر الطلبات.
- `/dashboard/orders/[id]` — تفاصيل الطلب والعناصر.
- `/dashboard/products` — المنتجات والمخزون والتوفر.
- `/dashboard/categories` — التصنيفات.
- `/dashboard/support` — طلبات المكالمات الصوتية/الفيديو/الشات.
