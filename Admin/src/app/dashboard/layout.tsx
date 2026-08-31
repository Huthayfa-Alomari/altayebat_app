import Link from "next/link";
import { requireAdminStore } from "@/lib/store-context";
import LogoutButton from "./LogoutButton";

const navItems = [
  { href: "/dashboard", label: "الطلبات" },
  { href: "/dashboard/products", label: "المنتجات" },
  { href: "/dashboard/categories", label: "التصنيفات" },
  { href: "/dashboard/support", label: "طلبات التواصل" },
];

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { storeName } = await requireAdminStore();

  return (
    <div className="min-h-screen bg-gray-50 lg:flex">
      <aside className="border-b border-gray-200 bg-white p-4 lg:min-h-screen lg:w-56 lg:shrink-0 lg:border-b-0 lg:border-l">
        <div className="flex items-center justify-between gap-4 lg:block">
          <p className="truncate text-sm font-medium text-brand lg:mb-6">
            {storeName}
          </p>
          <div className="lg:hidden">
            <LogoutButton />
          </div>
        </div>

        <nav className="mt-4 flex gap-2 overflow-x-auto lg:mt-0 lg:block lg:space-y-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="whitespace-nowrap rounded-lg px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 lg:block"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="mt-8 hidden lg:block">
          <LogoutButton />
        </div>
      </aside>
      <main className="min-w-0 flex-1 p-4 sm:p-6">{children}</main>
    </div>
  );
}
