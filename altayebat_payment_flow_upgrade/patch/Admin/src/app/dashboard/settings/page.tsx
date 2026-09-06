"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type StoreConfig = {
  storeId: string;
  storeName: string;
  cliqAlias: string;
  cliqRecipientName: string;
  phone: string;
};

export default function PaymentSettingsPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [config, setConfig] = useState<StoreConfig | null>(null);
  const [cardReady, setCardReady] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [checking, setChecking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  useEffect(() => {
    void load();
    // Supabase client is memoized for the lifetime of this page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function load() {
    setLoading(true);
    setError(null);

    try {
      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser();

      if (userError || !user) {
        router.replace("/login");
        return;
      }

      const { data: adminLink, error: linkError } = await supabase
        .from("store_admins")
        .select("store_id")
        .eq("user_id", user.id)
        .limit(1)
        .maybeSingle();

      if (linkError) throw linkError;
      if (!adminLink?.store_id) {
        throw new Error("هذا الحساب غير مربوط بأي مول.");
      }

      const { data: store, error: storeError } = await supabase
        .from("stores")
        .select("id,name,cliq_alias,cliq_recipient_name,phone")
        .eq("id", adminLink.store_id)
        .single();

      if (storeError) throw storeError;

      setConfig({
        storeId: store.id,
        storeName: store.name,
        cliqAlias: store.cliq_alias ?? "",
        cliqRecipientName: store.cliq_recipient_name ?? "",
        phone: store.phone ?? "",
      });

      await checkCardReadiness();
    } catch (err) {
      setError(message(err));
    } finally {
      setLoading(false);
    }
  }

  async function checkCardReadiness() {
    setChecking(true);
    try {
      const { data, error: fnError } = await supabase.functions.invoke(
        "payment-readiness",
        { body: {} },
      );

      if (fnError) {
        setCardReady(false);
        return;
      }

      setCardReady(
        !!data &&
          typeof data === "object" &&
          "card_enabled" in data &&
          data.card_enabled === true,
      );
    } finally {
      setChecking(false);
    }
  }

  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!config || saving) return;

    setSaving(true);
    setError(null);
    setSaved(null);

    try {
      const { data, error: rpcError } = await supabase.rpc(
        "admin_update_store_payment_config",
        {
          p_store_id: config.storeId,
          p_cliq_alias: config.cliqAlias,
          p_cliq_recipient_name: config.cliqRecipientName,
          p_phone: config.phone,
        },
      );

      if (rpcError) throw rpcError;

      const row =
        data && typeof data === "object"
          ? (data as Record<string, unknown>)
          : {};

      setConfig((current) =>
        current
          ? {
              ...current,
              cliqAlias:
                typeof row.cliq_alias === "string" ? row.cliq_alias : "",
              cliqRecipientName:
                typeof row.cliq_recipient_name === "string"
                  ? row.cliq_recipient_name
                  : "",
              phone: typeof row.phone === "string" ? row.phone : "",
            }
          : current,
      );

      setSaved("تم حفظ إعدادات الدفع والتواصل.");
    } catch (err) {
      setError(message(err));
    } finally {
      setSaving(false);
    }
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

  if (loading) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center">
        <div className="text-sm text-gray-500">جاري تحميل الإعدادات...</div>
      </div>
    );
  }

  if (!config) {
    return (
      <div className="space-y-4" dir="rtl">
        <Link
          href="/dashboard"
          className="text-sm font-medium text-red-600 hover:underline"
        >
          العودة للوحة التحكم
        </Link>
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-700">
          {error ?? "تعذر تحميل إعدادات المول."}
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6" dir="rtl">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">إعدادات الدفع</h1>
          <p className="mt-1 text-sm text-gray-500">{config.storeName}</p>
        </div>
        <Link
          href="/dashboard"
          className="rounded-lg border border-gray-200 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          العودة للوحة التحكم
        </Link>
      </div>

      <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="font-bold text-gray-900">PayTabs</h2>
            <p className="mt-1 text-sm text-gray-500">
              Visa / Mastercard — حالة ربط بوابة الدفع.
            </p>
          </div>

          <div
            className={`rounded-full px-3 py-1 text-sm font-semibold ${
              cardReady
                ? "bg-green-100 text-green-700"
                : "bg-amber-100 text-amber-800"
            }`}
          >
            {checking ? "جاري الفحص..." : cardReady ? "مفعّل" : "غير مفعّل"}
          </div>
        </div>

        {!cardReady && (
          <div className="mt-4 rounded-xl bg-amber-50 p-4 text-sm leading-7 text-amber-900">
            أضف القيمتين <b>PAYTABS_SERVER_KEY</b> و{" "}
            <b>PAYTABS_PROFILE_ID</b> داخل Supabase Edge Function Secrets.
            لا تضع Server Key داخل Flutter أو Vercel.
          </div>
        )}

        <button
          type="button"
          onClick={() => void checkCardReadiness()}
          disabled={checking}
          className="mt-4 rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
        >
          إعادة فحص PayTabs
        </button>
      </section>

      <form
        onSubmit={save}
        className="space-y-5 rounded-2xl border border-gray-200 bg-white p-5 shadow-sm"
      >
        <div>
          <h2 className="font-bold text-gray-900">CliQ والتواصل</h2>
          <p className="mt-1 text-sm text-gray-500">
            هذه البيانات تظهر للزبون بعد اختيار CliQ.
          </p>
        </div>

        <label className="block space-y-2">
          <span className="text-sm font-medium text-gray-700">CliQ Alias</span>
          <input
            value={config.cliqAlias}
            onChange={(e) =>
              setConfig({ ...config, cliqAlias: e.target.value })
            }
            placeholder="مثال: ALTAYEBAT"
            maxLength={80}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5 outline-none focus:border-red-500"
          />
        </label>

        <label className="block space-y-2">
          <span className="text-sm font-medium text-gray-700">
            اسم المستفيد
          </span>
          <input
            value={config.cliqRecipientName}
            onChange={(e) =>
              setConfig({
                ...config,
                cliqRecipientName: e.target.value,
              })
            }
            placeholder="الاسم الذي يظهر عند التحويل"
            maxLength={120}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5 outline-none focus:border-red-500"
          />
        </label>

        <label className="block space-y-2">
          <span className="text-sm font-medium text-gray-700">
            رقم هاتف/واتساب المول
          </span>
          <input
            dir="ltr"
            value={config.phone}
            onChange={(e) => setConfig({ ...config, phone: e.target.value })}
            placeholder="+9627XXXXXXXX"
            maxLength={30}
            className="w-full rounded-xl border border-gray-300 px-3 py-2.5 text-left outline-none focus:border-red-500"
          />
          <span className="block text-xs text-gray-500">
            يستخدمه التطبيق لزر الاتصال وإرسال إثبات تحويل CliQ عبر واتساب.
          </span>
        </label>

        {error && (
          <div className="rounded-xl bg-red-50 p-3 text-sm text-red-700">
            {error}
          </div>
        )}

        {saved && (
          <div className="rounded-xl bg-green-50 p-3 text-sm text-green-700">
            {saved}
          </div>
        )}

        <button
          type="submit"
          disabled={saving}
          className="w-full rounded-xl bg-red-600 px-4 py-3 font-semibold text-white hover:bg-red-700 disabled:opacity-50"
        >
          {saving ? "جاري الحفظ..." : "حفظ الإعدادات"}
        </button>
      </form>
    </div>
  );
}
