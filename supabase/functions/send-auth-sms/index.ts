import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

type HookEvent = {
  user?: {
    id?: string;
    phone?: string;
  };
  sms?: {
    otp?: string;
  };
};

type RenderContext = {
  phone: string;
  otp: string;
  message: string;
  sender: string;
};

function json(body: unknown, status = 200, extraHeaders: HeadersInit = {}) {
  return Response.json(body, {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...extraHeaders,
    },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function maskedPhone(phone: string): string {
  if (phone.length <= 5) return "***";
  return `${phone.slice(0, 4)}***${phone.slice(-3)}`;
}

function renderString(value: string, context: RenderContext): string {
  return value
    .replaceAll("{{phone}}", context.phone)
    .replaceAll("{{otp}}", context.otp)
    .replaceAll("{{message}}", context.message)
    .replaceAll("{{sender}}", context.sender);
}

function renderValue(value: unknown, context: RenderContext): unknown {
  if (typeof value === "string") return renderString(value, context);
  if (Array.isArray(value)) return value.map((item) => renderValue(item, context));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, item]) => [
        key,
        renderValue(item, context),
      ]),
    );
  }
  return value;
}

function buildProviderPayload(context: RenderContext): Record<string, unknown> {
  const payloadTemplate = Deno.env.get("SMS_PROVIDER_PAYLOAD_TEMPLATE")?.trim();

  if (payloadTemplate) {
    const parsed = JSON.parse(payloadTemplate);
    const rendered = renderValue(parsed, context);
    if (!rendered || typeof rendered !== "object" || Array.isArray(rendered)) {
      throw new Error("SMS_PROVIDER_PAYLOAD_TEMPLATE must be a JSON object");
    }
    return rendered as Record<string, unknown>;
  }

  const toField = Deno.env.get("SMS_FIELD_TO")?.trim() || "to";
  const messageField = Deno.env.get("SMS_FIELD_MESSAGE")?.trim() || "message";
  const senderField = Deno.env.get("SMS_FIELD_SENDER")?.trim() || "sender";

  return {
    [toField]: context.phone,
    [messageField]: context.message,
    [senderField]: context.sender,
  };
}

function buildProviderHeaders(contentType: string): Headers {
  const headers = new Headers({ "content-type": contentType });

  const rawHeaders = Deno.env.get("SMS_PROVIDER_HEADERS_JSON")?.trim();
  if (rawHeaders) {
    const parsed = JSON.parse(rawHeaders) as Record<string, unknown>;
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value === "string") headers.set(key, value);
    }
  }

  const apiKey = Deno.env.get("SMS_PROVIDER_API_KEY")?.trim();
  if (apiKey) {
    const authHeader =
      Deno.env.get("SMS_PROVIDER_AUTH_HEADER")?.trim() || "Authorization";
    const authScheme = Deno.env.get("SMS_PROVIDER_AUTH_SCHEME")?.trim();
    headers.set(authHeader, authScheme ? `${authScheme} ${apiKey}` : apiKey);
  }

  return headers;
}

function formBody(payload: Record<string, unknown>): URLSearchParams {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(payload)) {
    if (value == null) continue;
    if (typeof value === "object") {
      body.set(key, JSON.stringify(value));
    } else {
      body.set(key, String(value));
    }
  }
  return body;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const startedAt = Date.now();
  let phoneForLog = "unknown";

  try {
    const hookSecret = requireEnv("SEND_SMS_HOOK_SECRET").replace(
      /^v1,whsec_/,
      "",
    );

    const rawBody = await req.text();
    const webhook = new Webhook(hookSecret);

    let event: HookEvent;
    try {
      event = webhook.verify(
        rawBody,
        Object.fromEntries(req.headers.entries()),
      ) as HookEvent;
    } catch {
      return json({ error: "Invalid webhook signature" }, 401);
    }

    const phone = event.user?.phone?.trim() || "";
    const otp = event.sms?.otp?.trim() || "";
    phoneForLog = maskedPhone(phone);

    if (!phone || !otp) {
      return json({ error: "Invalid Send SMS hook payload" }, 400);
    }

    const allowedPrefix = Deno.env.get("SMS_ALLOWED_PHONE_PREFIX")?.trim();
    if (allowedPrefix && !phone.startsWith(allowedPrefix)) {
      console.warn("send-auth-sms blocked phone prefix", {
        phone: phoneForLog,
      });
      return json({ error: "Phone number is not allowed" }, 400);
    }

    const providerUrl = requireEnv("SMS_PROVIDER_URL");
    const sender = Deno.env.get("SMS_SENDER_ID")?.trim() || "Altayebat";
    const messageTemplate =
      Deno.env.get("SMS_MESSAGE_TEMPLATE")?.trim() ||
      "رمز التحقق لأسواق الطيبات: {{otp}}. لا تشارك الرمز مع أحد.";

    const message = renderString(messageTemplate, {
      phone,
      otp,
      message: "",
      sender,
    });

    const context: RenderContext = {
      phone,
      otp,
      message,
      sender,
    };

    const payload = buildProviderPayload(context);
    const bodyFormat =
      Deno.env.get("SMS_PROVIDER_BODY_FORMAT")?.trim().toLowerCase() || "json";
    const method = Deno.env.get("SMS_PROVIDER_METHOD")?.trim().toUpperCase() || "POST";

    const contentType =
      bodyFormat === "form"
        ? "application/x-www-form-urlencoded"
        : "application/json";

    const headers = buildProviderHeaders(contentType);
    const body =
      bodyFormat === "form"
        ? formBody(payload).toString()
        : JSON.stringify(payload);

    const response = await fetch(providerUrl, {
      method,
      headers,
      body,
      signal: AbortSignal.timeout(3200),
    });

    const responseText = await response.text();

    if (!response.ok) {
      console.error("send-auth-sms provider failure", {
        phone: phoneForLog,
        status: response.status,
        duration_ms: Date.now() - startedAt,
        provider_response: responseText.slice(0, 300),
      });

      return json(
        { error: "SMS provider temporarily unavailable" },
        503,
        { "retry-after": "true" },
      );
    }

    console.log("send-auth-sms delivered to provider", {
      phone: phoneForLog,
      status: response.status,
      duration_ms: Date.now() - startedAt,
    });

    return json({});
  } catch (error) {
    console.error("send-auth-sms internal error", {
      phone: phoneForLog,
      duration_ms: Date.now() - startedAt,
      error: error instanceof Error ? error.message : String(error),
    });

    return json(
      { error: "SMS delivery service is not configured" },
      503,
      { "retry-after": "true" },
    );
  }
});
