"use client";

import { useEffect, useState } from "react";

export default function DriverLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const [appUri, setAppUri] = useState<string | null>(null);

  useEffect(() => {
    const token = new URLSearchParams(window.location.search).get("token");
    if (!token || token.length < 32) return;

    const uri = `altayebat://driver?token=${encodeURIComponent(token)}`;
    setAppUri(uri);

    const isMobile =
      /Android|iPhone|iPad|iPod/i.test(window.navigator.userAgent);

    if (!isMobile) return;

    // Native app first on a phone. If it is not installed, the existing web
    // driver screen remains available as the fallback.
    const timer = window.setTimeout(() => {
      window.location.href = uri;
    }, 250);

    return () => window.clearTimeout(timer);
  }, []);

  return (
    <>
      {appUri ? (
        <div
          dir="rtl"
          style={{
            position: "sticky",
            top: 0,
            zIndex: 9999,
            padding: "10px 12px",
            background: "#ffffff",
            borderBottom: "1px solid #e5e7eb",
            textAlign: "center",
          }}
        >
          <a
            href={appUri}
            style={{
              display: "inline-block",
              padding: "10px 16px",
              borderRadius: 10,
              background: "#111827",
              color: "#ffffff",
              textDecoration: "none",
              fontWeight: 700,
            }}
          >
            فتح المهمة في تطبيق أسواق الطيبات
          </a>
        </div>
      ) : null}
      {children}
    </>
  );
}
