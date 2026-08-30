import { createClient } from "@/lib/supabase/server";
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

  const { data: orders } = await supabase
    .from("orders")
    .select("id, status, total, created_at, customers(name, phone)")
    .order("created_at", { ascending: false })
    .limit(50);

  return (
    <div>
      <h1 className="mb-4 text-lg font-medium">الطلبات</h1>

      {!orders || orders.length === 0 ? (
        <p className="text-sm text-gray-500">ما في طلبات لسه</p>
      ) : (
        <div className="overflow-hidden rounded-xl border border-gray-200 bg-white">
          <table className="w-full text-right text-sm">
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
                      {customer?.name || customer?.phone || "زبون"}
                    </td>
                    <td className="px-4 py-3">{order.total} د.أ</td>
                    <td className="px-4 py-3">
                      <OrderStatusSelect
                        orderId={order.id}
                        currentStatus={order.status}
                        labels={statusLabels}
                      />
                    </td>
                    <td className="px-4 py-3 text-gray-500">
                      {new Date(order.created_at).toLocaleDateString("ar")}
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