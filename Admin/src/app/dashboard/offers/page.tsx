import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import OffersManager from "./OffersManager";

export default async function OffersPage() {
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  const [{ data: products }, { data: offers }] = await Promise.all([
    supabase
      .from("products")
      .select("id,name,price_per_unit,sale_type,base_unit,is_available")
      .eq("store_id", storeId)
      .eq("is_available", true)
      .order("name"),
    supabase
      .from("store_offers")
      .select(
        "id,product_id,title,subtitle,regular_price_per_unit,offer_price_per_unit,ends_at,is_active,created_at,products(name)",
      )
      .eq("store_id", storeId)
      .order("created_at", { ascending: false }),
  ]);

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">العروض</h1>
        <p className="mt-1 text-sm text-gray-500">
          السعر المخفّض ينعكس على التطبيق والطلب مباشرة، وليس مجرد إعلان.
        </p>
      </div>
      <OffersManager
        storeId={storeId}
        products={products || []}
        initialOffers={offers || []}
      />
    </div>
  );
}
