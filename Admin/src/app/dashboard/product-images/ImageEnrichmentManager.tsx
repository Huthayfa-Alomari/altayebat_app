"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Stats = {
  active: number;
  withImage: number;
  unchecked: number;
  matched: number;
  needsReview: number;
  notFound: number;
  errors: number;
};

type BatchResult = {
  ok?: boolean;
  processed?: number;
  external_lookups?: number;
  matched?: number;
  not_found?: number;
  needs_review?: number;
  errors?: number;
  remaining_unchecked?: number;
  total_matched?: number;
  total_needs_review?: number;
};

const EMPTY_STATS: Stats = {
  active: 0,
  withImage: 0,
  unchecked: 0,
  matched: 0,
  needsReview: 0,
  notFound: 0,
  errors: 0,
};

export default function ImageEnrichmentManager({ storeId }: { storeId: string }) {
  const [stats, setStats] = useState<Stats>(EMPTY_STATS);
  const [loadingStats, setLoadingStats] = useState(true);
  const [batchBusy, setBatchBusy] = useState(false);
  const [autoRunning, setAutoRunning] = useState(false);
  const [lastResult, setLastResult] = useState<BatchResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const stopRef = useRef(false);
  const supabaseRef = useRef(createClient());

  const count = useCallback(
    async (configure: (query: any) => any) => {
      const base = supabaseRef.current
        .from("products")
        .select("id", { count: "exact", head: true })
        .eq("store_id", storeId)
        .eq("is_available", true);
      const { count: value, error: countError } = await configure(base);
      if (countError) throw countError;
      return Number(value || 0);
    },
    [storeId],
  );

  const refreshStats = useCallback(async () => {
    setLoadingStats(true);
    try {
      const [
        active,
        withImage,
        unchecked,
        matched,
        needsReview,
        notFound,
        errors,
      ] = await Promise.all([
        count((query) => query),
        count((query) => query.not("image_url", "is", null)),
        count((query) =>
          query.is("image_url", null).is("image_enrichment_status", null),
        ),
        count((query) => query.eq("image_enrichment_status", "matched")),
        count((query) => query.eq("image_enrichment_status", "needs_review")),
        count((query) => query.eq("image_enrichment_status", "not_found")),
        count((query) => query.eq("image_enrichment_status", "error")),
      ]);
      setStats({
        active,
        withImage,
        unchecked,
        matched,
        needsReview,
        notFound,
        errors,
      });
      setError(null);
    } catch (caught) {
      const message =
        caught instanceof Error ? caught.message : "تعذر تحميل إحصائيات الصور.";
      setError(message);
    } finally {
      setLoadingStats(false);
    }
  }, [count]);

  useEffect(() => {
    void refreshStats();
  }, [refreshStats]);

  const processBatch = useCallback(async () => {
    setBatchBusy(true);
    setError(null);
    try {
      const { data, error: functionError } =
        await supabaseRef.current.functions.invoke("enrich-product-images", {
          body: {
            store_id: storeId,
            batch_size: 10,
          },
        });
      if (functionError) throw functionError;

      const result = (data || {}) as BatchResult;
      setLastResult(result);
      await refreshStats();
      return result;
    } catch (caught) {
      const message =
        caught instanceof Error ? caught.message : "تعذر تشغيل بحث الصور.";
      setError(message);
      throw caught;
    } finally {
      setBatchBusy(false);
    }
  }, [refreshStats, storeId]);

  async function startAuto() {
    if (autoRunning || batchBusy) return;
    stopRef.current = false;
    setAutoRunning(true);
    setError(null);

    try {
      while (!stopRef.current) {
        const result = await processBatch();
        if (!result.processed || result.remaining_unchecked === 0) break;
        await new Promise((resolve) => window.setTimeout(resolve, 1500));
      }
    } catch {
      // Error is already shown by processBatch.
    } finally {
      setAutoRunning(false);
      stopRef.current = false;
    }
  }

  function stopAuto() {
    stopRef.current = true;
    setAutoRunning(false);
  }

  const progress =
    stats.active > 0 ? Math.round((stats.withImage / stats.active) * 1000) / 10 : 0;

  return (
    <div className="mx-auto max-w-5xl space-y-5">
      <div>
        <h1 className="text-xl font-bold text-gray-950">صور المنتجات</h1>
        <p className="mt-1 text-sm text-gray-600">
          مطابقة آلية بالباركود أولاً، ثم حفظ نسخة من الصورة داخل Storage الخاص
          بالمتجر. المطابقة غير المؤكدة لا تُربط تلقائيًا.
        </p>
      </div>

      {error ? (
        <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="المنتجات الفعالة" value={loadingStats ? "…" : stats.active} />
        <Stat label="عندها صورة" value={loadingStats ? "…" : stats.withImage} />
        <Stat label="غير مفحوصة" value={loadingStats ? "…" : stats.unchecked} />
        <Stat label="التقدم" value={loadingStats ? "…" : `${progress}%`} />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="تطابق باركود مؤكد" value={stats.matched} />
        <Stat label="تحتاج مراجعة اسم" value={stats.needsReview} />
        <Stat label="لم توجد صورة بالمصدر" value={stats.notFound} />
        <Stat label="أخطاء مؤقتة" value={stats.errors} />
      </div>

      <section className="rounded-2xl border border-gray-200 bg-white p-5">
        <h2 className="font-semibold text-gray-950">تشغيل التعبئة</h2>
        <p className="mt-2 text-sm leading-6 text-gray-600">
          كل دفعة تفحص حتى 10 منتجات مع تأخير متعمد احترامًا لحدود API. يمكنك
          إيقاف التشغيل وإكماله لاحقًا؛ المنتجات التي فُحصت لا تبدأ من الصفر.
        </p>

        <div className="mt-4 flex flex-wrap gap-2">
          <button
            type="button"
            disabled={batchBusy || autoRunning}
            onClick={() => void processBatch()}
            className="rounded-xl bg-sky-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
          >
            {batchBusy && !autoRunning ? "جاري فحص الدفعة…" : "فحص دفعة واحدة"}
          </button>

          {!autoRunning ? (
            <button
              type="button"
              disabled={batchBusy || stats.unchecked === 0}
              onClick={() => void startAuto()}
              className="rounded-xl bg-emerald-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              بدء التشغيل التلقائي
            </button>
          ) : (
            <button
              type="button"
              onClick={stopAuto}
              className="rounded-xl bg-amber-600 px-4 py-2 text-sm font-semibold text-white"
            >
              إيقاف بعد الدفعة الحالية
            </button>
          )}

          <button
            type="button"
            disabled={loadingStats}
            onClick={() => void refreshStats()}
            className="rounded-xl border border-gray-300 bg-white px-4 py-2 text-sm font-semibold text-gray-700 disabled:opacity-50"
          >
            تحديث الإحصائيات
          </button>
        </div>

        {autoRunning ? (
          <p className="mt-3 text-sm font-medium text-emerald-700">
            التشغيل التلقائي يعمل الآن. اترك هذه الصفحة مفتوحة حتى توقفه أو
            تنتهي قائمة المطابقة المؤكدة.
          </p>
        ) : null}

        {lastResult ? (
          <div className="mt-4 rounded-xl bg-gray-50 p-3 text-sm text-gray-700">
            آخر دفعة: {lastResult.processed || 0} مفحوص —{" "}
            {lastResult.matched || 0} صورة مضافة —{" "}
            {lastResult.needs_review || 0} للمراجعة —{" "}
            {lastResult.not_found || 0} بدون صورة —{" "}
            {lastResult.errors || 0} أخطاء.
          </div>
        ) : null}
      </section>

      <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm leading-6 text-amber-900">
        المرحلة الأولى لا تستخدم بحث صور عام بالاسم، لأن ذلك قد يربط منتجًا
        مشابهًا بصورة منتج مختلف. الأصناف ذات الأكواد الداخلية أو التي لا تجد
        لها قاعدة المصدر صورة تنتقل إلى قائمة المراجعة للمرحلة الثانية.
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-2xl border border-gray-200 bg-white p-4">
      <p className="text-xs text-gray-500">{label}</p>
      <p className="mt-1 text-2xl font-bold text-gray-950">{value}</p>
    </div>
  );
}
