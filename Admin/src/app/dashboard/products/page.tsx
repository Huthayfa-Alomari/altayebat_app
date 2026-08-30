import { createClient } from "@/lib/supabase/server";
import ProductsManager from "./ProductsManager";

export default async function ProductsPage() {
  const supabase = createClient();

  const { data: products } = await supabase
    .from("products")
    .select("id, name, price, stock_qty, is_available, category_id")
    .order("created_at", { ascending: false });

  const { data: categories } = await supabase
    .from("categories")
    .select("id, name")
    .order("sort_order");

  return (
    <div>
      <h1 className="mb-4 text-lg font-medium">المنتجات</h1>
      <ProductsManager
        initialProducts={products || []}
        categories={categories || []}
      />
    </div>
  );
}