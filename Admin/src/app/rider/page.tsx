"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type RiderStatus = "offline" | "available" | "busy" | "break";
type Rider = {
  id: string;
  store_id: string;
  name: string;
  phone: string | null;
  approval_status: "pending" | "approved" | "rejected";
  is_active: boolean;
  availability_status: RiderStatus;
  effective_status: RiderStatus;
  vehicle_type: string | null;
  vehicle_plate: string | null;
  active_orders: number;
};

type DeliveryTask = {
  id: string;
  status: "preparing" | "out_for_delivery" | string;
  total: number;
  payment_method: string;
  payment_status: string;
  address_snapshot: Record<string, unknown>;
  customer_name: string | null;
  customer_phone: string | null;
  created_at: string | null;
  rider_picked_up_at: string | null;
  rider_started_delivery_at: string | null;
  rider_delivered_at: string | null;
  cash_due: number;
};

const STORE_KEY = "altayebat_rider_store_id";

function normalizeJordanPhone(input: string) {
  const digits = input.replace(/\D/g, "");
  if (/^9627\d{8}$/.test(digits)) return `+${digits}`;
  if (/^07\d{8}$/.test(digits)) return `+962${digits.slice(1)}`;
  if (/^7\d{8}$/.test(digits)) return `+962${digits}`;
  return null;
}

function statusLabel(value: RiderStatus) {
  if (value === "available") return "متاح";
  if (value === "busy") return "في توصيل";
  if (value === "break") return "استراحة";
  return "غير متاح";
}

function statusStyle(value: RiderStatus) {
  if (value === "available") return "border-emerald-200 bg-emerald-50 text-emerald-700";
  if (value === "busy") return "border-sky-200 bg-sky-50 text-sky-700";
  if (value === "break") return "border-amber-200 bg-amber-50 text-amber-700";
  return "border-gray-200 bg-gray-100 text-gray-600";
}

function money(value: number) {
  return `${Number.isFinite(value) ? value.toFixed(2) : "0.00"} د.أ`;
}

function shortId(id: string) {
  return id.replaceAll("-", "").slice(0, 8).toUpperCase();
}

function addressText(snapshot: Record<string, unknown>) {
  const direct = snapshot.address_text?.toString().trim();
  if (direct) return direct;
  const parts = [
    snapshot.city,
    snapshot.area,
    snapshot.street,
    snapshot.building ? `بناية ${snapshot.building}` : null,
    snapshot.floor ? `طابق ${snapshot.floor}` : null,
  ]
    .map((value) => value?.toString().trim())
    .filter(Boolean);
  return parts.length > 0 ? parts.join("، ") : "العنوان غير مكتمل";
}

function addressNotes(snapshot: Record<string, unknown>) {
  return snapshot.notes?.toString().trim() || null;
}

function directionsUrl(snapshot: Record<string, unknown>) {
  const lat = Number(snapshot.lat ?? snapshot.latitude);
  const lng = Number(snapshot.lng ?? snapshot.longitude);
  if (Number.isFinite(lat) && Number.isFinite(lng) && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
    return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
  }
  const text = addressText(snapshot);
  return text === "العنوان غير مكتمل"
    ? null
    : `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(text)}`;
}

function taskStatusText(task: DeliveryTask) {
  if (task.status === "out_for_delivery") return "بالتوصيل الآن";
  if (task.rider_picked_up_at) return "تم الاستلام — جاهز للانطلاق";
  return "جاهز للاستلام من المول";
}

