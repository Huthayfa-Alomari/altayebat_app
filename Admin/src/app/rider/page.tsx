"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Rider = {
  id: string;
  store_id: string;
  name: string;
  phone: string | null;
  approval_status: "pending" | "approved" | "rejected";
  is_active: boolean;
  availability_status: "offline" | "available" | "busy" | "break";
  effective_status: "offline" | "available" | "busy" | "break";
  vehicle_type: string | null;
  vehicle_plate: string | null;
  active_orders: number;
};

const STORE_KEY = "altayebat_rider_store_id";

function normalizeJordanPhone(input: string) {
  const digits = input.replace(/\D/g, "");
  if (/^9627\d{8}$/.test(digits)) return `+${digits}`;
  if (/^07\d{8}$/.test(digits)) return `+962${digits.slice(1)}`;
  if (/^7\d{8}$/.test(digits)) return `+962${digits}`;
  return null;
}

function statusLabel(value: Rider["effective_status"]) {
  if (value === "available") return "متاح";
  if (value === "busy") return "في توصيل";
  if (value === "break") return "استراحة";
  return "غير متاح";
}

function statusStyle(value: Rider["effective_status"]) {
  if (value === "available") return "border-emerald-200 bg-emerald-50 text-emerald-700";
  if (value === "busy") return "border-sky-200 bg-sky-50 text-sky-700";
  if (value === "break") return "border-amber-200 bg-amber-50 text-amber-700";
  return "border-gray-200 bg-gray-100 text-gray-600";
}

