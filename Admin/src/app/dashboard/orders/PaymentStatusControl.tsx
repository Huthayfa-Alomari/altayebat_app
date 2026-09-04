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
  paymentMethod,
  currentStatus,
}: {
  orderId: string;
  storeId: string;
  paymentMethod: string;
  currentStatus: string;
}) {
  const router = useRouter();
  const supabase = createClient();
  const [value, setValue] = useState(currentStatus);
  const [saving, setSaving] = useState(false);

  if (paymentMethod === "card") {
    return (
      <div className="space-y-1">
        <div className="inline-flex rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm font-medium text-gray-700">
          {statusLabels[currentStatus] || currentStatus}
        </div>
        <p className="text-xs text-gray-500">
          حالة الدفع بالبطاقة تُحدّث تلقائيًا بعد التحقق من PayTabs ولا يمكن تعديلها يدويًا.
        </p>
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
