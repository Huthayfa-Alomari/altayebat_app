"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Rider = {
  id: string;
  name: string;
  phone: string | null;
  is_active: boolean;
  approval_status: "pending" | "approved" | "rejected";
  availability_status: "offline" | "available" | "busy" | "break";
  effective_status: "offline" | "available" | "busy" | "break";
  registration_source: "admin" | "self";
  vehicle_type: string | null;
  vehicle_plate: string | null;
  last_seen_at: string | null;
  active_orders: number;
  connected_account: boolean;
  created_at: string | null;
};

type RiderPerformance = {
  driver_id: string;
  today_delivered: number;
  week_delivered: number;
  active_orders: number;
  avg_delivery_minutes_today: number | null;
  cash_collected_today: number;
};

function statusLabel(value: Rider["effective_status"]) {
  if (value === "available") return "متاح";
  if (value === "busy") return "في توصيل";
  if (value === "break") return "استراحة";
  return "غير متصل";
}

function statusClass(value: Rider["effective_status"]) {
  if (value === "available") return "border-emerald-200 bg-emerald-50 text-emerald-700";
  if (value === "busy") return "border-sky-200 bg-sky-50 text-sky-700";
  if (value === "break") return "border-amber-200 bg-amber-50 text-amber-700";
  return "border-gray-200 bg-gray-100 text-gray-600";
}

function lastSeen(value: string | null) {
  if (!value) return "لم يتصل بعد";
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return `قبل ${seconds} ثانية`;
  if (seconds < 3600) return `قبل ${Math.floor(seconds / 60)} دقيقة`;
  return `قبل ${Math.floor(seconds / 3600)} ساعة`;
}

function money(value: number) {
  return `${Number.isFinite(value) ? value.toFixed(2) : "0.00"} د.أ`;
}

