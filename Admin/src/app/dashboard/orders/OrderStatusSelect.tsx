"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

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

  async function handleChange(e: React.ChangeEvent<HTMLSelectElement>) {
    const newStatus = e.target.value;
    if (!(newStatus in labels) || newStatus === value) return;

    const previous = value;
    setValue(newStatus);
    setSaving(true);

    const { error } = await supabase
      .from("orders")
      .update({ status: newStatus, updated_at: new Date().toISOString() })
      .eq("id", orderId)
      .eq("store_id", storeId);

    setSaving(false);

    if (error) {
      setValue(previous);
      window.alert("تعذر تحديث حالة الطلب. حاول مرة ثانية.");
      return;
    }

    router.refresh();
  }

  return (
    <select
      value={value}
      disabled={saving}
      onChange={handleChange}
      aria-label="حالة الطلب"
      className="rounded-lg border border-gray-300 px-2 py-1 text-sm disabled:opacity-60"
    >
      {Object.entries(labels).map(([statusValue, label]) => (
        <option key={statusValue} value={statusValue}>
          {label}
        </option>
      ))}
    </select>
  );
}
