"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { createClient } from "@/lib/supabase/client";

type JsonObject = Record<string, unknown>;
type AlertRow = {
  id: number;
  alert_type: string;
  severity: "info" | "warning" | "critical";
  title: string;
  message: string;
  entity_type?: string | null;
  entity_id?: string | null;
  status: "open" | "acknowledged" | "resolved";
  created_at?: string | null;
};

type ConfigForm = {
  low_stock_threshold: number;
  order_pending_alert_minutes: number;
  order_preparing_alert_minutes: number;
  delivery_gps_stale_seconds: number;
  delivery_late_grace_minutes: number;
  payment_pending_alert_minutes: number;
  product_report_days: number;
};

const DEFAULT_CONFIG: ConfigForm = {
  low_stock_threshold: 5,
  order_pending_alert_minutes: 10,
  order_preparing_alert_minutes: 25,
  delivery_gps_stale_seconds: 120,
  delivery_late_grace_minutes: 10,
  payment_pending_alert_minutes: 15,
  product_report_days: 30,
};

function objectOf(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonObject)
    : {};
}

function arrayOf(value: unknown): JsonObject[] {
  return Array.isArray(value)
    ? value.filter((item): item is JsonObject => Boolean(item && typeof item === "object"))
    : [];
}

function stringOf(value: unknown, fallback = "—"): string {
  if (typeof value === "string" && value.trim()) return value;
  if (typeof value === "number") return String(value);
  return fallback;
}

function numberOf(value: unknown, fallback = 0): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatMoney(value: unknown): string {
  return `${numberOf(value).toFixed(2)} د.أ`;
}

function shortId(value: unknown): string {
  const text = stringOf(value, "");
  return text ? text.slice(0, 8).toUpperCase() : "—";
}

