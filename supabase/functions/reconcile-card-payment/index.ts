import { createClient } from "npm:@supabase/supabase-js@2.112.4";

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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const serverKey = Deno.env.get("PAYTABS_SERVER_KEY");
    const profileId = Deno.env.get("PAYTABS_PROFILE_ID");
    const paytabsBaseUrl =
      Deno.env.get("PAYTABS_BASE_URL") ||
      "https://secure-jordan.paytabs.com";

    if (!serverKey || !profileId) {
      return json({ error: "Payment gateway not configured" }, 503);
    }

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const user = userData.user;
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const orderId = body?.order_id;
    if (typeof orderId !== "string" || !orderId) {
      return json({ error: "order_id is required" }, 400);
    }

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select(
        "id, store_id, customer_id, status, payment_method, payment_status, payment_reference, created_at",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order) return json({ error: "Order not found" }, 404);

    let authorised = order.customer_id === user.id;
    if (!authorised) {
      const { data: storeAdmin } = await admin
        .from("store_admins")
        .select("user_id")
        .eq("user_id", user.id)
        .eq("store_id", order.store_id)
        .maybeSingle();
      authorised = Boolean(storeAdmin);
    }
    if (!authorised) return json({ error: "Forbidden" }, 403);

    if (order.payment_method !== "card") {
      return json({ error: "Order is not a card payment" }, 409);
    }

    if (order.payment_status === "paid") {
      return json({
        payment_status: "paid",
        order_status: order.status,
        finalization: order.status === "cancelled"
          ? "paid_requires_refund"
          : "paid",
      });
    }

    const createdAt = new Date(order.created_at).getTime();
    const ageMinutes = Number.isFinite(createdAt)
      ? (Date.now() - createdAt) / 60000
      : 0;

    // If PayTabs never returned a transaction reference, no payment page was
    // successfully created. After the hosted-page timeout window plus a safety
    // buffer, release the reservation.
    if (!order.payment_reference) {
      if (ageMinutes < 25 || order.status !== "pending") {
        return json({
          payment_status: order.payment_status,
          order_status: order.status,
          finalization: "pending",
          retry_after_seconds: Math.max(0, Math.ceil((25 - ageMinutes) * 60)),
        });
      }

      const { data: finalization, error: finalizeError } = await admin.rpc(
        "finalize_card_payment",
        {
          p_order_id: order.id,
          p_tran_ref: null,
          p_payment_status: "failed",
        },
      );
      if (finalizeError) {
        console.error("Unstarted card finalization failed", finalizeError);
        return json({ error: "Database update failed" }, 500);
      }
      return json({
        payment_status: "failed",
        order_status: finalization === "cancelled" ? "cancelled" : order.status,
        finalization,
        gateway_status: "NO_REFERENCE",
      });
    }

    const queryResponse = await fetch(`${paytabsBaseUrl}/payment/query`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: serverKey,
      },
      body: JSON.stringify({
        profile_id: Number(profileId),
        tran_ref: order.payment_reference,
      }),
    });
    const verified = await queryResponse.json().catch(() => ({}));

    if (!queryResponse.ok) {
      console.error("PayTabs reconciliation query failed", verified);
      return json({ error: "Unable to verify payment" }, 502);
    }
    if (
      verified?.tran_ref !== order.payment_reference ||
      verified?.cart_id !== order.id
    ) {
      console.error("PayTabs reconciliation identity mismatch", {
        orderId: order.id,
        paymentReference: order.payment_reference,
        verified,
      });
      return json({ error: "Payment verification mismatch" }, 409);
    }

    const gatewayStatus = verified?.payment_result?.response_status;
    const paymentStatus = gatewayStatus === "A"
      ? "paid"
      : gatewayStatus === "D" ||
          gatewayStatus === "E" ||
          gatewayStatus === "X" ||
          gatewayStatus === "V"
      ? "failed"
      : "pending";

    const { data: finalization, error: finalizeError } = await admin.rpc(
      "finalize_card_payment",
      {
        p_order_id: order.id,
        p_tran_ref: order.payment_reference,
        p_payment_status: paymentStatus,
      },
    );
    if (finalizeError) {
      console.error("Card reconciliation finalization failed", finalizeError);
      return json({ error: "Database update failed" }, 500);
    }

    if (finalization === "paid_requires_refund") {
      console.error(
        "Reconciliation found an authorised payment on a cancelled order; refund review required",
        { orderId: order.id, tranRef: order.payment_reference },
      );
    }

    return json({
      payment_status: paymentStatus,
      order_status: finalization === "cancelled" ? "cancelled" : order.status,
      finalization,
      gateway_status: gatewayStatus ?? null,
    });
  } catch (error) {
    console.error(error);
    return json({ error: "Internal error" }, 500);
  }
});
