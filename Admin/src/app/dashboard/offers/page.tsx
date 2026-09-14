import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import OffersManager from "./OffersManager";

export default async function OffersPage() {
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  // Refresh both expired and newly-due scheduled offers before rendering the
  // dashboard. Older databases simply return an RPC error, which is harmless
  // until the matching migration is deployed.
  await supabase.rpc("refresh_expired_offers", { p_store_id: storeId });

  const [{ data: products }, { data: offers }, { data: settings }] =
    await Promise.all([
      supabase
        .from("products")
        .select(
          "id,name,price_per_unit,sale_type,base_unit,is_available,stock_qty",
        )
        .eq("store_id", storeId)
        .eq("is_available", true)
        .order("name"),
      supabase
        .from("store_offers")
        .select(
          "id,product_id,title,subtitle,regular_price_per_unit,offer_price_per_unit,starts_at,ends_at,is_active,ended_at,created_at,products(name)",
        )
        .eq("store_id", storeId)
        .order("created_at", { ascending: false }),
      supabase
        .from("storefront_settings")
        .select(
          "show_offers_section,offer_banner_title,offer_banner_subtitle",
        )
        .eq("store_id", storeId)
        .maybeSingle(),
    ]);

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">العروض</h1>
        <p className="mt-1 text-sm text-gray-500">
          حدّد أكثر من صنف من البضاعة، ضع سعر العرض لكل صنف، وحدد بداية ونهاية
          الحملة من نفس الصفحة.
        </p>
      </div>
      <OffersManager
        storeId={storeId}
        products={products || []}
        initialOffers={offers || []}
        initialSettings={{
          show_offers_section: settings?.show_offers_section ?? true,
          offer_banner_title: settings?.offer_banner_title || "عروض مميزة اليوم",
          offer_banner_subtitle:
            settings?.offer_banner_subtitle || "وفر أكثر مع عروض أسواق الطيبات",
        }}
      />
    </div>
  );
}
