"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Product = {
  id: string;
  name: string;
  price_per_unit: number | null;
  sale_type: string | null;
  base_unit: string | null;
  is_available: boolean;
};

type Offer = {
  id: string;
  product_id: string;
  title: string;
  subtitle: string | null;
  regular_price_per_unit: number;
  offer_price_per_unit: number;
  ends_at: string | null;
  is_active: boolean;
  created_at: string;
  products: { name: string } | { name: string }[] | null;
};

function productName(offer: Offer) {
  if (Array.isArray(offer.products)) return offer.products[0]?.name || "منتج";
  return offer.products?.name || "منتج";
}

function money(value: number) {
  return `${Number(value).toFixed(2)} د.أ`;
}

export default function OffersManager({
  storeId,
  products,
  initialOffers,
}: {
  storeId: string;
  products: Product[];
  initialOffers: Offer[];
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [productId, setProductId] = useState(products[0]?.id || "");
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [offerPrice, setOfferPrice] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [notify, setNotify] = useState(true);
  const [busy, setBusy] = useState(false);
  const [endingId, setEndingId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const selected = products.find((product) => product.id === productId);
  const regular = Number(selected?.price_per_unit || 0);
  const activeOffers = initialOffers.filter((offer) => offer.is_active);
  const oldOffers = initialOffers.filter((offer) => !offer.is_active).slice(0, 20);

  async function createOffer(event: FormEvent) {
    event.preventDefault();
    if (!selected || busy) return;

    const price = Number(offerPrice);
    if (!Number.isFinite(price) || price <= 0 || price >= regular) {
      setMessage("سعر العرض لازم يكون أكبر من صفر وأقل من السعر الحالي.");
      return;
    }

    setBusy(true);
    setMessage(null);
    try {
      const { data, error } = await supabase.rpc("admin_create_product_offer", {
        p_store_id: storeId,
        p_product_id: selected.id,
        p_title: title.trim() || `عرض على ${selected.name}`,
        p_subtitle: subtitle.trim() || null,
        p_offer_price_per_unit: price,
        p_ends_at: endsAt ? new Date(endsAt).toISOString() : null,
        p_notify_customers: notify,
      });
      if (error) throw error;

      let pushNote = "";
      if (notify && typeof data === "string" && data) {
        try {
          const response = await supabase.functions.invoke("send-customer-push", {
            body: { offer_id: data },
          });
          if (response.error) pushNote = " تم إنشاء العرض، لكن الإشعار الخارجي لم يُرسل.";
        } catch {
          pushNote = " تم إنشاء العرض، لكن الإشعار الخارجي لم يُرسل.";
        }
      }

      setTitle("");
      setSubtitle("");
      setOfferPrice("");
      setEndsAt("");
      setMessage(`تم تفعيل العرض.${pushNote}`);
      router.refresh();
    } catch (error) {
      const text = error instanceof Error ? error.message : String(error);
      if (text.includes("ACTIVE_OFFER_EXISTS")) {
        setMessage("هذا المنتج عليه عرض فعّال حاليًا. أنهيه أولًا.");
      } else {
        setMessage(text);
      }
    } finally {
      setBusy(false);
    }
  }

  async function endOffer(id: string) {
    if (endingId) return;
    setEndingId(id);
    setMessage(null);
    try {
      const { error } = await supabase.rpc("admin_end_product_offer", {
        p_offer_id: id,
      });
      if (error) throw error;
      setMessage("تم إنهاء العرض وإرجاع السعر العادي.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setEndingId(null);
    }
  }

  return (
    <div className="space-y-6">
      <form
        onSubmit={createOffer}
        className="grid gap-4 rounded-2xl border border-gray-200 bg-white p-5 lg:grid-cols-2"
      >
        <label className="space-y-1 text-sm font-medium">
          <span>المنتج</span>
          <select
            value={productId}
            onChange={(event) => setProductId(event.target.value)}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
            required
          >
            {products.map((product) => (
              <option key={product.id} value={product.id}>
                {product.name} — {money(Number(product.price_per_unit || 0))}
              </option>
            ))}
          </select>
        </label>

        <label className="space-y-1 text-sm font-medium">
          <span>سعر العرض {regular > 0 ? `(العادي ${money(regular)})` : ""}</span>
          <input
            type="number"
            min="0.001"
            step="0.001"
            value={offerPrice}
            onChange={(event) => setOfferPrice(event.target.value)}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
            placeholder="مثال: 1.250"
            required
          />
        </label>

        <label className="space-y-1 text-sm font-medium">
          <span>عنوان العرض</span>
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
            placeholder={selected ? `عرض على ${selected.name}` : "عرض خاص"}
          />
        </label>

        <label className="space-y-1 text-sm font-medium">
          <span>وصف قصير</span>
          <input
            value={subtitle}
            onChange={(event) => setSubtitle(event.target.value)}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
            placeholder="مثال: عرض نهاية الأسبوع"
          />
        </label>

        <label className="space-y-1 text-sm font-medium">
          <span>ينتهي في (اختياري)</span>
          <input
            type="datetime-local"
            value={endsAt}
            onChange={(event) => setEndsAt(event.target.value)}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
          />
        </label>

        <div className="flex items-end">
          <label className="flex items-center gap-2 rounded-xl bg-gray-50 px-3 py-2.5 text-sm">
            <input
              type="checkbox"
              checked={notify}
              onChange={(event) => setNotify(event.target.checked)}
            />
            أرسل إشعار للزبائن
          </label>
        </div>

        <div className="lg:col-span-2">
          <button
            type="submit"
            disabled={busy || !products.length}
            className="rounded-xl bg-brand px-5 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
          >
            {busy ? "جاري التفعيل..." : "تفعيل العرض"}
          </button>
        </div>
      </form>

      {message ? (
        <div className="rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm">
          {message}
        </div>
      ) : null}

      <section className="space-y-3">
        <h2 className="font-semibold">العروض الفعّالة ({activeOffers.length})</h2>
        {activeOffers.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-gray-300 bg-white p-8 text-center text-sm text-gray-500">
            ما في عروض فعّالة حاليًا.
          </div>
        ) : (
          activeOffers.map((offer) => (
            <div
              key={offer.id}
              className="flex flex-col gap-3 rounded-2xl border border-orange-200 bg-orange-50 p-4 sm:flex-row sm:items-center"
            >
              <div className="min-w-0 flex-1">
                <p className="font-semibold">{offer.title}</p>
                <p className="text-sm text-gray-600">{productName(offer)}</p>
                <p className="mt-1 text-sm">
                  <span className="line-through text-gray-400">
                    {money(offer.regular_price_per_unit)}
                  </span>{" "}
                  <span className="font-bold text-orange-700">
                    {money(offer.offer_price_per_unit)}
                  </span>
                </p>
                {offer.ends_at ? (
                  <p className="mt-1 text-xs text-gray-500">
                    ينتهي: {new Date(offer.ends_at).toLocaleString("ar-JO")}
                  </p>
                ) : null}
              </div>
              <button
                type="button"
                disabled={endingId === offer.id}
                onClick={() => endOffer(offer.id)}
                className="rounded-xl border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 disabled:opacity-50"
              >
                {endingId === offer.id ? "جاري الإنهاء..." : "إنهاء العرض"}
              </button>
            </div>
          ))
        )}
      </section>

      {oldOffers.length > 0 ? (
        <section className="space-y-2">
          <h2 className="font-semibold">العروض السابقة</h2>
          <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white">
            {oldOffers.map((offer) => (
              <div
                key={offer.id}
                className="flex items-center justify-between gap-4 border-b border-gray-100 px-4 py-3 last:border-b-0"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{offer.title}</p>
                  <p className="truncate text-xs text-gray-500">{productName(offer)}</p>
                </div>
                <span className="text-xs text-gray-500">{money(offer.offer_price_per_unit)}</span>
              </div>
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
