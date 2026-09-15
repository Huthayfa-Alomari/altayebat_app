"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Zone = {
  id: string | null;
  name: string;
  centerLat: string;
  centerLng: string;
  radiusKm: string;
  deliveryFee: string;
  minOrder: string;
  etaMin: string;
  etaMax: string;
  isActive: boolean;
};

const fallbackZone: Zone = {
  id: null,
  name: "نطاق التوصيل الأساسي",
  centerLat: "32.07375",
  centerLng: "36.09375",
  radiusKm: "15",
  deliveryFee: "1",
  minOrder: "5",
  etaMin: "35",
  etaMax: "75",
  isActive: true,
};

export default function DeliveryZonesPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState("");
  const [zone, setZone] = useState<Zone>(fallbackZone);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState("");

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

      const { data, error: zoneError } = await supabase
        .from("delivery_zones")
        .select("id,name,center_lat,center_lng,radius_km,delivery_fee,min_order,eta_min_minutes,eta_max_minutes,is_active")
        .eq("store_id", admin.store_id)
        .order("priority")
        .limit(1)
        .maybeSingle();
      if (zoneError) throw zoneError;

      if (data) {
        setZone({
          id: data.id,
          name: data.name ?? fallbackZone.name,
          centerLat: String(data.center_lat ?? fallbackZone.centerLat),
          centerLng: String(data.center_lng ?? fallbackZone.centerLng),
          radiusKm: String(data.radius_km ?? fallbackZone.radiusKm),
          deliveryFee: String(data.delivery_fee ?? fallbackZone.deliveryFee),
          minOrder: String(data.min_order ?? fallbackZone.minOrder),
          etaMin: String(data.eta_min_minutes ?? fallbackZone.etaMin),
          etaMax: String(data.eta_max_minutes ?? fallbackZone.etaMax),
          isActive: data.is_active ?? true,
        });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر تحميل نطاق التوصيل.");
    } finally {
      setLoading(false);
    }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!storeId || saving) return;

    const radius = Number(zone.radiusKm);
    const lat = Number(zone.centerLat);
    const lng = Number(zone.centerLng);
    const fee = Number(zone.deliveryFee);
    const minOrder = Number(zone.minOrder);
    if (!Number.isFinite(radius) || radius <= 0 || radius > 100) {
      setError("مسافة التوصيل يجب أن تكون بين 0 و100 كم.");
      return;
    }
    if (!Number.isFinite(lat) || lat < -90 || lat > 90 || !Number.isFinite(lng) || lng < -180 || lng > 180) {
      setError("إحداثيات مركز الفرع غير صالحة.");
      return;
    }

    setSaving(true);
    setError("");
    setSaved("");
    const payload = {
      store_id: storeId,
      name: zone.name.trim() || fallbackZone.name,
      city: "الزرقاء",
      areas: [],
      center_lat: lat,
      center_lng: lng,
      radius_km: radius,
      delivery_fee: Number.isFinite(fee) ? fee : 0,
      min_order: Number.isFinite(minOrder) ? minOrder : 0,
      eta_min_minutes: Number(zone.etaMin) || 35,
      eta_max_minutes: Number(zone.etaMax) || 75,
      priority: 10,
      is_active: zone.isActive,
    };

    try {
      if (zone.id) {
        const { error: updateError } = await supabase
          .from("delivery_zones")
          .update(payload)
          .eq("id", zone.id)
          .eq("store_id", storeId);
        if (updateError) throw updateError;
      } else {
        const { data, error: insertError } = await supabase
          .from("delivery_zones")
          .insert(payload)
          .select("id")
          .single();
        if (insertError) throw insertError;
        setZone((current) => ({ ...current, id: data.id }));
      }
      setSaved("تم حفظ نطاق التوصيل. التحقق يطبق من الخادم عند كل طلب.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "تعذر حفظ نطاق التوصيل.");
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <p className="p-6 text-sm text-gray-500">جاري تحميل نطاق التوصيل...</p>;

  const field = (
    label: string,
    value: string,
    onChange: (value: string) => void,
    suffix?: string,
  ) => (
    <label className="space-y-2">
      <span className="text-sm font-medium text-gray-700">{label}</span>
      <div className="flex items-center rounded-xl border border-gray-300 bg-white focus-within:border-red-500">
        <input
          dir="ltr"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          className="min-w-0 flex-1 rounded-xl px-3 py-2.5 text-left outline-none"
        />
        {suffix && <span className="px-3 text-sm text-gray-500">{suffix}</span>}
      </div>
    </label>
  );

  return (
    <div className="mx-auto max-w-4xl space-y-6" dir="rtl">
      <div>
        <h1 className="text-2xl font-bold">نطاق التوصيل</h1>
        <p className="mt-1 text-sm leading-6 text-gray-500">
          أي عنوان خارج المسافة المحددة يتم رفضه من التطبيق ومن قاعدة البيانات، وليس فقط من الواجهة.
        </p>
      </div>

      <form onSubmit={save} className="space-y-5 rounded-2xl border bg-white p-5 shadow-sm">
        <label className="block space-y-2">
          <span className="text-sm font-medium text-gray-700">اسم النطاق</span>
          <input
            value={zone.name}
            onChange={(event) => setZone({ ...zone, name: event.target.value })}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5 outline-none focus:border-red-500"
          />
        </label>

        <div className="grid gap-4 md:grid-cols-3">
          {field("أقصى مسافة توصيل", zone.radiusKm, (value) => setZone({ ...zone, radiusKm: value }), "كم")}
          {field("رسوم التوصيل", zone.deliveryFee, (value) => setZone({ ...zone, deliveryFee: value }), "د.أ")}
          {field("الحد الأدنى للطلب", zone.minOrder, (value) => setZone({ ...zone, minOrder: value }), "د.أ")}
        </div>

        <div className="grid gap-4 md:grid-cols-2">
          {field("Latitude مركز الفرع", zone.centerLat, (value) => setZone({ ...zone, centerLat: value }))}
          {field("Longitude مركز الفرع", zone.centerLng, (value) => setZone({ ...zone, centerLng: value }))}
        </div>

        <div className="grid gap-4 md:grid-cols-2">
          {field("أقل وقت توصيل", zone.etaMin, (value) => setZone({ ...zone, etaMin: value }), "دقيقة")}
          {field("أعلى وقت توصيل", zone.etaMax, (value) => setZone({ ...zone, etaMax: value }), "دقيقة")}
        </div>

        <label className="flex items-center gap-3 rounded-xl bg-gray-50 p-3 text-sm font-medium text-gray-700">
          <input
            type="checkbox"
            checked={zone.isActive}
            onChange={(event) => setZone({ ...zone, isActive: event.target.checked })}
            className="h-4 w-4"
          />
          تفعيل التوصيل داخل هذا النطاق
        </label>

        {!zone.isActive && (
          <div className="rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
            عند تعطيل النطاق سيتم إيقاف قبول عناوين التوصيل بدل فتح التوصيل لكل المناطق.
          </div>
        )}
        {error && <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div>}
        {saved && <div className="rounded-xl bg-green-50 p-3 text-sm text-green-700">{saved}</div>}

        <button
          type="submit"
          disabled={saving}
          className="w-full rounded-xl bg-red-600 px-4 py-3 font-semibold text-white disabled:opacity-50"
        >
          {saving ? "جاري الحفظ..." : "حفظ نطاق التوصيل"}
        </button>
      </form>
    </div>
  );
}
