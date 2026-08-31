import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import OrderStatusSelect from "./orders/OrderStatusSelect";

const statusLabels: Record<string, string> = {
  pending: "بانتظار التأكيد",
  preparing: "قيد التحضير",
  out_for_delivery: "بالتوصيل",
  delivered: "تم التسليم",
  cancelled: "ملغي",
};

export default async function OrdersPage() {
  const supabase = createClient();
  const { storeId } = await requireAdminStore();

  const { data: orders, error } = await supabase
    .from("orders")
    .select("id, status, total, created_at, customers(name, phone)")
    .eq("store_id", storeId)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    return (
      <div>
        <h1 className="mb-4 text-lg font-medium">الطلبات</h1>
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          تعذر تحميل الطلبات حاليًا. حاول تحديث الصفحة.
        </div>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-4 flex items-center justify-between gap-3">
        <h1 className="text-lg font-medium">الطلبات</h1>
        <span className="rounded-full bg-gray-100 px-3 py-1 text-xs text-gray-600">
          آخر 50 طلب
        </span>
      </div>

      {!orders || orders.length === 0 ? (
        <p className="rounded-xl border border-dashed border-gray-300 p-8 text-center text-sm text-gray-500">
          ما في طلبات لسه
        </p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
          <table className="min-w-[720px] w-full text-right text-sm">
            <thead className="bg-gray-50 text-gray-500">
              <tr>
                <th className="px-4 py-3 font-normal">الزبون</th>
                <th className="px-4 py-3 font-normal">المجموع</th>
                <th className="px-4 py-3 font-normal">الحالة</th>
                <th className="px-4 py-3 font-normal">التاريخ</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => {
                const customer = order.customers as unknown as {
                  name: string | null;
                  phone: string | null;
                } | null;
                return (
                  <tr key={order.id} className="border-t border-gray-100">
                    <td className="px-4 py-3">
                      <div className="font-medium text-gray-900">
                        {customer?.name || "زبون"}
                      </div>
                      {customer?.phone && (
                        <div className="mt-0.5 text-xs text-gray-500" dir="ltr">
                          {customer.phone}
                        </div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {Number(order.total).toFixed(2)} د.أ
                    </td>
                    <td className="px-4 py-3">
                      <OrderStatusSelect
                        orderId={order.id}
                        storeId={storeId}
                        currentStatus={order.status}
                        labels={statusLabels}
                      />
                    </td>
                    <td className="px-4 py-3 text-gray-500">
                      {new Date(order.created_at).toLocaleString("ar-JO")}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
