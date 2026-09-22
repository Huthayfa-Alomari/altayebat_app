import { createClient } from "npm:@supabase/supabase-js@2.112.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SOURCE_NAME = "open-food-facts-network";
const SOURCE_LICENSE =
  "Open Food Facts image — CC Attribution-ShareAlike; package artwork may have additional rights.";
const USER_AGENT =
  "Altayebat/1.0 (https://github.com/Huthayfa-Alomari/altayebat_app)";
const PRODUCT_IMAGES_BUCKET = "product-images";
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const LOOKUP_DELAY_MS = 4100;

type ProductRow = {
  id: string;
  name: string;
  barcode: string | null;
  sku: string | null;
  image_url: string | null;
  image_source: string | null;
  image_source_url: string | null;
};

function json(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeDigits(value: string | null | undefined) {
  return (value || "").replace(/\D/g, "");
}

function hasValidGtinCheckDigit(code: string) {
  if (![8, 12, 13, 14].includes(code.length)) return false;
  if (!/^\d+$/.test(code)) return false;

  const digits = code.split("").map(Number);
  const checkDigit = digits.pop()!;
  let sum = 0;
  let weight = 3;

  for (let index = digits.length - 1; index >= 0; index--) {
    sum += digits[index] * weight;
    weight = weight === 3 ? 1 : 3;
  }

  return (10 - (sum % 10)) % 10 === checkDigit;
}

function pickSelectedFront(selectedImages: unknown) {
  if (!selectedImages || typeof selectedImages !== "object") return null;

  const front = (selectedImages as Record<string, unknown>).front;
  if (!front || typeof front !== "object") return null;

  const frontRecord = front as Record<string, unknown>;
  for (const size of ["display", "small", "thumb"]) {
    const value = frontRecord[size];
    if (!value || typeof value !== "object") continue;

    const urls = value as Record<string, unknown>;
    for (const lang of ["ar", "en"]) {
      if (typeof urls[lang] === "string" && urls[lang]) return urls[lang] as string;
    }

    const first = Object.values(urls).find(
      (candidate) => typeof candidate === "string" && candidate.length > 0,
    );
    if (typeof first === "string") return first;
  }

  return null;
}

function pickImageUrl(product: Record<string, unknown>) {
  // Prefer the largest front packshot first. The selected display variant is
  // deliberately secondary because it is often a smaller derivative.
  return (
    (typeof product.image_front_url === "string" ? product.image_front_url : null) ||
    pickSelectedFront(product.selected_images) ||
    (typeof product.image_url === "string" ? product.image_url : null)
  );
}

function openFactsSourceName(url: string) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    if (host.includes("openbeautyfacts")) return "open-beauty-facts";
    if (host.includes("openpetfoodfacts")) return "open-pet-food-facts";
    if (host.includes("openproductsfacts")) return "open-products-facts";
    return "open-food-facts";
  } catch {
    return SOURCE_NAME;
  }
}

function storagePathFromPublicUrl(url: string | null) {
  if (!url) return null;
  const marker = `/storage/v1/object/public/${PRODUCT_IMAGES_BUCKET}/`;
  const index = url.indexOf(marker);
  if (index < 0) return null;
  const encoded = url.slice(index + marker.length).split("?")[0];
  try {
    return decodeURIComponent(encoded);
  } catch {
    return encoded;
  }
}

function extensionForContentType(contentType: string) {
  const normalized = contentType.toLowerCase().split(";")[0].trim();
  if (normalized === "image/jpeg") return { ext: "jpg", contentType: "image/jpeg" };
  if (normalized === "image/png") return { ext: "png", contentType: "image/png" };
  if (normalized === "image/webp") return { ext: "webp", contentType: "image/webp" };
  return null;
}

function upcItemCodes(item: Record<string, unknown>) {
  return [item.ean, item.upc, item.gtin]
    .filter((value): value is string => typeof value === "string")
    .map((value) => normalizeDigits(value))
    .filter(Boolean);
}

function pickUpcItemImage(item: Record<string, unknown>) {
  if (!Array.isArray(item.images)) return null;
  const image = item.images.find(
    (candidate) => typeof candidate === "string" && /^https:\/\//i.test(candidate),
  );
  return typeof image === "string" ? image : null;
}

