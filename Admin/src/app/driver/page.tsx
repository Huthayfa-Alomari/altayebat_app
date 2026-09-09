"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type SessionData = {
  order_id: string;
  order_status: string;
  total: number | string;
  payment_method: string;
  payment_status: string;
  expires_at?: string;
  driver?: { id?: string; name?: string; phone?: string | null };
  customer?: { name?: string; phone?: string | null };
  address?: {
    lat?: number | string | null;
    lng?: number | string | null;
    address_text?: string | null;
    city?: string | null;
    area?: string | null;
    street?: string | null;
    building?: string | null;
    floor?: string | null;
    notes?: string | null;
  };
};

type WakeLockLike = { release: () => Promise<void> };
type NavigatorWithWakeLock = Navigator & {
  wakeLock?: { request: (type: "screen") => Promise<WakeLockLike> };
};

const TOKEN_KEY = "altayebat_driver_tracking_token";

function shortId(id: string) {
  return id.replaceAll("-", "").slice(0, 8).toUpperCase();
}

function money(value: number | string) {
  const numeric = Number(value);
  return `${Number.isFinite(numeric) ? numeric.toFixed(2) : "0.00"} د.أ`;
}

function paymentText(method: string, status: string) {
  if (method === "cash") return status === "paid" ? "كاش • تم الدفع" : "كاش عند الاستلام";
  if (method === "cliq") return status === "paid" ? "CliQ • تم الدفع" : "CliQ • بانتظار التأكيد";
  return status === "paid" ? "بطاقة • تم الدفع" : "بطاقة • بانتظار التأكيد";
}

function distanceMeters(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const rad = Math.PI / 180;
  const x = (b.lng - a.lng) * rad * Math.cos(((a.lat + b.lat) / 2) * rad);
  const y = (b.lat - a.lat) * rad;
  return Math.sqrt(x * x + y * y) * 6371000;
}


function geolocationErrorText(error: GeolocationPositionError) {
  if (error.code === error.PERMISSION_DENIED) {
    return "تم رفض صلاحية الموقع. اسمح للموقع باستخدام GPS من إعدادات المتصفح ثم حاول مرة ثانية.";
  }
  if (error.code === error.POSITION_UNAVAILABLE) {
    return "الهاتف لم يتمكن من تحديد الموقع. شغّل الموقع الدقيق (Precise location) ثم حاول مرة ثانية.";
  }
  if (error.code === error.TIMEOUT) {
    return "تحديد الموقع أخذ وقتًا طويلًا. اقترب من نافذة أو مكان مفتوح ثم حاول مرة ثانية.";
  }
  return "تعذر تحديد موقع الهاتف.";
}

async function getCurrentPositionWithFallback() {
  if (!window.isSecureContext) {
    throw new Error("GPS_REQUIRES_HTTPS");
  }
  if (!navigator.geolocation) {
    throw new Error("GEOLOCATION_UNSUPPORTED");
  }

  try {
    if (navigator.permissions?.query) {
      const permission = await navigator.permissions.query({ name: "geolocation" });
      if (permission.state === "denied") {
        throw new Error("GEOLOCATION_PERMISSION_DENIED");
      }
    }
  } catch (permissionError) {
    if (permissionError instanceof Error && permissionError.message === "GEOLOCATION_PERMISSION_DENIED") {
      throw permissionError;
    }
    // Some mobile browsers do not fully implement the Permissions API.
  }

  const read = (options: PositionOptions) =>
    new Promise<GeolocationPosition>((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(resolve, reject, options);
    });

  // Fast first fix: network/cached position usually succeeds indoors.
  try {
    return await read({
      enableHighAccuracy: false,
      timeout: 12000,
      maximumAge: 60000,
    });
  } catch (firstError) {
    if (
      typeof firstError === "object" &&
      firstError !== null &&
      "code" in firstError &&
      Number((firstError as GeolocationPositionError).code) === 1
    ) {
      throw firstError;
    }
  }

  // Second attempt asks for a fresh, precise GPS fix.
  return read({
    enableHighAccuracy: true,
    timeout: 35000,
    maximumAge: 0,
  });
}
function parseCoordinate(value: number | string | null | undefined, axis: "lat" | "lng") {
  if (value === null || value === undefined) return null;
  if (typeof value === "string" && value.trim() === "") return null;

  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return null;
  if (axis === "lat" && (numeric < -90 || numeric > 90)) return null;
  if (axis === "lng" && (numeric < -180 || numeric > 180)) return null;

  return numeric;
}

