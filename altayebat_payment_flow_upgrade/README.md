# Altayebat — Payment Flow Upgrade

هذا الباكيج يقفل مسار الدفع من طرف الزبون + الـAdmin + Supabase بدون ترك طلبات Card معلقة بلا عملية دفع.

## ما الذي يتغير؟

### Flutter
- يمنع اختيار **CliQ** إذا لم يكن Alias مضافًا.
- يمنع اختيار **Visa/Mastercard** إذا PayTabs غير مفعّل.
- يعمل **Preflight** قبل إنشاء Card order.
- إذا فشل PayTabs قبل إنشاء `tran_ref`: يلغي الطلب تلقائيًا ويعيد المخزون.
- لا يمسح السلة في Card إلا بعد بدء عملية الدفع فعليًا.
- يصلح قيمة `substitute_policy` من `no_substitute` غير المقبولة إلى `remove_item`.
- شاشة تتبع جديدة:
  - CliQ Alias + المبلغ + نسخ Alias.
  - إرسال إثبات CliQ عبر WhatsApp عند وجود رقم المول.
  - إعادة محاولة بدء Card payment فقط إذا لم يوجد `payment_reference`.
  - Reconcile إذا بدأت العملية.
  - تحديث تلقائي + polling احتياطي.

### Admin
Route جديد:
`/dashboard/settings`

منه تضبط:
- CliQ Alias
- اسم المستفيد
- رقم هاتف/WhatsApp المول
- مشاهدة حالة جاهزية PayTabs بدون كشف أي secret.

### Supabase
- `get_store_payment_config`
- `admin_update_store_payment_config`
- `cancel_unstarted_card_order`
- Edge Function: `payment-readiness`
- Hardened `create-card-payment` يمنع إنشاء PayTabs transaction ثانية لنفس الطلب.

## Backend LIVE

تم تطبيق الـSQL والـEdge Functions على:
`Altayebat-MultiStore (wfvuojrhxewogdnynytf)`

يبقى فقط إدخال بيانات PayTabs السرية من لوحة Supabase إذا لم تكن موجودة:
- `PAYTABS_SERVER_KEY`
- `PAYTABS_PROFILE_ID`

اختياري:
- `PAYTABS_BASE_URL=https://secure-jordan.paytabs.com`

**لا تضع Server Key داخل Flutter / Vercel / GitHub.**

## التثبيت المحلي

فك الضغط داخل:
`C:\Projects\altayebat_app\altayebat_payment_flow_upgrade`

ثم:

```powershell
cd C:\Projects\altayebat_app\altayebat_payment_flow_upgrade
powershell -ExecutionPolicy Bypass -File .\install_payment_flow.ps1
```

السكريبت:
1. يعمل Backup.
2. يركب الملفات.
3. `dart format`.
4. `flutter analyze`.
5. `flutter test`.
6. `npm run build` للـAdmin.

بعد النجاح:

```powershell
cd C:\Projects\altayebat_app
git status --short
git diff --check
```

ثم راجع وارفع على branch:
`chatgpt-production-upgrade`
