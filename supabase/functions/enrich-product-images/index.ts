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
  const mode = payload?.mode === "refresh_existing" ? "refresh_existing" : "fill_missing";
  const refreshExisting = mode === "refresh_existing";

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

  let queue = admin
    .from("products")
    .select("id,name,barcode,sku,image_url,image_source,image_source_url")
    .eq("store_id", storeId)
    .eq("is_available", true)
    .order("image_checked_at", { ascending: true, nullsFirst: true })
    .order("sort_order", { ascending: true })
    .limit(batchSize);

  if (refreshExisting) {
    // Refresh only images already coming from our automated open-catalog
    // pipeline (plus legacy rows with no source). This avoids overwriting
    // deliberately curated/manual photography.
    queue = queue
      .not("image_url", "is", null)
      .or(
        "image_source.eq.open-food-facts-network,image_source.eq.open-food-facts,image_source.eq.open-beauty-facts,image_source.eq.open-pet-food-facts,image_source.eq.open-products-facts,image_source.is.null",
      );
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
