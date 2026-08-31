"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type SupportRequest = {
  id: string;
  type: string;
  status: string;
  order_id: string | null;
  created_at: string;
  customers: { name: string | null; phone: string | null } | null;
};

const typeLabels: Record<string, string> = {
  voice: "مكالمة صوتية",
  video: "مكالمة فيديو",
  chat: "شات",
};

function jordanWhatsAppNumber(phone: string | null | undefined) {
  if (!phone) return null;
  let digits = phone.replace(/\D/g, "");
  if (digits.startsWith("00962")) digits = digits.slice(2);
  if (digits.startsWith("962")) return digits;
  if (digits.startsWith("0")) digits = digits.slice(1);
  return digits ? `962${digits}` : null;
}

export default function SupportRequestsManager({
  requests,
  storeId,
}: {
  requests: SupportRequest[];
  storeId: string;
}) {
  const router = useRouter();
  const supabase = createClient();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function markCompleted(id: string) {
    setBusyId(id);
    setError(null);
    const { error } = await supabase
      .from("call_requests")
      .update({ status: "completed" })
      .eq("id", id)
      .eq("store_id", storeId);

    setBusyId(null);
    if (error) {
      setError("تعذر تحديث طلب التواصل.");
      return;
    }
    router.refresh();
  }

  if (requests.length === 0) {
    return (
      <p className="rounded-xl border border-dashed border-gray-300 p-8 text-center text-sm text-gray-500">
        ما في طلبات تواصل حاليًا.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
      )}

      {requests.map((request) => {
        const pending = request.status === "requested";
        const customer = request.customers;
        const whatsapp = jordanWhatsAppNumber(customer?.phone);
        const orderShort = request.order_id?.slice(0, 8).toUpperCase();

        return (
          <div key={request.id} className="rounded-xl border border-gray-200 bg-white p-4">
            <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium text-gray-900">
                    {typeLabels[request.type] || request.type}
                  </span>
                  <span
                    className={`rounded-full px-2.5 py-1 text-xs ${
                      pending
                        ? "bg-amber-100 text-amber-800"
                        : "bg-green-100 text-green-700"
                    }`}
                  >
                    {pending ? "بانتظار الموظف" : "تمت المعالجة"}
                  </span>
                </div>
                <p className="mt-2 text-sm text-gray-700">
                  {customer?.name || "زبون"}
                  {customer?.phone ? ` — ${customer.phone}` : ""}
                </p>
                <p className="mt-1 text-xs text-gray-500">
                  {new Date(request.created_at).toLocaleString("ar-JO")}
                  {orderShort ? ` — طلب #${orderShort}` : ""}
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                {customer?.phone && (
                  <a
                    href={`tel:${customer.phone}`}
                    className="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium hover:bg-gray-50"
                  >
                    اتصال
                  </a>
                )}
                {whatsapp && (
                  <a
                    href={`https://wa.me/${whatsapp}?text=${encodeURIComponent(
                      `مرحبًا، معك أسواق الطيبات${orderShort ? ` بخصوص طلبك #${orderShort}` : ""}`
                    )}`}
                    target="_blank"
                    rel="noreferrer"
                    className="rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700"
                  >
                    واتساب
                  </a>
                )}
                {pending && (
                  <button
                    type="button"
                    disabled={busyId === request.id}
                    onClick={() => markCompleted(request.id)}
                    className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-60"
                  >
                    {busyId === request.id ? "جاري التحديث..." : "تم التواصل"}
                  </button>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
