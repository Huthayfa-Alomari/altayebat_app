import { createClient } from "npm:@supabase/supabase-js@2.112.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
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
      return Response.json(
        { error: "Payment gateway not configured" },
        { status: 503, headers: corsHeaders },
      );
    }

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const user = userData.user;
    if (userError || !user) {
      return Response.json(
        { error: "Unauthorized" },
        { status: 401, headers: corsHeaders },
      );
    }

    const body = await req.json();
    const orderId = body?.order_id;
    if (typeof orderId !== "string") {
      return Response.json(
        { error: "order_id is required" },
        { status: 400, headers: corsHeaders },
      );
    }

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select(
        "id, customer_id, total, status, payment_method, payment_status, customers(name, phone)",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order || order.customer_id !== user.id) {
      return Response.json(
        { error: "Order not found" },
        { status: 404, headers: corsHeaders },
      );
    }
    if (order.payment_method !== "card") {
      return Response.json(
        { error: "Order is not a card payment" },
        { status: 409, headers: corsHeaders },
      );
    }
    if (order.status === "cancelled") {
      return Response.json(
        { error: "Order is cancelled" },
        { status: 409, headers: corsHeaders },
      );
    }
    if (order.payment_status === "paid") {
      return Response.json(
        { error: "Order is already paid" },
        { status: 409, headers: corsHeaders },
      );
    }

    const customer = Array.isArray(order.customers)
      ? order.customers[0]
      : order.customers;
    const callback = `${supabaseUrl}/functions/v1/paytabs-callback`;
    const returnUrl =
      `${supabaseUrl}/functions/v1/payment-return?order_id=${encodeURIComponent(order.id)}`;

    const paymentResponse = await fetch(`${paytabsBaseUrl}/payment/request`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: serverKey,
      },
      body: JSON.stringify({
        profile_id: Number(profileId),
        tran_type: "sale",
        tran_class: "ecom",
        cart_id: order.id,
        cart_description:
          `Altayebat order ${order.id.slice(0, 8).toUpperCase()}`,
        cart_currency: "JOD",
        cart_amount: Number(order.total),
        paypage_lang: "ar",
        return: returnUrl,
        callback,
        customer_details: {
          name: customer?.name || "Altayebat Customer",
          phone: customer?.phone || "0790000000",
          country: "JO",
        },
      }),
    });

    const paymentData = await paymentResponse.json().catch(() => ({}));
    if (
      !paymentResponse.ok ||
      !paymentData?.redirect_url ||
      !paymentData?.tran_ref
    ) {
      console.error("PayTabs create payment failed", paymentData);
      return Response.json(
        { error: "Unable to create payment" },
        { status: 502, headers: corsHeaders },
      );
    }

    await admin
      .from("orders")
      .update({
        payment_reference: paymentData.tran_ref,
        payment_status: "pending",
        updated_at: new Date().toISOString(),
      })
      .eq("id", order.id)
      .eq("customer_id", user.id);

    return Response.json(
      {
        redirect_url: paymentData.redirect_url,
        tran_ref: paymentData.tran_ref,
      },
      {
        headers: {
          ...corsHeaders,
          "content-type": "application/json",
        },
      },
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: "Internal error" },
      { status: 500, headers: corsHeaders },
    );
  }
});
