export const metadata = {
  title: "حذف الحساب | أسواق الطيبات",
  description: "طلب حذف حساب وبيانات تطبيق أسواق الطيبات",
}

const whatsapp =
  "https://wa.me/962788570246?text=" +
  encodeURIComponent(
    "مرحباً أسواق الطيبات، أريد طلب حذف حسابي وبياناتي من التطبيق.",
  )

export default function AccountDeletionPage() {
  return (
    <main dir="rtl" className="mx-auto max-w-2xl px-5 py-10 text-right leading-8 text-gray-800">
      <h1 className="mb-2 text-3xl font-black text-gray-950">طلب حذف حساب أسواق الطيبات</h1>
      <p className="mb-8 text-sm text-gray-500">آخر تحديث: 20 سبتمبر 2026</p>

      <div className="space-y-5">
        <p>
          إذا كان التطبيق متاحًا لديك، فالطريقة الأسرع هي: حسابي ← حذف الحساب
          وبياناتي. هذا ينشئ طلبًا مرتبطًا بحسابك المسجل.
        </p>
        <p>
          إذا لم تتمكن من الدخول إلى التطبيق، يمكنك بدء الطلب من خارج التطبيق عبر
          واتساب. سنطلب معلومات كافية للتحقق من أنك صاحب الحساب قبل تنفيذ الحذف.
        </p>
        <a
          href={whatsapp}
          className="inline-flex rounded-xl bg-green-600 px-5 py-3 font-bold text-white"
          rel="noreferrer"
          target="_blank"
        >
          بدء طلب الحذف عبر واتساب
        </a>
        <p>
          يشمل الطلب حذف أو إلغاء ربط بيانات الحساب التي لا يلزم الاحتفاظ بها.
          قد نحتفظ بسجلات معاملات أو فواتير محدودة إذا كان الاحتفاظ بها مطلوبًا
          قانونيًا أو محاسبيًا، مع تقييد استخدامها لهذه الأغراض.
        </p>
        <p>للتواصل الهاتفي: 0788570246.</p>
      </div>
    </main>
  )
}
