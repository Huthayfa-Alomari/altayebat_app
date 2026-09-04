import { createClient } from "npm:@supabase/supabase-js@2.112.4";

Deno.serve(async (req: Request) => {
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
      return new Response("Not configured", { status: 503 });
    }

    const callback = await req.json();
    const orderId = callback?.cart_id;
    const tranRef = callback?.tran_ref;
    if (typeof orderId !== "string" || typeof tranRef !== "string") {
      return new Response("Invalid payload", { status: 400 });
    }

    const queryResponse = await fetch(`${paytabsBaseUrl}/payment/query`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: serverKey,
      },
      body: JSON.stringify({
        profile_id: Number(profileId),
        tran_ref: tranRef,
      }),
    });
    const verified = await queryResponse.json().catch(() => ({}));
    if (
      !queryResponse.ok ||
      verified?.tran_ref !== tranRef ||
      verified?.cart_id !== orderId
    ) {
      console.error("PayTabs verification failed", verified);
      return new Response("Verification failed", { status: 400 });
    }

    const responseStatus = verified?.payment_result?.response_status;
    const paymentStatus = responseStatus === "A"
      ? "paid"
      : responseStatus === "D" ||
          responseStatus === "E" ||
          responseStatus === "X"
      ? "failed"
      : "pending";

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { data: finalization, error } = await admin.rpc(
      "finalize_card_payment",
      {
        p_order_id: orderId,
        p_tran_ref: tranRef,
        p_payment_status: paymentStatus,
      },
    );

    if (error) {
      console.error("Card finalization failed", error);
      return new Response("Database update failed", { status: 500 });
    }

    if (finalization === "failed_requires_review") {
      console.warn(
        "Card payment failed after fulfilment advanced; admin review required",
        { orderId, tranRef },
      );
    } else if (finalization === "cancelled" && paymentStatus === "paid") {
      console.error(
        "Authorised payment arrived for an already cancelled/restocked order",
        { orderId, tranRef },
      );
    }

    return new Response("OK", { status: 200 });
  } catch (error) {
    console.error(error);
    return new Response("Internal error", { status: 500 });
  }
});
