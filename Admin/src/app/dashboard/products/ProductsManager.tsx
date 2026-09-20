"use client";

import { Fragment, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { BarcodeField } from "@/components/products/barcode-field";
import { BarcodeBulkImport } from "@/components/products/barcode-bulk-import";
import { validateAdminBarcode } from "@/lib/barcode";
import { createClient } from "@/lib/supabase/client";

type SaleType = "piece" | "weight" | "volume";

type Product = {
  id: string;
  name: string;
  sku: string | null;
  barcode: string | null;
  price: number;
  price_per_unit: number | null;
  stock_qty: number;
  is_available: boolean;
  category_id: string | null;
  image_url: string | null;
  sale_type: SaleType | null;
  base_unit: string | null;
  inventory_scale: number | null;
  min_qty: number | null;
  qty_step: number | null;
  allow_amount_purchase: boolean | null;
};

type Category = { id: string; name: string };

const PRODUCT_IMAGES_BUCKET = "product-images";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

function scaleFor(type: SaleType) {
  return type === "piece" ? 1 : 1000;
}

function baseUnitFor(type: SaleType) {
  if (type === "weight") return "kg";
  if (type === "volume") return "liter";
  return "piece";
}

function typeLabel(type: SaleType) {
  if (type === "weight") return "بالوزن";
  if (type === "volume") return "بالحجم";
  return "بالحبة";
}

function unitLabel(type: SaleType) {
  if (type === "weight") return "كغ";
  if (type === "volume") return "لتر";
  return "قطعة";
}

function smallUnitLabel(type: SaleType) {
  if (type === "weight") return "غرام";
  if (type === "volume") return "مل";
  return "قطعة";
}

function normalizedType(product: Product): SaleType {
  return product.sale_type === "weight" || product.sale_type === "volume"
    ? product.sale_type
    : "piece";
}

function displayUnitPrice(product: Product) {
  const type = normalizedType(product);
  return Number(product.price_per_unit ?? Number(product.price) * scaleFor(type));
}

function displayStock(product: Product) {
  const scale = Number(product.inventory_scale || scaleFor(normalizedType(product)));
  return Number(product.stock_qty) / (scale > 0 ? scale : 1);
}

function formatStock(product: Product) {
  const type = normalizedType(product);
  if (type === "piece") return `${product.stock_qty} قطعة`;
  const value = displayStock(product);
  return `${value.toLocaleString("ar-JO", { maximumFractionDigits: 3 })} ${unitLabel(type)}`;
}

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
  if (reason === "BARCODE_TOO_LONG") return "الباركود أطول من الحد المسموح.";
  return "تعذر التحقق من الباركود. حاول مرة ثانية.";
}

function defaultMin(type: SaleType) {
  return type === "piece" ? "1" : "100";
}

