import Link from "next/link";
import { requireAdminStore } from "@/lib/store-context";
import LogoutButton from "./LogoutButton";

const navItems = [
  { href: "/dashboard", label: "\u0627\u0644\u0637\u0644\u0628\u0627\u062a" },
  { href: "/dashboard/products", label: "\u0627\u0644\u0645\u0646\u062a\u062c\u0627\u062a" },
  { href: "/dashboard/categories", label: "\u0627\u0644\u062a\u0635\u0646\u064a\u0641\u0627\u062a" },
  { href: "/dashboard/support", label: "\u0637\u0644\u0628\u0627\u062a \u0627\u0644\u062a\u0648\u0627\u0635\u0644" },
  { href: "/dashboard/settings", label: "\u0625\u0639\u062f\u0627\u062f\u0627\u062a \u0627\u0644\u062f\u0641\u0639" },
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
