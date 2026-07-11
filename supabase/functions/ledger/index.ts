// Sky Warden — the pooled skill ledger (Supabase Edge Function)
//
// The companion to the weather proxy. Where that function pools upstream CALLS,
// this one pools the accuracy MOAT: each device scores every forecast source
// against the local thermometer and keeps a per-source mean-absolute-error on a
// ~55 km grid. Alone, that scoreboard is private and empty for every new user.
//
// Here, a device POSTs the DELTA of its observation-scored errors; the server
// sums it into a shared row (see ledger_add); and any device on that grid GETs
// the fleet's combined scoreboard, so a newcomer near a well-measured spot
// inherits proven weights instead of waiting a day to earn them.
//
// Privacy: the only thing stored is how wrong each source has been on a grid
// cell — a count and a summed error. No user, no device id, no coordinate finer
// than the grid, no per-observation timestamp.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APP_TOKEN = Deno.env.get("SKYWARDEN_APP_TOKEN") ?? "";
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const METRICS = new Set(["temp", "wind"]);
// Abuse guards. A single honest sync sends at most a day or two of hourly checks
// per (source, metric); anything wildly larger, or an impossible error, is a
// poisoning attempt and is dropped rather than summed into everyone's weights.
const MAX_COUNT_PER_ENTRY = 500;      // ~three weeks of hourly samples in one sync
const MAX_PLAUSIBLE_MAE = 200;        // °C or km/h — far past any real forecast miss
const MAX_ENTRIES = 64;               // 9 sources × 2 metrics, with headroom

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    // Same lightweight abuse gate as the weather proxy. (Harden with App Attest /
    // DeviceCheck for production — a leaked token still can't do more than skew
    // aggregate error stats, which the clamps above bound.)
    if (APP_TOKEN && req.headers.get("x-skywarden-app") !== APP_TOKEN) {
      return json({ error: "unauthorized" }, 401);
    }

    const url = new URL(req.url);

    // READ — the pooled scoreboard for one grid cell.
    if (req.method === "GET") {
      const grid = url.searchParams.get("grid");
      if (!grid) return json({ error: "grid required" }, 400);

      const { data, error } = await supabase
        .from("ledger")
        .select("source,metric,count,sum_abs_error")
        .eq("grid", grid);
      if (error) return json({ error: error.message }, 500);

      // Shape it as the client's own scoreboard: "source|metric" -> {count, sumAbsError}.
      const out: Record<string, { count: number; sumAbsError: number }> = {};
      for (const r of data ?? []) {
        out[`${r.source}|${r.metric}`] = { count: r.count, sumAbsError: r.sum_abs_error };
      }
      return json({ grid, stats: out });
    }

    // CONTRIBUTE — add this device's new samples to the pool.
    if (req.method === "POST") {
      const body = await req.json().catch(() => null);
      const grid = body?.grid;
      const entries = body?.entries;
      if (typeof grid !== "string" || !grid || !Array.isArray(entries)) {
        return json({ error: "grid and entries required" }, 400);
      }
      if (entries.length > MAX_ENTRIES) return json({ error: "too many entries" }, 400);

      // Validate and clamp every entry; silently drop the implausible ones rather
      // than rejecting the whole batch (one bad row shouldn't lose a day of honest
      // samples).
      const clean: { source: string; metric: string; count: number; sumAbsError: number }[] = [];
      for (const e of entries) {
        const source = typeof e?.source === "string" ? e.source : "";
        const metric = typeof e?.metric === "string" ? e.metric : "";
        const count = Number(e?.count);
        const sumAbsError = Number(e?.sumAbsError);
        if (!source || !METRICS.has(metric)) continue;
        if (!Number.isFinite(count) || count <= 0 || count > MAX_COUNT_PER_ENTRY) continue;
        if (!Number.isFinite(sumAbsError) || sumAbsError < 0) continue;
        if (sumAbsError / count > MAX_PLAUSIBLE_MAE) continue;   // impossible average miss
        clean.push({ source, metric, count: Math.round(count), sumAbsError });
      }
      if (clean.length === 0) return json({ ok: true, added: 0 });

      const { error } = await supabase.rpc("ledger_add", { p_grid: grid, p_entries: clean });
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true, added: clean.length });
    }

    return json({ error: "method not allowed" }, 405);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
