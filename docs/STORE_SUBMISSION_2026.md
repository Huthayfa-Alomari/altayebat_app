# أسواق الطيبات — حزمة تجهيز المتجرين

تاريخ المراجعة: 28 سبتمبر 2026. هذه الحزمة تجهز ملفات البناء والهوية ونصوص المتجر؛ لا تعني أن النسخ رُفعت أو أن مراجعة المتجرين اكتملت.

## هوية النسخة

| الحقل | القيمة من المشروع |
|---|---|
| اسم التطبيق | أسواق الطيبات |
| Android applicationId / iOS Bundle ID | `com.altayebat.app` |
| إصدار Flutter الحالي | `0.3.0+3` |
| Android target/compile SDK | API 36 |
| iOS target | iPhone، iOS 15+ |
| الفئة المقترحة | Shopping / التسوق |
| الأيقونة | `store_assets/app_icon_1024.png` لـ iOS، و`store_assets/play_icon_512.png` لـ Play |
| صورة Play الترويجية | `store_assets/play_feature_graphic_1024x500.png` |

قبل إدخال التطبيق في المتجرين تأكد من أن معرف الحزمة ليس مستخدمًا لتطبيق آخر في حساباتكم. حافظ على نفس المفتاح الدائم ورقم إصدار أعلى عند كل تحديث.

## نص عربي جاهز للمراجعة

**اسم المتجر:** أسواق الطيبات

**وصف Google Play القصير:** تسوّق احتياجات بيتك من أسواق الطيبات وتابع طلبك بسهولة.

**عنوان فرعي لـ App Store:** تسوّق واطلب احتياجات بيتك

**الوصف:**

أسواق الطيبات تتيح لك تصفح الأقسام والمنتجات، البحث عن احتياجاتك، إضافة المنتجات إلى السلة وإرسال الطلب للتوصيل. يمكنك متابعة حالة الطلب والعودة إلى طلباتك السابقة، والاطلاع على العروض والإشعارات عندما تكون متاحة. اختر عنوان التوصيل وأكمل الطلب من داخل التطبيق.

تظهر الأسعار والتوافر ورسوم التوصيل النهائية قبل تأكيد الطلب. بعض الميزات، مثل الدفع الإلكتروني والمساعد الذكي، تعتمد على تفعيلها في المتجر. للاستفسارات أو المساعدة، يمكنك الوصول إلى خدمة العملاء من صفحة حسابي.

**كلمات مفتاحية مقترحة لـ App Store:** بقالة,مواد غذائية,توصيل,تسوق,عروض,خضار,منزل

لا تنشر وصفًا إنجليزيًا يعد بواجهة مترجمة بالكامل قبل استكمال وترجمة الشاشات الثانوية ونصوص البيانات؛ الاختيار الحالي يترجم واجهات التسوق الأساسية ويعرض أسماء المنتجات الإنجليزية إذا توفرت.

## صور الشاشة المطلوبة

التقط لقطات حقيقية من نسخة الإنتاج على الأجهزة أو المحاكيات بعد ربط بيانات المتجر. لا تستخدم صورًا وهمية أو بيانات عميل فعلية. تسلسل مناسب: الرئيسية، الأقسام الفرعية، تفاصيل المنتج، السلة، اختيار التوصيل، متابعة الطلب. أظهر الوضعين العربي والإنجليزي فقط بعد اكتمال فحص الترجمة.

- Google Play: لقطات هاتف، والأيقونة 512×512 والصورة الترويجية 1024×500؛ راجع المقاسات والمحتوى النهائي في Play Console.
- App Store: لقطة iPhone واحدة على الأقل بالمقاسات التي يقبلها App Store Connect لفئة 6.9 بوصة (مثل 1320×2868 أو 1290×2796) أو 6.5 بوصة. حُصر البناء على iPhone حتى لا تُطلب لقطات iPad قبل اختبار واجهته.

## Android — ملف AAB دائم التوقيع

