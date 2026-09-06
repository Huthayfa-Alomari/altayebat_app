"use client";

import { Fragment, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BarcodeField } from "@/components/products/barcode-field";
import { validateAdminBarcode } from "@/lib/barcode";
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

function barcodeErrorMessage(reason?: string, productName?: string) {
  if (reason === "DUPLICATE") {
    return `هذا الباركود مستخدم${productName ? ` للمنتج: ${productName}` : " لمنتج آخر"}.`;
  }
  if (reason === "BARCODE_TOO_LONG") {
    return "الباركود أطول من الحد المسموح.";
  }
  return "تعذر التحقق من الباركود. حاول مرة ثانية.";
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
  const [barcode, setBarcode] = useState("");
  const [imageFile, setImageFile] = useState<File | null>(null);

  const [saving, setSaving] = useState(false);
  const [busyProductId, setBusyProductId] = useState<string | null>(null);

  const [loadingBarcodeId, setLoadingBarcodeId] = useState<string | null>(null);
  const [editingBarcodeProductId, setEditingBarcodeProductId] = useState<string | null>(null);
  const [editingBarcodeValue, setEditingBarcodeValue] = useState("");
  const [savingBarcode, setSavingBarcode] = useState(false);

  const [error, setError] = useState<string | null>(null);

  const [quickBarcode, setQuickBarcode] = useState("");
  const [quickBarcodeBusy, setQuickBarcodeBusy] = useState(false);
  const [quickBarcodeMessage, setQuickBarcodeMessage] = useState<string | null>(null);
  const [highlightProductId, setHighlightProductId] = useState<string | null>(null);

  const [editingProductId, setEditingProductId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editPrice, setEditPrice] = useState("");
  const [editStock, setEditStock] = useState("");
  const [editCategoryId, setEditCategoryId] = useState("");
  const [editAvailable, setEditAvailable] = useState(true);
  const [editBarcode, setEditBarcode] = useState("");
  const [editImageFile, setEditImageFile] = useState<File | null>(null);
  const [editRemoveImage, setEditRemoveImage] = useState(false);
  const [savingProductEdit, setSavingProductEdit] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);
  const [editSuccess, setEditSuccess] = useState<string | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      document
        .querySelector<HTMLInputElement>("#quick-barcode-form input")
        ?.focus();
    }, 100);

    return () => window.clearTimeout(timer);
  }, []);

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

  async function handleQuickBarcodeSearch(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();

    const normalizedBarcode = quickBarcode.trim();
    if (!normalizedBarcode) {
      setQuickBarcodeMessage("امسح الباركود أو اكتب الرقم أولاً.");
      return;
    }

    setQuickBarcodeBusy(true);
    setQuickBarcodeMessage(null);
    setError(null);

    try {
      const barcodeStatus = await validateAdminBarcode(supabase, {
        storeId,
        barcode: normalizedBarcode,
      });

      const status = barcodeStatus as typeof barcodeStatus & {
        product_id?: string;
        product_name?: string;
      };

      if (!status.valid) {
        setQuickBarcodeMessage(barcodeErrorMessage(status.reason, status.product_name));
        return;
      }

      if (!status.available && status.product_id) {
        const product = initialProducts.find((item) => item.id === status.product_id);

        if (!product) {
          setQuickBarcodeMessage(
            `تم العثور على المنتج${status.product_name ? `: ${status.product_name}` : ""}. حدّث الصفحة إذا لم يظهر في القائمة.`,
          );
          router.refresh();
          return;
        }

        setHighlightProductId(product.id);
        setQuickBarcodeMessage(
          `تم العثور على ${product.name} — السعر ${Number(product.price).toFixed(2)} د.أ — المخزون ${product.stock_qty}.`,
        );
        setQuickBarcode("");

        window.setTimeout(() => {
          document.getElementById(`product-${product.id}`)?.scrollIntoView({
            behavior: "smooth",
            block: "center",
          });
          document
            .querySelector<HTMLInputElement>("#quick-barcode-form input")
            ?.focus();
        }, 50);
        return;
      }

      if (status.available) {
        setBarcode(normalizedBarcode);
        setQuickBarcode("");
        setHighlightProductId(null);
        setQuickBarcodeMessage(
          "هذا الباركود غير مربوط بأي منتج. تم نقله إلى نموذج إضافة منتج جديد.",
        );

        window.setTimeout(() => {
          document.getElementById("add-product-form")?.scrollIntoView({
            behavior: "smooth",
            block: "start",
          });
          document.getElementById("product-name")?.focus();
        }, 50);
        return;
      }

      setQuickBarcodeMessage("تعذر تحديد حالة الباركود.");
    } catch {
      setQuickBarcodeMessage("تعذر البحث عن الباركود. حاول مرة ثانية.");
    } finally {
      setQuickBarcodeBusy(false);
    }
  }

  async function handleAdd(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);

    const normalizedName = name.trim();
    const normalizedBarcode = barcode.trim();
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
      if (normalizedBarcode) {
        const barcodeStatus = await validateAdminBarcode(supabase, {
          storeId,
          barcode: normalizedBarcode,
        });

        if (!barcodeStatus.valid || !barcodeStatus.available) {
          setError(barcodeErrorMessage(barcodeStatus.reason, barcodeStatus.product_name));
          return;
        }
      }

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
        barcode: normalizedBarcode || null,
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
      setBarcode("");
      setImageFile(null);

      const fileInput = document.getElementById("product-image") as HTMLInputElement | null;
      if (fileInput) fileInput.value = "";

      router.refresh();
    } catch (caught) {
      const code =
        typeof caught === "object" && caught !== null && "code" in caught
          ? String((caught as { code?: unknown }).code ?? "")
          : "";

      setError(
        code === "23505"
          ? "هذا الباركود مستخدم لمنتج آخر."
          : "تعذر إضافة المنتج أو رفع الصورة. تأكد من البيانات وحاول مرة ثانية.",
      );
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

  async function beginBarcodeEdit(product: Product) {
    setError(null);
    setLoadingBarcodeId(product.id);

    try {
      const { data, error: fetchError } = await supabase
        .from("products")
        .select("barcode")
        .eq("id", product.id)
        .eq("store_id", storeId)
        .maybeSingle();

      if (fetchError) throw fetchError;

      setEditingBarcodeProductId(product.id);
      setEditingBarcodeValue(
        typeof data?.barcode === "string" ? data.barcode : "",
      );
    } catch {
      setError("تعذر تحميل باركود المنتج.");
    } finally {
      setLoadingBarcodeId(null);
    }
  }

  async function saveProductBarcode(product: Product) {
    const normalizedBarcode = editingBarcodeValue.trim();
    setError(null);
    setSavingBarcode(true);

    try {
      if (normalizedBarcode) {
        const barcodeStatus = await validateAdminBarcode(supabase, {
          storeId,
          barcode: normalizedBarcode,
          excludeProductId: product.id,
        });

        if (!barcodeStatus.valid || !barcodeStatus.available) {
          setError(barcodeErrorMessage(barcodeStatus.reason, barcodeStatus.product_name));
          return;
        }
      }

      const { error: updateError } = await supabase
        .from("products")
        .update({ barcode: normalizedBarcode || null })
        .eq("id", product.id)
        .eq("store_id", storeId);

      if (updateError) throw updateError;

      setEditingBarcodeProductId(null);
      setEditingBarcodeValue("");
      router.refresh();
    } catch (caught) {
      const code =
        typeof caught === "object" && caught !== null && "code" in caught
          ? String((caught as { code?: unknown }).code ?? "")
          : "";

      setError(
        code === "23505"
          ? "هذا الباركود مستخدم لمنتج آخر."
          : "تعذر حفظ باركود المنتج.",
      );
    } finally {
      setSavingBarcode(false);
    }
  }

  function resetProductEdit() {
    setEditingProductId(null);
    setEditName("");
    setEditPrice("");
    setEditStock("");
    setEditCategoryId("");
    setEditAvailable(true);
    setEditBarcode("");
    setEditImageFile(null);
    setEditRemoveImage(false);
    setEditError(null);

    const editImageInput = document.getElementById(
      "edit-product-image",
    ) as HTMLInputElement | null;
    if (editImageInput) editImageInput.value = "";
  }

  async function beginProductEdit(product: Product) {
    setEditSuccess(null);
    setEditError(null);
    setError(null);
    setEditingBarcodeProductId(null);
    setEditingBarcodeValue("");
    setEditingProductId(product.id);
    setEditName(product.name);
    setEditPrice(String(product.price));
    setEditStock(String(product.stock_qty));
    setEditCategoryId(product.category_id ?? "");
    setEditAvailable(product.is_available);
    setEditBarcode("");
    setEditImageFile(null);
    setEditRemoveImage(false);

    try {
      const { data, error: fetchError } = await supabase
        .from("products")
        .select("barcode")
        .eq("id", product.id)
        .eq("store_id", storeId)
        .maybeSingle();

      if (fetchError) throw fetchError;
      setEditBarcode(typeof data?.barcode === "string" ? data.barcode : "");
    } catch {
      setEditError("تعذر تحميل باركود المنتج، لكن يمكنك تعديل باقي المعلومات.");
    }

    window.setTimeout(() => {
      document.getElementById(`edit-product-${product.id}`)?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
      document.getElementById("edit-product-name")?.focus();
    }, 50);
  }

  async function saveProductEdit(product: Product) {
    const normalizedName = editName.trim();
    const normalizedBarcode = editBarcode.trim();
    const parsedPrice = Number(editPrice);
    const parsedStock = Number(editStock);
    const imageValidationError = validateImage(editImageFile);

    setEditError(null);
    setEditSuccess(null);

    if (!normalizedName) {
      setEditError("اسم المنتج مطلوب.");
      return;
    }
    if (!Number.isFinite(parsedPrice) || parsedPrice <= 0) {
      setEditError("السعر لازم يكون رقم أكبر من صفر.");
      return;
    }
    if (!Number.isInteger(parsedStock) || parsedStock < 0) {
      setEditError("الكمية لازم تكون رقم صحيح صفر أو أكبر.");
      return;
    }
    if (imageValidationError) {
      setEditError(imageValidationError);
      return;
    }

    setSavingProductEdit(true);
    let uploadedPath: string | null = null;

    try {
      if (normalizedBarcode) {
        const barcodeStatus = await validateAdminBarcode(supabase, {
          storeId,
          barcode: normalizedBarcode,
          excludeProductId: product.id,
        });

        if (!barcodeStatus.valid || !barcodeStatus.available) {
          setEditError(
            barcodeErrorMessage(barcodeStatus.reason, barcodeStatus.product_name),
          );
          return;
        }
      }

      let nextImageUrl = product.image_url;
      if (editImageFile) {
        const uploaded = await uploadImage(editImageFile);
        uploadedPath = uploaded.path;
        nextImageUrl = uploaded.publicUrl;
      } else if (editRemoveImage) {
        nextImageUrl = null;
      }

      const { error: updateError } = await supabase
        .from("products")
        .update({
          name: normalizedName,
          price: parsedPrice,
          stock_qty: parsedStock,
          category_id: editCategoryId || null,
          is_available: parsedStock > 0 ? editAvailable : false,
          barcode: normalizedBarcode || null,
          image_url: nextImageUrl,
        })
        .eq("id", product.id)
        .eq("store_id", storeId);

      if (updateError) {
        if (uploadedPath) {
          await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([uploadedPath]);
        }
        throw updateError;
      }

      if ((editImageFile || editRemoveImage) && product.image_url) {
        const oldImagePath = storagePathFromPublicUrl(product.image_url);
        if (oldImagePath) {
          await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([oldImagePath]);
        }
      }

      setEditSuccess(`تم حفظ تعديلات ${normalizedName} بنجاح.`);
      resetProductEdit();
      router.refresh();

      window.setTimeout(() => {
        setEditSuccess(null);
      }, 3500);
    } catch (caught) {
      const code =
        typeof caught === "object" && caught !== null && "code" in caught
          ? String((caught as { code?: unknown }).code ?? "")
          : "";

      setEditError(
        code === "23505"
          ? "هذا الباركود مستخدم لمنتج آخر."
          : "تعذر حفظ تعديلات المنتج. تأكد من البيانات وحاول مرة ثانية.",
      );
    } finally {
      setSavingProductEdit(false);
    }
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
        id="quick-barcode-form"
        onSubmit={handleQuickBarcodeSearch}
        className="rounded-xl border border-gray-200 bg-white p-4"
      >
        <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h2 className="text-base font-semibold text-gray-900">مسح سريع بالباركود</h2>
            <p className="mt-1 text-xs leading-6 text-gray-500">
              قارئ USB: ضع المؤشر في حقل الباركود ثم امسح المنتج؛ أغلب الأجهزة ترسل Enter تلقائيًا.
              ويمكنك استخدام زر الكاميرا داخل نفس الحقل.
            </p>
          </div>
          <span className="w-fit rounded-full bg-green-50 px-3 py-1 text-xs font-medium text-green-700">
            USB + كاميرا
          </span>
        </div>

        <BarcodeField
          supabase={supabase}
          storeId={storeId}
          value={quickBarcode}
          onChange={(value) => {
            setQuickBarcode(value);
            setQuickBarcodeMessage(null);
            setHighlightProductId(null);
          }}
          disabled={quickBarcodeBusy}
        />

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="submit"
            disabled={quickBarcodeBusy || !quickBarcode.trim()}
            className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:cursor-not-allowed disabled:opacity-50"
          >
            {quickBarcodeBusy ? "جاري البحث..." : "بحث عن المنتج"}
          </button>

          <button
            type="button"
            disabled={quickBarcodeBusy}
            onClick={() => {
              setQuickBarcode("");
              setQuickBarcodeMessage(null);
              setHighlightProductId(null);
              document
                .querySelector<HTMLInputElement>("#quick-barcode-form input")
                ?.focus();
            }}
            className="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
          >
            مسح جديد
          </button>
        </div>

        {quickBarcodeMessage && (
          <p
            className={`mt-3 rounded-lg px-3 py-2 text-sm ${
              highlightProductId
                ? "bg-green-50 text-green-800"
                : "bg-amber-50 text-amber-800"
            }`}
          >
            {quickBarcodeMessage}
          </p>
        )}
      </form>

      <form
        id="add-product-form"
        onSubmit={handleAdd}
        className="grid grid-cols-1 gap-3 rounded-xl border border-gray-200 bg-white p-4 sm:grid-cols-6"
      >
        <input
          id="product-name"
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

        <div className="sm:col-span-6">
          <BarcodeField
            supabase={supabase}
            storeId={storeId}
            value={barcode}
            onChange={setBarcode}
            disabled={saving}
          />
        </div>

        <button
          type="submit"
          disabled={saving}
          className="rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:cursor-not-allowed disabled:opacity-60 sm:col-span-6"
        >
          {saving ? "جاري رفع الصورة وإضافة المنتج..." : "إضافة منتج"}
        </button>

        <p className="text-xs text-gray-500 sm:col-span-6">
          الصور المدعومة: JPG / PNG / WebP، وبحد أقصى 5MB. الباركود اختياري، لكنه مطلوب لتفعيل البحث والمسح للمنتج.
        </p>

        {error && (
          <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700 sm:col-span-6">
            {error}
          </p>
        )}
      </form>

      {editSuccess && (
        <div className="rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-sm font-medium text-green-800">
          {editSuccess}
        </div>
      )}

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
                const barcodeLoading = loadingBarcodeId === product.id;
                const editingBarcode = editingBarcodeProductId === product.id;
                const editingProduct = editingProductId === product.id;

                return (
                  <Fragment key={product.id}>
                    <tr
                      id={`product-${product.id}`}
                      className={`border-t border-gray-100 transition-colors ${
                        highlightProductId === product.id ? "bg-amber-50 ring-1 ring-inset ring-amber-300" : ""
                      }`}
                    >
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
                          {busy ? "..." : product.is_available ? "متوفر" : "غير متوفر"}
                        </button>
                      </td>

                      <td className="px-4 py-3">
                        <div className="flex items-center justify-end gap-3">
                          <button
                            type="button"
                            disabled={busy || savingProductEdit}
                            onClick={() => void beginProductEdit(product)}
                            className="text-xs font-semibold text-brand hover:underline disabled:opacity-50"
                          >
                            تعديل
                          </button>

                          <button
                            type="button"
                            disabled={busy || barcodeLoading || savingBarcode || savingProductEdit}
                            onClick={() => void beginBarcodeEdit(product)}
                            className="text-xs font-medium text-gray-700 hover:underline disabled:opacity-50"
                          >
                            {barcodeLoading ? "..." : "باركود"}
                          </button>

                          <button
                            type="button"
                            disabled={busy}
                            onClick={() => deleteProduct(product)}
                            className="text-xs text-red-600 hover:underline disabled:opacity-50"
                          >
                            حذف
                          </button>
                        </div>
                      </td>
                    </tr>

                    {editingProduct && (
                      <tr
                        id={`edit-product-${product.id}`}
                        className="border-t border-gray-100 bg-blue-50/40"
                      >
                        <td colSpan={6} className="px-4 py-5">
                          <div className="mx-auto max-w-5xl rounded-xl border border-blue-200 bg-white p-4 shadow-sm">
                            <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
                              <div>
                                <h3 className="text-base font-semibold text-gray-900">
                                  تعديل معلومات المنتج
                                </h3>
                                <p className="mt-1 text-xs text-gray-500">
                                  عدّل الاسم والسعر والمخزون والتصنيف والصورة والباركود وحالة التوفر.
                                </p>
                              </div>
                              <span className="rounded-full bg-blue-50 px-3 py-1 text-xs font-medium text-blue-700">
                                {product.name}
                              </span>
                            </div>

                            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                              <label className="space-y-1 lg:col-span-2">
                                <span className="text-xs font-medium text-gray-700">
                                  اسم المنتج
                                </span>
                                <input
                                  id="edit-product-name"
                                  value={editName}
                                  maxLength={120}
                                  disabled={savingProductEdit}
                                  onChange={(e) => setEditName(e.target.value)}
                                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand disabled:bg-gray-50"
                                />
                              </label>

                              <label className="space-y-1">
                                <span className="text-xs font-medium text-gray-700">
                                  السعر (د.أ)
                                </span>
                                <input
                                  type="number"
                                  min="0.01"
                                  step="0.01"
                                  value={editPrice}
                                  disabled={savingProductEdit}
                                  onChange={(e) => setEditPrice(e.target.value)}
                                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand disabled:bg-gray-50"
                                />
                              </label>

                              <label className="space-y-1">
                                <span className="text-xs font-medium text-gray-700">
                                  الكمية
                                </span>
                                <input
                                  type="number"
                                  min="0"
                                  step="1"
                                  value={editStock}
                                  disabled={savingProductEdit}
                                  onChange={(e) => setEditStock(e.target.value)}
                                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand disabled:bg-gray-50"
                                />
                              </label>

                              <label className="space-y-1 lg:col-span-2">
                                <span className="text-xs font-medium text-gray-700">
                                  التصنيف
                                </span>
                                <select
                                  value={editCategoryId}
                                  disabled={savingProductEdit}
                                  onChange={(e) => setEditCategoryId(e.target.value)}
                                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand disabled:bg-gray-50"
                                >
                                  <option value="">بدون تصنيف</option>
                                  {categories.map((category) => (
                                    <option key={category.id} value={category.id}>
                                      {category.name}
                                    </option>
                                  ))}
                                </select>
                              </label>

                              <label className="space-y-1 lg:col-span-2">
                                <span className="text-xs font-medium text-gray-700">
                                  حالة التوفر
                                </span>
                                <select
                                  value={editAvailable ? "available" : "unavailable"}
                                  disabled={savingProductEdit || Number(editStock) <= 0}
                                  onChange={(e) =>
                                    setEditAvailable(e.target.value === "available")
                                  }
                                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm outline-none focus:border-brand disabled:bg-gray-50"
                                >
                                  <option value="available">متوفر</option>
                                  <option value="unavailable">غير متوفر</option>
                                </select>
                                {Number(editStock) <= 0 && (
                                  <p className="text-[11px] text-amber-700">
                                    عند وصول الكمية إلى صفر سيتم حفظ المنتج كغير متوفر تلقائيًا.
                                  </p>
                                )}
                              </label>

                              <div className="space-y-2 lg:col-span-4">
                                <span className="text-xs font-medium text-gray-700">
                                  الباركود
                                </span>
                                <BarcodeField
                                  supabase={supabase}
                                  storeId={storeId}
                                  productId={product.id}
                                  value={editBarcode}
                                  onChange={setEditBarcode}
                                  disabled={savingProductEdit}
                                />
                              </div>

                              <div className="rounded-lg border border-gray-200 p-3 lg:col-span-4">
                                <div className="grid grid-cols-1 gap-3 sm:grid-cols-[auto_1fr] sm:items-center">
                                  <div className="flex h-20 w-20 items-center justify-center overflow-hidden rounded-lg border border-gray-200 bg-gray-50">
                                    {!editRemoveImage && product.image_url ? (
                                      // eslint-disable-next-line @next/next/no-img-element
                                      <img
                                        src={
                                          editImageFile
                                            ? URL.createObjectURL(editImageFile)
                                            : product.image_url
                                        }
                                        alt={editName || product.name}
                                        className="h-full w-full object-cover"
                                      />
                                    ) : editImageFile ? (
                                      // eslint-disable-next-line @next/next/no-img-element
                                      <img
                                        src={URL.createObjectURL(editImageFile)}
                                        alt={editName || product.name}
                                        className="h-full w-full object-cover"
                                      />
                                    ) : (
                                      <span className="text-[10px] text-gray-400">
                                        بدون صورة
                                      </span>
                                    )}
                                  </div>

                                  <div className="space-y-2">
                                    <label className="flex cursor-pointer items-center justify-center rounded-lg border border-dashed border-gray-300 px-3 py-2 text-sm text-gray-600 hover:border-brand hover:text-brand">
                                      <span className="truncate">
                                        {editImageFile
                                          ? editImageFile.name
                                          : "اختيار صورة جديدة"}
                                      </span>
                                      <input
                                        id="edit-product-image"
                                        type="file"
                                        accept="image/jpeg,image/png,image/webp"
                                        className="sr-only"
                                        disabled={savingProductEdit}
                                        onChange={(e) => {
                                          const file = e.target.files?.[0] ?? null;
                                          const validationError = validateImage(file);
                                          if (validationError) {
                                            setEditError(validationError);
                                            e.target.value = "";
                                            setEditImageFile(null);
                                            return;
                                          }
                                          setEditError(null);
                                          setEditImageFile(file);
                                          if (file) setEditRemoveImage(false);
                                        }}
                                      />
                                    </label>

                                    {(product.image_url || editImageFile) && (
                                      <label className="flex items-center gap-2 text-xs text-gray-600">
                                        <input
                                          type="checkbox"
                                          checked={editRemoveImage}
                                          disabled={savingProductEdit}
                                          onChange={(e) => {
                                            setEditRemoveImage(e.target.checked);
                                            if (e.target.checked) {
                                              setEditImageFile(null);
                                              const input = document.getElementById(
                                                "edit-product-image",
                                              ) as HTMLInputElement | null;
                                              if (input) input.value = "";
                                            }
                                          }}
                                        />
                                        حذف صورة المنتج الحالية
                                      </label>
                                    )}
                                  </div>
                                </div>
                              </div>
                            </div>

                            {editError && (
                              <p className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">
                                {editError}
                              </p>
                            )}

                            <div className="mt-4 flex flex-wrap justify-end gap-2">
                              <button
                                type="button"
                                disabled={savingProductEdit}
                                onClick={resetProductEdit}
                                className="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                              >
                                إلغاء
                              </button>

                              <button
                                type="button"
                                disabled={savingProductEdit}
                                onClick={() => void saveProductEdit(product)}
                                className="rounded-lg bg-brand px-5 py-2 text-sm font-semibold text-white hover:bg-brand-dark disabled:opacity-50"
                              >
                                {savingProductEdit ? "جاري الحفظ..." : "حفظ التعديلات"}
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}

                    {editingBarcode && (
                      <tr className="border-t border-gray-100 bg-gray-50/60">
                        <td colSpan={6} className="px-4 py-4">
                          <div className="mx-auto max-w-2xl rounded-xl border border-gray-200 bg-white p-4">
                            <p className="mb-3 text-sm font-semibold text-gray-800">
                              باركود: {product.name}
                            </p>

                            <BarcodeField
                              supabase={supabase}
                              storeId={storeId}
                              productId={product.id}
                              value={editingBarcodeValue}
                              onChange={setEditingBarcodeValue}
                              disabled={savingBarcode}
                            />

                            <div className="mt-3 flex justify-end gap-2">
                              <button
                                type="button"
                                disabled={savingBarcode}
                                onClick={() => {
                                  setEditingBarcodeProductId(null);
                                  setEditingBarcodeValue("");
                                }}
                                className="rounded-lg border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                              >
                                إلغاء
                              </button>

                              <button
                                type="button"
                                disabled={savingBarcode}
                                onClick={() => void saveProductBarcode(product)}
                                className="rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-50"
                              >
                                {savingBarcode ? "جاري الحفظ..." : "حفظ الباركود"}
                              </button>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
