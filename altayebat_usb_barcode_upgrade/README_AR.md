# ترقية قارئ الباركود الخارجي — أسواق الطيبات

هذه الحزمة تضيف **مسح سريع بالباركود** إلى صفحة المنتجات في لوحة التحكم، مع الإبقاء على ماسح الكاميرا الحالي.

## ماذا يتغير؟

- يظهر مربع **مسح سريع بالباركود** أعلى `/dashboard/products`.
- عند فتح الصفحة يتم تركيز حقل الباركود تلقائيًا، لذلك قارئ USB من نوع HID/Keyboard يعمل مباشرة.
- إذا كان الباركود موجودًا:
  - يتم العثور على المنتج.
  - يظهر الاسم والسعر والمخزون.
  - يتم تمرير الصفحة إلى صف المنتج وتمييزه.
- إذا كان الباركود جديدًا:
  - يتم تعبئة الباركود تلقائيًا في نموذج إضافة منتج.
  - يتم الانتقال إلى النموذج والتركيز على اسم المنتج.
- ماسح **الكاميرا الحالي** يبقى موجودًا داخل حقول الباركود.
- لا توجد أي Migration جديدة لقاعدة البيانات؛ يعتمد التحديث على `admin_barcode_status` الموجود حاليًا.

## التثبيت

ضع ملف ZIP داخل:

`C:\Projects\altayebat_app`

ثم:

```powershell
cd C:\Projects\altayebat_app

Expand-Archive .\altayebat_usb_barcode_upgrade.zip . -Force

powershell -ExecutionPolicy Bypass -File .\altayebat_usb_barcode_upgrade\install_usb_barcode_upgrade.ps1
```

السكريبت:
1. يتأكد أن Barcode integration الحالي موجود.
2. ينشئ Backup.
3. يثبت التعديل.
4. يشغل `npm run build`.
5. إذا فشل الـBuild يعيد الملف القديم تلقائيًا.

## الاختبار

1. افتح `/dashboard/products`.
2. أوصل قارئ USB.
3. امسح باركود منتج معروف.
4. يجب أن يظهر المنتج ويتم تمييز صفه.
5. امسح باركود غير موجود.
6. يجب أن ينتقل إلى نموذج إضافة المنتج ويملأ الباركود تلقائيًا.
7. جرّب زر الكاميرا الموجود في حقل الباركود للتأكد أن مسح الكاميرا ما زال يعمل.

### ملاحظة قارئ USB
يفضل أن يكون الجهاز مضبوطًا ليضيف **Enter / CR** بعد قراءة الباركود. أغلب قارئات المتاجر تأتي بهذا الإعداد افتراضيًا. إذا كتب الرقم فقط ولم يبدأ البحث تلقائيًا، اضغط Enter أو فعّل Enter suffix من إعدادات القارئ.

## الرفع إلى Production

بعد نجاح الاختبار:

```powershell
cd C:\Projects\altayebat_app

git status --short
git add -A
git commit -m "feat: add USB barcode quick scan workflow"
git push origin chatgpt-production-upgrade
```

Vercel سيبني Admin تلقائيًا من branch `chatgpt-production-upgrade`.
