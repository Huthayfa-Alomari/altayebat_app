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
  stock_qty: number | null;
};

type Offer = {
  id: string;
  product_id: string;
  title: string;
  subtitle: string | null;
  regular_price_per_unit: number;
  offer_price_per_unit: number;
  starts_at: string | null;
  ends_at: string | null;
  is_active: boolean;
  ended_at: string | null;
  created_at: string;
  products: { name: string } | { name: string }[] | null;
};

type StorefrontSettings = {
  show_offers_section: boolean;
  offer_banner_title: string;
  offer_banner_subtitle: string;
};

function productName(offer: Offer) {
  if (Array.isArray(offer.products)) return offer.products[0]?.name || "منتج";
  return offer.products?.name || "منتج";
}

function money(value: number) {
  return `${Number(value).toFixed(2)} د.أ`;
}

function localDateTimeValue(date: Date) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours(),
  )}:${pad(date.getMinutes())}`;
}

function offerStatus(offer: Offer) {
  const now = Date.now();
  const start = offer.starts_at ? new Date(offer.starts_at).getTime() : 0;
  const end = offer.ends_at ? new Date(offer.ends_at).getTime() : Number.POSITIVE_INFINITY;

  if (offer.ended_at || end <= now) return "ended" as const;
  if (offer.is_active) return "active" as const;
  if (start > now) return "scheduled" as const;
  return "paused" as const;
}

export default function OffersManager({
  storeId,
  products,
  initialOffers,
  initialSettings,
}: {
  storeId: string;
  products: Product[];
  initialOffers: Offer[];
  initialSettings: StorefrontSettings;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [search, setSearch] = useState("");
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [prices, setPrices] = useState<Record<string, string>>({});
  const [discountPercent, setDiscountPercent] = useState("10");
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [notify, setNotify] = useState(true);
  const [busy, setBusy] = useState(false);
  const [endingId, setEndingId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const [showOffersSection, setShowOffersSection] = useState(
    initialSettings.show_offers_section,
  );
  const [bannerTitle, setBannerTitle] = useState(
    initialSettings.offer_banner_title,
  );
  const [bannerSubtitle, setBannerSubtitle] = useState(
    initialSettings.offer_banner_subtitle,
  );
  const [settingsBusy, setSettingsBusy] = useState(false);

  const visibleProducts = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return products;
    return products.filter((product) => product.name.toLowerCase().includes(q));
  }, [products, search]);

  const selectedProducts = useMemo(
    () => products.filter((product) => selectedIds.includes(product.id)),
    [products, selectedIds],
  );

  const activeOffers = initialOffers.filter(
    (offer) => offerStatus(offer) === "active",
  );
  const scheduledOffers = initialOffers.filter(
    (offer) => offerStatus(offer) === "scheduled",
  );
  const oldOffers = initialOffers
    .filter((offer) => ["ended", "paused"].includes(offerStatus(offer)))
    .slice(0, 30);

  function toggleProduct(product: Product) {
    setSelectedIds((current) => {
      if (current.includes(product.id)) {
        setPrices((currentPrices) => {
          const next = { ...currentPrices };
          delete next[product.id];
          return next;
        });
        return current.filter((id) => id !== product.id);
      }
      return [...current, product.id];
    });
  }

  function selectVisible() {
    setSelectedIds((current) => {
      const next = new Set(current);
      for (const product of visibleProducts) next.add(product.id);
      return [...next];
    });
  }

  function clearSelection() {
    setSelectedIds([]);
    setPrices({});
  }

  function applyDiscountPercent() {
    const percent = Number(discountPercent);
    if (!Number.isFinite(percent) || percent <= 0 || percent >= 100) {
      setMessage("اكتب نسبة خصم صحيحة بين 1 و99.");
      return;
    }
    if (!selectedProducts.length) {
      setMessage("حدد صنفًا واحدًا على الأقل أولًا.");
      return;
    }

    setPrices((current) => {
      const next = { ...current };
      for (const product of selectedProducts) {
        const regular = Number(product.price_per_unit || 0);
        if (regular > 0) {
          next[product.id] = (regular * (1 - percent / 100)).toFixed(3);
        }
      }
      return next;
    });
    setMessage(`تم تطبيق خصم ${percent}% مبدئيًا. تقدر تعدّل سعر أي صنف لحاله.`);
  }

  function startNow() {
    const now = new Date();
    now.setSeconds(0, 0);
    setStartsAt(localDateTimeValue(now));
  }

  function endAfter(hours: number) {
    const base = startsAt ? new Date(startsAt) : new Date();
    if (Number.isNaN(base.getTime())) return;
    base.setHours(base.getHours() + hours);
    setEndsAt(localDateTimeValue(base));
  }

  async function saveStorefrontSettings() {
    if (settingsBusy) return;
    setSettingsBusy(true);
    setMessage(null);
    try {
      const { error } = await supabase.from("storefront_settings").upsert({
        store_id: storeId,
        show_offers_section: showOffersSection,
        offer_banner_title: bannerTitle.trim() || "عروض مميزة اليوم",
        offer_banner_subtitle:
          bannerSubtitle.trim() || "وفر أكثر مع عروض أسواق الطيبات",
        updated_at: new Date().toISOString(),
      });
      if (error) throw error;
      setMessage(
        showOffersSection
          ? "تم إظهار قسم العروض والبنر داخل التطبيق."
          : "تم إخفاء قسم العروض والبنر من التطبيق.",
      );
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setSettingsBusy(false);
    }
  }

  async function createCampaign(event: FormEvent) {
    event.preventDefault();
    if (busy) return;

    if (!selectedProducts.length) {
      setMessage("حدد صنفًا واحدًا على الأقل من البضاعة.");
      return;
    }
    if (!startsAt || !endsAt) {
      setMessage("حدد وقت بداية ووقت نهاية العرض.");
      return;
    }

    const start = new Date(startsAt);
    const end = new Date(endsAt);
    if (
      Number.isNaN(start.getTime()) ||
      Number.isNaN(end.getTime()) ||
      end <= start
    ) {
      setMessage("وقت نهاية العرض لازم يكون بعد وقت البداية.");
      return;
    }
    if (end <= new Date()) {
      setMessage("وقت نهاية العرض لازم يكون بالمستقبل.");
      return;
    }

    const items = [] as Array<{
      product_id: string;
      offer_price_per_unit: number;
    }>;

    for (const product of selectedProducts) {
      const regular = Number(product.price_per_unit || 0);
      const price = Number(prices[product.id]);
      if (!Number.isFinite(price) || price <= 0 || price >= regular) {
        setMessage(
          `راجع سعر العرض للصنف «${product.name}». لازم يكون أقل من ${money(regular)}.`,
        );
        return;
      }
      items.push({ product_id: product.id, offer_price_per_unit: price });
    }

    setBusy(true);
    setMessage(null);
    try {
      const { data, error } = await supabase.rpc("admin_create_offer_campaign", {
        p_store_id: storeId,
        p_items: items,
        p_title: title.trim() || "عروض الطيبات",
        p_subtitle: subtitle.trim() || null,
        p_starts_at: start.toISOString(),
        p_ends_at: end.toISOString(),
        p_notify_customers: notify,
      });
      if (error) throw error;

      const response = data as {
        offer_count?: number;
        active_now?: boolean;
      } | null;
      const count = Number(response?.offer_count || items.length);
      setMessage(
        response?.active_now
          ? `تم تشغيل الحملة على ${count} صنف الآن.`
          : `تمت جدولة الحملة على ${count} صنف وستبدأ تلقائيًا بالوقت المحدد.`,
      );
      clearSelection();
      setTitle("");
      setSubtitle("");
      setStartsAt("");
      setEndsAt("");
      router.refresh();
    } catch (error) {
      const text = error instanceof Error ? error.message : String(error);
      if (text.includes("OFFER_WINDOW_OVERLAP")) {
        setMessage("في صنف محدد عنده عرض آخر يتداخل مع نفس الفترة. عدّل الفترة أو الاختيار.");
      } else if (text.includes("OFFER_PRICE_MUST_BE_LOWER")) {
        setMessage("أحد أسعار العرض غير صالح أو ليس أقل من السعر العادي.");
      } else if (text.includes("admin_create_offer_campaign")) {
        setMessage("ميزة حملات العروض تحتاج تشغيل migration الجديدة على Supabase أولًا.");
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
      setMessage("تم إنهاء العرض وإرجاع السعر العادي إذا كان العرض شغالًا.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setEndingId(null);
    }
  }

  return (
    <div className="space-y-6">
      <section className="rounded-2xl border border-sky-200 bg-gradient-to-l from-sky-50 via-white to-red-50 p-5">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p className="text-sm font-semibold text-sky-800">واجهة العروض في التطبيق</p>
            <h2 className="mt-1 text-lg font-bold">إظهار / إخفاء قسم العروض والبنر</h2>
            <p className="mt-1 text-xs text-gray-600">
              العروض تبقى محفوظة ومجدولة حتى لو أخفيت القسم عن الزبائن.
            </p>
          </div>
          <label className="flex items-center gap-3 rounded-xl border border-sky-200 bg-white px-4 py-3 text-sm font-semibold">
            <input
              type="checkbox"
              checked={showOffersSection}
              onChange={(event) => setShowOffersSection(event.target.checked)}
              className="h-5 w-5"
            />
            {showOffersSection ? "ظاهر داخل التطبيق" : "مخفي عن التطبيق"}
          </label>
        </div>

        <div className="mt-4 grid gap-3 lg:grid-cols-2">
          <label className="space-y-1 text-sm font-medium">
            <span>عنوان البنر</span>
            <input
              value={bannerTitle}
              onChange={(event) => setBannerTitle(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5"
              placeholder="عروض مميزة اليوم"
            />
          </label>
          <label className="space-y-1 text-sm font-medium">
            <span>النص تحت العنوان</span>
            <input
              value={bannerSubtitle}
              onChange={(event) => setBannerSubtitle(event.target.value)}
              className="w-full rounded-xl border border-gray-300 bg-white px-3 py-2.5"
              placeholder="وفر أكثر مع عروض أسواق الطيبات"
            />
          </label>
        </div>

        <button
          type="button"
          onClick={() => void saveStorefrontSettings()}
          disabled={settingsBusy}
          className="mt-4 rounded-xl bg-sky-600 px-5 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
        >
          {settingsBusy ? "جاري الحفظ..." : "حفظ إعدادات العرض"}
        </button>
      </section>

      <form
        onSubmit={createCampaign}
        className="space-y-5 rounded-2xl border border-gray-200 bg-white p-5"
      >
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-lg font-bold">إنشاء حملة عروض</h2>
            <p className="text-sm text-gray-500">
              اختَر الأصناف من مخزون المول، ثم حدد سعر العرض والفترة.
            </p>
          </div>
          <span className="rounded-full bg-sky-50 px-3 py-1.5 text-xs font-bold text-sky-700">
            محدد: {selectedProducts.length}
          </span>
        </div>

        <div className="grid gap-4 lg:grid-cols-2">
          <label className="space-y-1 text-sm font-medium">
            <span>عنوان الحملة</span>
            <input
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
              placeholder="مثال: عروض نهاية الأسبوع"
            />
          </label>
          <label className="space-y-1 text-sm font-medium">
            <span>وصف قصير</span>
            <input
              value={subtitle}
              onChange={(event) => setSubtitle(event.target.value)}
              className="w-full rounded-xl border border-gray-300 px-3 py-2.5"
              placeholder="مثال: أسعار خاصة حتى السبت"
            />
          </label>

          <label className="space-y-1 text-sm font-medium">
            <span>تبدأ في</span>
            <div className="flex gap-2">
              <input
                type="datetime-local"
                value={startsAt}
                onChange={(event) => setStartsAt(event.target.value)}
                className="min-w-0 flex-1 rounded-xl border border-gray-300 px-3 py-2.5"
                required
              />
              <button
                type="button"
                onClick={startNow}
                className="rounded-xl border border-gray-200 px-3 text-xs font-semibold"
              >
                الآن
              </button>
            </div>
          </label>

          <label className="space-y-1 text-sm font-medium">
            <span>تنتهي في</span>
            <div className="flex gap-2">
              <input
                type="datetime-local"
                value={endsAt}
                onChange={(event) => setEndsAt(event.target.value)}
                className="min-w-0 flex-1 rounded-xl border border-gray-300 px-3 py-2.5"
                required
              />
              <button
                type="button"
                onClick={() => endAfter(24)}
                className="rounded-xl border border-gray-200 px-3 text-xs font-semibold"
              >
                +24س
              </button>
            </div>
          </label>
        </div>

        <div className="rounded-2xl border border-gray-200 bg-gray-50 p-4">
          <div className="flex flex-col gap-3 md:flex-row md:items-center">
            <input
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              className="min-w-0 flex-1 rounded-xl border border-gray-300 bg-white px-3 py-2.5 text-sm"
              placeholder="ابحث باسم الصنف..."
            />
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={selectVisible}
                className="rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs font-semibold"
              >
                تحديد الظاهر
              </button>
              <button
                type="button"
                onClick={clearSelection}
                className="rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs font-semibold text-gray-600"
              >
                مسح التحديد
              </button>
            </div>
          </div>

          <div className="mt-3 max-h-72 overflow-y-auto rounded-xl border border-gray-200 bg-white">
            {visibleProducts.length === 0 ? (
              <p className="p-6 text-center text-sm text-gray-500">ما في أصناف مطابقة.</p>
            ) : (
              visibleProducts.map((product) => {
                const checked = selectedIds.includes(product.id);
                return (
                  <label
                    key={product.id}
                    className={`flex cursor-pointer items-center gap-3 border-b border-gray-100 px-3 py-3 last:border-b-0 ${
                      checked ? "bg-sky-50" : "hover:bg-gray-50"
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() => toggleProduct(product)}
                      className="h-5 w-5"
                    />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold">{product.name}</p>
                      <p className="text-xs text-gray-500">
                        السعر {money(Number(product.price_per_unit || 0))}
                        {product.stock_qty !== null ? ` • المخزون ${product.stock_qty}` : ""}
                      </p>
                    </div>
                  </label>
                );
              })
            )}
          </div>
        </div>

        {selectedProducts.length > 0 ? (
          <section className="space-y-3">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <h3 className="font-bold">أسعار الأصناف المحددة</h3>
                <p className="text-xs text-gray-500">
                  لكل صنف سعر عرض مستقل، أو طبّق نسبة خصم سريعة ثم عدّل يدويًا.
                </p>
              </div>
              <div className="flex items-end gap-2">
                <label className="space-y-1 text-xs font-medium">
                  <span>خصم سريع %</span>
                  <input
                    type="number"
                    min="1"
                    max="99"
                    step="1"
                    value={discountPercent}
                    onChange={(event) => setDiscountPercent(event.target.value)}
                    className="w-24 rounded-xl border border-gray-300 px-3 py-2"
                  />
                </label>
                <button
                  type="button"
                  onClick={applyDiscountPercent}
                  className="rounded-xl bg-sky-100 px-3 py-2 text-xs font-bold text-sky-800"
                >
                  تطبيق
                </button>
              </div>
            </div>

            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              {selectedProducts.map((product) => (
                <div
                  key={product.id}
                  className="rounded-xl border border-sky-100 bg-sky-50/40 p-3"
                >
                  <p className="truncate text-sm font-bold">{product.name}</p>
                  <p className="mt-1 text-xs text-gray-500">
                    العادي: {money(Number(product.price_per_unit || 0))}
                  </p>
                  <input
                    type="number"
                    min="0.001"
                    step="0.001"
                    value={prices[product.id] || ""}
                    onChange={(event) =>
                      setPrices((current) => ({
                        ...current,
                        [product.id]: event.target.value,
                      }))
                    }
                    className="mt-2 w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-sm"
                    placeholder="سعر العرض"
                    required
                  />
                </div>
              ))}
            </div>
          </section>
        ) : null}

        <div className="flex flex-col gap-3 border-t border-gray-100 pt-4 sm:flex-row sm:items-center sm:justify-between">
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={notify}
              onChange={(event) => setNotify(event.target.checked)}
            />
            إظهار إشعار داخل التطبيق عند بدء الحملة
          </label>
          <button
            type="submit"
            disabled={busy || !selectedProducts.length}
            className="rounded-xl bg-brand px-6 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
          >
            {busy ? "جاري الحفظ..." : `حفظ الحملة (${selectedProducts.length} صنف)`}
          </button>
        </div>
      </form>

      {message ? (
        <div className="rounded-xl border border-gray-200 bg-white px-4 py-3 text-sm">
          {message}
        </div>
      ) : null}

      {scheduledOffers.length > 0 ? (
        <OfferList
          title={`العروض المجدولة (${scheduledOffers.length})`}
          offers={scheduledOffers}
          endingId={endingId}
          onEnd={endOffer}
          tone="sky"
        />
      ) : null}

      <OfferList
        title={`العروض الفعّالة (${activeOffers.length})`}
        offers={activeOffers}
        endingId={endingId}
        onEnd={endOffer}
        tone="orange"
      />

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
                <span className="text-xs text-gray-500">
                  {money(offer.offer_price_per_unit)}
                </span>
              </div>
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}

