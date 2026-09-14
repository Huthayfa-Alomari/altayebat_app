"use client";

import { FormEvent, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type LoyaltyProgram = {
  is_enabled: boolean;
  program_name: string;
  baskets_required: number;
  min_order_total: number;
  reward_title: string;
};

type LoyaltyStats = {
  members: number;
  lifetimeBaskets: number;
  rewardsAvailable: number;
  rewardsRedeemed: number;
};

export default function LoyaltyManager({
  storeId,
  initialProgram,
  stats,
}: {
  storeId: string;
  initialProgram: LoyaltyProgram;
  stats: LoyaltyStats;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [enabled, setEnabled] = useState(initialProgram.is_enabled);
  const [programName, setProgramName] = useState(initialProgram.program_name);
  const [basketsRequired, setBasketsRequired] = useState(
    String(initialProgram.baskets_required),
  );
  const [minOrderTotal, setMinOrderTotal] = useState(
    String(initialProgram.min_order_total),
  );
  const [rewardTitle, setRewardTitle] = useState(initialProgram.reward_title);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (busy) return;

    const required = Number(basketsRequired);
    const minimum = Number(minOrderTotal);
    if (!Number.isInteger(required) || required < 2 || required > 20) {
      setMessage("عدد السلال لازم يكون رقمًا صحيحًا بين 2 و20.");
      return;
    }
    if (!Number.isFinite(minimum) || minimum < 0) {
      setMessage("الحد الأدنى للطلب غير صالح.");
      return;
    }

    setBusy(true);
    setMessage(null);
    try {
      const { error } = await supabase.from("loyalty_programs").upsert({
        store_id: storeId,
        is_enabled: enabled,
        program_name: programName.trim() || "مكافآت الطيبات",
        baskets_required: required,
        min_order_total: minimum,
        reward_type: "free_delivery",
        reward_title: rewardTitle.trim() || "التوصيل علينا بالطلب القادم",
        updated_at: new Date().toISOString(),
      });
      if (error) throw error;
      setMessage("تم حفظ برنامج المكافآت.");
    } catch (error) {
      const text = error instanceof Error ? error.message : String(error);
      if (text.includes("loyalty_programs")) {
        setMessage("ميزة المكافآت تحتاج تشغيل migration الجديدة على Supabase أولًا.");
      } else {
        setMessage(text);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-6">
      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="مشتركين عندهم رصيد" value={stats.members} />
        <StatCard label="سلال جُمعت" value={stats.lifetimeBaskets} />
        <StatCard label="مكافآت جاهزة" value={stats.rewardsAvailable} />
        <StatCard label="توصيلات مجانية استُخدمت" value={stats.rewardsRedeemed} />
      </section>

      <form
        onSubmit={save}
        className="space-y-5 rounded-2xl border border-sky-200 bg-gradient-to-bl from-white via-white to-sky-50 p-5"
      >
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-bold text-sky-700">بدل النقاط التقليدية</p>
            <h2 className="mt-1 text-xl font-black">🧺 سلال الطيبات</h2>
            <p className="mt-1 max-w-2xl text-sm leading-6 text-gray-600">
              كل طلب مؤهل يتم تسليمه يملأ سلة واحدة. عند اكتمال عدد السلال
              المحدد، يحصل الزبون على توصيل مجاني يُطبّق تلقائيًا على طلبه القادم.
              ما في تحويل نقاط ولا كوبونات.
            </p>
          </div>
          <label className="flex items-center gap-3 rounded-xl border border-sky-200 bg-white px-4 py-3 text-sm font-bold">
            <input
              type="checkbox"
              checked={enabled}
              onChange={(event) => setEnabled(event.target.checked)}
              className="h-5 w-5"
            />
            {enabled ? "البرنامج مفعّل" : "البرنامج متوقف"}
          </label>
        </div>

        <div className="grid gap-4 lg:grid-cols-2">
          <label className="space-y-1 text-sm font-medium">
            <span>اسم البرنامج داخل التطبيق</span>
            <input
              value={programName}
              onChange={(event) => setProgramName(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5"
              placeholder="مكافآت الطيبات"
            />
          </label>

          <label className="space-y-1 text-sm font-medium">
            <span>المكافأة</span>
            <input
              value={rewardTitle}
              onChange={(event) => setRewardTitle(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5"
              placeholder="التوصيل علينا بالطلب القادم"
            />
          </label>

          <label className="space-y-1 text-sm font-medium">
            <span>كم سلة حتى يفتح المكافأة؟</span>
            <input
              type="number"
              min="2"
              max="20"
              step="1"
              value={basketsRequired}
              onChange={(event) => setBasketsRequired(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5"
              required
            />
            <p className="text-xs text-gray-500">
              مثال: 5 يعني كل خمسة طلبات مؤهلة = توصيل مجاني.
            </p>
          </label>

          <label className="space-y-1 text-sm font-medium">
            <span>أقل قيمة طلب تحتسب سلة (د.أ)</span>
            <input
              type="number"
              min="0"
              step="0.5"
              value={minOrderTotal}
              onChange={(event) => setMinOrderTotal(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5"
              required
            />
            <p className="text-xs text-gray-500">
              الطلبات الصغيرة جدًا لن تُستخدم للتحايل على البرنامج.
            </p>
          </label>
        </div>

        <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900">
          <strong>التجربة للزبون:</strong> بعد اكتمال السلال تظهر له هدية جاهزة،
          وأول طلب قادم عليه رسوم توصيل يأخذ التوصيل مجانًا تلقائيًا. إذا كان
          الطلب أصلًا بدون رسوم توصيل، تبقى الهدية محفوظة لطلب لاحق.
        </div>

        {message ? (
          <div className="rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm">
            {message}
          </div>
        ) : null}

        <button
          type="submit"
          disabled={busy}
          className="rounded-xl bg-brand px-6 py-2.5 text-sm font-bold text-white disabled:opacity-50"
        >
          {busy ? "جاري الحفظ..." : "حفظ إعدادات المكافآت"}
        </button>
      </form>
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-4">
      <p className="text-xs text-gray-500">{label}</p>
      <p className="mt-2 text-2xl font-black text-gray-900">{value}</p>
    </div>
  );
}
