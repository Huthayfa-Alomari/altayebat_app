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
  image_url: string | null;
};

type Category = { id: string; name: string };

const PRODUCT_IMAGES_BUCKET = "product-images";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

function extensionForMime(type: string) {
  if (type === "image/jpeg") return "jpg";
  if (type === "image/png") return "png";
  if (type === "image/webp") return "webp";
  return null;
}

function storagePathFromPublicUrl(url: string | null) {
  if (!url) return null;
  const marker = `/storage/v1/object/public/${PRODUCT_IMAGES_BUCKET}/`;
  const markerIndex = url.indexOf(marker);
  if (markerIndex < 0) return null;

  const encodedPath = url.slice(markerIndex + marker.length).split("?")[0];
  try {
    return decodeURIComponent(encodedPath);
  } catch {
    return encodedPath;
  }
}

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
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [busyProductId, setBusyProductId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function validateImage(file: File | null) {
    if (!file) return null;
    if (!ALLOWED_IMAGE_TYPES.has(file.type)) {
      return "الصورة لازم تكون JPG أو PNG أو WebP";
    }
    if (file.size > MAX_IMAGE_BYTES) {
      return "حجم الصورة لازم يكون 5MB أو أقل";
    }
    return null;
  }

  async function uploadImage(file: File) {
    const extension = extensionForMime(file.type);
    if (!extension) throw new Error("UNSUPPORTED_IMAGE_TYPE");

    const path = `${storeId}/${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await supabase.storage
      .from(PRODUCT_IMAGES_BUCKET)
      .upload(path, file, {
        cacheControl: "31536000",
        contentType: file.type,
        upsert: false,
      });

    if (uploadError) throw uploadError;

    const { data } = supabase.storage.from(PRODUCT_IMAGES_BUCKET).getPublicUrl(path);
    return { path, publicUrl: data.publicUrl };
  }

  async function handleAdd(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    const normalizedName = name.trim();
    const parsedPrice = Number(price);
    const parsedStock = stock.trim() === "" ? 0 : Number(stock);
    const imageValidationError = validateImage(imageFile);

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
    if (imageValidationError) {
      setError(imageValidationError);
      return;
    }

    setSaving(true);
    let uploadedPath: string | null = null;

    try {
      let imageUrl: string | null = null;
      if (imageFile) {
        const uploaded = await uploadImage(imageFile);
        uploadedPath = uploaded.path;
        imageUrl = uploaded.publicUrl;
      }

      const { error: insertError } = await supabase.from("products").insert({
        store_id: storeId,
        category_id: categoryId || null,
        name: normalizedName,
        price: parsedPrice,
        stock_qty: parsedStock,
        is_available: parsedStock > 0,
        image_url: imageUrl,
      });

      if (insertError) {
        if (uploadedPath) {
          await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([uploadedPath]);
        }
        throw insertError;
      }

      setName("");
      setPrice("");
      setStock("");
      setImageFile(null);
      const fileInput = document.getElementById("product-image") as HTMLInputElement | null;
      if (fileInput) fileInput.value = "";
      router.refresh();
    } catch {
      setError("تعذر إضافة المنتج أو رفع الصورة. تأكد من الصورة وحاول مرة ثانية.");
    } finally {
      setSaving(false);
    }
  }

  async function toggleAvailability(product: Product) {
    setBusyProductId(product.id);
    setError(null);

    const { error: updateError } = await supabase
      .from("products")
      .update({ is_available: !product.is_available })
      .eq("id", product.id)
      .eq("store_id", storeId);

    setBusyProductId(null);
    if (updateError) {
      setError("تعذر تحديث حالة المنتج.");
      return;
    }
    router.refresh();
  }

  async function deleteProduct(product: Product) {
    if (!window.confirm("متأكد إنك بدك تحذف المنتج؟")) return;

    setBusyProductId(product.id);
    setError(null);
    const { error: deleteError } = await supabase
      .from("products")
      .delete()
      .eq("id", product.id)
      .eq("store_id", storeId);

    if (deleteError) {
      setBusyProductId(null);
      setError("تعذر حذف المنتج. قد يكون مرتبطًا بطلبات سابقة.");
      return;
    }

    const imagePath = storagePathFromPublicUrl(product.image_url);
    if (imagePath) {
      await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([imagePath]);
    }

    setBusyProductId(null);
    router.refresh();
  }

  return (
    <div className="space-y-6">
      <form
        onSubmit={handleAdd}
        className="grid grid-cols-1 gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-6"
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
        <label className="flex cursor-pointer items-center justify-center rounded-lg border border-dashed border-gray-300 px-3 py-2 text-sm text-gray-600 hover:border-brand hover:text-brand">
          <span className="truncate">{imageFile ? imageFile.name : "اختيار صورة"}</span>
          <input
            id="product-image"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="sr-only"
            onChange={(e) => {
              const file = e.target.files?.[0] ?? null;
              const validationError = validateImage(file);
              if (validationError) {
                setError(validationError);
                e.target.value = "";
                setImageFile(null);
                return;
              }
              setError(null);
              setImageFile(file);
            }}
          />
        </label>
        <button
          type="submit"
          disabled={saving}
          className="rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:cursor-not-allowed disabled:opacity-60 sm:col-span-6"
        >
          {saving ? "جاري رفع الصورة وإضافة المنتج..." : "إضافة منتج"}
        </button>
        <p className="text-xs text-gray-500 sm:col-span-6">
          الصور المدعومة: JPG / PNG / WebP، وبحد أقصى 5MB.
        </p>
        {error && (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 sm:col-span-6">
            {error}
          </p>
        )}
      </form>

      <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
        <table className="min-w-[760px] w-full text-right text-sm">
          <thead className="bg-gray-50 text-gray-500">
            <tr>
              <th className="px-4 py-3 font-normal">الصورة</th>
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
                <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                  ما في منتجات لسه.
                </td>
              </tr>
            ) : (
              initialProducts.map((product) => {
                const busy = busyProductId === product.id;
                return (
                  <tr key={product.id} className="border-t border-gray-100">
                    <td className="px-4 py-3">
                      {product.image_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={product.image_url}
                          alt={product.name}
                          className="h-14 w-14 rounded-lg border border-gray-100 object-cover"
                          loading="lazy"
                        />
                      ) : (
                        <div className="flex h-14 w-14 items-center justify-center rounded-lg bg-gray-100 text-[10px] text-gray-400">
                          بدون صورة
                        </div>
                      )}
                    </td>
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
                        onClick={() => deleteProduct(product)}
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
