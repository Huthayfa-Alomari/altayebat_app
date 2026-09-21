"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Category = {
  id: string;
  name: string;
  sort_order: number;
  image_url: string | null;
};

const CATEGORY_MEDIA_BUCKET = "product-images";
const MAX_CATEGORY_MEDIA_BYTES = 6 * 1024 * 1024;
const ALLOWED_CATEGORY_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);

function extensionForMime(type: string) {
  if (type === "image/jpeg") return "jpg";
  if (type === "image/png") return "png";
  if (type === "image/webp") return "webp";
  if (type === "image/gif") return "gif";
  return null;
}

function storagePathFromPublicUrl(url: string | null) {
  if (!url) return null;
  const marker = `/storage/v1/object/public/${CATEGORY_MEDIA_BUCKET}/`;
  const markerIndex = url.indexOf(marker);
  if (markerIndex < 0) return null;

  const encodedPath = url.slice(markerIndex + marker.length).split("?")[0];
  try {
    return decodeURIComponent(encodedPath);
  } catch {
    return encodedPath;
  }
}

export default function CategoriesManager({
  initialCategories,
  storeId,
}: {
  initialCategories: Category[];
  storeId: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [name, setName] = useState("");
  const [mediaFile, setMediaFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [busyCategoryId, setBusyCategoryId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  function validateMedia(file: File | null) {
    if (!file) return null;
    if (!ALLOWED_CATEGORY_MEDIA_TYPES.has(file.type)) {
      return "الملف لازم يكون JPG أو PNG أو WebP أو GIF.";
    }
    if (file.size > MAX_CATEGORY_MEDIA_BYTES) {
      return "حجم صورة/GIF التصنيف لازم يكون 6MB أو أقل.";
    }
    return null;
  }

  async function uploadCategoryMedia(file: File, categoryId: string) {
    const extension = extensionForMime(file.type);
    if (!extension) throw new Error("UNSUPPORTED_MEDIA_TYPE");

    const path = `${storeId}/categories/${categoryId}/${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await supabase.storage
      .from(CATEGORY_MEDIA_BUCKET)
      .upload(path, file, {
        cacheControl: "31536000",
        contentType: file.type,
        upsert: false,
      });

    if (uploadError) throw uploadError;

    const { data } = supabase.storage
      .from(CATEGORY_MEDIA_BUCKET)
      .getPublicUrl(path);

    return { path, publicUrl: data.publicUrl };
  }

  async function deleteStoredMedia(url: string | null) {
    const path = storagePathFromPublicUrl(url);
    if (!path) return;
    await supabase.storage.from(CATEGORY_MEDIA_BUCKET).remove([path]);
  }

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    const normalizedName = name.trim();
    if (!normalizedName) return;

    const mediaError = validateMedia(mediaFile);
    if (mediaError) {
      setError(mediaError);
      return;
    }

    setSaving(true);
    setError(null);
    setSuccess(null);

    let createdId: string | null = null;
    let uploadedPath: string | null = null;

    try {
      const { data: created, error: insertError } = await supabase
        .from("categories")
        .insert({
          store_id: storeId,
          name: normalizedName,
          sort_order: initialCategories.length,
        })
        .select("id")
        .single();

      if (insertError || !created?.id) throw insertError ?? new Error("CATEGORY_CREATE_FAILED");
      createdId = created.id as string;

      if (mediaFile) {
        const uploaded = await uploadCategoryMedia(mediaFile, createdId);
        uploadedPath = uploaded.path;

        const { error: mediaUpdateError } = await supabase
          .from("categories")
          .update({ image_url: uploaded.publicUrl })
          .eq("id", createdId)
          .eq("store_id", storeId);

        if (mediaUpdateError) throw mediaUpdateError;
      }

      setName("");
      setMediaFile(null);
      if (fileInputRef.current) fileInputRef.current.value = "";
      setSuccess("تمت إضافة التصنيف وترتيبه للواجهة.");
      router.refresh();
    } catch {
      if (uploadedPath) {
        await supabase.storage.from(CATEGORY_MEDIA_BUCKET).remove([uploadedPath]);
      }
      if (createdId) {
        await supabase
          .from("categories")
          .delete()
          .eq("id", createdId)
          .eq("store_id", storeId);
      }
      setError("تعذر إضافة التصنيف أو رفع صورته. حاول مرة ثانية.");
    } finally {
      setSaving(false);
    }
  }

  async function replaceCategoryMedia(category: Category, file: File) {
    const mediaError = validateMedia(file);
    if (mediaError) {
      setError(mediaError);
      return;
    }

    setBusyCategoryId(category.id);
    setError(null);
    setSuccess(null);

    let uploadedPath: string | null = null;
    try {
      const uploaded = await uploadCategoryMedia(file, category.id);
      uploadedPath = uploaded.path;

      const { error: updateError } = await supabase
        .from("categories")
        .update({ image_url: uploaded.publicUrl })
        .eq("id", category.id)
        .eq("store_id", storeId);

      if (updateError) throw updateError;

      await deleteStoredMedia(category.image_url);
      setSuccess("تم تحديث صورة/GIF التصنيف.");
      router.refresh();
    } catch {
      if (uploadedPath) {
        await supabase.storage.from(CATEGORY_MEDIA_BUCKET).remove([uploadedPath]);
      }
      setError("تعذر تحديث صورة/GIF التصنيف.");
    } finally {
      setBusyCategoryId(null);
    }
  }

  async function removeCategoryMedia(category: Category) {
    if (!category.image_url) return;
    setBusyCategoryId(category.id);
    setError(null);
    setSuccess(null);

    try {
      const { error: updateError } = await supabase
        .from("categories")
        .update({ image_url: null })
        .eq("id", category.id)
        .eq("store_id", storeId);

      if (updateError) throw updateError;
      await deleteStoredMedia(category.image_url);
      setSuccess("تم حذف صورة التصنيف.");
      router.refresh();
    } catch {
      setError("تعذر حذف صورة التصنيف.");
    } finally {
      setBusyCategoryId(null);
    }
  }

  async function moveCategory(category: Category, direction: -1 | 1) {
    const ordered = [...initialCategories].sort(
      (a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "ar"),
    );
    const index = ordered.findIndex((item) => item.id === category.id);
    const swapIndex = index + direction;
    if (index < 0 || swapIndex < 0 || swapIndex >= ordered.length) return;

    const other = ordered[swapIndex];
    setBusyCategoryId(category.id);
    setError(null);
    setSuccess(null);

    const currentOrder = category.sort_order;
    const otherOrder = other.sort_order;

    const { error: firstError } = await supabase
      .from("categories")
      .update({ sort_order: otherOrder })
      .eq("id", category.id)
      .eq("store_id", storeId);

    if (firstError) {
      setBusyCategoryId(null);
      setError("تعذر تغيير ترتيب التصنيفات.");
      return;
    }

    const { error: secondError } = await supabase
      .from("categories")
      .update({ sort_order: currentOrder })
      .eq("id", other.id)
      .eq("store_id", storeId);

    if (secondError) {
      await supabase
        .from("categories")
        .update({ sort_order: currentOrder })
        .eq("id", category.id)
        .eq("store_id", storeId);
      setBusyCategoryId(null);
      setError("تعذر تغيير ترتيب التصنيفات.");
      return;
    }

    setBusyCategoryId(null);
    setSuccess("تم تحديث ترتيب التصنيفات.");
    router.refresh();
  }

  async function deleteCategory(category: Category) {
    if (!window.confirm("متأكد إنك بدك تحذف التصنيف؟")) return;

    setBusyCategoryId(category.id);
    setError(null);
    setSuccess(null);

    const { error: deleteError } = await supabase
      .from("categories")
      .delete()
      .eq("id", category.id)
      .eq("store_id", storeId);

    if (deleteError) {
      setBusyCategoryId(null);
      setError("تعذر حذف التصنيف. تأكد أنه غير مستخدم بمنتجات وحاول مرة ثانية.");
      return;
    }

    await deleteStoredMedia(category.image_url);
    setBusyCategoryId(null);
    setSuccess("تم حذف التصنيف.");
    router.refresh();
  }

  const orderedCategories = [...initialCategories].sort(
    (a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "ar"),
  );

  return (
    <div className="space-y-6">
      <form
        onSubmit={handleAdd}
        className="grid gap-4 rounded-2xl border border-gray-200 bg-white p-4 lg:grid-cols-[1fr_1fr_auto]"
      >
        <div>
          <label className="mb-1.5 block text-xs font-medium text-gray-600">
            اسم التصنيف
          </label>
          <input
            placeholder="مثال: خضار وفواكه"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={80}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5 text-sm outline-none focus:border-brand"
          />
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-medium text-gray-600">
            صورة أو GIF للتصنيف
          </label>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/jpeg,image/png,image/webp,image/gif"
            onChange={(e) => setMediaFile(e.target.files?.[0] ?? null)}
            className="block w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs file:ml-3 file:rounded-lg file:border-0 file:bg-sky-50 file:px-3 file:py-1.5 file:text-xs file:font-medium file:text-sky-700"
          />
          <p className="mt-1 text-[11px] text-gray-400">
            يدعم GIF المتحرك وWebP حتى 6MB. يظهر مباشرة داخل بطاقات التطبيق.
          </p>
        </div>

        <button
          type="submit"
          disabled={saving || !name.trim()}
          className="self-end rounded-xl bg-brand px-5 py-2.5 text-sm font-medium text-white hover:bg-brand-dark disabled:cursor-not-allowed disabled:opacity-60"
        >
          {saving ? "جاري الحفظ..." : "إضافة التصنيف"}
        </button>
      </form>

      {error && (
        <p className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">
          {error}
        </p>
      )}
      {success && (
        <p className="rounded-xl bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
          {success}
        </p>
      )}

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {orderedCategories.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-gray-300 p-6 text-center text-sm text-gray-500 md:col-span-2 xl:col-span-3">
            ما في تصنيفات لسه.
          </p>
        ) : (
          orderedCategories.map((cat, index) => {
            const busy = busyCategoryId === cat.id;
            return (
              <div
                key={cat.id}
                className="overflow-hidden rounded-2xl border border-gray-200 bg-white"
              >
                <div className="flex min-h-36 items-center gap-4 p-4">
                  <div className="flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-gradient-to-br from-red-50 to-sky-50">
                    {cat.image_url ? (
                      <img
                        src={cat.image_url}
                        alt=""
                        className="h-full w-full object-contain p-2"
                      />
                    ) : (
                      <span className="text-3xl" aria-hidden="true">
                        🛍️
                      </span>
                    )}
                  </div>

                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-gray-900">
                      {cat.name}
                    </p>
                    <p className="mt-1 text-xs text-gray-400">
                      ترتيب الواجهة: {index + 1}
                    </p>

                    <label className="mt-3 inline-flex cursor-pointer items-center rounded-lg border border-sky-200 bg-sky-50 px-3 py-1.5 text-xs font-medium text-sky-700 hover:bg-sky-100">
                      {busy ? "جاري..." : cat.image_url ? "تغيير الصورة/GIF" : "إضافة صورة/GIF"}
                      <input
                        type="file"
                        accept="image/jpeg,image/png,image/webp,image/gif"
                        className="hidden"
                        disabled={busy}
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          if (file) void replaceCategoryMedia(cat, file);
                          e.currentTarget.value = "";
                        }}
                      />
                    </label>
                  </div>
                </div>

                <div className="flex items-center justify-between border-t border-gray-100 bg-gray-50/70 px-3 py-2">
                  <div className="flex gap-1">
                    <button
                      type="button"
                      disabled={busy || index === 0}
                      onClick={() => void moveCategory(cat, -1)}
                      className="rounded-lg border border-gray-200 bg-white px-2.5 py-1.5 text-xs text-gray-700 disabled:opacity-35"
                      title="تحريك للأعلى"
                    >
                      ↑
                    </button>
                    <button
                      type="button"
                      disabled={busy || index === orderedCategories.length - 1}
                      onClick={() => void moveCategory(cat, 1)}
                      className="rounded-lg border border-gray-200 bg-white px-2.5 py-1.5 text-xs text-gray-700 disabled:opacity-35"
                      title="تحريك للأسفل"
                    >
                      ↓
                    </button>
                  </div>

                  <div className="flex gap-3">
                    {cat.image_url && (
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => void removeCategoryMedia(cat)}
                        className="text-xs text-gray-500 hover:text-gray-800 disabled:opacity-50"
                      >
                        حذف الصورة
                      </button>
                    )}
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void deleteCategory(cat)}
                      className="text-xs text-red-600 hover:underline disabled:opacity-50"
                    >
                      حذف
                    </button>
                  </div>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
