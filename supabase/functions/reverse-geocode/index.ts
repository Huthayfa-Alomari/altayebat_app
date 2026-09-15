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
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: userData } = await admin.auth.getUser(jwt);
    if (!userData.user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const lat = Number(body?.lat);
    const lng = Number(body?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return json({ error: "Invalid coordinates" }, 400);
    }

    const base = Deno.env.get("GEOCODING_BASE_URL") || "https://nominatim.openstreetmap.org/reverse";
    const url = new URL(base);
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("lat", String(lat));
    url.searchParams.set("lon", String(lng));
    url.searchParams.set("zoom", "18");
    url.searchParams.set("addressdetails", "1");
    url.searchParams.set("accept-language", "ar,en");

    const response = await fetch(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": "AltayebatApp/0.2 (delivery address lookup)",
      },
    });
    if (!response.ok) return json({ error: "Geocoding unavailable" }, 502);

    const data = await response.json();
    const a = data?.address || {};
    return json({
      ok: true,
      display_name: data?.display_name ?? null,
      city: a.city || a.town || a.village || a.municipality || a.county || null,
      area: a.suburb || a.neighbourhood || a.quarter || a.city_district || null,
      street: a.road || a.pedestrian || a.residential || null,
      building: a.house_number || null,
      postcode: a.postcode || null,
      provider: "openstreetmap_nominatim",
    });
  } catch (error) {
    console.error("reverse-geocode", error);
    return json({ error: "Reverse geocoding failed" }, 500);
  }
});
