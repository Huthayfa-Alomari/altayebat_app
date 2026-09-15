"use client";

import { useCallback, useEffect, useMemo, useRef } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  riderPushConfigured,
  syncRiderPushIfGranted,
} from "@/lib/rider-push";

export default function RiderLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const supabase = useMemo(() => createClient(), []);
  const readyRef = useRef(false);
  const inFlightRef = useRef(false);

  const syncPush = useCallback(async () => {
    if (readyRef.current || inFlightRef.current || !riderPushConfigured()) return;
    if (typeof window === "undefined" || !("Notification" in window)) return;
    if (window.Notification.permission !== "granted") return;

    inFlightRef.current = true;
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) return;

      const { data: rider, error: riderError } = await supabase.rpc("rider_me");
      if (riderError || !rider || typeof rider !== "object") return;
      const row = rider as Record<string, unknown>;
      if (row.approval_status !== "approved" || !Boolean(row.is_active)) return;

      const result = await syncRiderPushIfGranted(supabase);
      if (result.status === "ready") readyRef.current = true;
    } catch (error) {
      console.warn("rider background push registration failed", error);
    } finally {
      inFlightRef.current = false;
    }
  }, [supabase]);

  useEffect(() => {
    void syncPush();

    // The rider page already owns the permission button. This short watcher
    // upgrades a granted browser permission into a real FCM Web Push token,
    // including when permission was granted after this layout mounted.
    const timer = window.setInterval(() => void syncPush(), 5000);
    const onVisible = () => {
      if (document.visibilityState === "visible") void syncPush();
    };
    document.addEventListener("visibilitychange", onVisible);

    const { data: authListener } = supabase.auth.onAuthStateChange(() => {
      readyRef.current = false;
      window.setTimeout(() => void syncPush(), 0);
    });

    return () => {
      window.clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
      authListener.subscription.unsubscribe();
    };
  }, [supabase, syncPush]);

  return children;
}
