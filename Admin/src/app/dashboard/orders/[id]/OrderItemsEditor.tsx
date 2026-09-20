"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Item = {
  id: string;
  quantity: number;
  unit_price: number;
  sale_type_snapshot: string | null;
  inventory_scale_snapshot: number | null;
  products: { name: string | null } | null;
};

type DraftLine = {
  quantity: number;
  markUnavailable: boolean;
};

function quantityLabel(item: Item, quantity: number) {
  const saleType = item.sale_type_snapshot || "piece";
  if (saleType === "piece") return `${quantity} قطعة`;
  const scale = Number(item.inventory_scale_snapshot || 1000);
  if (quantity < scale) return `${quantity} ${saleType === "weight" ? "غ" : "مل"}`;
  const value = quantity / scale;
  return `${value.toLocaleString("ar-JO", { maximumFractionDigits: 3 })} ${saleType === "weight" ? "كغ" : "لتر"}`;
}

function stepFor(item: Item) {
  return item.sale_type_snapshot === "piece" ? 1 : 50;
}

function errorText(cause: unknown) {
  if (cause instanceof Error) return cause.message;
  if (typeof cause === "string") return cause;

  if (cause && typeof cause === "object") {
    const value = cause as Record<string, unknown>;
    const parts = [value.message, value.details, value.hint]
      .filter((part): part is string => typeof part === "string" && part.trim().length > 0);

    if (parts.length) return [...new Set(parts)].join(" — ");

    try {
      return JSON.stringify(cause);
    } catch {
      return "تعذر تحديث الطلب.";
    }
  }

  return "تعذر تحديث الطلب.";
}

