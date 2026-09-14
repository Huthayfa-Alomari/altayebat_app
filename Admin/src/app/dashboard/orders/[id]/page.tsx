import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import OrderStatusSelect from "../OrderStatusSelect";
import PaymentStatusControl from "../PaymentStatusControl";
import OrderItemsEditor from "./OrderItemsEditor";

const statusLabels: Record<string, string> = {
  pending: "بانتظار التأكيد",
  preparing: "قيد التحضير",
  out_for_delivery: "بالتوصيل",
  delivered: "تم التسليم",
  cancelled: "ملغي",
};

const paymentMethodLabels: Record<string, string> = {
  cash: "كاش عند الاستلام",
  cliq: "CliQ",
  card: "Visa / Mastercard",
};

type OrderItemRow = {
  id: string;
  quantity: number;
  unit_price: number;
  sale_type_snapshot: string | null;
  base_unit_snapshot: string | null;
  inventory_scale_snapshot: number | null;
  display_unit_price_snapshot: number | null;
  products: { name: string | null } | null;
};

function quantityLabel(item: OrderItemRow) {
  const saleType = item.sale_type_snapshot || "piece";
  if (saleType === "piece") return `${item.quantity}`;
  const scale = Number(item.inventory_scale_snapshot || 1000);
  if (item.quantity < scale) return `${item.quantity} ${saleType === "weight" ? "غ" : "مل"}`;
  const value = item.quantity / scale;
  return `${value.toLocaleString("ar-JO", { maximumFractionDigits: 3 })} ${saleType === "weight" ? "كغ" : "لتر"}`;
}

function unitPriceLabel(item: OrderItemRow) {
  const saleType = item.sale_type_snapshot || "piece";
  const price = Number(item.display_unit_price_snapshot ?? item.unit_price);
  const unit = saleType === "weight" ? "كغ" : saleType === "volume" ? "لتر" : "قطعة";
  return `${price.toFixed(3)} د.أ / ${unit}`;
}

export default async function OrderDetailsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  const [{ data: order, error: orderError }, { data: items, error: itemsError }] = await Promise.all([
    supabase
      .from("orders")
      .select("id, status, total, created_at, payment_method, payment_status, payment_reference, customers(name, phone)")
      .eq("id", id)
      .eq("store_id", storeId)
      .maybeSingle(),
    supabase
      .from("order_items")
      .select("id, quantity, unit_price, sale_type_snapshot, base_unit_snapshot, inventory_scale_snapshot, display_unit_price_snapshot, products(name)")
      .eq("order_id", id),
  ]);

  if (orderError || !order) notFound();

  const customer = order.customers as unknown as { name: string | null; phone: string | null } | null;
  const orderItems = (items || []) as unknown as OrderItemRow[];
  const canAdjust = order.status === "pending" || order.status === "preparing";

  return (
    <div className="space-y-6">
      <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
        <div>
          <Link href="/dashboard" className="mb-2 inline-block text-sm text-brand hover:underline">← رجوع للطلبات</Link>
          <h1 className="text-xl font-semibold">طلب #{order.id.slice(0, 8).toUpperCase()}</h1>
          <p className="mt-1 text-sm text-gray-500">{new Date(order.created_at).toLocaleString("ar-JO")}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href={`/dashboard/invoices/${order.id}`}
            className="rounded-xl border border-sky-200 bg-sky-50 px-4 py-2 text-sm font-semibold text-sky-800 hover:bg-sky-100"
          >
            طباعة / الإيصال
          </Link>
          <OrderStatusSelect orderId={order.id} storeId={storeId} currentStatus={order.status} labels={statusLabels} />
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="mb-3 text-sm font-semibold text-gray-900">بيانات الزبون</h2>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4"><dt className="text-gray-500">الاسم</dt><dd>{customer?.name || "غير مسجل"}</dd></div>
            <div className="flex justify-between gap-4"><dt className="text-gray-500">الموبايل</dt><dd dir="ltr">{customer?.phone || "—"}</dd></div>
          </dl>
        </section>

        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="mb-3 text-sm font-semibold text-gray-900">الدفع والطلب</h2>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4"><dt className="text-gray-500">طريقة الدفع</dt><dd className="font-medium">{paymentMethodLabels[order.payment_method] || order.payment_method}</dd></div>
            {order.payment_reference ? <div className="flex justify-between gap-4"><dt className="text-gray-500">مرجع الدفع</dt><dd dir="ltr" className="font-mono text-xs">{order.payment_reference}</dd></div> : null}
            <div className="flex justify-between gap-4"><dt className="text-gray-500">عدد الأصناف</dt><dd>{orderItems.length}</dd></div>
            <div className="flex justify-between gap-4 border-t border-gray-100 pt-2 font-semibold"><dt>المجموع</dt><dd>{Number(order.total).toFixed(2)} د.أ</dd></div>
          </dl>
          <div className="mt-4">
            <PaymentStatusControl orderId={order.id} storeId={storeId} orderStatus={order.status} paymentMethod={order.payment_method} currentStatus={order.payment_status} />
          </div>
        </section>
      </div>

      <section>
        <h2 className="mb-3 text-sm font-semibold text-gray-900">محتويات الطلب</h2>
        {itemsError ? (
          <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">تعذر تحميل محتويات الطلب.</div>
        ) : orderItems.length === 0 ? (
          <div className="rounded-xl border border-dashed border-gray-300 p-6 text-center text-sm text-gray-500">لا توجد عناصر مرتبطة بهذا الطلب.</div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
            <table className="min-w-[620px] w-full text-right text-sm">
              <thead className="bg-gray-50 text-gray-500"><tr><th className="px-4 py-3 font-normal">المنتج</th><th className="px-4 py-3 font-normal">الكمية</th><th className="px-4 py-3 font-normal">سعر الوحدة</th><th className="px-4 py-3 font-normal">الإجمالي</th></tr></thead>
              <tbody className="divide-y divide-gray-100">
                {orderItems.map((item) => (
                  <tr key={item.id}>
                    <td className="px-4 py-3 font-medium text-gray-900">{item.products?.name || "منتج"}</td>
                    <td className="px-4 py-3">{quantityLabel(item)}</td>
                    <td className="px-4 py-3">{unitPriceLabel(item)}</td>
                    <td className="px-4 py-3 font-medium">{(Number(item.unit_price) * item.quantity).toFixed(2)} د.أ</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {canAdjust && orderItems.length > 0 ? (
        <OrderItemsEditor orderId={order.id} items={orderItems} paymentMethod={order.payment_method} paymentStatus={order.payment_status} />
      ) : null}
    </div>
  );
}
