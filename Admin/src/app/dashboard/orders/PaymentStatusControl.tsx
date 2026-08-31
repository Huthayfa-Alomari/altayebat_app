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

export default function PaymentStatusControl({
  orderId,
  storeId,
  currentStatus,
}: {
  orderId: string;
  storeId: string;
  currentStatus: string;
}) {
  const router = useRouter();
  const supabase = createClient();
  const [value, setValue] = useState(currentStatus);
  const [saving, setSaving] = useState(false);

  async function save(next: string) {
    if (!(next in statusLabels) || next === value) return;
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
        {Object.entries(statusLabels).map(([key, label]) => (
          <option key={key} value={key}>
            {label}
          </option>
        ))}
      </select>
      {value !== "paid" && (
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
