import { createClient } from "npm:@supabase/supabase-js@2.112.4";
import { GoogleAuth } from "npm:google-auth-library@9.15.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const rawServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");

    if (!rawServiceAccount) {
      return json(
        { error: "Firebase is not configured", code: "FCM_NOT_CONFIGURED" },
        503,
      );
    }

    const authorization = req.headers.get("Authorization") || "";
    const jwt = authorization.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const user = userData.user;
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const payload = await req.json().catch(() => ({}));
    const orderId = typeof payload?.order_id === "string" ? payload.order_id : "";
    if (!orderId) return json({ error: "order_id is required" }, 400);

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id,store_id,driver_id,total,status")
      .eq("id", orderId)
      .maybeSingle();
    if (orderError || !order) return json({ error: "Order not found" }, 404);
    if (!order.driver_id) return json({ error: "Order has no rider" }, 409);

    const { data: membership } = await admin
      .from("store_admins")
      .select("store_id")
      .eq("user_id", user.id)
      .eq("store_id", order.store_id)
      .maybeSingle();
    if (!membership) return json({ error: "Forbidden" }, 403);

    const { data: rider, error: riderError } = await admin
      .from("drivers")
      .select("id,name,is_active,approval_status")
      .eq("id", order.driver_id)
      .eq("store_id", order.store_id)
      .maybeSingle();
    if (
      riderError ||
      !rider ||
      !rider.is_active ||
      rider.approval_status !== "approved"
    ) {
      return json({ error: "Rider is not available" }, 409);
    }

    const { data: tokenRows, error: tokenError } = await admin
      .from("rider_push_tokens")
      .select("id,token")
      .eq("store_id", order.store_id)
      .eq("driver_id", rider.id);
    if (tokenError) throw tokenError;
    if (!tokenRows?.length) {
      return json({ ok: true, sent: 0, reason: "no_tokens" });
    }

    const serviceAccount = JSON.parse(rawServiceAccount);
    const projectId = serviceAccount.project_id;
    if (!projectId) throw new Error("Firebase service account has no project_id");

    const googleAuth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = await googleAuth.getAccessToken();
    if (!accessToken) throw new Error("Unable to obtain Firebase access token");

    const shortOrder = String(order.id).replaceAll("-", "").slice(0, 8).toUpperCase();
    const title = "طلب توصيل جديد — أسواق الطيبات";
    const body = `تم إسناد الطلب #${shortOrder} إليك. افتح بوابة المندوب للتفاصيل.`;
    const data = {
      kind: "rider_assignment",
      order_id: String(order.id),
      store_id: String(order.store_id),
      title,
      body,
      url: `/rider?store=${encodeURIComponent(String(order.store_id))}`,
    };

    let sent = 0;
    let failed = 0;
    const staleIds: string[] = [];

    for (const row of tokenRows) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              data,
              webpush: {
                headers: {
                  Urgency: "high",
                  TTL: "3600",
                },
              },
            },
          }),
        },
      );

      if (response.ok) {
        sent++;
        continue;
      }

      failed++;
      const text = await response.text();
      if (
        text.includes("UNREGISTERED") ||
        text.includes("registration-token-not-registered")
      ) {
        staleIds.push(row.id);
      }
    }

    if (staleIds.length) {
      await admin.from("rider_push_tokens").delete().in("id", staleIds);
    }

    return json({
      ok: true,
      sent,
      failed,
      removed_stale_tokens: staleIds.length,
      rider_id: rider.id,
      order_id: order.id,
    });
  } catch (error) {
    console.error("send-rider-push", error);
    return json({ error: "Rider push dispatch failed", code: "PUSH_FAILED" }, 500);
  }
});