function formatDate(value: unknown): string {
  if (typeof value !== "string" || !value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("ar-JO", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function severityClasses(severity: AlertRow["severity"]): string {
  if (severity === "critical") return "border-red-200 bg-red-50 text-red-800";
  if (severity === "warning") return "border-amber-200 bg-amber-50 text-amber-800";
  return "border-blue-200 bg-blue-50 text-blue-800";
}

function severityLabel(severity: AlertRow["severity"]): string {
  if (severity === "critical") return "حرج";
  if (severity === "warning") return "تحذير";
  return "معلومة";
}

function readConfig(raw: JsonObject): ConfigForm {
  return {
    low_stock_threshold: numberOf(raw.low_stock_threshold, 5),
    order_pending_alert_minutes: numberOf(raw.order_pending_alert_minutes, 10),
    order_preparing_alert_minutes: numberOf(raw.order_preparing_alert_minutes, 25),
    delivery_gps_stale_seconds: numberOf(raw.delivery_gps_stale_seconds, 120),
    delivery_late_grace_minutes: numberOf(raw.delivery_late_grace_minutes, 10),
    payment_pending_alert_minutes: numberOf(raw.payment_pending_alert_minutes, 15),
    product_report_days: numberOf(raw.product_report_days, 30),
  };
}

export default function OperationsCenterPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [dashboard, setDashboard] = useState<JsonObject | null>(null);
  const [config, setConfig] = useState<ConfigForm>(DEFAULT_CONFIG);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const loadStore = useCallback(async () => {
    const { data, error: adminError } = await supabase
      .from("store_admins")
      .select("store_id")
      .limit(1)
      .maybeSingle();

    if (adminError) throw adminError;
    const id = data?.store_id;
    if (!id) throw new Error("لم يتم العثور على متجر مرتبط بحساب الإدارة.");
    setStoreId(id);
    return id as string;
  }, [supabase]);

  const refresh = useCallback(async (knownStoreId?: string) => {
    setError(null);
    try {
      const id = knownStoreId ?? storeId ?? (await loadStore());
      const { data, error: rpcError } = await supabase.rpc("admin_get_ops_dashboard", {
        p_store_id: id,
      });
      if (rpcError) throw rpcError;
      const next = objectOf(data);
      setDashboard(next);
      setConfig(readConfig(objectOf(next.config)));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "تعذر تحميل مركز العمليات.");
    } finally {
      setLoading(false);
    }
  }, [loadStore, storeId, supabase]);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    if (!storeId) return;
    const timer = window.setInterval(() => { void refresh(storeId); }, 30_000);
    return () => window.clearInterval(timer);
  }, [refresh, storeId]);

  async function runCheck(check: string, successText: string) {
    if (!storeId) return;
    setWorking(check);
    setError(null);
    setMessage(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_run_ops_check", {
        p_store_id: storeId,
        p_check: check,
      });
      if (rpcError) throw rpcError;
      setMessage(successText);
      await refresh(storeId);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "فشل تشغيل الفحص.");
    } finally {
      setWorking(null);
    }
  }

  async function updateAlert(id: number, status: "acknowledged" | "resolved") {
    setWorking(`alert-${id}`);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_set_ops_alert_status", {
        p_alert_id: id,
        p_status: status,
      });
      if (rpcError) throw rpcError;
      await refresh(storeId ?? undefined);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "تعذر تحديث التنبيه.");
    } finally {
      setWorking(null);
    }
  }

  async function saveConfig() {
    if (!storeId) return;
    setWorking("config");
    setError(null);
    setMessage(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_update_ops_config", {
        p_store_id: storeId,
        p_low_stock_threshold: config.low_stock_threshold,
        p_order_pending_alert_minutes: config.order_pending_alert_minutes,
        p_order_preparing_alert_minutes: config.order_preparing_alert_minutes,
        p_delivery_gps_stale_seconds: config.delivery_gps_stale_seconds,
        p_delivery_late_grace_minutes: config.delivery_late_grace_minutes,
        p_payment_pending_alert_minutes: config.payment_pending_alert_minutes,
        p_product_report_days: config.product_report_days,
      });
      if (rpcError) throw rpcError;
      setMessage("تم حفظ إعدادات التشغيل.");
      await refresh(storeId);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "تعذر حفظ الإعدادات.");
    } finally {
      setWorking(null);
    }
  }

  const today = objectOf(dashboard?.today);
  const metrics = objectOf(today.metrics);
  const topProducts = arrayOf(today.top_products);
  const alerts = arrayOf(dashboard?.alerts) as unknown as AlertRow[];
  const lowStock = arrayOf(objectOf(dashboard?.low_stock).items);
  const delayedOrders = arrayOf(objectOf(dashboard?.delayed_orders).items);
  const deliveries = arrayOf(objectOf(dashboard?.delivery).items);
  const paymentIssues = arrayOf(objectOf(dashboard?.payments).items);
  const reports = arrayOf(dashboard?.reports);
  const openAlertCount = numberOf(dashboard?.open_alert_count);

  if (loading) {
    return <div className="flex min-h-[50vh] items-center justify-center" dir="rtl"><p className="text-sm text-gray-500">جاري تحميل مركز العمليات...</p></div>;
  }

  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">العمليات والتقارير</h1>
          <p className="mt-1 text-sm text-gray-500">مراقبة الطلبات والمخزون والتوصيل والدفع والتقارير من مكان واحد.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button type="button" disabled={working !== null} onClick={() => void runCheck("all", "تم فحص العمليات الآن.")} className="rounded-xl bg-gray-900 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
            {working === "all" ? "جاري الفحص..." : "تشغيل الفحص الآن"}
          </button>
          <button type="button" onClick={() => void refresh(storeId ?? undefined)} className="rounded-xl border border-gray-200 bg-white px-4 py-2.5 text-sm font-semibold text-gray-700">تحديث</button>
        </div>
      </div>

      {error && <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
      {message && <div className="rounded-xl border border-green-200 bg-green-50 p-3 text-sm text-green-700">{message}</div>}

      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        <MetricCard label="طلبات اليوم" value={numberOf(metrics.orders_count)} />
        <MetricCard label="تم التسليم" value={numberOf(metrics.delivered_count)} />
        <MetricCard label="مبيعات مسلمة" value={formatMoney(metrics.delivered_revenue)} />
        <MetricCard label="متوسط الطلب" value={formatMoney(metrics.average_order_value)} />
        <MetricCard label="تنبيهات مفتوحة" value={openAlertCount} danger={openAlertCount > 0} />
      </section>

      <section className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
        <div className="mb-4 flex items-center justify-between gap-3">
          <div><h2 className="text-lg font-bold text-gray-900">مركز التنبيهات</h2><p className="text-xs text-gray-500">الطلب المتأخر، المخزون، GPS، التوصيل والدفع.</p></div>
          <span className="rounded-full bg-gray-100 px-3 py-1 text-xs font-bold text-gray-700">{openAlertCount} مفتوح</span>
        </div>
        {alerts.length === 0 ? <EmptyState text="لا توجد تنبيهات تشغيلية مفتوحة." /> : (
          <div className="space-y-3">
            {alerts.map((alert) => (
              <div key={alert.id} className={`rounded-xl border p-4 ${severityClasses(alert.severity)}`}>
                <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                  <div>
                    <div className="flex flex-wrap items-center gap-2"><span className="text-sm font-bold">{alert.title}</span><span className="rounded-full bg-white/70 px-2 py-0.5 text-[11px] font-bold">{severityLabel(alert.severity)}</span></div>
                    <p className="mt-1 text-sm">{alert.message}</p><p className="mt-1 text-[11px] opacity-70">{formatDate(alert.created_at)}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {alert.entity_type === "order" && alert.entity_id && <Link href={`/dashboard/orders/${alert.entity_id}`} className="rounded-lg bg-white px-3 py-2 text-xs font-bold text-gray-800 shadow-sm">فتح الطلب</Link>}
                    <button type="button" disabled={working === `alert-${alert.id}`} onClick={() => void updateAlert(alert.id, "acknowledged")} className="rounded-lg border border-current/20 bg-white/60 px-3 py-2 text-xs font-bold disabled:opacity-50">تمت المراجعة</button>
                    <button type="button" disabled={working === `alert-${alert.id}`} onClick={() => void updateAlert(alert.id, "resolved")} className="rounded-lg border border-current/20 bg-white/60 px-3 py-2 text-xs font-bold disabled:opacity-50">إغلاق</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="grid gap-4 xl:grid-cols-2">
        <OpsPanel title="الطلبات المتأخرة" count={delayedOrders.length} onRun={() => void runCheck("delayed_orders", "تم فحص الطلبات المتأخرة.")} running={working === "delayed_orders"}>
          {delayedOrders.length === 0 ? <EmptyState text="لا توجد طلبات متأخرة." /> : <div className="space-y-2">{delayedOrders.map((item) => <Link key={stringOf(item.order_id)} href={`/dashboard/orders/${stringOf(item.order_id, "")}`} className="flex items-center justify-between rounded-xl bg-gray-50 p-3 hover:bg-gray-100"><div><p className="text-sm font-bold text-gray-900">#{shortId(item.order_id)}</p><p className="text-xs text-gray-500">{stringOf(item.status)} • {numberOf(item.minutes_in_status).toFixed(0)} دقيقة</p></div><span className="text-sm font-bold text-gray-900">{formatMoney(item.total)}</span></Link>)}</div>}
        </OpsPanel>

        <OpsPanel title="المخزون" count={lowStock.length} onRun={() => void runCheck("low_stock", "تم فحص المخزون.")} running={working === "low_stock"}>
          {lowStock.length === 0 ? <EmptyState text="لا توجد منتجات تحت حد المخزون حاليًا." /> : <div className="space-y-2">{lowStock.slice(0, 12).map((item) => <div key={stringOf(item.product_id)} className="flex items-center justify-between rounded-xl bg-gray-50 p-3"><div><p className="text-sm font-semibold text-gray-900">{stringOf(item.name)}</p><p className="text-xs text-gray-500">الحد: {numberOf(item.threshold)}</p></div><span className="text-sm font-bold text-red-600">{numberOf(item.stock_qty)}</span></div>)}</div>}
        </OpsPanel>

        <OpsPanel title="مراقبة التوصيل وGPS" count={deliveries.length} onRun={() => void runCheck("delivery", "تم فحص التوصيل وGPS.")} running={working === "delivery"}>
          {deliveries.length === 0 ? <EmptyState text="لا توجد طلبات خارجة للتوصيل الآن." /> : <div className="space-y-2">{deliveries.map((item) => <div key={stringOf(item.order_id)} className="rounded-xl bg-gray-50 p-3"><div className="flex items-center justify-between gap-3"><div><p className="text-sm font-bold text-gray-900">#{shortId(item.order_id)} • {stringOf(item.driver_name, "بدون مندوب")}</p><p className="text-xs text-gray-500">آخر GPS: {formatDate(item.last_location_at)}</p></div><div className="text-left text-xs">{Boolean(item.missing_gps) && <span className="rounded-full bg-red-100 px-2 py-1 font-bold text-red-700">GPS مفقود</span>}{!Boolean(item.missing_gps) && Boolean(item.stale_gps) && <span className="rounded-full bg-amber-100 px-2 py-1 font-bold text-amber-700">GPS متوقف</span>}{Boolean(item.late_delivery) && <span className="mr-1 rounded-full bg-red-100 px-2 py-1 font-bold text-red-700">متأخر</span>}</div></div></div>)}</div>}
        </OpsPanel>

        <OpsPanel title="مراجعة الدفع" count={paymentIssues.length} onRun={() => void runCheck("payments", "تم فحص حالات الدفع.")} running={working === "payments"}>
          {paymentIssues.length === 0 ? <EmptyState text="لا توجد دفعات تحتاج مراجعة." /> : <div className="space-y-2">{paymentIssues.map((item) => <Link key={stringOf(item.order_id)} href={`/dashboard/orders/${stringOf(item.order_id, "")}`} className="block rounded-xl bg-gray-50 p-3 hover:bg-gray-100"><p className="text-sm font-bold text-gray-900">#{shortId(item.order_id)} • {stringOf(item.payment_method)}</p><p className="mt-1 text-xs text-red-600">{stringOf(item.reason)}</p></Link>)}</div>}
        </OpsPanel>
      </section>

      <section className="grid gap-4 xl:grid-cols-2">
        <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2"><div><h2 className="text-lg font-bold text-gray-900">أكثر المنتجات مبيعًا اليوم</h2><p className="text-xs text-gray-500">حسب الطلبات المسلمة.</p></div><button type="button" disabled={working !== null} onClick={() => void runCheck("product_report", "تم إنشاء تقرير المنتجات.")} className="rounded-lg border border-gray-200 px-3 py-2 text-xs font-bold text-gray-700">تقرير المنتجات</button></div>
          {topProducts.length === 0 ? <EmptyState text="لا توجد مبيعات مسلمة اليوم بعد." /> : <div className="space-y-2">{topProducts.slice(0, 10).map((item, index) => <div key={`${stringOf(item.product_id)}-${index}`} className="flex items-center justify-between rounded-xl bg-gray-50 p-3"><div><p className="text-sm font-semibold text-gray-900">{index + 1}. {stringOf(item.product_name)}</p><p className="text-xs text-gray-500">{numberOf(item.quantity_sold)} قطعة</p></div><span className="text-sm font-bold text-gray-900">{formatMoney(item.revenue)}</span></div>)}</div>}
        </div>

        <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
          <div className="mb-4 flex flex-wrap items-center justify-between gap-2"><div><h2 className="text-lg font-bold text-gray-900">التقارير المحفوظة</h2><p className="text-xs text-gray-500">يومي، منتجات، وأسبوعي.</p></div><div className="flex gap-2"><button type="button" disabled={working !== null} onClick={() => void runCheck("daily_report", "تم إنشاء تقرير اليوم.")} className="rounded-lg border border-gray-200 px-3 py-2 text-xs font-bold">يومي</button><button type="button" disabled={working !== null} onClick={() => void runCheck("weekly_report", "تم إنشاء التقرير الأسبوعي.")} className="rounded-lg border border-gray-200 px-3 py-2 text-xs font-bold">أسبوعي</button></div></div>
          {reports.length === 0 ? <EmptyState text="لا توجد تقارير محفوظة بعد." /> : <div className="space-y-2">{reports.slice(0, 10).map((report) => <div key={stringOf(report.id)} className="rounded-xl border border-gray-100 p-3"><div className="flex items-center justify-between gap-3"><p className="text-sm font-bold text-gray-900">{reportLabel(stringOf(report.report_type))}</p><span className="text-xs text-gray-500">{formatDate(report.created_at)}</span></div><p className="mt-1 text-xs text-gray-500">{formatDate(report.period_start)} ← {formatDate(report.period_end)}</p></div>)}</div>}
        </div>
      </section>

      <section className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
        <div className="mb-4"><h2 className="text-lg font-bold text-gray-900">إعدادات المراقبة</h2><p className="text-xs text-gray-500">تعمل تلقائيًا من Supabase Cron ولا تحتاج n8n أو جهازًا مفتوحًا.</p></div>
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <NumberField label="حد المخزون" value={config.low_stock_threshold} onChange={(value) => setConfig((current) => ({ ...current, low_stock_threshold: value }))} />
          <NumberField label="Pending بعد (دقيقة)" value={config.order_pending_alert_minutes} onChange={(value) => setConfig((current) => ({ ...current, order_pending_alert_minutes: value }))} />
          <NumberField label="Preparing بعد (دقيقة)" value={config.order_preparing_alert_minutes} onChange={(value) => setConfig((current) => ({ ...current, order_preparing_alert_minutes: value }))} />
          <NumberField label="GPS متوقف بعد (ثانية)" value={config.delivery_gps_stale_seconds} onChange={(value) => setConfig((current) => ({ ...current, delivery_gps_stale_seconds: value }))} />
          <NumberField label="مهلة تأخير التوصيل (دقيقة)" value={config.delivery_late_grace_minutes} onChange={(value) => setConfig((current) => ({ ...current, delivery_late_grace_minutes: value }))} />
          <NumberField label="Payment Pending بعد (دقيقة)" value={config.payment_pending_alert_minutes} onChange={(value) => setConfig((current) => ({ ...current, payment_pending_alert_minutes: value }))} />
          <NumberField label="مدة تحليل المنتجات (يوم)" value={config.product_report_days} onChange={(value) => setConfig((current) => ({ ...current, product_report_days: value }))} />
        </div>
        <button type="button" disabled={working !== null} onClick={() => void saveConfig()} className="mt-4 rounded-xl bg-red-600 px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50">{working === "config" ? "جاري الحفظ..." : "حفظ إعدادات المراقبة"}</button>
      </section>
    </div>
  );
}

function MetricCard({ label, value, danger = false }: { label: string; value: string | number; danger?: boolean }) {
  return <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"><p className="text-xs font-medium text-gray-500">{label}</p><p className={`mt-2 text-2xl font-bold ${danger ? "text-red-600" : "text-gray-900"}`}>{value}</p></div>;
}

function EmptyState({ text }: { text: string }) {
  return <div className="rounded-xl border border-dashed border-gray-200 p-5 text-center text-sm text-gray-500">{text}</div>;
}

function OpsPanel({ title, count, onRun, running, children }: { title: string; count: number; onRun: () => void; running: boolean; children: ReactNode }) {
  return <div className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm"><div className="mb-4 flex items-center justify-between gap-3"><div className="flex items-center gap-2"><h2 className="text-lg font-bold text-gray-900">{title}</h2><span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-bold text-gray-600">{count}</span></div><button type="button" disabled={running} onClick={onRun} className="rounded-lg border border-gray-200 px-3 py-1.5 text-xs font-bold text-gray-600 disabled:opacity-50">{running ? "..." : "فحص"}</button></div>{children}</div>;
}

function NumberField({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return <label className="block"><span className="mb-1.5 block text-xs font-bold text-gray-600">{label}</span><input type="number" min={0} value={value} onChange={(event) => onChange(numberOf(event.target.value))} className="w-full rounded-xl border border-gray-200 px-3 py-2.5 text-sm outline-none focus:border-gray-400" /></label>;
}

function reportLabel(type: string): string {
  if (type === "daily_sales") return "تقرير المبيعات اليومي";
  if (type === "product_intelligence") return "تحليل المنتجات";
  if (type === "weekly_management") return "تقرير الإدارة الأسبوعي";
  return type;
}