1. أنشئ التطبيق في Play Console بمعرف `com.altayebat.app`، وفعّل Play App Signing. إذا سبق نشر هذا المعرف فاستخدم مفتاح الرفع الموجود، لا مفتاحًا جديدًا.
2. اتبع `docs/ANDROID_PLAY_SIGNING.md` لضبط `ANDROID_RELEASE_KEYSTORE_BASE64` و`ANDROID_RELEASE_STORE_PASSWORD` و`ANDROID_RELEASE_KEY_ALIAS` و`ANDROID_RELEASE_KEY_PASSWORD` في GitHub Actions، مع `FIREBASE_API_KEY` الصحيح.
3. شغّل workflow **Android Play Release** بعد نجاح quality checks؛ الناتج `app-release.aab` وملف SHA-256 ومرجع الـ commit. ارفع AAB إلى مسار اختبار داخلي أولًا، راجع فحص توافق صفحات الذاكرة 16KB في Play Console، وافحص تثبيته والدفع والطلب والإشعارات على جهاز حقيقي.
4. أدخل URL عامًا يصل إلى `/privacy` في صفحة المتجر وURL عامًا يصل إلى `/account-deletion` في نموذج حذف الحساب. المساران موجودان في `Admin/src/app` لكن يجب تأكيد النطاق المنشور وإمكانية فتحهما بلا تسجيل دخول.
5. أكمل Data Safety بالرجوع إلى `docs/GOOGLE_PLAY_DATA_SAFETY.md` بعد مقارنة كل إجابة مع نسخة الإنتاج الفعلية. إذا كان حساب المطور شخصيًا أُنشئ بعد 13 نوفمبر 2023، راجع شرط الاختبار المغلق (12 مختبرًا لمدة 14 يومًا) في Play Console.

## iPhone — ملف IPA موقّع للمتجر

1. يلزم حساب Apple Developer، وتسجيل Bundle ID `com.altayebat.app` وتفعيل Push Notifications، ثم إنشاء تطبيق في App Store Connect. على Firebase سجّل تطبيق iOS بهذا المعرف واربط مفتاح APNs المناسب.
2. استخرج شهادة **Apple Distribution** بصيغة P12 مع المفتاح الخاص، وملف **App Store provisioning profile** لهذا المعرف مع Push Notifications. احتفظ بهما خارج Git.
3. أضف الأسرار التالية إلى GitHub Actions: `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`، `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`، `APPLE_APP_STORE_PROFILE_BASE64`، `APPLE_TEAM_ID`، `APPLE_CI_KEYCHAIN_PASSWORD`، `FIREBASE_API_KEY`، `FIREBASE_IOS_APP_ID`.
4. شغّل workflow **iOS App Store Release**. يولّد مشروع iOS، يضيف أيقونة المتجر ووصف أذونات الكاميرا والموقع، يتحقق من تطابق ملف التوقيع مع التطبيق ويدمج شهادة التوزيع، ثم يبني IPA موقّعًا ويرفق SHA-256 ومرجع الـ commit. لا يرفع التطبيق تلقائيًا إلى Apple.
5. ارفع IPA بـ Transporter أو Xcode إلى TestFlight. اختبر OTP، الإشعارات، الموقع، الطلب، الدفع والروابط، ثم أكمل App Privacy، سياسة الخصوصية، معلومات الدعم (المسار `/support` موجود في Admin)، التصنيف العمري، لقطة iPhone، وإجابات التشفير في App Store Connect.

## ما يزال يحتاج تحققًا قبل النشر العام

- تشغيل فحوص Flutter والبناء على macOS/Android CI؛ البيئة الحالية لا تحتوي حزم Flutter المحلية ولا صلاحية توقيع المتجرين.
- استكمال ترجمة الشاشات الثانوية إلى الإنجليزية وفحص الوضع الداكن على الأجهزة، خصوصًا الدفع والمندوب.
- تأكيد سياسة الخصوصية وحذف الحساب على نطاق عام، وتدقيق سياسة الاحتفاظ بالبيانات مع صاحب المتجر.
- التقاط صور الشاشة من نسخة حقيقية مع بيانات اختبار، ومراجعة الاسم والوصف والصورة الترويجية مع صاحب المتجر.
- تأكيد حالة حسابي المطور، مفاتيح التوقيع الدائمة، إعدادات Firebase/APNs، الأسعار ونطاق التوصيل والمنتجات المتاحة قبل إطلاقها للجمهور.

## المراجع الرسمية

- Google Play API target: https://support.google.com/googleplay/android-developer/answer/11926878
- Google Play previews: https://support.google.com/googleplay/android-developer/answer/9866151
- Google Play deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Google Play testing: https://support.google.com/googleplay/android-developer/answer/14151465
- Flutter iOS release: https://docs.flutter.dev/deployment/ios
- Apple SDK minimum: https://developer.apple.com/news/upcoming-requirements/
- Apple screenshots: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- Apple account deletion: https://developer.apple.com/support/offering-account-deletion-in-your-app/