function defaultStep(type: SaleType) {
  return type === "piece" ? "1" : "50";
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
  const supabase = useMemo(() => createClient(), []);

  const [name, setName] = useState("");
  const [price, setPrice] = useState("");
  const [stock, setStock] = useState("");
  const [saleType, setSaleType] = useState<SaleType>("piece");
  const [minQty, setMinQty] = useState("1");
  const [qtyStep, setQtyStep] = useState("1");
  const [allowAmountPurchase, setAllowAmountPurchase] = useState(false);
  const [categoryId, setCategoryId] = useState(categories[0]?.id || "");
  const [barcode, setBarcode] = useState("");
  const [imageFile, setImageFile] = useState<File | null>(null);

  const [saving, setSaving] = useState(false);
  const [busyProductId, setBusyProductId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [quickBarcode, setQuickBarcode] = useState("");
  const [quickBarcodeBusy, setQuickBarcodeBusy] = useState(false);
  const [quickBarcodeMessage, setQuickBarcodeMessage] = useState<string | null>(null);
  const [highlightProductId, setHighlightProductId] = useState<string | null>(null);

  const [editingProductId, setEditingProductId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [editPrice, setEditPrice] = useState("");
  const [editStock, setEditStock] = useState("");
  const [editSaleType, setEditSaleType] = useState<SaleType>("piece");
  const [editMinQty, setEditMinQty] = useState("1");
  const [editQtyStep, setEditQtyStep] = useState("1");
  const [editAllowAmountPurchase, setEditAllowAmountPurchase] = useState(false);
  const [editCategoryId, setEditCategoryId] = useState("");
  const [editAvailable, setEditAvailable] = useState(true);
  const [editBarcode, setEditBarcode] = useState("");
  const [editImageFile, setEditImageFile] = useState<File | null>(null);
  const [editRemoveImage, setEditRemoveImage] = useState(false);
  const [savingProductEdit, setSavingProductEdit] = useState(false);
  const [editError, setEditError] = useState<string | null>(null);

  function validateImage(file: File | null) {
    if (!file) return null;
    if (!ALLOWED_IMAGE_TYPES.has(file.type)) return "الصورة لازم تكون JPG أو PNG أو WebP";
    if (file.size > MAX_IMAGE_BYTES) return "حجم الصورة لازم يكون 5MB أو أقل";
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

  function changeSaleType(next: SaleType) {
    setSaleType(next);
    setMinQty(defaultMin(next));
    setQtyStep(defaultStep(next));
    setAllowAmountPurchase(next !== "piece");
  }

  function changeEditSaleType(next: SaleType) {
    setEditSaleType(next);
    if (next === "piece") {
      setEditMinQty("1");
      setEditQtyStep("1");
      setEditAllowAmountPurchase(false);
    } else if (editSaleType === "piece") {
      setEditMinQty("100");
      setEditQtyStep("50");
      setEditAllowAmountPurchase(true);
    }
  }

  function parseProductInputs(
    type: SaleType,
    priceValue: string,
    stockValue: string,
    minValue: string,
    stepValue: string,
  ) {
    const unitPrice = Number(priceValue);
    const displayStockValue = stockValue.trim() === "" ? 0 : Number(stockValue);
    const parsedMin = Number(minValue);
    const parsedStep = Number(stepValue);
    const scale = scaleFor(type);

    if (!Number.isFinite(unitPrice) || unitPrice <= 0) {
      throw new Error("السعر لازم يكون رقم أكبر من صفر.");
    }
    if (!Number.isFinite(displayStockValue) || displayStockValue < 0) {
      throw new Error("المخزون لازم يكون صفر أو أكبر.");
    }
    if (type === "piece" && !Number.isInteger(displayStockValue)) {
      throw new Error("مخزون المنتج بالحبة لازم يكون رقم صحيح.");
    }
    if (!Number.isInteger(parsedMin) || parsedMin <= 0) {
      throw new Error("الحد الأدنى للكمية غير صالح.");
    }
    if (!Number.isInteger(parsedStep) || parsedStep <= 0) {
      throw new Error("خطوة الكمية غير صالحة.");
    }

    return {
      unitPrice,
      atomicPrice: unitPrice / scale,
      atomicStock: Math.round(displayStockValue * scale),
      min: type === "piece" ? 1 : parsedMin,
      step: type === "piece" ? 1 : parsedStep,
      scale,
    };
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
    try {
      const status = await validateAdminBarcode(supabase, {
        storeId,
        barcode: normalizedBarcode,
      });

      const result = status as typeof status & { product_id?: string; product_name?: string };
      if (!result.valid) {
        setQuickBarcodeMessage(barcodeErrorMessage(result.reason, result.product_name));
      } else if (!result.available && result.product_id) {
        const product = initialProducts.find((item) => item.id === result.product_id);
        if (product) {
          setHighlightProductId(product.id);
          setQuickBarcodeMessage(
            `تم العثور على ${product.name} — ${displayUnitPrice(product).toFixed(2)} د.أ/${unitLabel(normalizedType(product))} — ${formatStock(product)}.`,
          );
          window.setTimeout(() => {
            document.getElementById(`product-${product.id}`)?.scrollIntoView({
              behavior: "smooth",
              block: "center",
            });
          }, 50);
        } else {
          setQuickBarcodeMessage("تم العثور على المنتج. حدّث الصفحة إذا لم يظهر في القائمة.");
        }
      } else {
        setBarcode(normalizedBarcode);
        setQuickBarcodeMessage("الباركود جديد وتم نقله لنموذج إضافة المنتج.");
        window.setTimeout(() => {
          document.getElementById("add-product-form")?.scrollIntoView({ behavior: "smooth" });
        }, 50);
      }
    } catch {
      setQuickBarcodeMessage("تعذر البحث عن الباركود. حاول مرة ثانية.");
    } finally {
      setQuickBarcodeBusy(false);
    }
  }

  async function handleAdd(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    const normalizedName = name.trim();
    const normalizedBarcode = barcode.trim();
    if (!normalizedName) {
      setError("لازم تعبي اسم المنتج");
      return;
    }

    let values: ReturnType<typeof parseProductInputs>;
    try {
      values = parseProductInputs(saleType, price, stock, minQty, qtyStep);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "بيانات المنتج غير صالحة.");
      return;
    }

    const imageValidationError = validateImage(imageFile);
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
        price: values.atomicPrice,
        price_per_unit: values.unitPrice,
        stock_qty: values.atomicStock,
        is_available: values.atomicStock > 0,
        image_url: imageUrl,
        barcode: normalizedBarcode || null,
        sale_type: saleType,
        base_unit: baseUnitFor(saleType),
        inventory_scale: values.scale,
        min_qty: values.min,
        qty_step: values.step,
        allow_amount_purchase: saleType !== "piece" && allowAmountPurchase,
      });

      if (insertError) {
        if (uploadedPath) await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([uploadedPath]);
        throw insertError;
      }

      setName("");
      setPrice("");
      setStock("");
      setBarcode("");
      setImageFile(null);
      changeSaleType("piece");
      const fileInput = document.getElementById("product-image") as HTMLInputElement | null;
      if (fileInput) fileInput.value = "";
      setSuccess(`تمت إضافة ${normalizedName}.`);
      router.refresh();
    } catch (caught) {
      const code = typeof caught === "object" && caught !== null && "code" in caught
        ? String((caught as { code?: unknown }).code ?? "")
        : "";
      setError(code === "23505" ? "هذا الباركود مستخدم لمنتج آخر." : "تعذر إضافة المنتج.");
    } finally {
      setSaving(false);
    }
  }

  async function toggleAvailability(product: Product) {
    setBusyProductId(product.id);
    const { error: updateError } = await supabase
      .from("products")
      .update({ is_available: !product.is_available })
      .eq("id", product.id)
      .eq("store_id", storeId);
    setBusyProductId(null);
    if (updateError) setError("تعذر تحديث حالة المنتج.");
    else router.refresh();
  }

  async function beginProductEdit(product: Product) {
    setEditError(null);
    setEditingProductId(product.id);
    const type = normalizedType(product);
    setEditName(product.name);
    setEditPrice(String(displayUnitPrice(product)));
    setEditStock(String(displayStock(product)));
    setEditSaleType(type);
    setEditMinQty(String(product.min_qty ?? (type === "piece" ? 1 : 100)));
    setEditQtyStep(String(product.qty_step ?? (type === "piece" ? 1 : 50)));
    setEditAllowAmountPurchase(Boolean(product.allow_amount_purchase && type !== "piece"));
    setEditCategoryId(product.category_id ?? "");
    setEditAvailable(product.is_available);
    setEditImageFile(null);
    setEditRemoveImage(false);

    try {
      const { data } = await supabase
        .from("products")
        .select("barcode")
        .eq("id", product.id)
        .eq("store_id", storeId)
        .maybeSingle();
      setEditBarcode(typeof data?.barcode === "string" ? data.barcode : "");
    } catch {
      setEditBarcode("");
    }
  }

  function cancelProductEdit() {
    setEditingProductId(null);
    setEditImageFile(null);
    setEditRemoveImage(false);
    setEditError(null);
  }

  async function saveProductEdit(product: Product) {
    const normalizedName = editName.trim();
    const normalizedBarcode = editBarcode.trim();
    if (!normalizedName) {
      setEditError("اسم المنتج مطلوب.");
      return;
    }

    let values: ReturnType<typeof parseProductInputs>;
    try {
      values = parseProductInputs(editSaleType, editPrice, editStock, editMinQty, editQtyStep);
    } catch (caught) {
      setEditError(caught instanceof Error ? caught.message : "بيانات المنتج غير صالحة.");
      return;
    }

    const imageValidationError = validateImage(editImageFile);
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
          setEditError(barcodeErrorMessage(barcodeStatus.reason, barcodeStatus.product_name));
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
          price: values.atomicPrice,
          price_per_unit: values.unitPrice,
          stock_qty: values.atomicStock,
          category_id: editCategoryId || null,
          is_available: values.atomicStock > 0 ? editAvailable : false,
          barcode: normalizedBarcode || null,
          image_url: nextImageUrl,
          sale_type: editSaleType,
          base_unit: baseUnitFor(editSaleType),
          inventory_scale: values.scale,
          min_qty: values.min,
          qty_step: values.step,
          allow_amount_purchase: editSaleType !== "piece" && editAllowAmountPurchase,
        })
        .eq("id", product.id)
        .eq("store_id", storeId);

      if (updateError) {
        if (uploadedPath) await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([uploadedPath]);
        throw updateError;
      }

      if ((editImageFile || editRemoveImage) && product.image_url) {
        const oldImagePath = storagePathFromPublicUrl(product.image_url);
        if (oldImagePath) await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([oldImagePath]);
      }

      setEditingProductId(null);
      setSuccess(`تم حفظ تعديلات ${normalizedName}.`);
      router.refresh();
    } catch (caught) {
      const code = typeof caught === "object" && caught !== null && "code" in caught
        ? String((caught as { code?: unknown }).code ?? "")
        : "";
      setEditError(code === "23505" ? "هذا الباركود مستخدم لمنتج آخر." : "تعذر حفظ تعديلات المنتج.");
    } finally {
      setSavingProductEdit(false);
    }
  }

  async function deleteProduct(product: Product) {
    if (!window.confirm("متأكد إنك بدك تحذف المنتج؟")) return;
    setBusyProductId(product.id);
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
    if (imagePath) await supabase.storage.from(PRODUCT_IMAGES_BUCKET).remove([imagePath]);
    setBusyProductId(null);
    router.refresh();
  }

  return (
    <div className="space-y-6">
      <BarcodeBulkImport
        storeId={storeId}
        products={initialProducts.map((product) => ({
          id: product.id,
          name: product.name,
          sku: product.sku,
          barcode: product.barcode,
        }))}
      />

      <form
        id="quick-barcode-form"
        onSubmit={handleQuickBarcodeSearch}
        className="rounded-xl border border-gray-200 bg-white p-4"
      >
        <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
          <div>
            <h2 className="font-semibold">مسح سريع بالباركود</h2>
            <p className="mt-1 text-xs text-gray-500">USB أو كاميرا — ابحث عن المنتج أو انقل الباركود لنموذج الإضافة.</p>
          </div>
          <span className="rounded-full bg-green-50 px-3 py-1 text-xs text-green-700">USB + كاميرا</span>
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
        <button
          type="submit"
          disabled={quickBarcodeBusy || !quickBarcode.trim()}
          className="mt-3 rounded-lg bg-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        >
          {quickBarcodeBusy ? "جاري البحث..." : "بحث"}
        </button>
        {quickBarcodeMessage && (
          <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-900">{quickBarcodeMessage}</p>
        )}
      </form>

      <form
        id="add-product-form"
        onSubmit={handleAdd}
        className="rounded-xl border border-gray-200 bg-white p-4"
      >
        <div className="mb-4">
          <h2 className="font-semibold">إضافة منتج</h2>
          <p className="mt-1 text-xs text-gray-500">اختر طريقة البيع أولًا. المنتجات بالوزن تُخزّن داخليًا بالغرام لتبقى الفواتير والدفع دقيقة.</p>
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label className="space-y-1 lg:col-span-2">
            <span className="text-xs font-medium">اسم المنتج</span>
            <input id="product-name" value={name} maxLength={120} onChange={(e) => setName(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
          </label>

          <label className="space-y-1">
            <span className="text-xs font-medium">طريقة البيع</span>
            <select value={saleType} onChange={(e) => changeSaleType(e.target.value as SaleType)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
              <option value="piece">بالحبة / العبوة</option>
              <option value="weight">بالوزن (كغ)</option>
              <option value="volume">بالحجم (لتر)</option>
            </select>
          </label>

          <label className="space-y-1">
            <span className="text-xs font-medium">السعر لكل {unitLabel(saleType)} (د.أ)</span>
            <input type="number" min="0.001" step="0.001" value={price} onChange={(e) => setPrice(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
          </label>

          <label className="space-y-1">
            <span className="text-xs font-medium">المخزون ({unitLabel(saleType)})</span>
            <input type="number" min="0" step={saleType === "piece" ? "1" : "0.001"} value={stock} onChange={(e) => setStock(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
          </label>

          <label className="space-y-1">
            <span className="text-xs font-medium">التصنيف</span>
            <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
              <option value="">بدون تصنيف</option>
              {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
            </select>
          </label>

          {saleType !== "piece" && (
            <>
              <label className="space-y-1">
                <span className="text-xs font-medium">أقل كمية ({smallUnitLabel(saleType)})</span>
                <input type="number" min="1" step="1" value={minQty} onChange={(e) => setMinQty(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
              </label>
              <label className="space-y-1">
                <span className="text-xs font-medium">خطوة الاختيار ({smallUnitLabel(saleType)})</span>
                <input type="number" min="1" step="1" value={qtyStep} onChange={(e) => setQtyStep(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
              </label>
              <label className="flex items-center gap-2 rounded-lg border border-gray-200 px-3 py-2 text-sm">
                <input type="checkbox" checked={allowAmountPurchase} onChange={(e) => setAllowAmountPurchase(e.target.checked)} />
                السماح بالشراء حسب المبلغ (نصف دينار / دينار...)
              </label>
            </>
          )}

          <label className="flex cursor-pointer items-center justify-center rounded-lg border border-dashed border-gray-300 px-3 py-2 text-sm text-gray-600">
            <span className="truncate">{imageFile ? imageFile.name : "اختيار صورة"}</span>
            <input id="product-image" type="file" accept="image/jpeg,image/png,image/webp" className="sr-only" onChange={(e) => setImageFile(e.target.files?.[0] ?? null)} />
          </label>

          <div className="sm:col-span-2 lg:col-span-4">
            <BarcodeField supabase={supabase} storeId={storeId} value={barcode} onChange={setBarcode} disabled={saving} />
          </div>
        </div>

        <button type="submit" disabled={saving} className="mt-4 w-full rounded-lg bg-brand px-4 py-3 text-sm font-semibold text-white disabled:opacity-50">
          {saving ? "جاري الحفظ..." : "إضافة المنتج"}
        </button>
        {error && <p className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
        {success && <p className="mt-3 rounded-lg bg-green-50 px-3 py-2 text-sm text-green-800">{success}</p>}
      </form>

      <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
        <table className="min-w-[900px] w-full text-right text-sm">
          <thead className="bg-gray-50 text-gray-500">
            <tr>
              <th className="px-4 py-3 font-normal">الصورة</th>
              <th className="px-4 py-3 font-normal">المنتج</th>
              <th className="px-4 py-3 font-normal">طريقة البيع</th>
              <th className="px-4 py-3 font-normal">السعر</th>
              <th className="px-4 py-3 font-normal">المخزون</th>
              <th className="px-4 py-3 font-normal">متوفر</th>
              <th className="px-4 py-3 font-normal"></th>
            </tr>
          </thead>
          <tbody>
            {initialProducts.length === 0 ? (
              <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-500">ما في منتجات لسه.</td></tr>
            ) : initialProducts.map((product) => {
              const type = normalizedType(product);
              const editing = editingProductId === product.id;
              const busy = busyProductId === product.id;
              return (
                <Fragment key={product.id}>
                  <tr id={`product-${product.id}`} className={`border-t border-gray-100 ${highlightProductId === product.id ? "bg-amber-50" : ""}`}>
                    <td className="px-4 py-3">
                      {product.image_url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={product.image_url} alt={product.name} className="h-14 w-14 rounded-lg border object-cover" />
                      ) : <div className="flex h-14 w-14 items-center justify-center rounded-lg bg-gray-100 text-[10px] text-gray-400">بدون صورة</div>}
                    </td>
                    <td className="px-4 py-3 font-medium">{product.name}</td>
                    <td className="px-4 py-3"><span className="rounded-full bg-gray-100 px-2 py-1 text-xs">{typeLabel(type)}</span></td>
                    <td className="px-4 py-3">{displayUnitPrice(product).toFixed(3)} د.أ / {unitLabel(type)}</td>
                    <td className="px-4 py-3">{formatStock(product)}</td>
                    <td className="px-4 py-3">
                      <button type="button" disabled={busy || product.stock_qty <= 0} onClick={() => void toggleAvailability(product)} className={`rounded-full px-3 py-1 text-xs ${product.is_available ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-500"}`}>
                        {product.is_available ? "متوفر" : "غير متوفر"}
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end gap-3">
                        <button type="button" onClick={() => void beginProductEdit(product)} className="text-xs font-semibold text-brand hover:underline">تعديل</button>
                        <button type="button" disabled={busy} onClick={() => void deleteProduct(product)} className="text-xs text-red-600 hover:underline">حذف</button>
                      </div>
                    </td>
                  </tr>

                  {editing && (
                    <tr className="border-t bg-blue-50/40">
                      <td colSpan={7} className="px-4 py-5">
                        <div className="rounded-xl border border-blue-200 bg-white p-4">
                          <div className="mb-4 flex items-center justify-between gap-2">
                            <h3 className="font-semibold">تعديل {product.name}</h3>
                            <button type="button" onClick={cancelProductEdit} className="text-xs text-gray-500 hover:underline">إلغاء</button>
                          </div>
                          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                            <label className="space-y-1 lg:col-span-2">
                              <span className="text-xs font-medium">الاسم</span>
                              <input value={editName} onChange={(e) => setEditName(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
                            </label>
                            <label className="space-y-1">
                              <span className="text-xs font-medium">طريقة البيع</span>
                              <select value={editSaleType} onChange={(e) => changeEditSaleType(e.target.value as SaleType)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                                <option value="piece">بالحبة</option>
                                <option value="weight">بالوزن</option>
                                <option value="volume">بالحجم</option>
                              </select>
                            </label>
                            <label className="space-y-1">
                              <span className="text-xs font-medium">السعر / {unitLabel(editSaleType)}</span>
                              <input type="number" min="0.001" step="0.001" value={editPrice} onChange={(e) => setEditPrice(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
                            </label>
                            <label className="space-y-1">
                              <span className="text-xs font-medium">المخزون ({unitLabel(editSaleType)})</span>
                              <input type="number" min="0" step={editSaleType === "piece" ? "1" : "0.001"} value={editStock} onChange={(e) => setEditStock(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
                            </label>
                            <label className="space-y-1">
                              <span className="text-xs font-medium">التصنيف</span>
                              <select value={editCategoryId} onChange={(e) => setEditCategoryId(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                                <option value="">بدون تصنيف</option>
                                {categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}
                              </select>
                            </label>
                            {editSaleType !== "piece" && (
                              <>
                                <label className="space-y-1">
                                  <span className="text-xs font-medium">أقل كمية ({smallUnitLabel(editSaleType)})</span>
                                  <input type="number" min="1" step="1" value={editMinQty} onChange={(e) => setEditMinQty(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
                                </label>
                                <label className="space-y-1">
                                  <span className="text-xs font-medium">خطوة الكمية ({smallUnitLabel(editSaleType)})</span>
                                  <input type="number" min="1" step="1" value={editQtyStep} onChange={(e) => setEditQtyStep(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
                                </label>
                                <label className="flex items-center gap-2 rounded-lg border px-3 py-2 text-sm">
                                  <input type="checkbox" checked={editAllowAmountPurchase} onChange={(e) => setEditAllowAmountPurchase(e.target.checked)} />
                                  شراء حسب المبلغ
                                </label>
                              </>
                            )}
                            <label className="space-y-1">
                              <span className="text-xs font-medium">التوفر</span>
                              <select value={editAvailable ? "yes" : "no"} onChange={(e) => setEditAvailable(e.target.value === "yes")} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                                <option value="yes">متوفر</option>
                                <option value="no">غير متوفر</option>
                              </select>
                            </label>
                            <div className="sm:col-span-2 lg:col-span-4">
                              <BarcodeField supabase={supabase} storeId={storeId} productId={product.id} value={editBarcode} onChange={setEditBarcode} disabled={savingProductEdit} />
                            </div>
                            <label className="space-y-1 lg:col-span-2">
                              <span className="text-xs font-medium">صورة جديدة</span>
                              <input id="edit-product-image" type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => setEditImageFile(e.target.files?.[0] ?? null)} className="block w-full text-sm" />
                            </label>
                            {product.image_url && (
                              <label className="flex items-center gap-2 text-sm">
                                <input type="checkbox" checked={editRemoveImage} onChange={(e) => setEditRemoveImage(e.target.checked)} /> حذف الصورة الحالية
                              </label>
                            )}
                          </div>
                          {editError && <p className="mt-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{editError}</p>}
                          <div className="mt-4 flex gap-2">
                            <button type="button" disabled={savingProductEdit} onClick={() => void saveProductEdit(product)} className="rounded-lg bg-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">{savingProductEdit ? "جاري الحفظ..." : "حفظ"}</button>
                            <button type="button" onClick={cancelProductEdit} className="rounded-lg border border-gray-300 px-4 py-2 text-sm">إلغاء</button>
                          </div>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