export default function OrderItemsEditor({
  orderId,
  items,
  paymentMethod,
  paymentStatus,
}: {
  orderId: string;
  items: Item[];
  paymentMethod: string;
  paymentStatus: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [draft, setDraft] = useState<Record<string, DraftLine>>(() =>
    Object.fromEntries(items.map((item) => [item.id, { quantity: item.quantity, markUnavailable: false }])),
  );
  const [reason, setReason] = useState("تعديل بسبب عدم توفر صنف أو كمية في المول");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [messageTone, setMessageTone] = useState<"success" | "warning">("success");
  const [error, setError] = useState<string | null>(null);

  const changed = items.some((item) => {
    const line = draft[item.id];
    return line && (line.quantity !== item.quantity || line.markUnavailable);
  });

  function setQuantity(item: Item, quantity: number) {
    const normalized = Math.max(0, Math.floor(quantity));
    setDraft((current) => ({
      ...current,
      [item.id]: {
        quantity: normalized,
        markUnavailable: normalized === 0 ? current[item.id]?.markUnavailable ?? false : false,
      },
    }));
  }

  function markUnavailable(item: Item) {
    setDraft((current) => ({
      ...current,
      [item.id]: { quantity: 0, markUnavailable: true },
    }));
  }

  function resetLine(item: Item) {
    setDraft((current) => ({
      ...current,
      [item.id]: { quantity: item.quantity, markUnavailable: false },
    }));
  }

  async function save() {
    if (busy || !changed) return;
    if (!reason.trim()) {
      setError("اكتب سبب التعديل حتى يظهر للزبون ويُحفظ في سجل الطلب.");
      return;
    }

    const lines = items
      .map((item) => ({ item, draft: draft[item.id] }))
      .filter(({ item, draft: line }) => line && (line.quantity !== item.quantity || line.markUnavailable))
      .map(({ item, draft: line }) => ({
        item_id: item.id,
        quantity: line.quantity,
        mark_unavailable: line.markUnavailable,
      }));

    if (!lines.length) return;
    if (items.every((item) => (draft[item.id]?.quantity ?? item.quantity) === 0)) {
      setError("لا يمكن حذف كل الأصناف من هنا. إذا الطلب كامل غير متوفر ألغِ الطلب.");
      return;
    }

    setBusy(true);
    setMessage(null);
    setMessageTone("success");
    setError(null);
    try {
      const { data, error: rpcError } = await supabase.rpc("admin_adjust_order_items", {
        p_order_id: orderId,
        p_reason: reason.trim(),
        p_items: lines,
      });
      if (rpcError) throw rpcError;

      let pushState: "sent" | "no_tokens" | "failed" = "failed";
      try {
        const { data: pushData, error: pushError } = await supabase.functions.invoke(
          "send-customer-push",
          { body: { order_id: orderId } },
        );

        if (!pushError && pushData && typeof pushData === "object") {
          const payload = pushData as {
            sent?: number;
            failed?: number;
            reason?: string;
          };
          if (Number(payload.sent || 0) > 0) {
            pushState = "sent";
          } else if (payload.reason === "no_tokens") {
            pushState = "no_tokens";
          }
        }
      } catch {
        pushState = "failed";
      }

      const result = (data || {}) as { new_total?: number; refund_amount?: number };
      const refund = Number(result.refund_amount || 0);
      const totalText = Number(result.new_total || 0).toFixed(2);

      const deliveryText =
        pushState === "sent"
          ? " وتم إرسال إشعار فوري للزبون."
          : pushState === "no_tokens"
            ? " وتم حفظ إشعار داخل التطبيق، لكن لا يوجد جهاز مسجل حاليًا لاستقبال Push."
            : " وتم حفظ إشعار داخل التطبيق، لكن تعذر تأكيد إرسال Push الآن.";

      setMessageTone(pushState === "sent" ? "success" : "warning");
      setMessage(
        refund > 0
          ? `تم تحديث الطلب. المجموع الجديد ${totalText} د.أ. يلزم مراجعة رد ${refund.toFixed(2)} د.أ للبطاقة.${deliveryText}`
          : `تم تحديث الطلب. المجموع الجديد ${totalText} د.أ.${deliveryText}`,
      );
      router.refresh();
    } catch (cause) {
      const text = errorText(cause);
      if (text.includes("ORDER_LOCKED_FOR_ADJUSTMENT")) {
        setError("لا يمكن تعديل الطلب بعد خروجه للتوصيل أو بعد التسليم.");
      } else if (text.includes("INSUFFICIENT_STOCK_FOR_ADJUSTMENT")) {
        setError("الكمية الجديدة أكبر من المخزون المتوفر.");
      } else if (text.includes("EMPTY_ORDER_AFTER_ADJUSTMENT")) {
        setError("لا يمكن حذف كل الأصناف؛ ألغِ الطلب بدلًا من ذلك.");
      } else if (text.includes("PAID_ORDER_INCREASE_NOT_ALLOWED")) {
        setError("لا يمكن زيادة قيمة طلب مدفوع. خفّض الكمية فقط أو أنشئ طلبًا إضافيًا.");
      } else if (text.includes("MIN_QTY_FOR_ADJUSTMENT")) {
        setError("الكمية الجديدة أقل من الحد الأدنى المسموح لهذا المنتج.");
      } else if (text.includes("INVALID_QTY_STEP_FOR_ADJUSTMENT")) {
        setError("الكمية الجديدة لا تطابق خطوة البيع المسموحة لهذا المنتج.");
      } else if (text.includes("FORBIDDEN")) {
        setError("ليس لديك صلاحية تعديل هذا الطلب.");
      } else {
        setError(text);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="rounded-2xl border border-sky-200 bg-sky-50/60 p-4">
      <div className="mb-4 flex flex-col justify-between gap-2 sm:flex-row sm:items-center">
        <div>
          <h2 className="font-semibold text-gray-900">تعديل الطلب قبل التجهيز النهائي</h2>
          <p className="mt-1 text-xs text-gray-600">
            عدّل الكمية أو اختر «غير متوفر». التعديل يحدّث الإجمالي والإيصال ويظهر للزبون فورًا.
          </p>
        </div>
        {paymentMethod === "card" && paymentStatus === "paid" ? (
          <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-800">
            بطاقة مدفوعة — أي تخفيض قد يحتاج رد مبلغ
          </span>
        ) : null}
      </div>

      <div className="space-y-3">
        {items.map((item) => {
          const line = draft[item.id] || { quantity: item.quantity, markUnavailable: false };
          const step = stepFor(item);
          const isChanged = line.quantity !== item.quantity || line.markUnavailable;
          return (
            <div key={item.id} className={`rounded-xl border p-3 ${isChanged ? "border-sky-300 bg-white" : "border-gray-200 bg-white"}`}>
              <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-gray-900">{item.products?.name || "منتج"}</p>
                  <p className="mt-1 text-xs text-gray-500">
                    الأصلي: {quantityLabel(item, item.quantity)} — الحالي: {quantityLabel(item, line.quantity)}
                  </p>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setQuantity(item, Math.max(0, line.quantity - step))}
                    className="h-10 w-10 rounded-lg border border-gray-300 bg-white text-lg"
                  >
                    −
                  </button>
                  <input
                    type="number"
                    min={0}
                    step={step}
                    value={line.quantity}
                    onChange={(event) => setQuantity(item, Number(event.target.value || 0))}
                    className="w-24 rounded-lg border border-gray-300 px-2 py-2 text-center"
                    dir="ltr"
                  />
                  <button
                    type="button"
                    onClick={() => setQuantity(item, line.quantity + step)}
                    className="h-10 w-10 rounded-lg border border-gray-300 bg-white text-lg"
                  >
                    +
                  </button>
                  <button
                    type="button"
                    onClick={() => markUnavailable(item)}
                    className={`rounded-lg px-3 py-2 text-xs font-semibold ${line.markUnavailable ? "bg-red-600 text-white" : "border border-red-200 bg-red-50 text-red-700"}`}
                  >
                    غير متوفر
                  </button>
                  {isChanged ? (
                    <button
                      type="button"
                      onClick={() => resetLine(item)}
                      className="rounded-lg px-3 py-2 text-xs text-gray-600 underline"
                    >
                      تراجع
                    </button>
                  ) : null}
                </div>
              </div>
            </div>
          );
        })}
      </div>

      <label className="mt-4 block space-y-1 text-sm font-medium">
        <span>سبب التعديل</span>
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          rows={2}
          className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2"
          placeholder="مثال: المنتج غير متوفر حاليًا"
        />
      </label>

      {error ? <div className="mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</div> : null}
      {message ? (
        <div
          className={`mt-3 rounded-xl p-3 text-sm ${
            messageTone === "success"
              ? "bg-green-50 text-green-700"
              : "bg-amber-50 text-amber-800"
          }`}
        >
          {message}
        </div>
      ) : null}

      <div className="mt-4 flex justify-end">
        <button
          type="button"
          onClick={() => void save()}
          disabled={busy || !changed}
          className="rounded-xl bg-sky-600 px-5 py-2.5 text-sm font-semibold text-white disabled:opacity-40"
        >
          {busy ? "جاري تحديث الطلب..." : "حفظ التعديل وإبلاغ الزبون"}
        </button>
      </div>
    </section>
  );
}
