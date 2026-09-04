Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const orderId = url.searchParams.get("order_id") || "";
  const body = `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>أسواق الطيبات</title><style>body{font-family:Arial,sans-serif;background:#f8f8f8;margin:0;display:grid;place-items:center;min-height:100vh}.card{background:white;padding:28px;border-radius:18px;max-width:420px;text-align:center;box-shadow:0 8px 30px #00000012}h1{color:#e91f2d;font-size:24px}p{line-height:1.8;color:#444}.ref{font-family:monospace}</style></head><body><div class="card"><h1>تمت العودة من بوابة الدفع</h1><p>سيتم تحديث حالة الدفع تلقائيًا بعد تأكيد العملية من PayTabs.</p>${orderId ? `<p class="ref">طلب #${orderId.slice(0, 8).toUpperCase()}</p>` : ""}<p>يمكنك الآن الرجوع إلى تطبيق أسواق الطيبات ومتابعة الطلب.</p></div></body></html>`;

  return new Response(body, {
    headers: { "content-type": "text/html; charset=utf-8" },
  });
});
