import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import ProductsManager from "./ProductsManager";

export default async function ProductsPage() {
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  const [{ data: products }, { data: categories }] = await Promise.all([
    supabase
      .from("products")
      .select(
        "id, name, sku, barcode, price, price_per_unit, stock_qty, is_available, category_id, image_url, sale_type, base_unit, inventory_scale, min_qty, qty_step, allow_amount_purchase",
      )
      .eq("store_id", storeId)
      .order("created_at", { ascending: false }),
    supabase
      .from("categories")
      .select("id, name")
      .eq("store_id", storeId)
      .order("sort_order"),
  ]);

  return (
    <div>
      <h1 className="mb-4 text-lg font-medium">المنتجات</h1>
      <ProductsManager
        initialProducts={products || []}
        categories={categories || []}
        storeId={storeId}
      />
    </div>
  );
}