export default function DriverTrackingPage() {
  const supabase = useMemo(() => createClient(), []);
  const [token, setToken] = useState<string | null>(null);
  const [session, setSession] = useState<SessionData | null>(null);
  const [loading, setLoading] = useState(true);
  const [tracking, setTracking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [gpsText, setGpsText] = useState("لم يبدأ التتبع بعد");
  const [lastSentAt, setLastSentAt] = useState<Date | null>(null);
  const [lastPoint, setLastPoint] = useState<{ lat: number; lng: number } | null>(null);

  const watchIdRef = useRef<number | null>(null);
  const wakeLockRef = useRef<WakeLockLike | null>(null);
  const lastSentMsRef = useRef(0);
  const lastSentPointRef = useRef<{ lat: number; lng: number } | null>(null);
  const pendingPositionRef = useRef<GeolocationPosition | null>(null);
  const retryTimerRef = useRef<number | null>(null);

  const bootstrap = useCallback(
    async (trackingToken: string) => {
      const { data, error: rpcError } = await supabase.rpc("driver_tracking_bootstrap", {
        p_token: trackingToken,
      });
      if (rpcError) throw rpcError;
      setSession(data as SessionData);
    },
    [supabase],
  );

  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.replace(/^#/, ""));
    const fromHash = params.get("token")?.trim() || null;
    const saved = window.localStorage.getItem(TOKEN_KEY)?.trim() || null;
    const current = fromHash || saved;

    if (!current) {
      setError("رابط المندوب غير صالح أو غير مكتمل");
      setLoading(false);
      return;
    }

    setToken(current);
    window.localStorage.setItem(TOKEN_KEY, current);
    if (fromHash) {
      window.history.replaceState(null, "", `${window.location.pathname}#active`);
    }

    void bootstrap(current)
      .catch(() => {
        window.localStorage.removeItem(TOKEN_KEY);
        setError("انتهت صلاحية رابط التوصيل أو تم إيقافه من المول");
      })
      .finally(() => setLoading(false));
  }, [bootstrap]);

  const requestWakeLock = useCallback(async () => {
    try {
      const wakeLock = (navigator as NavigatorWithWakeLock).wakeLock;
      if (!wakeLock || document.visibilityState !== "visible") return;
      wakeLockRef.current = await wakeLock.request("screen");
    } catch {
      // Wake Lock is a convenience only; GPS continues without it when supported.
    }
  }, []);

  const stopTracking = useCallback(async () => {
    if (watchIdRef.current !== null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    if (retryTimerRef.current !== null) {
      window.clearInterval(retryTimerRef.current);
      retryTimerRef.current = null;
    }
    try {
      await wakeLockRef.current?.release();
    } catch {
      // Ignore.
    }
    wakeLockRef.current = null;
    setTracking(false);
  }, []);

  useEffect(() => {
    if (!token) return;
    const timer = window.setInterval(() => {
      void bootstrap(token).catch(() => undefined);
    }, 30000);
    return () => window.clearInterval(timer);
  }, [bootstrap, token]);

  useEffect(() => {
    const onVisibility = () => {
      if (tracking && document.visibilityState === "visible") {
        void requestWakeLock();
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, [requestWakeLock, tracking]);

  useEffect(() => () => {
    if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
    if (retryTimerRef.current !== null) window.clearInterval(retryTimerRef.current);
    void wakeLockRef.current?.release();
  }, []);

  const sendPosition = useCallback(
    async (position: GeolocationPosition, force = false) => {
      if (!token) return;
      const now = Date.now();
      const point = {
        lat: position.coords.latitude,
        lng: position.coords.longitude,
      };
      const moved = lastSentPointRef.current
        ? distanceMeters(lastSentPointRef.current, point)
        : Number.POSITIVE_INFINITY;

      if (!force && now - lastSentMsRef.current < 6000 && moved < 12) return;

      const { error: rpcError } = await supabase.rpc("driver_tracking_push_location", {
        p_token: token,
        p_lat: point.lat,
        p_lng: point.lng,
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

      pendingPositionRef.current = null;
      lastSentMsRef.current = now;
      lastSentPointRef.current = point;
      setLastPoint(point);
      setLastSentAt(new Date(now));
      setGpsText(
        position.coords.accuracy <= 30
          ? `GPS ممتاز • دقة ±${Math.round(position.coords.accuracy)}م`
          : `GPS يعمل • دقة ±${Math.round(position.coords.accuracy)}م`,
      );
    },
    [supabase, token],
  );

  async function startDelivery() {
    if (!token || busy || tracking) return;
    if (!navigator.geolocation) {
      setError("هذا الجهاز لا يدعم GPS من المتصفح");
      return;
    }

    setBusy(true);
    setError(null);
    setGpsText("جاري تحديد موقعك...");
    try {
      const initial = await getCurrentPositionWithFallback();

      const { error: startError } = await supabase.rpc("driver_tracking_start_delivery", {
        p_token: token,
        p_lat: initial.coords.latitude,
        p_lng: initial.coords.longitude,
        p_accuracy_m: initial.coords.accuracy,
      });
      if (startError) throw startError;

      await sendPosition(initial, true);
      await bootstrap(token);
      await requestWakeLock();

      watchIdRef.current = navigator.geolocation.watchPosition(
        (position) => {
          pendingPositionRef.current = position;
          void sendPosition(position).catch(() => {
            setGpsText("انقطع الإنترنت مؤقتًا — سنعيد الإرسال تلقائيًا");
          });
        },
        (geoError) => {
          setGpsText(geolocationErrorText(geoError));
          if (geoError.code === geoError.PERMISSION_DENIED) {
            setError(geolocationErrorText(geoError));
          }
        },
        {
          enableHighAccuracy: true,
          timeout: 30000,
          maximumAge: 10000,
        },
      );

      retryTimerRef.current = window.setInterval(() => {
        const pending = pendingPositionRef.current;
        if (pending) {
          void sendPosition(pending, true).catch(() => undefined);
        }
      }, 12000);

      setTracking(true);
    } catch (caught) {
      const raw = caught instanceof Error ? caught.message : String(caught);
      if (raw.includes("ORDER_NOT_READY")) {
        setError("الطلب لم يصبح جاهزًا بعد. اطلب من المول تحويله إلى قيد التحضير.");
      } else if (raw.includes("PAYMENT_NOT_CONFIRMED")) {
        setError("الدفع الإلكتروني لم يتم تأكيده بعد. تواصل مع المول قبل الخروج.");
      } else if (raw.includes("GEOLOCATION_PERMISSION_DENIED")) {
        setError("صلاحية الموقع مرفوضة. من إعدادات المتصفح اسمح للموقع باستخدام الموقع الدقيق ثم أعد المحاولة.");
        setGpsText("صلاحية GPS مرفوضة");
      } else if (raw.includes("GPS_REQUIRES_HTTPS")) {
        setError("GPS في المتصفح يحتاج رابط HTTPS آمن.");
        setGpsText("GPS يحتاج HTTPS");
      } else if (raw.includes("GEOLOCATION_UNSUPPORTED")) {
        setError("هذا المتصفح لا يدعم تحديد الموقع. افتح الرابط في Chrome أو Safari.");
        setGpsText("المتصفح لا يدعم GPS");
      } else if (typeof caught === "object" && caught !== null && "code" in caught) {
        const message = geolocationErrorText(caught as GeolocationPositionError);
        setError(message);
        setGpsText(message);
      } else if (raw.includes("permission") || raw.includes("Permission")) {
        setError("اسمح للموقع باستخدام GPS ثم حاول مرة ثانية");
      } else {
        setError(`تعذر بدء التوصيل: ${raw || "خطأ غير معروف"}`);
      }
    } finally {
      setBusy(false);
    }
  }

  async function testGps() {
    if (busy) return;
    setBusy(true);
    setError(null);
    setGpsText("جاري اختبار GPS...");
    try {
      const position = await getCurrentPositionWithFallback();
      setLastPoint({ lat: position.coords.latitude, lng: position.coords.longitude });
      setGpsText(`GPS جاهز • دقة ±${Math.round(position.coords.accuracy)}م`);
    } catch (caught) {
      if (typeof caught === "object" && caught !== null && "code" in caught) {
        const message = geolocationErrorText(caught as GeolocationPositionError);
        setError(message);
        setGpsText(message);
      } else {
        const raw = caught instanceof Error ? caught.message : String(caught);
        if (raw.includes("GEOLOCATION_PERMISSION_DENIED")) {
          setError("صلاحية الموقع مرفوضة. اسمح للموقع باستخدام الموقع الدقيق من إعدادات المتصفح.");
          setGpsText("صلاحية GPS مرفوضة");
        } else {
          setError("تعذر اختبار GPS على هذا الجهاز.");
          setGpsText("GPS غير جاهز");
        }
      }
    } finally {
      setBusy(false);
    }
  }

  async function completeDelivery() {
    if (!token || busy) return;
    if (!window.confirm("تأكيد أن الطلب تم تسليمه للزبون؟")) return;
    setBusy(true);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc("driver_tracking_complete_delivery", {
        p_token: token,
      });
      if (rpcError) throw rpcError;
      await stopTracking();
      window.localStorage.removeItem(TOKEN_KEY);
      setSession((current) => (current ? { ...current, order_status: "delivered" } : current));
      setGpsText("تم التسليم بنجاح");
    } catch {
      setError("تعذر تأكيد التسليم. حاول مرة ثانية.");
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return <main className="flex min-h-screen items-center justify-center bg-gray-50 p-6">جاري فتح طلب التوصيل...</main>;
  }

  if (!session) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-gray-50 p-6" dir="rtl">
        <div className="w-full max-w-md rounded-3xl border bg-white p-6 text-center shadow-sm">
          <div className="text-4xl">🔒</div>
          <h1 className="mt-3 text-xl font-black">رابط التوصيل غير متاح</h1>
          <p className="mt-2 text-sm leading-6 text-gray-500">{error || "اطلب رابطًا جديدًا من أسواق الطيبات."}</p>
        </div>
      </main>
    );
  }

  const address = session.address || {};
  const destinationLat = parseCoordinate(address.lat, "lat");
  const destinationLng = parseCoordinate(address.lng, "lng");
  const hasGps =
    destinationLat !== null &&
    destinationLng !== null &&
    !(destinationLat === 0 && destinationLng === 0);
  const addressText = address.address_text || [address.city, address.area, address.street].filter(Boolean).join("، ") || "العنوان غير مكتمل";
  const mapsHref = hasGps
    ? `https://www.google.com/maps/dir/?api=1&destination=${destinationLat},${destinationLng}`
    : `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(addressText)}`;
  const customerPhone = session.customer?.phone?.toString().trim() || "";
  const delivered = session.order_status === "delivered";
  const cancelled = session.order_status === "cancelled";
  const outForDelivery = session.order_status === "out_for_delivery";

  return (
    <main className="min-h-screen bg-gray-50 pb-28" dir="rtl">
      <header className="sticky top-0 z-10 border-b bg-white/95 px-4 py-4 backdrop-blur">
        <div className="mx-auto flex max-w-lg items-center justify-between">
          <div>
            <div className="text-xs font-semibold text-red-600">أسواق الطيبات • المندوب</div>
            <div className="font-black text-gray-950">طلب #{shortId(session.order_id)}</div>
          </div>
          <div className={`rounded-full px-3 py-1.5 text-xs font-bold ${tracking ? "bg-green-50 text-green-700" : "bg-gray-100 text-gray-600"}`}>
            {tracking ? "● GPS مباشر" : delivered ? "تم التسليم" : cancelled ? "الطلب ملغي" : "GPS متوقف"}
          </div>
        </div>
      </header>

      <div className="mx-auto max-w-lg space-y-4 p-4">
        <section className="rounded-3xl border bg-white p-5 shadow-sm">
          <div className="text-xs text-gray-500">مرحبًا</div>
          <div className="mt-1 text-lg font-black text-gray-950">{session.driver?.name || "مندوب الطيبات"}</div>
          <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
            <div className="rounded-2xl bg-gray-50 p-3">
              <div className="text-xs text-gray-500">قيمة الطلب</div>
              <div className="mt-1 font-black">{money(session.total)}</div>
            </div>
            <div className="rounded-2xl bg-gray-50 p-3">
              <div className="text-xs text-gray-500">الدفع</div>
              <div className="mt-1 font-bold">{paymentText(session.payment_method, session.payment_status)}</div>
            </div>
          </div>
        </section>

        <section className="rounded-3xl border bg-white p-5 shadow-sm">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="text-xs text-gray-500">التوصيل إلى</div>
              <div className="mt-1 font-black text-gray-950">{session.customer?.name || "الزبون"}</div>
              <div className="mt-2 text-sm leading-6 text-gray-600">{addressText}</div>
              {address.building && <div className="mt-1 text-xs text-gray-500">بناية {address.building}{address.floor ? ` • طابق ${address.floor}` : ""}</div>}
              {address.notes && <div className="mt-2 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-800">ملاحظة: {address.notes}</div>}
              {!hasGps && (
                <div className="mt-2 rounded-xl bg-amber-50 px-3 py-2 text-xs font-medium leading-5 text-amber-800">
                  هذا العنوان محفوظ بدون نقطة GPS. سيتم فتح Google Maps بالعنوان النصي بدل الإحداثيات.
                </div>
              )}
            </div>
            <div className={`mt-1 h-3 w-3 shrink-0 rounded-full ${hasGps ? "bg-green-500" : "bg-amber-500"}`} />
          </div>

          <div className="mt-4 grid grid-cols-2 gap-2">
            <a href={mapsHref} target="_blank" rel="noreferrer" className="rounded-xl bg-blue-600 px-3 py-3 text-center text-sm font-bold text-white">
              فتح الملاحة
            </a>
            <a
              href={customerPhone ? `tel:${customerPhone}` : undefined}
              aria-disabled={!customerPhone}
              className={`rounded-xl px-3 py-3 text-center text-sm font-bold ${customerPhone ? "bg-gray-950 text-white" : "pointer-events-none bg-gray-100 text-gray-400"}`}
            >
              {customerPhone ? "اتصال بالزبون" : "رقم الزبون غير مسجل"}
            </a>
          </div>
          {!customerPhone && (
            <div className="mt-2 rounded-xl bg-amber-50 px-3 py-2 text-xs font-medium leading-5 text-amber-800">
              لا يوجد رقم هاتف محفوظ لهذا الزبون. اطلب من الزبون حفظ اسمه ورقمه في التطبيق ثم حدّث هذه الصفحة.
            </div>
          )}
        </section>

        <section className="rounded-3xl border bg-white p-5 shadow-sm">
          <div className="font-black text-gray-950">حالة GPS</div>
          <div className="mt-2 text-sm text-gray-600">{gpsText}</div>
          {lastSentAt && <div className="mt-1 text-xs text-gray-400">آخر إرسال {lastSentAt.toLocaleTimeString("ar-JO")}</div>}
          {lastPoint && (
            <div className="mt-2 text-xs text-gray-400">{lastPoint.lat.toFixed(5)}, {lastPoint.lng.toFixed(5)}</div>
          )}
          {!tracking && !delivered && !cancelled && (
            <button
              type="button"
              onClick={() => void testGps()}
              disabled={busy}
              className="mt-3 w-full rounded-xl border border-gray-200 bg-white px-3 py-2.5 text-sm font-bold text-gray-700 disabled:opacity-50"
            >
              {busy ? "جاري الفحص..." : "اختبار GPS على هذا الهاتف"}
            </button>
          )}
          {!delivered && !cancelled && (
            <div className="mt-4 rounded-2xl bg-red-50 p-3 text-xs leading-6 text-red-800">
              أثناء التوصيل اترك هذه الصفحة مفتوحة قدر الإمكان. سيحاول النظام إبقاء الشاشة نشطة وإعادة إرسال آخر موقع إذا انقطع الإنترنت مؤقتًا.
            </div>
          )}
        </section>

        {error && <div className="rounded-2xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
      </div>

      <div className="fixed inset-x-0 bottom-0 border-t bg-white/95 p-4 backdrop-blur">
        <div className="mx-auto max-w-lg">
          {delivered ? (
            <div className="rounded-2xl bg-green-50 px-4 py-4 text-center font-black text-green-700">✓ تم تسليم الطلب</div>
          ) : cancelled ? (
            <div className="rounded-2xl bg-gray-100 px-4 py-4 text-center font-black text-gray-700">تم إلغاء الطلب — لا تبدأ التوصيل</div>
          ) : outForDelivery || tracking ? (
            <div className="grid grid-cols-[1fr_auto] gap-2">
              <button
                type="button"
                onClick={() => void completeDelivery()}
                disabled={busy}
                className="rounded-2xl bg-green-600 px-5 py-4 font-black text-white disabled:opacity-50"
              >
                تم التسليم
              </button>
              {!tracking && (
                <button
                  type="button"
                  onClick={() => void startDelivery()}
                  disabled={busy}
                  className="rounded-2xl border px-4 py-4 text-sm font-bold"
                >
                  تشغيل GPS
                </button>
              )}
            </div>
          ) : (
            <button
              type="button"
              onClick={() => void startDelivery()}
              disabled={busy}
              className="w-full rounded-2xl bg-red-600 px-5 py-4 text-lg font-black text-white shadow-lg disabled:opacity-50"
            >
              {busy ? "جاري بدء التوصيل..." : "ابدأ التوصيل وGPS"}
            </button>
          )}
        </div>
      </div>
    </main>
  );
}
