"use client";

import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

type Driver = {
  id: string;
  name: string;
  phone: string | null;
  is_active: boolean;
  active_orders: number;
};

type Order = {
  id: string;
  status: string;
  total: number | string;
  payment_method: string;
  payment_status: string;
  driver_id: string | null;
  address_snapshot: Record<string, unknown> | null;
  created_at: string | null;
};

type DriverLocation = {
  order_id: string;
  lat: number | string;
  lng: number | string;
  updated_at: string | null;
  recorded_at?: string | null;
};

function shortId(id: string) {
  return id.replaceAll("-", "").slice(0, 8).toUpperCase();
}

function money(value: number | string) {
  const numeric = Number(value);
  return `${Number.isFinite(numeric) ? numeric.toFixed(2) : "0.00"} Ø¯.Ø£`;
}

function statusLabel(value: string) {
  if (value === "pending") return "Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„ØªØ£ÙƒÙŠØ¯";
  if (value === "preparing") return "Ù‚ÙŠØ¯ Ø§Ù„ØªØ­Ø¶ÙŠØ±";
  if (value === "out_for_delivery") return "Ø¨Ø§Ù„ØªÙˆØµÙŠÙ„";
  return value;
}

function paymentLabel(method: string, status: string) {
  if (method === "cash") {
    return status === "paid" ? "ÙƒØ§Ø´ â€¢ ØªÙ… Ø§Ù„Ø¯ÙØ¹" : "ÙƒØ§Ø´ Ø¹Ù†Ø¯ Ø§Ù„Ø§Ø³ØªÙ„Ø§Ù…";
  }
  if (method === "cliq") {
    return status === "paid" ? "CliQ â€¢ Ù…Ø¯ÙÙˆØ¹" : "CliQ â€¢ Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„ØªØ£ÙƒÙŠØ¯";
  }
  return status === "paid" ? "Ø¨Ø·Ø§Ù‚Ø© â€¢ Ù…Ø¯ÙÙˆØ¹" : "Ø¨Ø·Ø§Ù‚Ø© â€¢ Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„ØªØ£ÙƒÙŠØ¯";
}

