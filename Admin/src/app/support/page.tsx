export const metadata = {
  title: "الدعم والمساعدة | أسواق الطيبات",
  description: "طرق التواصل مع خدمة عملاء أسواق الطيبات",
}

export default function SupportPage() {
  return (
    <main dir="rtl" className="mx-auto max-w-2xl px-5 py-10 text-right leading-8 text-gray-800">
      <h1 className="mb-4 text-3xl font-black text-gray-950">الدعم والمساعدة</h1>
      <p className="mb-6">
        للاستفسار عن طلبك أو التوصيل أو الدفع أو التطبيق، تواصل مع فريق أسواق الطيبات.
        يرجى عدم إرسال كلمة مرور أو معلومات البطاقة البنكية عبر الرسائل.
      </p>
      <div className="flex flex-wrap gap-3">
        <a className="rounded-xl bg-blue-800 px-5 py-3 font-bold text-white" href="tel:+962788570246">
          اتصال: 0788570246
        </a>
        <a
          className="rounded-xl bg-green-700 px-5 py-3 font-bold text-white"
          href="https://wa.me/962788570246"
          target="_blank"
          rel="noopener noreferrer"
        >
          واتساب
        </a>
      </div>
      <p className="mt-8">
        يمكنك أيضًا مراجعة <a className="font-bold text-blue-800 underline" href="/privacy">سياسة الخصوصية</a>
        {" "}أو <a className="font-bold text-blue-800 underline" href="/account-deletion">طلب حذف الحساب</a>.
      </p>
    </main>
  )
}
