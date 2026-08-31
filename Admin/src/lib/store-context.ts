import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AdminStoreContext = {
  userId: string;
  storeId: string;
  storeName: string;
};

export async function requireAdminStore(): Promise<AdminStoreContext> {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: admin, error } = await supabase
    .from("store_admins")
    .select("store_id, stores(name)")
    .eq("user_id", user.id)
    .maybeSingle();

  if (error || !admin?.store_id) {
    redirect("/login?error=no-store-access");
  }

  const store = admin.stores as unknown as { name: string | null } | null;

  return {
    userId: user.id,
    storeId: admin.store_id as string,
    storeName: store?.name?.trim() || "لوحة التحكم",
  };
}
