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
}: {
  initialProducts: Product[];
  categories: Category[];
}) {
  const router = useRouter();
  const supabase = createClient();
  const storeId = process.env.NEXT_PUBLIC_STORE_ID!;

  const [name, setName] = useState("");
  const [price, setPrice] = useState("");
  const [stock, setStock] = useState("");
  const [categoryId, setCategoryId] = useState(categories[0]?.id || "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!name.trim() || !price) {
      setError("لازم تعبي اسم المنتج والسعر");
      return;
    }

    setSaving(true);
    const { error } = await supabase.from("products").insert({
      store_id: storeId,
      category_id: categoryId || null,
      name: name.trim(),
      price: Number(price),
      stock_qty: Number(stock) || 0,
    });
    setSaving(false);

    if (error) {
      setError("صار خطأ، جرب مرة ثانية");
      return;
    }

    setName("");
    setPrice("");
    setStock("");
    router.refresh();
  }

  async function toggleAvailability(product: Product) {
    await supabase
      .from("products")
      .update({ is_available: !product.is_available })
      .eq("id", product.id);
    router.refresh();
  }

  async function deleteProduct(id: string) {
    await supabase.from("products").delete().eq("id", id);
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
          onChange={(e) => setName(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm sm:col-span-2"
        />
        <input
          placeholder="السعر"
          type="number"
          step="0.01"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
        />
        <input
          placeholder="الكمية"
          type="number"
          value={stock}
          onChange={(e) => setStock(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
        />
        <select
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
          className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
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
          className="rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-60 sm:col-span-5"
        >
          {saving ? "جاري الإضافة..." : "إضافة منتج"}
        </button>
        {error && (
          <p className="text-sm text-red-600 sm:col-span-5">{error}</p>
        )}
      </form>

      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white">
        <table className="w-full text-right text-sm">
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
            {initialProducts.map((product) => (
              <tr key={product.id} className="border-t border-gray-100">
                <td className="px-4 py-3">{product.name}</td>
                <td className="px-4 py-3">{product.price} د.أ</td>
                <td className="px-4 py-3">{product.stock_qty}</td>
                <td className="px-4 py-3">
                  <button
                    onClick={() => toggleAvailability(product)}
                    className={`rounded-full px-3 py-1 text-xs ${
                      product.is_available
                        ? "bg-green-100 text-green-700"
                        : "bg-gray-100 text-gray-500"
                    }`}
                  >
                    {product.is_available ? "متوفر" : "غير متوفر"}
                  </button>
                </td>
                <td className="px-4 py-3">
                  <button
                    onClick={() => deleteProduct(product.id)}
                    className="text-xs text-red-600 hover:underline"
                  >
                    حذف
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}