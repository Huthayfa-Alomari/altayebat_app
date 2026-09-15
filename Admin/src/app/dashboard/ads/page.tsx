"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type AdRow = {
  id: string;
  title: string;
  subtitle: string | null;
  image_url: string | null;
  target_value: string | null;
  is_active: boolean;
  sort_order: number;
};

type AdMetric = {
  banner_id: string;
  title: string;
  impressions: number;
  clicks: number;
  ctr_percent: number;
};

export default function AdsPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState("");
  const [ads, setAds] = useState<AdRow[]>([]);
  const [metrics, setMetrics] = useState<Record<string, AdMetric>>({});
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [link, setLink] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function load() {
    setLoading(true);
    try {
      const { data: auth } = await supabase.auth.getUser();
      if (!auth.user) {
        router.replace("/login");
        return;
      }
      const { data: admin, error: adminError } = await supabase
        .from("store_admins")
        .select("store_id")
        .eq("user_id", auth.user.id)
        .limit(1)
        .maybeSingle();
      if (adminError) throw adminError;
      if (!admin?.store_id) throw new Error("هذا الحساب غير مربوط بأي مول.");
      setStoreId(admin.store_id);
      await refresh(admin.store_id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر تحميل الإعلانات.");
    } finally {
      setLoading(false);
    }
  }

  async function refresh(id: string) {
    const [{ data, error: queryError }, { data: metricRows, error: metricError }] = await Promise.all([
      supabase
        .from("storefront_banners")
        .select("id,title,subtitle,image_url,target_value,is_active,sort_order")
        .eq("store_id", id)
        .eq("position", "sponsor")
        .order("sort_order"),
      supabase.rpc("admin_ad_performance", { p_store_id: id, p_days: 30 }),
    ]);
    if (queryError) throw queryError;
    if (metricError) throw metricError;
    setAds((data ?? []) as AdRow[]);
    const next: Record<string, AdMetric> = {};
    for (const row of (metricRows ?? []) as AdMetric[]) next[row.banner_id] = row;
    setMetrics(next);
  }

  async function addAd(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!storeId || saving || !title.trim()) return;
    setSaving(true);
    setError("");
    try {
      const nextOrder = ads.length ? Math.max(...ads.map((ad) => ad.sort_order)) + 10 : 10;
      const target = link.trim();
      const { error: insertError } = await supabase.from("storefront_banners").insert({
        store_id: storeId,
        title: title.trim(),
        subtitle: subtitle.trim() || null,
        image_url: imageUrl.trim() || null,
        position: "sponsor",
        target_type: target ? "url" : "none",
        target_value: target || null,
        sort_order: nextOrder,
        is_active: true,
      });
      if (insertError) throw insertError;
      setTitle("");
      setSubtitle("");
      setImageUrl("");
      setLink("");
      await refresh(storeId);
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر حفظ الإعلان.");
    } finally {
      setSaving(false);
    }
  }

  async function toggle(ad: AdRow) {
    if (!storeId) return;
    const { error: updateError } = await supabase
      .from("storefront_banners")
      .update({ is_active: !ad.is_active })
      .eq("id", ad.id)
      .eq("store_id", storeId);
    if (updateError) {
      setError(updateError.message);
      return;
    }
    setAds((current) =>
      current.map((item) =>
        item.id === ad.id ? { ...item, is_active: !item.is_active } : item,
      ),
    );
  }

  if (loading) return <p className="p-6 text-sm text-gray-500">جاري التحميل...</p>;

  return (
    <div className="mx-auto max-w-4xl space-y-6" dir="rtl">
      <div>
        <h1 className="text-2xl font-bold">إعلانات الشركات</h1>
        <p className="mt-1 text-sm text-gray-500">
          الإعلانات المفعلة تظهر في تطبيق الزبون مع وسم «إعلان ممول». الإحصائيات أدناه لآخر 30 يومًا.
        </p>
      </div>

      <form onSubmit={addAd} className="grid gap-3 rounded-2xl border bg-white p-5 md:grid-cols-2">
        <input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder="عنوان الإعلان"
          className="rounded-xl border px-3 py-2.5"
          required
        />
        <input
          value={subtitle}
          onChange={(event) => setSubtitle(event.target.value)}
          placeholder="نص مختصر"
          className="rounded-xl border px-3 py-2.5"
        />
        <input
          dir="ltr"
          value={imageUrl}
          onChange={(event) => setImageUrl(event.target.value)}
          placeholder="رابط صورة الإعلان"
          className="rounded-xl border px-3 py-2.5 text-left"
        />
        <input
          dir="ltr"
          value={link}
          onChange={(event) => setLink(event.target.value)}
          placeholder="رابط الشركة عند الضغط"
          className="rounded-xl border px-3 py-2.5 text-left"
        />
        <button
          type="submit"
          disabled={saving}
          className="rounded-xl bg-red-600 px-4 py-3 font-semibold text-white disabled:opacity-50 md:col-span-2"
        >
          {saving ? "جاري الحفظ..." : "إضافة إعلان"}
        </button>
      </form>

      {error && <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div>}

      <div className="space-y-3">
        {ads.length === 0 ? (
          <div className="rounded-2xl border border-dashed bg-white p-6 text-center text-sm text-gray-500">
            لا يوجد إعلان حاليًا، لذلك القسم مخفي تلقائيًا داخل التطبيق.
          </div>
        ) : (
          ads.map((ad) => {
            const metric = metrics[ad.id];
            return (
              <div key={ad.id} className="rounded-2xl border bg-white p-4">
                <div className="flex items-center justify-between gap-4">
                  <div className="min-w-0">
                    <div className="font-semibold">{ad.title}</div>
                    {ad.subtitle && <div className="mt-1 text-sm text-gray-500">{ad.subtitle}</div>}
                  </div>
                  <button
                    type="button"
                    onClick={() => void toggle(ad)}
                    className={`rounded-lg px-4 py-2 text-sm font-semibold ${ad.is_active ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-600"}`}
                  >
                    {ad.is_active ? "ظاهر — إخفاء" : "مخفي — إظهار"}
                  </button>
                </div>
                <div className="mt-4 grid grid-cols-3 gap-2 text-center">
                  <div className="rounded-xl bg-gray-50 p-3">
                    <div className="text-lg font-bold">{metric?.impressions ?? 0}</div>
                    <div className="text-xs text-gray-500">ظهور</div>
                  </div>
                  <div className="rounded-xl bg-gray-50 p-3">
                    <div className="text-lg font-bold">{metric?.clicks ?? 0}</div>
                    <div className="text-xs text-gray-500">ضغطات</div>
                  </div>
                  <div className="rounded-xl bg-gray-50 p-3">
                    <div className="text-lg font-bold">{Number(metric?.ctr_percent ?? 0).toFixed(2)}%</div>
                    <div className="text-xs text-gray-500">CTR</div>
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
