"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

type Driver = {
  id: string;
  name: string;
  phone: string | null;
  is_active: boolean;
  active_orders: number;
};

type Order = {
  id: string;
  status: string;
  total: number | string;
  payment_method: string;
  payment_status: string;
  driver_id: string | null;
  address_snapshot: Record<string, unknown> | null;
  created_at: string | null;
};

type DriverLocation = {
  order_id: string;
  lat: number | string;
  lng: number | string;
  updated_at: string | null;
  recorded_at?: string | null;
};

function shortId(id: string) {
  return id.replaceAll("-", "").slice(0, 8).toUpperCase();
}

function money(value: number | string) {
  const numeric = Number(value);
  return `${Number.isFinite(numeric) ? numeric.toFixed(2) : "0.00"} د.أ`;
}

function statusLabel(value: string) {
  if (value === "pending") return "بانتظار التأكيد";
  if (value === "preparing") return "قيد التحضير";
  if (value === "out_for_delivery") return "بالتوصيل";
  return value;
}

function paymentLabel(method: string, status: string) {
  if (method === "cash") {
    return status === "paid" ? "كاش • تم الدفع" : "كاش عند الاستلام";
  }
  if (method === "cliq") {
    return status === "paid" ? "CliQ • مدفوع" : "CliQ • بانتظار التأكيد";
  }
  return status === "paid" ? "بطاقة • مدفوع" : "بطاقة • بانتظار التأكيد";
}

