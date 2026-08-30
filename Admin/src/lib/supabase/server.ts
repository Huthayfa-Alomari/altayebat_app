import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// عميل Supabase يشتغل بالسيرفر — يستخدم بالـ Server Components و Server Actions
export function createClient() {
  const cookieStore = cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // بيصير تجاهله لو انستدعت من Server Component ما بتقدر تكتب كوكيز
          }
        },
      },
    }
  );
}