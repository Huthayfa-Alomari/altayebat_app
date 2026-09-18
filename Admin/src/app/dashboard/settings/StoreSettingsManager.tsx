"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type StoreRow = {
  name: string;
  logo_url: string | null;
  primary_color: string | null;
  phone: string | null;
  address: string | null;
  delivery_fee: number | string | null;
  min_order: number | string | null;
  accepts_orders: boolean;
  prep_time_min_minutes: number | null;
  prep_time_max_minutes: number | null;
  cliq_alias: string | null;
  cliq_recipient_name: string | null;
};

type PublicSettings = {
  facebook_url: string;
  instagram_url: string;
  tiktok_url: string;
  website_url: string;
  google_maps_url: string;
  facebook_enabled: boolean;
  instagram_enabled: boolean;
  whatsapp_number: string;
  whatsapp_enabled: boolean;
  whatsapp_default_message: string;
  support_phone: string;
  support_whatsapp_number: string;
  support_hours_text: string;
  privacy_policy_url: string;
  terms_url: string;
  play_store_url: string;
  app_store_url: string;
  store_status: "open" | "busy" | "temporarily_closed" | "maintenance";
  status_message: string;
  allow_scheduled_orders_when_closed: boolean;
  announcement_enabled: boolean;
  announcement_title: string;
  announcement_body: string;
  announcement_action_label: string;
  announcement_action_url: string;
  announcement_style: "info" | "sale" | "warning";
  feature_ai: boolean;
  feature_offers: boolean;
  feature_loyalty: boolean;
  feature_ads: boolean;
  feature_call: boolean;
  feature_whatsapp: boolean;
  feature_reorder: boolean;
  feature_referral: boolean;
  maintenance_checkout: boolean;
  maintenance_payments: boolean;
  maintenance_delivery: boolean;
  welcome_text: string;
  share_message: string;
};

type ReferralSettings = {
  is_enabled: boolean;
  program_name: string;
  min_first_order_total: number;
  referrer_reward_count: number;
  referred_reward_count: number;
  max_referrer_rewards_per_customer: number;
  reward_title: string;
  terms_text: string;
};

type StoreForm = {
  name: string;
  logoUrl: string;
  primaryColor: string;
  phone: string;
  address: string;
  deliveryFee: number;
  minOrder: number;
  acceptsOrders: boolean;
  prepMin: number;
  prepMax: number;
  cliqAlias: string;
  cliqRecipientName: string;
};

type HourRow = {
  day: number;
  configured: boolean;
  isClosed: boolean;
  openTime: string;
  closeTime: string;
  closesNextDay: boolean;
};

const dayNames = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];

const defaultPublic: PublicSettings = {
  facebook_url: "",
  instagram_url: "",
  tiktok_url: "",
  website_url: "",
  google_maps_url: "",
  facebook_enabled: true,
  instagram_enabled: true,
  whatsapp_number: "",
  whatsapp_enabled: true,
  whatsapp_default_message: "مرحباً أسواق الطيبات، أحتاج مساعدة بخصوص طلبي.",
  support_phone: "",
  support_whatsapp_number: "",
  support_hours_text: "",
  privacy_policy_url: "",
  terms_url: "",
  play_store_url: "",
  app_store_url: "",
  store_status: "open",
  status_message: "",
  allow_scheduled_orders_when_closed: false,
  announcement_enabled: false,
  announcement_title: "",
  announcement_body: "",
  announcement_action_label: "",
  announcement_action_url: "",
  announcement_style: "info",
  feature_ai: true,
  feature_offers: true,
  feature_loyalty: true,
  feature_ads: true,
  feature_call: true,
  feature_whatsapp: true,
  feature_reorder: true,
  feature_referral: true,
  maintenance_checkout: false,
  maintenance_payments: false,
  maintenance_delivery: false,
  welcome_text: "كل احتياجات البيت بمكان واحد",
  share_message: "حمّل تطبيق أسواق الطيبات وتسوق بسهولة.",
};

const defaultReferral: ReferralSettings = {
  is_enabled: false,
  program_name: "ادعُ صديقك",
  min_first_order_total: 5,
  referrer_reward_count: 1,
  referred_reward_count: 1,
  max_referrer_rewards_per_customer: 20,
  reward_title: "مكافأة دعوة صديق",
  terms_text: "تُمنح المكافأة بعد تسليم أول طلب مؤهل للصديق.",
};

