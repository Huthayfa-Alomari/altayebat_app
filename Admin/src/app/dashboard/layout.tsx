import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import LogoutButton from "./LogoutButton";

const navItems = [
  { href: "/dashboard", label: "الطلبات" },
  { href: "/dashboard/products", label: "المنتجات" },
  { href: "/dashboard/categories", label: "التصنيفات" },
];

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let storeName = "لوحة التحكم";
  if (user) {
    const { data: admin } = await supabase
      .from("store_admins")
      .select("stores(name)")
      .eq("user_id", user.id)
      .maybeSingle();
    const store = admin?.stores as unknown as { name: string } | null;
    if (store?.name) storeName = store.name;
  }

  return (
    <div className="flex min-h-screen">
      <aside className="w-56 shrink-0 border-l border-gray-200 bg-white p-4">
        <p className="mb-6 truncate text-sm font-medium text-brand">
          {storeName}
        </p>
        <nav className="space-y-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="mt-8">
          <LogoutButton />
        </div>
      </aside>
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}