function OfferList({
  title,
  offers,
  endingId,
  onEnd,
  tone,
}: {
  title: string;
  offers: Offer[];
  endingId: string | null;
  onEnd: (id: string) => Promise<void>;
  tone: "sky" | "orange";
}) {
  return (
    <section className="space-y-3">
      <h2 className="font-semibold">{title}</h2>
      {offers.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-gray-300 bg-white p-8 text-center text-sm text-gray-500">
          ما في عروض ضمن هذه الحالة.
        </div>
      ) : (
        offers.map((offer) => (
          <div
            key={offer.id}
            className={`flex flex-col gap-3 rounded-2xl border p-4 sm:flex-row sm:items-center ${
              tone === "sky"
                ? "border-sky-200 bg-sky-50"
                : "border-orange-200 bg-orange-50"
            }`}
          >
            <div className="min-w-0 flex-1">
              <p className="font-semibold">{offer.title}</p>
              <p className="text-sm text-gray-600">{productName(offer)}</p>
              <p className="mt-1 text-sm">
                <span className="line-through text-gray-400">
                  {money(offer.regular_price_per_unit)}
                </span>{" "}
                <span
                  className={`font-bold ${
                    tone === "sky" ? "text-sky-700" : "text-orange-700"
                  }`}
                >
                  {money(offer.offer_price_per_unit)}
                </span>
              </p>
              <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500">
                {offer.starts_at ? (
                  <span>يبدأ: {new Date(offer.starts_at).toLocaleString("ar-JO")}</span>
                ) : null}
                {offer.ends_at ? (
                  <span>ينتهي: {new Date(offer.ends_at).toLocaleString("ar-JO")}</span>
                ) : null}
              </div>
            </div>
            <button
              type="button"
              disabled={endingId === offer.id}
              onClick={() => void onEnd(offer.id)}
              className="rounded-xl border border-red-200 bg-white px-4 py-2 text-sm font-medium text-red-700 disabled:opacity-50"
            >
              {endingId === offer.id ? "جاري الإنهاء..." : "إنهاء العرض"}
            </button>
          </div>
        ))
      )}
    </section>
  );
}
