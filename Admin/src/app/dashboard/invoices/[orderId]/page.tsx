"use client";

import { useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Item = {
  id?: string;
  product_id?: string;
  name?: string;
  quantity?: number;
  unit_price?: number | string;
  subtotal?: number | string;
};

type Invoice = {
  id: string;
  order_id: string;
  document_number: string;
  document_kind: string;
  source: string;
  status: string;
  official: boolean;
  currency: string;
  issued_at: string | null;
  subtotal: number | string;
  delivery_fee: number | string;
  discount: number | string;
  tax: number | string | null;
  total: number | string;
  payment_method: string | null;
  payment_status: string | null;
  customer_name: string | null;
  customer_phone: string | null;
  store_name: string | null;
  store_phone: string | null;
  store_address: string | null;
  address: Record<string, unknown> | null;
  items: Item[];
  external_invoice_id: string | null;
  external_invoice_url: string | null;
  created_at: string;
  updated_at: string;
};

function num(v: unknown) {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function money(v: unknown) {
  return `${num(v).toFixed(2)} د.أ`;
}

function dateTime(value?: string | null) {
  if (!value) return "—";
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return new Intl.DateTimeFormat("ar-JO", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(d);
}

function paymentMethod(v?: string | null) {
  if (v === "cash") return "كاش عند الاستلام";
  if (v === "cliq") return "CliQ";
  if (v === "card") return "بطاقة";
  return v || "—";
}

function normalizeJordanPhone(raw?: string | null) {
  if (!raw) return "";
  let digits = raw.replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.startsWith("0")) digits = `962${digits.slice(1)}`;
  return digits;
}

export default function InvoiceDetailsPage() {
  const params = useParams<{ orderId: string }>();
  const orderId = params.orderId;
  const supabase = useMemo(() => createClient(), []);

  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [loading, setLoading] = useState(true);
  const [working, setWorking] = useState(false);
  const [shareUrl, setShareUrl] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc("admin_get_order_invoice", {
        p_order_id: orderId,
      });
      if (rpcError) throw rpcError;
      setInvoice(data as Invoice);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "تعذر تحميل الإيصال.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [orderId]);

  async function createShareLink() {
    setWorking(true);
    setMessage(null);
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc("admin_issue_invoice_share", {
        p_order_id: orderId,
        p_hours: 168,
      });
      if (rpcError) throw rpcError;
      const token = String(data || "");
      const url = `${window.location.origin}/receipt/${token}`;
      setShareUrl(url);
      await navigator.clipboard.writeText(url);
      setMessage("تم إنشاء رابط آمن لمدة 7 أيام ونسخه.");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "تعذر إنشاء رابط الإيصال.");
    } finally {
      setWorking(false);
    }
  }

  function sendWhatsApp() {
    if (!invoice || !shareUrl) return;
    const phone = normalizeJordanPhone(invoice.customer_phone);
    if (!phone) {
      setError("رقم الزبون غير مسجل.");
      return;
    }

    const text = [
      `شكرًا لتسوقك من ${invoice.store_name || "أسواق الطيبات"}.`,
      `إيصال طلبك ${invoice.document_number}:`,
      shareUrl,
      "",
      "ملاحظة: هذا إيصال طلب إلكتروني. الفاتورة الرسمية تعتمد نظام المول.",
    ].join("\n");

    window.open(`https://wa.me/${phone}?text=${encodeURIComponent(text)}`, "_blank", "noopener,noreferrer");
  }

  if (loading) {
    return <div className="p-10 text-center text-sm text-gray-500">جاري تحميل الإيصال...</div>;
  }

  if (!invoice) {
    return (
      <div className="space-y-4" dir="rtl">
        {error && <div className="rounded-xl bg-red-50 p-4 text-red-700">{error}</div>}
      </div>
    );
  }

  const addressText =
    (invoice.address?.address_text as string | undefined) ||
    [invoice.address?.city, invoice.address?.area, invoice.address?.street]
      .filter(Boolean)
      .join("، ") ||
    "—";

  return (
    <div className="mx-auto max-w-4xl space-y-4" dir="rtl">
      <div className="print:hidden flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-bold">الإيصال الإلكتروني</h1>
          <p className="text-xs text-gray-500">يمكن طباعته أو إرساله للزبون.</p>
        </div>

        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => window.print()}
            className="rounded-xl border border-gray-200 bg-white px-4 py-2 text-sm font-bold"
          >
            طباعة / حفظ PDF
          </button>

          <button
            type="button"
            disabled={working}
            onClick={() => void createShareLink()}
            className="rounded-xl bg-gray-900 px-4 py-2 text-sm font-bold text-white disabled:opacity-50"
          >
            {working ? "جاري الإنشاء..." : "إنشاء رابط للزبون"}
          </button>

          {shareUrl && (
            <button
              type="button"
              onClick={sendWhatsApp}
              className="rounded-xl bg-green-600 px-4 py-2 text-sm font-bold text-white"
            >
              إرسال واتساب
            </button>
          )}
        </div>
      </div>

      {message && (
        <div className="print:hidden rounded-xl border border-green-200 bg-green-50 p-3 text-sm text-green-700">
          {message}
          {shareUrl && (
            <div className="mt-2 break-all font-mono text-xs text-green-900">{shareUrl}</div>
          )}
        </div>
      )}

      {error && (
        <div className="print:hidden rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      <article className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm print:border-0 print:shadow-none">
        <div className="flex flex-col gap-5 border-b border-gray-200 pb-5 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xl font-black text-gray-900">{invoice.store_name || "أسواق الطيبات"}</p>
            <p className="mt-1 text-sm text-gray-500">{invoice.store_address || "الأردن"}</p>
            {invoice.store_phone && <p className="text-sm text-gray-500">{invoice.store_phone}</p>}
          </div>

          <div className="sm:text-left">
            <p className="text-sm font-bold text-gray-500">
              {invoice.official ? "فاتورة رسمية مرتبطة" : "إيصال طلب إلكتروني"}
            </p>
            <p className="mt-1 font-mono text-lg font-black">{invoice.external_invoice_id || invoice.document_number}</p>
            <p className="text-xs text-gray-500">
              {invoice.issued_at ? dateTime(invoice.issued_at) : "مسودة قبل التسليم"}
            </p>
          </div>
        </div>

        {!invoice.official && (
          <div className="my-5 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
            هذا <strong>إيصال طلب إلكتروني غير ضريبي</strong>. عند ربط Bonanza / نظام الفوترة سيتم ربط الفاتورة الرسمية بنفس الطلب.
          </div>
        )}

        <div className="grid gap-4 border-b border-gray-100 py-5 sm:grid-cols-2">
          <div>
            <p className="text-xs font-bold text-gray-500">الزبون</p>
            <p className="mt-1 font-semibold">{invoice.customer_name || "—"}</p>
            <p className="text-sm text-gray-500">{invoice.customer_phone || "—"}</p>
          </div>
          <div>
            <p className="text-xs font-bold text-gray-500">عنوان التوصيل</p>
            <p className="mt-1 text-sm leading-6">{addressText}</p>
          </div>
        </div>

        <div className="overflow-x-auto py-5">
          <table className="w-full min-w-[620px] text-right text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500">
              <tr>
                <th className="px-3 py-2.5">الصنف</th>
                <th className="px-3 py-2.5">الكمية</th>
                <th className="px-3 py-2.5">سعر الوحدة</th>
                <th className="px-3 py-2.5">المجموع</th>
              </tr>
            </thead>
            <tbody>
              {(invoice.items || []).map((item, idx) => (
                <tr key={item.id || `${item.product_id}-${idx}`} className="border-b border-gray-100">
                  <td className="px-3 py-3 font-medium">{item.name || "منتج"}</td>
                  <td className="px-3 py-3">{item.quantity ?? 0}</td>
                  <td className="px-3 py-3">{money(item.unit_price)}</td>
                  <td className="px-3 py-3 font-semibold">{money(item.subtotal)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="mr-auto w-full max-w-sm space-y-2 border-t border-gray-200 pt-4 text-sm">
          <TotalRow label="المجموع الفرعي" value={money(invoice.subtotal)} />
          <TotalRow label="التوصيل" value={money(invoice.delivery_fee)} />
          {num(invoice.discount) > 0 && <TotalRow label="الخصم" value={`- ${money(invoice.discount)}`} />}
          {invoice.tax !== null && <TotalRow label="الضريبة" value={money(invoice.tax)} />}
          <div className="flex items-center justify-between border-t border-gray-200 pt-3 text-lg font-black">
            <span>الإجمالي</span>
            <span>{money(invoice.total)}</span>
          </div>
        </div>

        <div className="mt-6 grid gap-3 rounded-xl bg-gray-50 p-4 text-sm sm:grid-cols-2">
          <div>
            <span className="text-gray-500">طريقة الدفع: </span>
            <strong>{paymentMethod(invoice.payment_method)}</strong>
          </div>
          <div>
            <span className="text-gray-500">حالة الدفع: </span>
            <strong>{invoice.payment_status || "—"}</strong>
          </div>
        </div>

        {invoice.official && invoice.external_invoice_url && (
          <div className="mt-5 print:hidden">
            <a
              href={invoice.external_invoice_url}
              target="_blank"
              rel="noreferrer"
              className="inline-flex rounded-xl bg-red-600 px-4 py-2.5 text-sm font-bold text-white"
            >
              فتح الفاتورة الرسمية
            </a>
          </div>
        )}
      </article>
    </div>
  );
}

function TotalRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-gray-500">{label}</span>
      <span className="font-semibold">{value}</span>
    </div>
  );
}
