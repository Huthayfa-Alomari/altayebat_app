"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Category = { id: string; name: string; sort_order: number };

export default function CategoriesManager({
  initialCategories,
}: {
  initialCategories: Category[];
}) {
  const router = useRouter();
  const supabase = createClient();
  const storeId = process.env.NEXT_PUBLIC_STORE_ID!;
  const [name, setName] = useState("");
  const [saving, setSaving] = useState(false);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;

    setSaving(true);
    await supabase.from("categories").insert({
      store_id: storeId,
      name: name.trim(),
      sort_order: initialCategories.length,
    });
    setSaving(false);
    setName("");
    router.refresh();
  }

  async function deleteCategory(id: string) {
    await supabase.from("categories").delete().eq("id", id);
    router.refresh();
  }

  return (
    <div className="space-y-6">
      <form
        onSubmit={handleAdd}
        className="flex gap-3 rounded-xl border border-gray-200 bg-white p-4"
      >
        <input
          placeholder="اسم التصنيف (مثال: خضار وفواكه)"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm"
        />
        <button
          type="submit"
          disabled={saving}
          className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-60"
        >
          إضافة
        </button>
      </form>

      <div className="space-y-2">
        {initialCategories.map((cat) => (
          <div
            key={cat.id}
            className="flex items-center justify-between rounded-xl border border-gray-200 bg-white px-4 py-3"
          >
            <span className="text-sm">{cat.name}</span>
            <button
              onClick={() => deleteCategory(cat.id)}
              className="text-xs text-red-600 hover:underline"
            >
              حذف
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}