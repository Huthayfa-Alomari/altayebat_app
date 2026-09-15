const FIREBASE_VERSION = "11.10.0";

export const dynamic = "force-dynamic";

export async function GET() {
  const firebaseConfig = {
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

  const script = `
importScripts("https://www.gstatic.com/firebasejs/${FIREBASE_VERSION}/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/${FIREBASE_VERSION}/firebase-messaging-compat.js");

const firebaseConfig = ${JSON.stringify(firebaseConfig)};

if (firebaseConfig.apiKey && firebaseConfig.appId && firebaseConfig.projectId && firebaseConfig.messagingSenderId) {
  firebase.initializeApp(firebaseConfig);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const data = payload && payload.data ? payload.data : {};
    const title = data.title || "طلب توصيل جديد — أسواق الطيبات";
    const body = data.body || "تم إسناد طلب توصيل جديد إليك.";
    const url = data.url || "/rider";

    self.registration.showNotification(title, {
      body,
      tag: data.order_id ? "rider-order-" + data.order_id : "rider-order",
      renotify: true,
      data: { url },
    });
  });
} else {
  console.warn("Rider push is not configured: missing Firebase public web configuration.");
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const relative = event.notification && event.notification.data && event.notification.data.url
    ? event.notification.data.url
    : "/rider";
  const target = new URL(relative, self.location.origin).href;

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if (client.url.startsWith(self.location.origin) && "focus" in client) {
          if ("navigate" in client) client.navigate(target);
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(target);
      return undefined;
    }),
  );
});
`;

  return new Response(script, {
    headers: {
      "Content-Type": "application/javascript; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "Service-Worker-Allowed": "/",
    },
  });
}