export default function RiderPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [rider, setRider] = useState<Rider | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [otpSent, setOtpSent] = useState(false);
  const [otpPhone, setOtpPhone] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [vehicleType, setVehicleType] = useState("");
  const [vehiclePlate, setVehiclePlate] = useState("");
  const [otp, setOtp] = useState("");

  const loadRider = useCallback(async () => {
    const { data, error: rpcError } = await supabase.rpc("rider_me");
    if (rpcError) {
      if (rpcError.message.includes("AUTH_REQUIRED")) {
        setRider(null);
        return;
      }
      throw rpcError;
    }
    if (!data || typeof data !== "object") {
      setRider(null);
      return;
    }
    const raw = data as Record<string, unknown>;
    const next: Rider = {
      id: String(raw.id ?? ""),
      store_id: String(raw.store_id ?? ""),
      name: String(raw.name ?? ""),
      phone: raw.phone ? String(raw.phone) : null,
      approval_status: String(raw.approval_status ?? "pending") as Rider["approval_status"],
      is_active: Boolean(raw.is_active),
      availability_status: String(raw.availability_status ?? "offline") as Rider["availability_status"],
      effective_status: String(raw.effective_status ?? "offline") as Rider["effective_status"],
      vehicle_type: raw.vehicle_type ? String(raw.vehicle_type) : null,
      vehicle_plate: raw.vehicle_plate ? String(raw.vehicle_plate) : null,
      active_orders: Number(raw.active_orders ?? 0),
    };
    setRider(next);
    setStoreId(next.store_id);
    window.localStorage.setItem(STORE_KEY, next.store_id);
  }, [supabase]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const resolved = params.get("store")?.trim() || window.localStorage.getItem(STORE_KEY)?.trim() || null;
    if (resolved) {
      setStoreId(resolved);
      window.localStorage.setItem(STORE_KEY, resolved);
    }
    void supabase.auth.getUser()
      .then(({ data }) => data.user ? loadRider() : undefined)
      .catch(() => undefined)
      .finally(() => setLoading(false));
  }, [loadRider, supabase]);

  useEffect(() => {
    if (!rider || rider.approval_status !== "approved" || !rider.is_active) return;
    const ping = async () => {
      try {
        await supabase.rpc("rider_heartbeat");
        await loadRider();
      } catch {
        // A later heartbeat will recover presence.
      }
    };
    const timer = window.setInterval(() => void ping(), 30000);
    const onVisible = () => document.visibilityState === "visible" && void ping();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [loadRider, rider?.approval_status, rider?.id, rider?.is_active, supabase]);

  async function sendOtp() {
    setError(null);
    setMessage(null);
    if (!storeId) return setError("اطلب رابط تسجيل المندوبين من المول.");
    if (name.trim().length < 2) return setError("اكتب اسم المندوب.");
    const normalized = normalizeJordanPhone(phone);
    if (!normalized) return setError("اكتب رقم أردني صحيح مثل 0791234567.");
    setBusy(true);
    try {
      const { error: authError } = await supabase.auth.signInWithOtp({
        phone: normalized,
        options: { shouldCreateUser: true },
      });
      if (authError) throw authError;
      setOtpPhone(normalized);
      setOtpSent(true);
      setMessage("تم إرسال رمز التحقق.");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر إرسال الرمز");
    } finally {
      setBusy(false);
    }
  }

  async function verifyOtp() {
    if (!otpPhone || !storeId) return;
    if (!/^\d{6}$/.test(otp)) return setError("أدخل رمز التحقق المكوّن من 6 أرقام.");
    setBusy(true);
    setError(null);
    try {
      const { error: verifyError } = await supabase.auth.verifyOtp({ phone: otpPhone, token: otp, type: "sms" });
      if (verifyError) throw verifyError;
      const { error: registerError } = await supabase.rpc("rider_register", {
        p_store_id: storeId,
        p_name: name.trim(),
        p_vehicle_type: vehicleType.trim() || null,
        p_vehicle_plate: vehiclePlate.trim() || null,
      });
      if (registerError) throw registerError;
      await loadRider();
      setOtpSent(false);
      setOtp("");
      setMessage("تم تسجيل حساب المندوب.");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر إكمال التسجيل");
    } finally {
      setBusy(false);
    }
  }

  async function setAvailability(status: "available" | "break" | "offline") {
    setBusy(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc("rider_set_availability", { p_status: status });
      if (rpcError) throw rpcError;
      await loadRider();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر تحديث الحالة");
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return <main className="flex min-h-screen items-center justify-center bg-slate-50" dir="rtl"><span className="text-sm text-gray-500">جاري التحميل...</span></main>;
  }

  return (
    <main className="min-h-screen bg-slate-50 px-4 py-8" dir="rtl">
      <div className="mx-auto max-w-lg space-y-4">
        <header className="rounded-3xl bg-gradient-to-l from-sky-500 via-sky-400 to-cyan-300 p-5 text-white shadow-lg shadow-sky-100">
          <div className="text-xs font-bold text-white/80">أسواق الطيبات</div>
          <h1 className="mt-1 text-2xl font-black">بوابة مندوب التوصيل</h1>
          <p className="mt-2 text-sm leading-6 text-white/90">سجّل برقم هاتفك وحدّث حالتك حتى يعرف المول من المتاح فورًا.</p>
        </header>

        {error && <div className="rounded-2xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
        {message && <div className="rounded-2xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{message}</div>}

        {!rider ? (
          <section className="rounded-3xl border bg-white p-5 shadow-sm">
            <h2 className="text-lg font-black text-gray-950">تسجيل المندوب</h2>
            {!storeId && <div className="mt-3 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">الرابط غير مربوط بالمول. اطلب رابط التسجيل من الإدارة.</div>}
            {!otpSent ? (
              <div className="mt-4 space-y-3">
                <input value={name} onChange={(e) => setName(e.target.value)} className="w-full rounded-xl border px-3 py-3 text-sm outline-none focus:border-sky-400" placeholder="الاسم الكامل" />
                <input value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" dir="ltr" className="w-full rounded-xl border px-3 py-3 text-left text-sm outline-none focus:border-sky-400" placeholder="0791234567" />
                <div className="grid grid-cols-2 gap-2">
                  <input value={vehicleType} onChange={(e) => setVehicleType(e.target.value)} className="rounded-xl border px-3 py-3 text-sm outline-none focus:border-sky-400" placeholder="سيارة / سكوتر" />
                  <input value={vehiclePlate} onChange={(e) => setVehiclePlate(e.target.value)} className="rounded-xl border px-3 py-3 text-sm outline-none focus:border-sky-400" placeholder="رقم اللوحة" />
                </div>
                <button onClick={() => void sendOtp()} disabled={busy || !storeId} className="w-full rounded-xl bg-sky-500 px-4 py-3 text-sm font-black text-white disabled:opacity-50">{busy ? "جاري الإرسال..." : "إرسال رمز التحقق"}</button>
              </div>
            ) : (
              <div className="mt-4 space-y-3">
                <div className="rounded-xl bg-sky-50 p-3 text-sm text-sky-800">أدخل الرمز المرسل إلى <b dir="ltr">{otpPhone}</b></div>
                <input value={otp} onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))} inputMode="numeric" autoComplete="one-time-code" dir="ltr" className="w-full rounded-xl border px-3 py-4 text-center text-2xl font-black tracking-[0.3em]" placeholder="000000" />
                <button onClick={() => void verifyOtp()} disabled={busy} className="w-full rounded-xl bg-gray-950 px-4 py-3 text-sm font-black text-white disabled:opacity-50">{busy ? "جاري التحقق..." : "تأكيد التسجيل"}</button>
                <button onClick={() => { setOtpSent(false); setOtp(""); }} className="w-full rounded-xl border px-4 py-2.5 text-sm font-bold text-gray-600">تغيير الرقم</button>
              </div>
            )}
          </section>
        ) : rider.approval_status === "pending" ? (
          <section className="rounded-3xl border bg-white p-6 text-center shadow-sm">
            <div className="text-4xl">⏳</div>
            <h2 className="mt-3 text-xl font-black">بانتظار موافقة المول</h2>
            <p className="mt-2 text-sm leading-6 text-gray-500">تم تسجيلك باسم {rider.name}. بعد الاعتماد ستظهر لك حالة متاح / استراحة / غير متاح.</p>
            <button onClick={() => void loadRider()} className="mt-4 rounded-xl bg-gray-950 px-5 py-2.5 text-sm font-bold text-white">تحديث</button>
          </section>
        ) : rider.approval_status === "rejected" ? (
          <section className="rounded-3xl border bg-white p-6 text-center shadow-sm"><h2 className="text-xl font-black">الحساب غير معتمد</h2><p className="mt-2 text-sm text-gray-500">تواصل مع إدارة المول لمراجعة الحساب.</p></section>
        ) : (
          <section className="rounded-3xl border bg-white p-5 shadow-sm">
            <div className="flex items-start justify-between gap-3">
              <div><div className="text-xs text-gray-400">مرحبًا</div><h2 className="text-xl font-black">{rider.name}</h2><p className="mt-1 text-xs text-gray-500">{rider.phone}{rider.vehicle_type ? ` • ${rider.vehicle_type}` : ""}</p></div>
              <span className={`rounded-full border px-3 py-1.5 text-xs font-black ${statusStyle(rider.effective_status)}`}>{statusLabel(rider.effective_status)}</span>
            </div>
            {rider.effective_status === "busy" ? (
              <div className="mt-5 rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm text-sky-800">لديك {rider.active_orders} طلب توصيل نشط. حالتك تتحول تلقائيًا إلى <b>في توصيل</b>.</div>
            ) : (
              <div className="mt-5 grid grid-cols-3 gap-2">
                <button disabled={busy} onClick={() => void setAvailability("available")} className="rounded-2xl border border-emerald-200 bg-emerald-50 p-3 text-sm font-black text-emerald-700">🟢<br />متاح</button>
                <button disabled={busy} onClick={() => void setAvailability("break")} className="rounded-2xl border border-amber-200 bg-amber-50 p-3 text-sm font-black text-amber-700">🟡<br />استراحة</button>
                <button disabled={busy} onClick={() => void setAvailability("offline")} className="rounded-2xl border border-gray-200 bg-gray-100 p-3 text-sm font-black text-gray-700">⚫<br />غير متاح</button>
              </div>
            )}
            <p className="mt-4 text-center text-[11px] leading-5 text-gray-400">يتم إرسال نبضة حضور كل 30 ثانية. إذا أغلق المندوب الصفحة أو انقطع الإنترنت يظهر للمول غير متصل تلقائيًا.</p>
            <button onClick={() => void supabase.auth.signOut().then(() => setRider(null))} className="mt-3 w-full rounded-xl border px-4 py-2.5 text-sm font-bold text-gray-600">تسجيل الخروج</button>
          </section>
        )}
      </div>
    </main>
  );
}