function mapUrl(location?: DriverLocation) {
  if (!location) return null;
  const lat = Number(location.lat);
  const lng = Number(location.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

function freshness(location?: DriverLocation) {
  if (!location) return "Ù„Ù… ÙŠØ¨Ø¯Ø£ GPS Ø¨Ø¹Ø¯";
  const raw = location.recorded_at || location.updated_at;
  if (!raw) return "ÙŠÙˆØ¬Ø¯ Ù…ÙˆÙ‚Ø¹ Ù…Ø³Ø¬Ù„";
  const seconds = Math.max(
    0,
    Math.floor((Date.now() - new Date(raw).getTime()) / 1000),
  );
  if (seconds < 30) return "Ù…Ø¨Ø§Ø´Ø± Ø§Ù„Ø¢Ù†";
  if (seconds < 60) return `Ù‚Ø¨Ù„ ${seconds} Ø«Ø§Ù†ÙŠØ©`;
  return `Ù‚Ø¨Ù„ ${Math.floor(seconds / 60)} Ø¯Ù‚ÙŠÙ‚Ø©`;
}

export default function DeliveryManagementPage() {
  const supabase = useMemo(() => createClient(), []);
  const [storeId, setStoreId] = useState<string | null>(null);
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [locations, setLocations] = useState<Record<string, DriverLocation>>({});
  const [selectedDrivers, setSelectedDrivers] = useState<Record<string, string>>({});
  const [generatedLinks, setGeneratedLinks] = useState<Record<string, string>>({});
  const [driverName, setDriverName] = useState("");
  const [driverPhone, setDriverPhone] = useState("");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setError(null);
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("ÙŠØ¬Ø¨ ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø£ÙˆÙ„Ø§Ù‹");

      const { data: adminLink, error: adminError } = await supabase
        .from("store_admins")
        .select("store_id")
        .eq("user_id", user.id)
        .maybeSingle();

      if (adminError) throw adminError;
      const currentStoreId = adminLink?.store_id?.toString();
      if (!currentStoreId) throw new Error("Ù„Ù… ÙŠØªÙ… Ø§Ù„Ø¹Ø«ÙˆØ± Ø¹Ù„Ù‰ Ù…ØªØ¬Ø± Ù…Ø±ØªØ¨Ø· Ø¨Ù‡Ø°Ø§ Ø§Ù„Ø­Ø³Ø§Ø¨");
      setStoreId(currentStoreId);

      const [{ data: driverRows, error: driversError }, { data: orderRows, error: ordersError }] =
        await Promise.all([
          supabase.rpc("admin_list_delivery_drivers", {
            p_store_id: currentStoreId,
          }),
          supabase
            .from("orders")
            .select(
              "id,status,total,payment_method,payment_status,driver_id,address_snapshot,created_at",
            )
            .eq("store_id", currentStoreId)
            .in("status", ["pending", "preparing", "out_for_delivery"])
            .order("created_at", { ascending: true }),
        ]);

      if (driversError) throw driversError;
      if (ordersError) throw ordersError;

      const normalizedDrivers = ((driverRows ?? []) as Array<Record<string, unknown>>).map(
        (row) => ({
          id: String(row.id),
          name: String(row.name ?? ""),
          phone: row.phone ? String(row.phone) : null,
          is_active: Boolean(row.is_active),
          active_orders: Number(row.active_orders ?? 0),
        }),
      );
      const normalizedOrders = ((orderRows ?? []) as Array<Record<string, unknown>>).map(
        (row) => ({
          id: String(row.id),
          status: String(row.status ?? "pending"),
          total: (row.total as number | string) ?? 0,
          payment_method: String(row.payment_method ?? "cash"),
          payment_status: String(row.payment_status ?? "unpaid"),
          driver_id: row.driver_id ? String(row.driver_id) : null,
          address_snapshot:
            row.address_snapshot && typeof row.address_snapshot === "object"
              ? (row.address_snapshot as Record<string, unknown>)
              : null,
          created_at: row.created_at ? String(row.created_at) : null,
        }),
      );

      setDrivers(normalizedDrivers);
      setOrders(normalizedOrders);
      setSelectedDrivers((current) => {
        const next = { ...current };
        for (const order of normalizedOrders) {
          if (!next[order.id] && order.driver_id) next[order.id] = order.driver_id;
        }
        return next;
      });

      const orderIds = normalizedOrders.map((order) => order.id);
      if (orderIds.length > 0) {
        const { data: locationRows, error: locationError } = await supabase
          .from("driver_locations")
          .select("order_id,lat,lng,updated_at,recorded_at")
          .in("order_id", orderIds);
        if (locationError) throw locationError;

        const nextLocations: Record<string, DriverLocation> = {};
        for (const row of (locationRows ?? []) as Array<Record<string, unknown>>) {
          const orderId = String(row.order_id ?? "");
          if (!orderId) continue;
          nextLocations[orderId] = {
            order_id: orderId,
            lat: row.lat as number | string,
            lng: row.lng as number | string,
            updated_at: row.updated_at ? String(row.updated_at) : null,
            recorded_at: row.recorded_at ? String(row.recorded_at) : null,
          };
        }
        setLocations(nextLocations);
      } else {
        setLocations({});
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„ØªÙˆØµÙŠÙ„");
    } finally {
      setLoading(false);
    }
  }, [supabase]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (!storeId) return;

    const channel = supabase
      .channel(`admin-delivery-${storeId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "orders",
          filter: `store_id=eq.${storeId}`,
        },
        () => void load(),
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "driver_locations" },
        () => void load(),
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [load, storeId, supabase]);

  async function createDriver(event: FormEvent) {
    event.preventDefault();
    if (!storeId || !driverName.trim()) return;
    setBusy("create-driver");
    setError(null);
    setSuccess(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_create_delivery_driver", {
        p_store_id: storeId,
        p_name: driverName.trim(),
        p_phone: driverPhone.trim() || null,
      });
      if (rpcError) throw rpcError;
      setDriverName("");
      setDriverPhone("");
      setSuccess("ØªÙ…Øª Ø¥Ø¶Ø§ÙØ© Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨");
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "ØªØ¹Ø°Ø± Ø¥Ø¶Ø§ÙØ© Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨");
    } finally {
      setBusy(null);
    }
  }

  async function createTrackingLink(order: Order) {
    const driverId = selectedDrivers[order.id] || order.driver_id;
    if (!driverId) {
      setError("Ø§Ø®ØªØ± Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ Ø£ÙˆÙ„Ø§Ù‹");
      return;
    }
    if (order.status === "pending") {
      setError("Ø­ÙˆÙ‘Ù„ Ø­Ø§Ù„Ø© Ø§Ù„Ø·Ù„Ø¨ Ø¥Ù„Ù‰ Ù‚ÙŠØ¯ Ø§Ù„ØªØ­Ø¶ÙŠØ± Ù‚Ø¨Ù„ Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø·Ù„Ø¨ Ù„Ù„Ù…Ù†Ø¯ÙˆØ¨");
      return;
    }

    setBusy(order.id);
    setError(null);
    setSuccess(null);
    try {
      const { error: assignError } = await supabase.rpc(
        "admin_assign_delivery_driver",
        { p_order_id: order.id, p_driver_id: driverId },
      );
      if (assignError) throw assignError;

      const { data, error: issueError } = await supabase.rpc(
        "admin_issue_driver_tracking_session",
        { p_order_id: order.id, p_driver_id: driverId },
      );
      if (issueError) throw issueError;

      const token = (data as Record<string, unknown> | null)?.token?.toString();
      if (!token) throw new Error("ØªØ¹Ø°Ø± Ø¥Ù†Ø´Ø§Ø¡ Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨");

      const link = `altayebat://driver?token=${encodeURIComponent(token)}`;
      setGeneratedLinks((current) => ({ ...current, [order.id]: link }));
      setSuccess(`ØªÙ… ØªØ¬Ù‡ÙŠØ² Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ Ù„Ù„Ø·Ù„Ø¨ #${shortId(order.id)}`);
      await load();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "ØªØ¹Ø°Ø± ØªØ¬Ù‡ÙŠØ² Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨");
    } finally {
      setBusy(null);
    }
  }

  async function shareLink(orderId: string) {
    const link = generatedLinks[orderId];
    if (!link) return;
    try {
      if (navigator.share) {
        await navigator.share({
          title: "Ø±Ø§Ø¨Ø· ØªÙˆØµÙŠÙ„ Ø£Ø³ÙˆØ§Ù‚ Ø§Ù„Ø·ÙŠØ¨Ø§Øª",
          text: `Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ Ù„Ù„Ø·Ù„Ø¨ #${shortId(orderId)}`,
          url: link,
        });
      } else {
        await navigator.clipboard.writeText(link);
        setSuccess("ØªÙ… Ù†Ø³Ø® Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨");
      }
    } catch {
      // Closing the native share sheet is not an application error.
    }
  }

  async function revokeTracking(orderId: string) {
    setBusy(`revoke-${orderId}`);
    setError(null);
    try {
      const { error: rpcError } = await supabase.rpc("admin_revoke_driver_tracking", {
        p_order_id: orderId,
      });
      if (rpcError) throw rpcError;
      setGeneratedLinks((current) => {
        const next = { ...current };
        delete next[orderId];
        return next;
      });
      setSuccess("ØªÙ… Ø¥ÙŠÙ‚Ø§Ù Ø±Ø§Ø¨Ø· Ø§Ù„ØªØªØ¨Ø¹");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "ØªØ¹Ø°Ø± Ø¥ÙŠÙ‚Ø§Ù Ø§Ù„ØªØªØ¨Ø¹");
    } finally {
      setBusy(null);
    }
  }

  if (loading) {
    return <div className="p-6 text-sm text-gray-500">Ø¬Ø§Ø±ÙŠ ØªØ­Ù…ÙŠÙ„ Ø§Ù„ØªÙˆØµÙŠÙ„...</div>;
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6 p-4 sm:p-6" dir="rtl">
      <div>
        <h1 className="text-2xl font-bold text-gray-950">Ø¥Ø¯Ø§Ø±Ø© Ø§Ù„ØªÙˆØµÙŠÙ„ Ø§Ù„Ù…Ø¨Ø§Ø´Ø±</h1>
        <p className="mt-1 text-sm text-gray-500">
          Ø¹ÙŠÙ‘Ù† Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ØŒ Ø£Ø±Ø³Ù„ Ù„Ù‡ Ø±Ø§Ø¨Ø·Ù‹Ø§ Ø¢Ù…Ù†Ù‹Ø§ØŒ ÙˆÙŠØ´Ø§Ù‡Ø¯ Ø§Ù„Ø²Ø¨ÙˆÙ† Ù…ÙˆÙ‚Ø¹Ù‡ Ù…Ø¨Ø§Ø´Ø±Ø© Ø¯Ø§Ø®Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚.
        </p>
      </div>

      {error && <div className="rounded-xl bg-red-50 px-4 py-3 text-sm text-red-700">{error}</div>}
      {success && <div className="rounded-xl bg-green-50 px-4 py-3 text-sm text-green-700">{success}</div>}

      <section className="grid gap-3 md:grid-cols-3">
        {[
          ["1", "Ø¬Ù‡Ù‘Ø² Ø§Ù„Ø·Ù„Ø¨", "Ø­ÙˆÙ‘Ù„ Ø§Ù„Ø·Ù„Ø¨ Ø¥Ù„Ù‰ Ù‚ÙŠØ¯ Ø§Ù„ØªØ­Ø¶ÙŠØ± Ù…Ù† ØµÙØ­Ø© Ø§Ù„Ø·Ù„Ø¨Ø§Øª."],
          ["2", "Ø¹ÙŠÙ‘Ù† Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨", "Ø§Ø®ØªØ± Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ ÙˆØ£Ù†Ø´Ø¦ Ø±Ø§Ø¨Ø· Ø§Ù„ØªÙˆØµÙŠÙ„."],
          ["3", "ØªØªØ¨Ø¹ Ù…Ø¨Ø§Ø´Ø±", "Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ ÙŠØ¶ØºØ· Ø¨Ø¯Ø¡ Ø§Ù„ØªÙˆØµÙŠÙ„ ÙˆÙŠØ¨Ø¯Ø£ GPS ØªÙ„Ù‚Ø§Ø¦ÙŠÙ‹Ø§."],
        ].map(([number, title, body]) => (
          <div key={number} className="rounded-2xl border bg-white p-4 shadow-sm">
            <div className="mb-2 flex h-8 w-8 items-center justify-center rounded-full bg-red-50 font-bold text-red-600">
              {number}
            </div>
            <div className="font-bold text-gray-900">{title}</div>
            <div className="mt-1 text-sm leading-6 text-gray-500">{body}</div>
          </div>
        ))}
      </section>

      <section className="rounded-2xl border bg-white p-4 shadow-sm sm:p-5">
        <h2 className="font-bold text-gray-950">Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨ÙˆÙ†</h2>
        <form onSubmit={createDriver} className="mt-4 grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
          <input
            value={driverName}
            onChange={(event) => setDriverName(event.target.value)}
            placeholder="Ø§Ø³Ù… Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨"
            className="rounded-xl border px-3 py-2.5 text-sm outline-none focus:border-red-500"
            required
          />
          <input
            value={driverPhone}
            onChange={(event) => setDriverPhone(event.target.value)}
            placeholder="Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ (Ø§Ø®ØªÙŠØ§Ø±ÙŠ)"
            className="rounded-xl border px-3 py-2.5 text-sm outline-none focus:border-red-500"
          />
          <button
            type="submit"
            disabled={busy === "create-driver"}
            className="rounded-xl bg-gray-950 px-5 py-2.5 text-sm font-bold text-white disabled:opacity-50"
          >
            {busy === "create-driver" ? "Ø¬Ø§Ø±ÙŠ Ø§Ù„Ø¥Ø¶Ø§ÙØ©..." : "Ø¥Ø¶Ø§ÙØ© Ù…Ù†Ø¯ÙˆØ¨"}
          </button>
        </form>

        <div className="mt-4 flex flex-wrap gap-2">
          {drivers.length === 0 ? (
            <span className="text-sm text-gray-500">Ø£Ø¶Ù Ø£ÙˆÙ„ Ù…Ù†Ø¯ÙˆØ¨ Ù„Ù„Ø¨Ø¯Ø¡.</span>
          ) : (
            drivers.map((driver) => (
              <span key={driver.id} className="rounded-full border bg-gray-50 px-3 py-1.5 text-xs text-gray-700">
                {driver.name}{driver.phone ? ` â€¢ ${driver.phone}` : ""}
                {driver.active_orders > 0 ? ` â€¢ ${driver.active_orders} Ø·Ù„Ø¨` : ""}
              </span>
            ))
          )}
        </div>
      </section>

      <section className="space-y-3">
        <div className="flex items-end justify-between gap-3">
          <div>
            <h2 className="font-bold text-gray-950">Ø·Ù„Ø¨Ø§Øª Ø§Ù„ØªÙˆØµÙŠÙ„ Ø§Ù„Ø­Ø§Ù„ÙŠØ©</h2>
            <p className="text-xs text-gray-500">Ø§Ù„Ù…ÙˆÙ‚Ø¹ ÙŠØªØ­Ø¯Ø« ØªÙ„Ù‚Ø§Ø¦ÙŠÙ‹Ø§ Ø¹Ù†Ø¯ ÙˆØµÙˆÙ„ GPS Ù…Ù† Ø¬Ù‡Ø§Ø² Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨.</p>
          </div>
          <Link href="/dashboard" className="text-sm font-semibold text-red-600 hover:underline">
            ÙƒÙ„ Ø§Ù„Ø·Ù„Ø¨Ø§Øª
          </Link>
        </div>

        {orders.length === 0 ? (
          <div className="rounded-2xl border border-dashed bg-white p-8 text-center text-sm text-gray-500">
            Ù„Ø§ ØªÙˆØ¬Ø¯ Ø·Ù„Ø¨Ø§Øª Ù†Ø´Ø·Ø© Ø§Ù„Ø¢Ù†.
          </div>
        ) : (
          orders.map((order) => {
            const location = locations[order.id];
            const currentMapUrl = mapUrl(location);
            const addressText = order.address_snapshot?.address_text?.toString() || "Ø§Ù„Ø¹Ù†ÙˆØ§Ù† ØºÙŠØ± Ù…ÙƒØªÙ…Ù„";
            const generatedLink = generatedLinks[order.id];
            const currentDriver = selectedDrivers[order.id] || order.driver_id || "";
            const canIssue = order.status !== "pending" && drivers.some((driver) => driver.is_active);

            return (
              <article key={order.id} className="rounded-2xl border bg-white p-4 shadow-sm sm:p-5">
                <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <Link href={`/dashboard/orders/${order.id}`} className="font-black text-gray-950 hover:text-red-600">
                        Ø·Ù„Ø¨ #{shortId(order.id)}
                      </Link>
                      <span className="rounded-full bg-gray-100 px-2.5 py-1 text-xs font-semibold text-gray-700">
                        {statusLabel(order.status)}
                      </span>
                      {order.status === "out_for_delivery" && (
                        <span className="rounded-full bg-green-50 px-2.5 py-1 text-xs font-semibold text-green-700">
                          GPS: {freshness(location)}
                        </span>
                      )}
                    </div>
                    <div className="mt-2 text-sm text-gray-600">{addressText}</div>
                    <div className="mt-1 text-xs text-gray-500">
                      {money(order.total)} â€¢ {paymentLabel(order.payment_method, order.payment_status)}
                    </div>
                  </div>

                  <div className="grid gap-2 sm:min-w-[360px] sm:grid-cols-[1fr_auto]">
                    <select
                      value={currentDriver}
                      onChange={(event) =>
                        setSelectedDrivers((current) => ({
                          ...current,
                          [order.id]: event.target.value,
                        }))
                      }
                      className="rounded-xl border px-3 py-2.5 text-sm"
                    >
                      <option value="">Ø§Ø®ØªØ± Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨</option>
                      {drivers
                        .filter((driver) => driver.is_active)
                        .map((driver) => (
                          <option key={driver.id} value={driver.id}>
                            {driver.name}
                          </option>
                        ))}
                    </select>
                    <button
                      type="button"
                      disabled={!canIssue || busy === order.id}
                      onClick={() => void createTrackingLink(order)}
                      className="rounded-xl bg-red-600 px-4 py-2.5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {busy === order.id ? "Ø¬Ø§Ø±ÙŠ Ø§Ù„ØªØ¬Ù‡ÙŠØ²..." : generatedLink ? "ØªØ¯ÙˆÙŠØ± Ø§Ù„Ø±Ø§Ø¨Ø·" : "Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨"}
                    </button>
                  </div>
                </div>

                {order.status === "pending" && (
                  <div className="mt-4 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-800">
                    Ø§Ù„Ø±Ø§Ø¨Ø· ÙŠØµØ¨Ø­ Ù…ØªØ§Ø­Ù‹Ø§ Ø¨Ø¹Ø¯ ØªØ­ÙˆÙŠÙ„ Ø­Ø§Ù„Ø© Ø§Ù„Ø·Ù„Ø¨ Ø¥Ù„Ù‰ <b>Ù‚ÙŠØ¯ Ø§Ù„ØªØ­Ø¶ÙŠØ±</b>.
                  </div>
                )}

                {generatedLink && (
                  <div className="mt-4 rounded-xl border border-red-100 bg-red-50/50 p-3">
                    <div className="text-xs font-bold text-red-700">Ø±Ø§Ø¨Ø· Ø®Ø§Øµ Ø¨Ù‡Ø°Ø§ Ø§Ù„Ø·Ù„Ø¨ â€” ØµØ§Ù„Ø­ Ù„Ù…Ø¯Ø© 18 Ø³Ø§Ø¹Ø©</div>
                    <div className="mt-2 break-all rounded-lg bg-white px-3 py-2 text-xs text-gray-600">{generatedLink}</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => void shareLink(order.id)}
                        className="rounded-lg bg-gray-950 px-3 py-2 text-xs font-bold text-white"
                      >
                        Ù…Ø´Ø§Ø±ÙƒØ© / Ù†Ø³Ø®
                      </button>
                      <button
                        type="button"
                        onClick={() => void revokeTracking(order.id)}
                        disabled={busy === `revoke-${order.id}`}
                        className="rounded-lg border border-red-200 px-3 py-2 text-xs font-bold text-red-700"
                      >
                        Ø¥ÙŠÙ‚Ø§Ù Ø§Ù„Ø±Ø§Ø¨Ø·
                      </button>
                    </div>
                  </div>
                )}

                {location && (
                  <div className="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-xl bg-green-50 px-3 py-3 text-sm text-green-800">
                    <span className="font-semibold">Ø¢Ø®Ø± Ù…ÙˆÙ‚Ø¹: {freshness(location)}</span>
                    {currentMapUrl && (
                      <a href={currentMapUrl} target="_blank" rel="noreferrer" className="font-bold underline">
                        ÙØªØ­ Ù…ÙˆÙ‚Ø¹ Ø§Ù„Ù…Ù†Ø¯ÙˆØ¨
                      </a>
                    )}
                  </div>
                )}
              </article>
            );
          })
        )}
      </section>
    </div>
  );
}