function textValue(value: unknown) {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function booleanValue(value: unknown, fallback = false) {
  return typeof value === "boolean" ? value : fallback;
}

export default function StoreSettingsManager({
  storeId,
  storeName,
}: {
  storeId: string;
  storeName: string;
}) {
  const supabase = useMemo(() => createClient(), []);

  const [store, setStore] = useState<StoreForm | null>(null);
  const [publicSettings, setPublicSettings] = useState<PublicSettings>(defaultPublic);
  const [referral, setReferral] = useState<ReferralSettings>(defaultReferral);
  const [hours, setHours] = useState<HourRow[]>(
    dayNames.map((_, day) => ({
      day,
      configured: false,
      isClosed: false,
      openTime: "",
      closeTime: "",
      closesNextDay: false,
    })),
  );
  const [engagement, setEngagement] = useState<Record<string, unknown>>({});
  const [cardReady, setCardReady] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [checkingCard, setCheckingCard] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storeId]);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const [storeResult, publicResult, hoursResult, referralResult, engagementResult] =
        await Promise.all([
          supabase
            .from("stores")
            .select(
              "name,logo_url,primary_color,phone,address,delivery_fee,min_order,accepts_orders,prep_time_min_minutes,prep_time_max_minutes,cliq_alias,cliq_recipient_name",
            )
            .eq("id", storeId)
            .single(),
          supabase
            .from("store_public_settings")
            .select("*")
            .eq("store_id", storeId)
            .maybeSingle(),
          supabase
            .from("store_hours")
            .select("day_of_week,open_time,close_time,is_closed,closes_next_day")
            .eq("store_id", storeId)
            .order("day_of_week"),
          supabase
            .from("referral_programs")
            .select("*")
            .eq("store_id", storeId)
            .maybeSingle(),
          supabase.rpc("admin_store_engagement_summary", { p_store_id: storeId }),
        ]);

      if (storeResult.error) throw storeResult.error;
      if (publicResult.error) throw publicResult.error;
      if (hoursResult.error) throw hoursResult.error;
      if (referralResult.error) throw referralResult.error;

      const rawStore = storeResult.data as StoreRow;
      setStore({
        name: rawStore.name ?? storeName,
        logoUrl: rawStore.logo_url ?? "",
        primaryColor: rawStore.primary_color ?? "#E31E24",
        phone: rawStore.phone ?? "",
        address: rawStore.address ?? "",
        deliveryFee: numberValue(rawStore.delivery_fee),
        minOrder: numberValue(rawStore.min_order),
        acceptsOrders: rawStore.accepts_orders !== false,
        prepMin: numberValue(rawStore.prep_time_min_minutes, 10),
        prepMax: numberValue(rawStore.prep_time_max_minutes, 30),
        cliqAlias: rawStore.cliq_alias ?? "",
        cliqRecipientName: rawStore.cliq_recipient_name ?? "",
      });

      const rawPublic = (publicResult.data ?? {}) as Record<string, unknown>;
      setPublicSettings({
        ...defaultPublic,
        facebook_url: textValue(rawPublic.facebook_url),
        instagram_url: textValue(rawPublic.instagram_url),
        tiktok_url: textValue(rawPublic.tiktok_url),
        website_url: textValue(rawPublic.website_url),
        google_maps_url: textValue(rawPublic.google_maps_url),
        facebook_enabled: booleanValue(rawPublic.facebook_enabled, true),
        instagram_enabled: booleanValue(rawPublic.instagram_enabled, true),
        whatsapp_number: textValue(rawPublic.whatsapp_number),
        whatsapp_enabled: booleanValue(rawPublic.whatsapp_enabled, true),
        whatsapp_default_message:
          textValue(rawPublic.whatsapp_default_message) || defaultPublic.whatsapp_default_message,
        support_phone: textValue(rawPublic.support_phone),
        support_whatsapp_number: textValue(rawPublic.support_whatsapp_number),
        support_hours_text: textValue(rawPublic.support_hours_text),
        privacy_policy_url: textValue(rawPublic.privacy_policy_url),
        terms_url: textValue(rawPublic.terms_url),
        play_store_url: textValue(rawPublic.play_store_url),
        app_store_url: textValue(rawPublic.app_store_url),
        store_status:
          (textValue(rawPublic.store_status) as PublicSettings["store_status"]) || "open",
        status_message: textValue(rawPublic.status_message),
        allow_scheduled_orders_when_closed: booleanValue(
          rawPublic.allow_scheduled_orders_when_closed,
        ),
        announcement_enabled: booleanValue(rawPublic.announcement_enabled),
        announcement_title: textValue(rawPublic.announcement_title),
        announcement_body: textValue(rawPublic.announcement_body),
        announcement_action_label: textValue(rawPublic.announcement_action_label),
        announcement_action_url: textValue(rawPublic.announcement_action_url),
        announcement_style:
          (textValue(rawPublic.announcement_style) as PublicSettings["announcement_style"]) ||
          "info",
        feature_ai: booleanValue(rawPublic.feature_ai, true),
        feature_offers: booleanValue(rawPublic.feature_offers, true),
        feature_loyalty: booleanValue(rawPublic.feature_loyalty, true),
        feature_ads: booleanValue(rawPublic.feature_ads, true),
        feature_call: booleanValue(rawPublic.feature_call, true),
        feature_whatsapp: booleanValue(rawPublic.feature_whatsapp, true),
        feature_reorder: booleanValue(rawPublic.feature_reorder, true),
        feature_referral: booleanValue(rawPublic.feature_referral, true),
        maintenance_checkout: booleanValue(rawPublic.maintenance_checkout),
        maintenance_payments: booleanValue(rawPublic.maintenance_payments),
        maintenance_delivery: booleanValue(rawPublic.maintenance_delivery),
        welcome_text: textValue(rawPublic.welcome_text) || defaultPublic.welcome_text,
        share_message: textValue(rawPublic.share_message) || defaultPublic.share_message,
      });

      const rawHours = (hoursResult.data ?? []) as Array<Record<string, unknown>>;
      setHours(
        dayNames.map((_, day) => {
          const row = rawHours.find((item) => Number(item.day_of_week) === day);
          return {
            day,
            configured: !!row,
            isClosed: row ? booleanValue(row.is_closed) : false,
            openTime: row ? textValue(row.open_time).slice(0, 5) : "",
            closeTime: row ? textValue(row.close_time).slice(0, 5) : "",
            closesNextDay: row ? booleanValue(row.closes_next_day) : false,
          };
        }),
      );

      const rawReferral = (referralResult.data ?? {}) as Record<string, unknown>;
      setReferral({
        is_enabled: booleanValue(rawReferral.is_enabled),
        program_name: textValue(rawReferral.program_name) || defaultReferral.program_name,
        min_first_order_total: numberValue(
          rawReferral.min_first_order_total,
          defaultReferral.min_first_order_total,
        ),
        referrer_reward_count: numberValue(
          rawReferral.referrer_reward_count,
          defaultReferral.referrer_reward_count,
        ),
        referred_reward_count: numberValue(
          rawReferral.referred_reward_count,
          defaultReferral.referred_reward_count,
        ),
        max_referrer_rewards_per_customer: numberValue(
          rawReferral.max_referrer_rewards_per_customer,
          defaultReferral.max_referrer_rewards_per_customer,
        ),
        reward_title: textValue(rawReferral.reward_title) || defaultReferral.reward_title,
        terms_text: textValue(rawReferral.terms_text) || defaultReferral.terms_text,
      });

      if (!engagementResult.error && engagementResult.data) {
        setEngagement(engagementResult.data as Record<string, unknown>);
      }

      await checkCardReadiness();
    } catch (err) {
      setError(message(err));
    } finally {
      setLoading(false);
    }
  }

  async function checkCardReadiness() {
    setCheckingCard(true);
    try {
      const { data, error: functionError } = await supabase.functions.invoke(
        "payment-readiness",
        { body: {} },
      );
      setCardReady(
        !functionError &&
          !!data &&
          typeof data === "object" &&
          "card_enabled" in data &&
          data.card_enabled === true,
      );
    } finally {
      setCheckingCard(false);
    }
  }

  function validateHours() {
    for (const row of hours) {
      if (row.configured && !row.isClosed && (!row.openTime || !row.closeTime)) {
        throw new Error(`حدد وقت الفتح والإغلاق ليوم ${dayNames[row.day]}.`);
      }
    }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!store || saving) return;

    setSaving(true);
    setError(null);
    setSaved(null);

    try {
      validateHours();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("انتهت الجلسة. سجّل الدخول مرة ثانية.");

      const profileResult = await supabase.rpc("admin_update_store_profile", {
        p_store_id: storeId,
        p_name: store.name,
        p_logo_url: store.logoUrl,
        p_primary_color: store.primaryColor,
        p_phone: store.phone,
        p_address: store.address,
        p_delivery_fee: store.deliveryFee,
        p_min_order: store.minOrder,
        p_accepts_orders: store.acceptsOrders,
        p_prep_time_min_minutes: store.prepMin,
        p_prep_time_max_minutes: store.prepMax,
      });
      if (profileResult.error) throw profileResult.error;

      const paymentResult = await supabase.rpc("admin_update_store_payment_config", {
        p_store_id: storeId,
        p_cliq_alias: store.cliqAlias,
        p_cliq_recipient_name: store.cliqRecipientName,
        p_phone: store.phone,
      });
      if (paymentResult.error) throw paymentResult.error;

      const publicResult = await supabase.from("store_public_settings").upsert({
        store_id: storeId,
        ...publicSettings,
        updated_at: new Date().toISOString(),
        updated_by: user.id,
      });
      if (publicResult.error) throw publicResult.error;

      const deleteHours = await supabase
        .from("store_hours")
        .delete()
        .eq("store_id", storeId);
      if (deleteHours.error) throw deleteHours.error;

      const configuredHours = hours
        .filter((row) => row.configured)
        .map((row) => ({
          store_id: storeId,
          day_of_week: row.day,
          is_closed: row.isClosed,
          open_time: row.isClosed ? null : row.openTime,
          close_time: row.isClosed ? null : row.closeTime,
          closes_next_day: row.isClosed ? false : row.closesNextDay,
          updated_at: new Date().toISOString(),
        }));

      if (configuredHours.length > 0) {
        const hoursResult = await supabase.from("store_hours").insert(configuredHours);
        if (hoursResult.error) throw hoursResult.error;
      }

      const referralResult = await supabase.from("referral_programs").upsert({
        store_id: storeId,
        ...referral,
        updated_at: new Date().toISOString(),
        updated_by: user.id,
      });
      if (referralResult.error) throw referralResult.error;

      const engagementResult = await supabase.rpc("admin_store_engagement_summary", {
        p_store_id: storeId,
      });
      if (!engagementResult.error && engagementResult.data) {
        setEngagement(engagementResult.data as Record<string, unknown>);
      }

      setSaved("تم حفظ إعدادات المتجر ونشرها للتطبيق.");
    } catch (err) {
      setError(message(err));
    } finally {
      setSaving(false);
    }
  }

  function updateHour(day: number, patch: Partial<HourRow>) {
    setHours((current) =>
      current.map((row) => (row.day === day ? { ...row, ...patch } : row)),
    );
  }

  function message(err: unknown) {
    if (err instanceof Error) return err.message;
    if (
      err &&
      typeof err === "object" &&
      "message" in err &&
      typeof err.message === "string"
    ) {
      return err.message;
    }
    return "حدث خطأ غير متوقع.";
  }

  const social = (engagement.social ?? {}) as Record<string, unknown>;
  const referrals = (engagement.referrals ?? {}) as Record<string, unknown>;

  if (loading || !store) {
    return (
      <div className="flex min-h-[55vh] items-center justify-center">
        <div className="text-sm text-gray-500">جاري تحميل إعدادات المتجر...</div>
      </div>
    );
  }

  return (
    <form onSubmit={save} className="mx-auto max-w-6xl space-y-6" dir="rtl">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-gray-950">إعدادات المتجر</h1>
          <p className="mt-1 text-sm text-gray-500">
            {storeName} — أي تغيير هنا ينعكس على التطبيق بدون إصدار جديد.
          </p>
        </div>
        <button
          type="submit"
          disabled={saving}
          className="rounded-xl bg-red-600 px-5 py-3 font-semibold text-white hover:bg-red-700 disabled:opacity-50"
        >
          {saving ? "جاري الحفظ..." : "حفظ ونشر الإعدادات"}
        </button>
      </header>

      {error && <Notice tone="error">{error}</Notice>}
      {saved && <Notice tone="success">{saved}</Notice>}

      <div className="grid gap-6 xl:grid-cols-2">
        <Section title="هوية المتجر" subtitle="الاسم والشعار والنص الظاهر للزبون.">
          <Field label="اسم المتجر">
            <input
              value={store.name}
              onChange={(e) => setStore({ ...store, name: e.target.value })}
              className="input"
              required
            />
          </Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="رابط الشعار">
              <input
                value={store.logoUrl}
                onChange={(e) => setStore({ ...store, logoUrl: e.target.value })}
                className="input text-left"
                dir="ltr"
                placeholder="https://..."
              />
            </Field>
            <Field label="اللون الأساسي">
              <input
                value={store.primaryColor}
                onChange={(e) => setStore({ ...store, primaryColor: e.target.value })}
                className="input text-left"
                dir="ltr"
                placeholder="#E31E24"
              />
            </Field>
          </div>
          <Field label="نص الترحيب">
            <input
              value={publicSettings.welcome_text}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, welcome_text: e.target.value })
              }
              className="input"
            />
          </Field>
          <Field label="رسالة مشاركة التطبيق">
            <textarea
              value={publicSettings.share_message}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, share_message: e.target.value })
              }
              className="input min-h-20"
            />
          </Field>
        </Section>

        <Section title="حالة المتجر والطلبات" subtitle="تحكم فوري في استقبال الطلبات وحالة التشغيل.">
          <Toggle
            label="استقبال الطلبات"
            checked={store.acceptsOrders}
            onChange={(value) => setStore({ ...store, acceptsOrders: value })}
          />
          <Field label="الحالة الظاهرة">
            <select
              className="input"
              value={publicSettings.store_status}
              onChange={(e) =>
                setPublicSettings({
                  ...publicSettings,
                  store_status: e.target.value as PublicSettings["store_status"],
                })
              }
            >
              <option value="open">مفتوح</option>
              <option value="busy">مزدحم</option>
              <option value="temporarily_closed">مغلق مؤقتًا</option>
              <option value="maintenance">صيانة</option>
            </select>
          </Field>
          <Field label="رسالة الحالة">
            <input
              value={publicSettings.status_message}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, status_message: e.target.value })
              }
              className="input"
              placeholder="مثال: ضغط طلبات مرتفع، قد يتأخر التوصيل."
            />
          </Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="أقل وقت تجهيز (دقيقة)">
              <input
                type="number"
                min={0}
                max={360}
                value={store.prepMin}
                onChange={(e) => setStore({ ...store, prepMin: Number(e.target.value) })}
                className="input"
              />
            </Field>
            <Field label="أقصى وقت تجهيز (دقيقة)">
              <input
                type="number"
                min={0}
                max={360}
                value={store.prepMax}
                onChange={(e) => setStore({ ...store, prepMax: Number(e.target.value) })}
                className="input"
              />
            </Field>
          </div>
        </Section>

        <Section title="التوصيل" subtitle="الرسوم والحد الأدنى والعنوان العام.">
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="رسوم التوصيل الافتراضية (د.أ)">
              <input
                type="number"
                min={0}
                step="0.001"
                value={store.deliveryFee}
                onChange={(e) =>
                  setStore({ ...store, deliveryFee: Number(e.target.value) })
                }
                className="input"
              />
            </Field>
            <Field label="الحد الأدنى للطلب (د.أ)">
              <input
                type="number"
                min={0}
                step="0.001"
                value={store.minOrder}
                onChange={(e) => setStore({ ...store, minOrder: Number(e.target.value) })}
                className="input"
              />
            </Field>
          </div>
          <Field label="عنوان المتجر">
            <input
              value={store.address}
              onChange={(e) => setStore({ ...store, address: e.target.value })}
              className="input"
            />
          </Field>
          <Toggle
            label="السماح بجدولة الطلب عندما يكون المتجر مغلقًا"
            checked={publicSettings.allow_scheduled_orders_when_closed}
            onChange={(value) =>
              setPublicSettings({
                ...publicSettings,
                allow_scheduled_orders_when_closed: value,
              })
            }
          />
        </Section>

        <Section title="الدفع" subtitle="PayTabs وCliQ وبيانات التحويل.">
          <div className="flex items-center justify-between rounded-xl bg-gray-50 p-3">
            <div>
              <div className="font-semibold">PayTabs</div>
              <div className="text-xs text-gray-500">Visa / Mastercard</div>
            </div>
            <span
              className={`rounded-full px-3 py-1 text-xs font-bold ${
                cardReady
                  ? "bg-green-100 text-green-700"
                  : "bg-amber-100 text-amber-800"
              }`}
            >
              {checkingCard ? "فحص..." : cardReady ? "مفعّل" : "غير مفعّل"}
            </span>
          </div>
          <button
            type="button"
            onClick={() => void checkCardReadiness()}
            className="rounded-lg border border-gray-300 px-3 py-2 text-sm"
          >
            إعادة فحص PayTabs
          </button>
          <Field label="CliQ Alias">
            <input
              dir="ltr"
              value={store.cliqAlias}
              onChange={(e) => setStore({ ...store, cliqAlias: e.target.value })}
              className="input text-left"
            />
          </Field>
          <Field label="اسم المستفيد">
            <input
              value={store.cliqRecipientName}
              onChange={(e) =>
                setStore({ ...store, cliqRecipientName: e.target.value })
              }
              className="input"
            />
          </Field>
          <Toggle
            label="وضع صيانة للدفع"
            checked={publicSettings.maintenance_payments}
            onChange={(value) =>
              setPublicSettings({ ...publicSettings, maintenance_payments: value })
            }
          />
        </Section>
      </div>

      <Section title="ساعات العمل" subtitle="اترك اليوم غير محدد إذا لا تريد فرض ساعات عمل عليه.">
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {hours.map((row) => (
            <div key={row.day} className="rounded-xl border border-gray-200 p-3">
              <div className="flex items-center justify-between">
                <strong>{dayNames[row.day]}</strong>
                <label className="flex items-center gap-2 text-xs">
                  <input
                    type="checkbox"
                    checked={row.configured}
                    onChange={(e) =>
                      updateHour(row.day, { configured: e.target.checked })
                    }
                  />
                  تحديد ساعات
                </label>
              </div>
              {row.configured && (
                <div className="mt-3 space-y-3">
                  <Toggle
                    compact
                    label="مغلق طوال اليوم"
                    checked={row.isClosed}
                    onChange={(value) => updateHour(row.day, { isClosed: value })}
                  />
                  {!row.isClosed && (
                    <>
                      <div className="grid grid-cols-2 gap-2">
                        <input
                          type="time"
                          value={row.openTime}
                          onChange={(e) =>
                            updateHour(row.day, { openTime: e.target.value })
                          }
                          className="input"
                        />
                        <input
                          type="time"
                          value={row.closeTime}
                          onChange={(e) =>
                            updateHour(row.day, { closeTime: e.target.value })
                          }
                          className="input"
                        />
                      </div>
                      <Toggle
                        compact
                        label="الإغلاق في اليوم التالي"
                        checked={row.closesNextDay}
                        onChange={(value) =>
                          updateHour(row.day, { closesNextDay: value })
                        }
                      />
                    </>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      </Section>

      <Section title="السوشال والتواصل" subtitle="الروابط تتحدث داخل التطبيق مباشرة.">
        <div className="grid gap-4 lg:grid-cols-2">
          <SocialField
            label="Facebook"
            value={publicSettings.facebook_url}
            enabled={publicSettings.facebook_enabled}
            onValue={(value) =>
              setPublicSettings({ ...publicSettings, facebook_url: value })
            }
            onEnabled={(value) =>
              setPublicSettings({ ...publicSettings, facebook_enabled: value })
            }
          />
          <SocialField
            label="Instagram"
            value={publicSettings.instagram_url}
            enabled={publicSettings.instagram_enabled}
            onValue={(value) =>
              setPublicSettings({ ...publicSettings, instagram_url: value })
            }
            onEnabled={(value) =>
              setPublicSettings({ ...publicSettings, instagram_enabled: value })
            }
          />
          <Field label="TikTok">
            <input
              dir="ltr"
              value={publicSettings.tiktok_url}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, tiktok_url: e.target.value })
              }
              className="input text-left"
              placeholder="https://..."
            />
          </Field>
          <Field label="الموقع الإلكتروني">
            <input
              dir="ltr"
              value={publicSettings.website_url}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, website_url: e.target.value })
              }
              className="input text-left"
              placeholder="https://..."
            />
          </Field>
          <Field label="Google Maps">
            <input
              dir="ltr"
              value={publicSettings.google_maps_url}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, google_maps_url: e.target.value })
              }
              className="input text-left"
              placeholder="https://maps.google.com/..."
            />
          </Field>
          <Field label="رقم الهاتف">
            <input
              dir="ltr"
              value={store.phone}
              onChange={(e) => setStore({ ...store, phone: e.target.value })}
              className="input text-left"
            />
          </Field>
          <Field label="رقم WhatsApp">
            <input
              dir="ltr"
              value={publicSettings.whatsapp_number}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, whatsapp_number: e.target.value })
              }
              className="input text-left"
              placeholder="9627XXXXXXXX"
            />
          </Field>
          <Field label="رسالة WhatsApp الافتراضية">
            <textarea
              value={publicSettings.whatsapp_default_message}
              onChange={(e) =>
                setPublicSettings({
                  ...publicSettings,
                  whatsapp_default_message: e.target.value,
                })
              }
              className="input min-h-20"
            />
          </Field>
        </div>
        <Toggle
          label="إظهار WhatsApp"
          checked={publicSettings.whatsapp_enabled}
          onChange={(value) =>
            setPublicSettings({ ...publicSettings, whatsapp_enabled: value })
          }
        />
        <div className="flex flex-wrap gap-3 text-xs text-gray-600">
          <Metric label="Facebook" value={social.facebook_clicks} />
          <Metric label="Instagram" value={social.instagram_clicks} />
          <Metric label="WhatsApp" value={social.whatsapp_clicks} />
          <Metric label="TikTok" value={social.tiktok_clicks} />
          <Metric label="Maps" value={social.maps_clicks} />
          <Metric label="Website" value={social.website_clicks} />
          <Metric label="دعم العملاء" value={social.support_clicks} />
          <Metric label="مشاركة التطبيق" value={social.app_shares} />
        </div>
        <div className="flex flex-wrap gap-2">
          {[
            ["Facebook QR", publicSettings.facebook_url],
            ["Instagram QR", publicSettings.instagram_url],
            ["WhatsApp QR", publicSettings.whatsapp_number ? `https://wa.me/${publicSettings.whatsapp_number.replace(/\D/g, "")}` : ""],
          ].map(([label, value]) =>
            value ? (
              <a
                key={label}
                href={`https://quickchart.io/qr?size=260&text=${encodeURIComponent(value)}`}
                target="_blank"
                rel="noreferrer"
                className="rounded-lg border border-gray-300 px-3 py-2 text-xs font-semibold hover:bg-gray-50"
              >
                {label}
              </a>
            ) : null,
          )}
        </div>
      </Section>

      <div className="grid gap-6 xl:grid-cols-2">
        <Section title="خدمة العملاء" subtitle="قنوات وساعات الدعم.">
          <Field label="رقم دعم العملاء">
            <input
              dir="ltr"
              value={publicSettings.support_phone}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, support_phone: e.target.value })
              }
              className="input text-left"
            />
          </Field>
          <Field label="WhatsApp الدعم">
            <input
              dir="ltr"
              value={publicSettings.support_whatsapp_number}
              onChange={(e) =>
                setPublicSettings({
                  ...publicSettings,
                  support_whatsapp_number: e.target.value,
                })
              }
              className="input text-left"
            />
          </Field>
          <Field label="ساعات الدعم">
            <input
              value={publicSettings.support_hours_text}
              onChange={(e) =>
                setPublicSettings({
                  ...publicSettings,
                  support_hours_text: e.target.value,
                })
              }
              className="input"
              placeholder="مثال: يوميًا 9 صباحًا – 11 مساءً"
            />
          </Field>
        </Section>

        <Section title="الروابط القانونية والمتاجر" subtitle="روابط النشر والمشاركة.">
          {[
            ["سياسة الخصوصية", "privacy_policy_url"],
            ["الشروط والأحكام", "terms_url"],
            ["Google Play", "play_store_url"],
            ["App Store", "app_store_url"],
          ].map(([label, key]) => (
            <Field key={key} label={label}>
              <input
                dir="ltr"
                value={publicSettings[key as keyof PublicSettings] as string}
                onChange={(e) =>
                  setPublicSettings({
                    ...publicSettings,
                    [key]: e.target.value,
                  })
                }
                className="input text-left"
                placeholder="https://..."
              />
            </Field>
          ))}
        </Section>
      </div>

      <Section title="الإعلان أعلى التطبيق" subtitle="رسالة فورية بدون إصدار APK جديد.">
        <Toggle
          label="إظهار الإعلان"
          checked={publicSettings.announcement_enabled}
          onChange={(value) =>
            setPublicSettings({ ...publicSettings, announcement_enabled: value })
          }
        />
        <div className="grid gap-3 md:grid-cols-2">
          <Field label="العنوان">
            <input
              value={publicSettings.announcement_title}
              onChange={(e) =>
                setPublicSettings({
                  ...publicSettings,
                  announcement_title: e.target.value,
                })
              }
              className="input"
            />
          </Field>
          <Field label="النوع">
            <select
              value={publicSettings.announcement_style}
              onChange={(e) =>
                setPublicSettings({
                  ...publicSettings,
                  announcement_style: e.target.value as PublicSettings["announcement_style"],
                })
              }
              className="input"
            >
              <option value="info">معلومة</option>
              <option value="sale">عرض</option>
              <option value="warning">تنبيه</option>
            </select>
          </Field>
          <Field label="النص">
            <textarea
              value={publicSettings.announcement_body}
              onChange={(e) =>
                setPublicSettings({ ...publicSettings, announcement_body: e.target.value })
              }
              className="input min-h-20"
            />
          </Field>
          <div className="space-y-3">
            <Field label="نص الزر">
              <input
                value={publicSettings.announcement_action_label}
                onChange={(e) =>
                  setPublicSettings({
                    ...publicSettings,
                    announcement_action_label: e.target.value,
                  })
                }
                className="input"
              />
            </Field>
            <Field label="رابط الزر">
              <input
                dir="ltr"
                value={publicSettings.announcement_action_url}
                onChange={(e) =>
                  setPublicSettings({
                    ...publicSettings,
                    announcement_action_url: e.target.value,
                  })
                }
                className="input text-left"
              />
            </Field>
          </div>
        </div>
      </Section>

      <div className="grid gap-6 xl:grid-cols-2">
        <Section title="الميزات" subtitle="إظهار أو إخفاء أجزاء التطبيق.">
          <div className="grid gap-2 sm:grid-cols-2">
            {([
              ["المساعد AI", "feature_ai"],
              ["العروض", "feature_offers"],
              ["الولاء", "feature_loyalty"],
              ["الإعلانات", "feature_ads"],
              ["زر الاتصال", "feature_call"],
              ["WhatsApp", "feature_whatsapp"],
              ["إعادة الطلب", "feature_reorder"],
              ["Referral", "feature_referral"],
            ] as const).map(([label, key]) => (
              <Toggle
                key={key}
                label={label}
                checked={publicSettings[key]}
                onChange={(value) =>
                  setPublicSettings({ ...publicSettings, [key]: value })
                }
              />
            ))}
          </div>
        </Section>

        <Section title="الصيانة" subtitle="أوقف جزءًا محددًا بدل إغلاق التطبيق بالكامل.">
          <Toggle
            label="إيقاف إتمام الطلب"
            checked={publicSettings.maintenance_checkout}
            onChange={(value) =>
              setPublicSettings({ ...publicSettings, maintenance_checkout: value })
            }
          />
          <Toggle
            label="إيقاف الدفع الإلكتروني"
            checked={publicSettings.maintenance_payments}
            onChange={(value) =>
              setPublicSettings({ ...publicSettings, maintenance_payments: value })
            }
          />
          <Toggle
            label="إيقاف التوصيل"
            checked={publicSettings.maintenance_delivery}
            onChange={(value) =>
              setPublicSettings({ ...publicSettings, maintenance_delivery: value })
            }
          />
        </Section>
      </div>

      <Section title="Referral — ادعُ صديقك" subtitle="المكافأة تُمنح بعد تسليم أول طلب مؤهل فقط.">
        <div className="grid gap-5 lg:grid-cols-[1fr_260px]">
          <div className="space-y-4">
            <Toggle
              label="تشغيل نظام Referral"
              checked={referral.is_enabled}
              onChange={(value) => setReferral({ ...referral, is_enabled: value })}
            />
            <div className="grid gap-3 sm:grid-cols-2">
              <Field label="اسم البرنامج">
                <input
                  value={referral.program_name}
                  onChange={(e) =>
                    setReferral({ ...referral, program_name: e.target.value })
                  }
                  className="input"
                />
              </Field>
              <Field label="الحد الأدنى لأول طلب (د.أ)">
                <input
                  type="number"
                  min={0}
                  step="0.001"
                  value={referral.min_first_order_total}
                  onChange={(e) =>
                    setReferral({
                      ...referral,
                      min_first_order_total: Number(e.target.value),
                    })
                  }
                  className="input"
                />
              </Field>
              <Field label="مكافآت صاحب الدعوة">
                <input
                  type="number"
                  min={0}
                  max={10}
                  value={referral.referrer_reward_count}
                  onChange={(e) =>
                    setReferral({
                      ...referral,
                      referrer_reward_count: Number(e.target.value),
                    })
                  }
                  className="input"
                />
              </Field>
              <Field label="مكافآت الصديق الجديد">
                <input
                  type="number"
                  min={0}
                  max={10}
                  value={referral.referred_reward_count}
                  onChange={(e) =>
                    setReferral({
                      ...referral,
                      referred_reward_count: Number(e.target.value),
                    })
                  }
                  className="input"
                />
              </Field>
              <Field label="حد مكافآت صاحب الدعوة">
                <input
                  type="number"
                  min={0}
                  value={referral.max_referrer_rewards_per_customer}
                  onChange={(e) =>
                    setReferral({
                      ...referral,
                      max_referrer_rewards_per_customer: Number(e.target.value),
                    })
                  }
                  className="input"
                />
                <p className="mt-1 text-[11px] text-gray-500">0 = بدون حد</p>
              </Field>
              <Field label="اسم المكافأة">
                <input
                  value={referral.reward_title}
                  onChange={(e) =>
                    setReferral({ ...referral, reward_title: e.target.value })
                  }
                  className="input"
                />
              </Field>
            </div>
            <Field label="الشروط">
              <textarea
                value={referral.terms_text}
                onChange={(e) =>
                  setReferral({ ...referral, terms_text: e.target.value })
                }
                className="input min-h-24"
              />
            </Field>
          </div>
          <div className="grid content-start gap-3">
            <MetricCard label="إجمالي الدعوات" value={referrals.total} />
            <MetricCard label="قيد الانتظار" value={referrals.pending} />
            <MetricCard label="مكافآت مكتملة" value={referrals.rewarded} />
            <MetricCard label="مرات المشاركة" value={social.referral_shares} />
          </div>
        </div>
      </Section>

      <button
        type="submit"
        disabled={saving}
        className="w-full rounded-xl bg-red-600 px-5 py-3.5 font-bold text-white hover:bg-red-700 disabled:opacity-50"
      >
        {saving ? "جاري الحفظ..." : "حفظ ونشر جميع الإعدادات"}
      </button>
    </form>
  );
}

