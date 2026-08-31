import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import SupportRequestsManager from "./SupportRequestsManager";

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
          requests={(requests || []) as Parameters<
            typeof SupportRequestsManager
          >[0]["requests"]}
          storeId={storeId}
        />
      )}
    </div>
  );
}
