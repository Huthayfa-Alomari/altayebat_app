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
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: corsHeaders },
    );
  }

  const serverKey = Deno.env.get("PAYTABS_SERVER_KEY");
  const profileId = Deno.env.get("PAYTABS_PROFILE_ID");
  const baseUrl =
    Deno.env.get("PAYTABS_BASE_URL") ||
    "https://secure-jordan.paytabs.com";

  return Response.json(
    {
      card_enabled: Boolean(serverKey && profileId),
      provider: "paytabs",
      environment: baseUrl.includes("secure-jordan.paytabs.com")
        ? "jordan"
        : "custom",
    },
    {
      headers: {
        ...corsHeaders,
        "content-type": "application/json",
      },
    },
  );
});
