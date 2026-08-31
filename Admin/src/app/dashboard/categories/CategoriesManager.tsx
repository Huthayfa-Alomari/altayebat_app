"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Category = { id: string; name: string; sort_order: number };

export default function CategoriesManager({
  initialCategories,
  storeId,
}: {
  initialCategories: Category[];
  storeId: string;
}) {
  const router = useRouter();
  const supabase = createClient();
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    const normalizedName = name.trim();
    if (!normalizedName) return;

    setSaving(true);
    setError(null);

    const { error } = await supabase.from("categories").insert({
      store_id: storeId,
      name: normalizedName,
      sort_order: initialCategories.length,
    });

    setSaving(false);

    if (error) {
      setError("تعذر إضافة التصنيف. حاول مرة ثانية.");
      return;
    }

    setName("");
    router.refresh();
  }

  async function deleteCategory(id: string) {
    if (!window.confirm("متأكد إنك بدك تحذف التصنيف؟")) return;

    setError(null);
    const { error } = await supabase
      .from("categories")
      .delete()
      .eq("id", id)
      .eq("store_id", storeId);

    if (error) {
      setError("تعذر حذف التصنيف. تأكد أنه غير مستخدم بمنتجات وحاول مرة ثانية.");
      return;
    }

    router.refresh();
  }

  return (
    <div className="space-y-6">
      <form
        onSubmit={handleAdd}
        className="flex flex-col gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:flex-row"
      >
        <input
          placeholder="اسم التصنيف (مثال: خضار وفواكه)"
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={80}
          className="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand"
        />
        <button
          type="submit"
          disabled={saving || !name.trim()}
          className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:cursor-not-allowed disabled:opacity-60"
        >
          {saving ? "جاري الإضافة..." : "إضافة"}
        </button>
      </form>

      {error && (
        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
          {error}
        </p>
      )}

      <div className="space-y-2">
        {initialCategories.length === 0 ? (
          <p className="rounded-xl border border-dashed border-gray-300 p-6 text-center text-sm text-gray-500">
            ما في تصنيفات لسه.
          </p>
        ) : (
          initialCategories.map((cat) => (
            <div
              key={cat.id}
              className="flex items-center justify-between rounded-xl border border-gray-200 bg-white px-4 py-3"
            >
              <span className="text-sm">{cat.name}</span>
              <button
                type="button"
                onClick={() => deleteCategory(cat.id)}
                className="text-xs text-red-600 hover:underline"
              >
                حذف
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