async function downloadAndStoreImage(
  admin: any,
  storeId: string,
  productId: string,
  imageSourceUrl: string,
  folder: string,
) {
  const imageResponse = await fetch(imageSourceUrl, {
    headers: { "User-Agent": USER_AGENT, Accept: "image/*" },
    redirect: "follow",
  });
  if (!imageResponse.ok) {
    throw new Error(`Image download failed: HTTP ${imageResponse.status}`);
  }

  const declaredLength = Number(imageResponse.headers.get("content-length") || 0);
  if (declaredLength > MAX_IMAGE_BYTES) throw new Error("Image exceeds 5 MB");

  const imageType = extensionForContentType(
    imageResponse.headers.get("content-type") || "",
  );
  if (!imageType) throw new Error("Unsupported image MIME type");

  const bytes = new Uint8Array(await imageResponse.arrayBuffer());
  if (bytes.byteLength > MAX_IMAGE_BYTES) throw new Error("Image exceeds 5 MB");

  const storagePath =
    `${storeId}/${folder}/${productId}-${Date.now()}.${imageType.ext}`;
  const { error: uploadError } = await admin.storage
    .from(PRODUCT_IMAGES_BUCKET)
    .upload(storagePath, bytes, {
      upsert: true,
      contentType: imageType.contentType,
      cacheControl: "31536000",
    });
  if (uploadError) throw uploadError;

  const { data: publicUrlData } = admin.storage
    .from(PRODUCT_IMAGES_BUCKET)
    .getPublicUrl(storagePath);

  return {
    storagePath,
    publicUrl: publicUrlData.publicUrl as string,
    resolvedSourceUrl: imageResponse.url || imageSourceUrl,
  };
}

function decodeHtmlEntities(value: string) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function absoluteUrl(value: string, base: string) {
  try {
    return new URL(decodeHtmlEntities(value), base).toString();
  } catch {
    return null;
  }
}

