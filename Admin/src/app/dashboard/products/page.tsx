import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import ProductsManager from "./ProductsManager";

export default async function ProductsPage() {
  const supabase = createClient();
  const { storeId } = await requireAdminStore();

  const [{ data: products }, { data: categories }] = await Promise.all([
    supabase
      .from("products")
      .select("id, name, price, stock_qty, is_available, category_id")
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
