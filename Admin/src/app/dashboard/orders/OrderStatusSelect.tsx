"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

const allowedTransitions: Record<string, string[]> = {
  pending: ["preparing", "cancelled"],
  preparing: ["out_for_delivery", "cancelled"],
  out_for_delivery: ["delivered"],
  delivered: [],
  cancelled: [],
};

export default function OrderStatusSelect({
  orderId,
  storeId,
  currentStatus,
  labels,
}: {
  orderId: string;
  storeId: string;
  currentStatus: string;
  labels: Record<string, string>;
}) {
  const router = useRouter();
  const supabase = createClient();
  const [value, setValue] = useState(currentStatus);
  const [saving, setSaving] = useState(false);
  const nextStatuses = allowedTransitions[value] || [];

  async function handleChange(e: React.ChangeEvent<HTMLSelectElement>) {
    const newStatus = e.target.value;
    if (!nextStatuses.includes(newStatus) || newStatus === value) return;

    const previous = value;
    setValue(newStatus);
    setSaving(true);

    const { error } = await supabase.rpc("admin_update_order_status", {
      p_order_id: orderId,
      p_store_id: storeId,
      p_new_status: newStatus,
    });

    setSaving(false);

    if (error) {
      setValue(previous);
      window.alert(
        error.message.includes("refund") || error.message.includes("gateway")
          ? "لا يمكن إلغاء هذا الطلب قبل معالجة حالة الدفع."
          : "تعذر تحديث حالة الطلب. حاول مرة ثانية."
      );
      return;
    }

    router.refresh();
  }

  if (nextStatuses.length === 0) {
    return (
      <span className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm font-medium text-gray-700">
        {labels[value] || value}
      </span>
    );
  }

  return (
    <select
      value={value}
      disabled={saving}
      onChange={handleChange}
      aria-label="حالة الطلب"
      className="rounded-lg border border-gray-300 px-2 py-1 text-sm disabled:opacity-60"
    >
      <option value={value}>{labels[value] || value}</option>
      {nextStatuses.map((statusValue) => (
        <option key={statusValue} value={statusValue}>
          {labels[statusValue] || statusValue}
        </option>
      ))}
    </select>
  );
}