function mapUrl(location?: DriverLocation) {
  if (!location) return null;
  const lat = Number(location.lat);
  const lng = Number(location.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

function freshness(location?: DriverLocation) {
  if (!location) return "لم يبدأ GPS بعد";
  const raw = location.recorded_at || location.updated_at;
  if (!raw) return "يوجد موقع مسجل";
  const seconds = Math.max(
    0,
    Math.floor((Date.now() - new Date(raw).getTime()) / 1000),
  );
  if (seconds < 30) return "مباشر الآن";
  if (seconds < 60) return `قبل ${seconds} ثانية`;
  return `قبل ${Math.floor(seconds / 60)} دقيقة`;
}

export default function DeliveryManagementPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [locations, setLocations] = useState<Record<string, DriverLocation>>({});
  const [selectedDrivers, setSelectedDrivers] = useState<Record<string, string>>({});
  const [generatedLinks, setGeneratedLinks] = useState<Record<string, string>>({});
  const [driverName, setDriverName] = useState("");
  const [driverPhone, setDriverPhone] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setError(null);
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("يجب تسجيل الدخول أولاً");

      const { data: adminLink, error: adminError } = await supabase
        .from("store_admins")
        .select("store_id")
        .eq("user_id", user.id)
        .maybeSingle();

      if (adminError) throw adminError;
      const currentStoreId = adminLink?.store_id?.toString();
      if (!currentStoreId) throw new Error("لم يتم العثور على متجر مرتبط بهذا الحساب");
      setStoreId(currentStoreId);

      const [{ data: driverRows, error: driversError }, { data: orderRows, error: ordersError }] =
        await Promise.all([
          supabase.rpc("admin_list_delivery_drivers", {
            p_store_id: currentStoreId,
          }),
          supabase
            .from("orders")
            .select(
              "id,status,total,payment_method,payment_status,driver_id,address_snapshot,created_at",
            )
            .eq("store_id", currentStoreId)
            .in("status", ["pending", "preparing", "out_for_delivery"])
            .order("created_at", { ascending: true }),
        ]);

      if (driversError) throw driversError;
      if (ordersError) throw ordersError;

      const normalizedDrivers = ((driverRows ?? []) as Array<Record<string, unknown>>).map(
        (row) => ({
          id: String(row.id),
          name: String(row.name ?? ""),
          phone: row.phone ? String(row.phone) : null,
          is_active: Boolean(row.is_active),
          active_orders: Number(row.active_orders ?? 0),
        }),
      );
      const normalizedOrders = ((orderRows ?? []) as Array<Record<string, unknown>>).map(
        (row) => ({
          id: String(row.id),
          status: String(row.status ?? "pending"),
          total: (row.total as number | string) ?? 0,
          payment_method: String(row.payment_method ?? "cash"),
          payment_status: String(row.payment_status ?? "unpaid"),
          driver_id: row.driver_id ? String(row.driver_id) : null,
          address_snapshot:
            row.address_snapshot && typeof row.address_snapshot === "object"
              ? (row.address_snapshot as Record<string, unknown>)
              : null,
          created_at: row.created_at ? String(row.created_at) : null,
        }),
      );

      setDrivers(normalizedDrivers);
      setOrders(normalizedOrders);
      setSelectedDrivers((current) => {
        const next = { ...current };
        for (const order of normalizedOrders) {
          if (!next[order.id] && order.driver_id) next[order.id] = order.driver_id;
        }
        return next;
      });

      const orderIds = normalizedOrders.map((order) => order.id);
      if (orderIds.length > 0) {
        const { data: locationRows, error: locationError } = await supabase
          .from("driver_locations")
          .select("order_id,lat,lng,updated_at,recorded_at")
          .in("order_id", orderIds);
        if (locationError) throw locationError;

        const nextLocations: Record<string, DriverLocation> = {};
        for (const row of (locationRows ?? []) as Array<Record<string, unknown>>) {
          const orderId = String(row.order_id ?? "");
          if (!orderId) continue;
          nextLocations[orderId] = {
            order_id: orderId,
            lat: row.lat as number | string,
            lng: row.lng as number | string,
            updated_at: row.updated_at ? String(row.updated_at) : null,
            recorded_at: row.recorded_at ? String(row.recorded_at) : null,
          };
        }
        setLocations(nextLocations);
      } else {
        setLocations({});
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر تحميل بيانات التوصيل");
    } finally {
      setLoading(false);
    }
  }, [supabase]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!storeId) return;

    const channel = supabase
      .channel(`admin-delivery-${storeId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "orders",
          filter: `store_id=eq.${storeId}`,
        },
        () => void load(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "driver_locations" },
        () => void load(),
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [load, storeId, supabase]);

  async function createDriver(event: FormEvent) {
    event.preventDefault();
    if (!storeId || !driverName.trim()) return;
    setBusy("create-driver");
    setError(null);
    setSuccess(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_create_delivery_driver", {
        p_store_id: storeId,
        p_name: driverName.trim(),
        p_phone: driverPhone.trim() || null,
      });
      if (rpcError) throw rpcError;
      setDriverName("");
      setDriverPhone("");
      setSuccess("تمت إضافة المندوب");
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر إضافة المندوب");
    } finally {
      setBusy(null);
    }
  }

  async function createTrackingLink(order: Order) {
    const driverId = selectedDrivers[order.id] || order.driver_id;
    if (!driverId) {
      setError("اختر المندوب أولاً");
      return;
    }
    if (order.status === "pending") {
      setError("حوّل حالة الطلب إلى قيد التحضير قبل إرسال الطلب للمندوب");
      return;
    }

    setBusy(order.id);
    setError(null);
    setSuccess(null);
    try {
      const { error: assignError } = await supabase.rpc(
        "admin_assign_delivery_driver",
        { p_order_id: order.id, p_driver_id: driverId },
      );
      if (assignError) throw assignError;

      const { data, error: issueError } = await supabase.rpc(
        "admin_issue_driver_tracking_session",
        { p_order_id: order.id, p_driver_id: driverId },
      );
      if (issueError) throw issueError;

      const token = (data as Record<string, unknown> | null)?.token?.toString();
      if (!token) throw new Error("تعذر إنشاء رابط المندوب");

      const link = `${window.location.origin}/driver#token=${token}`;
      setGeneratedLinks((current) => ({ ...current, [order.id]: link }));
      setSuccess(`تم تجهيز رابط المندوب للطلب #${shortId(order.id)}`);
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر تجهيز رابط المندوب");
    } finally {
      setBusy(null);
    }
  }

  async function shareLink(orderId: string) {
    const link = generatedLinks[orderId];
    if (!link) return;
    try {
      if (navigator.share) {
        await navigator.share({
          title: "رابط توصيل أسواق الطيبات",
          text: `رابط المندوب للطلب #${shortId(orderId)}`,
          url: link,
        });
      } else {
        await navigator.clipboard.writeText(link);
        setSuccess("تم نسخ رابط المندوب");
      }
    } catch {
      // Closing the native share sheet is not an application error.
    }
  }

  async function revokeTracking(orderId: string) {
    setBusy(`revoke-${orderId}`);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_revoke_driver_tracking", {
        p_order_id: orderId,
      });
      if (rpcError) throw rpcError;
      setGeneratedLinks((current) => {
        const next = { ...current };
        delete next[orderId];
        return next;
      });
      setSuccess("تم إيقاف رابط التتبع");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "تعذر إيقاف التتبع");
    } finally {
      setBusy(null);
    }
  }

  if (loading) {
    return <div className="p-6 text-sm text-gray-500">جاري تحميل التوصيل...</div>;
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-4 sm:p-6" dir="rtl">
      <div>
        <h1 className="text-2xl font-bold text-gray-950">إدارة التوصيل المباشر</h1>
        <p className="mt-1 text-sm text-gray-500">
          عيّن المندوب، أرسل له رابطًا آمنًا، ويشاهد الزبون موقعه مباشرة داخل التطبيق.
        </p>
      </div>

      {error && <div className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
      {success && <div className="rounded-xl bg-green-50 px-4 py-3 text-sm text-green-700">{success}</div>}

      <section className="grid gap-3 md:grid-cols-3">
        {[
          ["1", "جهّز الطلب", "حوّل الطلب إلى قيد التحضير من صفحة الطلبات."],
          ["2", "عيّن المندوب", "اختر المندوب وأنشئ رابط التوصيل."],
          ["3", "تتبع مباشر", "المندوب يضغط بدء التوصيل ويبدأ GPS تلقائيًا."],
        ].map(([number, title, body]) => (
          <div key={number} className="rounded-2xl border bg-white p-4 shadow-sm">
            <div className="mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-red-50 font-bold text-red-600">
              {number}
            </div>
            <div className="font-bold text-gray-900">{title}</div>
            <div className="mt-1 text-sm leading-6 text-gray-500">{body}</div>
          </div>
        ))}
      </section>

      <section className="rounded-2xl border bg-white p-4 shadow-sm sm:p-5">
        <h2 className="font-bold text-gray-950">المندوبون</h2>
        <form onSubmit={createDriver} className="mt-4 grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
          <input
            value={driverName}
            onChange={(event) => setDriverName(event.target.value)}
            placeholder="اسم المندوب"
            className="rounded-xl border px-3 py-2.5 text-sm outline-none focus:border-red-500"
            required
          />
          <input
            value={driverPhone}
            onChange={(event) => setDriverPhone(event.target.value)}
            placeholder="رقم الهاتف (اختياري)"
            className="rounded-xl border px-3 py-2.5 text-sm outline-none focus:border-red-500"
          />
          <button
            type="submit"
            disabled={busy === "create-driver"}
            className="rounded-xl bg-gray-950 px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50"
          >
            {busy === "create-driver" ? "جاري الإضافة..." : "إضافة مندوب"}
          </button>
        </form>

        <div className="mt-4 flex flex-wrap gap-2">
          {drivers.length === 0 ? (
            <span className="text-sm text-gray-500">أضف أول مندوب للبدء.</span>
          ) : (
            drivers.map((driver) => (
              <span key={driver.id} className="rounded-full border bg-gray-50 px-3 py-1.5 text-xs text-gray-700">
                {driver.name}{driver.phone ? ` • ${driver.phone}` : ""}
                {driver.active_orders > 0 ? ` • ${driver.active_orders} طلب` : ""}
              </span>
            ))
          )}
        </div>
      </section>

      <section className="space-y-3">
        <div className="flex items-end justify-between gap-3">
          <div>
            <h2 className="font-bold text-gray-950">طلبات التوصيل الحالية</h2>
            <p className="text-xs text-gray-500">الموقع يتحدث تلقائيًا عند وصول GPS من جهاز المندوب.</p>
          </div>
          <Link href="/dashboard" className="text-sm font-semibold text-red-600 hover:underline">
            كل الطلبات
          </Link>
        </div>

        {orders.length === 0 ? (
          <div className="rounded-2xl border border-dashed bg-white p-8 text-center text-sm text-gray-500">
            لا توجد طلبات نشطة الآن.
          </div>
        ) : (
          orders.map((order) => {
            const location = locations[order.id];
            const currentMapUrl = mapUrl(location);
            const addressText = order.address_snapshot?.address_text?.toString() || "العنوان غير مكتمل";
            const generatedLink = generatedLinks[order.id];
            const currentDriver = selectedDrivers[order.id] || order.driver_id || "";
            const canIssue = order.status !== "pending" && drivers.some((driver) => driver.is_active);

            return (
              <article key={order.id} className="rounded-2xl border bg-white p-4 shadow-sm sm:p-5">
                <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Link href={`/dashboard/orders/${order.id}`} className="font-black text-gray-950 hover:text-red-600">
                        طلب #{shortId(order.id)}
                      </Link>
                      <span className="rounded-full bg-gray-100 px-2.5 py-1 text-xs font-semibold text-gray-700">
                        {statusLabel(order.status)}
                      </span>
                      {order.status === "out_for_delivery" && (
                        <span className="rounded-full bg-green-50 px-2.5 py-1 text-xs font-semibold text-green-700">
                          GPS: {freshness(location)}
                        </span>
                      )}
                    </div>
                    <div className="mt-2 text-sm text-gray-600">{addressText}</div>
                    <div className="mt-1 text-xs text-gray-500">
                      {money(order.total)} • {paymentLabel(order.payment_method, order.payment_status)}
                    </div>
                  </div>

                  <div className="grid gap-2 sm:min-w-[360px] sm:grid-cols-[1fr_auto]">
                    <select
                      value={currentDriver}
                      onChange={(event) =>
                        setSelectedDrivers((current) => ({
                          ...current,
                          [order.id]: event.target.value,
                        }))
                      }
                      className="rounded-xl border px-3 py-2.5 text-sm"
                    >
                      <option value="">اختر المندوب</option>
                      {drivers
                        .filter((driver) => driver.is_active)
                        .map((driver) => (
                          <option key={driver.id} value={driver.id}>
                            {driver.name}
                          </option>
                        ))}
                    </select>
                    <button
                      type="button"
                      disabled={!canIssue || busy === order.id}
                      onClick={() => void createTrackingLink(order)}
                      className="rounded-xl bg-red-600 px-4 py-2.5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {busy === order.id ? "جاري التجهيز..." : generatedLink ? "تدوير الرابط" : "رابط المندوب"}
                    </button>
                  </div>
                </div>

                {order.status === "pending" && (
                  <div className="mt-4 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-800">
                    الرابط يصبح متاحًا بعد تحويل حالة الطلب إلى <b>قيد التحضير</b>.
                  </div>
                )}

                {generatedLink && (
                  <div className="mt-4 rounded-xl border border-red-100 bg-red-50/50 p-3">
                    <div className="text-xs font-bold text-red-700">رابط خاص بهذا الطلب — صالح لمدة 18 ساعة</div>
                    <div className="mt-2 break-all rounded-lg bg-white px-3 py-2 text-xs text-gray-600">{generatedLink}</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => void shareLink(order.id)}
                        className="rounded-lg bg-gray-950 px-3 py-2 text-xs font-bold text-white"
                      >
                        مشاركة / نسخ
                      </button>
                      <button
                        type="button"
                        onClick={() => void revokeTracking(order.id)}
                        disabled={busy === `revoke-${order.id}`}
                        className="rounded-lg border border-red-200 px-3 py-2 text-xs font-bold text-red-700"
                      >
                        إيقاف الرابط
                      </button>
                    </div>
                  </div>
                )}

                {location && (
                  <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-xl bg-green-50 px-3 py-3 text-sm text-green-800">
                    <span className="font-semibold">آخر موقع: {freshness(location)}</span>
                    {currentMapUrl && (
                      <a href={currentMapUrl} target="_blank" rel="noreferrer" className="font-bold underline">
                        فتح موقع المندوب
                      </a>
                    )}
                  </div>
                )}
              </article>
            );
          })
        )}
      </section>
    </div>
  );
}
