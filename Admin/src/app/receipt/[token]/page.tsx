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
  document_number: string;
  source: string;
  status: string;
  official: boolean;
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

function maskPhone(raw?: string | null) {
  if (!raw) return "—";
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 4) return "••••";
  return `••••••${digits.slice(-4)}`;
}

export default function SharedReceiptPage() {
  const params = useParams<{ token: string }>();
  const token = params.token;
  const supabase = useMemo(() => createClient(), []);

  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    async function load() {
      try {
        const { data, error: rpcError } = await supabase.rpc("get_shared_order_invoice", {
          p_token: token,
        });
        if (rpcError) throw rpcError;
        if (active) setInvoice(data as Invoice);
      } catch {
        if (active) setError("الرابط غير صالح أو انتهت صلاحيته.");
      }
    }
    void load();
    return () => {
      active = false;
    };
  }, [supabase, token]);

  if (error) {
    return (
      <main className="mx-auto flex min-h-screen max-w-xl items-center px-5" dir="rtl">
        <div className="w-full rounded-2xl border border-red-200 bg-red-50 p-6 text-center text-red-700">
          {error}
        </div>
      </main>
    );
  }

  if (!invoice) {
    return (
      <main className="flex min-h-screen items-center justify-center" dir="rtl">
        <p className="text-sm text-gray-500">جاري تحميل الإيصال...</p>
      </main>
    );
  }

  const addressText =
    (invoice.address?.address_text as string | undefined) ||
    [invoice.address?.city, invoice.address?.area, invoice.address?.street].filter(Boolean).join("، ") ||
    "—";

  return (
    <main className="min-h-screen bg-gray-50 px-4 py-8 print:bg-white print:p-0" dir="rtl">
      <div className="mx-auto max-w-3xl">
        <div className="mb-4 flex justify-end print:hidden">
          <button
            type="button"
            onClick={() => window.print()}
            className="rounded-xl bg-gray-900 px-4 py-2.5 text-sm font-bold text-white"
          >
            طباعة / حفظ PDF
          </button>
        </div>

        <article className="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm print:border-0 print:shadow-none">
          <div className="flex flex-col gap-4 border-b border-gray-200 pb-5 sm:flex-row sm:justify-between">
            <div>
              <h1 className="text-xl font-black">{invoice.store_name || "أسواق الطيبات"}</h1>
              <p className="mt-1 text-sm text-gray-500">{invoice.store_address || "الأردن"}</p>
            </div>
            <div className="sm:text-left">
              <p className="text-sm font-bold text-gray-500">
                {invoice.official ? "فاتورة رسمية مرتبطة" : "إيصال طلب إلكتروني"}
              </p>
              <p className="font-mono text-lg font-black">
                {invoice.external_invoice_id || invoice.document_number}
              </p>
              <p className="text-xs text-gray-500">
                {invoice.issued_at ? dateTime(invoice.issued_at) : "مسودة قبل التسليم"}
              </p>
            </div>
          </div>

          {!invoice.official && (
            <div className="my-5 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
              هذا إيصال طلب إلكتروني غير ضريبي. الفاتورة الرسمية تعتمد نظام المول.
            </div>
          )}

          <div className="grid gap-4 border-b border-gray-100 py-5 sm:grid-cols-2">
            <div>
              <p className="text-xs font-bold text-gray-500">الزبون</p>
              <p className="mt-1 font-semibold">{invoice.customer_name || "—"}</p>
              <p className="text-sm text-gray-500">{maskPhone(invoice.customer_phone)}</p>
            </div>
            <div>
              <p className="text-xs font-bold text-gray-500">التوصيل إلى</p>
              <p className="mt-1 text-sm leading-6">{addressText}</p>
            </div>
          </div>

          <div className="overflow-x-auto py-5">
            <table className="w-full min-w-[560px] text-right text-sm">
              <thead className="bg-gray-50 text-xs text-gray-500">
                <tr>
                  <th className="px-3 py-2.5">الصنف</th>
                  <th className="px-3 py-2.5">الكمية</th>
                  <th className="px-3 py-2.5">السعر</th>
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

          <div className="mr-auto max-w-sm space-y-2 border-t border-gray-200 pt-4 text-sm">
            <Line label="المجموع الفرعي" value={money(invoice.subtotal)} />
            <Line label="التوصيل" value={money(invoice.delivery_fee)} />
            {num(invoice.discount) > 0 && <Line label="الخصم" value={`- ${money(invoice.discount)}`} />}
            {invoice.tax !== null && <Line label="الضريبة" value={money(invoice.tax)} />}
            <div className="flex justify-between border-t border-gray-200 pt-3 text-lg font-black">
              <span>الإجمالي</span>
              <span>{money(invoice.total)}</span>
            </div>
          </div>

          {invoice.official && invoice.external_invoice_url && (
            <a
              href={invoice.external_invoice_url}
              target="_blank"
              rel="noreferrer"
              className="mt-5 inline-flex rounded-xl bg-red-600 px-4 py-2.5 text-sm font-bold text-white print:hidden"
            >
              فتح الفاتورة الرسمية
            </a>
          )}
        </article>
      </div>
    </main>
  );
}

function Line({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between">
      <span className="text-gray-500">{label}</span>
      <span className="font-semibold">{value}</span>
    </div>
  );
}