function Section({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-4 rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
      <div>
        <h2 className="font-bold text-gray-950">{title}</h2>
        {subtitle && <p className="mt-1 text-xs leading-5 text-gray-500">{subtitle}</p>}
      </div>
      {children}
    </section>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-2">
      <span className="text-sm font-medium text-gray-700">{label}</span>
      {children}
    </label>
  );
}

function Toggle({
  label,
  checked,
  onChange,
  compact = false,
}: {
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
  compact?: boolean;
}) {
  return (
    <label
      className={`flex cursor-pointer items-center justify-between gap-3 rounded-xl border border-gray-200 ${
        compact ? "px-3 py-2" : "p-3"
      }`}
    >
      <span className={compact ? "text-xs font-medium" : "text-sm font-medium"}>
        {label}
      </span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="h-4 w-4 accent-red-600"
      />
    </label>
  );
}

function SocialField({
  label,
  value,
  enabled,
  onValue,
  onEnabled,
}: {
  label: string;
  value: string;
  enabled: boolean;
  onValue: (value: string) => void;
  onEnabled: (value: boolean) => void;
}) {
  return (
    <div className="space-y-2 rounded-xl border border-gray-200 p-3">
      <Toggle compact label={`إظهار ${label}`} checked={enabled} onChange={onEnabled} />
      <input
        dir="ltr"
        value={value}
        onChange={(e) => onValue(e.target.value)}
        className="input text-left"
        placeholder="https://..."
      />
    </div>
  );
}

function Notice({
  tone,
  children,
}: {
  tone: "success" | "error";
  children: React.ReactNode;
}) {
  return (
    <div
      className={`rounded-xl p-4 text-sm ${
        tone === "success"
          ? "bg-green-50 text-green-700"
          : "bg-red-50 text-red-700"
      }`}
    >
      {children}
    </div>
  );
}

function Metric({ label, value }: { label: string; value: unknown }) {
  return (
    <span className="rounded-full bg-gray-100 px-3 py-1.5">
      {label}: <b>{numberValue(value)}</b>
    </span>
  );
}

function MetricCard({ label, value }: { label: string; value: unknown }) {
  return (
    <div className="rounded-xl border border-gray-200 bg-gray-50 p-4">
      <div className="text-xs text-gray-500">{label}</div>
      <div className="mt-1 text-2xl font-black text-gray-950">{numberValue(value)}</div>
    </div>
  );
}
