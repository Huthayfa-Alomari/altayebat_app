"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const statusLabels: Record<string, string> = {
  unpaid: "غير مدفوع",
  pending: "بانتظار التحقق",
  paid: "مدفوع",
  failed: "فشل الدفع",
};

const allowedStatusesByMethod: Record<string, string[]> = {
  cash: ["unpaid", "paid"],
  cliq: ["pending", "paid", "failed"],
};

export default function PaymentStatusControl({
  orderId,
  storeId,
  orderStatus,
  paymentMethod,
  currentStatus,
}: {
  orderId: string;
  storeId: string;
  orderStatus: string;
  paymentMethod: string;
  currentStatus: string;
}) {
  const router = useRouter();
  const supabase = createClient();
  const [value, setValue] = useState(currentStatus);
  const [saving, setSaving] = useState(false);
  const [checking, setChecking] = useState(false);

  async function reconcileCardPayment() {
    if (checking) return;
    setChecking(true);
    const { data, error } = await supabase.functions.invoke(
      "reconcile-card-payment",
      { body: { order_id: orderId } }
    );
    setChecking(false);

    if (error) {
      window.alert("تعذر التحقق من PayTabs الآن. حاول مرة ثانية.");
      return;
    }

    if (data?.finalization === "paid_requires_refund") {
      window.alert(
        "تم العثور على دفعة ناجحة لطلب ملغي. يجب مراجعة العملية وإجراء الاسترداد من PayTabs."
      );
    }
    router.refresh();
  }

  if (paymentMethod === "card") {
    const needsRefund = currentStatus === "paid" && orderStatus === "cancelled";
    return (
      <div className="space-y-2">
        <div
          className={`inline-flex rounded-lg border px-3 py-2 text-sm font-medium ${
            needsRefund
              ? "border-red-200 bg-red-50 text-red-700"
              : "border-gray-200 bg-gray-50 text-gray-700"
          }`}
        >
          {statusLabels[currentStatus] || currentStatus}
        </div>
        <p className={`text-xs ${needsRefund ? "text-red-700" : "text-gray-500"}`}>
          {needsRefund
            ? "الطلب ملغي لكن PayTabs أكد الدفع. يلزم مراجعة واسترداد المبلغ."
            : "حالة الدفع بالبطاقة تُدار تلقائيًا من PayTabs ولا يمكن تعديلها يدويًا."}
        </p>
        {currentStatus !== "paid" && (
          <button
            type="button"
            disabled={checking}
            onClick={reconcileCardPayment}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium hover:bg-gray-50 disabled:opacity-60"
          >
            {checking ? "جاري التحقق..." : "تحقق من PayTabs"}
          </button>
        )}
      </div>
    );
  }

  const allowedStatuses = allowedStatusesByMethod[paymentMethod] || [currentStatus];
  const options = allowedStatuses.includes(value)
    ? allowedStatuses
    : [value, ...allowedStatuses];

  async function save(next: string) {
    if (!allowedStatuses.includes(next) || next === value) return;
    const previous = value;
    setValue(next);
    setSaving(true);

    const { error } = await supabase
      .from("orders")
      .update({ payment_status: next, updated_at: new Date().toISOString() })
      .eq("id", orderId)
      .eq("store_id", storeId);

    setSaving(false);
    if (error) {
      setValue(previous);
      window.alert("تعذر تحديث حالة الدفع.");
      return;
    }
    router.refresh();
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <select
        value={value}
        disabled={saving}
        onChange={(e) => save(e.target.value)}
        className="rounded-lg border border-gray-300 px-3 py-2 text-sm disabled:opacity-60"
        aria-label="حالة الدفع"
      >
        {options.map((key) => (
          <option key={key} value={key}>
            {statusLabels[key] || key}
          </option>
        ))}
      </select>
      {allowedStatuses.includes("paid") && value !== "paid" && (
        <button
          type="button"
          disabled={saving}
          onClick={() => save("paid")}
          className="rounded-lg bg-green-600 px-3 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-60"
        >
          تم الدفع
        </button>
      )}
    </div>
  );
}
