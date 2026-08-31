"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Product = {
  id: string;
  name: string;
  price: number;
  stock_qty: number;
  is_available: boolean;
  category_id: string | null;
};

type Category = { id: string; name: string };

export default function ProductsManager({
  initialProducts,
  categories,
  storeId,
}: {
  initialProducts: Product[];
  categories: Category[];
  storeId: string;
}) {
  const router = useRouter();
  const supabase = createClient();

  const [name, setName] = useState("");
  const [price, setPrice] = useState("");
  const [stock, setStock] = useState("");
  const [categoryId, setCategoryId] = useState(categories[0]?.id || "");
  const [saving, setSaving] = useState(false);
  const [busyProductId, setBusyProductId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const normalizedName = name.trim();
    const parsedPrice = Number(price);
    const parsedStock = stock.trim() === "" ? 0 : Number(stock);

    if (!normalizedName) {
      setError("لازم تعبي اسم المنتج");
      return;
    }
    if (!Number.isFinite(parsedPrice) || parsedPrice <= 0) {
      setError("السعر لازم يكون رقم أكبر من صفر");
      return;
    }
    if (!Number.isInteger(parsedStock) || parsedStock < 0) {
      setError("الكمية لازم تكون رقم صحيح صفر أو أكبر");
      return;
    }

    setSaving(true);
    const { error } = await supabase.from("products").insert({
      store_id: storeId,
      category_id: categoryId || null,
      name: normalizedName,
      price: parsedPrice,
      stock_qty: parsedStock,
      is_available: parsedStock > 0,
    });
    setSaving(false);

    if (error) {
      setError("تعذر إضافة المنتج. حاول مرة ثانية.");
      return;
    }

    setName("");
    setPrice("");
    setStock("");
    router.refresh();
  }

  async function toggleAvailability(product: Product) {
    setBusyProductId(product.id);
    setError(null);

    const { error } = await supabase
      .from("products")
      .update({ is_available: !product.is_available })
      .eq("id", product.id)
      .eq("store_id", storeId);

    setBusyProductId(null);
    if (error) {
      setError("تعذر تحديث حالة المنتج.");
      return;
    }
    router.refresh();
  }

  async function deleteProduct(id: string) {
    if (!window.confirm("متأكد إنك بدك تحذف المنتج؟")) return;

    setBusyProductId(id);
    setError(null);
    const { error } = await supabase
      .from("products")
      .delete()
      .eq("id", id)
      .eq("store_id", storeId);

    setBusyProductId(null);
    if (error) {
      setError("تعذر حذف المنتج. قد يكون مرتبطًا بطلبات سابقة.");
      return;
    }
    router.refresh();
  }

  return (
    <div className="space-y-6">
      <form
        onSubmit={handleAdd}
        className="grid grid-cols-1 gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-5"
      >
        <input
          placeholder="اسم المنتج"
          value={name}
          maxLength={120}
          onChange={(e) => setName(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand sm:col-span-2"
        />
        <input
          placeholder="السعر"
          type="number"
          min="0.01"
          step="0.01"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand"
        />
        <input
          placeholder="الكمية"
          type="number"
          min="0"
          step="1"
          value={stock}
          onChange={(e) => setStock(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand"
        />
        <select
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand"
        >
          <option value="">بدون تصنيف</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
        <button
          type="submit"
          disabled={saving}
          className="rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:cursor-not-allowed disabled:opacity-60 sm:col-span-5"
        >
          {saving ? "جاري الإضافة..." : "إضافة منتج"}
        </button>
        {error && (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 sm:col-span-5">
            {error}
          </p>
        )}
      </form>

      <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
        <table className="min-w-[680px] w-full text-right text-sm">
          <thead className="bg-gray-50 text-gray-500">
            <tr>
              <th className="px-4 py-3 font-normal">الاسم</th>
              <th className="px-4 py-3 font-normal">السعر</th>
              <th className="px-4 py-3 font-normal">الكمية</th>
              <th className="px-4 py-3 font-normal">متوفر</th>
              <th className="px-4 py-3 font-normal"></th>
            </tr>
          </thead>
          <tbody>
            {initialProducts.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-gray-500">
                  ما في منتجات لسه.
                </td>
              </tr>
            ) : (
              initialProducts.map((product) => {
                const busy = busyProductId === product.id;
                return (
                  <tr key={product.id} className="border-t border-gray-100">
                    <td className="px-4 py-3">{product.name}</td>
                    <td className="px-4 py-3">{Number(product.price).toFixed(2)} د.أ</td>
                    <td className="px-4 py-3">{product.stock_qty}</td>
                    <td className="px-4 py-3">
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => toggleAvailability(product)}
                        className={`rounded-full px-3 py-1 text-xs disabled:opacity-50 ${
                          product.is_available
                            ? "bg-green-100 text-green-700"
                            : "bg-gray-100 text-gray-500"
                        }`}
                      >
                        {busy
                          ? "..."
                          : product.is_available
                            ? "متوفر"
                            : "غير متوفر"}
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => deleteProduct(product.id)}
                        className="text-xs text-red-600 hover:underline disabled:opacity-50"
                      >
                        حذف
                      </button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
