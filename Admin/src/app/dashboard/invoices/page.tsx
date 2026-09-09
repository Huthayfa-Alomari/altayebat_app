"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Row = {
  order_id: string;
  order_status: string;
  total: number | string;
  payment_method: string | null;
  payment_status: string | null;
  created_at: string;
  customer_name: string | null;
  customer_phone: string | null;
  document_number: string | null;
  invoice_status: string | null;
  source: string | null;
  official: boolean | null;
  external_invoice_id: string | null;
  issued_at: string | null;
};

function money(value: number | string | null | undefined) {
  const n = Number(value ?? 0);
  return `${Number.isFinite(n) ? n.toFixed(2) : "0.00"} د.أ`;
}

function shortId(id: string) {
  return id.replaceAll("-", "").slice(0, 8).toUpperCase();
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

function sourceLabel(source?: string | null) {
  if (source === "bonanza") return "Bonanza";
  if (source === "jofotara") return "JoFotara";
  return "إيصال داخلي";
}

function invoiceLabel(row: Row) {
  if (row.official) return "فاتورة رسمية";
  if (row.invoice_status === "final") return "إيصال نهائي";
  if (row.invoice_status === "draft") return "إيصال مسودة";
  return "لم يُنشأ بعد";
}

export default function InvoicesPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      let id = storeId;
      if (!id) {
        const { data: admin, error: adminError } = await supabase
          .from("store_admins")
          .select("store_id")
          .limit(1)
          .maybeSingle();

        if (adminError) throw adminError;
        if (!admin?.store_id) throw new Error("لم يتم العثور على متجر مرتبط بحساب الإدارة.");

        id = admin.store_id as string;
        setStoreId(id);
      }

      const { data, error: rpcError } = await supabase.rpc(
        "admin_list_order_invoice_rows",
        {
          p_store_id: id,
          p_limit: 100,
        },
      );

      if (rpcError) throw rpcError;
      setRows(Array.isArray(data) ? (data as Row[]) : []);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "تعذر تحميل الفواتير.");
    } finally {
      setLoading(false);
    }
  }, [storeId, supabase]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="space-y-6" dir="rtl">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">الفواتير والإيصالات</h1>
          <p className="mt-1 text-sm text-gray-500">
            حاليًا نصدر إيصال طلب إلكتروني غير ضريبي. عند ربط Bonanza نربط الفاتورة الرسمية بنفس الطلب.
          </p>
        </div>

        <button
          type="button"
          onClick={() => void load()}
          className="rounded-xl border border-gray-200 bg-white px-4 py-2.5 text-sm font-semibold text-gray-700"
        >
          تحديث
        </button>
      </div>

      <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
        <strong>مهم:</strong> رقم <span className="font-mono">ALT-RCP-...</span> هو رقم إيصال داخلي للتطبيق،
        وليس رقم فاتورة ضريبية. الفاتورة الرسمية ستأتي من Bonanza / نظام الفوترة بعد تحديد طريقة الربط.
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {error}
        </div>
      )}

      {loading ? (
        <div className="rounded-2xl border border-gray-200 bg-white p-10 text-center text-sm text-gray-500">
          جاري التحميل...
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-gray-200 bg-white p-10 text-center text-sm text-gray-500">
          لا توجد طلبات بعد.
        </div>
      ) : (
        <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-[920px] w-full text-right text-sm">
              <thead className="bg-gray-50 text-xs text-gray-500">
                <tr>
                  <th className="px-4 py-3">الطلب</th>
                  <th className="px-4 py-3">الزبون</th>
                  <th className="px-4 py-3">الإجمالي</th>
                  <th className="px-4 py-3">حالة الطلب</th>
                  <th className="px-4 py-3">المستند</th>
                  <th className="px-4 py-3">المصدر</th>
                  <th className="px-4 py-3">التاريخ</th>
                  <th className="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.order_id} className="border-t border-gray-100">
                    <td className="px-4 py-3 font-bold text-gray-900">
                      #{shortId(row.order_id)}
                    </td>
                    <td className="px-4 py-3">
                      <div className="font-medium text-gray-900">{row.customer_name || "بدون اسم"}</div>
                      <div className="text-xs text-gray-500">{row.customer_phone || "بدون رقم"}</div>
                    </td>
                    <td className="px-4 py-3 font-semibold">{money(row.total)}</td>
                    <td className="px-4 py-3">{row.order_status}</td>
                    <td className="px-4 py-3">
                      <div className={row.official ? "font-bold text-green-700" : "font-semibold text-gray-800"}>
                        {invoiceLabel(row)}
                      </div>
                      <div className="text-[11px] text-gray-500">
                        {row.external_invoice_id || row.document_number || "يُنشأ عند الفتح"}
                      </div>
                    </td>
                    <td className="px-4 py-3">{sourceLabel(row.source)}</td>
                    <td className="px-4 py-3 text-xs text-gray-500">{dateTime(row.created_at)}</td>
                    <td className="px-4 py-3">
                      <Link
                        href={`/dashboard/invoices/${row.order_id}`}
                        className="inline-flex rounded-lg bg-gray-900 px-3 py-2 text-xs font-bold text-white"
                      >
                        عرض الإيصال
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
