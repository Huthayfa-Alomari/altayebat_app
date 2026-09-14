import { createClient } from "@/lib/supabase/server";
import { requireAdminStore } from "@/lib/store-context";
import LoyaltyManager from "./LoyaltyManager";

export default async function LoyaltyPage() {
  const supabase = await createClient();
  const { storeId } = await requireAdminStore();

  const [{ data: program }, { data: wallets }] = await Promise.all([
    supabase
      .from("loyalty_programs")
      .select(
        "is_enabled,program_name,baskets_required,min_order_total,reward_title",
      )
      .eq("store_id", storeId)
      .maybeSingle(),
    supabase
      .from("customer_loyalty_wallets")
      .select(
        "customer_id,lifetime_baskets,rewards_available,rewards_redeemed",
      )
      .eq("store_id", storeId),
  ]);

  const walletRows = wallets || [];
  const stats = walletRows.reduce(
    (acc, row) => ({
      members: acc.members + 1,
      lifetimeBaskets:
        acc.lifetimeBaskets + Number(row.lifetime_baskets || 0),
      rewardsAvailable:
        acc.rewardsAvailable + Number(row.rewards_available || 0),
      rewardsRedeemed:
        acc.rewardsRedeemed + Number(row.rewards_redeemed || 0),
    }),
    {
      members: 0,
      lifetimeBaskets: 0,
      rewardsAvailable: 0,
      rewardsRedeemed: 0,
    },
  );

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-lg font-semibold">المكافآت</h1>
        <p className="mt-1 text-sm text-gray-500">
          برنامج ولاء واضح وبسيط: الزبون يجمع سلال بدل أرقام نقاط غير مفهومة.
        </p>
      </div>
      <LoyaltyManager
        storeId={storeId}
        initialProgram={{
          is_enabled: program?.is_enabled ?? true,
          program_name: program?.program_name || "مكافآت الطيبات",
          baskets_required: Number(program?.baskets_required || 5),
          min_order_total: Number(program?.min_order_total || 5),
          reward_title:
            program?.reward_title || "التوصيل علينا بالطلب القادم",
        }}
        stats={stats}
      />
    </div>
  );
}
