import { createClient } from "npm:@supabase/supabase-js@2.112.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "Server configuration error" }, 500);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  const user = userData.user;
  if (userError || !user) return json({ error: "Unauthorized" }, 401);

  const { data: storeAdmin, error: adminError } = await admin
    .from("store_admins")
    .select("store_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();

  if (adminError) return json({ error: "Authorization check failed" }, 500);
  if (!storeAdmin) return json({ error: "Forbidden" }, 403);

  const key = Deno.env.get("OPENROUTER_API_KEY");
  const model = Deno.env.get("OPENROUTER_MODEL") || "openrouter/free";
  if (!key) return json({ ok: false, secret: false, model }, 503);

  try {
    const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://altayebat.app",
        "X-Title": "Altayebat AI Health Check",
      },
      body: JSON.stringify({
        model,
        max_tokens: 24,
        temperature: 0,
        messages: [{ role: "user", content: "Reply with exactly: OK" }],
      }),
    });

    const text = await r.text();
    return json({
      ok: r.ok,
      secret: true,
      model,
      upstream_status: r.status,
      sample: r.ok ? text.slice(0, 300) : text.slice(0, 500),
    }, r.ok ? 200 : 502);
  } catch (e) {
    return json({ ok: false, secret: true, model, error: String(e) }, 500);
  }
});