export default function RidersPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [riders, setRiders] = useState<Rider[]>([]);
  const [performance, setPerformance] = useState<Record<string, RiderPerformance>>({});
  const [registrationLink, setRegistrationLink] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const { data: authData } = await supabase.auth.getUser();
      if (!authData.user) throw new Error("يجب تسجيل الدخول أولًا");
      const { data: admin, error: adminError } = await supabase
        .from("store_admins")
        .select("store_id")
        .eq("user_id", authData.user.id)
        .maybeSingle();
      if (adminError) throw adminError;
      const currentStore = admin?.store_id?.toString();
      if (!currentStore) throw new Error("لم يتم العثور على متجر مرتبط بالحساب");
      setStoreId(currentStore);
      if (typeof window !== "undefined") {
        setRegistrationLink(`${window.location.origin}/rider?store=${encodeURIComponent(currentStore)}`);
      }

      const [riderResult, performanceResult] = await Promise.all([
        supabase.rpc("admin_list_riders", { p_store_id: currentStore }),
        supabase.rpc("admin_rider_performance", { p_store_id: currentStore }),
      ]);

      if (riderResult.error) throw riderResult.error;
      const normalized = ((riderResult.data ?? []) as Array<Record<string, unknown>>).map((row) => ({
        id: String(row.id ?? ""),
        name: String(row.name ?? ""),
        phone: row.phone ? String(row.phone) : null,
        is_active: Boolean(row.is_active),
        approval_status: String(row.approval_status ?? "approved") as Rider["approval_status"],
        availability_status: String(row.availability_status ?? "offline") as Rider["availability_status"],
        effective_status: String(row.effective_status ?? "offline") as Rider["effective_status"],
        registration_source: String(row.registration_source ?? "admin") as Rider["registration_source"],
        vehicle_type: row.vehicle_type ? String(row.vehicle_type) : null,
        vehicle_plate: row.vehicle_plate ? String(row.vehicle_plate) : null,
        last_seen_at: row.last_seen_at ? String(row.last_seen_at) : null,
        active_orders: Number(row.active_orders ?? 0),
        connected_account: Boolean(row.connected_account),
        created_at: row.created_at ? String(row.created_at) : null,
      }));
      setRiders(normalized);

      if (!performanceResult.error) {
        const nextPerformance: Record<string, RiderPerformance> = {};
        for (const row of (performanceResult.data ?? []) as Array<Record<string, unknown>>) {
          const driverId = String(row.driver_id ?? "");
          if (!driverId) continue;
          nextPerformance[driverId] = {
            driver_id: driverId,
            today_delivered: Number(row.today_delivered ?? 0),
            week_delivered: Number(row.week_delivered ?? 0),
            active_orders: Number(row.active_orders ?? 0),
            avg_delivery_minutes_today:
              row.avg_delivery_minutes_today === null || row.avg_delivery_minutes_today === undefined
                ? null
                : Number(row.avg_delivery_minutes_today),
            cash_collected_today: Number(row.cash_collected_today ?? 0),
          };
        }
        setPerformance(nextPerformance);
      }
      setError(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر تحميل المندوبين");
    } finally {
      if (!silent) setLoading(false);
    }
  }, [supabase]);

  useEffect(() => {
    void load();
    const timer = window.setInterval(() => void load(true), 10000);
    return () => window.clearInterval(timer);
  }, [load]);

  async function review(id: string, decision: "approved" | "rejected") {
    setBusy(id);
    setError(null);
    setMessage(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_review_rider", {
        p_driver_id: id,
        p_decision: decision,
      });
      if (rpcError) throw rpcError;
      setMessage(decision === "approved" ? "تم اعتماد المندوب" : "تم رفض طلب المندوب");
      await load(true);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر تحديث المندوب");
    } finally {
      setBusy(null);
    }
  }

  async function toggleActive(rider: Rider) {
    setBusy(rider.id);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_set_delivery_driver_active", {
        p_driver_id: rider.id,
        p_active: !rider.is_active,
      });
      if (rpcError) throw rpcError;
      await load(true);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر تحديث حالة الحساب");
    } finally {
      setBusy(null);
    }
  }

  async function copyRegistrationLink() {
    if (!registrationLink) return;
    await navigator.clipboard.writeText(registrationLink);
    setMessage("تم نسخ رابط تسجيل المندوبين");
  }

  const pending = riders.filter((r) => r.approval_status === "pending").length;
  const available = riders.filter((r) => r.approval_status === "approved" && r.effective_status === "available").length;
  const busyCount = riders.filter((r) => r.effective_status === "busy").length;
  const offline = riders.filter((r) => r.approval_status === "approved" && r.effective_status === "offline").length;
  const totalDeliveredToday = Object.values(performance).reduce((sum, row) => sum + row.today_delivered, 0);
  const totalDeliveredWeek = Object.values(performance).reduce((sum, row) => sum + row.week_delivered, 0);
  const totalCashToday = Object.values(performance).reduce((sum, row) => sum + row.cash_collected_today, 0);

  if (loading) return <div className="p-6 text-sm text-gray-500">جاري تحميل المندوبين...</div>;

  return (
    <div className="mx-auto max-w-6xl space-y-5" dir="rtl">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-black text-gray-950">مندوبو التوصيل</h1>
          <p className="mt-1 text-sm text-gray-500">الحضور المباشر، اعتماد الحسابات، وأداء التوصيل من مكان واحد.</p>
        </div>
        <Link href="/dashboard/delivery" className="rounded-xl bg-gray-950 px-4 py-2.5 text-center text-sm font-bold text-white">إدارة طلبات التوصيل</Link>
      </div>

      {error && <div className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
      {message && <div className="rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-700">{message}</div>}

      <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          ["تم توصيله اليوم", totalDeliveredToday, "text-emerald-700"],
          ["هذا الأسبوع", totalDeliveredWeek, "text-sky-700"],
          ["تحصيل كاش اليوم", money(totalCashToday), "text-amber-700"],
          ["متاح الآن", available, "text-emerald-700"],
        ].map(([label, value, color]) => (
          <div key={String(label)} className="rounded-2xl border bg-white p-4 shadow-sm">
            <div className="text-xs font-bold text-gray-400">{label}</div>
            <div className={`mt-1 text-2xl font-black ${color}`}>{value}</div>
          </div>
        ))}
      </section>

      <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[
          ["متاح", available, "text-emerald-700"],
          ["في توصيل", busyCount, "text-sky-700"],
          ["غير متصل", offline, "text-gray-700"],
          ["بانتظار الموافقة", pending, "text-amber-700"],
        ].map(([label, value, color]) => (
          <div key={String(label)} className="rounded-2xl border bg-white p-3 shadow-sm">
            <div className="text-xs font-bold text-gray-400">{label}</div>
            <div className={`mt-1 text-2xl font-black ${color}`}>{value}</div>
          </div>
        ))}
      </section>

      <section className="rounded-2xl border border-sky-100 bg-sky-50 p-4">
        <div className="font-black text-sky-950">رابط تسجيل المندوبين</div>
        <p className="mt-1 text-xs leading-5 text-sky-800">أرسل هذا الرابط لأي مندوب جديد. يسجل برقم الهاتف وOTP، وبعدها يظهر هنا بانتظار موافقتك.</p>
        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
          <div className="min-w-0 flex-1 break-all rounded-xl bg-white px-3 py-2.5 text-xs text-gray-600">{registrationLink || "جاري تجهيز الرابط..."}</div>
          <button onClick={() => void copyRegistrationLink()} disabled={!registrationLink} className="rounded-xl bg-sky-600 px-4 py-2.5 text-sm font-black text-white disabled:opacity-50">نسخ الرابط</button>
        </div>
      </section>

      <section className="space-y-3">
        {riders.length === 0 ? (
          <div className="rounded-2xl border border-dashed bg-white p-10 text-center text-sm text-gray-500">لا يوجد مندوبون بعد. أرسل رابط التسجيل لأول مندوب.</div>
        ) : riders.map((rider) => {
          const metrics = performance[rider.id];
          return (
            <article key={rider.id} className="rounded-2xl border bg-white p-4 shadow-sm sm:p-5">
              <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="font-black text-gray-950">{rider.name}</h2>
                    {rider.approval_status === "pending" ? (
                      <span className="rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-black text-amber-700">بانتظار الموافقة</span>
                    ) : rider.approval_status === "rejected" ? (
                      <span className="rounded-full border border-red-200 bg-red-50 px-2.5 py-1 text-xs font-black text-red-700">مرفوض</span>
                    ) : (
                      <span className={`rounded-full border px-2.5 py-1 text-xs font-black ${statusClass(rider.effective_status)}`}>{statusLabel(rider.effective_status)}</span>
                    )}
                    {!rider.connected_account && <span className="rounded-full bg-gray-100 px-2.5 py-1 text-[11px] font-bold text-gray-500">حساب يدوي</span>}
                  </div>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500">
                    {rider.phone && <span dir="ltr">{rider.phone}</span>}
                    {rider.vehicle_type && <span>{rider.vehicle_type}{rider.vehicle_plate ? ` • ${rider.vehicle_plate}` : ""}</span>}
                    {rider.connected_account && <span>آخر ظهور: {lastSeen(rider.last_seen_at)}</span>}
                    {rider.active_orders > 0 && <span className="font-bold text-sky-700">{rider.active_orders} طلب نشط</span>}
                  </div>

                  {metrics && rider.approval_status === "approved" && (
                    <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
                      <div className="rounded-xl bg-emerald-50 px-3 py-2">
                        <div className="text-[10px] font-bold text-emerald-600">توصيلات اليوم</div>
                        <div className="mt-0.5 font-black text-emerald-900">{metrics.today_delivered}</div>
                      </div>
                      <div className="rounded-xl bg-sky-50 px-3 py-2">
                        <div className="text-[10px] font-bold text-sky-600">هذا الأسبوع</div>
                        <div className="mt-0.5 font-black text-sky-900">{metrics.week_delivered}</div>
                      </div>
                      <div className="rounded-xl bg-violet-50 px-3 py-2">
                        <div className="text-[10px] font-bold text-violet-600">متوسط اليوم</div>
                        <div className="mt-0.5 font-black text-violet-900">{metrics.avg_delivery_minutes_today === null ? "—" : `${metrics.avg_delivery_minutes_today.toFixed(1)} د`}</div>
                      </div>
                      <div className="rounded-xl bg-amber-50 px-3 py-2">
                        <div className="text-[10px] font-bold text-amber-600">كاش اليوم</div>
                        <div className="mt-0.5 font-black text-amber-900">{money(metrics.cash_collected_today)}</div>
                      </div>
                    </div>
                  )}
                </div>

                <div className="flex flex-wrap gap-2">
                  {rider.approval_status === "pending" && (
                    <>
                      <button disabled={busy === rider.id} onClick={() => void review(rider.id, "approved")} className="rounded-xl bg-emerald-600 px-4 py-2 text-xs font-black text-white disabled:opacity-50">اعتماد</button>
                      <button disabled={busy === rider.id} onClick={() => void review(rider.id, "rejected")} className="rounded-xl border border-red-200 px-4 py-2 text-xs font-black text-red-700 disabled:opacity-50">رفض</button>
                    </>
                  )}
                  {rider.approval_status === "approved" && (
                    <button disabled={busy === rider.id} onClick={() => void toggleActive(rider)} className={`rounded-xl border px-4 py-2 text-xs font-black disabled:opacity-50 ${rider.is_active ? "border-gray-200 text-gray-600" : "border-emerald-200 text-emerald-700"}`}>
                      {rider.is_active ? "إيقاف الحساب" : "تفعيل الحساب"}
                    </button>
                  )}
                </div>
              </div>
            </article>
          );
        })}
      </section>

      {storeId && <div className="text-[10px] text-gray-300">Store: {storeId}</div>}
    </div>
  );
}
