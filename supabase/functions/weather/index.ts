// Sky Warden — central weather proxy (Supabase Edge Function)
//
// Why this exists: without it, every device calls every provider directly using
// the SAME API keys baked into the app — so all users share one quota and drain
// it (WorldTides is only ~1,000 req/month), and the keys are extractable from the
// binary. This function holds the keys server-side and caches responses per
// location-grid + time window, so thousands of users near one spot collapse into
// a handful of upstream calls instead of thousands.
//
// It is a deliberately thin, allowlisted key-injecting forwarder: the client
// sends each provider's own query params (minus the key); we grid-bucket the
// location, serve from cache if fresh, else fetch upstream with the server-side
// key and cache the raw response. The client's existing parsers are unchanged.
//
// NOTE: Apple WeatherKit stays NATIVE on the device (it has a huge included quota
// tied to the app's own entitlement) — it is intentionally not proxied here.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface Provider { base: string; keyParam?: string; keyEnv?: string; ttl: number }

// Allowlist — we only ever forward to these known bases.
const PROVIDERS: Record<string, Provider> = {
  openmeteo:   { base: "https://api.open-meteo.com/v1/forecast",           ttl: 900 },      // 15 min
  archive:     { base: "https://archive-api.open-meteo.com/v1/archive",    ttl: 2_592_000 },// 30 d (immutable history)
  openweather: { base: "https://api.openweathermap.org/data/3.0/onecall",  keyParam: "appid",  keyEnv: "OPENWEATHER_API_KEY", ttl: 900 },
  worldtides:  { base: "https://www.worldtides.info/api/v3",               keyParam: "key",    keyEnv: "WORLDTIDES_API_KEY",  ttl: 21_600 },   // 6 h (tides are deterministic)
  gnews:       { base: "https://gnews.io/api/v4/search",                   keyParam: "apikey", keyEnv: "GNEWS_API_KEY",       ttl: 1_800 },    // 30 min
};

const APP_TOKEN = Deno.env.get("SKYWARDEN_APP_TOKEN") ?? "";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ~0.05° ≈ 5.5 km buckets — the single biggest lever for collapsing duplicate calls.
const grid = (v: number) => (Math.round(v / 0.05) * 0.05).toFixed(2);

function json(body: unknown, status = 200, cache?: string): Response {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (cache) headers["x-cache"] = cache;
  return new Response(JSON.stringify(body), { status, headers });
}

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const source = url.searchParams.get("source") ?? "";
    const prov = PROVIDERS[source];
    if (!prov) return json({ error: "unknown source" }, 400);

    // Lightweight abuse guard so randoms can't drain the credits either.
    // (Harden with App Attest / DeviceCheck for production — see README.)
    if (APP_TOKEN && req.headers.get("x-skywarden-app") !== APP_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }

    const lat = url.searchParams.get("latitude") ?? url.searchParams.get("lat");
    const lon = url.searchParams.get("longitude") ?? url.searchParams.get("lon");
    if (lat === null || lon === null) return json({ error: "lat/lon required" }, 400);

    // Cache key = source + grid cell + the params that actually change the result.
    const extra = ["days", "start_date", "end_date", "q"]
      .map((k) => url.searchParams.get(k)).filter(Boolean).join("|");
    const key = `${source}:${grid(+lat)},${grid(+lon)}:${extra}`;

    const { data: hit } = await supabase
      .from("cache").select("payload,expires_at").eq("key", key).maybeSingle();
    if (hit && new Date(hit.expires_at) > new Date()) {
      return json(hit.payload, 200, "HIT");
    }

    // Build the upstream request: forward the client's params, inject the key.
    const up = new URL(prov.base);
    for (const [k, v] of url.searchParams) if (k !== "source") up.searchParams.set(k, v);
    if (prov.keyParam && prov.keyEnv) up.searchParams.set(prov.keyParam, Deno.env.get(prov.keyEnv) ?? "");

    const res = await fetch(up.toString());
    const body = await res.json().catch(() => null);
    if (!res.ok || body === null) return json({ error: "upstream failed", status: res.status }, 502);

    const expires_at = new Date(Date.now() + prov.ttl * 1000).toISOString();
    await supabase.from("cache").upsert({ key, payload: body, expires_at, updated_at: new Date().toISOString() });

    return json(body, 200, "MISS");
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
