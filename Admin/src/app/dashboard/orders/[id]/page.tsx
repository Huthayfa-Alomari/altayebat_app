import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import OrderStatusSelect from "../OrderStatusSelect";
import PaymentStatusControl from "../PaymentStatusControl";

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

function jordanWhatsAppNumber(phone: string | null | undefined) {
  if (!phone) return null;
  let digits = phone.replace(/\D/g, "");
  if (digits.startsWith("00962")) digits = digits.slice(2);
  if (digits.startsWith("962")) return digits;
  if (digits.startsWith("0")) digits = digits.slice(1);
  return digits ? `962${digits}` : null;
}

type OrderItemRow = {
  id: string;
  quantity: number;
  unit_price: number;
  products: { name: string | null } | null;
};

export default async function OrderDetailsPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  const [{ data: order, error: orderError }, { data: items, error: itemsError }] =
    await Promise.all([
      supabase
        .from("orders")
        .select(
          "id, status, total, created_at, payment_method, payment_status, payment_reference, customers(name, phone)"
        )
        .eq("id", id)
        .eq("store_id", storeId)
        .maybeSingle(),
      supabase
        .from("order_items")
        .select("id, quantity, unit_price, products(name)")
        .eq("order_id", id),
    ]);

  if (orderError || !order) notFound();

  const customer = order.customers as unknown as {
    name: string | null;
    phone: string | null;
  } | null;
  const orderItems = (items || []) as unknown as OrderItemRow[];
  const whatsapp = jordanWhatsAppNumber(customer?.phone);

  return (
    <div className="space-y-6">
      <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
        <div>
          <Link href="/dashboard" className="mb-2 inline-block text-sm text-brand hover:underline">
            ← رجوع للطلبات
          </Link>
          <h1 className="text-xl font-semibold">
            طلب #{order.id.slice(0, 8).toUpperCase()}
          </h1>
          <p className="mt-1 text-sm text-gray-500">
            {new Date(order.created_at).toLocaleString("ar-JO")}
          </p>
        </div>
        <OrderStatusSelect
          orderId={order.id}
          storeId={storeId}
          currentStatus={order.status}
          labels={statusLabels}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="mb-3 text-sm font-semibold text-gray-900">بيانات الزبون</h2>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-gray-500">الاسم</dt>
              <dd>{customer?.name || "غير مسجل"}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-gray-500">الموبايل</dt>
              <dd dir="ltr">{customer?.phone || "—"}</dd>
            </div>
          </dl>
          {customer?.phone && (
            <div className="mt-4 flex flex-wrap gap-2">
              <a
                href={`tel:${customer.phone}`}
                className="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium hover:bg-gray-50"
              >
                اتصال
              </a>
              {whatsapp && (
                <a
                  href={`https://wa.me/${whatsapp}?text=${encodeURIComponent(
                    `مرحبًا، معك أسواق الطيبات بخصوص طلبك #${order.id.slice(0, 8).toUpperCase()}`
                  )}`}
                  target="_blank"
                  rel="noreferrer"
                  className="rounded-lg bg-green-600 px-3 py-2 text-sm font-medium text-white hover:bg-green-700"
                >
                  واتساب
                </a>
              )}
            </div>
          )}
        </section>

        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="mb-3 text-sm font-semibold text-gray-900">الدفع والطلب</h2>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-gray-500">طريقة الدفع</dt>
              <dd className="font-medium">
                {paymentMethodLabels[order.payment_method] || order.payment_method}
              </dd>
            </div>
            {order.payment_reference && (
              <div className="flex justify-between gap-4">
                <dt className="text-gray-500">مرجع الدفع</dt>
                <dd dir="ltr" className="font-mono text-xs">{order.payment_reference}</dd>
              </div>
            )}
            <div className="flex justify-between gap-4">
              <dt className="text-gray-500">عدد الأصناف</dt>
              <dd>{orderItems.length}</dd>
            </div>
            <div className="flex justify-between gap-4 border-t border-gray-100 pt-2 font-semibold">
              <dt>المجموع</dt>
              <dd>{Number(order.total).toFixed(2)} د.أ</dd>
            </div>
          </dl>
          <div className="mt-4">
            <PaymentStatusControl
              orderId={order.id}
              storeId={storeId}
              paymentMethod={order.payment_method}
              currentStatus={order.payment_status}
            />
          </div>
        </section>
      </div>

      <section>
        <h2 className="mb-3 text-sm font-semibold text-gray-900">محتويات الطلب</h2>
        {itemsError ? (
          <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
            تعذر تحميل محتويات الطلب.
          </div>
        ) : orderItems.length === 0 ? (
          <div className="rounded-xl border border-dashed border-gray-300 p-6 text-center text-sm text-gray-500">
            لا توجد عناصر مرتبطة بهذا الطلب.
          </div>
        ) : (
          <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
            <table className="min-w-[560px] w-full text-right text-sm">
              <thead className="bg-gray-50 text-gray-500">
                <tr>
                  <th className="px-4 py-3 font-normal">المنتج</th>
                  <th className="px-4 py-3 font-normal">الكمية</th>
                  <th className="px-4 py-3 font-normal">سعر الوحدة</th>
                  <th className="px-4 py-3 font-normal">الإجمالي</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {orderItems.map((item) => (
                  <tr key={item.id}>
                    <td className="px-4 py-3 font-medium text-gray-900">
                      {item.products?.name || "منتج"}
                    </td>
                    <td className="px-4 py-3">{item.quantity}</td>
                    <td className="px-4 py-3">{Number(item.unit_price).toFixed(2)} د.أ</td>
                    <td className="px-4 py-3 font-medium">
                      {(Number(item.unit_price) * item.quantity).toFixed(2)} د.أ
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
