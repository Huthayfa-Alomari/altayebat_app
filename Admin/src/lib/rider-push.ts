import type { SupabaseClient } from "@supabase/supabase-js";

type FirebaseMessagingCompat = {
  getToken(options: {
    vapidKey: string;
    serviceWorkerRegistration: ServiceWorkerRegistration;
  }): Promise<string>;
};

type FirebaseCompatNamespace = {
  apps: unknown[];
  initializeApp(config: Record<string, string>): unknown;
  messaging(): FirebaseMessagingCompat;
};

declare global {
  interface Window {
    firebase?: FirebaseCompatNamespace;
  }
}

const TOKEN_KEY = "altayebat_rider_fcm_token";
const FIREBASE_VERSION = "11.10.0";

function firebaseConfig() {
  return {
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY || "",
    authDomain:
      process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN ||
      "altayebat-4cb36.firebaseapp.com",
    projectId:
      process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID || "altayebat-4cb36",
    messagingSenderId:
      process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID || "534447632380",
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID || "",
  };
}

export function riderPushConfigured() {
  const config = firebaseConfig();
  return Boolean(
    config.apiKey &&
      config.appId &&
      config.projectId &&
      config.messagingSenderId &&
      process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY,
  );
}

function loadScript(src: string, marker: string) {
  return new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(
      `script[data-rider-push="${marker}"]`,
    );
    if (existing) {
      if (existing.dataset.loaded === "true") resolve();
      else {
        existing.addEventListener("load", () => resolve(), { once: true });
        existing.addEventListener(
          "error",
          () => reject(new Error("تعذر تحميل خدمة الإشعارات")),
          { once: true },
        );
      }
      return;
    }

    const script = document.createElement("script");
    script.src = src;
    script.async = true;
    script.dataset.riderPush = marker;
    script.addEventListener(
      "load",
      () => {
        script.dataset.loaded = "true";
        resolve();
      },
      { once: true },
    );
    script.addEventListener(
      "error",
      () => reject(new Error("تعذر تحميل خدمة الإشعارات")),
      { once: true },
    );
    document.head.appendChild(script);
  });
}

async function messaging() {
  await loadScript(
    `https://www.gstatic.com/firebasejs/${FIREBASE_VERSION}/firebase-app-compat.js`,
    "firebase-app",
  );
  await loadScript(
    `https://www.gstatic.com/firebasejs/${FIREBASE_VERSION}/firebase-messaging-compat.js`,
    "firebase-messaging",
  );

  const firebase = window.firebase;
  if (!firebase) throw new Error("تعذر تهيئة Firebase");
  if (firebase.apps.length === 0) firebase.initializeApp(firebaseConfig());
  return firebase.messaging();
}

export type RiderPushResult =
  | { status: "ready"; token: string }
  | { status: "permission_required" }
  | { status: "denied" }
  | { status: "unsupported" }
  | { status: "not_configured" };

export async function registerRiderPush(
  supabase: SupabaseClient,
  requestPermission = true,
): Promise<RiderPushResult> {
  if (typeof window === "undefined") return { status: "unsupported" };
  if (
    !window.isSecureContext ||
    !("serviceWorker" in navigator) ||
    !("Notification" in window)
  ) {
    return { status: "unsupported" };
  }
  if (!riderPushConfigured()) return { status: "not_configured" };

  let permission = window.Notification.permission;
  if (permission === "default" && requestPermission) {
    permission = await window.Notification.requestPermission();
  }
  if (permission === "default") return { status: "permission_required" };
  if (permission !== "granted") return { status: "denied" };

  const registration = await navigator.serviceWorker.register(
    "/api/rider-push-sw",
    { scope: "/", updateViaCache: "none" },
  );
  await registration.update().catch(() => undefined);

  const firebaseMessaging = await messaging();
  const token = await firebaseMessaging.getToken({
    vapidKey: process.env.NEXT_PUBLIC_FIREBASE_VAPID_KEY!,
    serviceWorkerRegistration: registration,
  });
  if (!token) throw new Error("لم نحصل على رمز الإشعارات من Firebase");

  const { error } = await supabase.rpc("register_rider_push_token", {
    p_token: token,
    p_platform: "web",
  });
  if (error) throw error;

  window.localStorage.setItem(TOKEN_KEY, token);
  return { status: "ready", token };
}

export async function syncRiderPushIfGranted(supabase: SupabaseClient) {
  if (typeof window === "undefined" || !("Notification" in window)) {
    return { status: "unsupported" } as RiderPushResult;
  }
  if (window.Notification.permission !== "granted") {
    return { status: "permission_required" } as RiderPushResult;
  }
  return registerRiderPush(supabase, false);
}

export function storedRiderPushToken() {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(TOKEN_KEY);
}
