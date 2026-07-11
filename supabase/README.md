# Sky Warden — central data proxy (Supabase)

Holds the weather API keys **server-side** and caches responses per location-grid
so users don't share/drain one quota. Apple WeatherKit stays native on-device and
is **not** proxied. The client falls back to direct provider calls when
`PROXY_BASE_URL` is unset, so the app runs before this is deployed.

```
device ─► WeatherKit (native, on-device)
device ─► /functions/v1/weather?source=… ─► Open-Meteo · OpenWeather · WorldTides · GNews
             (keys here, cached per grid+TTL)
device ─► /functions/v1/ledger            ─► pooled accuracy scoreboard
             (each device contributes its per-source error deltas; any device on
              the same ~55 km grid reads the fleet's combined skill — see below)
```

## One-time setup

The whole thing is scripted. You only do the two steps that need *your* login:

```sh
# 1. Sign in (opens a browser — only you can do this)
supabase login

# 2. Deploy everything: link, push the schema, set secrets from Config.xcconfig,
#    deploy the function, and print the two values to paste back.
bash supabase/deploy.sh <your-project-ref>
```

Your project ref is the code in the dashboard URL:
`https://supabase.com/dashboard/project/<ref>`. It is not a secret. The script
reads the provider keys from your gitignored `Config.xcconfig` and sets them as
server-side secrets, so they never pass through anything but your own machine
and Supabase. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the
platform automatically.

<details><summary>What the script runs, if you'd rather do it by hand</summary>

```sh
supabase link --project-ref <ref>
supabase db push                       # applies migrations 0001 (cache) + 0002 (ledger)
supabase secrets set WORLDTIDES_API_KEY=… OPENWEATHER_API_KEY=… \
  GNEWS_API_KEY=… SKYWARDEN_APP_TOKEN=<long-random-string>
supabase functions deploy weather --no-verify-jwt
supabase functions deploy ledger  --no-verify-jwt
```

`db push` needs the database password (a token-only login doesn't have it). If you
don't want to enter it, paste `migrations/0001_weather_cache.sql` then
`0002_ledger.sql` into the dashboard SQL editor instead — the functions work the
moment their table exists, and the app falls back to per-device accuracy until the
ledger table is there, so nothing breaks if you defer 0002.
</details>

## Point the app at it

The deploy prints a URL like `https://<ref>.supabase.co/functions/v1/weather`.
Put it (and the same app token) in `Config.xcconfig`:

```
PROXY_BASE_URL   = https:/$()/<ref>.supabase.co/functions/v1/weather
PROXY_APP_TOKEN  = <the same long random string>
```

⚠️ The `$()` is **required**. xcconfig treats `//` as a comment, so a raw
`https://…` silently truncates to `https:` and every proxied call fails with
"could not connect". The empty `$()` breaks the `//` and expands back to `https://`
at build time. The app derives the ledger endpoint from this same base (it swaps
the trailing `/weather` for `/ledger`), so you only set the one URL.

Then rebuild. Once this is set, the app routes Open-Meteo / OpenWeather /
WorldTides / GNews through the proxy — **remove those provider keys from
`Config.xcconfig`**, since the client no longer needs them.

## Verify

```sh
curl -s "https://<ref>.supabase.co/functions/v1/weather?source=worldtides&lat=-27.87&lon=153.35&heights&extremes&days=2&datum=LAT" \
  -H "x-skywarden-app: <token>" -i | grep -i x-cache   # MISS first call, HIT within 6h
```

## Notes & next steps
- **Abuse hardening:** the app token is a deterrent, not a wall (it still ships in
  the binary, rotatable). For production, gate with **App Attest / DeviceCheck**.
- **Licensing:** Open-Meteo's free tier is non-commercial — move to their
  commercial plan (keys still live only here) before a paid launch.
- **Reuse:** this same project also hosts the pooled accuracy ledger (below).
  People's Weather votes will live here too (a later phase) — one backend.

## The pooled ledger (`/functions/v1/ledger`)

The accuracy moat scores each source against the local thermometer and keeps a
per-source mean-absolute-error on a ~55 km grid. On its own that scoreboard is
private to one device and empty for every new user. The ledger pools it:

- **Contribute** — `POST { grid, entries:[{source, metric, count, sumAbsError}] }`.
  The device sends only the *delta* since its last successful send; the server sums
  it into a shared row via the `ledger_add` RPC. Because `SkillStat` is a
  commutative monoid (counts and errors just add), the pooled row equals what one
  device would hold had it made every observation — so pooling weakens none of the
  moat's invariants (min-samples, the 2× weight cap, "truth is an observation").
- **Read** — `GET ?grid=…` → `{ grid, stats:{ "source|metric": {count, sumAbsError} } }`.
  On refresh the app blends this with its own not-yet-sent samples, so a new user
  near a well-measured grid inherits proven weights on their first refresh.

**Privacy:** the only thing stored is how wrong each source has been on a grid cell
— a count and a summed error. No user, no device id, no coordinate finer than the
grid, no per-observation timestamp. It is aggregate accuracy, not location history.

**Abuse:** the same app-token gate as the proxy, plus per-entry clamps (max samples
per sync, max plausible MAE, allowlisted metrics) so a leaked token can at worst
nudge aggregate error stats within bounds. App Attest / DeviceCheck is the real fix.

Verify once deployed (contribute, then read it back):
```sh
L="https://<ref>.supabase.co/functions/v1/ledger"; H="x-skywarden-app: <token>"
curl -s -X POST "$L" -H "$H" -H 'content-type: application/json' \
  -d '{"grid":"demo","entries":[{"source":"ecmwf","metric":"temp","count":25,"sumAbsError":30}]}'
curl -s "$L?grid=demo" -H "$H"      # → {"grid":"demo","stats":{"ecmwf|temp":{"count":25,"sumAbsError":30}}}
```
