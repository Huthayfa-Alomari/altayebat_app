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

type PushTarget = {
  title: string;
  body: string;
  storeId: string;
  customerId?: string;
  data: Record<string, string>;
};

function stringData(value: unknown) {
  if (!value || typeof value !== "object") return {} as Record<string, string>;
  const out: Record<string, string> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (raw === null || raw === undefined) continue;
    out[key] = typeof raw === "string" ? raw : String(raw);
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const rawServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");

    if (!rawServiceAccount) {
      return json({ error: "Firebase is not configured", code: "FCM_NOT_CONFIGURED" }, 503);
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
    const offerId = typeof payload?.offer_id === "string" ? payload.offer_id : "";

    let target: PushTarget | null = null;

    if (orderId) {
      const { data: order, error: orderError } = await admin
        .from("orders")
        .select("id,store_id,customer_id,status")
        .eq("id", orderId)
        .maybeSingle();
      if (orderError || !order) return json({ error: "Order not found" }, 404);

      const { data: membership } = await admin
        .from("store_admins")
        .select("store_id")
        .eq("user_id", user.id)
        .eq("store_id", order.store_id)
        .maybeSingle();
      if (!membership) return json({ error: "Forbidden" }, 403);

      const statusCopy: Record<string, [string, string]> = {
        preparing: ["بدأنا تجهيز طلبك", "فريق أسواق الطيبات يعمل الآن على تجهيز طلبك."],
        out_for_delivery: ["طلبك في الطريق", "السائق خرج بطلبك. افتح التطبيق لمتابعة التوصيل."],
        delivered: ["تم توصيل طلبك", "شكراً لتسوقك من أسواق الطيبات."],
        cancelled: ["تم إلغاء الطلب", "افتح التطبيق لمعرفة التفاصيل أو إعادة الطلب."],
      };
      const statusText = statusCopy[order.status] || ["تحديث على طلبك", "تم تحديث حالة طلبك."];

      const { data: inboxRow } = await admin
        .from("customer_notifications")
        .select("id,type,title,body,data")
        .eq("order_id", order.id)
        .eq("customer_id", order.customer_id)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      const inboxData = stringData(inboxRow?.data);
      const isAdjustment = inboxData.kind === "order_adjusted";

      target = {
        title: isAdjustment ? String(inboxRow?.title || "تم تعديل طلبك") : statusText[0],
        body: isAdjustment ? String(inboxRow?.body || "تم تحديث بعض أصناف طلبك.") : statusText[1],
        storeId: order.store_id,
        customerId: order.customer_id,
        data: isAdjustment
          ? {
              kind: "order_adjusted",
              order_id: order.id,
              ...inboxData,
              ...(inboxRow?.id ? { notification_id: inboxRow.id } : {}),
            }
          : {
              kind: "order_status",
              order_id: order.id,
              status: order.status,
              ...(inboxRow?.id ? { notification_id: inboxRow.id } : {}),
            },
      };
    } else if (offerId) {
      const { data: offer, error: offerError } = await admin
        .from("store_offers")
        .select("id,store_id,product_id,title,subtitle,offer_price_per_unit,is_active")
        .eq("id", offerId)
        .maybeSingle();
      if (offerError || !offer) return json({ error: "Offer not found" }, 404);

      const { data: membership } = await admin
        .from("store_admins")
        .select("store_id")
        .eq("user_id", user.id)
        .eq("store_id", offer.store_id)
        .maybeSingle();
      if (!membership) return json({ error: "Forbidden" }, 403);
      if (!offer.is_active) return json({ error: "Offer is not active" }, 409);

      target = {
        title: offer.title,
        body: offer.subtitle || `عرض جديد بسعر ${Number(offer.offer_price_per_unit).toFixed(2)} د.أ`,
        storeId: offer.store_id,
        data: {
          kind: "offer",
          offer_id: offer.id,
          product_id: offer.product_id,
        },
      };
    }

    if (!target) return json({ error: "order_id or offer_id is required" }, 400);

    let tokenQuery = admin
      .from("customer_push_tokens")
      .select("id,token")
      .eq("store_id", target.storeId);
    if (target.customerId) tokenQuery = tokenQuery.eq("customer_id", target.customerId);

    const { data: tokenRows, error: tokenError } = await tokenQuery;
    if (tokenError) throw tokenError;
    if (!tokenRows?.length) return json({ ok: true, sent: 0, reason: "no_tokens" });

    const serviceAccount = JSON.parse(rawServiceAccount);
    const projectId = serviceAccount.project_id;
    if (!projectId) throw new Error("Firebase service account has no project_id");

    const googleAuth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = await googleAuth.getAccessToken();
    if (!accessToken) throw new Error("Unable to obtain Firebase access token");

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
              notification: { title: target.title, body: target.body },
              data: target.data,
              android: {
                priority: "high",
                notification: { sound: "default" },
              },
              apns: {
                payload: { aps: { sound: "default" } },
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
      if (text.includes("UNREGISTERED") || text.includes("registration-token-not-registered")) {
        staleIds.push(row.id);
      }
    }

    if (staleIds.length) {
      await admin.from("customer_push_tokens").delete().in("id", staleIds);
    }

    return json({ ok: true, sent, failed, removed_stale_tokens: staleIds.length });
  } catch (error) {
    console.error("send-customer-push", error);
    return json({ error: "Push dispatch failed", code: "PUSH_FAILED" }, 500);
  }
});
