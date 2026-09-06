import { createClient } from "npm:@supabase/supabase-js@2.112.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(
      { error: "Method not allowed", code: "METHOD_NOT_ALLOWED" },
      405,
    );
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
      return json(
        {
          error: "Payment gateway not configured",
          code: "PAYTABS_NOT_CONFIGURED",
        },
        503,
      );
    }

    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: userData, error: userError } =
      await admin.auth.getUser(jwt);
    const user = userData.user;
    if (userError || !user) {
      return json(
        { error: "Unauthorized", code: "UNAUTHORIZED" },
        401,
      );
    }

    const body = await req.json();
    const orderId = body?.order_id;
    if (typeof orderId !== "string" || !orderId) {
      return json(
        {
          error: "order_id is required",
          code: "ORDER_ID_REQUIRED",
        },
        400,
      );
    }

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select(
        "id, customer_id, total, status, payment_method, payment_status, payment_reference, customers(name, phone)",
      )
      .eq("id", orderId)
      .maybeSingle();

    if (orderError || !order || order.customer_id !== user.id) {
      return json(
        { error: "Order not found", code: "ORDER_NOT_FOUND" },
        404,
      );
    }
    if (order.payment_method !== "card") {
      return json(
        {
          error: "Order is not a card payment",
          code: "NOT_CARD_ORDER",
        },
        409,
      );
    }
    if (order.status === "cancelled") {
      return json(
        { error: "Order is cancelled", code: "ORDER_CANCELLED" },
        409,
      );
    }
    if (order.payment_status === "paid") {
      return json(
        { error: "Order is already paid", code: "ALREADY_PAID" },
        409,
      );
    }
    if (order.payment_reference) {
      return json(
        {
          error: "Payment already started",
          code: "PAYMENT_ALREADY_STARTED",
          tran_ref: order.payment_reference,
        },
        409,
      );
    }

    const customer = Array.isArray(order.customers)
      ? order.customers[0]
      : order.customers;

    const callback =
      `${supabaseUrl}/functions/v1/paytabs-callback`;
    const returnUrl =
      `${supabaseUrl}/functions/v1/payment-return?order_id=${
        encodeURIComponent(order.id)
      }`;

    const paymentResponse = await fetch(
      `${paytabsBaseUrl}/payment/request`,
      {
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
      },
    );

    const paymentData =
      await paymentResponse.json().catch(() => ({}));

    if (
      !paymentResponse.ok ||
      !paymentData?.redirect_url ||
      !paymentData?.tran_ref
    ) {
      console.error(
        "PayTabs create payment failed",
        paymentData,
      );
      return json(
        {
          error: "Unable to create payment",
          code: "PAYTABS_CREATE_FAILED",
        },
        502,
      );
    }

    const { error: updateError } = await admin
      .from("orders")
      .update({
        payment_reference: paymentData.tran_ref,
        payment_status: "pending",
        updated_at: new Date().toISOString(),
      })
      .eq("id", order.id)
      .eq("customer_id", user.id)
      .is("payment_reference", null);

    if (updateError) {
      console.error(
        "Failed to persist PayTabs reference",
        updateError,
      );
      return json(
        {
          error: "Unable to save payment reference",
          code: "PAYMENT_REFERENCE_SAVE_FAILED",
        },
        500,
      );
    }

    return json({
      redirect_url: paymentData.redirect_url,
      tran_ref: paymentData.tran_ref,
    });
  } catch (error) {
    console.error(error);
    return json(
      { error: "Internal error", code: "INTERNAL_ERROR" },
      500,
    );
  }
});
