import { createClient } from "npm:@supabase/supabase-js@2.112.4";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
function json(body:unknown,status=200){return Response.json(body,{status,headers:{...cors,"content-type":"application/json"}})}
function cleanTokens(text:string){return [...new Set(text.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu," ").split(/\s+/).filter((x)=>x.length>=2))].slice(0,20)}
function normalizeDigits(text:string){const ar="٠١٢٣٤٥٦٧٨٩",fa="۰۱۲۳۴۵۶۷۸۹";return text.replace(/[٠-٩]/g,(d)=>String(ar.indexOf(d))).replace(/[۰-۹]/g,(d)=>String(fa.indexOf(d)))}
function budgetFrom(text:string){
  const t=normalizeDigits(text).replace(/,/g,".");
  const keyword=t.match(/(?:ميزاني(?:ة|تي)|بحدود|حدود|تحت|حد\s*(?:أقصى|اقصى)|budget|max(?:imum)?)\s*(?:هي|هو|حوالي|تقريب(?:ا|اً)?|[:=-])?\s*(\d+(?:\.\d+)?)/i);
  const currency=t.match(/(\d+(?:\.\d+)?)\s*(?:د\.?\s*أ?\.?|دينار(?:ات)?|jd|jod)/i);
  const raw=keyword?.[1]??currency?.[1];
  if(!raw) return null;
  const value=Number(raw);
  return Number.isFinite(value)&&value>0?value:null;
}
async function askOpenRouter(prompt:string,budget:number|null,candidates:any[]){
  const key=Deno.env.get("OPENROUTER_API_KEY"); if(!key) return null;
  const model=Deno.env.get("OPENROUTER_MODEL")||"openrouter/free";
  const sys=`أنت مساعد تسوق لمتجر أردني. اختر فقط من المنتجات المعطاة. أعد JSON فقط بالشكل {\"message\":\"...\",\"items\":[{\"id\":\"uuid\",\"quantity\":1,\"reason\":\"...\"}]}. لا تختر منتجاً غير موجود. احترم الميزانية قدر الإمكان. كن مختصراً وبالعربية.`;
  try{
    const r=await fetch("https://openrouter.ai/api/v1/chat/completions",{method:"POST",headers:{Authorization:`Bearer ${key}`,"Content-Type":"application/json","HTTP-Referer":"https://altayebat.app","X-Title":"Altayebat Smart Shopping"},body:JSON.stringify({model,temperature:0.2,response_format:{type:"json_object"},messages:[{role:"system",content:sys},{role:"user",content:`طلب العميل: ${prompt}\nالميزانية: ${budget??"غير محددة"}\nالمنتجات: ${JSON.stringify(candidates)}`}]})});
    if(!r.ok){console.error("openrouter",r.status,await r.text());return null}
    const d=await r.json(); const content=d?.choices?.[0]?.message?.content||""; try{return {...JSON.parse(content),provider:`openrouter:${model}`}}catch{console.error("openrouter json parse failed");return null}
  }catch(e){console.error("openrouter request",e);return null}
}
async function askGroq(prompt:string,budget:number|null,candidates:any[]){
  const key=Deno.env.get("GROQ_API_KEY"); if(!key) return null;
  const model=Deno.env.get("GROQ_MODEL")||"llama-3.3-70b-versatile";
  const sys=`أنت مساعد تسوق لمتجر أردني. اختر فقط من المنتجات المعطاة. أعد JSON فقط بالشكل {\"message\":\"...\",\"items\":[{\"id\":\"uuid\",\"quantity\":1,\"reason\":\"...\"}]}. لا تختر منتجاً غير موجود. احترم الميزانية قدر الإمكان.`;
  try{
    const r=await fetch("https://api.groq.com/openai/v1/chat/completions",{method:"POST",headers:{Authorization:`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify({model,temperature:0.2,response_format:{type:"json_object"},messages:[{role:"system",content:sys},{role:"user",content:`طلب العميل: ${prompt}\nالميزانية: ${budget??"غير محددة"}\nالمنتجات: ${JSON.stringify(candidates)}`}]})});
    if(!r.ok){console.error("groq",r.status,await r.text());return null}
    const d=await r.json(); try{return {...JSON.parse(d?.choices?.[0]?.message?.content||"{}"),provider:`groq:${model}`}}catch{return null}
  }catch(e){console.error("groq request",e);return null}
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(req.method!=="POST") return json({error:"Method not allowed"},405);
  try{
    const jwt=(req.headers.get("Authorization")||"").replace(/^Bearer\s+/i,"");
    if(!jwt) return json({error:"Unauthorized"},401);
    const url=Deno.env.get("SUPABASE_URL")!, key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data:userData}=await admin.auth.getUser(jwt); const user=userData.user;
    if(!user) return json({error:"Unauthorized"},401);
    const body=await req.json().catch(()=>({}));
    const prompt=String(body?.prompt||"").trim(); const storeId=String(body?.store_id||"").trim();
    if(prompt.length<3||prompt.length>600||!storeId) return json({error:"Invalid request"},400);
    const {data:store}=await admin.from("stores").select("id,name,is_active").eq("id",storeId).maybeSingle();
    if(!store?.is_active) return json({error:"Store unavailable"},409);

    const {data:reqRow,error:reqErr}=await admin.from("ai_basket_requests").insert({store_id:storeId,customer_id:user.id,prompt,status:"processing",started_at:new Date().toISOString()}).select("id").single();
    if(reqErr) throw reqErr;

    const {data:products,error:pErr}=await admin.from("products").select("id,name,description,price,image_url,stock_qty,is_available,category_id,sale_type,base_unit,inventory_scale,price_per_unit,min_qty,qty_step,allow_amount_purchase").eq("store_id",storeId).eq("is_available",true).gt("stock_qty",0).order("name").limit(180);
    if(pErr) throw pErr;
    const catalog=(products||[]) as any[]; const tokens=cleanTokens(prompt); const budget=budgetFrom(prompt);
    const scored=catalog.map((p)=>{
      const hay=`${p.name||""} ${p.description||""}`.toLowerCase();
      let score=tokens.reduce((s,t)=>s+(hay.includes(t)?4:0),0);
      if(/فطور|breakfast/.test(prompt.toLowerCase())&&/(حليب|لبن|جبن|خبز|بيض|شاي|قهوة)/.test(hay)) score+=5;
      if(/مقلوب|منسف|كبسة|طبخ|غدا|غداء|عشا|عشاء|وصفة/.test(prompt)&&/(رز|أرز|دجاج|لحم|لبن|بهار|زيت|خضار)/.test(hay)) score+=4;
      if(/تنظيف|منظف/.test(prompt)&&/(منظف|كلور|صابون|مسحوق|سائل)/.test(hay)) score+=5;
      return {p,score};
    }).sort((a,b)=>b.score-a.score || Number(a.p.price_per_unit||a.p.price)-Number(b.p.price_per_unit||b.p.price));

    const candidates=scored.slice(0,80).map(({p})=>({id:p.id,name:p.name,price:Number(p.price_per_unit||p.price),stock:p.stock_qty,sale_type:p.sale_type}));
    let result:any=await askOpenRouter(prompt,budget,candidates);
    if(!result) result=await askGroq(prompt,budget,candidates);

    const byId=new Map(catalog.map((p)=>[p.id,p]));
    if(!result?.items?.length){
      const picks:any[]=[]; let total=0;
      for(const {p,score} of scored){
        if(picks.length>=8) break; if(score<=0 && picks.length>=4) break;
        const unit=Number(p.price_per_unit||p.price||0); if(unit<=0) continue;
        if(budget && total+unit>budget && picks.length>0) continue;
        picks.push({id:p.id,quantity:1,reason:score>0?"مناسب لطلبك":"اقتراح متوفر من المتجر"}); total+=unit;
      }
      result={message:picks.length?"جهزت لك اقتراحات من المنتجات المتوفرة حالياً.":"ما لقيت منتجات مطابقة بشكل كافٍ. جرّب وصف طلبك بتفاصيل أكثر.",items:picks,provider:"catalog_fallback"};
    }

    const normalized=[]; let estimate=0;
    for(const item of Array.isArray(result.items)?result.items:[]){
      const p=byId.get(String(item.id)); if(!p) continue;
      let q=Math.max(1,Math.min(Number(item.quantity)||1,20)); if(p.sale_type&&p.sale_type!=="piece") q=Number(p.min_qty||100);
      const linePrice=p.sale_type&&p.sale_type!=="piece"?Number(p.price||0)*q:Number(p.price_per_unit||p.price||0)*q;
      estimate+=linePrice;
      normalized.push({...p,quantity:q,reason:String(item.reason||"اقتراح ذكي")});
      if(normalized.length>=10) break;
    }
    const output={request_id:reqRow.id,message:String(result.message||"هذه أفضل الاقتراحات المتاحة."),items:normalized,total_estimate:Number(estimate.toFixed(2)),provider:result.provider||"catalog_fallback",budget};
    await admin.from("ai_basket_requests").update({status:"completed",result:output,completed_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("id",reqRow.id);
    return json(output);
  }catch(error){console.error("smart-shopping-assistant",error);return json({error:"AI assistant failed"},500)}
});
