import { createClient } from "npm:@supabase/supabase-js@2.112.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: { ...cors, "content-type": "application/json" } });
}
function haversine(lat1:number,lng1:number,lat2:number,lng2:number){
  const r=6371,dLat=(lat2-lat1)*Math.PI/180,dLng=(lng2-lng1)*Math.PI/180;
  const a=Math.sin(dLat/2)**2+Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLng/2)**2;
  return r*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const jwt=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"");
    if(!jwt) return json({error:"Unauthorized"},401);
    const admin=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:userData}=await admin.auth.getUser(jwt);
    if(!userData.user) return json({error:"Unauthorized"},401);

    const b=await req.json().catch(()=>({}));
    const fromLat=Number(b?.from_lat),fromLng=Number(b?.from_lng),toLat=Number(b?.to_lat),toLng=Number(b?.to_lng);
    if([fromLat,fromLng,toLat,toLng].some((v)=>!Number.isFinite(v))) return json({error:"Invalid coordinates"},400);

    const base=Deno.env.get("ROUTING_BASE_URL")||"https://router.project-osrm.org/route/v1/driving";
    try {
      const r=await fetch(`${base}/${fromLng},${fromLat};${toLng},${toLat}?overview=false&steps=false`,{headers:{"User-Agent":"AltayebatApp/0.2"}});
      if(r.ok){
        const data=await r.json(),route=data?.routes?.[0];
        if(route) return json({ok:true,distance_km:Number(route.distance)/1000,duration_minutes:Math.ceil(Number(route.duration)/60),provider:"osrm"});
      }
    } catch (_) {}

    const km=haversine(fromLat,fromLng,toLat,toLng);
    return json({ok:true,distance_km:Number(km.toFixed(2)),duration_minutes:Math.max(8,Math.ceil((km/28)*60)),provider:"haversine_fallback"});
  } catch(error){
    console.error("route-eta",error);
    return json({error:"Routing failed"},500);
  }
});