export default function RiderPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [rider, setRider] = useState<Rider | null>(null);
  const [tasks, setTasks] = useState<DeliveryTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [tasksLoading, setTasksLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionBusy, setActionBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [otpSent, setOtpSent] = useState(false);
  const [otpPhone, setOtpPhone] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [vehicleType, setVehicleType] = useState("");
  const [vehiclePlate, setVehiclePlate] = useState("");
  const [otp, setOtp] = useState("");
  const [notificationsEnabled, setNotificationsEnabled] = useState(false);
  const [gpsOrderId, setGpsOrderId] = useState<string | null>(null);
  const [gpsText, setGpsText] = useState("GPS غير مشغّل");

  const knownTaskIdsRef = useRef<Set<string>>(new Set());
  const tasksInitializedRef = useRef(false);
  const watchIdRef = useRef<number | null>(null);
  const lastGpsSendRef = useRef(0);

  const loadRider = useCallback(async () => {
    const { data, error: rpcError } = await supabase.rpc("rider_me");
    if (rpcError) {
      if (rpcError.message.includes("AUTH_REQUIRED")) {
        setRider(null);
        return null;
      }
      throw rpcError;
    }
    if (!data || typeof data !== "object") {
      setRider(null);
      return null;
    }
    const raw = data as Record<string, unknown>;
    const next: Rider = {
      id: String(raw.id ?? ""),
      store_id: String(raw.store_id ?? ""),
      name: String(raw.name ?? ""),
      phone: raw.phone ? String(raw.phone) : null,
      approval_status: String(raw.approval_status ?? "pending") as Rider["approval_status"],
      is_active: Boolean(raw.is_active),
      availability_status: String(raw.availability_status ?? "offline") as RiderStatus,
      effective_status: String(raw.effective_status ?? "offline") as RiderStatus,
      vehicle_type: raw.vehicle_type ? String(raw.vehicle_type) : null,
      vehicle_plate: raw.vehicle_plate ? String(raw.vehicle_plate) : null,
      active_orders: Number(raw.active_orders ?? 0),
    };
    setRider(next);
    setStoreId(next.store_id);
    window.localStorage.setItem(STORE_KEY, next.store_id);
    return next;
  }, [supabase]);

  const showNewTaskNotification = useCallback((task: DeliveryTask) => {
    setMessage(`تم إسناد طلب جديد #${shortId(task.id)} إليك.`);
    if (typeof window === "undefined" || !("Notification" in window)) return;
    if (window.Notification.permission !== "granted") return;
    const notification = new window.Notification("طلب توصيل جديد — أسواق الطيبات", {
      body: `${task.customer_name || "زبون"} • ${money(task.total)}`,
      tag: `rider-order-${task.id}`,
    });
    notification.onclick = () => {
      window.focus();
      notification.close();
    };
  }, []);

  const loadTasks = useCallback(async (silent = false) => {
    if (!silent) setTasksLoading(true);
    try {
      const { data, error: rpcError } = await supabase.rpc("rider_my_delivery_tasks");
      if (rpcError) throw rpcError;
      const normalized = ((data ?? []) as Array<Record<string, unknown>>).map((raw) => ({
        id: String(raw.id ?? ""),
        status: String(raw.status ?? "preparing"),
        total: Number(raw.total ?? 0),
        payment_method: String(raw.payment_method ?? "cash"),
        payment_status: String(raw.payment_status ?? "unpaid"),
        address_snapshot:
          raw.address_snapshot && typeof raw.address_snapshot === "object"
            ? (raw.address_snapshot as Record<string, unknown>)
            : {},
        customer_name: raw.customer_name ? String(raw.customer_name) : null,
        customer_phone: raw.customer_phone ? String(raw.customer_phone) : null,
        created_at: raw.created_at ? String(raw.created_at) : null,
        rider_picked_up_at: raw.rider_picked_up_at ? String(raw.rider_picked_up_at) : null,
        rider_started_delivery_at: raw.rider_started_delivery_at ? String(raw.rider_started_delivery_at) : null,
        rider_delivered_at: raw.rider_delivered_at ? String(raw.rider_delivered_at) : null,
        cash_due: Number(raw.cash_due ?? 0),
      })) as DeliveryTask[];

      const nextIds = new Set(normalized.map((task) => task.id));
      if (tasksInitializedRef.current) {
        for (const task of normalized) {
          if (!knownTaskIdsRef.current.has(task.id)) showNewTaskNotification(task);
        }
      } else {
        tasksInitializedRef.current = true;
      }
      knownTaskIdsRef.current = nextIds;
      setTasks(normalized);
    } catch (caught) {
      if (!silent) {
        setError(caught instanceof Error ? caught.message : "تعذر تحميل طلبات التوصيل");
      }
    } finally {
      if (!silent) setTasksLoading(false);
    }
  }, [showNewTaskNotification, supabase]);

  useEffect(() => {
    if (typeof window !== "undefined" && "Notification" in window) {
      setNotificationsEnabled(window.Notification.permission === "granted");
    }
    const params = new URLSearchParams(window.location.search);
    const resolved = params.get("store")?.trim() || window.localStorage.getItem(STORE_KEY)?.trim() || null;
    if (resolved) {
      setStoreId(resolved);
      window.localStorage.setItem(STORE_KEY, resolved);
    }
    void supabase.auth
      .getUser()
      .then(async ({ data }) => {
        if (data.user) await loadRider();
      })
      .catch(() => undefined)
      .finally(() => setLoading(false));
  }, [loadRider, supabase]);

  useEffect(() => {
    if (!rider || rider.approval_status !== "approved" || !rider.is_active) {
      setTasks([]);
      return;
    }
    void loadTasks();
    const tasksTimer = window.setInterval(() => void loadTasks(true), 10000);
    const heartbeatTimer = window.setInterval(async () => {
      try {
        await supabase.rpc("rider_heartbeat");
        await loadRider();
      } catch {
        // A later heartbeat will recover presence.
      }
    }, 30000);
    const onVisible = () => {
      if (document.visibilityState !== "visible") return;
      void supabase.rpc("rider_heartbeat").then(() => loadRider()).catch(() => undefined);
      void loadTasks(true);
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.clearInterval(tasksTimer);
      window.clearInterval(heartbeatTimer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [loadRider, loadTasks, rider?.approval_status, rider?.id, rider?.is_active, supabase]);

  const stopGps = useCallback(() => {
    if (watchIdRef.current !== null && typeof navigator !== "undefined" && navigator.geolocation) {
      navigator.geolocation.clearWatch(watchIdRef.current);
    }
    watchIdRef.current = null;
    lastGpsSendRef.current = 0;
    setGpsOrderId(null);
    setGpsText("GPS غير مشغّل");
  }, []);

  useEffect(() => () => stopGps(), [stopGps]);

  const sendPosition = useCallback(async (orderId: string, position: GeolocationPosition, force = false) => {
    const now = Date.now();
    if (!force && now - lastGpsSendRef.current < 7000) return;
    lastGpsSendRef.current = now;
    const { error: rpcError } = await supabase.rpc("rider_push_location", {
      p_order_id: orderId,
      p_lat: position.coords.latitude,
      p_lng: position.coords.longitude,
      p_accuracy_m: Number.isFinite(position.coords.accuracy) ? position.coords.accuracy : null,
      p_speed_mps:
        position.coords.speed !== null && Number.isFinite(position.coords.speed)
          ? Math.max(0, position.coords.speed)
          : null,
      p_heading_deg:
        position.coords.heading !== null && Number.isFinite(position.coords.heading)
          ? position.coords.heading
          : null,
    });
    if (rpcError) throw rpcError;
    setGpsText(`GPS يعمل • دقة ±${Math.round(position.coords.accuracy)}م`);
  }, [supabase]);

  const startGps = useCallback(async (orderId: string) => {
    if (!navigator.geolocation) {
      setError("هذا الجهاز لا يدعم GPS من المتصفح.");
      return;
    }
    if (gpsOrderId === orderId && watchIdRef.current !== null) return;
    stopGps();
    setGpsText("جاري تشغيل GPS...");
    try {
      const initial = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(resolve, reject, {
          enableHighAccuracy: true,
          timeout: 25000,
          maximumAge: 10000,
        });
      });
      await sendPosition(orderId, initial, true);
      setGpsOrderId(orderId);
      watchIdRef.current = navigator.geolocation.watchPosition(
        (position) => {
          void sendPosition(orderId, position).catch(() => {
            setGpsText("GPS يعمل لكن تعذر إرسال آخر موقع مؤقتًا");
          });
        },
        () => setGpsText("تعذر قراءة GPS — تأكد من صلاحية الموقع"),
        { enableHighAccuracy: true, timeout: 30000, maximumAge: 10000 },
      );
    } catch {
      setGpsText("لم يتم تشغيل GPS");
      setError("اسمح لبوابة المندوب باستخدام الموقع الدقيق ثم حاول مرة ثانية.");
    }
  }, [gpsOrderId, sendPosition, stopGps]);

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

  async function enableNotifications() {
    if (!("Notification" in window)) {
      setError("هذا المتصفح لا يدعم تنبيهات المتصفح.");
      return;
    }
    const permission = await window.Notification.requestPermission();
    setNotificationsEnabled(permission === "granted");
    if (permission === "granted") setMessage("تم تشغيل تنبيهات الطلبات الجديدة.");
  }

  async function runTaskAction(task: DeliveryTask, action: "pickup" | "start" | "complete") {
    if (action === "complete" && task.cash_due > 0) {
      const confirmed = window.confirm(
        `تأكيد التسليم والتحصيل: هل استلمت ${money(task.cash_due)} كاش من الزبون؟`,
      );
      if (!confirmed) return;
    }
    const key = `${task.id}:${action}`;
    setActionBusy(key);
    setError(null);
    setMessage(null);
    try {
      const { error: rpcError } = await supabase.rpc("rider_delivery_action", {
        p_order_id: task.id,
        p_action: action,
      });
      if (rpcError) throw rpcError;
      if (action === "pickup") setMessage("تم تسجيل استلام الطلب من المول.");
      if (action === "start") {
        setMessage("بدأ التوصيل. شغّل GPS ليظهر موقعك للزبون.");
        await startGps(task.id);
      }
      if (action === "complete") {
        if (gpsOrderId === task.id) stopGps();
        setMessage("تم تسليم الطلب بنجاح.");
      }
      await Promise.all([loadRider(), loadTasks(true)]);
    } catch (caught) {
      const raw = caught instanceof Error ? caught.message : String(caught);
      if (raw.includes("PAYMENT_NOT_CONFIRMED")) {
        setError("الدفع الإلكتروني لم يتم تأكيده بعد. تواصل مع المول قبل الخروج.");
      } else {
        setError(raw || "تعذر تحديث الطلب");
      }
    } finally {
      setActionBusy(null);
    }
  }

  async function logout() {
    stopGps();
    await supabase.auth.signOut();
    setTasks([]);
    setRider(null);
  }

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-slate-50" dir="rtl">
        <span className="text-sm text-gray-500">جاري التحميل...</span>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-slate-50 px-4 py-8" dir="rtl">
      <div className="mx-auto max-w-xl space-y-4">
        <header className="rounded-3xl bg-gradient-to-l from-sky-500 via-sky-400 to-cyan-300 p-5 text-white shadow-lg shadow-sky-100">
          <div className="text-xs font-bold text-white/80">أسواق الطيبات</div>
          <h1 className="mt-1 text-2xl font-black">بوابة مندوب التوصيل</h1>
          <p className="mt-2 text-sm leading-6 text-white/90">
            حالتك، طلباتك، العنوان، التحصيل وGPS في شاشة واحدة.
          </p>
        </header>

        {error && <div className="rounded-2xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
        {message && <div className="rounded-2xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">{message}</div>}

        {!rider ? (
          <section className="rounded-3xl border bg-white p-5 shadow-sm">
            <h2 className="text-lg font-black text-gray-950">تسجيل المندوب</h2>
            {!storeId && (
              <div className="mt-3 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
                الرابط غير مربوط بالمول. اطلب رابط التسجيل من الإدارة.
              </div>
            )}
            {!otpSent ? (
              <div className="mt-4 space-y-3">
                <input value={name} onChange={(e) => setName(e.target.value)} className="w-full rounded-xl border px-3 py-3 text-sm outline-none focus:border-sky-400" placeholder="الاسم الكامل" />
                <input value={phone} onChange={(e) => setPhone(e.target.value)} inputMode="tel" dir="ltr" className="w-full rounded-xl border px-3 py-3 text-left text-sm outline-none focus:border-sky-400" placeholder="0791234567" />
                <div className="grid grid-cols-2 gap-2">
                  <input value={vehicleType} onChange={(e) => setVehicleType(e.target.value)} className="rounded-xl border px-3 py-3 text-sm outline-none focus:border-sky-400" placeholder="سيارة / سكوتر" />
                  <input value={vehiclePlate} onChange={(e) => setVehiclePlate(e.target.value)} className="rounded-xl border px-3 py-3 text-sm outline-none focus:border-sky-400" placeholder="رقم اللوحة" />
                </div>
                <button onClick={() => void sendOtp()} disabled={busy || !storeId} className="w-full rounded-xl bg-sky-500 px-4 py-3 text-sm font-black text-white disabled:opacity-50">
                  {busy ? "جاري الإرسال..." : "إرسال رمز التحقق"}
                </button>
              </div>
            ) : (
              <div className="mt-4 space-y-3">
                <div className="rounded-xl bg-sky-50 p-3 text-sm text-sky-800">
                  أدخل الرمز المرسل إلى <b dir="ltr">{otpPhone}</b>
                </div>
                <input value={otp} onChange={(e) => setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))} inputMode="numeric" autoComplete="one-time-code" dir="ltr" className="w-full rounded-xl border px-3 py-4 text-center text-2xl font-black tracking-[0.3em]" placeholder="000000" />
                <button onClick={() => void verifyOtp()} disabled={busy} className="w-full rounded-xl bg-gray-950 px-4 py-3 text-sm font-black text-white disabled:opacity-50">
                  {busy ? "جاري التحقق..." : "تأكيد التسجيل"}
                </button>
                <button onClick={() => { setOtpSent(false); setOtp(""); }} className="w-full rounded-xl border px-4 py-2.5 text-sm font-bold text-gray-600">تغيير الرقم</button>
              </div>
            )}
          </section>
        ) : rider.approval_status === "pending" ? (
          <section className="rounded-3xl border bg-white p-6 text-center shadow-sm">
            <div className="text-4xl">⏳</div>
            <h2 className="mt-3 text-xl font-black">بانتظار موافقة المول</h2>
            <p className="mt-2 text-sm leading-6 text-gray-500">تم تسجيلك باسم {rider.name}. بعد الاعتماد ستظهر لك الطلبات والحالة.</p>
            <button onClick={() => void loadRider()} className="mt-4 rounded-xl bg-gray-950 px-5 py-2.5 text-sm font-bold text-white">تحديث</button>
          </section>
        ) : rider.approval_status === "rejected" ? (
          <section className="rounded-3xl border bg-white p-6 text-center shadow-sm">
            <h2 className="text-xl font-black">الحساب غير معتمد</h2>
            <p className="mt-2 text-sm text-gray-500">تواصل مع إدارة المول لمراجعة الحساب.</p>
          </section>
        ) : (
          <>
            <section className="rounded-3xl border bg-white p-5 shadow-sm">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-xs text-gray-400">مرحبًا</div>
                  <h2 className="text-xl font-black">{rider.name}</h2>
                  <p className="mt-1 text-xs text-gray-500">{rider.phone}{rider.vehicle_type ? ` • ${rider.vehicle_type}` : ""}</p>
                </div>
                <span className={`rounded-full border px-3 py-1.5 text-xs font-black ${statusStyle(rider.effective_status)}`}>
                  {statusLabel(rider.effective_status)}
                </span>
              </div>

              {rider.effective_status === "busy" ? (
                <div className="mt-5 rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm text-sky-800">
                  لديك {rider.active_orders} طلب توصيل نشط. حالتك تتحول تلقائيًا إلى <b>في توصيل</b>.
                </div>
              ) : (
                <div className="mt-5 grid grid-cols-3 gap-2">
                  <button disabled={busy} onClick={() => void setAvailability("available")} className="rounded-2xl border border-emerald-200 bg-emerald-50 p-3 text-sm font-black text-emerald-700">🟢<br />متاح</button>
                  <button disabled={busy} onClick={() => void setAvailability("break")} className="rounded-2xl border border-amber-200 bg-amber-50 p-3 text-sm font-black text-amber-700">🟡<br />استراحة</button>
                  <button disabled={busy} onClick={() => void setAvailability("offline")} className="rounded-2xl border border-gray-200 bg-gray-100 p-3 text-sm font-black text-gray-700">⚫<br />غير متاح</button>
                </div>
              )}

              {!notificationsEnabled && (
                <button onClick={() => void enableNotifications()} className="mt-4 w-full rounded-xl border border-sky-200 bg-sky-50 px-4 py-2.5 text-sm font-bold text-sky-700">
                  🔔 تشغيل تنبيهات الطلبات الجديدة
                </button>
              )}
              <p className="mt-3 text-center text-[11px] leading-5 text-gray-400">
                نبضة حضور كل 30 ثانية. إذا أغلقت الصفحة أو انقطع الإنترنت تظهر غير متصل تلقائيًا.
              </p>
            </section>

            <section className="space-y-3">
              <div className="flex items-end justify-between gap-3 px-1">
                <div>
                  <h2 className="font-black text-gray-950">طلباتك الحالية</h2>
                  <p className="text-xs text-gray-500">لا يظهر لك إلا الطلبات المسندة لحسابك.</p>
                </div>
                <button onClick={() => void loadTasks()} className="text-xs font-black text-sky-700">تحديث</button>
              </div>

              {tasksLoading ? (
                <div className="rounded-2xl border bg-white p-5 text-center text-sm text-gray-500">جاري تحميل الطلبات...</div>
              ) : tasks.length === 0 ? (
                <div className="rounded-2xl border border-dashed bg-white p-8 text-center text-sm text-gray-500">
                  لا يوجد طلب مسند إليك الآن. خليك <b>متاح</b> حتى يظهر اسمك للمول.
                </div>
              ) : (
                tasks.map((task) => {
                  const mapLink = directionsUrl(task.address_snapshot);
                  const notes = addressNotes(task.address_snapshot);
                  const phoneHref = task.customer_phone ? `tel:${task.customer_phone.replace(/[^+\d]/g, "")}` : null;
                  const trackingThis = gpsOrderId === task.id;
                  return (
                    <article key={task.id} className="overflow-hidden rounded-3xl border bg-white shadow-sm">
                      <div className="border-b bg-slate-50 px-5 py-4">
                        <div className="flex items-center justify-between gap-3">
                          <div>
                            <div className="text-xs font-bold text-gray-400">طلب #{shortId(task.id)}</div>
                            <div className="mt-1 font-black text-gray-950">{taskStatusText(task)}</div>
                          </div>
                          <div className="text-left text-lg font-black text-gray-950">{money(task.total)}</div>
                        </div>
                      </div>

                      <div className="space-y-4 p-5">
                        <div>
                          <div className="text-xs font-bold text-gray-400">الزبون</div>
                          <div className="mt-1 font-black text-gray-950">{task.customer_name || "زبون الطيبات"}</div>
                          {task.customer_phone && <div className="mt-1 text-sm text-gray-500" dir="ltr">{task.customer_phone}</div>}
                        </div>

                        <div>
                          <div className="text-xs font-bold text-gray-400">العنوان</div>
                          <div className="mt-1 text-sm font-semibold leading-6 text-gray-800">{addressText(task.address_snapshot)}</div>
                          {notes && <div className="mt-2 rounded-xl bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-800"><b>ملاحظة:</b> {notes}</div>}
                        </div>

                        <div className="grid grid-cols-2 gap-2">
                          {mapLink ? (
                            <a href={mapLink} target="_blank" rel="noreferrer" className="rounded-xl bg-sky-600 px-4 py-3 text-center text-sm font-black text-white">📍 فتح Google Maps</a>
                          ) : (
                            <button disabled className="rounded-xl bg-gray-100 px-4 py-3 text-sm font-black text-gray-400">العنوان غير مكتمل</button>
                          )}
                          {phoneHref ? (
                            <a href={phoneHref} className="rounded-xl bg-gray-950 px-4 py-3 text-center text-sm font-black text-white">📞 اتصال بالزبون</a>
                          ) : (
                            <button disabled className="rounded-xl bg-gray-100 px-4 py-3 text-sm font-black text-gray-400">لا يوجد رقم</button>
                          )}
                        </div>

                        {task.cash_due > 0 && (
                          <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-center">
                            <div className="text-xs font-black text-amber-700">المبلغ المطلوب تحصيله كاش</div>
                            <div className="mt-1 text-3xl font-black text-amber-900">{money(task.cash_due)}</div>
                          </div>
                        )}

                        {task.status === "preparing" && !task.rider_picked_up_at && (
                          <button disabled={Boolean(actionBusy)} onClick={() => void runTaskAction(task, "pickup")} className="w-full rounded-2xl bg-gray-950 px-4 py-3.5 text-sm font-black text-white disabled:opacity-50">
                            {actionBusy === `${task.id}:pickup` ? "جاري التسجيل..." : "✅ استلمت الطلب من المول"}
                          </button>
                        )}

                        {task.status === "preparing" && task.rider_picked_up_at && (
                          <button disabled={Boolean(actionBusy)} onClick={() => void runTaskAction(task, "start")} className="w-full rounded-2xl bg-sky-600 px-4 py-3.5 text-sm font-black text-white disabled:opacity-50">
                            {actionBusy === `${task.id}:start` ? "جاري البدء..." : "🚚 بدأت التوصيل"}
                          </button>
                        )}

                        {task.status === "out_for_delivery" && (
                          <>
                            <div className={`rounded-xl px-3 py-2 text-xs font-bold ${trackingThis ? "bg-emerald-50 text-emerald-700" : "bg-gray-100 text-gray-600"}`}>
                              {trackingThis ? gpsText : "GPS غير مشغّل لهذا الطلب"}
                            </div>
                            {!trackingThis && (
                              <button onClick={() => void startGps(task.id)} className="w-full rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-2.5 text-sm font-black text-emerald-700">📡 تشغيل GPS للزبون</button>
                            )}
                            <button disabled={Boolean(actionBusy)} onClick={() => void runTaskAction(task, "complete")} className="w-full rounded-2xl bg-emerald-600 px-4 py-3.5 text-sm font-black text-white disabled:opacity-50">
                              {actionBusy === `${task.id}:complete` ? "جاري الإكمال..." : task.cash_due > 0 ? "✅ تم التسليم واستلمت المبلغ" : "✅ تم التسليم"}
                            </button>
                          </>
                        )}
                      </div>
                    </article>
                  );
                })
              )}
            </section>

            <button onClick={() => void logout()} className="w-full rounded-xl border bg-white px-4 py-2.5 text-sm font-bold text-gray-600">تسجيل الخروج</button>
          </>
        )}
      </div>
    </main>
  );
}