function pickImageFromHtml(html: string, pageUrl: string) {
  const patterns = [
    /<meta[^>]+property=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["'][^>]*>/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image(?::secure_url)?["'][^>]*>/i,
    /<meta[^>]+name=["']twitter:image(?::src)?["'][^>]+content=["']([^"']+)["'][^>]*>/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]+name=["']twitter:image(?::src)?["'][^>]*>/i,
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match?.[1]) {
      const resolved = absoluteUrl(match[1], pageUrl);
      if (resolved && /^https:\/\//i.test(resolved)) return resolved;
    }
  }

  const jsonLdBlocks = [
    ...html.matchAll(
      /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
    ),
  ];

  const visit = (value: unknown): string | null => {
    if (!value) return null;
    if (Array.isArray(value)) {
      for (const item of value) {
        const found = visit(item);
        if (found) return found;
      }
      return null;
    }
    if (typeof value !== "object") return null;

    const record = value as Record<string, unknown>;
    const type = record["@type"];
    const isProduct =
      type === "Product" ||
      (Array.isArray(type) && type.some((item) => item === "Product"));

    if (isProduct) {
      const image = record.image;
      const candidates = Array.isArray(image) ? image : [image];
      for (const candidate of candidates) {
        if (typeof candidate === "string") {
          const resolved = absoluteUrl(candidate, pageUrl);
          if (resolved && /^https:\/\//i.test(resolved)) return resolved;
        } else if (
          candidate &&
          typeof candidate === "object" &&
          typeof (candidate as Record<string, unknown>).url === "string"
        ) {
          const resolved = absoluteUrl(
            (candidate as Record<string, unknown>).url as string,
            pageUrl,
          );
          if (resolved && /^https:\/\//i.test(resolved)) return resolved;
        }
      }
    }

    for (const nested of Object.values(record)) {
      const found = visit(nested);
      if (found) return found;
    }
    return null;
  };

  for (const block of jsonLdBlocks) {
    try {
      const parsed = JSON.parse(block[1].trim());
      const found = visit(parsed);
      if (found) return found;
    } catch {
      // Ignore malformed structured data and continue to the next block.
    }
  }

  // Some barcode/catalog sites expose the product packshot as a regular
  // image rather than OpenGraph/JSON-LD metadata. Prefer images whose alt
  // text clearly says they are a product image and reject barcode/logo art.
  const imageTags = [...html.matchAll(/<img\b[^>]*>/gi)];
  const candidates: Array<{ url: string; score: number }> = [];

  for (const match of imageTags) {
    const tag = match[0];
    const srcMatch =
      tag.match(/\bsrc=["']([^"']+)["']/i) ||
      tag.match(/\bdata-src=["']([^"']+)["']/i) ||
      tag.match(/\bdata-original=["']([^"']+)["']/i);
    if (!srcMatch?.[1]) continue;

    const alt = tag.match(/\balt=["']([^"']*)["']/i)?.[1] || "";
    const resolved = absoluteUrl(srcMatch[1], pageUrl);
    if (!resolved || !/^https:\/\//i.test(resolved)) continue;

    const text = `${alt} ${resolved}`.toLowerCase();
    if (
      text.includes("barcode") ||
      text.includes("logo") ||
      text.includes("favicon") ||
      text.includes("sprite") ||
      text.includes("placeholder") ||
      text.includes("invalid_icon") ||
      text.includes("/invalid") ||
      text.includes("no-image") ||
      text.includes("no_image") ||
      text.includes("pro_recipes") ||
      text.includes("/recipe/") ||
      text.includes("recipe_")
    ) {
      continue;
    }

    let score = 0;
    if (text.includes("product image")) score += 8;
    if (text.includes("product")) score += 4;
    if (text.includes("image")) score += 1;
    if (/\.(jpe?g|png|webp)(\?|$)/i.test(resolved)) score += 2;
    if (/\b(600|800|1000|1200|1500|2000)\b/.test(resolved)) score += 1;

    if (score > 0) candidates.push({ url: resolved, score });
  }

  candidates.sort((a, b) => b.score - a.score);
  return candidates[0]?.url || null;
}

async function imageFromProductPage(pageUrl: string) {
  const parsed = new URL(pageUrl);
  const host = parsed.hostname.toLowerCase();
  if (
    parsed.protocol !== "https:" ||
    host === "localhost" ||
    host.endsWith(".local") ||
    host === "127.0.0.1" ||
    host === "::1"
  ) {
    throw new Error("A public https product page is required");
  }

  const response = await fetch(pageUrl, {
    headers: {
      "User-Agent": USER_AGENT,
      Accept: "text/html,application/xhtml+xml",
    },
    redirect: "follow",
  });
  if (!response.ok) {
    throw new Error(`Product page fetch failed: HTTP ${response.status}`);
  }

  const contentType = response.headers.get("content-type") || "";
  if (!contentType.toLowerCase().includes("text/html")) {
    throw new Error("Product page did not return HTML");
  }

  const html = (await response.text()).slice(0, 2_000_000);
  const imageUrl = pickImageFromHtml(html, response.url || pageUrl);
  if (!imageUrl) throw new Error("No product image found in page metadata");

  return {
    pageUrl: response.url || pageUrl,
    imageUrl,
  };
}

async function tryGoUpcFallback(
  admin: any,
  storeId: string,
  product: ProductRow,
  code: string,
) {
  const pageUrl = `https://go-upc.com/search?q=${encodeURIComponent(code)}`;
  const response = await fetch(pageUrl, {
    headers: {
      "User-Agent": USER_AGENT,
      Accept: "text/html,application/xhtml+xml",
    },
    redirect: "follow",
  });

  if (response.status === 429) {
    return { status: "rate_limited" as const };
  }
  if (!response.ok) {
    return { status: "error" as const, message: `HTTP ${response.status}` };
  }

  const html = (await response.text()).slice(0, 2_000_000);
  const compactDigits = html.replace(/\D/g, "");
  if (!compactDigits.includes(code)) {
    return { status: "not_found" as const };
  }

  const imageUrl = pickImageFromHtml(html, response.url || pageUrl);
  if (!imageUrl) return { status: "not_found" as const };

  let imageHost = "";
  try {
    imageHost = new URL(imageUrl).hostname.toLowerCase();
  } catch {
    return { status: "not_found" as const };
  }

  // Search pages can contain unrelated site graphics. Only accept the
  // product-image CDN used by Go-UPC for exact catalog results.
  if (
    imageHost !== "go-upc.s3.amazonaws.com" &&
    !imageHost.endsWith(".go-upc.s3.amazonaws.com")
  ) {
    return { status: "not_found" as const };
  }

  const stored = await downloadAndStoreImage(
    admin,
    storeId,
    product.id,
    imageUrl,
    "internet/go-upc",
  );

  const { error: updateError } = await admin
    .from("products")
    .update({
      image_url: stored.publicUrl,
      image_source: "go-upc",
      image_source_url: response.url || pageUrl,
      image_license:
        "Internet barcode catalog image; exact GTIN search page retained for provenance.",
      image_match_method: "exact_gtin_go_upc",
      image_enrichment_status: "matched",
      image_checked_at: new Date().toISOString(),
      image_secondary_source: "go-upc",
      image_secondary_status: "matched",
      image_secondary_checked_at: new Date().toISOString(),
    })
    .eq("id", product.id)
    .eq("store_id", storeId)
    .is("image_url", null);

  if (updateError) throw updateError;
  return { status: "matched" as const, imageUrl: stored.publicUrl };
}

async function runUpcItemDbFallback(
  admin: any,
  storeId: string,
  products: ProductRow[],
) {
  const userKey = Deno.env.get("UPCITEMDB_USER_KEY") || "";
  const keyType = Deno.env.get("UPCITEMDB_KEY_TYPE") || "3scale";
  const maxItems = userKey ? 10 : 2;
  const candidates = products
    .map((product) => ({
      product,
      code: normalizeDigits(product.barcode || product.sku),
    }))
    .filter(({ code }) => hasValidGtinCheckDigit(code))
    .slice(0, maxItems);

  if (candidates.length === 0) {
    return {
      ok: true,
      mode: "internet_fallback",
      processed: 0,
      matched: 0,
      not_found: 0,
      errors: 0,
      rate_limited: false,
      provider: "upcitemdb",
    };
  }

  const endpoint = new URL(
    userKey
      ? "https://api.upcitemdb.com/prod/v1/lookup"
      : "https://api.upcitemdb.com/prod/trial/lookup",
  );
  endpoint.searchParams.set(
    "upc",
    candidates.map(({ code }) => code).join(","),
  );

  const headers: Record<string, string> = {
    "User-Agent": USER_AGENT,
    Accept: "application/json",
    "Accept-Encoding": "gzip, deflate",
  };
  if (userKey) {
    headers.user_key = userKey;
    headers.key_type = keyType;
  }

  const lookupResponse = await fetch(endpoint, {
    headers,
    redirect: "follow",
  });

  if (lookupResponse.status === 429) {
    let goUpcMatched = 0;
    let goUpcNotFound = 0;
    let goUpcErrors = 0;
    let goUpcRateLimited = false;

    for (const { product, code } of candidates) {
      try {
        const fallback = await tryGoUpcFallback(admin, storeId, product, code);
        if (fallback.status === "matched") {
          goUpcMatched++;
        } else if (fallback.status === "rate_limited") {
          goUpcRateLimited = true;
          await admin
            .from("products")
            .update({
              image_secondary_source: "go-upc",
              image_secondary_status: "rate_limited",
              image_secondary_checked_at: new Date().toISOString(),
            })
            .eq("id", product.id)
            .eq("store_id", storeId)
            .is("image_url", null);
        } else {
          goUpcNotFound++;
          await admin
            .from("products")
            .update({
              image_secondary_source: "go-upc",
              image_secondary_status:
                fallback.status === "error" ? "error" : "not_found",
              image_secondary_checked_at: new Date().toISOString(),
            })
            .eq("id", product.id)
            .eq("store_id", storeId)
            .is("image_url", null);
        }
      } catch (error) {
        goUpcErrors++;
        console.error("go-upc-fallback", {
          productId: product.id,
          barcode: code,
          message: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return {
      ok: true,
      mode: "internet_fallback",
      processed: candidates.length,
      matched: goUpcMatched,
      not_found: goUpcNotFound,
      errors: goUpcErrors,
      rate_limited: goUpcRateLimited,
      provider: "go-upc-after-upcitemdb-limit",
      remaining: lookupResponse.headers.get("x-ratelimit-remaining"),
      reset: lookupResponse.headers.get("x-ratelimit-reset"),
    };
  }

  if (lookupResponse.status === 404) {
    let goUpcMatched = 0;
    let goUpcNotFound = 0;
    let goUpcErrors = 0;

    for (const { product, code } of candidates) {
      try {
        const fallback = await tryGoUpcFallback(admin, storeId, product, code);
        if (fallback.status === "matched") {
          goUpcMatched++;
        } else {
          goUpcNotFound++;
          await admin
            .from("products")
            .update({
              image_secondary_source: "go-upc",
              image_secondary_status:
                fallback.status === "rate_limited"
                  ? "rate_limited"
                  : fallback.status === "error"
                    ? "error"
                    : "not_found",
              image_secondary_checked_at: new Date().toISOString(),
            })
            .eq("id", product.id)
            .eq("store_id", storeId)
            .is("image_url", null);
        }
      } catch (error) {
        goUpcErrors++;
      }
    }

    return {
      ok: true,
      mode: "internet_fallback",
      processed: candidates.length,
      matched: goUpcMatched,
      not_found: goUpcNotFound,
      errors: goUpcErrors,
      rate_limited: false,
      provider: "go-upc-after-upcitemdb-404",
    };
  }

  if (!lookupResponse.ok) {
    throw new Error(`UPCitemdb lookup failed: HTTP ${lookupResponse.status}`);
  }

  const body = await lookupResponse.json();
  const items = Array.isArray(body?.items)
    ? (body.items as Record<string, unknown>[])
    : [];

  let matched = 0;
  let notFound = 0;
  let errors = 0;

  for (const { product, code } of candidates) {
    const item = items.find((candidate) => upcItemCodes(candidate).includes(code));
    const imageSourceUrl = item ? pickUpcItemImage(item) : null;
    const externalName =
      item && typeof item.title === "string" ? item.title : null;

    if (!item || !imageSourceUrl) {
      try {
        const fallback = await tryGoUpcFallback(admin, storeId, product, code);
        if (fallback.status === "matched") {
          matched++;
          continue;
        }

        notFound++;
        await admin
          .from("products")
          .update({
            image_secondary_source: "go-upc",
            image_secondary_status:
              fallback.status === "rate_limited"
                ? "rate_limited"
                : fallback.status === "error"
                  ? "error"
                  : "not_found",
            image_secondary_checked_at: new Date().toISOString(),
          })
          .eq("id", product.id)
          .eq("store_id", storeId)
          .is("image_url", null);
      } catch (error) {
        errors++;
        console.error("go-upc-fallback", {
          productId: product.id,
          barcode: code,
          message: error instanceof Error ? error.message : String(error),
        });
      }
      continue;
    }

    try {
      const stored = await downloadAndStoreImage(
        admin,
        storeId,
        product.id,
        imageSourceUrl,
        "internet/upcitemdb",
      );

      const { error: updateError } = await admin
        .from("products")
        .update({
          image_url: stored.publicUrl,
          image_source: "upcitemdb",
          image_source_url: stored.resolvedSourceUrl,
          image_license:
            "UPCitemdb catalog image; original source URL retained for provenance.",
          image_match_method: "exact_gtin_upcitemdb",
          image_external_name: externalName,
          image_enrichment_status: "matched",
          image_checked_at: new Date().toISOString(),
          image_secondary_source: "upcitemdb",
          image_secondary_status: "matched",
          image_secondary_checked_at: new Date().toISOString(),
        })
        .eq("id", product.id)
        .eq("store_id", storeId)
        .is("image_url", null);

      if (updateError) throw updateError;
      matched++;
    } catch (error) {
      errors++;
      console.error("product-image-internet-fallback", {
        productId: product.id,
        barcode: code,
        message: error instanceof Error ? error.message : String(error),
      });

      await admin
        .from("products")
        .update({
          image_secondary_source: "upcitemdb",
          image_secondary_status: "error",
          image_secondary_checked_at: new Date().toISOString(),
        })
        .eq("id", product.id)
        .eq("store_id", storeId)
        .is("image_url", null);
    }
  }

  return {
    ok: true,
    mode: "internet_fallback",
    processed: candidates.length,
    matched,
    not_found: notFound,
    errors,
    rate_limited: false,
    provider: "upcitemdb",
    remaining: lookupResponse.headers.get("x-ratelimit-remaining"),
    reset: lookupResponse.headers.get("x-ratelimit-reset"),
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "Supabase runtime is not configured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const payload = await req.json().catch(() => ({}));
  const storeId = typeof payload?.store_id === "string" ? payload.store_id : "";
  const requestedBatch = Number(payload?.batch_size || 10);
  const batchSize = Math.max(
    1,
    Math.min(Number.isFinite(requestedBatch) ? requestedBatch : 10, 12),
  );
  const retryFailed = payload?.retry_failed === true;
  const retryNotFound = payload?.retry_not_found === true;
  const mode =
    payload?.mode === "refresh_existing"
      ? "refresh_existing"
      : payload?.mode === "internet_fallback"
        ? "internet_fallback"
        : payload?.mode === "manual_candidate"
          ? "manual_candidate"
          : payload?.mode === "manual_page"
            ? "manual_page"
            : "fill_missing";
  const refreshExisting = mode === "refresh_existing";
  const internetFallback = mode === "internet_fallback";
  const manualCandidate = mode === "manual_candidate";
  const manualPage = mode === "manual_page";

  if (!storeId) return json({ error: "store_id is required" }, 400);

  const authorization = req.headers.get("Authorization") || "";
  const jwt = authorization.replace(/^Bearer\s+/i, "");
  const jobToken = req.headers.get("x-image-job-token") || "";

  let authorized = false;

  if (jwt) {
    const { data: userData, error: userError } = await admin.auth.getUser(jwt);
    const user = userData.user;

    if (!userError && user) {
      const { data: membership, error: membershipError } = await admin
        .from("store_admins")
        .select("store_id")
        .eq("user_id", user.id)
        .eq("store_id", storeId)
        .maybeSingle();

      authorized = !membershipError && Boolean(membership);
    }
  }

  if (!authorized && jobToken) {
    const { data: jobAllowed, error: jobAuthError } = await admin.rpc(
      "internal_validate_product_image_job_token",
      { p_store_id: storeId, p_token: jobToken },
    );
    authorized = !jobAuthError && jobAllowed === true;
  }

  if (!authorized) return json({ error: "Forbidden" }, 403);

  if (manualPage) {
    const productId =
      typeof payload?.product_id === "string" ? payload.product_id : "";
    const pageUrl =
      typeof payload?.page_url === "string" ? payload.page_url.trim() : "";
    const candidateSource =
      typeof payload?.source === "string" && payload.source.trim()
        ? payload.source.trim().slice(0, 120)
        : "manual-web-page";
    const candidateExternalName =
      typeof payload?.external_name === "string"
        ? payload.external_name.trim().slice(0, 300)
        : null;

    if (!productId) return json({ error: "product_id is required" }, 400);
    if (!/^https:\/\//i.test(pageUrl)) {
      return json({ error: "A public https page_url is required" }, 400);
    }

    const { data: product, error: productError } = await admin
      .from("products")
      .select("id,name,barcode")
      .eq("id", productId)
      .eq("store_id", storeId)
      .eq("is_available", true)
      .maybeSingle();

    if (productError) return json({ error: productError.message }, 500);
    if (!product) return json({ error: "Product not found" }, 404);

    try {
      const resolved = await imageFromProductPage(pageUrl);
      const stored = await downloadAndStoreImage(
        admin,
        storeId,
        productId,
        resolved.imageUrl,
        "internet/page",
      );

      const { error: updateError } = await admin
        .from("products")
        .update({
          image_url: stored.publicUrl,
          image_source: candidateSource,
          image_source_url: resolved.pageUrl,
          image_license:
            "Internet catalog image; product page retained for provenance.",
          image_match_method: "manual_page_verified",
          image_external_name: candidateExternalName,
          image_enrichment_status: "matched",
          image_checked_at: new Date().toISOString(),
          image_secondary_source: candidateSource,
          image_secondary_status: "matched",
          image_secondary_checked_at: new Date().toISOString(),
        })
        .eq("id", productId)
        .eq("store_id", storeId);

      if (updateError) throw updateError;

      return json({
        ok: true,
        mode,
        product_id: productId,
        product_name: product.name,
        barcode: product.barcode,
        source: candidateSource,
        page_url: resolved.pageUrl,
        resolved_image_url: resolved.imageUrl,
        stored_url: stored.publicUrl,
      });
    } catch (error) {
      return json(
        {
          error: error instanceof Error ? error.message : String(error),
          mode,
          product_id: productId,
        },
        502,
      );
    }
  }

  if (manualCandidate) {
    const productId =
      typeof payload?.product_id === "string" ? payload.product_id : "";
    const candidateUrl =
      typeof payload?.image_url === "string" ? payload.image_url.trim() : "";
    const candidateSource =
      typeof payload?.source === "string" && payload.source.trim()
        ? payload.source.trim().slice(0, 120)
        : "manual-web";
    const candidateExternalName =
      typeof payload?.external_name === "string"
        ? payload.external_name.trim().slice(0, 300)
        : null;

    if (!productId) return json({ error: "product_id is required" }, 400);
    if (!/^https:\/\//i.test(candidateUrl)) {
      return json({ error: "A public https image_url is required" }, 400);
    }

    const parsed = new URL(candidateUrl);
    const host = parsed.hostname.toLowerCase();
    if (
      host === "localhost" ||
      host.endsWith(".local") ||
      host === "127.0.0.1" ||
      host === "::1"
    ) {
      return json({ error: "Private/local image hosts are not allowed" }, 400);
    }

    const { data: product, error: productError } = await admin
      .from("products")
      .select("id,name,barcode,image_url")
      .eq("id", productId)
      .eq("store_id", storeId)
      .eq("is_available", true)
      .maybeSingle();

    if (productError) return json({ error: productError.message }, 500);
    if (!product) return json({ error: "Product not found" }, 404);

    try {
      const stored = await downloadAndStoreImage(
        admin,
        storeId,
        productId,
        candidateUrl,
        "internet/manual",
      );

      const { error: updateError } = await admin
        .from("products")
        .update({
          image_url: stored.publicUrl,
          image_source: candidateSource,
          image_source_url: stored.resolvedSourceUrl,
          image_license:
            "Internet catalog image; source URL retained for provenance.",
          image_match_method: "manual_web_verified",
          image_external_name: candidateExternalName,
          image_enrichment_status: "matched",
          image_checked_at: new Date().toISOString(),
          image_secondary_source: candidateSource,
          image_secondary_status: "matched",
          image_secondary_checked_at: new Date().toISOString(),
        })
        .eq("id", productId)
        .eq("store_id", storeId);

      if (updateError) throw updateError;

      return json({
        ok: true,
        mode,
        product_id: productId,
        product_name: product.name,
        barcode: product.barcode,
        source: candidateSource,
        source_url: stored.resolvedSourceUrl,
        stored_url: stored.publicUrl,
      });
    } catch (error) {
      return json(
        {
          error: error instanceof Error ? error.message : String(error),
          mode,
          product_id: productId,
        },
        502,
      );
    }
  }

  let queue = admin
    .from("products")
    .select("id,name,barcode,sku,image_url,image_source,image_source_url")
    .eq("store_id", storeId)
    .eq("is_available", true)
    .order("image_checked_at", { ascending: true, nullsFirst: true })
    .order("sort_order", { ascending: true })
    .limit(batchSize);

  if (internetFallback) {
    queue = queue
      .is("image_url", null)
      .eq("image_enrichment_status", "not_found")
      .is("image_secondary_status", null);
  } else if (refreshExisting) {
    // Refresh only images already coming from our automated open-catalog
    // pipeline. Source-null/legacy photography is intentionally left alone
    // because it may have been curated manually.
    queue = queue
      .not("image_url", "is", null)
      .in("image_source", [
        "open-food-facts-network",
        "open-food-facts",
        "open-beauty-facts",
        "open-pet-food-facts",
        "open-products-facts",
      ])
      .eq("image_match_method", "exact_gtin");
  } else {
    queue = queue.is("image_url", null);
    if (retryNotFound) {
      queue = queue.or(
        "image_enrichment_status.is.null,image_enrichment_status.eq.not_found,image_enrichment_status.eq.error,image_enrichment_status.eq.needs_review",
      );
    } else if (retryFailed) {
      queue = queue.or("image_enrichment_status.is.null,image_enrichment_status.eq.error");
    } else {
      queue = queue.is("image_enrichment_status", null);
    }
  }

  const { data: productRows, error: queueError } = await queue;
  if (queueError) return json({ error: queueError.message }, 500);

  const products = (productRows || []) as ProductRow[];

  if (internetFallback) {
    try {
      return json(await runUpcItemDbFallback(admin, storeId, products));
    } catch (error) {
      return json(
        {
          error: error instanceof Error ? error.message : String(error),
          mode,
          provider: "upcitemdb",
        },
        502,
      );
    }
  }

  let matched = 0;
  let notFound = 0;
  let needsReview = 0;
  let errors = 0;
  let externalLookups = 0;

  for (let index = 0; index < products.length; index++) {
    const product = products[index];
    const code = normalizeDigits(product.barcode || product.sku);

    if (!hasValidGtinCheckDigit(code)) {
      needsReview++;
      await admin
        .from("products")
        .update({
          image_enrichment_status: "needs_review",
          image_match_method: "non_gtin_or_invalid_gtin",
          image_checked_at: new Date().toISOString(),
        })
        .eq("id", product.id)
        .eq("store_id", storeId)
        .is("image_url", null);
      continue;
    }

    externalLookups++;

    try {
      const endpoint = new URL(
        `https://world.openfoodfacts.org/api/v3/product/${encodeURIComponent(code)}`,
      );
      endpoint.searchParams.set("product_type", "all");
      endpoint.searchParams.set(
        "fields",
        "code,product_name,brands,selected_images,image_front_url,image_url,last_modified_t,last_image_t",
      );

      const lookupResponse = await fetch(endpoint, {
        headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
        redirect: "follow",
      });

      if (lookupResponse.status === 404) {
        notFound++;
        await admin
          .from("products")
          .update({
            image_enrichment_status: "not_found",
            image_match_method: "exact_gtin",
            image_checked_at: new Date().toISOString(),
          })
          .eq("id", product.id)
          .eq("store_id", storeId)
          .is("image_url", null);
      } else if (!lookupResponse.ok) {
        throw new Error(`Catalog lookup failed: HTTP ${lookupResponse.status}`);
      } else {
        const body = await lookupResponse.json();
        const externalProduct =
          body?.product && typeof body.product === "object"
            ? (body.product as Record<string, unknown>)
            : null;
        const imageSourceUrl = externalProduct ? pickImageUrl(externalProduct) : null;
        const externalName =
          externalProduct && typeof externalProduct.product_name === "string"
            ? externalProduct.product_name
            : null;

        if (!imageSourceUrl || !/^https:\/\//i.test(imageSourceUrl)) {
          notFound++;
          await admin
            .from("products")
            .update({
              image_enrichment_status: "not_found",
              image_match_method: "exact_gtin",
              image_external_name: externalName,
              image_checked_at: new Date().toISOString(),
            })
            .eq("id", product.id)
            .eq("store_id", storeId)
            .is("image_url", null);
        } else {
          const imageResponse = await fetch(imageSourceUrl, {
            headers: { "User-Agent": USER_AGENT, Accept: "image/*" },
            redirect: "follow",
          });
          if (!imageResponse.ok) {
            throw new Error(`Image download failed: HTTP ${imageResponse.status}`);
          }

          const declaredLength = Number(imageResponse.headers.get("content-length") || 0);
          if (declaredLength > MAX_IMAGE_BYTES) throw new Error("Image exceeds 5 MB");

          const imageType = extensionForContentType(
            imageResponse.headers.get("content-type") || "",
          );
          if (!imageType) throw new Error("Unsupported image MIME type");

          const bytes = new Uint8Array(await imageResponse.arrayBuffer());
          if (bytes.byteLength > MAX_IMAGE_BYTES) throw new Error("Image exceeds 5 MB");

          const storagePath = refreshExisting
            ? `${storeId}/auto-v2/${product.id}-${Date.now()}.${imageType.ext}`
            : `${storeId}/auto/${product.id}.${imageType.ext}`;
          const { error: uploadError } = await admin.storage
            .from(PRODUCT_IMAGES_BUCKET)
            .upload(storagePath, bytes, {
              upsert: true,
              contentType: imageType.contentType,
              cacheControl: "31536000",
            });
          if (uploadError) throw uploadError;

          const { data: publicUrlData } = admin.storage
            .from(PRODUCT_IMAGES_BUCKET)
            .getPublicUrl(storagePath);

          let updateQuery = admin
            .from("products")
            .update({
              image_url: publicUrlData.publicUrl,
              image_source: openFactsSourceName(lookupResponse.url),
              image_source_url: imageSourceUrl,
              image_license: SOURCE_LICENSE,
              image_match_method: refreshExisting
                ? "exact_gtin_refresh"
                : "exact_gtin",
              image_external_name: externalName,
              image_enrichment_status: "matched",
              image_checked_at: new Date().toISOString(),
            })
            .eq("id", product.id)
            .eq("store_id", storeId);

          if (!refreshExisting) {
            updateQuery = updateQuery.is("image_url", null);
          }

          const { error: updateError } = await updateQuery;
          if (updateError) throw updateError;

          if (
            refreshExisting &&
            product.image_url &&
            product.image_url !== publicUrlData.publicUrl
          ) {
            const oldStoragePath = storagePathFromPublicUrl(product.image_url);
            if (oldStoragePath && oldStoragePath !== storagePath) {
              await admin.storage
                .from(PRODUCT_IMAGES_BUCKET)
                .remove([oldStoragePath])
                .catch(() => undefined);
            }
          }

          matched++;
        }
      }
    } catch (error) {
      errors++;
      const message = error instanceof Error ? error.message : String(error);
      let errorUpdate = admin
        .from("products")
        .update({
          image_enrichment_status: refreshExisting ? "matched" : "error",
          image_match_method: refreshExisting ? "exact_gtin_refresh_error" : "exact_gtin",
          image_checked_at: new Date().toISOString(),
        })
        .eq("id", product.id)
        .eq("store_id", storeId);

      if (!refreshExisting) {
        errorUpdate = errorUpdate.is("image_url", null);
      }
      await errorUpdate;

      console.error("product-image-enrichment", {
        productId: product.id,
        barcode: code,
        message,
      });
    }

    if (index < products.length - 1) await sleep(LOOKUP_DELAY_MS);
  }

  const [{ count: remaining }, { count: totalMatched }, { count: reviewCount }] =
    await Promise.all([
      admin
        .from("products")
        .select("id", { count: "exact", head: true })
        .eq("store_id", storeId)
        .eq("is_available", true)
        .is("image_url", null)
        .is("image_enrichment_status", null),
      admin
        .from("products")
        .select("id", { count: "exact", head: true })
        .eq("store_id", storeId)
        .eq("is_available", true)
        .eq("image_enrichment_status", "matched"),
      admin
        .from("products")
        .select("id", { count: "exact", head: true })
        .eq("store_id", storeId)
        .eq("is_available", true)
        .eq("image_enrichment_status", "needs_review"),
    ]);

  return json({
    ok: true,
    mode,
    processed: products.length,
    external_lookups: externalLookups,
    matched,
    not_found: notFound,
    needs_review: needsReview,
    errors,
    remaining_unchecked: remaining || 0,
    total_matched: totalMatched || 0,
    total_needs_review: reviewCount || 0,
  });
});
