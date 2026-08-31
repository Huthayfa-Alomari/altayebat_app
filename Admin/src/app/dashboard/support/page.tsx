import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import SupportRequestsManager from "./SupportRequestsManager";

type SupportRequest = {
  id: string;
  type: string;
  status: string;
  order_id: string | null;
  created_at: string;
  customers: { name: string | null; phone: string | null } | null;
};

export default async function SupportPage() {
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  const { data: requests, error } = await supabase
    .from("call_requests")
    .select(
      "id, type, status, order_id, created_at, customers(name, phone)"
    )
    .eq("store_id", storeId)
    .order("created_at", { ascending: false })
    .limit(100);

  const normalizedRequests: SupportRequest[] = (requests || []).map(
    (request) => {
      const relation = request.customers;
      const customer = Array.isArray(relation) ? relation[0] ?? null : relation;

      return {
        id: String(request.id),
        type: String(request.type),
        status: String(request.status),
        order_id: request.order_id ? String(request.order_id) : null,
        created_at: String(request.created_at),
        customers: customer
          ? {
              name: customer.name ?? null,
              phone: customer.phone ?? null,
            }
          : null,
      };
    }
  );

  return (
    <div>
      <div className="mb-4 flex items-center justify-between gap-3">
        <div>
          <h1 className="text-lg font-medium">طلبات التواصل</h1>
          <p className="mt-1 text-sm text-gray-500">
            مكالمات الصوت والفيديو والشات التي يطلبها الزبائن.
          </p>
        </div>
      </div>

      {error ? (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          تعذر تحميل طلبات التواصل. حاول تحديث الصفحة.
        </div>
      ) : (
        <SupportRequestsManager
          requests={normalizedRequests}
          storeId={storeId}
        />
      )}
    </div>
  );
}
