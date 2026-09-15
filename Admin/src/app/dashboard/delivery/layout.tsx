"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function DeliveryLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const assignmentRef = useRef<Map<string, string | null>>(new Map());
  const initializedRef = useRef(false);
  const sendingRef = useRef<Set<string>>(new Set());

  const dispatchPush = useCallback(
    async (orderId: string, driverId: string) => {
      const key = `${orderId}:${driverId}`;
      if (sendingRef.current.has(key)) return;
      sendingRef.current.add(key);
      try {
        const { error } = await supabase.functions.invoke("send-rider-push", {
          body: { order_id: orderId },
        });
        if (error) console.warn("rider push dispatch failed", error);
      } catch (error) {
        console.warn("rider push dispatch failed", error);
      } finally {
        window.setTimeout(() => sendingRef.current.delete(key), 5000);
      }
    },
    [supabase],
  );

  const refreshAssignments = useCallback(async () => {
    if (!storeId) return;
    const { data, error } = await supabase
      .from("orders")
      .select("id,driver_id")
      .eq("store_id", storeId)
      .in("status", ["pending", "preparing", "out_for_delivery"]);
    if (error) {
      console.warn("unable to refresh delivery assignments", error);
      return;
    }

    const next = new Map<string, string | null>();
    for (const raw of (data ?? []) as Array<Record<string, unknown>>) {
      const orderId = String(raw.id ?? "");
      if (!orderId) continue;
      const driverId = raw.driver_id ? String(raw.driver_id) : null;
      next.set(orderId, driverId);

      if (initializedRef.current) {
        const previousDriver = assignmentRef.current.get(orderId) ?? null;
        if (driverId && driverId !== previousDriver) {
          void dispatchPush(orderId, driverId);
        }
      }
    }

    assignmentRef.current = next;
    initializedRef.current = true;
  }, [dispatchPush, storeId, supabase]);

  useEffect(() => {
    void supabase.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const { data: membership, error } = await supabase
        .from("store_admins")
        .select("store_id")
        .eq("user_id", data.user.id)
        .maybeSingle();
      if (!error && membership?.store_id) {
        setStoreId(String(membership.store_id));
      }
    });
  }, [supabase]);

  useEffect(() => {
    if (!storeId) return;
    initializedRef.current = false;
    assignmentRef.current.clear();
    void refreshAssignments();

    const channel = supabase
      .channel(`rider-assignment-push-${storeId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "orders",
          filter: `store_id=eq.${storeId}`,
        },
        (payload) => {
          const row = payload.new as Record<string, unknown>;
          const orderId = row?.id ? String(row.id) : "";
          if (!orderId) return;
          const driverId = row.driver_id ? String(row.driver_id) : null;
          const previousDriver = assignmentRef.current.get(orderId) ?? null;
          assignmentRef.current.set(orderId, driverId);
          if (initializedRef.current && driverId && driverId !== previousDriver) {
            void dispatchPush(orderId, driverId);
          }
        },
      )
      .subscribe();

    // Realtime is the fast path. Polling is a fallback so a brief websocket
    // interruption cannot silently lose a rider assignment notification.
    const timer = window.setInterval(() => void refreshAssignments(), 15000);

    return () => {
      window.clearInterval(timer);
      void supabase.removeChannel(channel);
    };
  }, [dispatchPush, refreshAssignments, storeId, supabase]);

  return children;
}
