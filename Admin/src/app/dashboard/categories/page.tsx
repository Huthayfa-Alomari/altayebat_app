import { createClient } from "@/lib/supabase/server";
import CategoriesManager from "./CategoriesManager";

export default async function CategoriesPage() {
  const supabase = createClient();

  const { data: categories } = await supabase
    .from("categories")
    .select("id, name, sort_order")
    .order("sort_order");

  return (
    <div>
      <h1 className="mb-4 text-lg font-medium">التصنيفات</h1>
      <CategoriesManager initialCategories={categories || []} />
    </div>
  );
}