"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type OrderInsert = {
  id?: string;
  total?: number | string | null;
  payment_method?: string | null;
  payment_status?: string | null;
  created_at?: string | null;
};

type AlertState = {
  id: string;
  total: number | null;
  paymentMethod: string | null;
};

const ENABLED_KEY = "altayebat_order_device_alerts_enabled";
const LAST_ALERT_KEY = "altayebat_last_order_device_alert";

function displayPaymentMethod(value: string | null) {
  switch (value) {
    case "cash":
      return "كاش";
    case "cliq":
      return "CliQ";
    case "card":
      return "بطاقة";
    default:
      return value || "غير محدد";
  }
}

function shortOrderId(id: string) {
  return id.length > 8 ? id.slice(0, 8).toUpperCase() : id.toUpperCase();
}

export default function OrderDeviceNotifier() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const audioContextRef = useRef<AudioContext | null>(null);
  const [enabled, setEnabled] = useState(false);
  const [permission, setPermission] = useState<NotificationPermission | "unsupported">(
    "unsupported",
  );
  const [realtimeConnected, setRealtimeConnected] = useState(false);
  const [alert, setAlert] = useState<AlertState | null>(null);

  useEffect(() => {
    if (!("Notification" in window)) {
      setPermission("unsupported");
      return;
    }

    setPermission(Notification.permission);
    setEnabled(
      Notification.permission === "granted" &&
        localStorage.getItem(ENABLED_KEY) === "true",
    );
  }, []);

  function ensureAudioContext() {
    if (typeof window === "undefined") return null;

    const AudioContextCtor =
      window.AudioContext ||
      (window as typeof window & { webkitAudioContext?: typeof AudioContext })
        .webkitAudioContext;

    if (!AudioContextCtor) return null;

    if (!audioContextRef.current) {
      audioContextRef.current = new AudioContextCtor();
    }

    return audioContextRef.current;
  }

  async function beepOnce(delayMs = 0) {
    if (delayMs > 0) {
      await new Promise((resolve) => window.setTimeout(resolve, delayMs));
    }

    const ctx = ensureAudioContext();
    if (!ctx) return;

    try {
      if (ctx.state === "suspended") {
        await ctx.resume();
      }

      const oscillator = ctx.createOscillator();
      const gain = ctx.createGain();

      oscillator.type = "sine";
      oscillator.frequency.setValueAtTime(880, ctx.currentTime);

      gain.gain.setValueAtTime(0.0001, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.28, ctx.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.32);

      oscillator.connect(gain);
      gain.connect(ctx.destination);

      oscillator.start();
      oscillator.stop(ctx.currentTime + 0.34);
    } catch {
      // Browser audio policy can block sound until the user interacts with the page.
    }
  }

  async function playOrderSound() {
    await beepOnce(0);
    await beepOnce(420);
    await beepOnce(840);
  }

  async function activateAlerts() {
    let nextPermission: NotificationPermission | "unsupported" = "unsupported";

    if ("Notification" in window) {
      nextPermission =
        Notification.permission === "default"
          ? await Notification.requestPermission()
          : Notification.permission;
    }

    setPermission(nextPermission);

    const ctx = ensureAudioContext();
    if (ctx?.state === "suspended") {
      try {
        await ctx.resume();
      } catch {
        // Ignore; browser notification can still work.
      }
    }

    const active = nextPermission === "granted";
    setEnabled(active);

    if (active) {
      localStorage.setItem(ENABLED_KEY, "true");
      void beepOnce();

      const testNotification = new Notification("إشعارات أسواق الطيبات مفعّلة", {
        body: "سيظهر تنبيه على هذا الجهاز فور وصول طلب جديد.",
        tag: "altayebat-order-alerts-enabled",
      });
      window.setTimeout(() => testNotification.close(), 3500);
    } else {
      localStorage.removeItem(ENABLED_KEY);
    }
  }

  function shouldAlertForOrder(orderId: string) {
    try {
      const raw = localStorage.getItem(LAST_ALERT_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as { id?: string; at?: number };
        if (
          parsed.id === orderId &&
          typeof parsed.at === "number" &&
          Date.now() - parsed.at < 30_000
        ) {
          return false;
        }
      }

      localStorage.setItem(
        LAST_ALERT_KEY,
        JSON.stringify({ id: orderId, at: Date.now() }),
      );
    } catch {
      // localStorage failure should not suppress the alert.
    }

    return true;
  }

  useEffect(() => {
    const channel = supabase
      .channel("admin-new-order-device-alerts")
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "orders",
        },
        (payload) => {
          const order = payload.new as OrderInsert;
          const id = typeof order.id === "string" ? order.id : "";
          if (!id || !shouldAlertForOrder(id)) return;

          const numericTotal =
            order.total === null || order.total === undefined
              ? null
              : Number(order.total);

          const total =
            numericTotal !== null && Number.isFinite(numericTotal)
              ? numericTotal
              : null;

          setAlert({
            id,
            total,
            paymentMethod: order.payment_method ?? null,
          });

          document.title = `🔴 طلب جديد #${shortOrderId(id)} | أسواق الطيبات`;

          window.setTimeout(() => {
            document.title = "لوحة تحكم المول";
          }, 15_000);

          if (enabled) {
            void playOrderSound();

            if (
              "Notification" in window &&
              Notification.permission === "granted"
            ) {
              const notification = new Notification("🔔 طلب جديد - أسواق الطيبات", {
                body: `طلب #${shortOrderId(id)}${
                  total !== null ? ` • ${total.toFixed(2)} د.أ` : ""
                } • ${displayPaymentMethod(order.payment_method ?? null)}`,
                tag: `altayebat-order-${id}`,
                requireInteraction: true,
              });

              notification.onclick = () => {
                window.focus();
                window.location.href = `/dashboard/orders/${id}`;
                notification.close();
              };
            }
          }

          router.refresh();
        },
      )
      .subscribe((status) => {
        setRealtimeConnected(status === "SUBSCRIBED");
      });

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [enabled, router, supabase]);

  return (
    <>
      <div className="fixed bottom-4 left-4 z-[90] flex items-center gap-2 rounded-xl border border-gray-200 bg-white p-2 shadow-lg">
        <span
          className={`h-2.5 w-2.5 rounded-full ${
            realtimeConnected ? "bg-green-500" : "bg-amber-500"
          }`}
          title={realtimeConnected ? "الاتصال المباشر يعمل" : "جاري الاتصال"}
        />

        <button
          type="button"
          onClick={() => void activateAlerts()}
          className={`rounded-lg px-3 py-2 text-xs font-semibold ${
            enabled
              ? "bg-green-50 text-green-700"
              : "bg-red-600 text-white hover:bg-red-700"
          }`}
        >
          {enabled ? "🔔 إشعارات الطلبات مفعّلة" : "🔔 تفعيل إشعارات الطلبات"}
        </button>

        {permission === "denied" && (
          <span className="max-w-44 text-[11px] text-red-600">
            اسمح بالإشعارات من إعدادات المتصفح.
          </span>
        )}
      </div>

      {alert && (
        <div
          className="fixed inset-x-4 top-4 z-[100] mx-auto max-w-xl rounded-2xl border-2 border-red-500 bg-white p-4 shadow-2xl"
          dir="rtl"
        >
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-lg font-bold text-red-600">🔔 طلب جديد وصل الآن</p>
              <p className="mt-1 text-sm font-semibold text-gray-900">
                رقم الطلب #{shortOrderId(alert.id)}
              </p>
              <p className="mt-1 text-sm text-gray-600">
                {alert.total !== null ? `${alert.total.toFixed(2)} د.أ • ` : ""}
                {displayPaymentMethod(alert.paymentMethod)}
              </p>
            </div>

            <button
              type="button"
              onClick={() => setAlert(null)}
              className="rounded-lg px-2 py-1 text-sm text-gray-500 hover:bg-gray-100"
            >
              إغلاق
            </button>
          </div>

          <button
            type="button"
            onClick={() => {
              router.push(`/dashboard/orders/${alert.id}`);
              setAlert(null);
            }}
            className="mt-4 w-full rounded-xl bg-red-600 px-4 py-3 text-sm font-bold text-white hover:bg-red-700"
          >
            فتح الطلب
          </button>
        </div>
      )}
    </>
  );
}
